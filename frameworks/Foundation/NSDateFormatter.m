/* NSDateFormatter, NSByteCountFormatter, NSDateComponentsFormatter and
 * NSRelativeDateTimeFormatter, in the en_US way (the Gregorian calendar,
 * English names), as documented for these classes and for Unicode TR35
 * date patterns. Time zones are NSTimeZone's (NSFormatters.m). */
#import "FoundationInternal.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static NSString *const kMonths[] = {@"January", @"February", @"March", @"April", @"May", @"June", @"July",
                                    @"August", @"September", @"October", @"November", @"December"};
static NSString *const kShortMonths[] = {@"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun",
                                         @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec"};
static NSString *const kWeekdays[] = {@"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday"};
static NSString *const kShortWeekdays[] = {@"Sun", @"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat"};
static NSString *const kShorterWeekdays[] = {@"Su", @"Mo", @"Tu", @"We", @"Th", @"Fr", @"Sa"};

static NSArray *array_of(NSString *const *items, int n) { return [NSArray arrayWithObjects:items count:(NSUInteger)n]; }

/* broken-down local time for a date in a zone */
typedef struct {
    int year, month, day, hour, minute, second, weekday, yday; /* month 1-12, weekday 0 = Sunday */
    double frac;
    NSInteger offset;
} Fields;

static Fields fields_for(NSDate *date, NSTimeZone *tz) {
    Fields f;
    NSTimeInterval t = date.timeIntervalSince1970;
    f.offset = [tz secondsFromGMTForDate:date];
    double local = t + (double)f.offset;
    double whole = floor(local);
    time_t secs = (time_t)whole;
    struct tm tmv;
    gmtime_r(&secs, &tmv);
    f.year = tmv.tm_year + 1900;
    f.month = tmv.tm_mon + 1;
    f.day = tmv.tm_mday;
    f.hour = tmv.tm_hour;
    f.minute = tmv.tm_min;
    f.second = tmv.tm_sec;
    f.weekday = tmv.tm_wday;
    f.yday = tmv.tm_yday;
    f.frac = local - whole;
    return f;
}

static NSString *pad(long v, int width) {
    char buf[32];
    if (v < 0) snprintf(buf, sizeof buf, "-%0*ld", width, -v);
    else snprintf(buf, sizeof buf, "%0*ld", width, v);
    return [NSString stringWithUTF8String:buf];
}

static NSString *gmt_offset(NSInteger off, BOOL colon, BOOL zulu, BOOL with_minutes_always, BOOL seconds) {
    if (off == 0 && zulu) return @"Z";
    NSInteger a = off < 0 ? -off : off;
    NSMutableString *s = [NSMutableString stringWithFormat:@"%c%02ld", off < 0 ? '-' : '+', (long)(a / 3600)];
    if (with_minutes_always || a % 3600) [s appendFormat:@"%s%02ld", colon ? ":" : "", (long)(a % 3600 / 60)];
    if (seconds && a % 60) [s appendFormat:@"%s%02ld", colon ? ":" : "", (long)(a % 60)];
    return s;
}

/* ---- patterns ----------------------------------------------------------------------- */

typedef void (^TokenBlock)(unichar letter, int count, NSString *literal);
static void each_token(NSString *format, TokenBlock block) {
    NSUInteger n = format.length, i = 0;
    while (i < n) {
        unichar c = [format characterAtIndex:i];
        if (c == '\'') {
            NSMutableString *lit = [NSMutableString string];
            if (i + 1 < n && [format characterAtIndex:i + 1] == '\'') {
                block(0, 0, @"'");
                i += 2;
                continue;
            }
            i++;
            while (i < n) {
                unichar d = [format characterAtIndex:i];
                if (d == '\'') {
                    if (i + 1 < n && [format characterAtIndex:i + 1] == '\'') {
                        [lit appendString:@"'"];
                        i += 2;
                        continue;
                    }
                    i++;
                    break;
                }
                [lit appendFormat:@"%C", d];
                i++;
            }
            block(0, 0, lit);
            continue;
        }
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
            int count = 0;
            while (i < n && [format characterAtIndex:i] == c) { count++; i++; }
            block(c, count, nil);
            continue;
        }
        block(0, 0, [NSString stringWithFormat:@"%C", c]);
        i++;
    }
}

