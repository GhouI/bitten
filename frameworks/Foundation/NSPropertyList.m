/* Property lists: reading XML and binary ("bplist00") plists, writing XML.
 * Bundles' Info.plist files and preferences are property lists. Formats are
 * the documented ones; the parsers are written here. */
#import "FoundationInternal.h"

/* ---- binary ---------------------------------------------------------------------- */

typedef struct {
    const uint8_t *bytes;
    size_t length;
    unsigned offset_size, ref_size;
    uint64_t count, top, table;
} bplist;

static uint64_t be_uint(const uint8_t *p, unsigned n) {
    uint64_t v = 0;
    for (unsigned i = 0; i < n; i++) v = v << 8 | p[i];
    return v;
}

static id bplist_object(bplist *b, uint64_t ref, int depth);

/* The length that follows a marker whose low nibble is 0xF: an int object. */
static BOOL bplist_count(bplist *b, const uint8_t **p, uint64_t *count) {
    uint8_t m = **p;
    *count = m & 0x0F;
    (*p)++;
    if (*count != 0x0F) return YES;
    if (*p >= b->bytes + b->length || (**p & 0xF0) != 0x10) return NO;
    unsigned n = 1u << (**p & 0x0F);
    *count = be_uint(*p + 1, n);
    *p += 1 + n;
    return YES;
}

static id bplist_object(bplist *b, uint64_t ref, int depth) {
    if (ref >= b->count || depth > 512) return nil;
    uint64_t off = be_uint(b->bytes + b->table + ref * b->offset_size, b->offset_size);
    if (off >= b->length) return nil;
    const uint8_t *p = b->bytes + off;
    uint8_t marker = *p;
    switch (marker >> 4) {
    case 0x0:
        if (marker == 0x08) return @NO;
        if (marker == 0x09) return @YES;
        return [NSNull null];
    case 0x1: {
        unsigned n = 1u << (marker & 0x0F);
        uint64_t v = be_uint(p + 1, n > 8 ? 8 : n);
        return n == 8 ? [NSNumber numberWithLongLong:(long long)v] : [NSNumber numberWithUnsignedLongLong:v];
    }
    case 0x2: {
        unsigned n = 1u << (marker & 0x0F);
        uint64_t v = be_uint(p + 1, n);
        if (n == 4) {
            uint32_t w = (uint32_t)v;
            float f;
            memcpy(&f, &w, 4);
            return [NSNumber numberWithFloat:f];
        }
        double d;
        memcpy(&d, &v, 8);
        return [NSNumber numberWithDouble:d];
    }
    case 0x3: {
        uint64_t v = be_uint(p + 1, 8);
        double d;
        memcpy(&d, &v, 8);
        return [NSDate dateWithTimeIntervalSinceReferenceDate:d];
    }
    case 0x4: {
        uint64_t n;
        if (!bplist_count(b, &p, &n) || p + n > b->bytes + b->length) return nil;
        return [NSData dataWithBytes:p length:n];
    }
    case 0x5: {
        uint64_t n;
        if (!bplist_count(b, &p, &n) || p + n > b->bytes + b->length) return nil;
        return [[NSString alloc] initWithBytes:p length:n encoding:NSASCIIStringEncoding];
    }
    case 0x6: {
        uint64_t n;
        if (!bplist_count(b, &p, &n) || p + 2 * n > b->bytes + b->length) return nil;
        unichar *u = malloc(n * sizeof(unichar) + 1);
        for (uint64_t i = 0; i < n; i++) u[i] = (unichar)be_uint(p + 2 * i, 2);
        NSString *s = [[NSString alloc] initWithCharacters:u length:n];
        free(u);
        return s;
    }
    case 0x8:
        return [NSNumber numberWithUnsignedLongLong:be_uint(p + 1, (marker & 0x0F) + 1)];
    case 0xA:
    case 0xC: {
        uint64_t n;
        if (!bplist_count(b, &p, &n) || p + n * b->ref_size > b->bytes + b->length) return nil;
        NSMutableArray *a = [NSMutableArray arrayWithCapacity:n];
        for (uint64_t i = 0; i < n; i++) {
            id o = bplist_object(b, be_uint(p + i * b->ref_size, b->ref_size), depth + 1);
            if (!o) return nil;
            [a addObject:o];
        }
        return (marker >> 4) == 0xC ? [NSSet setWithArray:a] : a;
    }
    case 0xD: {
        uint64_t n;
        if (!bplist_count(b, &p, &n) || p + 2 * n * b->ref_size > b->bytes + b->length) return nil;
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:n];
        for (uint64_t i = 0; i < n; i++) {
            id k = bplist_object(b, be_uint(p + i * b->ref_size, b->ref_size), depth + 1);
            id v = bplist_object(b, be_uint(p + (n + i) * b->ref_size, b->ref_size), depth + 1);
            if (!k || !v) return nil;
            [d setObject:v forKey:k];
        }
        return d;
    }
    }
    return nil;
}

