#import "FoundationInternal.h"

/* ---- writer ---- */
static BOOL is_real_number(id o) { return [o isKindOfClass:[NSNumber class]]; }

static BOOL valid_json(id o, BOOL top) {
    if ([o isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)o) if (!valid_json(e, NO)) return NO;
        return YES;
    }
    if ([o isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)o)
            if (![k isKindOfClass:[NSString class]] || !valid_json([(NSDictionary *)o objectForKey:k], NO)) return NO;
        return YES;
    }
    if (top) return NO;
    if ([o isKindOfClass:[NSString class]] || o == [NSNull null]) return YES;
    if (is_real_number(o)) {
        double d = [o doubleValue];
        return d == d && d - d == 0; /* no NaN or infinity */
    }
    return NO;
}

static void write_string(NSMutableString *out, NSString *s, NSJSONWritingOptions options) {
    [out appendString:@"\""];
    NSUInteger n = s.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
        case '"': [out appendString:@"\\\""]; break;
        case '\\': [out appendString:@"\\\\"]; break;
        case '\n': [out appendString:@"\\n"]; break;
        case '\r': [out appendString:@"\\r"]; break;
        case '\t': [out appendString:@"\\t"]; break;
        case '\b': [out appendString:@"\\b"]; break;
        case '\f': [out appendString:@"\\f"]; break;
        case '/':
            [out appendString:(options & NSJSONWritingWithoutEscapingSlashes) ? @"/" : @"\\/"];
            break;
        default:
            if (c < 0x20) [out appendFormat:@"\\u%04x", c];
            else [out appendString:[[NSString alloc] initWithCharacters:&c length:1]];
        }
    }
    [out appendString:@"\""];
}

static void write_value(NSMutableString *out, id o, NSJSONWritingOptions options, int depth) {
    BOOL pretty = (options & NSJSONWritingPrettyPrinted) != 0;
    NSString *indent = pretty ? [@"" stringByPaddingToLength:(NSUInteger)(depth + 1) * 2 withString:@" " startingAtIndex:0] : @"";
    NSString *outdent = pretty ? [@"" stringByPaddingToLength:(NSUInteger)depth * 2 withString:@" " startingAtIndex:0] : @"";
    if ([o isKindOfClass:[NSString class]]) {
        write_string(out, o, options);
    } else if (o == [NSNull null]) {
        [out appendString:@"null"];
    } else if (is_real_number(o)) {
        NSNumber *n = o;
        if (CFGetTypeID((__bridge CFTypeRef)n) == CFBooleanGetTypeID()) [out appendString:n.boolValue ? @"true" : @"false"];
        else [out appendString:n.stringValue];
    } else if ([o isKindOfClass:[NSArray class]]) {
        NSArray *a = o;
        if (!a.count) { [out appendString:@"[]"]; return; }
        [out appendString:pretty ? @"[\n" : @"["];
        for (NSUInteger i = 0; i < a.count; i++) {
            [out appendString:indent];
            write_value(out, a[i], options, depth + 1);
            if (i + 1 < a.count) [out appendString:@","];
            if (pretty) [out appendString:@"\n"];
        }
        [out appendFormat:@"%@]", outdent];
    } else {
        NSDictionary *d = o;
        if (!d.count) { [out appendString:@"{}"]; return; }
        NSArray *keys = d.allKeys;
        if (options & NSJSONWritingSortedKeys) keys = [keys sortedArrayUsingSelector:@selector(compare:)];
        [out appendString:pretty ? @"{\n" : @"{"];
        for (NSUInteger i = 0; i < keys.count; i++) {
            [out appendString:indent];
            write_string(out, keys[i], options);
            [out appendString:pretty ? @" : " : @":"];
            write_value(out, d[keys[i]], options, depth + 1);
            if (i + 1 < keys.count) [out appendString:@","];
            if (pretty) [out appendString:@"\n"];
        }
        [out appendFormat:@"%@}", outdent];
    }
}

/* ---- parser ---- */
struct parser {
    const unsigned char *p, *end;
    BOOL mutable_containers, mutable_leaves;
    const char *error;
};