@implementation NSDateFormatter {
    NSString *_format;     /* explicit, or nil for the styles' */
    NSDateFormatterStyle _dateStyle, _timeStyle;
    NSLocale *_locale;
    NSTimeZone *_timeZone;
    id _calendar;
    BOOL _lenient, _relative;
    NSDate *_defaultDate, *_twoDigitStartDate;
    NSString *_am, *_pm;
    NSFormattingContext _context;
    NSDateFormatterBehavior _behavior;
}
- (instancetype)init {
    if ((self = [super init])) {
        _am = @"AM";
        _pm = @"PM";
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    NSDateFormatter *f = [[self class] new];
    f->_format = _format;
    f->_dateStyle = _dateStyle;
    f->_timeStyle = _timeStyle;
    f->_locale = _locale;
    f->_timeZone = _timeZone;
    f->_calendar = _calendar;
    f->_lenient = _lenient;
    f->_relative = _relative;
    f->_defaultDate = _defaultDate;
    f->_twoDigitStartDate = _twoDigitStartDate;
    f->_am = _am;
    f->_pm = _pm;
    return f;
}

- (NSString *)_styleFormat {
    static NSString *const dates[] = {@"", @"M/d/yy", @"MMM d, y", @"MMMM d, y", @"EEEE, MMMM d, y"};
    static NSString *const times[] = {@"", @"h:mm a", @"h:mm:ss a", @"h:mm:ss a z", @"h:mm:ss a zzzz"};
    NSString *d = dates[_dateStyle <= 4 ? _dateStyle : 0], *t = times[_timeStyle <= 4 ? _timeStyle : 0];
    if (!d.length) return t;
    if (!t.length) return d;
    return [NSString stringWithFormat:_dateStyle >= NSDateFormatterLongStyle ? @"%@ 'at' %@" : @"%@, %@", d, t];
}
- (NSString *)dateFormat { return _format ?: [self _styleFormat]; }
- (void)setDateFormat:(NSString *)format { _format = [format copy]; }
- (NSDateFormatterStyle)dateStyle { return _dateStyle; }
- (void)setDateStyle:(NSDateFormatterStyle)s { _dateStyle = s; _format = nil; }
- (NSDateFormatterStyle)timeStyle { return _timeStyle; }
- (void)setTimeStyle:(NSDateFormatterStyle)s { _timeStyle = s; _format = nil; }
- (NSLocale *)locale { return _locale ?: [NSLocale currentLocale]; }
- (void)setLocale:(NSLocale *)locale { _locale = locale; }
- (NSTimeZone *)timeZone { return _timeZone ?: [NSTimeZone defaultTimeZone]; }
- (void)setTimeZone:(NSTimeZone *)tz { _timeZone = tz; }
- (id)calendar { return _calendar; }
- (void)setCalendar:(id)calendar { _calendar = calendar; }
- (BOOL)isLenient { return _lenient; }
- (void)setLenient:(BOOL)v { _lenient = v; }
- (BOOL)doesRelativeDateFormatting { return _relative; }
- (void)setDoesRelativeDateFormatting:(BOOL)v { _relative = v; }
- (NSDate *)defaultDate { return _defaultDate; }
- (void)setDefaultDate:(NSDate *)d { _defaultDate = d; }
- (NSDate *)twoDigitStartDate { return _twoDigitStartDate ?: [NSDate dateWithTimeIntervalSinceNow:-80 * 365.2425 * 86400]; }
- (void)setTwoDigitStartDate:(NSDate *)d { _twoDigitStartDate = d; }
- (NSString *)AMSymbol { return _am; }
- (void)setAMSymbol:(NSString *)s { _am = [s copy] ?: @"AM"; }
- (NSString *)PMSymbol { return _pm; }
- (void)setPMSymbol:(NSString *)s { _pm = [s copy] ?: @"PM"; }
- (NSFormattingContext)formattingContext { return _context; }
- (void)setFormattingContext:(NSFormattingContext)c { _context = c; }
- (NSDateFormatterBehavior)formatterBehavior { return NSDateFormatterBehavior10_4; }
- (void)setFormatterBehavior:(NSDateFormatterBehavior)b { _behavior = b; }
- (BOOL)generatesCalendarDates { return NO; }
- (void)setGeneratesCalendarDates:(BOOL)v {}
- (NSArray<NSString *> *)monthSymbols { return array_of(kMonths, 12); }
- (NSArray<NSString *> *)shortMonthSymbols { return array_of(kShortMonths, 12); }
- (NSArray<NSString *> *)standaloneMonthSymbols { return array_of(kMonths, 12); }
- (NSArray<NSString *> *)shortStandaloneMonthSymbols { return array_of(kShortMonths, 12); }
- (NSArray<NSString *> *)veryShortMonthSymbols {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < 12; i++) [a addObject:[kMonths[i] substringToIndex:1]];
    return a;
}
- (NSArray<NSString *> *)weekdaySymbols { return array_of(kWeekdays, 7); }
- (NSArray<NSString *> *)shortWeekdaySymbols { return array_of(kShortWeekdays, 7); }
- (NSArray<NSString *> *)standaloneWeekdaySymbols { return array_of(kWeekdays, 7); }
- (NSArray<NSString *> *)shortStandaloneWeekdaySymbols { return array_of(kShortWeekdays, 7); }
- (NSArray<NSString *> *)veryShortWeekdaySymbols {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < 7; i++) [a addObject:[kWeekdays[i] substringToIndex:1]];
    return a;
}
- (NSArray<NSString *> *)eraSymbols { return @[ @"BC", @"AD" ]; }
- (NSArray<NSString *> *)longEraSymbols { return @[ @"Before Christ", @"Anno Domini" ]; }
- (NSArray<NSString *> *)quarterSymbols { return @[ @"1st quarter", @"2nd quarter", @"3rd quarter", @"4th quarter" ]; }
- (NSArray<NSString *> *)shortQuarterSymbols { return @[ @"Q1", @"Q2", @"Q3", @"Q4" ]; }

+ (NSString *)localizedStringFromDate:(NSDate *)date dateStyle:(NSDateFormatterStyle)ds timeStyle:(NSDateFormatterStyle)ts {
    NSDateFormatter *f = [self new];
    f.dateStyle = ds;
    f.timeStyle = ts;
    return [f stringFromDate:date];
}
/* A template's fields, in the en_US order and punctuation. */
+ (NSString *)dateFormatFromTemplate:(NSString *)tmpl options:(NSUInteger)opts locale:(NSLocale *)locale {
    __block NSMutableDictionary<NSString *, NSNumber *> *have = [NSMutableDictionary dictionary];
    each_token(tmpl, ^(unichar l, int count, NSString *lit) {
        if (l) have[[NSString stringWithFormat:@"%C", l]] = @(count);
    });
    int M = have[@"M"].intValue ?: have[@"L"].intValue, d = have[@"d"].intValue, y = have[@"y"].intValue,
        E = have[@"E"].intValue;
    int h = have[@"h"].intValue, H = have[@"H"].intValue ?: have[@"k"].intValue, j = have[@"j"].intValue,
        m = have[@"m"].intValue, s = have[@"s"].intValue, a = have[@"a"].intValue;
    if (j) h = j;
    (void)a;
    NSMutableString *date = [NSMutableString string];
    if (M >= 3) {
        if (E) [date appendString:E >= 4 ? @"EEEE, " : @"EEE, "];
        [date appendString:M >= 4 ? @"MMMM" : @"MMM"];
        if (d) [date appendString:d >= 2 ? @" dd" : @" d"];
        if (y) [date appendString:d ? @", y" : @" y"];
    } else if (M || d || y) {
        NSMutableArray *parts = [NSMutableArray array];
        if (M) [parts addObject:M == 2 ? @"MM" : @"M"];
        if (d) [parts addObject:d == 2 ? @"dd" : @"d"];
        if (y) [parts addObject:y == 2 ? @"yy" : @"y"];
        if (E) [date appendString:E >= 4 ? @"EEEE, " : @"EEE, "];
        [date appendString:[parts componentsJoinedByString:@"/"]];
    } else if (E) {
        [date appendString:E >= 4 ? @"EEEE" : @"EEE"];
    }
    NSMutableString *time = [NSMutableString string];
    if (h || H) {
        [time appendString:H ? (H >= 2 ? @"HH" : @"HH") : (h >= 2 ? @"hh" : @"h")];
        if (m) [time appendString:@":mm"];
        if (s) [time appendString:@":ss"];
        if (!H) [time appendString:@" a"];
    } else if (m) {
        [time appendString:s ? @"mm:ss" : @"mm"];
    } else if (s) {
        [time appendString:@"ss"];
    }
    if (date.length && time.length) return [NSString stringWithFormat:@"%@, %@", date, time];
    return date.length ? date : time;
}
- (void)setLocalizedDateFormatFromTemplate:(NSString *)tmpl {
    self.dateFormat = [NSDateFormatter dateFormatFromTemplate:tmpl options:0 locale:self.locale];
}