static id parse_binary(const uint8_t *bytes, size_t length) {
    if (length < 8 + 32 || memcmp(bytes, "bplist00", 8)) return nil;
    const uint8_t *t = bytes + length - 32;
    bplist b = {bytes, length, t[6], t[7], be_uint(t + 8, 8), be_uint(t + 16, 8), be_uint(t + 24, 8)};
    if (!b.offset_size || !b.ref_size || b.table + b.count * b.offset_size > length) return nil;
    return bplist_object(&b, b.top, 0);
}

/* ---- XML --------------------------------------------------------------------------- */

typedef struct {
    const char *p, *end;
} xml;

static void skip_space(xml *x) {
    for (;;) {
        while (x->p < x->end && (*x->p == ' ' || *x->p == '\t' || *x->p == '\n' || *x->p == '\r')) x->p++;
        if (x->end - x->p >= 4 && !strncmp(x->p, "<!--", 4)) {
            const char *e = strstr(x->p, "-->");
            x->p = e ? e + 3 : x->end;
            continue;
        }
        if (x->end - x->p >= 2 && (!strncmp(x->p, "<?", 2) || !strncmp(x->p, "<!", 2))) {
            const char *e = memchr(x->p, '>', x->end - x->p);
            x->p = e ? e + 1 : x->end;
            continue;
        }
        return;
    }
}

/* Reads "<name ...>" or "<name/>"; returns the name length, sets *empty. */
static size_t open_tag(xml *x, const char **name, BOOL *empty) {
    skip_space(x);
    if (x->p >= x->end || *x->p != '<' || (x->p + 1 < x->end && x->p[1] == '/')) return 0;
    const char *n = x->p + 1, *q = n;
    while (q < x->end && *q != '>' && *q != ' ' && *q != '/') q++;
    const char *close = memchr(q, '>', x->end - q);
    if (!close) return 0;
    *empty = close > x->p && close[-1] == '/';
    *name = n;
    x->p = close + 1;
    return (size_t)(q - n);
}

static BOOL close_tag(xml *x, const char *name, size_t len) {
    skip_space(x);
    if (x->end - x->p < (long)len + 3 || strncmp(x->p, "</", 2) || strncmp(x->p + 2, name, len)) return NO;
    x->p += 2 + len;
    while (x->p < x->end && *x->p != '>') x->p++;
    if (x->p < x->end) x->p++;
    return YES;
}

/* Text up to the next '<', with the five predefined entities decoded. */
static NSString *text_until_tag(xml *x) {
    const char *start = x->p;
    while (x->p < x->end && *x->p != '<') x->p++;
    NSMutableString *s = [NSMutableString string];
    const char *run = start;
    for (const char *c = start; c < x->p; c++) {
        if (*c != '&') continue;
        [s appendString:[[NSString alloc] initWithBytes:run length:c - run encoding:NSUTF8StringEncoding]];
        const char *semi = memchr(c, ';', x->p - c);
        if (!semi) { run = c; break; }
        size_t n = semi - c - 1;
        const char *e = c + 1;
        if (n == 3 && !strncmp(e, "amp", 3)) [s appendString:@"&"];
        else if (n == 2 && !strncmp(e, "lt", 2)) [s appendString:@"<"];
        else if (n == 2 && !strncmp(e, "gt", 2)) [s appendString:@">"];
        else if (n == 4 && !strncmp(e, "quot", 4)) [s appendString:@"\""];
        else if (n == 4 && !strncmp(e, "apos", 4)) [s appendString:@"'"];
        else if (*e == '#') {
            unsigned long v = e[1] == 'x' ? strtoul(e + 2, NULL, 16) : strtoul(e + 1, NULL, 10);
            unichar u = (unichar)v;
            [s appendString:[NSString stringWithCharacters:&u length:1]];
        }
        c = semi;
        run = semi + 1;
    }
    if (run < x->p) [s appendString:[[NSString alloc] initWithBytes:run length:x->p - run encoding:NSUTF8StringEncoding]];
    return s;
}

