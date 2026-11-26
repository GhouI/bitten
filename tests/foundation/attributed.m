// NSAttributedString / NSMutableAttributedString (toll-free bridged to
// CFAttributedString) and NSProgress.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        NSAttributedString *a = [[NSAttributedString alloc] initWithString:@"hello" attributes:@{@"k" : @1}];
        CHECK([a.string isEqualToString:@"hello"] && a.length == 5);
        NSRange r;
        CHECK([[a attribute:@"k" atIndex:2 effectiveRange:&r] isEqual:@1] && r.location == 0 && r.length == 5);
        CHECK(CFGetTypeID((__bridge CFTypeRef)a) == CFAttributedStringGetTypeID());

        NSMutableAttributedString *m = [a mutableCopy];
        [m appendAttributedString:[[NSAttributedString alloc] initWithString:@" world" attributes:@{@"k" : @2}]];
        CHECK([m.string isEqualToString:@"hello world"]);
        CHECK([[m attribute:@"k" atIndex:7 effectiveRange:&r] isEqual:@2] && r.location == 5 && r.length == 6);
        [m addAttribute:@"bold" value:@YES range:NSMakeRange(0, 3)];
        NSDictionary *d = [m attributesAtIndex:1 effectiveRange:&r];
        CHECK([d[@"bold"] isEqual:@YES] && [d[@"k"] isEqual:@1] && r.length == 3);
        [m removeAttribute:@"bold" range:NSMakeRange(0, 11)];
        CHECK([m attribute:@"bold" atIndex:1 effectiveRange:NULL] == nil);
        // Same attributes on both sides of a removed one merge in the longest range.
        [m attributesAtIndex:0 longestEffectiveRange:&r inRange:NSMakeRange(0, 11)];
        CHECK(r.location == 0 && r.length == 5);
        __block int runs = 0;
        [m enumerateAttribute:@"k" inRange:NSMakeRange(0, m.length) options:0
                   usingBlock:^(id v, NSRange range, BOOL *stop) { runs++; }];
        CHECK(runs == 2);
        NSAttributedString *sub = [m attributedSubstringFromRange:NSMakeRange(3, 4)];
        CHECK([sub.string isEqualToString:@"lo w"] && [[sub attribute:@"k" atIndex:3 effectiveRange:NULL] isEqual:@2]);
        [m replaceCharactersInRange:NSMakeRange(0, 5) withString:@"HELLO"];
        CHECK([m.string isEqualToString:@"HELLO world"]);
        CHECK(![m isEqual:a] && [[a copy] isEqual:a]);

        NSProgress *p = [NSProgress progressWithTotalUnitCount:10];
        NSProgress *c = [NSProgress progressWithTotalUnitCount:2 parent:p pendingUnitCount:5];
        c.completedUnitCount = 1;
        CHECK(p.fractionCompleted > 0.24 && p.fractionCompleted < 0.26);
        c.completedUnitCount = 2;
        CHECK(p.completedUnitCount == 5 && !p.isFinished);
        p.completedUnitCount = 10;
        CHECK(p.isFinished);
        [p cancel];
        CHECK(p.isCancelled);
        printf("ok\n");
    }
    return 0;
}