- (NSString *)stringFromDate:(NSDate *)date {
    if (!date) return nil;
    if (_relative && !_format && _dateStyle) {
        /* Today / Yesterday / Tomorrow in place of the date */
        Fields f = fields_for(date, self.timeZone), now = fields_for([NSDate date], self.timeZone);
        struct tm a = {0}, b = {0};
        a.tm_year = f.year - 1900; a.tm_mon = f.month - 1; a.tm_mday = f.day;
        b.tm_year = now.year - 1900; b.tm_mon = now.month - 1; b.tm_mday = now.day;
        long days = (long)((timegm(&a) - timegm(&b)) / 86400);
        NSString *word = days == 0 ? @"Today" : days == -1 ? @"Yesterday" : days == 1 ? @"Tomorrow" : nil;
        if (word) {
            if (!_timeStyle) return word;
            NSDateFormatter *t = [self copy];
            t.dateStyle = NSDateFormatterNoStyle;
            t.timeStyle = _timeStyle;
            t.doesRelativeDateFormatting = NO;
            return [NSString stringWithFormat:@"%@ at %@", word, [t stringFromDate:date]];
        }
    }
    NSTimeZone *tz = self.timeZone;
    Fields f = fields_for(date, tz);
    NSMutableString *out = [NSMutableString string];
    NSString *am = _am, *pm = _pm;
    each_token(self.dateFormat, ^(unichar l, int n, NSString *lit) {
        if (!l) {
            [out appendString:lit];
            return;
        }
        int hour12 = f.hour % 12 == 0 ? 12 : f.hour % 12;
        switch (l) {
        case 'G': [out appendString:n == 4 ? (f.year > 0 ? @"Anno Domini" : @"Before Christ") : n == 5 ? (f.year > 0 ? @"A" : @"B") : (f.year > 0 ? @"AD" : @"BC")]; break;
        case 'y': case 'Y': case 'u': case 'U':
            [out appendString:n == 2 ? pad(f.year % 100, 2) : pad(f.year, n)];
            break;
        case 'Q': case 'q': {
            int q = (f.month - 1) / 3 + 1;
            static NSString *const names[] = {@"1st quarter", @"2nd quarter", @"3rd quarter", @"4th quarter"};
            if (n <= 2) [out appendString:pad(q, n)];
            else if (n == 3) [out appendFormat:@"Q%d", q];
            else if (n == 4) [out appendString:names[q - 1]];
            else [out appendFormat:@"%d", q];
            break;
        }
        case 'M': case 'L':
            if (n <= 2) [out appendString:pad(f.month, n)];
            else if (n == 3) [out appendString:kShortMonths[f.month - 1]];
            else if (n == 4) [out appendString:kMonths[f.month - 1]];
            else [out appendString:[kMonths[f.month - 1] substringToIndex:1]];
            break;
        case 'd': [out appendString:pad(f.day, n)]; break;
        case 'D': [out appendString:pad(f.yday + 1, n)]; break;
        case 'F': [out appendString:pad((f.day - 1) / 7 + 1, n)]; break;
        case 'w': {
            struct tm jan = {0};
            jan.tm_year = f.year - 1900; jan.tm_mday = 1;
            time_t t0 = timegm(&jan);
            struct tm j1;
            gmtime_r(&t0, &j1);
            [out appendString:pad((f.yday + j1.tm_wday) / 7 + 1, n)];
            break;
        }
        case 'W': {
            int first_wday = (f.weekday - (f.day - 1) % 7 + 7) % 7;
            [out appendString:pad((f.day - 1 + first_wday) / 7 + 1, n)];
            break;
        }
        case 'e': case 'c':
            if (n <= 2) { [out appendString:pad(f.weekday + 1, n)]; break; }
            /* fall through: names */
        case 'E':
            if (n <= 3) [out appendString:kShortWeekdays[f.weekday]];
            else if (n == 4) [out appendString:kWeekdays[f.weekday]];
            else if (n == 5) [out appendString:[kWeekdays[f.weekday] substringToIndex:1]];
            else [out appendString:kShorterWeekdays[f.weekday]];
            break;
        case 'a': case 'b': case 'B': [out appendString:f.hour < 12 ? am : pm]; break;
        case 'h': [out appendString:pad(hour12, n)]; break;
        case 'H': [out appendString:pad(f.hour, n)]; break;
        case 'K': [out appendString:pad(f.hour % 12, n)]; break;
        case 'k': [out appendString:pad(f.hour == 0 ? 24 : f.hour, n)]; break;
        case 'j': [out appendString:pad(hour12, n)]; break;
        case 'm': [out appendString:pad(f.minute, n)]; break;
        case 's': [out appendString:pad(f.second, n)]; break;
        case 'S': {
            long digits = (long)floor(f.frac * pow(10, n) + 1e-6);
            [out appendString:pad(digits, n)];
            break;
        }
        case 'A': [out appendString:pad(((f.hour * 60 + f.minute) * 60 + f.second) * 1000 + (long)(f.frac * 1000), n)]; break;
        case 'z':
            if (n <= 3) {
                NSString *abbr = [tz abbreviationForDate:date];
                [out appendString:abbr.length ? abbr : [@"GMT" stringByAppendingString:gmt_offset(f.offset, YES, NO, NO, NO)]];
            } else {
                [out appendString:f.offset ? [@"GMT" stringByAppendingString:gmt_offset(f.offset, YES, NO, YES, NO)] : @"GMT"];
            }
            break;
        case 'Z':
            if (n <= 3) [out appendString:gmt_offset(f.offset, NO, NO, YES, NO)];
            else if (n == 4) [out appendString:f.offset ? [@"GMT" stringByAppendingString:gmt_offset(f.offset, YES, NO, YES, NO)] : @"GMT"];
            else [out appendString:gmt_offset(f.offset, YES, YES, YES, NO)];
            break;
        case 'O':
            if (!f.offset) [out appendString:@"GMT"];
            else if (n == 4) [out appendString:[@"GMT" stringByAppendingString:gmt_offset(f.offset, YES, NO, YES, NO)]];
            else {
                NSInteger a = f.offset < 0 ? -f.offset : f.offset;
                [out appendFormat:@"GMT%c%ld", f.offset < 0 ? '-' : '+', (long)(a / 3600)];
                if (a % 3600) [out appendFormat:@":%02ld", (long)(a % 3600 / 60)];
            }
            break;
        case 'X': case 'x': {
            BOOL zulu = l == 'X';
            if (n == 1) [out appendString:gmt_offset(f.offset, NO, zulu, NO, NO)];
            else if (n == 2 || n == 4) [out appendString:gmt_offset(f.offset, NO, zulu, YES, n == 4)];
            else [out appendString:gmt_offset(f.offset, YES, zulu, YES, n == 5)];
            break;
        }
        case 'V': case 'v':
            [out appendString:n == 1 && l == 'V' ? @"unk" : tz.name];
            break;
        default: break; /* unknown pattern letters produce nothing */
        }
    });
    return out;
}
- (NSString *)stringForObjectValue:(id)obj {
    return [obj isKindOfClass:[NSDate class]] ? [self stringFromDate:obj] : nil;
}