static id xml_value(xml *x, int depth);

static NSData *base64(NSString *s) {
    NSString *compact = [[s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        componentsJoinedByString:@""];
    return [[NSData alloc] initWithBase64EncodedString:compact options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

static id xml_value(xml *x, int depth) {
    const char *name;
    BOOL empty;
    size_t len = open_tag(x, &name, &empty);
    if (!len || depth > 512) return nil;
#define IS(t) (len == sizeof(t) - 1 && !strncmp(name, t, len))
    if (IS("true")) { if (!empty) close_tag(x, name, len); return @YES; }
    if (IS("false")) { if (!empty) close_tag(x, name, len); return @NO; }
    if (IS("array")) {
        NSMutableArray *a = [NSMutableArray array];
        if (empty) return a;
        for (;;) {
            if (close_tag(x, "array", 5)) return a;
            id v = xml_value(x, depth + 1);
            if (!v) return nil;
            [a addObject:v];
        }
    }
    if (IS("dict")) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        if (empty) return d;
        for (;;) {
            if (close_tag(x, "dict", 4)) return d;
            const char *kn;
            BOOL ke;
            size_t kl = open_tag(x, &kn, &ke);
            if (kl != 3 || strncmp(kn, "key", 3)) return nil;
            NSString *key = ke ? @"" : text_until_tag(x);
            if (!ke && !close_tag(x, "key", 3)) return nil;
            id v = xml_value(x, depth + 1);
            if (!v) return nil;
            [d setObject:v forKey:key];
        }
    }
    NSString *t = empty ? @"" : text_until_tag(x);
    if (!empty && !close_tag(x, name, len)) return nil;
    if (IS("string")) return t;
    if (IS("integer")) return [NSNumber numberWithLongLong:strtoll(t.UTF8String, NULL, 10)];
    if (IS("real")) return [NSNumber numberWithDouble:strtod(t.UTF8String, NULL)];
    if (IS("data")) return base64(t);
    if (IS("date")) {
        struct tm tm = {0};
        if (sscanf(t.UTF8String, "%d-%d-%dT%d:%d:%dZ", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min,
                   &tm.tm_sec) == 6) {
            tm.tm_year -= 1900;
            tm.tm_mon -= 1;
            return [NSDate dateWithTimeIntervalSince1970:(double)timegm(&tm)];
        }
        return nil;
    }
#undef IS
    return nil;
}

static id parse_xml(const char *bytes, size_t length) {
    xml x = {bytes, bytes + length};
    const char *name;
    BOOL empty;
    size_t len = open_tag(&x, &name, &empty);
    if (len == 5 && !strncmp(name, "plist", 5)) {
        if (empty) return nil;
        id v = xml_value(&x, 0);
        close_tag(&x, "plist", 5);
        return v;
    }
    x.p = bytes; /* a bare value */
    return xml_value(&x, 0);
}

/* ---- writing (XML) --------------------------------------------------------------------- */

static void xml_escape(NSMutableString *out, NSString *s) {
    NSUInteger n = s.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '&') [out appendString:@"&amp;"];
        else if (c == '<') [out appendString:@"&lt;"];
        else if (c == '>') [out appendString:@"&gt;"];
        else [out appendString:[NSString stringWithCharacters:&c length:1]];
    }
}

