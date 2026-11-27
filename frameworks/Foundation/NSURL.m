#import "FoundationInternal.h"
#include <limits.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <unistd.h>

/* Components of a parsed URL (strong references: the pieces are fresh
 * substrings that nothing else keeps alive). */
@interface BNURLParts : NSObject {
  @public
    NSString *scheme, *host, *path, *query, *fragment;
    NSInteger port;
}
@end
@implementation BNURLParts
@end

static NSString *percent_decode(NSString *s) {
    const char *in = s.UTF8String;
    if (!in || !strchr(in, '%')) return s;
    size_t n = strlen(in), o = 0;
    char *out = malloc(n + 1);
    for (size_t i = 0; i < n; i++) {
        if (in[i] == '%' && i + 2 < n + 0 && in[i + 1] && in[i + 2]) {
            char hex[3] = {in[i + 1], in[i + 2], 0};
            char *end;
            long v = strtol(hex, &end, 16);
            if (end == hex + 2) {
                out[o++] = (char)v;
                i += 2;
                continue;
            }
        }
        out[o++] = in[i];
    }
    out[o] = 0;
    NSString *r = [NSString stringWithUTF8String:out];
    free(out);
    return r ?: s;
}

static NSString *percent_encode_path(NSString *path) {
    const unsigned char *in = (const unsigned char *)path.UTF8String;
    NSMutableString *out = [NSMutableString string];
    for (; in && *in; in++) {
        unsigned char c = *in;
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || strchr("-._~/!$&'()*+,;=:@", c))
            [out appendFormat:@"%c", c];
        else
            [out appendFormat:@"%%%02X", c];
    }
    return out;
}

/* Split an absolute URL string into its components. */
static BNURLParts *parse(NSString *url) {
    BNURLParts *p = [BNURLParts new];
    p->port = -1;
    NSString *rest = url;
    NSRange hash = [rest rangeOfString:@"#"];
    if (hash.location != NSNotFound) {
        p->fragment = [rest substringFromIndex:hash.location + 1];
        rest = [rest substringToIndex:hash.location];
    }
    NSRange q = [rest rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        p->query = [rest substringFromIndex:q.location + 1];
        rest = [rest substringToIndex:q.location];
    }
    NSRange colon = [rest rangeOfString:@":"];
    NSRange slash = [rest rangeOfString:@"/"];
    if (colon.location != NSNotFound && colon.location > 0 && (slash.location == NSNotFound || colon.location < slash.location)) {
        p->scheme = [rest substringToIndex:colon.location].lowercaseString;
        rest = [rest substringFromIndex:colon.location + 1];
    }
    if ([rest hasPrefix:@"//"]) {
        rest = [rest substringFromIndex:2];
        NSRange end = [rest rangeOfString:@"/"];
        NSString *authority = end.location == NSNotFound ? rest : [rest substringToIndex:end.location];
        rest = end.location == NSNotFound ? @"" : [rest substringFromIndex:end.location];
        NSRange at = [authority rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) authority = [authority substringFromIndex:at.location + 1];
        NSRange port = [authority rangeOfString:@":" options:NSBackwardsSearch];
        if (port.location != NSNotFound && ![authority hasSuffix:@"]"]) {
            p->port = [authority substringFromIndex:port.location + 1].integerValue;
            authority = [authority substringToIndex:port.location];
        }
        if (authority.length) p->host = authority;
    }
    p->path = percent_decode(rest);
    return p;
}

static NSString *remove_dot_segments(NSString *path) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    for (NSUInteger i = 0; i < parts.count; i++) {
        NSString *p = parts[i];
        BOOL last = i + 1 == parts.count;
        if ([p isEqualToString:@"."]) {
            if (last) [out addObject:@""];
        } else if ([p isEqualToString:@".."]) {
            if (out.count > 1) [out removeLastObject];
            if (last) [out addObject:@""];
        } else {
            [out addObject:p];
        }
    }
    NSString *joined = [out componentsJoinedByString:@"/"];
    return [path hasPrefix:@"/"] && ![joined hasPrefix:@"/"] ? [@"/" stringByAppendingString:joined] : joined;
}