/* ---- parsing ---- */

static BOOL match_word(NSString *s, NSUInteger *pos, NSArray<NSString *> *words, NSInteger *index) {
    NSInteger best = -1;
    NSUInteger bestLen = 0;
    for (NSUInteger i = 0; i < words.count; i++) {
        NSString *w = words[i];
        if (*pos + w.length <= s.length && w.length > bestLen &&
            [[s substringWithRange:NSMakeRange(*pos, w.length)] caseInsensitiveCompare:w] == NSOrderedSame) {
            best = (NSInteger)i;
            bestLen = w.length;
        }
    }
    if (best < 0) return NO;
    *pos += bestLen;
    *index = best;
    return YES;
}
static BOOL read_number(NSString *s, NSUInteger *pos, int maxDigits, long *out, BOOL allowSign) {
    NSUInteger p = *pos, n = s.length;
    BOOL neg = NO;
    if (allowSign && p < n && ([s characterAtIndex:p] == '-' || [s characterAtIndex:p] == '+')) {
        neg = [s characterAtIndex:p] == '-';
        p++;
    }
    long v = 0;
    int digits = 0;
    while (p < n && digits < maxDigits) {
        unichar c = [s characterAtIndex:p];
        if (c < '0' || c > '9') break;
        v = v * 10 + (c - '0');
        p++;
        digits++;
    }
    if (!digits) return NO;
    *out = neg ? -v : v;
    *pos = p;
    return YES;
}
/* "Z", "+08", "+0800", "+08:00", "GMT", "GMT+8", "GMT+08:00", "UTC", or an abbreviation */
static BOOL read_zone(NSString *s, NSUInteger *pos, NSInteger *offset, NSTimeZone **zone) {
    NSUInteger p = *pos, n = s.length;
    if (p < n && ([s characterAtIndex:p] == 'Z' || [s characterAtIndex:p] == 'z')) {
        *offset = 0;
        *pos = p + 1;
        return YES;
    }
    BOOL prefixed = NO;
    for (NSString *pre in @[ @"GMT", @"UTC", @"UT" ]) {
        if (p + pre.length <= n && [[s substringWithRange:NSMakeRange(p, pre.length)] isEqualToString:pre]) {
            p += pre.length;
            prefixed = YES;
            break;
        }
    }
    if (p < n && ([s characterAtIndex:p] == '+' || [s characterAtIndex:p] == '-')) {
        int sign = [s characterAtIndex:p] == '-' ? -1 : 1;
        p++;
        NSUInteger start = p;
        long h = 0, m = 0;
        while (p < n && [s characterAtIndex:p] >= '0' && [s characterAtIndex:p] <= '9' && p - start < 4) p++;
        NSUInteger digits = p - start;
        if (!digits) return NO;
        NSString *num = [s substringWithRange:NSMakeRange(start, digits)];
        if (digits <= 2) {
            h = num.integerValue;
            if (p < n && [s characterAtIndex:p] == ':') {
                p++;
                NSUInteger ms = p;
                while (p < n && p - ms < 2 && [s characterAtIndex:p] >= '0' && [s characterAtIndex:p] <= '9') p++;
                if (p - ms != 2) return NO;
                m = [s substringWithRange:NSMakeRange(ms, 2)].integerValue;
            }
        } else if (digits == 3) {
            h = [num substringToIndex:1].integerValue;
            m = [num substringFromIndex:1].integerValue;
        } else {
            h = [num substringToIndex:2].integerValue;
            m = [num substringFromIndex:2].integerValue;
        }
        *offset = sign * (h * 3600 + m * 60);
        *pos = p;
        return YES;
    }
    if (prefixed) {
        *offset = 0;
        *pos = p;
        return YES;
    }
    /* an abbreviation (PST, CEST, ...) or a zone name */
    NSUInteger start = p;
    while (p < n) {
        unichar c = [s characterAtIndex:p];
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '/' || c == '_')) break;
        p++;
    }
    if (p == start) return NO;
    NSString *word = [s substringWithRange:NSMakeRange(start, p - start)];
    NSTimeZone *tz = [NSTimeZone timeZoneWithAbbreviation:word] ?: [NSTimeZone timeZoneWithName:word];
    if (!tz) return NO;
    *zone = tz;
    *offset = NSIntegerMin;
    *pos = p;
    return YES;
}

