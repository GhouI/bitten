#import "FoundationInternal.h"

/* Membership bitmap for the Basic Multilingual Plane. Categories outside
 * ASCII/Latin-1 are approximated: code points above U+00BF count as letters
 * unless they fall in known punctuation, symbol or space blocks. */
@interface NSCharacterSet () {
  @public
    uint8_t _bits[8192];
}
@end

static void set_bit(NSCharacterSet *s, unichar c, BOOL on) {
    if (on) s->_bits[c >> 3] |= (uint8_t)(1 << (c & 7));
    else s->_bits[c >> 3] &= (uint8_t)~(1 << (c & 7));
}
static BOOL is_space(unichar c) { return c == ' ' || c == '\t' || c == 0xa0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200a) || c == 0x202f || c == 0x205f || c == 0x3000; }
static BOOL is_newline(unichar c) { return (c >= 0x0a && c <= 0x0d) || c == 0x85 || c == 0x2028 || c == 0x2029; }
static BOOL is_upper(unichar c) { return (c >= 'A' && c <= 'Z') || (c >= 0xc0 && c <= 0xde && c != 0xd7); }
static BOOL is_lower(unichar c) { return (c >= 'a' && c <= 'z') || (c >= 0xdf && c <= 0xff && c != 0xf7); }
static BOOL is_punct(unichar c) {
    return (c >= 0x21 && c <= 0x2f && c != '$' && c != '+') || (c >= 0x3a && c <= 0x40 && c != '<' && c != '=' && c != '>') ||
           (c >= 0x5b && c <= 0x60 && c != '^' && c != '`') || c == '{' || c == '}' || c == 0xa1 || c == 0xa7 || c == 0xab ||
           c == 0xb6 || c == 0xb7 || c == 0xbb || c == 0xbf || (c >= 0x2010 && c <= 0x2027) || (c >= 0x3001 && c <= 0x3003);
}
static BOOL is_letter(unichar c) {
    if (c < 0x80) return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
    if (c < 0xc0) return c == 0xaa || c == 0xb5 || c == 0xba;
    if (c == 0xd7 || c == 0xf7) return NO;
    if (c >= 0x2000 && c <= 0x2bff) return NO; /* punctuation, symbols, arrows, math */
    if (c >= 0x3000 && c <= 0x303f) return NO; /* CJK punctuation */
    if (c >= 0xd800 && c <= 0xf8ff) return NO; /* surrogates, private use */
    if (c >= 0xfe00) return c >= 0xff21 && c <= 0xffdc;
    return YES;
}

static NSCharacterSet *build(BOOL (*test)(unichar)) {
    NSCharacterSet *s = [NSCharacterSet new];
    for (unsigned c = 0; c < 65536; c++) if (test((unichar)c)) set_bit(s, (unichar)c, YES);
    return s;
}
static BOOL t_ws(unichar c) { return is_space(c); }
static BOOL t_wsnl(unichar c) { return is_space(c) || is_newline(c); }
static BOOL t_digit(unichar c) { return c >= '0' && c <= '9'; }
static BOOL t_alnum(unichar c) { return is_letter(c) || (c >= '0' && c <= '9'); }
static BOOL t_control(unichar c) { return c < 0x20 || (c >= 0x7f && c <= 0x9f); }

#define SHARED(name, test)                                   \
    +(NSCharacterSet *)name {                                \
        static NSCharacterSet *shared;                       \
        @synchronized([NSCharacterSet class]) {              \
            if (!shared) shared = build(test);               \
        }                                                    \
        return shared;                                       \
    }

@implementation NSCharacterSet
SHARED(whitespaceCharacterSet, t_ws)
SHARED(whitespaceAndNewlineCharacterSet, t_wsnl)
SHARED(newlineCharacterSet, is_newline)
SHARED(decimalDigitCharacterSet, t_digit)
SHARED(letterCharacterSet, is_letter)
SHARED(alphanumericCharacterSet, t_alnum)
SHARED(uppercaseLetterCharacterSet, is_upper)
SHARED(lowercaseLetterCharacterSet, is_lower)
SHARED(punctuationCharacterSet, is_punct)
SHARED(controlCharacterSet, t_control)
+ (instancetype)characterSetWithCharactersInString:(NSString *)string {
    NSCharacterSet *s = [self new];
    NSUInteger n = string.length;
    for (NSUInteger i = 0; i < n; i++) set_bit(s, [string characterAtIndex:i], YES);
    return s;
}
+ (instancetype)characterSetWithRange:(NSRange)range {
    NSCharacterSet *s = [self new];
    for (NSUInteger c = range.location; c < NSMaxRange(range) && c < 65536; c++) set_bit(s, (unichar)c, YES);
    return s;
}
- (BOOL)characterIsMember:(unichar)c { return (_bits[c >> 3] >> (c & 7)) & 1; }
- (NSCharacterSet *)invertedSet {
    NSCharacterSet *s = [NSCharacterSet new];
    for (int i = 0; i < 8192; i++) s->_bits[i] = (uint8_t)~_bits[i];
    return s;
}
- (id)copyWithZone:(NSZone *)zone {
    NSCharacterSet *s = [NSCharacterSet new];
    memcpy(s->_bits, _bits, sizeof _bits);
    return s;
}
- (id)mutableCopyWithZone:(NSZone *)zone {
    NSMutableCharacterSet *s = [NSMutableCharacterSet new];
    memcpy(s->_bits, _bits, sizeof _bits);
    return s;
}
- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:[NSCharacterSet class]] && !memcmp(((NSCharacterSet *)other)->_bits, _bits, sizeof _bits);
}
@end

