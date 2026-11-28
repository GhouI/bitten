#import "FoundationInternal.h"
#include <ctype.h>

CFStringEncoding BNCFEncoding(NSStringEncoding encoding) {
    switch (encoding) {
    case NSASCIIStringEncoding: return kCFStringEncodingASCII;
    case NSUTF8StringEncoding: return kCFStringEncodingUTF8;
    case NSISOLatin1StringEncoding: return kCFStringEncodingISOLatin1;
    case NSMacOSRomanStringEncoding: return kCFStringEncodingMacRoman;
    case NSUTF16StringEncoding: return kCFStringEncodingUTF16;
    case NSUTF16LittleEndianStringEncoding: return kCFStringEncodingUTF16LE;
    case NSUTF16BigEndianStringEncoding: return kCFStringEncodingUTF16BE;
    }
    return kCFStringEncodingUTF8;
}

/* ---- formatting ---------------------------------------------------------- */

struct outbuf {
    char *p;
    size_t len, cap;
};
static void out_bytes(struct outbuf *o, const char *s, size_t n) {
    if (o->len + n + 1 > o->cap) {
        o->cap = (o->len + n + 1) * 2;
        o->p = realloc(o->p, o->cap);
    }
    memcpy(o->p + o->len, s, n);
    o->len += n;
    o->p[o->len] = 0;
}
static void out_utf16(struct outbuf *o, const unichar *chars, size_t n) {
    CFStringRef s = CFStringCreateWithBytes(NULL, (const uint8_t *)chars, (CFIndex)n * 2, kCFStringEncodingUTF16LE, 0);
    if (!s) return;
    const char *u = CFStringGetCStringPtr(s, kCFStringEncodingUTF8);
    if (u) out_bytes(o, u, strlen(u));
    CFRelease(s);
}

char *BNFormatUTF8(NSString *format, va_list args) {
    struct outbuf o = {malloc(64), 0, 64};
    o.p[0] = 0;
    const char *f = format ? format.UTF8String : "";
    if (!f) f = "";
    while (*f) {
        const char *pct = strchr(f, '%');
        if (!pct) {
            out_bytes(&o, f, strlen(f));
            break;
        }
        out_bytes(&o, f, (size_t)(pct - f));
        /* parse one conversion: %[position$][flags][width][.precision][length]type */
        char spec[64];
        size_t n = 0;
        const char *p = pct + 1;
        spec[n++] = '%';
        while (*p && strchr("-+ #0'", *p) && n < 40) spec[n++] = *p++;
        int width = -1, precision = -1;
        if (*p == '*') {
            width = va_arg(args, int);
            p++;
        } else {
            while (*p >= '0' && *p <= '9' && n < 40) spec[n++] = *p++;
        }
        if (width >= 0) n += (size_t)snprintf(spec + n, sizeof spec - n, "%d", width);
        if (*p == '.') {
            spec[n++] = *p++;
            if (*p == '*') {
                precision = va_arg(args, int);
                p++;
                n += (size_t)snprintf(spec + n, sizeof spec - n, "%d", precision < 0 ? 0 : precision);
            } else {
                while (*p >= '0' && *p <= '9' && n < 50) spec[n++] = *p++;
            }
        }
        int longs = 0, is_size = 0, is_longdouble = 0, shorts = 0;
        for (;; p++) {
            if (*p == 'l') longs++;
            else if (*p == 'q') longs = 2;
            else if (*p == 'z' || *p == 't' || *p == 'j') is_size = 1;
            else if (*p == 'L') is_longdouble = 1;
            else if (*p == 'h') shorts++;
            else break;
        }
        char type = *p;
        if (!type) break;
        f = p + 1;
        char tmp[512];
        switch (type) {
        case '%':
            out_bytes(&o, "%", 1);
            break;
        case '@': {
            id obj = va_arg(args, id);
            NSString *d = BNDescribe(obj);
            const char *u = d.UTF8String;
            if (u) out_bytes(&o, u, strlen(u));
            break;
        }
        case 'd': case 'i': case 'u': case 'o': case 'x': case 'X': case 'c': {
            spec[n] = 0;
            int len;
            if (type == 'c') {
                snprintf(spec + n, sizeof spec - n, "c");
                len = snprintf(tmp, sizeof tmp, spec, va_arg(args, int));
            } else if (longs >= 1 || is_size) {
                snprintf(spec + n, sizeof spec - n, "ll%c", type);
                len = snprintf(tmp, sizeof tmp, spec, (long long)va_arg(args, long));
            } else {
                snprintf(spec + n, sizeof spec - n, "%s%c", shorts == 2 ? "hh" : shorts == 1 ? "h" : "", type);
                len = snprintf(tmp, sizeof tmp, spec, va_arg(args, int));
            }
            if (len > 0) out_bytes(&o, tmp, (size_t)len < sizeof tmp ? (size_t)len : sizeof tmp - 1);
            break;
        }
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A': {
            int len;
            if (is_longdouble) {
                snprintf(spec + n, sizeof spec - n, "L%c", type);
                len = snprintf(tmp, sizeof tmp, spec, va_arg(args, long double));
            } else {
                snprintf(spec + n, sizeof spec - n, "%c", type);
                len = snprintf(tmp, sizeof tmp, spec, va_arg(args, double));
            }
            if (len > 0) out_bytes(&o, tmp, (size_t)len < sizeof tmp ? (size_t)len : sizeof tmp - 1);
            break;
        }
        case 's': {
            const char *s = va_arg(args, const char *);
            if (!s) s = "(null)";
            snprintf(spec + n, sizeof spec - n, "s");
            int len = snprintf(NULL, 0, spec, s);
            if (len > 0) {
                char *big = malloc((size_t)len + 1);
                snprintf(big, (size_t)len + 1, spec, s);
                out_bytes(&o, big, (size_t)len);
                free(big);
            }
            break;
        }
        case 'p': {
            int len = snprintf(tmp, sizeof tmp, "%p", va_arg(args, void *));
            out_bytes(&o, tmp, (size_t)len);
            break;
        }
        case 'C': {
            unichar c = (unichar)va_arg(args, int);
            out_utf16(&o, &c, 1);
            break;
        }
        case 'S': {
            const unichar *s = va_arg(args, const unichar *);
            size_t len = 0;
            while (s && s[len]) len++;
            if (s) out_utf16(&o, s, len);
            break;
        }
        default:
            out_bytes(&o, pct, (size_t)(f - pct));
            break;
        }
    }
    return o.p;
}