static BOOL xml_write(NSMutableString *out, id v, int indent) {
    NSMutableString *pad = [NSMutableString string];
    for (int i = 0; i < indent; i++) [pad appendString:@"\t"];
    if ([v isKindOfClass:[NSString class]]) {
        [out appendFormat:@"%@<string>", pad];
        xml_escape(out, v);
        [out appendString:@"</string>\n"];
    } else if ([v isKindOfClass:[NSNumber class]]) {
        const char *type = [v objCType];
        if (v == (id)kCFBooleanTrue || v == (id)kCFBooleanFalse || !strcmp(type, "c") || !strcmp(type, "B"))
            [out appendFormat:@"%@<%@/>\n", pad, [v boolValue] ? @"true" : @"false"];
        else if (!strcmp(type, "f") || !strcmp(type, "d"))
            [out appendFormat:@"%@<real>%.17g</real>\n", pad, [v doubleValue]];
        else
            [out appendFormat:@"%@<integer>%lld</integer>\n", pad, [v longLongValue]];
    } else if ([v isKindOfClass:[NSData class]]) {
        [out appendFormat:@"%@<data>%@</data>\n", pad, [v base64EncodedStringWithOptions:0]];
    } else if ([v isKindOfClass:[NSDate class]]) {
        time_t t = (time_t)[v timeIntervalSince1970];
        struct tm tm;
        gmtime_r(&t, &tm);
        char buf[32];
        strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%SZ", &tm);
        [out appendFormat:@"%@<date>%s</date>\n", pad, buf];
    } else if ([v isKindOfClass:[NSArray class]]) {
        [out appendFormat:@"%@<array>\n", pad];
        for (id e in (NSArray *)v)
            if (!xml_write(out, e, indent + 1)) return NO;
        [out appendFormat:@"%@</array>\n", pad];
    } else if ([v isKindOfClass:[NSDictionary class]]) {
        [out appendFormat:@"%@<dict>\n", pad];
        NSArray *keys = [[(NSDictionary *)v allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (id k in keys) {
            if (![k isKindOfClass:[NSString class]]) return NO;
            [out appendFormat:@"%@\t<key>", pad];
            xml_escape(out, k);
            [out appendString:@"</key>\n"];
            if (!xml_write(out, [(NSDictionary *)v objectForKey:k], indent + 1)) return NO;
        }
        [out appendFormat:@"%@</dict>\n", pad];
    } else {
        return NO;
    }
    return YES;
}

/* ---- NSPropertyListSerialization ----------------------------------------------------------- */

@implementation NSPropertyListSerialization
+ (id)propertyListWithData:(NSData *)data options:(NSPropertyListReadOptions)opt
                    format:(NSPropertyListFormat *)format error:(NSError **)error {
    const uint8_t *b = data.bytes;
    size_t n = data.length;
    id v = nil;
    NSPropertyListFormat f = NSPropertyListXMLFormat_v1_0;
    if (n >= 8 && !memcmp(b, "bplist00", 8)) {
        v = parse_binary(b, n);
        f = NSPropertyListBinaryFormat_v1_0;
    } else {
        v = parse_xml((const char *)b, n);
    }
    if (!v) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError
                                     userInfo:@{NSLocalizedDescriptionKey : @"The data couldn’t be read because it isn’t in the correct format."}];
        return nil;
    }
    if (format) *format = f;
    if (opt & (NSPropertyListMutableContainers | NSPropertyListMutableContainersAndLeaves)) {
        if ([v isKindOfClass:[NSDictionary class]]) v = [v mutableCopy];
        else if ([v isKindOfClass:[NSArray class]]) v = [v mutableCopy];
    }
    return v;
}
+ (NSData *)dataWithPropertyList:(id)plist format:(NSPropertyListFormat)format
                         options:(NSPropertyListWriteOptions)opt error:(NSError **)error {
    NSMutableString *out = [NSMutableString stringWithString:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"];
    if (!xml_write(out, plist, 0)) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:3851 userInfo:nil];
        return nil;
    }
    [out appendString:@"</plist>\n"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}
+ (BOOL)propertyList:(id)plist isValidForFormat:(NSPropertyListFormat)format {
    NSMutableString *scratch = [NSMutableString string];
    return xml_write(scratch, plist, 0);
}
@end
