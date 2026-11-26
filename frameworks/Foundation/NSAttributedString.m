/* NSAttributedString and NSMutableAttributedString, toll-free bridged to
 * CFAttributedString: the concrete class (__NSCFAttributedString) is the
 * CF type's, and these methods call CF. */

#import <Foundation/Foundation.h>

static CFAttributedStringRef CF(id s) { return (__bridge CFAttributedStringRef)s; }
static CFMutableAttributedStringRef MCF(id s) { return (__bridge CFMutableAttributedStringRef)s; }
static BOOL wants_mutable(id self) { return [self isKindOfClass:[NSMutableAttributedString class]]; }

/* Wraps a +1 CF attributed string as the result of an initialiser. Both
 * classes share one concrete class; a mutable request gets a mutable CF
 * object. */
static id adopt(id self, CFAttributedStringRef a) {
    if (!a) return nil;
    if (wants_mutable(self)) {
        CFMutableAttributedStringRef m = CFAttributedStringCreateMutableCopy(NULL, 0, a);
        CFRelease(a);
        return (__bridge_transfer id)m;
    }
    return (__bridge_transfer id)a;
}
static void check(id s, NSRange r, const char *what) {
    if (NSMaxRange(r) > [s length])
        [NSException raise:NSRangeException format:@"-[NSAttributedString %s]: range {%lu, %lu} out of bounds; length %lu",
                                                    what, (unsigned long)r.location, (unsigned long)r.length,
                                                    (unsigned long)[s length]];
}