static NSString *format_string(NSString *format, va_list args, BOOL mutable) {
    char *utf8 = BNFormatUTF8(format, args);
    CFStringRef s = CFStringCreateWithCString(NULL, utf8, kCFStringEncodingUTF8);
    /* A %s given something not UTF-8 (or not a C string at all): keep the
     * text, the bad bytes as U+FFFD, rather than nothing. */
    if (!s) {
        size_t n = strlen(utf8);
        char *fixed = malloc(n * 3 + 1), *w = fixed;
        const unsigned char *r = (const unsigned char *)utf8, *end = r + n;
        while (r < end) {
            unsigned c = *r;
            int len = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 0;
            int ok = len > 0 && r + len <= end;
            for (int k = 1; ok && k < len; k++) ok = (r[k] & 0xC0) == 0x80;
            if (ok && len == 2) ok = c >= 0xC2;
            if (ok) {
                memcpy(w, r, (size_t)len);
                w += len;
                r += len;
            } else {
                memcpy(w, "\xEF\xBF\xBD", 3);
                w += 3;
                r++;
            }
        }
        *w = 0;
        s = CFStringCreateWithCString(NULL, fixed, kCFStringEncodingUTF8);
        free(fixed);
    }
    free(utf8);
    if (mutable && s) {
        CFMutableStringRef m = CFStringCreateMutableCopy(NULL, 0, s);
        CFRelease(s);
        return (__bridge_transfer NSMutableString *)m;
    }
    return (__bridge_transfer NSString *)s;
}