- (NSDate *)dateFromString:(NSString *)string {
    if (!string) return nil;
    __block NSUInteger pos = 0;
    __block BOOL ok = YES;
    __block long year = 2000, month = 1, day = 1, hour = 0, minute = 0, second = 0, yday = -1;
    __block double frac = 0;
    __block int pm = -1, twoDigitYear = 0;
    __block NSInteger offset = NSIntegerMin;
    __block NSTimeZone *zone = nil;
    BOOL lenient = _lenient;
    NSString *am = _am, *pmSym = _pm;
    /* numeric fields followed directly by another numeric field take only their width */
    NSMutableArray *tokens = [NSMutableArray array];
    each_token(self.dateFormat, ^(unichar l, int n, NSString *lit) {
        [tokens addObject:@[ @(l), @(n), lit ?: @"" ]];
    });
    NSString *numeric = @"yYuMLdDhHkKmsSwWFeQqc";
    for (NSUInteger ti = 0; ti < tokens.count && ok; ti++) {
        unichar l = (unichar)[tokens[ti][0] intValue];
        int n = [tokens[ti][1] intValue];
        NSString *lit = tokens[ti][2];
        if (!l) {
            for (NSUInteger k = 0; k < lit.length && ok; k++) {
                unichar c = [lit characterAtIndex:k];
                BOOL space = c == ' ' || c == 0x202f || c == 0xa0;
                if (space) {
                    /* any run of spaces (or none, when lenient) */
                    NSUInteger before = pos;
                    while (pos < string.length && ([string characterAtIndex:pos] == ' ' || [string characterAtIndex:pos] == 0x202f ||
                                                   [string characterAtIndex:pos] == 0xa0))
                        pos++;
                    if (pos == before && !lenient) ok = NO;
                    continue;
                }
                if (pos < string.length && [string characterAtIndex:pos] == c) pos++;
                else if (!lenient) ok = NO;
            }
            continue;
        }
        BOOL nextNumeric = NO;
        if (ti + 1 < tokens.count) {
            unichar nl = (unichar)[tokens[ti + 1][0] intValue];
            int nn = [tokens[ti + 1][1] intValue];
            nextNumeric = nl && [numeric rangeOfString:[NSString stringWithFormat:@"%C", nl]].location != NSNotFound &&
                          !((nl == 'M' || nl == 'L') && nn >= 3);
        }
        int width = nextNumeric ? n : 9;
        if (nextNumeric && (l == 'y' || l == 'u') && n <= 2) width = n == 1 ? 4 : 2;
        long v;
        NSInteger idx;
        switch (l) {
        case 'y': case 'Y': case 'u':
            if (!read_number(string, &pos, width, &v, l == 'u')) { ok = NO; break; }
            year = v;
            twoDigitYear = n == 2 && v < 100;
            break;
        case 'M': case 'L':
            if (n >= 3) {
                NSUInteger save = pos;
                if (match_word(string, &pos, array_of(kMonths, 12), &idx) || match_word(string, &pos, array_of(kShortMonths, 12), &idx))
                    month = idx + 1;
                else { pos = save; ok = NO; }
                if (ok && n == 3 && pos < string.length && [string characterAtIndex:pos] == '.') pos++;
            } else if (read_number(string, &pos, width < 2 ? width : 2, &v, NO) && v >= 1 && v <= 12) month = v;
            else ok = NO;
            break;
        case 'd':
            if (read_number(string, &pos, width < 2 ? width : 2, &v, NO) && v >= 1 && v <= 31) day = v;
            else ok = NO;
            break;
        case 'D':
            if (read_number(string, &pos, width < 3 ? width : 3, &v, NO)) yday = v - 1;
            else ok = NO;
            break;
        case 'E': case 'e': case 'c':
            if ((l != 'E' && n <= 2)) { if (!read_number(string, &pos, 1, &v, NO)) ok = NO; break; }
            if (!match_word(string, &pos, array_of(kWeekdays, 7), &idx) && !match_word(string, &pos, array_of(kShortWeekdays, 7), &idx) &&
                !match_word(string, &pos, array_of(kShorterWeekdays, 7), &idx))
                ok = NO;
            break;
        case 'a': {
            if (match_word(string, &pos, @[ am, pmSym, @"a.m.", @"p.m.", @"am", @"pm" ], &idx)) pm = (idx == 1 || idx == 3 || idx == 5);
            else ok = NO;
            break;
        }
        case 'h': case 'K': case 'H': case 'k': case 'j':
            if (read_number(string, &pos, width < 2 ? width : 2, &v, NO) && v <= 24) hour = (l == 'k' && v == 24) ? 0 : v;
            else ok = NO;
            break;
        case 'm':
            if (read_number(string, &pos, width < 2 ? width : 2, &v, NO) && v < 60) minute = v;
            else ok = NO;
            break;
        case 's':
            if (read_number(string, &pos, width < 2 ? width : 2, &v, NO) && v <= 60) second = v;
            else ok = NO;
            break;
        case 'S': {
            NSUInteger start = pos;
            if (!read_number(string, &pos, nextNumeric ? n : 9, &v, NO)) { ok = NO; break; }
            frac = (double)v / pow(10, (double)(pos - start));
            break;
        }
        case 'z': case 'Z': case 'X': case 'x': case 'O': case 'V': case 'v': {
            NSInteger off;
            NSTimeZone *tz = nil;
            if (!read_zone(string, &pos, &off, &tz)) { ok = NO; break; }
            offset = off;
            zone = tz;
            break;
        }
        case 'G':
            if (!match_word(string, &pos, @[ @"AD", @"BC", @"Anno Domini", @"Before Christ" ], &idx)) ok = NO;
            break;
        case 'Q': case 'q':
            if (n <= 2) { if (!read_number(string, &pos, 1, &v, NO)) ok = NO; }
            else if (!match_word(string, &pos, @[ @"Q1", @"Q2", @"Q3", @"Q4", @"1st quarter", @"2nd quarter", @"3rd quarter", @"4th quarter" ], &idx))
                ok = NO;
            break;
        default:
            if (!read_number(string, &pos, width, &v, NO)) ok = NO;
            break;
        }
    }
    if (!ok) return nil;
    if (lenient) while (pos < string.length && [string characterAtIndex:pos] == ' ') pos++;
    if (pos != string.length) return nil;
    if (pm == 1 && hour < 12) hour += 12;
    if (pm == 0 && hour == 12) hour = 0;
    if (twoDigitYear) {
        long startYear = fields_for(self.twoDigitStartDate, [NSTimeZone timeZoneWithName:@"GMT"]).year;
        long century = startYear - startYear % 100;
        year += century;
        if (year < startYear) year += 100;
    }
    struct tm tmv = {0};
    tmv.tm_year = (int)year - 1900;
    tmv.tm_mon = (int)month - 1;
    tmv.tm_mday = (int)day;
    if (yday >= 0) { tmv.tm_mon = 0; tmv.tm_mday = (int)yday + 1; }
    tmv.tm_hour = (int)hour;
    tmv.tm_min = (int)minute;
    tmv.tm_sec = (int)second;
    double local = (double)timegm(&tmv) + frac;
    if (offset != NSIntegerMin) return [NSDate dateWithTimeIntervalSince1970:local - (double)offset];
    NSTimeZone *tz = zone ?: self.timeZone;
    /* the zone's offset at that local time: guess, then correct once */
    NSInteger off = [tz secondsFromGMTForDate:[NSDate dateWithTimeIntervalSince1970:local]];
    off = [tz secondsFromGMTForDate:[NSDate dateWithTimeIntervalSince1970:local - (double)off]];
    return [NSDate dateWithTimeIntervalSince1970:local - (double)off];
}
- (BOOL)getObjectValue:(id _Nullable *)obj forString:(NSString *)string range:(NSRange *)rangep error:(NSError **)error {
    NSString *s = rangep ? [string substringWithRange:*rangep] : string;
    NSDate *d = [self dateFromString:s];
    if (obj) *obj = d;
    if (!d && error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:2048 userInfo:nil];
    return d != nil;
}
- (BOOL)getObjectValue:(id _Nullable *)obj forString:(NSString *)string errorDescription:(NSString **)error {
    NSDate *d = [self dateFromString:string];
    if (obj) *obj = d;
    if (!d && error) *error = @"Invalid date";
    return d != nil;
}
@end

/* ---- numbers in words, for the spell-out styles ---- */