static BOOL has_scheme(NSString *s) {
    NSUInteger n = s.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == ':') return i > 0;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (i && ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.')))) return NO;
    }
    return NO;
}

/* RFC 3986 section 5.2: resolve a reference against an absolute base URL. */
static NSString *resolve_reference(NSString *ref, NSString *base) {
    if (!base.length || has_scheme(ref)) return ref;
    NSRange hash = [base rangeOfString:@"#"];
    if (hash.location != NSNotFound) base = [base substringToIndex:hash.location];
    if (!ref.length) return base;
    if ([ref hasPrefix:@"#"]) return [base stringByAppendingString:ref];
    NSRange q = [base rangeOfString:@"?"];
    NSString *noQuery = q.location == NSNotFound ? base : [base substringToIndex:q.location];
    if ([ref hasPrefix:@"?"]) return [noQuery stringByAppendingString:ref];
    NSRange colon = [noQuery rangeOfString:@":"];
    NSString *scheme = [noQuery substringToIndex:colon.location + 1], *rest = [noQuery substringFromIndex:colon.location + 1];
    if ([ref hasPrefix:@"//"]) return [scheme stringByAppendingString:ref];
    NSString *authority = @"", *path = rest;
    if ([rest hasPrefix:@"//"]) {
        NSRange slash = [rest rangeOfString:@"/" options:0 range:NSMakeRange(2, rest.length - 2)];
        authority = slash.location == NSNotFound ? rest : [rest substringToIndex:slash.location];
        path = slash.location == NSNotFound ? @"" : [rest substringFromIndex:slash.location];
    }
    NSString *tail = @"", *refPath = ref;
    NSRange cut = [ref rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (cut.location != NSNotFound) {
        tail = [ref substringFromIndex:cut.location];
        refPath = [ref substringToIndex:cut.location];
    }
    if (![refPath hasPrefix:@"/"]) {
        NSRange last = [path rangeOfString:@"/" options:NSBackwardsSearch];
        NSString *dir = last.location == NSNotFound ? (authority.length ? @"/" : @"") : [path substringToIndex:last.location + 1];
        refPath = [dir stringByAppendingString:refPath];
    }
    return [NSString stringWithFormat:@"%@%@%@%@", scheme, authority, remove_dot_segments(refPath), tail];
}

static NSURL *with_path(NSURL *url, NSString *path) {
    NSString *s = url.absoluteString, *tail = @"";
    NSRange cut = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (cut.location != NSNotFound) tail = [s substringFromIndex:cut.location];
    if (url.isFileURL) return [NSURL URLWithString:[[@"file://" stringByAppendingString:percent_encode_path(path)] stringByAppendingString:tail]];
    NSString *head = [s substringToIndex:cut.location == NSNotFound ? s.length : cut.location];
    NSRange start = [head rangeOfString:@"://"];
    NSUInteger from = start.location == NSNotFound ? [head rangeOfString:@":"].location + 1 : start.location + 3;
    NSRange slash = [head rangeOfString:@"/" options:0 range:NSMakeRange(from, head.length - from)];
    NSString *prefix = slash.location == NSNotFound ? head : [head substringToIndex:slash.location];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@%@%@", prefix, percent_encode_path(path), tail]];
}

NSString *const NSURLFileResourceTypeNamedPipe = @"NSURLFileResourceTypeNamedPipe";
NSString *const NSURLFileResourceTypeCharacterSpecial = @"NSURLFileResourceTypeCharacterSpecial";
NSString *const NSURLFileResourceTypeDirectory = @"NSURLFileResourceTypeDirectory";
NSString *const NSURLFileResourceTypeBlockSpecial = @"NSURLFileResourceTypeBlockSpecial";
NSString *const NSURLFileResourceTypeRegular = @"NSURLFileResourceTypeRegular";
NSString *const NSURLFileResourceTypeSymbolicLink = @"NSURLFileResourceTypeSymbolicLink";
NSString *const NSURLFileResourceTypeSocket = @"NSURLFileResourceTypeSocket";
NSString *const NSURLFileResourceTypeUnknown = @"NSURLFileResourceTypeUnknown";

static NSString *file_type(mode_t m) {
    if (S_ISDIR(m)) return NSURLFileResourceTypeDirectory;
    if (S_ISREG(m)) return NSURLFileResourceTypeRegular;
    if (S_ISLNK(m)) return NSURLFileResourceTypeSymbolicLink;
    if (S_ISFIFO(m)) return NSURLFileResourceTypeNamedPipe;
    if (S_ISCHR(m)) return NSURLFileResourceTypeCharacterSpecial;
    if (S_ISBLK(m)) return NSURLFileResourceTypeBlockSpecial;
    if (S_ISSOCK(m)) return NSURLFileResourceTypeSocket;
    return NSURLFileResourceTypeUnknown;
}

@implementation NSURL (Foundation)
+ (instancetype)URLWithString:(NSString *)string relativeToURL:(NSURL *)base {
    return [[self alloc] initWithString:string relativeToURL:base];
}
- (instancetype)initWithString:(NSString *)string relativeToURL:(NSURL *)base {
    if (!string) return nil;
    if (!base) return [self initWithString:string];
    for (const char *c = string.UTF8String; c && *c; c++)
        if ((unsigned char)*c <= ' ') return nil;
    return [self initWithString:resolve_reference(string, base.absoluteString)];
}
+ (instancetype)fileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL)isDir relativeToURL:(NSURL *)base {
    return [[self alloc] initFileURLWithFileSystemRepresentation:path isDirectory:isDir relativeToURL:base];
}
- (instancetype)initFileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL)isDir relativeToURL:(NSURL *)base {
    NSString *p = path ? [NSString stringWithUTF8String:path] : nil;
    if (!p) return nil;
    if (![p hasPrefix:@"/"] && base.isFileURL) p = [base.path stringByAppendingPathComponent:p];
    if (isDir && ![p hasSuffix:@"/"]) p = [p stringByAppendingString:@"/"];
    return [self initFileURLWithPath:p];
}
- (const char *)fileSystemRepresentation {
    if (!self.isFileURL) return NULL;
    NSString *__autoreleasing path = self.path;
    return path.fileSystemRepresentation;
}
- (BOOL)getFileSystemRepresentation:(char *)buffer maxLength:(NSUInteger)max {
    NSString *path = self.isFileURL ? self.path : nil;
    const char *p = path.fileSystemRepresentation;
    if (!p || !buffer || strlen(p) + 1 > max) return NO;
    memcpy(buffer, p, strlen(p) + 1);
    return YES;
}
- (NSURL *)URLByAppendingPathComponent:(NSString *)component isDirectory:(BOOL)isDirectory {
    NSURL *url = [self URLByAppendingPathComponent:component];
    if (!isDirectory || [url.absoluteString hasSuffix:@"/"]) return url;
    return with_path(url, [url.path stringByAppendingString:@"/"]);
}
- (NSURL *)URLByAppendingPathExtension:(NSString *)extension {
    NSString *p = self.path;
    if (!p.length || [p isEqualToString:@"/"]) return self;
    NSString *dir = [self.absoluteString hasSuffix:@"/"] ? @"/" : @"";
    return with_path(self, [[p stringByAppendingPathExtension:extension] stringByAppendingString:dir]);
}
- (NSURL *)URLByDeletingPathExtension {
    NSString *p = self.path;
    if (!p.length) return self;
    NSString *dir = [self.absoluteString hasSuffix:@"/"] && p.length > 1 ? @"/" : @"";
    return with_path(self, [p.stringByDeletingPathExtension stringByAppendingString:dir]);
}
- (NSURL *)URLByStandardizingPath {
    if (!self.isFileURL) return self;
    NSString *dir = [self.absoluteString hasSuffix:@"/"] && self.path.length > 1 ? @"/" : @"";
    return with_path(self, [self.path.stringByStandardizingPath stringByAppendingString:dir]);
}
- (NSURL *)URLByResolvingSymlinksInPath {
    if (!self.isFileURL) return self;
    char resolved[MAXPATHLEN];
    if (!realpath(self.path.fileSystemRepresentation, resolved)) return self.URLByStandardizingPath;
    NSString *p = [NSString stringWithUTF8String:resolved];
    if ([p hasPrefix:@"/private/"] && ![self.path hasPrefix:@"/private/"]) p = [p substringFromIndex:8];
    NSString *dir = [self.absoluteString hasSuffix:@"/"] && p.length > 1 ? @"/" : @"";
    return with_path(self, [p stringByAppendingString:dir]);
}
- (NSDictionary<NSString *, id> *)resourceValuesForKeys:(NSArray<NSString *> *)keys error:(NSError **)error {
    if (!self.isFileURL) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnsupportedSchemeError
                                     userInfo:@{NSURLErrorKey : self}];
        return nil;
    }
    NSString *path = self.path;
    struct stat st, lst;
    if (lstat(path.fileSystemRepresentation, &lst) != 0) {
        BNSetPOSIXError(error, path, YES);
        return nil;
    }
    if (stat(path.fileSystemRepresentation, &st) != 0) st = lst;
    NSString *name = path.lastPathComponent, *ext = path.pathExtension.lowercaseString;
    BOOL dir = S_ISDIR(st.st_mode);
    BOOL package = dir && [@[ @"app", @"bundle", @"framework", @"plugin", @"kext", @"xpc", @"appex" ] containsObject:ext];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        id v = nil;
        if ([key isEqualToString:NSURLNameKey] || [key isEqualToString:NSURLLocalizedNameKey]) v = name;
        else if ([key isEqualToString:NSURLPathKey]) v = path;
        else if ([key isEqualToString:NSURLIsDirectoryKey]) v = @(dir);
        else if ([key isEqualToString:NSURLIsRegularFileKey]) v = @(S_ISREG(st.st_mode));
        else if ([key isEqualToString:NSURLIsSymbolicLinkKey]) v = @(S_ISLNK(lst.st_mode));
        else if ([key isEqualToString:NSURLIsPackageKey]) v = @(package);
        else if ([key isEqualToString:NSURLIsApplicationKey]) v = @(dir && [ext isEqualToString:@"app"]);
        else if ([key isEqualToString:NSURLIsHiddenKey]) v = @([name hasPrefix:@"."]);
        else if ([key isEqualToString:NSURLIsVolumeKey]) v = @([path isEqualToString:@"/"]);
        else if ([key isEqualToString:NSURLIsReadableKey]) v = @(access(path.fileSystemRepresentation, R_OK) == 0);
        else if ([key isEqualToString:NSURLIsWritableKey]) v = @(access(path.fileSystemRepresentation, W_OK) == 0);
        else if ([key isEqualToString:NSURLIsExecutableKey]) v = @(access(path.fileSystemRepresentation, X_OK) == 0);
        else if ([key isEqualToString:NSURLFileSizeKey] || [key isEqualToString:NSURLTotalFileSizeKey])
            v = dir ? nil : @((unsigned long long)st.st_size);
        else if ([key isEqualToString:NSURLFileAllocatedSizeKey] || [key isEqualToString:NSURLTotalFileAllocatedSizeKey])
            v = dir ? nil : @((unsigned long long)st.st_blocks * 512);
        else if ([key isEqualToString:NSURLContentModificationDateKey])
            v = [NSDate dateWithTimeIntervalSince1970:st.st_mtimespec.tv_sec + st.st_mtimespec.tv_nsec / 1e9];
        else if ([key isEqualToString:NSURLAttributeModificationDateKey])
            v = [NSDate dateWithTimeIntervalSince1970:st.st_ctimespec.tv_sec + st.st_ctimespec.tv_nsec / 1e9];
        else if ([key isEqualToString:NSURLContentAccessDateKey])
            v = [NSDate dateWithTimeIntervalSince1970:st.st_atimespec.tv_sec + st.st_atimespec.tv_nsec / 1e9];
        else if ([key isEqualToString:NSURLCreationDateKey])
            v = [NSDate dateWithTimeIntervalSince1970:st.st_birthtimespec.tv_sec + st.st_birthtimespec.tv_nsec / 1e9];
        else if ([key isEqualToString:NSURLLinkCountKey]) v = @((unsigned long)st.st_nlink);
        else if ([key isEqualToString:NSURLFileResourceTypeKey]) v = file_type(lst.st_mode);
        else if ([key isEqualToString:NSURLParentDirectoryURLKey]) v = self.URLByDeletingLastPathComponent;
        else if ([key isEqualToString:NSURLIsExcludedFromBackupKey] || [key isEqualToString:NSURLIsUbiquitousItemKey]) v = @NO;
        if (v) out[key] = v;
    }
    return out;
}
- (BOOL)getResourceValue:(id *)value forKey:(NSString *)key error:(NSError **)error {
    NSDictionary *values = [self resourceValuesForKeys:@[ key ] error:error];
    if (value) *value = values[key];
    return values != nil;
}
+ (instancetype)URLWithString:(NSString *)string { return [[self alloc] initWithString:string]; }
+ (instancetype)fileURLWithPath:(NSString *)path { return [[self alloc] initFileURLWithPath:path]; }
+ (instancetype)fileURLWithPath:(NSString *)path isDirectory:(BOOL)isDirectory {
    if (isDirectory && ![path hasSuffix:@"/"]) path = [path stringByAppendingString:@"/"];
    return [[self alloc] initFileURLWithPath:path];
}
- (instancetype)initWithString:(NSString *)string {
    if (!string.length) return nil;
    /* spaces and control characters make a string invalid as a URL */
    const char *u = string.UTF8String;
    for (const char *c = u; c && *c; c++)
        if ((unsigned char)*c <= ' ') return nil;
    return (__bridge_transfer id)CFURLCreateWithString(NULL, (__bridge CFStringRef)string, NULL);
}
- (instancetype)initFileURLWithPath:(NSString *)path {
    if (!path) BNRaise("NSInvalidArgumentException", "-[NSURL initFileURLWithPath:]: nil string parameter");
    if (![path hasPrefix:@"/"]) {
        NSString *cwd = [NSFileManager defaultManager].currentDirectoryPath ?: @"/";
        path = [cwd stringByAppendingPathComponent:path];
    }
    NSString *s = [@"file://" stringByAppendingString:percent_encode_path(path)];
    return (__bridge_transfer id)CFURLCreateWithString(NULL, (__bridge CFStringRef)s, NULL);
}
- (NSString *)absoluteString { return (__bridge NSString *)CFURLGetString((__bridge CFURLRef)self); }
- (NSString *)scheme { return parse(self.absoluteString)->scheme; }
- (NSString *)host { return parse(self.absoluteString)->host; }
- (NSNumber *)port { BNURLParts *p = parse(self.absoluteString); return p->port >= 0 ? @(p->port) : nil; }
- (NSString *)query { return parse(self.absoluteString)->query; }
- (NSString *)fragment { return parse(self.absoluteString)->fragment; }
- (NSString *)path {
    NSString *path = parse(self.absoluteString)->path;
    while (path.length > 1 && [path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    return path;
}
- (BOOL)isFileURL { return [self.scheme isEqualToString:@"file"]; }
- (BOOL)checkResourceIsReachableAndReturnError:(NSError **)error {
    if (self.isFileURL && access(self.path.fileSystemRepresentation, F_OK) == 0) return YES;
    if (error) {
        NSInteger code = self.isFileURL ? NSFileReadNoSuchFileError : NSFileReadUnsupportedSchemeError;
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:code
                                 userInfo:@{NSURLErrorKey : self, NSFilePathErrorKey : self.path ?: @""}];
    }
    return NO;
}
- (BOOL)checkPromisedItemIsReachableAndReturnError:(NSError **)error {
    return [self checkResourceIsReachableAndReturnError:error];
}
- (NSString *)lastPathComponent { return self.path.lastPathComponent; }
- (NSString *)pathExtension { return self.path.pathExtension; }
- (NSURL *)URLByAppendingPathComponent:(NSString *)component {
    NSString *s = self.absoluteString, *tail = @"";
    NSRange cut = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (cut.location != NSNotFound) {
        tail = [s substringFromIndex:cut.location];
        s = [s substringToIndex:cut.location];
    }
    if (![s hasSuffix:@"/"]) s = [s stringByAppendingString:@"/"];
    return [NSURL URLWithString:[[s stringByAppendingString:percent_encode_path(component)] stringByAppendingString:tail]];
}
- (NSURL *)URLByDeletingLastPathComponent {
    NSString *s = self.absoluteString;
    NSRange cut = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (cut.location != NSNotFound) s = [s substringToIndex:cut.location];
    while (s.length > 1 && [s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    NSRange slash = [s rangeOfString:@"/" options:NSBackwardsSearch];
    NSRange authority = [s rangeOfString:@"://"];
    if (slash.location == NSNotFound || (authority.location != NSNotFound && slash.location < authority.location + 3)) return self;
    return [NSURL URLWithString:[s substringToIndex:slash.location + 1]];
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return self.absoluteString; }
@end

/* URL resource keys: their values are their names. */
NSString *const NSURLNameKey = @"NSURLNameKey";
NSString *const NSURLLocalizedNameKey = @"NSURLLocalizedNameKey";
NSString *const NSURLIsRegularFileKey = @"NSURLIsRegularFileKey";
NSString *const NSURLIsDirectoryKey = @"NSURLIsDirectoryKey";
NSString *const NSURLIsSymbolicLinkKey = @"NSURLIsSymbolicLinkKey";
NSString *const NSURLIsVolumeKey = @"NSURLIsVolumeKey";
NSString *const NSURLIsPackageKey = @"NSURLIsPackageKey";
NSString *const NSURLIsApplicationKey = @"NSURLIsApplicationKey";
NSString *const NSURLIsHiddenKey = @"NSURLIsHiddenKey";
NSString *const NSURLIsReadableKey = @"NSURLIsReadableKey";
NSString *const NSURLIsWritableKey = @"NSURLIsWritableKey";
NSString *const NSURLIsExecutableKey = @"NSURLIsExecutableKey";
NSString *const NSURLCreationDateKey = @"NSURLCreationDateKey";
NSString *const NSURLContentAccessDateKey = @"NSURLContentAccessDateKey";
NSString *const NSURLContentModificationDateKey = @"NSURLContentModificationDateKey";
NSString *const NSURLAttributeModificationDateKey = @"NSURLAttributeModificationDateKey";
NSString *const NSURLFileSizeKey = @"NSURLFileSizeKey";
NSString *const NSURLFileAllocatedSizeKey = @"NSURLFileAllocatedSizeKey";
NSString *const NSURLTotalFileSizeKey = @"NSURLTotalFileSizeKey";
NSString *const NSURLTotalFileAllocatedSizeKey = @"NSURLTotalFileAllocatedSizeKey";
NSString *const NSURLContentTypeKey = @"NSURLContentTypeKey";
NSString *const NSURLIsExcludedFromBackupKey = @"NSURLIsExcludedFromBackupKey";
NSString *const NSURLPathKey = @"NSURLPathKey";
NSString *const NSURLParentDirectoryURLKey = @"NSURLParentDirectoryURLKey";
NSString *const NSURLFileResourceTypeKey = @"NSURLFileResourceTypeKey";
NSString *const NSURLTypeIdentifierKey = @"NSURLTypeIdentifierKey";
NSString *const NSURLLinkCountKey = @"NSURLLinkCountKey";
NSString *const NSURLFileSecurityKey = @"NSURLFileSecurityKey";
NSString *const NSURLQuarantinePropertiesKey = @"NSURLQuarantinePropertiesKey";
NSString *const NSURLVolumeAvailableCapacityKey = @"NSURLVolumeAvailableCapacityKey";
NSString *const NSURLVolumeTotalCapacityKey = @"NSURLVolumeTotalCapacityKey";
NSString *const NSURLIsUbiquitousItemKey = @"NSURLIsUbiquitousItemKey";
NSString *const NSURLFileProtectionKey = @"NSURLFileProtectionKey";
NSString *const NSURLAddedToDirectoryDateKey = @"NSURLAddedToDirectoryDateKey";