static void skip_ws(struct parser *ps) {
    while (ps->p < ps->end && (*ps->p == ' ' || *ps->p == '\t' || *ps->p == '\n' || *ps->p == '\r')) ps->p++;
}
static id parse_value(struct parser *ps, int depth);

static int hex4(struct parser *ps) {
    if (ps->end - ps->p < 4) return -1;
    int v = 0;
    for (int i = 0; i < 4; i++) {
        unsigned char c = *ps->p++;
        v <<= 4;
        if (c >= '0' && c <= '9') v |= c - '0';
        else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
        else return -1;
    }
    return v;
}

static NSString *parse_string(struct parser *ps) {
    ps->p++; /* opening quote */
    NSMutableData *utf16 = [NSMutableData data];
    NSMutableData *raw = [NSMutableData data]; /* pending UTF-8 run */
    void (^flush)(void) = ^{
        if (!raw.length) return;
        NSString *chunk = [[NSString alloc] initWithBytes:raw.bytes length:raw.length encoding:NSUTF8StringEncoding];
        if (chunk) {
            NSUInteger n = chunk.length;
            NSUInteger at = utf16.length;
            [utf16 increaseLengthBy:n * 2];
            [chunk getCharacters:(unichar *)((char *)utf16.mutableBytes + at) range:NSMakeRange(0, n)];
        }
        raw.length = 0;
    };
    while (ps->p < ps->end) {
        unsigned char c = *ps->p++;
        if (c == '"') {
            flush();
            NSString *s = [[NSString alloc] initWithCharacters:utf16.bytes length:utf16.length / 2];
            return ps->mutable_leaves ? [s mutableCopy] : s;
        }
        if (c < 0x20) { ps->error = "control character in string"; return nil; }
        if (c != '\\') {
            [raw appendBytes:&c length:1];
            continue;
        }
        if (ps->p >= ps->end) break;
        unsigned char e = *ps->p++;
        unichar out;
        switch (e) {
        case '"': out = '"'; break;
        case '\\': out = '\\'; break;
        case '/': out = '/'; break;
        case 'b': out = '\b'; break;
        case 'f': out = '\f'; break;
        case 'n': out = '\n'; break;
        case 'r': out = '\r'; break;
        case 't': out = '\t'; break;
        case 'u': {
            int v = hex4(ps);
            if (v < 0) { ps->error = "bad \\u escape"; return nil; }
            out = (unichar)v;
            break;
        }
        default: ps->error = "bad escape"; return nil;
        }
        flush();
        [utf16 appendBytes:&out length:2];
    }
    ps->error = "unterminated string";
    return nil;
}

static id parse_number(struct parser *ps) {
    const unsigned char *start = ps->p;
    BOOL is_float = NO;
    if (ps->p < ps->end && *ps->p == '-') ps->p++;
    if (ps->p >= ps->end || *ps->p < '0' || *ps->p > '9') { ps->error = "bad number"; return nil; }
    while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9') ps->p++;
    if (ps->p < ps->end && *ps->p == '.') {
        is_float = YES;
        ps->p++;
        if (ps->p >= ps->end || *ps->p < '0' || *ps->p > '9') { ps->error = "bad number"; return nil; }
        while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9') ps->p++;
    }
    if (ps->p < ps->end && (*ps->p == 'e' || *ps->p == 'E')) {
        is_float = YES;
        ps->p++;
        if (ps->p < ps->end && (*ps->p == '+' || *ps->p == '-')) ps->p++;
        if (ps->p >= ps->end || *ps->p < '0' || *ps->p > '9') { ps->error = "bad number"; return nil; }
        while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9') ps->p++;
    }
    char buf[64];
    size_t n = (size_t)(ps->p - start);
    if (n >= sizeof buf) is_float = YES, n = sizeof buf - 1;
    memcpy(buf, start, n);
    buf[n] = 0;
    if (!is_float && n < 19) return [NSNumber numberWithLongLong:strtoll(buf, NULL, 10)];
    return [NSNumber numberWithDouble:strtod(buf, NULL)];
}

static BOOL literal(struct parser *ps, const char *word) {
    size_t n = strlen(word);
    if ((size_t)(ps->end - ps->p) < n || memcmp(ps->p, word, n)) return NO;
    ps->p += n;
    return YES;
}

