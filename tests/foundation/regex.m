// NSRegularExpression (ICU syntax), NSTextCheckingResult and NSDataDetector.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

static NSRegularExpression *re(NSString *p, NSRegularExpressionOptions o) {
    NSError *e = nil;
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:p options:o error:&e];
    if (!r) printf("pattern %s: %s\n", p.UTF8String, e.description.UTF8String);
    return r;
}
static NSRange all(NSString *s) { return NSMakeRange(0, s.length); }
/* the first match's text, or nil */
static NSString *first(NSString *p, NSString *s, NSRegularExpressionOptions o) {
    NSTextCheckingResult *m = [re(p, o) firstMatchInString:s options:0 range:all(s)];
    return m ? [s substringWithRange:m.range] : nil;
}
/* every match's text, joined with | */
static NSString *every(NSString *p, NSString *s, NSRegularExpressionOptions o) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSTextCheckingResult *m in [re(p, o) matchesInString:s options:0 range:all(s)])
        [a addObject:[s substringWithRange:m.range]];
    return [a componentsJoinedByString:@"|"];
}
static NSString *sub(NSString *p, NSString *s, NSString *t, NSRegularExpressionOptions o) {
    return [re(p, o) stringByReplacingMatchesInString:s options:0 range:all(s) withTemplate:t];
}