static NSString *spell(long v) {
    static NSString *const ones[] = {@"zero", @"one", @"two", @"three", @"four", @"five", @"six", @"seven", @"eight",
                                     @"nine", @"ten", @"eleven", @"twelve", @"thirteen", @"fourteen", @"fifteen",
                                     @"sixteen", @"seventeen", @"eighteen", @"nineteen"};
    static NSString *const tens[] = {@"", @"", @"twenty", @"thirty", @"forty", @"fifty", @"sixty", @"seventy", @"eighty", @"ninety"};
    if (v < 0) return [@"minus " stringByAppendingString:spell(-v)];
    if (v < 20) return ones[v];
    if (v < 100) return v % 10 ? [NSString stringWithFormat:@"%@-%@", tens[v / 10], ones[v % 10]] : tens[v / 10];
    if (v < 1000)
        return v % 100 ? [NSString stringWithFormat:@"%@ hundred %@", ones[v / 100], spell(v % 100)]
                       : [NSString stringWithFormat:@"%@ hundred", ones[v / 100]];
    static const long scales[] = {1000000000000L, 1000000000L, 1000000L, 1000L};
    static NSString *const names[] = {@"trillion", @"billion", @"million", @"thousand"};
    for (int i = 0; i < 4; i++)
        if (v >= scales[i])
            return v % scales[i] ? [NSString stringWithFormat:@"%@ %@ %@", spell(v / scales[i]), names[i], spell(v % scales[i])]
                                 : [NSString stringWithFormat:@"%@ %@", spell(v / scales[i]), names[i]];
    return [NSString stringWithFormat:@"%ld", v];
}

static NSString *grouped(unsigned long long v) {
    char digits[32], out[48];
    snprintf(digits, sizeof digits, "%llu", v);
    size_t n = strlen(digits), k = 0;
    for (size_t i = 0; i < n; i++) {
        if (i && (n - i) % 3 == 0) out[k++] = ',';
        out[k++] = digits[i];
    }
    out[k] = 0;
    return [NSString stringWithUTF8String:out];
}

/* ---- NSByteCountFormatter ---------------------------------------------------------------- */

@implementation NSByteCountFormatter
@synthesize allowedUnits = _allowedUnits, countStyle = _countStyle, allowsNonnumericFormatting = _allowsNonnumericFormatting,
            includesUnit = _includesUnit, includesCount = _includesCount, includesActualByteCount = _includesActualByteCount,
            adaptive = _adaptive, zeroPadsFractionDigits = _zeroPadsFractionDigits, formattingContext = _formattingContext;
- (instancetype)init {
    if ((self = [super init])) {
        _allowsNonnumericFormatting = YES;
        _includesUnit = YES;
        _includesCount = YES;
        _adaptive = YES;
    }
    return self;
}
+ (NSString *)stringFromByteCount:(long long)count countStyle:(NSByteCountFormatterCountStyle)style {
    NSByteCountFormatter *f = [self new];
    f.countStyle = style;
    return [f stringFromByteCount:count];
}
- (NSString *)stringFromByteCount:(long long)count {
    static NSString *const units[] = {@"bytes", @"KB", @"MB", @"GB", @"TB", @"PB", @"EB", @"ZB", @"YB"};
    double base = (_countStyle == NSByteCountFormatterCountStyleMemory || _countStyle == NSByteCountFormatterCountStyleBinary) ? 1024 : 1000;
    NSByteCountFormatterUnits allowed = _allowedUnits ? _allowedUnits : NSByteCountFormatterUseAll;
    BOOL ok[9];
    for (int i = 0; i < 9; i++) ok[i] = i < 8 ? (allowed & (1u << i)) != 0 : (allowed & NSByteCountFormatterUseYBOrHigher) != 0;
    unsigned long long mag = count < 0 ? (unsigned long long)(-(count + 1)) + 1 : (unsigned long long)count;
    /* the largest allowed unit the count reaches, else the smallest allowed */
    int unit = -1;
    for (int i = 0; i < 9; i++)
        if (ok[i] && (double)mag >= pow(base, i)) unit = i;
    if (unit < 0)
        for (int i = 0; i < 9; i++)
            if (ok[i]) { unit = i; break; }
    if (unit < 0) unit = 0;
    if (count == 0 && _allowsNonnumericFormatting && _includesCount && _includesUnit) {
        int z = ok[1] ? 1 : unit;
        return [NSString stringWithFormat:@"Zero %@", z == 0 ? @"bytes" : units[z]];
    }
    static const int adaptiveDigits[] = {0, 0, 1, 2, 2, 2, 2, 2, 2};
    int digits = _adaptive ? adaptiveDigits[unit] : (unit == 0 ? 0 : 1);
    double value = (double)mag / pow(base, unit);
    double scale = pow(10, digits);
    double rounded = round(value * scale) / scale;
    /* 999.95 KB rounds up into the next unit */
    if (rounded >= base && unit < 8 && ok[unit + 1]) {
        unit++;
        digits = _adaptive ? adaptiveDigits[unit] : 1;
        value = (double)mag / pow(base, unit);
        scale = pow(10, digits);
        rounded = round(value * scale) / scale;
    }
    NSString *number;
    if (unit == 0) {
        number = grouped(mag);
    } else {
        char buf[64];
        snprintf(buf, sizeof buf, "%.*f", digits, rounded);
        if (!_zeroPadsFractionDigits && strchr(buf, '.')) {
            size_t l = strlen(buf);
            while (l && buf[l - 1] == '0') buf[--l] = 0;
            if (l && buf[l - 1] == '.') buf[--l] = 0;
        }
        char *dot = strchr(buf, '.');
        unsigned long long whole = strtoull(buf, NULL, 10);
        number = [grouped(whole) stringByAppendingString:dot ? [NSString stringWithUTF8String:dot] : @""];
    }
    if (count < 0) number = [@"-" stringByAppendingString:number];
    NSString *name = unit == 0 ? (mag == 1 ? @"byte" : @"bytes") : units[unit];
    NSString *s;
    if (_includesCount && _includesUnit) s = [NSString stringWithFormat:@"%@ %@", number, name];
    else if (_includesCount) s = number;
    else s = name;
    if (_includesActualByteCount && unit > 0)
        s = [s stringByAppendingFormat:@" (%@%@ bytes)", count < 0 ? @"-" : @"", grouped(mag)];
    return s;
}
- (NSString *)stringForObjectValue:(id)obj {
    return [obj respondsToSelector:@selector(longLongValue)] ? [self stringFromByteCount:[obj longLongValue]] : nil;
}
- (id)copyWithZone:(NSZone *)zone {
    NSByteCountFormatter *f = [[self class] new];
    f.allowedUnits = _allowedUnits;
    f.countStyle = _countStyle;
    f.allowsNonnumericFormatting = _allowsNonnumericFormatting;
    f.includesUnit = _includesUnit;
    f.includesCount = _includesCount;
    f.includesActualByteCount = _includesActualByteCount;
    f.adaptive = _adaptive;
    f.zeroPadsFractionDigits = _zeroPadsFractionDigits;
    return f;
}
@end

/* ---- NSDateComponentsFormatter -------------------------------------------------------------- */

