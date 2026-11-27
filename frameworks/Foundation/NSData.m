#import "FoundationInternal.h"
#include <fcntl.h>
#include <sys/stat.h>

static inline CFDataRef CFDT(NSData *d) { return (__bridge CFDataRef)d; }
static inline CFMutableDataRef CFMDT(NSData *d) { return (__bridge CFMutableDataRef)d; }
static BOOL wants_mutable(id self) { return [self isKindOfClass:[NSMutableData class]]; }

static id make_data(id self, const void *bytes, NSUInteger length) {
    if (wants_mutable(self)) {
        CFMutableDataRef m = CFDataCreateMutable(NULL, 0);
        if (length) CFDataAppendBytes(m, bytes, (CFIndex)length);
        return (__bridge_transfer id)m;
    }
    return (__bridge_transfer id)CFDataCreate(NULL, bytes, (CFIndex)length);
}

CFDataRef bitten_cf_data_create_no_copy(CFAllocatorRef allocator, const uint8_t *bytes, CFIndex length,
                                        void (*release)(void *, void *, CFIndex), void *context);

static void run_deallocator(void *context, void *bytes, CFIndex length) {
    void (^deallocator)(void *, NSUInteger) = (__bridge_transfer id)context;
    deallocator(bytes, (NSUInteger)length);
}

/* NSMutableData copies the bytes and gives the caller's buffer back at once, so it can grow. */
static id make_no_copy(id self, void *bytes, NSUInteger length, void (^deallocator)(void *, NSUInteger)) {
    if (wants_mutable(self)) {
        id data = make_data(self, bytes, length);
        if (deallocator) deallocator(bytes, length);
        return data;
    }
    if (!deallocator) return (__bridge_transfer id)CFDataCreateWithBytesNoCopy(NULL, bytes, (CFIndex)length, kCFAllocatorNull);
    return (__bridge_transfer id)bitten_cf_data_create_no_copy(NULL, bytes, (CFIndex)length, run_deallocator,
                                                               (__bridge_retained void *)[deallocator copy]);
}

static void (^const free_bytes)(void *, NSUInteger) = ^(void *bytes, NSUInteger length) { free(bytes); };

/* Read a whole file; returns malloc'd bytes or NULL with errno set. */
void *BNReadFile(const char *path, size_t *length) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return NULL;
    size_t cap = 65536, len = 0;
    struct stat st;
    if (fstat(fd, &st) == 0 && st.st_size > 0) cap = (size_t)st.st_size + 1;
    char *buf = malloc(cap);
    for (;;) {
        if (len == cap) buf = realloc(buf, cap *= 2);
        ssize_t n = read(fd, buf + len, cap - len);
        if (n < 0) {
            int e = errno;
            free(buf);
            close(fd);
            errno = e;
            return NULL;
        }
        if (n == 0) break;
        len += (size_t)n;
    }
    close(fd);
    *length = len;
    return buf;
}

BOOL BNWriteFile(const char *path, const void *bytes, size_t length, BOOL atomically) {
    char tmp[1100];
    const char *target = path;
    if (atomically) {
        snprintf(tmp, sizeof tmp, "%s.bitten-tmp-%d", path, getpid());
        target = tmp;
    }
    int fd = open(target, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) return NO;
    size_t done = 0;
    while (done < length) {
        ssize_t n = write(fd, (const char *)bytes + done, length - done);
        if (n < 0) {
            int e = errno;
            close(fd);
            unlink(target);
            errno = e;
            return NO;
        }
        done += (size_t)n;
    }
    close(fd);
    if (atomically && rename(tmp, path) != 0) {
        int e = errno;
        unlink(tmp);
        errno = e;
        return NO;
    }
    return YES;
}

static const char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