int main(void) {
    /* literals, classes, quantifiers */
    CHECK([first(@"b+", @"aabbbc", 0) isEqual:@"bbb"]);
    CHECK([first(@"\\d{2,3}", @"a1234", 0) isEqual:@"123"]);
    CHECK([first(@"\\d{2,3}?", @"a1234", 0) isEqual:@"12"]);
    CHECK([first(@"[a-c]+", @"xxabcabd", 0) isEqual:@"abcab"]);
    CHECK([first(@"[^a-c\\s]+", @"ab cxyz", 0) isEqual:@"xyz"]);
    CHECK([first(@"a.c", @"a\nc abc", 0) isEqual:@"abc"]);
    CHECK([first(@"a.c", @"a\nc", NSRegularExpressionDotMatchesLineSeparators) isEqual:@"a\nc"]);
    CHECK([first(@"colou?r", @"the color", 0) isEqual:@"color"]);
    CHECK([first(@"<.+?>", @"<a><b>", 0) isEqual:@"<a>"]);
    CHECK([first(@"<.+>", @"<a><b>", 0) isEqual:@"<a><b>"]);
    CHECK([first(@"[[:alpha:]]+", @"12ab3", 0) isEqual:@"ab"]);
    CHECK([first(@"\\p{Lu}\\p{Ll}+", @"hello World", 0) isEqual:@"World"]);
    CHECK([first(@"\\x41\\u0042\\x{43}", @"zABC", 0) isEqual:@"ABC"]);
    CHECK([first(@"\\Qa.b\\E", @"axb a.b", 0) isEqual:@"a.b"]);
    CHECK([first(@"a.b", @"axb a.b", NSRegularExpressionIgnoreMetacharacters) isEqual:@"a.b"]);
    CHECK(first(@"x", @"abc", 0) == nil);
    /* case and inline flags */
    CHECK([first(@"hello", @"Say HeLLo", NSRegularExpressionCaseInsensitive) isEqual:@"HeLLo"]);
    CHECK([first(@"(?i)[a-z]+", @"123ABC", 0) isEqual:@"ABC"]);
    CHECK([first(@"a(?i:b)c", @"aBc aBC", 0) isEqual:@"aBc"]);
    CHECK([first(@"(?x) a b  # comment\n c", @"abc", 0) isEqual:@"abc"]);
    CHECK([first(@"ÉTÉ", @"un été", NSRegularExpressionCaseInsensitive) isEqual:@"été"]);
    /* alternation, groups, back references, names */
    CHECK([first(@"cat|dog|bird", @"a bird", 0) isEqual:@"bird"]);
    CHECK([first(@"(\\w)\\1", @"abccd", 0) isEqual:@"cc"]);
    CHECK([first(@"(?<q>['\"]).*?\\k<q>", @"say 'hi' now", 0) isEqual:@"'hi'"]);
    NSString *date = @"on 2026-11-26 ok";
    NSRegularExpression *d = re(@"(?<y>\\d{4})-(\\d\\d)-(?<d>\\d\\d)", 0);
    CHECK(d.numberOfCaptureGroups == 3);
    NSTextCheckingResult *m = [d firstMatchInString:date options:0 range:all(date)];
    CHECK(m.numberOfRanges == 4 && m.range.location == 3 && m.range.length == 10);
    CHECK([[date substringWithRange:[m rangeAtIndex:2]] isEqual:@"11"]);
    CHECK([[date substringWithRange:[m rangeWithName:@"y"]] isEqual:@"2026"]);
    CHECK([[date substringWithRange:[m rangeWithName:@"d"]] isEqual:@"26"]);
    CHECK([m rangeWithName:@"nope"].location == NSNotFound);
    m = [re(@"(a)|(b)", 0) firstMatchInString:@"b" options:0 range:NSMakeRange(0, 1)];
    CHECK([m rangeAtIndex:1].location == NSNotFound && [m rangeAtIndex:2].location == 0);
    /* anchors and boundaries */
    CHECK([every(@"^\\w+", @"one two\nthree", 0) isEqual:@"one"]);
    CHECK([every(@"^\\w+", @"one two\nthree", NSRegularExpressionAnchorsMatchLines) isEqual:@"one|three"]);
    CHECK([every(@"\\w+$", @"one\ntwo\n", 0) isEqual:@"two"]);
    CHECK([every(@"\\bis\\b", @"this is island is", 0) isEqual:@"is|is"]);
    CHECK([first(@"\\Aab", @"ab", 0) isEqual:@"ab"] && first(@"\\Aab", @"cab", 0) == nil);
    CHECK([first(@"ab\\z", @"xab", 0) isEqual:@"ab"] && first(@"ab\\z", @"ab\n", 0) == nil && [first(@"ab\\Z", @"ab\n", 0) isEqual:@"ab"]);
    /* look-around and atomic groups */
    CHECK([first(@"\\w+(?=!)", @"hey you!", 0) isEqual:@"you"]);
    CHECK([first(@"\\b\\w+\\b(?!\\.)", @"a. bc.de", 0) isEqual:@"de"]);
    CHECK([first(@"(?<=\\$)\\d+", @"cost 5 or $12", 0) isEqual:@"12"]);
    CHECK([first(@"(?<!\\$)\\b\\d+", @"$12 or 5", 0) isEqual:@"5"]);
    CHECK(first(@"(?>a+)ab", @"aaab", 0) == nil);
    CHECK(first(@"a++b?a", @"aaa", 0) == nil);
    CHECK([first(@"a+?b", @"aaab", 0) isEqual:@"aaab"]);
    /* empty matches advance */
    CHECK([every(@"a*", @"baaa", 0) isEqual:@"|aaa|"]);
    CHECK([re(@"x*", 0) numberOfMatchesInString:@"abc" options:0 range:NSMakeRange(0, 3)] == 4);
    /* nested quantifiers end on empty loops */
    CHECK([first(@"(a*)*b", @"aaab", 0) isEqual:@"aaab"]);
    CHECK(first(@"(a|aa)*c", @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab", 0) == nil); /* gives up, does not hang */
    /* surrogate pairs */
    CHECK([first(@"😀.", @"a😀😃b", 0) isEqual:@"😀😃"]);
    CHECK([every(@".", @"😀b", 0) isEqual:@"😀|b"]);
    /* search ranges */
    NSString *s = @"a1 b2 c3";
    NSArray *ms = [re(@"\\w\\d", 0) matchesInString:s options:0 range:NSMakeRange(2, 6)];
    CHECK(ms.count == 2 && [ms[0] range].location == 3);
    CHECK([re(@"^b", 0) firstMatchInString:s options:0 range:NSMakeRange(3, 5)] != nil); /* anchoring bounds */
    CHECK([re(@"b", 0) firstMatchInString:s options:NSMatchingAnchored range:NSMakeRange(2, 6)] == nil);
    CHECK([re(@"b", 0) firstMatchInString:s options:NSMatchingAnchored range:NSMakeRange(3, 5)] != nil);
    /* replacement */
    CHECK([sub(@"(\\w+)@(\\w+)", @"me@host you@there", @"$2 at $1", 0) isEqual:@"host at me there at you"]);
    CHECK([sub(@"(?<w>o)", @"foo", @"[${w}]", 0) isEqual:@"f[o][o]"]);
    CHECK([sub(@"a", @"banana", @"\\$", 0) isEqual:@"b$n$n$"]);
    CHECK([sub(@"\\s+", @"  a  b ", @" ", 0) isEqual:@" a b "]);
    CHECK([sub(@"z", @"abc", @"y", 0) isEqual:@"abc"]);
    NSMutableString *ms2 = [@"one two three" mutableCopy];
    CHECK([re(@"\\b(\\w)", 0) replaceMatchesInString:ms2 options:0 range:NSMakeRange(0, ms2.length) withTemplate:@"<$1>"] == 3);
    CHECK([ms2 isEqual:@"<o>ne <t>wo <t>hree"]);
    CHECK([[NSRegularExpression escapedPatternForString:@"a.b*c"] isEqual:@"a\\.b\\*c"]);
    CHECK([[NSRegularExpression escapedTemplateForString:@"$1\\"] isEqual:@"\\$1\\\\"]);
    /* enumeration: stop, completion */
    __block int seen = 0, completed = 0;
    [re(@"\\d", 0) enumerateMatchesInString:@"1 2 3 4" options:NSMatchingReportCompletion range:NSMakeRange(0, 7)
                                 usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags f, BOOL *stop) {
                                     if (r) seen++;
                                     if (f & NSMatchingCompleted) completed++;
                                 }];
    CHECK(seen == 4 && completed == 1);
    seen = 0;
    [re(@"\\d", 0) enumerateMatchesInString:@"1 2 3 4" options:0 range:NSMakeRange(0, 7)
                                 usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags f, BOOL *stop) {
                                     if (++seen == 2) *stop = YES;
                                 }];
    CHECK(seen == 2);
    /* errors */
    NSError *err = nil;
    CHECK([NSRegularExpression regularExpressionWithPattern:@"(abc" options:0 error:&err] == nil);
    CHECK([err.domain isEqual:NSCocoaErrorDomain] && err.code == 2048);
    CHECK([NSRegularExpression regularExpressionWithPattern:@"*a" options:0 error:NULL] == nil);
    CHECK([NSRegularExpression regularExpressionWithPattern:@"[a-" options:0 error:NULL] == nil);
    CHECK([NSRegularExpression regularExpressionWithPattern:@"a{2,1}" options:0 error:NULL] == nil);
    CHECK([NSRegularExpression regularExpressionWithPattern:@"\\k<x>" options:0 error:NULL] == nil);
    CHECK([re(@"a\\d", 0).pattern isEqual:@"a\\d"]);
    /* adjusting result ranges */
    m = [re(@"(b)", 0) firstMatchInString:@"ab" options:0 range:NSMakeRange(0, 2)];
    NSTextCheckingResult *moved = [m resultByAdjustingRangesWithOffset:10];
    CHECK(moved.range.location == 11 && [moved rangeAtIndex:1].location == 11);

    /* data detectors */
    NSDataDetector *links = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:&err];
    CHECK(links && links.checkingTypes == NSTextCheckingTypeLink);
    NSString *text = @"See https://example.com/a?b=1. Or www.test.org, mail bob@mail.example.com (later).";
    NSArray<NSTextCheckingResult *> *found = [links matchesInString:text options:0 range:all(text)];
    CHECK(found.count == 3);
    CHECK(found[0].resultType == NSTextCheckingTypeLink && [found[0].URL.absoluteString isEqual:@"https://example.com/a?b=1"]);
    CHECK([[text substringWithRange:found[1].range] isEqual:@"www.test.org"] && [found[1].URL.absoluteString isEqual:@"http://www.test.org"]);
    CHECK([found[2].URL.absoluteString isEqual:@"mailto:bob@mail.example.com"]);
    NSDataDetector *phones = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypePhoneNumber error:NULL];
    NSTextCheckingResult *ph = [phones firstMatchInString:@"call (555) 123-4567 now" options:0 range:NSMakeRange(0, 23)];
    CHECK(ph && [ph.phoneNumber isEqual:@"(555) 123-4567"]);
    CHECK([NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeSpelling error:NULL] == nil);

    puts("regex ok");
    return 0;
}