void NSLogv(NSString *format, va_list args) {
    char *utf8 = BNFormatUTF8(format, args);
    struct timespec ts;
    struct tm tm;
    char stamp[40];
    clock_gettime(CLOCK_REALTIME, &ts);
    localtime_r(&ts.tv_sec, &tm);
    strftime(stamp, sizeof stamp, "%Y-%m-%d %H:%M:%S", &tm);
    size_t len = strlen(utf8);
    dprintf(2, "%s.%03ld %s[%d] %s%s", stamp, ts.tv_nsec / 1000000, getprogname(), getpid(), utf8,
            len && utf8[len - 1] == '\n' ? "" : "\n");
    free(utf8);
}
void NSLog(NSString *format, ...) {
    va_list ap;
    va_start(ap, format);
    NSLogv(format, ap);
    va_end(ap);
}

/* ---- NSString ------------------------------------------------------------- */

static BOOL wants_mutable(id self) { return [self isKindOfClass:[NSMutableString class]]; }

/* Wrap a +1 CFString as the result of an initialiser on `self`. */
static id adopt(id self, CFStringRef s) {
    if (!s) return nil;
    if (wants_mutable(self)) {
        CFMutableStringRef m = CFStringCreateMutableCopy(NULL, 0, s);
        CFRelease(s);
        return (__bridge_transfer id)m;
    }
    return (__bridge_transfer id)s;
}

static void check_index(NSString *s, NSUInteger index, const char *what) {
    if (index > s.length) BNRaise("NSRangeException", "-[NSString %s]: index %lu out of bounds; string length %lu", what, index, s.length);
}

@implementation NSString (Foundation)

+ (instancetype)string { return [[self alloc] init]; }
+ (instancetype)stringWithUTF8String:(const char *)c { return [[self alloc] initWithUTF8String:c]; }
+ (instancetype)stringWithCString:(const char *)c encoding:(NSStringEncoding)e { return [[self alloc] initWithCString:c encoding:e]; }
+ (instancetype)stringWithString:(NSString *)s { return [[self alloc] initWithString:s]; }
+ (instancetype)stringWithFormat:(NSString *)format, ... {
    va_list ap;
    va_start(ap, format);
    NSString *s = format_string(format, ap, [self isSubclassOfClass:[NSMutableString class]]);
    va_end(ap);
    return s;
}

- (instancetype)init { return adopt(self, CFStringCreateWithCString(NULL, "", kCFStringEncodingUTF8)); }
- (instancetype)initWithUTF8String:(const char *)c {
    if (!c) BNRaise("NSInvalidArgumentException", "-[NSString initWithUTF8String:]: NULL cString");
    return adopt(self, CFStringCreateWithCString(NULL, c, kCFStringEncodingUTF8));
}
- (instancetype)initWithCString:(const char *)c encoding:(NSStringEncoding)e {
    return c ? adopt(self, CFStringCreateWithCString(NULL, c, BNCFEncoding(e))) : nil;
}
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length encoding:(NSStringEncoding)e {
    return adopt(self, CFStringCreateWithBytes(NULL, bytes, (CFIndex)length, BNCFEncoding(e), e == NSUTF16StringEncoding));
}
- (instancetype)initWithData:(NSData *)data encoding:(NSStringEncoding)e {
    CFDataRef d = (__bridge CFDataRef)data;
    return adopt(self, CFStringCreateWithBytes(NULL, CFDataGetBytePtr(d), CFDataGetLength(d), BNCFEncoding(e), e == NSUTF16StringEncoding));
}
+ (instancetype)stringWithCharacters:(const unichar *)chars length:(NSUInteger)length {
    return [[self alloc] initWithCharacters:chars length:length];
}
- (instancetype)initWithCharacters:(const unichar *)chars length:(NSUInteger)length {
    return adopt(self, CFStringCreateWithBytes(NULL, (const uint8_t *)chars, (CFIndex)length * 2, kCFStringEncodingUTF16LE, 0));
}
- (instancetype)initWithString:(NSString *)s {
    if (!s) BNRaise("NSInvalidArgumentException", "-[NSString initWithString:]: nil argument");
    return adopt(self, CFStringCreateCopy(NULL, CFS(s)));
}
- (instancetype)initWithFormat:(NSString *)format arguments:(va_list)args {
    return format_string(format, args, wants_mutable(self));
}
- (instancetype)initWithFormat:(NSString *)format, ... {
    va_list ap;
    va_start(ap, format);
    NSString *s = format_string(format, ap, wants_mutable(self));
    va_end(ap);
    return s;
}

