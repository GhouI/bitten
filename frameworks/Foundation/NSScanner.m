/* NSScanner: reading numbers, words and delimited text from a string,
 * front to back. Positions are UTF-16 offsets, as in NSString; characters
 * in charactersToBeSkipped (whitespace and newlines unless set) are passed
 * over before each scan. A scan that finds nothing leaves the position
 * where it was. */

#import "FoundationInternal.h"
#include <limits.h>
#include <math.h>
#include <stdlib.h>

@implementation NSScanner {
    NSString *_string;
    NSUInteger _location;
    NSCharacterSet *_skip;
    BOOL _caseSensitive, _skipSet;
    id _locale;
}

+ (instancetype)scannerWithString:(NSString *)string { return [[self alloc] initWithString:string]; }
+ (id)localizedScannerWithString:(NSString *)string { return [self scannerWithString:string]; }
- (instancetype)initWithString:(NSString *)string {
    if ((self = [super init])) _string = [string copy] ?: @"";
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    NSScanner *c = [[NSScanner alloc] initWithString:_string];
    c->_location = _location;
    c->_skip = _skip;
    c->_skipSet = _skipSet;
    c->_caseSensitive = _caseSensitive;
    c->_locale = _locale;
    return c;
}
- (NSString *)string { return _string; }
- (NSUInteger)scanLocation { return _location; }
- (void)setScanLocation:(NSUInteger)loc {
    if (loc > _string.length) [NSException raise:NSRangeException format:@"scan location %lu beyond end of string", (unsigned long)loc];
    _location = loc;
}
- (NSCharacterSet *)charactersToBeSkipped { return _skipSet ? _skip : [NSCharacterSet whitespaceAndNewlineCharacterSet]; }
- (void)setCharactersToBeSkipped:(NSCharacterSet *)set { _skip = set; _skipSet = YES; }
- (BOOL)caseSensitive { return _caseSensitive; }
- (void)setCaseSensitive:(BOOL)b { _caseSensitive = b; }
- (id)locale { return _locale; }
- (void)setLocale:(id)l { _locale = l; }

/* The position after skipped characters (not stored until a scan works). */
- (NSUInteger)_skipped {
    NSCharacterSet *skip = self.charactersToBeSkipped;
    NSUInteger i = _location, n = _string.length;
    while (skip && i < n && [skip characterIsMember:[_string characterAtIndex:i]]) i++;
    return i;
}
- (BOOL)isAtEnd { return [self _skipped] >= _string.length; }

/* ---- numbers ---- */

/* The longest number text at i: [sign] digits [. digits] [e [sign] digits]
 * (only digits when `integer`). */