/* units, largest first: years, months, weeks, days, hours, minutes, seconds */
static const NSCalendarUnit kUnitFlags[] = {NSCalendarUnitYear, NSCalendarUnitMonth, NSCalendarUnitWeekOfMonth,
                                            NSCalendarUnitDay, NSCalendarUnitHour, NSCalendarUnitMinute, NSCalendarUnitSecond};
static const double kUnitSeconds[] = {365 * 86400.0, 30 * 86400.0, 7 * 86400.0, 86400, 3600, 60, 1};

static NSString *unit_name(int u, long v, NSDateComponentsFormatterUnitsStyle style) {
    static NSString *const full[] = {@"year", @"month", @"week", @"day", @"hour", @"minute", @"second"};
    static NSString *const shortSingular[] = {@"yr", @"mth", @"wk", @"day", @"hr", @"min", @"sec"};
    static NSString *const shortPlural[] = {@"yrs", @"mths", @"wks", @"days", @"hr", @"min", @"sec"};
    static NSString *const abbrev[] = {@"y", @"mo", @"w", @"d", @"h", @"m", @"s"};
    static NSString *const brief[] = {@"yr", @"mth", @"wk", @"d", @"hr", @"min", @"sec"};
    BOOL one = v == 1 || v == -1;
    switch (style) {
    case NSDateComponentsFormatterUnitsStyleAbbreviated: return abbrev[u];
    case NSDateComponentsFormatterUnitsStyleBrief: return brief[u];
    case NSDateComponentsFormatterUnitsStyleShort: return one ? shortSingular[u] : shortPlural[u];
    default: return one ? full[u] : [full[u] stringByAppendingString:@"s"];
    }
}

@implementation NSDateComponentsFormatter
@synthesize unitsStyle = _unitsStyle, allowedUnits = _allowedUnits, zeroFormattingBehavior = _zeroFormattingBehavior,
            calendar = _calendar, referenceDate = _referenceDate, allowsFractionalUnits = _allowsFractionalUnits,
            maximumUnitCount = _maximumUnitCount, collapsesLargestUnit = _collapsesLargestUnit,
            includesApproximationPhrase = _includesApproximationPhrase,
            includesTimeRemainingPhrase = _includesTimeRemainingPhrase, formattingContext = _formattingContext;