- (NSUInteger)length { return (NSUInteger)CFStringGetLength(CFS(self)); }
- (unichar)characterAtIndex:(NSUInteger)index {
    if (index >= self.length) BNRaise("NSRangeException", "-[NSString characterAtIndex:]: index %lu out of bounds; string length %lu", index, self.length);
    return CFStringGetCharacterAtIndex(CFS(self), (CFIndex)index);
}
- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    check_index(self, NSMaxRange(range), "getCharacters:range:");
    CFStringGetCharacters(CFS(self), CFRangeMake((CFIndex)range.location, (CFIndex)range.length), buffer);
}
- (const char *)UTF8String { return [self cStringUsingEncoding:NSUTF8StringEncoding]; }
- (const char *)cStringUsingEncoding:(NSStringEncoding)e {
    const char *direct = CFStringGetCStringPtr(CFS(self), BNCFEncoding(e));
    if (direct) return direct;
    /* converted bytes live as long as an autoreleased data object */
    NSData *data = [self dataUsingEncoding:e];
    if (!data) return NULL;
    CFMutableDataRef m = CFDataCreateMutableCopy(NULL, 0, (__bridge CFDataRef)data);
    CFDataAppendBytes(m, (const uint8_t *)"\0\0", 2);
    NSData *keep = (__bridge_transfer NSData *)m;
    return (const char *)CFDataGetBytePtr((__bridge CFDataRef)keep);
}
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)e {
    NSData *d = [self dataUsingEncoding:e];
    return d ? (NSUInteger)CFDataGetLength((__bridge CFDataRef)d) : 0;
}
- (NSData *)dataUsingEncoding:(NSStringEncoding)e {
    return (__bridge_transfer NSData *)CFStringCreateExternalRepresentation(NULL, CFS(self), BNCFEncoding(e), 0);
}
- (NSData *)dataUsingEncoding:(NSStringEncoding)e allowLossyConversion:(BOOL)lossy {
    return (__bridge_transfer NSData *)CFStringCreateExternalRepresentation(NULL, CFS(self), BNCFEncoding(e), lossy ? '?' : 0);
}
- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)e { return [self dataUsingEncoding:e] != nil; }

- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFStringCreateCopy(NULL, CFS(self)); }
- (id)mutableCopyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFStringCreateMutableCopy(NULL, 0, CFS(self)); }
- (NSString *)description { return self; }

- (BOOL)isEqualToString:(NSString *)other { return other && CFEqual(CFS(self), CFS(other)); }
- (NSComparisonResult)compare:(NSString *)other { return [self compare:other options:0]; }
- (NSComparisonResult)compare:(NSString *)other options:(NSStringCompareOptions)mask {
    if (!other) return NSOrderedDescending;
    return (NSComparisonResult)CFStringCompare(CFS(self), CFS(other), (mask & NSCaseInsensitiveSearch) ? kCFCompareCaseInsensitive : 0);
}
- (NSComparisonResult)caseInsensitiveCompare:(NSString *)other { return [self compare:other options:NSCaseInsensitiveSearch]; }
- (BOOL)hasPrefix:(NSString *)p { return p && CFStringHasPrefix(CFS(self), CFS(p)); }
- (BOOL)hasSuffix:(NSString *)s { return s && CFStringHasSuffix(CFS(self), CFS(s)); }