@implementation NSAttributedString (Foundation)
- (instancetype)init { return [self initWithString:@""]; }
- (instancetype)initWithString:(NSString *)str { return [self initWithString:str attributes:nil]; }
- (instancetype)initWithString:(NSString *)str attributes:(NSDictionary *)attrs {
    return adopt(self, CFAttributedStringCreate(NULL, (__bridge CFStringRef)(str ?: @""),
                                                (__bridge CFDictionaryRef)(attrs ?: @{})));
}
- (instancetype)initWithAttributedString:(NSAttributedString *)a {
    return adopt(self, CFAttributedStringCreateCopy(NULL, CF(a)));
}
- (NSString *)string { return [(__bridge NSString *)CFAttributedStringGetString(CF(self)) copy]; }
- (NSUInteger)length { return (NSUInteger)CFAttributedStringGetLength(CF(self)); }
- (NSDictionary *)attributesAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)range {
    if (i >= self.length) check(self, NSMakeRange(i, 1), "attributesAtIndex:effectiveRange:");
    CFRange r;
    CFDictionaryRef d = CFAttributedStringGetAttributes(CF(self), (CFIndex)i, &r);
    if (range) *range = NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length);
    return d ? (__bridge NSDictionary *)d : @{};
}
- (id)attribute:(NSAttributedStringKey)name atIndex:(NSUInteger)i effectiveRange:(NSRangePointer)range {
    if (i >= self.length) check(self, NSMakeRange(i, 1), "attribute:atIndex:effectiveRange:");
    CFRange r;
    CFTypeRef v = CFAttributedStringGetAttribute(CF(self), (CFIndex)i, (__bridge CFStringRef)name, &r);
    if (range) *range = NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length);
    return (__bridge id)v;
}
/* The longest range around `i`, within `limit`, with the same attributes. */
- (NSDictionary *)attributesAtIndex:(NSUInteger)i longestEffectiveRange:(NSRangePointer)range inRange:(NSRange)limit {
    NSRange r;
    NSDictionary *d = [self attributesAtIndex:i effectiveRange:&r];
    if (range) {
        NSUInteger lo = r.location, hi = NSMaxRange(r);
        while (lo > limit.location) {
            NSRange p;
            if (![[self attributesAtIndex:lo - 1 effectiveRange:&p] isEqual:d]) break;
            lo = p.location;
        }
        while (hi < NSMaxRange(limit)) {
            NSRange n;
            if (![[self attributesAtIndex:hi effectiveRange:&n] isEqual:d]) break;
            hi = NSMaxRange(n);
        }
        lo = MAX(lo, limit.location);
        hi = MIN(hi, NSMaxRange(limit));
        *range = NSMakeRange(lo, hi - lo);
    }
    return d;
}
- (id)attribute:(NSAttributedStringKey)name atIndex:(NSUInteger)i longestEffectiveRange:(NSRangePointer)range
        inRange:(NSRange)limit {
    NSRange r;
    id v = [self attribute:name atIndex:i effectiveRange:&r];
    if (range) {
        NSUInteger lo = r.location, hi = NSMaxRange(r);
        while (lo > limit.location) {
            NSRange p;
            id w = [self attribute:name atIndex:lo - 1 effectiveRange:&p];
            if (!(w == v || [w isEqual:v])) break;
            lo = p.location;
        }
        while (hi < NSMaxRange(limit)) {
            NSRange n;
            id w = [self attribute:name atIndex:hi effectiveRange:&n];
            if (!(w == v || [w isEqual:v])) break;
            hi = NSMaxRange(n);
        }
        lo = MAX(lo, limit.location);
        hi = MIN(hi, NSMaxRange(limit));
        *range = NSMakeRange(lo, hi - lo);
    }
    return v;
}
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range {
    check(self, range, "attributedSubstringFromRange:");
    NSMutableAttributedString *m = [[NSMutableAttributedString alloc]
        initWithString:[self.string substringWithRange:range]];
    NSUInteger i = range.location;
    while (i < NSMaxRange(range)) {
        NSRange r;
        NSDictionary *d = [self attributesAtIndex:i effectiveRange:&r];
        NSUInteger end = MIN(NSMaxRange(r), NSMaxRange(range));
        [m setAttributes:d range:NSMakeRange(i - range.location, end - i)];
        i = end;
    }
    return [m copy];
}
- (void)enumerateAttributesInRange:(NSRange)range options:(NSAttributedStringEnumerationOptions)opts
                        usingBlock:(void (^)(NSDictionary *, NSRange, BOOL *))block {
    check(self, range, "enumerateAttributesInRange:options:usingBlock:");
    NSMutableArray *runs = [NSMutableArray array];
    NSUInteger i = range.location;
    while (i < NSMaxRange(range)) {
        NSRange r;
        NSDictionary *d = (opts & NSAttributedStringEnumerationLongestEffectiveRangeNotRequired)
                              ? [self attributesAtIndex:i effectiveRange:&r]
                              : [self attributesAtIndex:i longestEffectiveRange:&r inRange:range];
        NSUInteger start = MAX(r.location, i), end = MIN(NSMaxRange(r), NSMaxRange(range));
        [runs addObject:@[ d, [NSValue valueWithRange:NSMakeRange(start, end - start)] ]];
        i = end;
    }
    NSEnumerator *e = (opts & NSAttributedStringEnumerationReverse) ? runs.reverseObjectEnumerator : runs.objectEnumerator;
    BOOL stop = NO;
    for (NSArray *run in e) {
        block(run[0], [run[1] rangeValue], &stop);
        if (stop) break;
    }
}
- (void)enumerateAttribute:(NSAttributedStringKey)name inRange:(NSRange)range
                   options:(NSAttributedStringEnumerationOptions)opts
                usingBlock:(void (^)(id, NSRange, BOOL *))block {
    check(self, range, "enumerateAttribute:inRange:options:usingBlock:");
    NSMutableArray *runs = [NSMutableArray array];
    NSUInteger i = range.location;
    while (i < NSMaxRange(range)) {
        NSRange r;
        id v = (opts & NSAttributedStringEnumerationLongestEffectiveRangeNotRequired)
                   ? [self attribute:name atIndex:i effectiveRange:&r]
                   : [self attribute:name atIndex:i longestEffectiveRange:&r inRange:range];
        NSUInteger start = MAX(r.location, i), end = MIN(NSMaxRange(r), NSMaxRange(range));
        [runs addObject:@[ v ?: [NSNull null], [NSValue valueWithRange:NSMakeRange(start, end - start)] ]];
        i = end;
    }
    NSEnumerator *e = (opts & NSAttributedStringEnumerationReverse) ? runs.reverseObjectEnumerator : runs.objectEnumerator;
    BOOL stop = NO;
    for (NSArray *run in e) {
        id v = run[0] == [NSNull null] ? nil : run[0];
        block(v, [run[1] rangeValue], &stop);
        if (stop) break;
    }
}
- (BOOL)isEqualToAttributedString:(NSAttributedString *)o {
    if (o == self) return YES;
    if (![o isKindOfClass:[NSAttributedString class]] || ![self.string isEqualToString:o.string]) return NO;
    NSUInteger i = 0, n = self.length;
    while (i < n) {
        NSRange a, b;
        NSDictionary *x = [self attributesAtIndex:i effectiveRange:&a], *y = [o attributesAtIndex:i effectiveRange:&b];
        if (![x isEqual:y]) return NO;
        i = MIN(NSMaxRange(a), NSMaxRange(b));
    }
    return YES;
}
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSAttributedString class]] && [self isEqualToAttributedString:o]; }
- (NSUInteger)hash { return self.string.hash; }
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFAttributedStringCreateCopy(NULL, CF(self)); }
- (id)mutableCopyWithZone:(NSZone *)zone {
    return (__bridge_transfer id)CFAttributedStringCreateMutableCopy(NULL, 0, CF(self));
}
- (NSString *)description {
    NSMutableString *s = [NSMutableString string];
    NSUInteger i = 0, n = self.length;
    while (i < n) {
        NSRange r;
        NSDictionary *d = [self attributesAtIndex:i effectiveRange:&r];
        [s appendFormat:@"%@%@", [self.string substringWithRange:r], d];
        i = NSMaxRange(r);
    }
    return s;
}
@end