- (instancetype)init {
    if ((self = [super init])) _zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDefault;
    return self;
}
- (NSString *)stringFromTimeInterval:(NSTimeInterval)ti {
    if (isnan(ti) || isinf(ti)) return nil;
    NSCalendarUnit allowed = _allowedUnits;
    if (!allowed)
        allowed = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitWeekOfMonth | NSCalendarUnitDay |
                  NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    int use[7], nuse = 0;
    for (int u = 0; u < 7; u++)
        if (allowed & kUnitFlags[u]) use[nuse++] = u;
    if (!nuse) return nil;
    BOOL neg = ti < 0;
    double rest = fabs(ti);
    /* round to the smallest allowed unit */
    double smallest = kUnitSeconds[use[nuse - 1]];
    rest = round(rest / smallest) * smallest;
    long values[7] = {0};
    for (int i = 0; i < nuse; i++) {
        double us = kUnitSeconds[use[i]];
        values[i] = (long)floor(rest / us + 1e-9);
        rest -= (double)values[i] * us;
    }
    NSDateComponentsFormatterUnitsStyle style = _unitsStyle;
    NSDateComponentsFormatterZeroFormattingBehavior z = _zeroFormattingBehavior;
    BOOL positional = style == NSDateComponentsFormatterUnitsStylePositional;
    if (z == NSDateComponentsFormatterZeroFormattingBehaviorDefault)
        z = positional ? NSDateComponentsFormatterZeroFormattingBehaviorDropLeading : NSDateComponentsFormatterZeroFormattingBehaviorDropAll;
    /* which units to show */
    BOOL show[7];
    int first = -1, last = -1;
    for (int i = 0; i < nuse; i++) {
        show[i] = YES;
        if (values[i]) {
            if (first < 0) first = i;
            last = i;
        }
    }
    if (!(z & NSDateComponentsFormatterZeroFormattingBehaviorPad)) {
        for (int i = 0; i < nuse; i++) {
            if (values[i]) continue;
            if ((z & NSDateComponentsFormatterZeroFormattingBehaviorDropLeading) && (first < 0 || i < first)) show[i] = NO;
            if ((z & NSDateComponentsFormatterZeroFormattingBehaviorDropTrailing) && last >= 0 && i > last) show[i] = NO;
            if ((z & NSDateComponentsFormatterZeroFormattingBehaviorDropMiddle) && first >= 0 && i > first && i < last) show[i] = NO;
        }
        if (positional) /* a clock keeps its minutes and seconds */
            for (int i = 0; i < nuse; i++)
                if ((use[i] == 5 || use[i] == 6) && use[nuse - 1] >= 5 && i >= nuse - 2) show[i] = YES;
    }
    int nshow = 0;
    for (int i = 0; i < nuse; i++) nshow += show[i];
    if (!nshow) show[nuse - 1] = YES; /* all zero: the smallest unit, as 0 */
    if (_maximumUnitCount > 0) {
        int kept = 0;
        for (int i = 0; i < nuse; i++)
            if (show[i] && (values[i] || positional)) {
                if (kept >= (int)_maximumUnitCount) show[i] = NO;
                else kept++;
            } else if (show[i] && !positional && kept >= (int)_maximumUnitCount) show[i] = NO;
    }
    NSMutableString *out = [NSMutableString string];
    if (positional) {
        BOOL firstShown = YES;
        for (int i = 0; i < nuse; i++) {
            if (!show[i]) continue;
            int u = use[i];
            if (u <= 3) { /* days and larger: "1d 2:03:04" */
                [out appendFormat:@"%ld%@ ", values[i], unit_name(u, values[i], NSDateComponentsFormatterUnitsStyleAbbreviated)];
                continue;
            }
            if (!firstShown || out.length) [out appendString:out.length && ![out hasSuffix:@" "] ? @":" : @""];
            BOOL padIt = !firstShown || (z & NSDateComponentsFormatterZeroFormattingBehaviorPad) || [out hasSuffix:@" "];
            [out appendString:padIt ? pad(values[i], 2) : [NSString stringWithFormat:@"%ld", values[i]]];
            firstShown = NO;
        }
        NSString *trimmed = [out stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        out = [trimmed mutableCopy];
    } else {
        NSString *sep = style == NSDateComponentsFormatterUnitsStyleAbbreviated || style == NSDateComponentsFormatterUnitsStyleBrief ? @" " : @", ";
        NSMutableArray *parts = [NSMutableArray array];
        for (int i = 0; i < nuse; i++) {
            if (!show[i]) continue;
            int u = use[i];
            long v = values[i];
            NSString *num = style == NSDateComponentsFormatterUnitsStyleSpellOut ? spell(v) : [NSString stringWithFormat:@"%ld", v];
            NSString *name = unit_name(u, v, style == NSDateComponentsFormatterUnitsStyleSpellOut ? NSDateComponentsFormatterUnitsStyleFull : style);
            if (style == NSDateComponentsFormatterUnitsStyleAbbreviated || style == NSDateComponentsFormatterUnitsStyleBrief)
                [parts addObject:[num stringByAppendingString:name]];
            else
                [parts addObject:[NSString stringWithFormat:@"%@ %@", num, name]];
        }
        [out appendString:[parts componentsJoinedByString:sep]];
    }
    if (neg && ti <= -smallest / 2) [out insertString:@"-" atIndex:0];
    if (_includesApproximationPhrase) [out insertString:@"About " atIndex:0];
    if (_includesTimeRemainingPhrase) [out appendString:@" remaining"];
    return out;
}
- (NSString *)stringFromDate:(NSDate *)start toDate:(NSDate *)end {
    return [self stringFromTimeInterval:[end timeIntervalSinceDate:start]];
}
- (NSString *)stringForObjectValue:(id)obj {
    if ([obj isKindOfClass:[NSNumber class]]) return [self stringFromTimeInterval:[obj doubleValue]];
    return nil;
}
+ (NSString *)localizedStringFromTimeInterval:(NSTimeInterval)ti unitsStyle:(NSDateComponentsFormatterUnitsStyle)style {
    NSDateComponentsFormatter *f = [self new];
    f.unitsStyle = style;
    return [f stringFromTimeInterval:ti];
}
- (id)copyWithZone:(NSZone *)zone {
    NSDateComponentsFormatter *f = [[self class] new];
    f.unitsStyle = _unitsStyle;
    f.allowedUnits = _allowedUnits;
    f.zeroFormattingBehavior = _zeroFormattingBehavior;
    f.maximumUnitCount = _maximumUnitCount;
    f.allowsFractionalUnits = _allowsFractionalUnits;
    f.collapsesLargestUnit = _collapsesLargestUnit;
    f.includesApproximationPhrase = _includesApproximationPhrase;
    f.includesTimeRemainingPhrase = _includesTimeRemainingPhrase;
    return f;
}
@end

/* ---- NSRelativeDateTimeFormatter ------------------------------------------------------------------ */

@implementation NSRelativeDateTimeFormatter
@synthesize dateTimeStyle = _dateTimeStyle, unitsStyle = _unitsStyle, formattingContext = _formattingContext,
            calendar = _calendar, locale = _locale;
- (NSString *)_phrase:(long)v unit:(int)u {
    /* u: 0 years .. 6 seconds */
    if (_dateTimeStyle == NSRelativeDateTimeFormatterStyleNamed) {
        static NSString *const last[] = {@"last year", @"last month", @"last week", @"yesterday", nil, nil, nil};
        static NSString *const next[] = {@"next year", @"next month", @"next week", @"tomorrow", nil, nil, nil};
        static NSString *const now[] = {@"this year", @"this month", @"this week", @"today", @"this hour", @"this minute", @"now"};
        if (v == -1 && last[u]) return last[u];
        if (v == 1 && next[u]) return next[u];
        if (v == 0) return now[u];
    }
    long a = v < 0 ? -v : v;
    NSString *num, *name;
    switch (_unitsStyle) {
    case NSRelativeDateTimeFormatterUnitsStyleAbbreviated: {
        static NSString *const ab[] = {@"y", @"mo", @"w", @"d", @"h", @"m", @"s"};
        num = [NSString stringWithFormat:@"%ld%@", a, ab[u]];
        return v < 0 ? [num stringByAppendingString:@" ago"] : [@"in " stringByAppendingString:num];
    }
    case NSRelativeDateTimeFormatterUnitsStyleShort: {
        static NSString *const sh[] = {@"yr.", @"mo.", @"wk.", @"day", @"hr.", @"min.", @"sec."};
        name = sh[u];
        if (u == 3 && a != 1) name = @"days";
        num = [NSString stringWithFormat:@"%ld", a];
        break;
    }
    case NSRelativeDateTimeFormatterUnitsStyleSpellOut: {
        static NSString *const fu[] = {@"year", @"month", @"week", @"day", @"hour", @"minute", @"second"};
        name = a == 1 ? fu[u] : [fu[u] stringByAppendingString:@"s"];
        num = spell(a);
        break;
    }
    default: {
        static NSString *const fu[] = {@"year", @"month", @"week", @"day", @"hour", @"minute", @"second"};
        name = a == 1 ? fu[u] : [fu[u] stringByAppendingString:@"s"];
        num = [NSString stringWithFormat:@"%ld", a];
        break;
    }
    }
    return v < 0 ? [NSString stringWithFormat:@"%@ %@ ago", num, name] : [NSString stringWithFormat:@"in %@ %@", num, name];
}
- (NSString *)localizedStringFromTimeInterval:(NSTimeInterval)ti {
    double a = fabs(ti);
    int u;
    if (a < 60) u = 6;
    else if (a < 3600) u = 5;
    else if (a < 86400) u = 4;
    else if (a < 7 * 86400) u = 3;
    else if (a < 30 * 86400) u = 2;
    else if (a < 365 * 86400) u = 1;
    else u = 0;
    long v = (long)(a / kUnitSeconds[u]);
    return [self _phrase:ti < 0 ? -v : v unit:u];
}
- (NSString *)localizedStringForDate:(NSDate *)date relativeToDate:(NSDate *)ref {
    NSTimeInterval ti = [date timeIntervalSinceDate:ref];
    if (fabs(ti) >= 86400 && fabs(ti) < 7 * 86400) {
        /* days count calendar days, as a calendar would */
        NSTimeZone *tz = [NSTimeZone defaultTimeZone];
        Fields a = fields_for(date, tz), b = fields_for(ref, tz);
        struct tm x = {0}, y = {0};
        x.tm_year = a.year - 1900; x.tm_mon = a.month - 1; x.tm_mday = a.day;
        y.tm_year = b.year - 1900; y.tm_mon = b.month - 1; y.tm_mday = b.day;
        long days = (long)((timegm(&x) - timegm(&y)) / 86400);
        return [self _phrase:days unit:3];
    }
    return [self localizedStringFromTimeInterval:ti];
}
- (NSString *)stringForObjectValue:(id)obj {
    return [obj isKindOfClass:[NSDate class]] ? [self localizedStringForDate:obj relativeToDate:[NSDate date]] : nil;
}
- (id)copyWithZone:(NSZone *)zone {
    NSRelativeDateTimeFormatter *f = [[self class] new];
    f.dateTimeStyle = _dateTimeStyle;
    f.unitsStyle = _unitsStyle;
    return f;
}
@end