- (NSRange)rangeOfString:(NSString *)needle options:(NSStringCompareOptions)mask {
    NSUInteger n = self.length, m = needle.length;
    NSRange none = {NSNotFound, 0};
    if (!needle || m == 0 || m > n) return none;
    unichar *hay = malloc(n * sizeof(unichar)), *pin = malloc(m * sizeof(unichar));
    [self getCharacters:hay range:NSMakeRange(0, n)];
    [needle getCharacters:pin range:NSMakeRange(0, m)];
    if (mask & NSCaseInsensitiveSearch) {
        for (NSUInteger i = 0; i < n; i++) if (hay[i] >= 'A' && hay[i] <= 'Z') hay[i] += 32;
        for (NSUInteger i = 0; i < m; i++) if (pin[i] >= 'A' && pin[i] <= 'Z') pin[i] += 32;
    }
    NSRange found = none;
    if (mask & NSBackwardsSearch) {
        for (NSUInteger i = n - m + 1; i-- > 0;)
            if (!memcmp(hay + i, pin, m * sizeof(unichar))) { found = NSMakeRange(i, m); break; }
    } else {
        for (NSUInteger i = 0; i + m <= n; i++)
            if (!memcmp(hay + i, pin, m * sizeof(unichar))) { found = NSMakeRange(i, m); break; }
    }
    free(hay);
    free(pin);
    return found;
}
- (NSRange)rangeOfString:(NSString *)needle { return [self rangeOfString:needle options:0]; }
/* The composed character (surrogate pair, base plus combining marks) at i. */
- (NSRange)rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)i {
    NSUInteger n = self.length;
    check_index(self, i + 1, "rangeOfComposedCharacterSequenceAtIndex:");
    NSUInteger start = i, end = i + 1;
    unichar c = [self characterAtIndex:i];
    if (c >= 0xDC00 && c <= 0xDFFF && i > 0) start--;
    else if (c >= 0xD800 && c <= 0xDBFF && end < n) end++;
    while (end < n) {
        unichar d = [self characterAtIndex:end];
        if (!((d >= 0x300 && d <= 0x36F) || (d >= 0xFE00 && d <= 0xFE0F) || d == 0x200D || (d >= 0x20D0 && d <= 0x20FF)))
            break;
        end++;
        if (d == 0x200D && end < n) end++;
    }
    return NSMakeRange(start, end - start);
}
- (NSRange)rangeOfComposedCharacterSequencesForRange:(NSRange)r {
    if (!r.length) return [self rangeOfComposedCharacterSequenceAtIndex:r.location];
    NSRange a = [self rangeOfComposedCharacterSequenceAtIndex:r.location];
    NSRange b = [self rangeOfComposedCharacterSequenceAtIndex:NSMaxRange(r) - 1];
    return NSUnionRange(a, b);
}
/* The line (or paragraph: the same for \n, \r, \r\n, U+2028/9) containing range. */
- (void)getLineStart:(NSUInteger *)startp end:(NSUInteger *)endp contentsEnd:(NSUInteger *)contentsEndp
            forRange:(NSRange)range {
    NSUInteger n = self.length, start = MIN(range.location, n), end = MIN(NSMaxRange(range), n);
    while (start > 0) {
        unichar c = [self characterAtIndex:start - 1];
        if (c == '\n' || c == '\r' || c == 0x2028 || c == 0x2029) break;
        start--;
    }
    if (range.length && end > 0) end--;
    while (end < n) {
        unichar c = [self characterAtIndex:end];
        if (c == '\n' || c == '\r' || c == 0x2028 || c == 0x2029) break;
        end++;
    }
    NSUInteger contents = end;
    if (end < n) {
        end++;
        if ([self characterAtIndex:end - 1] == '\r' && end < n && [self characterAtIndex:end] == '\n') end++;
    }
    if (startp) *startp = start;
    if (endp) *endp = end;
    if (contentsEndp) *contentsEndp = contents;
}
- (void)getParagraphStart:(NSUInteger *)s end:(NSUInteger *)e contentsEnd:(NSUInteger *)c forRange:(NSRange)r {
    [self getLineStart:s end:e contentsEnd:c forRange:r];
}
- (NSRange)lineRangeForRange:(NSRange)r {
    NSUInteger s, e;
    [self getLineStart:&s end:&e contentsEnd:NULL forRange:r];
    return NSMakeRange(s, e - s);
}
- (NSRange)paragraphRangeForRange:(NSRange)r { return [self lineRangeForRange:r]; }
static BOOL is_word_char(unichar c) {
    return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '\'' || c == '_' ||
           (c >= 0xc0 && c != 0xd7 && c != 0xf7 && !(c >= 0x2000 && c <= 0x206f) && c != 0x3000);
}
static BOOL is_sentence_end(unichar c) { return c == '.' || c == '!' || c == '?'; }
static BOOL is_blank(unichar c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0x2028 || c == 0x2029 || c == 0xa0; }
- (void)enumerateSubstringsInRange:(NSRange)range options:(NSStringEnumerationOptions)opts
                        usingBlock:(void (^)(NSString *, NSRange, NSRange, BOOL *))block {
    check_index(self, NSMaxRange(range), "enumerateSubstringsInRange:options:usingBlock:");
    NSUInteger kind = opts & 0xff, end = NSMaxRange(range), i = range.location, count = 0, cap = 16;
    NSRange (*pieces)[2] = malloc(cap * sizeof *pieces);
    while (i < end) {
        NSRange sub, enclosing;
        if (kind == NSStringEnumerationByComposedCharacterSequences) {
            sub = enclosing = NSIntersectionRange([self rangeOfComposedCharacterSequenceAtIndex:i], range);
        } else if (kind == NSStringEnumerationByWords) {
            NSUInteger start = i;
            while (i < end && !is_word_char([self characterAtIndex:i])) i++;
            if (i == end) break;
            NSUInteger w = i;
            while (i < end && is_word_char([self characterAtIndex:i])) i++;
            NSUInteger e = i;
            while (e < end && !is_word_char([self characterAtIndex:e])) e++;
            sub = NSMakeRange(w, i - w);
            enclosing = NSMakeRange(start, e - start);
        } else if (kind == NSStringEnumerationBySentences) {
            NSUInteger s = i;
            while (s < end && is_blank([self characterAtIndex:s])) s++;
            if (s == end) break;
            NSUInteger e = s;
            while (e < end) {
                unichar c = [self characterAtIndex:e];
                if (c == '\n' || c == 0x2029) break;
                e++;
                if (is_sentence_end(c)) {
                    while (e < end && is_sentence_end([self characterAtIndex:e])) e++;
                    if (e == end || is_blank([self characterAtIndex:e])) break;
                }
            }
            NSUInteger tail = e;
            while (tail < end && is_blank([self characterAtIndex:tail])) tail++;
            sub = NSMakeRange(s, e - s);
            enclosing = NSMakeRange(i, tail - i);
        } else {
            NSUInteger s, e, contents;
            [self getLineStart:&s end:&e contentsEnd:&contents forRange:NSMakeRange(i, 0)];
            s = MAX(s, range.location);
            e = MIN(e, end);
            contents = MIN(contents, end);
            sub = NSMakeRange(s, contents - s);
            enclosing = NSMakeRange(s, e - s);
        }
        if (count == cap) pieces = realloc(pieces, (cap *= 2) * sizeof *pieces);
        pieces[count][0] = sub;
        pieces[count][1] = enclosing;
        count++;
        i = MAX(NSMaxRange(enclosing), i + 1);
    }
    BOOL reverse = (opts & NSStringEnumerationReverse) != 0, stop = NO;
    for (NSUInteger k = 0; k < count && !stop; k++) {
        NSRange *pair = pieces[reverse ? count - 1 - k : k];
        NSString *text = (opts & NSStringEnumerationSubstringNotRequired) ? nil : [self substringWithRange:pair[0]];
        block(text, pair[0], pair[1], &stop);
    }
    free(pieces);
}
- (void)enumerateLinesUsingBlock:(void (^)(NSString *, BOOL *))block {
    [self enumerateSubstringsInRange:NSMakeRange(0, self.length) options:NSStringEnumerationByLines
                          usingBlock:^(NSString *line, NSRange r, NSRange e, BOOL *stop) { block(line, stop); }];
}
- (NSString *)stringByAddingPercentEncodingWithAllowedCharacters:(NSCharacterSet *)allowed {
    const unsigned char *in = (const unsigned char *)self.UTF8String;
    if (!in) return nil;
    NSMutableString *out = [NSMutableString string];
    for (; *in; in++) {
        if (*in < 0x80 && [allowed characterIsMember:*in]) [out appendFormat:@"%c", *in];
        else [out appendFormat:@"%%%02X", *in];
    }
    return out;
}
- (NSString *)stringByRemovingPercentEncoding {
    const char *in = self.UTF8String;
    if (!in) return nil;
    size_t n = strlen(in), o = 0;
    char *out = malloc(n + 1);
    for (size_t i = 0; i < n; i++) {
        if (in[i] != '%') {
            out[o++] = in[i];
            continue;
        }
        if (i + 2 >= n + 0 || !isxdigit((unsigned char)in[i + 1]) || !isxdigit((unsigned char)in[i + 2])) {
            free(out);
            return nil;
        }
        char hex[3] = {in[i + 1], in[i + 2], 0};
        out[o++] = (char)strtol(hex, NULL, 16);
        i += 2;
    }
    out[o] = 0;
    NSString *r = [NSString stringWithUTF8String:out];
    free(out);
    return r;
}
- (NSRange)rangeOfString:(NSString *)needle options:(NSStringCompareOptions)mask range:(NSRange)range {
    check_index(self, NSMaxRange(range), "rangeOfString:options:range:");
    NSRange r = [[self substringWithRange:range] rangeOfString:needle options:mask];
    if (r.location != NSNotFound) r.location += range.location;
    return r;
}
- (BOOL)containsString:(NSString *)s { return [self rangeOfString:s].location != NSNotFound; }