- (NSUInteger)_numberEnd:(NSUInteger)i integer:(BOOL)integer {
    NSUInteger n = _string.length, j = i;
    unichar c;
    if (j < n && ((c = [_string characterAtIndex:j]) == '-' || c == '+')) j++;
    NSUInteger digits = 0;
    while (j < n && (c = [_string characterAtIndex:j]) >= '0' && c <= '9') { j++; digits++; }
    if (!integer) {
        NSString *dec = @".";
        if (j < n && [_string characterAtIndex:j] == [dec characterAtIndex:0]) {
            NSUInteger k = j + 1, frac = 0;
            while (k < n && (c = [_string characterAtIndex:k]) >= '0' && c <= '9') { k++; frac++; }
            if (frac || digits) { j = k; digits += frac; }
        }
        if (digits && j < n && ((c = [_string characterAtIndex:j]) == 'e' || c == 'E')) {
            NSUInteger k = j + 1, ed = 0;
            if (k < n && ((c = [_string characterAtIndex:k]) == '-' || c == '+')) k++;
            while (k < n && (c = [_string characterAtIndex:k]) >= '0' && c <= '9') { k++; ed++; }
            if (ed) j = k;
        }
    }
    return digits ? j : i;
}
- (BOOL)_scanText:(NSString **)text integer:(BOOL)integer {
    NSUInteger i = [self _skipped], end = [self _numberEnd:i integer:integer];
    if (end == i) return NO;
    *text = [_string substringWithRange:NSMakeRange(i, end - i)];
    _location = end;
    return YES;
}
- (BOOL)scanLongLong:(long long *)result {
    NSString *t;
    if (![self _scanText:&t integer:YES]) return NO;
    errno = 0;
    long long v = strtoll(t.UTF8String, NULL, 10);
    if (result) *result = v;
    return YES;
}
- (BOOL)scanUnsignedLongLong:(unsigned long long *)result {
    NSUInteger save = _location;
    NSString *t;
    if (![self _scanText:&t integer:YES]) return NO;
    if ([t hasPrefix:@"-"]) { _location = save; return NO; }
    if (result) *result = strtoull(t.UTF8String, NULL, 10);
    return YES;
}
- (BOOL)scanInteger:(NSInteger *)result {
    long long v;
    if (![self scanLongLong:&v]) return NO;
    if (result) *result = (NSInteger)v;
    return YES;
}
- (BOOL)scanInt:(int *)result {
    long long v;
    if (![self scanLongLong:&v]) return NO;
    if (result) *result = v > INT_MAX ? INT_MAX : v < INT_MIN ? INT_MIN : (int)v;
    return YES;
}
- (BOOL)scanDouble:(double *)result {
    NSString *t;
    if (![self _scanText:&t integer:NO]) return NO;
    if (result) *result = strtod(t.UTF8String, NULL);
    return YES;
}
- (BOOL)scanFloat:(float *)result {
    double d;
    if (![self scanDouble:&d]) return NO;
    if (result) *result = (float)d;
    return YES;
}
- (BOOL)scanDecimal:(NSDecimal *)result {
    double d;
    if (![self scanDouble:&d]) return NO;
    if (result) *result = [[NSDecimalNumber alloc] initWithDouble:d].decimalValue;
    return YES;
}
/* Hexadecimal, with or without 0x. */
- (BOOL)scanHexLongLong:(unsigned long long *)result {
    NSUInteger i = [self _skipped], n = _string.length, j = i;
    if (j + 1 < n && [_string characterAtIndex:j] == '0' && ([_string characterAtIndex:j + 1] | 0x20) == 'x') j += 2;
    unsigned long long v = 0;
    NSUInteger start = j;
    for (; j < n; j++) {
        unichar c = [_string characterAtIndex:j];
        int d = c >= '0' && c <= '9' ? c - '0' : (c | 0x20) >= 'a' && (c | 0x20) <= 'f' ? (c | 0x20) - 'a' + 10 : -1;
        if (d < 0) break;
        v = v * 16 + (unsigned)d;
    }
    if (j == start) return NO;
    _location = j;
    if (result) *result = v;
    return YES;
}
- (BOOL)scanHexInt:(unsigned *)result {
    unsigned long long v;
    if (![self scanHexLongLong:&v]) return NO;
    if (result) *result = (unsigned)v;
    return YES;
}
- (BOOL)scanHexDouble:(double *)result {
    unsigned long long v;
    if (![self scanHexLongLong:&v]) return NO;
    if (result) *result = (double)v;
    return YES;
}

/* ---- text ---- */

- (BOOL)scanString:(NSString *)s intoString:(NSString **)result {
    if (!s.length) return NO;
    NSUInteger i = [self _skipped];
    if (i + s.length > _string.length) return NO;
    NSString *here = [_string substringWithRange:NSMakeRange(i, s.length)];
    BOOL match = _caseSensitive ? [here isEqualToString:s] : [here caseInsensitiveCompare:s] == NSOrderedSame;
    if (!match) return NO;
    _location = i + s.length;
    if (result) *result = here;
    return YES;
}
- (BOOL)scanCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result {
    NSUInteger i = [self _skipped], n = _string.length, j = i;
    while (j < n && [set characterIsMember:[_string characterAtIndex:j]]) j++;
    if (j == i) return NO;
    _location = j;
    if (result) *result = [_string substringWithRange:NSMakeRange(i, j - i)];
    return YES;
}
- (BOOL)scanUpToString:(NSString *)s intoString:(NSString **)result {
    NSUInteger i = [self _skipped], n = _string.length;
    if (i >= n) return NO;
    NSStringCompareOptions opts = _caseSensitive ? 0 : NSCaseInsensitiveSearch;
    NSRange r = s.length ? [_string rangeOfString:s options:opts range:NSMakeRange(i, n - i)] : NSMakeRange(NSNotFound, 0);
    NSUInteger end = r.location == NSNotFound ? n : r.location;
    if (end == i) return NO;
    _location = end;
    if (result) *result = [_string substringWithRange:NSMakeRange(i, end - i)];
    return YES;
}
- (BOOL)scanUpToCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result {
    NSUInteger i = [self _skipped], n = _string.length, j = i;
    while (j < n && ![set characterIsMember:[_string characterAtIndex:j]]) j++;
    if (j == i) return NO;
    _location = j;
    if (result) *result = [_string substringWithRange:NSMakeRange(i, j - i)];
    return YES;
}
@end
