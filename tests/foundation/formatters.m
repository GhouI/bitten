// NSDateFormatter, NSByteCountFormatter, NSDateComponentsFormatter and
// NSRelativeDateTimeFormatter, en_US.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)
#define EQ(a, b) do { NSString *a_ = (a), *b_ = (b); if (![a_ isEqual:b_]) { printf("FAIL %s:%d: \"%s\" != \"%s\"\n", __FILE__, __LINE__, a_.UTF8String, b_.UTF8String); exit(1); } } while (0)

int main(void) {
    NSTimeZone *utc = [NSTimeZone timeZoneWithName:@"GMT"];
    /* 2026-03-05 14:07:09.250 UTC, a Thursday */
    NSDate *when = [NSDate dateWithTimeIntervalSince1970:1772719629.25];

    NSDateFormatter *f = [NSDateFormatter new];
    f.timeZone = utc;
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
    EQ([f stringFromDate:when], @"2026-03-05T14:07:09.250Z");
    f.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
    EQ([f stringFromDate:when], @"Thu, 05 Mar 2026 14:07:09 GMT");
    f.dateFormat = @"EEEE MMMM d y h:mm a, 'week' w, Q QQQ, D";
    EQ([f stringFromDate:when], @"Thursday March 5 2026 2:07 PM, week 10, 1 Q1, 64");
    f.dateFormat = @"yy/M/d H 'o''clock' ''";
    EQ([f stringFromDate:when], @"26/3/5 14 o'clock '");
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:-(5 * 3600 + 30 * 60)];
    f.dateFormat = @"HH:mm Z ZZZZ ZZZZZ xxx X";
    EQ([f stringFromDate:when], @"08:37 -0530 GMT-05:30 -05:30 -05:30 -0530");
    f.timeZone = utc;

    /* styles */
    NSDateFormatter *st = [NSDateFormatter new];
    st.timeZone = utc;
    st.dateStyle = NSDateFormatterShortStyle;
    EQ([st stringFromDate:when], @"3/5/26");
    st.dateStyle = NSDateFormatterMediumStyle;
    EQ([st stringFromDate:when], @"Mar 5, 2026");
    st.timeStyle = NSDateFormatterShortStyle;
    EQ([st stringFromDate:when], @"Mar 5, 2026, 2:07 PM");
    st.dateStyle = NSDateFormatterFullStyle;
    st.timeStyle = NSDateFormatterNoStyle;
    EQ([st stringFromDate:when], @"Thursday, March 5, 2026");
    st.dateStyle = NSDateFormatterLongStyle;
    st.timeStyle = NSDateFormatterMediumStyle;
    EQ([st stringFromDate:when], @"March 5, 2026 at 2:07:09 PM");
    EQ(st.dateFormat, @"MMMM d, y 'at' h:mm:ss a");
    EQ([NSDateFormatter dateFormatFromTemplate:@"MMMd" options:0 locale:nil], @"MMM d");
    EQ([NSDateFormatter dateFormatFromTemplate:@"yMd" options:0 locale:nil], @"M/d/y");
    EQ([NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:nil], @"h:mm a");

    /* parsing */
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    NSDate *p = [f dateFromString:@"2026-03-05T14:07:09+0000"];
    CHECK(p && p.timeIntervalSince1970 == 1772719629);
    p = [f dateFromString:@"2026-03-05T16:07:09+02:00"];
    CHECK(p && p.timeIntervalSince1970 == 1772719629);
    CHECK([f dateFromString:@"2026-03-05T14:07:09"] == nil);   /* the zone is required */
    CHECK([f dateFromString:@"2026-03-05T14:07:09+0000x"] == nil);
    CHECK([f dateFromString:@"2026-13-05T14:07:09+0000"] == nil);
    f.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
    p = [f dateFromString:@"Thu, 05 Mar 2026 14:07:09 GMT"];
    CHECK(p && p.timeIntervalSince1970 == 1772719629);
    f.dateFormat = @"yyyyMMddHHmmss";
    p = [f dateFromString:@"20260305140709"];
    CHECK(p && p.timeIntervalSince1970 == 1772719629);
    f.dateFormat = @"MMMM d, y h:mm a";
    p = [f dateFromString:@"march 5, 2026 2:07 pm"];
    CHECK(p && p.timeIntervalSince1970 == 1772719620);
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    p = [f dateFromString:@"2026-03-05 14:07:09.250"];
    CHECK(p && p.timeIntervalSince1970 == 1772719629.25);
    f.dateFormat = @"HH:mm";
    p = [f dateFromString:@"10:30"];
    CHECK(p && p.timeIntervalSince1970 == 946722600); /* 2000-01-01 10:30 */

    /* byte counts */
    EQ([NSByteCountFormatter stringFromByteCount:0 countStyle:NSByteCountFormatterCountStyleFile], @"Zero KB");
    EQ([NSByteCountFormatter stringFromByteCount:1 countStyle:NSByteCountFormatterCountStyleFile], @"1 byte");
    EQ([NSByteCountFormatter stringFromByteCount:999 countStyle:NSByteCountFormatterCountStyleFile], @"999 bytes");
    EQ([NSByteCountFormatter stringFromByteCount:1000 countStyle:NSByteCountFormatterCountStyleFile], @"1 KB");
    EQ([NSByteCountFormatter stringFromByteCount:1023 countStyle:NSByteCountFormatterCountStyleMemory], @"1,023 bytes");
    EQ([NSByteCountFormatter stringFromByteCount:1536 countStyle:NSByteCountFormatterCountStyleMemory], @"2 KB");
    EQ([NSByteCountFormatter stringFromByteCount:1500000 countStyle:NSByteCountFormatterCountStyleFile], @"1.5 MB");
    EQ([NSByteCountFormatter stringFromByteCount:2000000 countStyle:NSByteCountFormatterCountStyleFile], @"2 MB");
    EQ([NSByteCountFormatter stringFromByteCount:999999 countStyle:NSByteCountFormatterCountStyleFile], @"1 MB");
    EQ([NSByteCountFormatter stringFromByteCount:1234567890 countStyle:NSByteCountFormatterCountStyleFile], @"1.23 GB");
    EQ([NSByteCountFormatter stringFromByteCount:-2048 countStyle:NSByteCountFormatterCountStyleBinary], @"-2 KB");
    NSByteCountFormatter *b = [NSByteCountFormatter new];
    b.allowedUnits = NSByteCountFormatterUseKB;
    EQ([b stringFromByteCount:5000000], @"5,000 KB");
    b.allowedUnits = NSByteCountFormatterUseMB;
    b.includesUnit = NO;
    EQ([b stringFromByteCount:5300000], @"5.3");
    b.includesUnit = YES;
    b.includesCount = NO;
    EQ([b stringFromByteCount:5300000], @"MB");
    b = [NSByteCountFormatter new];
    b.includesActualByteCount = YES;
    EQ([b stringFromByteCount:1500000], @"1.5 MB (1,500,000 bytes)");
    EQ([b stringForObjectValue:@2000], @"2 KB (2,000 bytes)");

    /* durations */
    NSDateComponentsFormatter *dc = [NSDateComponentsFormatter new];
    dc.allowedUnits = NSCalendarUnitMinute | NSCalendarUnitSecond;
    EQ([dc stringFromTimeInterval:65], @"1:05");
    EQ([dc stringFromTimeInterval:5], @"0:05");
    dc.allowedUnits = NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    EQ([dc stringFromTimeInterval:3725], @"1:02:05");
    EQ([dc stringFromTimeInterval:125], @"2:05");
    dc.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorPad;
    EQ([dc stringFromTimeInterval:125], @"00:02:05");
    dc.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDefault;
    dc.unitsStyle = NSDateComponentsFormatterUnitsStyleAbbreviated;
    EQ([dc stringFromTimeInterval:3725], @"1h 2m 5s");
    EQ([dc stringFromTimeInterval:3600], @"1h");
    EQ([dc stringFromTimeInterval:0], @"0s");
    dc.unitsStyle = NSDateComponentsFormatterUnitsStyleFull;
    EQ([dc stringFromTimeInterval:3661], @"1 hour, 1 minute, 1 second");
    EQ([dc stringFromTimeInterval:7322], @"2 hours, 2 minutes, 2 seconds");
    dc.unitsStyle = NSDateComponentsFormatterUnitsStyleShort;
    EQ([dc stringFromTimeInterval:3725], @"1 hr, 2 min, 5 sec");
    dc.unitsStyle = NSDateComponentsFormatterUnitsStyleSpellOut;
    EQ([dc stringFromTimeInterval:3725], @"one hour, two minutes, five seconds");
    dc.unitsStyle = NSDateComponentsFormatterUnitsStyleBrief;
    EQ([dc stringFromTimeInterval:3725], @"1hr 2min 5sec");
    dc.unitsStyle = NSDateComponentsFormatterUnitsStyleAbbreviated;
    dc.maximumUnitCount = 1;
    EQ([dc stringFromTimeInterval:3725], @"1h");
    dc.maximumUnitCount = 0;
    dc.allowedUnits = NSCalendarUnitDay | NSCalendarUnitHour;
    dc.includesApproximationPhrase = YES;
    dc.includesTimeRemainingPhrase = YES;
    EQ([dc stringFromTimeInterval:90000], @"About 1d 1h remaining");

    /* relative dates */
    NSRelativeDateTimeFormatter *r = [NSRelativeDateTimeFormatter new];
    NSDate *now = [NSDate date];
    EQ([r localizedStringForDate:[now dateByAddingTimeInterval:-300] relativeToDate:now], @"5 minutes ago");
    EQ([r localizedStringForDate:[now dateByAddingTimeInterval:7200] relativeToDate:now], @"in 2 hours");
    EQ([r localizedStringForDate:[now dateByAddingTimeInterval:-1] relativeToDate:now], @"1 second ago");
    EQ([r localizedStringFromTimeInterval:-14 * 86400], @"2 weeks ago");
    EQ([r localizedStringFromTimeInterval:400 * 86400], @"in 1 year");
    r.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleAbbreviated;
    EQ([r localizedStringFromTimeInterval:-7200], @"2h ago");
    r.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleShort;
    EQ([r localizedStringFromTimeInterval:-7200], @"2 hr. ago");
    r.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleSpellOut;
    EQ([r localizedStringFromTimeInterval:180], @"in three minutes");
    r.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleFull;
    r.dateTimeStyle = NSRelativeDateTimeFormatterStyleNamed;
    EQ([r localizedStringFromTimeInterval:0], @"now");
    EQ([r localizedStringFromTimeInterval:-8 * 86400], @"last week");

    puts("formatters ok");
    return 0;
}