- (NSString *)substringWithRange:(NSRange)range {
    check_index(self, NSMaxRange(range), "substringWithRange:");
    if (range.length == 0) return @"";
    unichar *chars = malloc(range.length * sizeof(unichar));
    [self getCharacters:chars range:range];
    NSString *s = [[NSString alloc] initWithCharacters:chars length:range.length];
    free(chars);
    return s;
}
- (NSString *)substringFromIndex:(NSUInteger)from {
    check_index(self, from, "substringFromIndex:");
    return [self substringWithRange:NSMakeRange(from, self.length - from)];
}
- (NSString *)substringToIndex:(NSUInteger)to {
    check_index(self, to, "substringToIndex:");
    return [self substringWithRange:NSMakeRange(0, to)];
}
- (NSString *)stringByAppendingString:(NSString *)other {
    if (!other) BNRaise("NSInvalidArgumentException", "-[NSString stringByAppendingString:]: nil argument");
    CFMutableStringRef m = CFStringCreateMutableCopy(NULL, 0, CFS(self));
    CFStringAppend(m, CFS(other));
    CFStringRef frozen = CFStringCreateCopy(NULL, m);
    CFRelease(m);
    return (__bridge_transfer NSString *)frozen;
}
- (NSString *)stringByAppendingFormat:(NSString *)format, ... {
    va_list ap;
    va_start(ap, format);
    NSString *tail = format_string(format, ap, NO);
    va_end(ap);
    return [self stringByAppendingString:tail];
}
- (NSArray *)componentsSeparatedByString:(NSString *)separator {
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger start = 0, n = self.length, m = separator.length;
    if (!m) return [NSArray arrayWithObject:[self copy]];
    while (start <= n) {
        NSRange rest = NSMakeRange(start, n - start);
        NSString *tail = [self substringWithRange:rest];
        NSRange hit = [tail rangeOfString:separator];
        if (hit.location == NSNotFound) {
            [parts addObject:tail];
            break;
        }
        [parts addObject:[tail substringToIndex:hit.location]];
        start += hit.location + m;
    }
    return [parts copy];
}
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement {
    if (!target.length) return [self copy];
    return [[self componentsSeparatedByString:target] componentsJoinedByString:replacement];
}