@implementation NSMutableAttributedString (Foundation)
- (NSMutableString *)mutableString {
    /* A snapshot: edits to it do not reach the attributed string. */
    return [self.string mutableCopy];
}
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    check(self, range, "replaceCharactersInRange:withString:");
    CFAttributedStringReplaceString(MCF(self), CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
                                    (__bridge CFStringRef)(str ?: @""));
}
- (void)replaceCharactersInRange:(NSRange)range withAttributedString:(NSAttributedString *)a {
    check(self, range, "replaceCharactersInRange:withAttributedString:");
    CFAttributedStringReplaceAttributedString(MCF(self), CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
                                              CF(a));
}
- (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range {
    check(self, range, "setAttributes:range:");
    CFAttributedStringSetAttributes(MCF(self), CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
                                    (__bridge CFDictionaryRef)(attrs ?: @{}), true);
}
- (void)addAttribute:(NSAttributedStringKey)name value:(id)value range:(NSRange)range {
    if (!value) [NSException raise:NSInvalidArgumentException format:@"-[NSMutableAttributedString addAttribute:value:range:]: nil value"];
    check(self, range, "addAttribute:value:range:");
    CFAttributedStringSetAttribute(MCF(self), CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
                                   (__bridge CFStringRef)name, (__bridge CFTypeRef)value);
}
- (void)addAttributes:(NSDictionary *)attrs range:(NSRange)range {
    check(self, range, "addAttributes:range:");
    CFAttributedStringSetAttributes(MCF(self), CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
                                    (__bridge CFDictionaryRef)attrs, false);
}
- (void)removeAttribute:(NSAttributedStringKey)name range:(NSRange)range {
    check(self, range, "removeAttribute:range:");
    CFAttributedStringRemoveAttribute(MCF(self), CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
                                      (__bridge CFStringRef)name);
}
- (void)insertAttributedString:(NSAttributedString *)a atIndex:(NSUInteger)loc {
    [self replaceCharactersInRange:NSMakeRange(loc, 0) withAttributedString:a];
}
- (void)appendAttributedString:(NSAttributedString *)a {
    [self replaceCharactersInRange:NSMakeRange(self.length, 0) withAttributedString:a];
}
- (void)deleteCharactersInRange:(NSRange)range { [self replaceCharactersInRange:range withString:@""]; }
- (void)setAttributedString:(NSAttributedString *)a {
    [self replaceCharactersInRange:NSMakeRange(0, self.length) withAttributedString:a];
}
- (void)beginEditing { CFAttributedStringBeginEditing(MCF(self)); }
- (void)endEditing { CFAttributedStringEndEditing(MCF(self)); }
@end
