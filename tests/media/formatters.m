// NSTimeZone (fixed and TZif zones), NSISO8601DateFormatter both ways with
// its options, NSListFormatter.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

int main(void) {
    @autoreleasepool {
        NSTimeZone *gmt = [NSTimeZone timeZoneWithName:@"GMT"];
        CHECK(gmt.secondsFromGMT == 0 && [gmt.name isEqualToString:@"GMT"]);
        NSTimeZone *plus = [NSTimeZone timeZoneForSecondsFromGMT:5400];
        CHECK([plus.name isEqualToString:@"GMT+0130"] && plus.secondsFromGMT == 5400);
        CHECK([NSTimeZone timeZoneWithName:@"Not/AZone"] == nil);
        NSTimeZone *ny = [NSTimeZone timeZoneWithName:@"America/New_York"];
        if (ny) {
            NSDate *winter = [NSDate dateWithTimeIntervalSince1970:1767225600];   // 2026-01-01
            NSDate *summer = [NSDate dateWithTimeIntervalSince1970:1782864000];   // 2026-07-01
            CHECK([ny secondsFromGMTForDate:winter] == -18000 && [ny secondsFromGMTForDate:summer] == -14400);
            CHECK([[ny abbreviationForDate:winter] isEqualToString:@"EST"] && [ny isDaylightSavingTimeForDate:summer]);
        }

        NSDate *date = [NSDate dateWithTimeIntervalSince1970:1764133443.25];      // 2025-11-26T05:04:03.25Z
        NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
        CHECK([[f stringFromDate:date] isEqualToString:@"2025-11-26T05:04:03Z"]);
        f.formatOptions |= NSISO8601DateFormatWithFractionalSeconds;
        CHECK([[f stringFromDate:date] isEqualToString:@"2025-11-26T05:04:03.250Z"]);
        f.timeZone = plus;
        CHECK([[f stringFromDate:date] isEqualToString:@"2025-11-26T06:34:03.250+01:30"]);
        CHECK([[NSISO8601DateFormatter stringFromDate:date timeZone:gmt formatOptions:NSISO8601DateFormatWithFullDate]
            isEqualToString:@"2025-11-26"]);
        NSISO8601DateFormatter *p = [NSISO8601DateFormatter new];
        CHECK([[p dateFromString:@"2025-11-26T05:04:03Z"] timeIntervalSince1970] == 1764133443);
        CHECK([[p dateFromString:@"2025-11-26T06:04:03+01:00"] timeIntervalSince1970] == 1764133443);
        CHECK([p dateFromString:@"yesterday"] == nil);

        NSArray *three = @[@"a", @"b", @"c"], *two = @[@"a", @"b"];
        CHECK([[NSListFormatter localizedStringByJoiningStrings:three] isEqualToString:@"a, b, and c"]);
        CHECK([[NSListFormatter localizedStringByJoiningStrings:two] isEqualToString:@"a and b"]);
        CHECK([[[NSListFormatter new] stringFromItems:@[]] isEqualToString:@""]);
    }
    printf("formatters ok\n");
    return 0;
}