static NSString *map_case(NSString *s, int upper) {
    NSUInteger n = s.length;
    if (!n) return @"";
    unichar *chars = malloc(n * sizeof(unichar));
    [s getCharacters:chars range:NSMakeRange(0, n)];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = chars[i];
        if (upper) {
            if ((c >= 'a' && c <= 'z') || (c >= 0xe0 && c <= 0xfe && c != 0xf7)) chars[i] = c - 32;
        } else {
            if ((c >= 'A' && c <= 'Z') || (c >= 0xc0 && c <= 0xde && c != 0xd7)) chars[i] = c + 32;
        }
    }
    NSString *r = [[NSString alloc] initWithCharacters:chars length:n];
    free(chars);
    return r;
}
- (NSString *)lowercaseString { return map_case(self, 0); }
- (NSString *)uppercaseString { return map_case(self, 1); }

- (long long)longLongValue { const char *u = self.UTF8String; return u ? strtoll(u, NULL, 10) : 0; }
- (int)intValue {
    long long v = self.longLongValue;
    return v > 0x7fffffffLL ? 0x7fffffff : v < -0x80000000LL ? (int)-0x80000000LL : (int)v;
}
- (NSInteger)integerValue { return (NSInteger)self.longLongValue; }
- (double)doubleValue { const char *u = self.UTF8String; return u ? strtod(u, NULL) : 0.0; }
- (float)floatValue { return (float)self.doubleValue; }
- (BOOL)boolValue {
    const char *u = self.UTF8String;
    while (u && (*u == ' ' || *u == '\t')) u++;
    if (!u) return NO;
    if (*u == '+' || *u == '-') u++;
    while (*u == '0') u++;
    return *u == 'Y' || *u == 'y' || *u == 'T' || *u == 't' || (*u >= '1' && *u <= '9');
}