static id parse_value(struct parser *ps, int depth) {
    if (depth > 512) { ps->error = "nesting too deep"; return nil; }
    skip_ws(ps);
    if (ps->p >= ps->end) { ps->error = "unexpected end of data"; return nil; }
    unsigned char c = *ps->p;
    if (c == '"') return parse_string(ps);
    if (c == '{') {
        ps->p++;
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        skip_ws(ps);
        if (ps->p < ps->end && *ps->p == '}') { ps->p++; return ps->mutable_containers ? d : [d copy]; }
        for (;;) {
            skip_ws(ps);
            if (ps->p >= ps->end || *ps->p != '"') { ps->error = "expected a string key"; return nil; }
            NSString *key = parse_string(ps);
            if (!key) return nil;
            skip_ws(ps);
            if (ps->p >= ps->end || *ps->p++ != ':') { ps->error = "expected ':'"; return nil; }
            id value = parse_value(ps, depth + 1);
            if (!value) return nil;
            d[key] = value;
            skip_ws(ps);
            if (ps->p < ps->end && *ps->p == ',') { ps->p++; continue; }
            if (ps->p < ps->end && *ps->p == '}') { ps->p++; break; }
            ps->error = "expected ',' or '}'";
            return nil;
        }
        return ps->mutable_containers ? d : [d copy];
    }
    if (c == '[') {
        ps->p++;
        NSMutableArray *a = [NSMutableArray array];
        skip_ws(ps);
        if (ps->p < ps->end && *ps->p == ']') { ps->p++; return ps->mutable_containers ? a : [a copy]; }
        for (;;) {
            id value = parse_value(ps, depth + 1);
            if (!value) return nil;
            [a addObject:value];
            skip_ws(ps);
            if (ps->p < ps->end && *ps->p == ',') { ps->p++; continue; }
            if (ps->p < ps->end && *ps->p == ']') { ps->p++; break; }
            ps->error = "expected ',' or ']'";
            return nil;
        }
        return ps->mutable_containers ? a : [a copy];
    }
    if (literal(ps, "true")) return @YES;
    if (literal(ps, "false")) return @NO;
    if (literal(ps, "null")) return [NSNull null];
    if (c == '-' || (c >= '0' && c <= '9')) return parse_number(ps);
    ps->error = "unexpected character";
    return nil;
}

@implementation NSJSONSerialization
+ (BOOL)isValidJSONObject:(id)object { return valid_json(object, YES); }
+ (NSData *)dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error {
    BOOL fragment_ok = (options & NSJSONWritingFragmentsAllowed) != 0;
    if (!(valid_json(object, YES) || (fragment_ok && valid_json(object, NO))))
        BNRaise("NSInvalidArgumentException", "*** +[NSJSONSerialization dataWithJSONObject:options:error:]: Invalid top-level type in JSON write");
    NSMutableString *out = [NSMutableString string];
    write_value(out, object, options, 0);
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error {
    if (!data) BNRaise("NSInvalidArgumentException", "+[NSJSONSerialization JSONObjectWithData:options:error:]: data parameter is nil");
    const unsigned char *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) bytes += 3, length -= 3;
    struct parser ps = {bytes, bytes + length, (options & NSJSONReadingMutableContainers) != 0,
                        (options & NSJSONReadingMutableLeaves) != 0, NULL};
    id value = parse_value(&ps, 0);
    if (value) {
        skip_ws(&ps);
        if (ps.p != ps.end) { value = nil; ps.error = "garbage after the JSON value"; }
        else if (!(options & NSJSONReadingFragmentsAllowed) && ![value isKindOfClass:[NSArray class]] &&
                 ![value isKindOfClass:[NSDictionary class]]) {
            value = nil;
            ps.error = "JSON text did not start with array or object and option to allow fragments not set";
        }
    }
    if (!value && error) {
        NSString *msg = [NSString stringWithFormat:@"The data couldn’t be read because it isn’t in the correct format: %s around character %ld.",
                         ps.error ?: "invalid JSON", (long)(ps.p - bytes)];
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError
                                 userInfo:@{NSLocalizedDescriptionKey: msg}];
    }
    return value;
}
@end