@implementation NSMutableCharacterSet
- (void)addCharactersInString:(NSString *)string {
    for (NSUInteger i = 0; i < string.length; i++) set_bit(self, [string characterAtIndex:i], YES);
}
- (void)removeCharactersInString:(NSString *)string {
    for (NSUInteger i = 0; i < string.length; i++) set_bit(self, [string characterAtIndex:i], NO);
}
- (void)addCharactersInRange:(NSRange)range {
    for (NSUInteger c = range.location; c < NSMaxRange(range) && c < 65536; c++) set_bit(self, (unichar)c, YES);
}
- (void)removeCharactersInRange:(NSRange)range {
    for (NSUInteger c = range.location; c < NSMaxRange(range) && c < 65536; c++) set_bit(self, (unichar)c, NO);
}
- (void)formUnionWithCharacterSet:(NSCharacterSet *)other {
    for (int i = 0; i < 8192; i++) _bits[i] |= other->_bits[i];
}
- (void)invert {
    for (int i = 0; i < 8192; i++) _bits[i] = (uint8_t)~_bits[i];
}
- (id)copyWithZone:(NSZone *)zone {
    NSCharacterSet *s = [NSCharacterSet new];
    memcpy(s->_bits, _bits, sizeof _bits);
    return s;
}
@end

@implementation NSString (CharacterSets)
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set {
    NSUInteger n = self.length;
    for (NSUInteger i = 0; i < n; i++)
        if ([set characterIsMember:[self characterAtIndex:i]]) return NSMakeRange(i, 1);
    return NSMakeRange(NSNotFound, 0);
}
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set {
    NSUInteger n = self.length, start = 0, end;
    if (!n) return @"";
    unichar *chars = malloc(n * sizeof(unichar));
    [self getCharacters:chars range:NSMakeRange(0, n)];
    while (start < n && [set characterIsMember:chars[start]]) start++;
    end = n;
    while (end > start && [set characterIsMember:chars[end - 1]]) end--;
    NSString *r = [[NSString alloc] initWithCharacters:chars + start length:end - start];
    free(chars);
    return r;
}
- (NSArray<NSString *> *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)set {
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger n = self.length, start = 0;
    unichar *chars = malloc((n ? n : 1) * sizeof(unichar));
    [self getCharacters:chars range:NSMakeRange(0, n)];
    for (NSUInteger i = 0; i <= n; i++) {
        if (i == n || [set characterIsMember:chars[i]]) {
            [parts addObject:[[NSString alloc] initWithCharacters:chars + start length:i - start]];
            start = i + 1;
        }
    }
    free(chars);
    return parts;
}
- (NSString *)capitalizedString {
    NSUInteger n = self.length;
    if (!n) return @"";
    unichar *chars = malloc(n * sizeof(unichar));
    [self getCharacters:chars range:NSMakeRange(0, n)];
    BOOL start = YES;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = chars[i];
        if (is_letter(c)) {
            if (start && is_lower(c) && c != 0xdf && c != 0xff) chars[i] = c - 32;
            else if (!start && is_upper(c)) chars[i] = c + 32;
            start = NO;
        } else if (c != '\'') start = YES;
    }
    NSString *r = [[NSString alloc] initWithCharacters:chars length:n];
    free(chars);
    return r;
}
- (NSString *)stringByPaddingToLength:(NSUInteger)length withString:(NSString *)pad startingAtIndex:(NSUInteger)index {
    NSUInteger n = self.length;
    if (length <= n) return [self substringToIndex:length];
    if (!pad.length) BNRaise("NSInvalidArgumentException", "-[NSString stringByPaddingToLength:withString:startingAtIndex:]: empty pad string");
    NSMutableString *s = [self mutableCopy];
    while (s.length < length) {
        unichar c = [pad characterAtIndex:index++ % pad.length];
        [s appendString:[[NSString alloc] initWithCharacters:&c length:1]];
    }
    return s;
}
@end