@implementation NSData (Foundation)
+ (instancetype)data { return [[self alloc] init]; }
+ (instancetype)dataWithBytes:(const void *)bytes length:(NSUInteger)length { return [[self alloc] initWithBytes:bytes length:length]; }
+ (instancetype)dataWithData:(NSData *)data { return [[self alloc] initWithData:data]; }
+ (instancetype)dataWithContentsOfFile:(NSString *)path { return [[self alloc] initWithContentsOfFile:path]; }
- (instancetype)init { return make_data(self, NULL, 0); }
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length { return make_data(self, bytes, length); }
+ (instancetype)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length { return [[self alloc] initWithBytesNoCopy:bytes length:length]; }
+ (instancetype)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b {
    return [[self alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:b];
}
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length { return make_no_copy(self, bytes, length, free_bytes); }
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b {
    return make_no_copy(self, bytes, length, b ? free_bytes : (void (^)(void *, NSUInteger))nil);
}
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length deallocator:(void (^)(void *, NSUInteger))deallocator {
    return make_no_copy(self, bytes, length, deallocator);
}
- (instancetype)initWithData:(NSData *)data { return make_data(self, data.bytes, data.length); }
- (instancetype)initWithContentsOfFile:(NSString *)path {
    size_t length = 0;
    void *bytes = path ? BNReadFile(path.fileSystemRepresentation, &length) : NULL;
    if (!bytes) return nil;
    id result = make_data(self, bytes, length);
    free(bytes);
    return result;
}
+ (instancetype)dataWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)options error:(NSError **)error {
    return [[self alloc] initWithContentsOfFile:path options:options error:error];
}
+ (instancetype)dataWithContentsOfURL:(NSURL *)url { return [[self alloc] initWithContentsOfURL:url]; }
+ (instancetype)dataWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)options error:(NSError **)error {
    return [[self alloc] initWithContentsOfURL:url options:options error:error];
}
- (instancetype)initWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)options error:(NSError **)error {
    size_t length = 0;
    void *bytes = path ? BNReadFile(path.fileSystemRepresentation, &length) : NULL;
    if (!bytes) {
        if (!path) errno = ENOENT;
        BNSetPOSIXError(error, path, YES);
        return nil;
    }
    id result = make_data(self, bytes, length);
    free(bytes);
    return result;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url { return [self initWithContentsOfURL:url options:0 error:NULL]; }
- (instancetype)initWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)options error:(NSError **)error {
    if (url.isFileURL) return [self initWithContentsOfFile:url.path options:options error:error];
    if (error)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnsupportedSchemeError
                                 userInfo:url ? @{NSURLErrorKey : url} : nil];
    return nil;
}
- (instancetype)initWithBase64EncodedString:(NSString *)string options:(NSDataBase64DecodingOptions)options {
    const char *in = string.UTF8String;
    if (!in) return nil;
    size_t n = strlen(in);
    uint8_t *out = malloc(n / 4 * 3 + 4);
    size_t len = 0;
    uint32_t acc = 0;
    int bits = 0, pad = 0;
    for (size_t i = 0; i < n; i++) {
        char c = in[i];
        int v;
        if (c >= 'A' && c <= 'Z') v = c - 'A';
        else if (c >= 'a' && c <= 'z') v = c - 'a' + 26;
        else if (c >= '0' && c <= '9') v = c - '0' + 52;
        else if (c == '+') v = 62;
        else if (c == '/') v = 63;
        else if (c == '=') { pad++; continue; }
        else if ((options & NSDataBase64DecodingIgnoreUnknownCharacters) || c == '\n' || c == '\r') continue;
        else { free(out); return nil; }
        if (pad) { free(out); return nil; }
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[len++] = (uint8_t)(acc >> bits);
        }
    }
    id result = make_data(self, out, len);
    free(out);
    return result;
}