/* ---- paths ---- */
static NSString *strip_trailing_slashes(NSString *s) {
    NSUInteger n = s.length;
    while (n > 1 && [s characterAtIndex:n - 1] == '/') n--;
    return n == s.length ? s : [s substringToIndex:n];
}
- (NSString *)lastPathComponent {
    NSString *s = strip_trailing_slashes(self);
    NSRange slash = [s rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location == NSNotFound || s.length == 1) return s;
    return [s substringFromIndex:slash.location + 1];
}
- (NSString *)stringByDeletingLastPathComponent {
    NSString *s = strip_trailing_slashes(self);
    NSRange slash = [s rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location == NSNotFound) return @"";
    if (slash.location == 0) return @"/";
    return strip_trailing_slashes([s substringToIndex:slash.location]);
}
- (NSString *)pathExtension {
    NSString *last = self.lastPathComponent;
    NSRange dot = [last rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound || dot.location == 0) return @"";
    return [last substringFromIndex:dot.location + 1];
}
- (NSString *)stringByDeletingPathExtension {
    NSString *s = strip_trailing_slashes(self);
    NSString *ext = s.pathExtension;
    if (!ext.length) return s;
    return [s substringToIndex:s.length - ext.length - 1];
}
- (NSString *)stringByAppendingPathComponent:(NSString *)component {
    if (!self.length) return [component copy];
    if (!component.length) return [self copy];
    NSString *base = strip_trailing_slashes(self);
    while (component.length > 1 && [component hasPrefix:@"/"]) component = [component substringFromIndex:1];
    if ([base isEqualToString:@"/"]) return [base stringByAppendingString:component];
    return [NSString stringWithFormat:@"%@/%@", base, strip_trailing_slashes(component)];
}
- (NSString *)stringByAppendingPathExtension:(NSString *)extension {
    return [NSString stringWithFormat:@"%@.%@", strip_trailing_slashes(self), extension];
}
@end

@implementation NSMutableString (Foundation)
+ (instancetype)stringWithCapacity:(NSUInteger)capacity { return [[self alloc] initWithCapacity:capacity]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity { return (__bridge_transfer id)CFStringCreateMutable(NULL, 0); }
- (void)appendString:(NSString *)s {
    if (!s) BNRaise("NSInvalidArgumentException", "-[NSMutableString appendString:]: nil argument");
    CFStringAppend((__bridge CFMutableStringRef)self, CFS(s));
}
- (void)appendFormat:(NSString *)format, ... {
    va_list ap;
    va_start(ap, format);
    char *utf8 = BNFormatUTF8(format, ap);
    va_end(ap);
    CFStringAppendCString((__bridge CFMutableStringRef)self, utf8, kCFStringEncodingUTF8);
    free(utf8);
}
- (void)setString:(NSString *)s { CFStringSetString((__bridge CFMutableStringRef)self, CFS(s)); }
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)s {
    check_index(self, NSMaxRange(range), "replaceCharactersInRange:withString:");
    CFStringReplace((__bridge CFMutableStringRef)self, CFRangeMake((CFIndex)range.location, (CFIndex)range.length), CFS(s));
}
- (void)insertString:(NSString *)s atIndex:(NSUInteger)index {
    [self replaceCharactersInRange:NSMakeRange(index, 0) withString:s];
}
- (void)deleteCharactersInRange:(NSRange)range {
    check_index(self, NSMaxRange(range), "deleteCharactersInRange:");
    CFStringDelete((__bridge CFMutableStringRef)self, CFRangeMake((CFIndex)range.location, (CFIndex)range.length));
}
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFStringCreateCopy(NULL, CFS(self)); }
@end