- (NSUInteger)length { return (NSUInteger)CFDataGetLength(CFDT(self)); }
- (const void *)bytes { return CFDataGetBytePtr(CFDT(self)); }
- (void)getBytes:(void *)buffer length:(NSUInteger)length {
    NSUInteger n = self.length;
    memcpy(buffer, self.bytes, length < n ? length : n);
}
- (void)getBytes:(void *)buffer range:(NSRange)range {
    if (NSMaxRange(range) > self.length) BNRaise("NSRangeException", "-[NSData getBytes:range:]: range {%lu, %lu} exceeds data length %lu", range.location, range.length, self.length);
    memcpy(buffer, (const char *)self.bytes + range.location, range.length);
}
- (NSData *)subdataWithRange:(NSRange)range {
    if (NSMaxRange(range) > self.length) BNRaise("NSRangeException", "-[NSData subdataWithRange:]: range {%lu, %lu} exceeds data length %lu", range.location, range.length, self.length);
    return [NSData dataWithBytes:(const char *)self.bytes + range.location length:range.length];
}
- (NSRange)rangeOfData:(NSData *)needle options:(NSDataSearchOptions)options range:(NSRange)range {
    NSUInteger length = self.length, n = needle.length;
    if (range.location > length || range.length > length - range.location)
        BNRaise("NSRangeException", "-[NSData rangeOfData:options:range:]: range {%lu, %lu} exceeds length %lu",
                (unsigned long)range.location, (unsigned long)range.length, (unsigned long)length);
    if (!n || n > range.length) return NSMakeRange(NSNotFound, 0);
    const char *base = (const char *)self.bytes + range.location, *p = needle.bytes;
    NSUInteger last = range.length - n;
    BOOL backwards = (options & NSDataSearchBackwards) != 0, anchored = (options & NSDataSearchAnchored) != 0;
    for (NSUInteger i = 0; i <= last; i++) {
        NSUInteger at = backwards ? last - i : i;
        if (!memcmp(base + at, p, n)) return NSMakeRange(range.location + at, n);
        if (anchored) break;
    }
    return NSMakeRange(NSNotFound, 0);
}
- (BOOL)isEqualToData:(NSData *)other {
    return other && other.length == self.length && !memcmp(self.bytes, other.bytes, self.length);
}
- (BOOL)isEqual:(id)other { return other == self || ([other isKindOfClass:[NSData class]] && [self isEqualToData:other]); }
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically {
    return path && BNWriteFile(path.fileSystemRepresentation, self.bytes, self.length, atomically);
}
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically {
    return url.isFileURL && [self writeToFile:url.path atomically:atomically];
}
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)options error:(NSError **)error {
    if ([self writeToFile:path atomically:(options & NSDataWritingAtomic) != 0]) return YES;
    if (!path) errno = ENOENT;
    BNSetPOSIXError(error, path, NO);
    return NO;
}
- (BOOL)writeToURL:(NSURL *)url options:(NSDataWritingOptions)options error:(NSError **)error {
    if (url.isFileURL) return [self writeToFile:url.path options:options error:error];
    if (error)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnsupportedSchemeError
                                 userInfo:url ? @{NSURLErrorKey : url} : nil];
    return NO;
}
- (NSString *)base64EncodedStringWithOptions:(NSDataBase64EncodingOptions)options {
    const uint8_t *in = self.bytes;
    NSUInteger n = self.length;
    char *out = malloc((n + 2) / 3 * 4 + 1);
    size_t o = 0;
    for (NSUInteger i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)in[i] << 16 | (i + 1 < n ? (uint32_t)in[i + 1] << 8 : 0) | (i + 2 < n ? in[i + 2] : 0);
        out[o++] = b64[v >> 18];
        out[o++] = b64[(v >> 12) & 63];
        out[o++] = i + 1 < n ? b64[(v >> 6) & 63] : '=';
        out[o++] = i + 2 < n ? b64[v & 63] : '=';
    }
    out[o] = 0;
    NSString *s = [NSString stringWithUTF8String:out];
    free(out);
    return s;
}
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFDataCreateCopy(NULL, CFDT(self)); }
- (id)mutableCopyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFDataCreateMutableCopy(NULL, 0, CFDT(self)); }
- (NSString *)description {
    NSMutableString *s = [NSMutableString stringWithFormat:@"{length = %lu, bytes = 0x", self.length];
    const uint8_t *b = self.bytes;
    NSUInteger n = self.length, shown = n > 24 ? 24 : n;
    for (NSUInteger i = 0; i < shown; i++) [s appendFormat:@"%02x", b[i]];
    [s appendString:n > shown ? @"...}" : @"}"];
    return s;
}
@end

@implementation NSMutableData (Foundation)
+ (instancetype)dataWithCapacity:(NSUInteger)capacity { return [[self alloc] init]; }
+ (instancetype)dataWithLength:(NSUInteger)length { return [[self alloc] initWithLength:length]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity { return (__bridge_transfer id)CFDataCreateMutable(NULL, 0); }
- (instancetype)initWithLength:(NSUInteger)length {
    CFMutableDataRef m = CFDataCreateMutable(NULL, 0);
    CFDataSetLength(m, (CFIndex)length);
    return (__bridge_transfer id)m;
}
- (void *)mutableBytes { return CFDataGetMutableBytePtr(CFMDT(self)); }
- (void)setLength:(NSUInteger)length { CFDataSetLength(CFMDT(self), (CFIndex)length); }
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length { if (length) CFDataAppendBytes(CFMDT(self), bytes, (CFIndex)length); }
- (void)appendData:(NSData *)other { [self appendBytes:other.bytes length:other.length]; }
- (void)increaseLengthBy:(NSUInteger)extra { CFDataIncreaseLength(CFMDT(self), (CFIndex)extra); }
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes {
    if (range.location > self.length) BNRaise("NSRangeException", "-[NSMutableData replaceBytesInRange:withBytes:]: location %lu exceeds data length %lu", range.location, self.length);
    if (NSMaxRange(range) > self.length) self.length = NSMaxRange(range);
    memmove((char *)self.mutableBytes + range.location, bytes, range.length);
}
- (void)resetBytesInRange:(NSRange)range {
    if (NSMaxRange(range) > self.length) self.length = NSMaxRange(range);
    memset((char *)self.mutableBytes + range.location, 0, range.length);
}
- (void)setData:(NSData *)data {
    self.length = 0;
    [self appendData:data];
}
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFDataCreateCopy(NULL, CFDT(self)); }
@end
