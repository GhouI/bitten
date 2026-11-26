/* NSTimeZone, NSFormatter, NSISO8601DateFormatter and NSListFormatter,
 * the Objective-C counterparts of TimeZone, ISO8601FormatStyle and
 * ListFormatStyle (swift/TimeZone.swift, swift/FormatStyle.swift), with the
 * same rules: named zones read their transitions from /usr/share/zoneinfo
 * (TZif), the current zone is TZ or /etc/localtime's target; lists are
 * joined the en_US way ("a, b, and c"). */
#import <Foundation/Foundation.h>
#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* ---- time zones ---- */

typedef struct { int32_t offset; uint8_t dst; uint8_t abbr; } TZType;

@implementation NSTimeZone {
    NSString *_name;
    BOOL _fixed;
    NSInteger _offset;
    int64_t *_times;
    uint8_t *_idx;
    int _ntimes;
    TZType *_types;
    int _ntypes;
    char *_abbrs;
    int _nabbrs;
}

static NSString *gmt_name(NSInteger off) {
    if (off == 0) return @"GMT";
    NSInteger a = off < 0 ? -off : off;
    return [NSString stringWithFormat:@"GMT%c%02ld%02ld", off < 0 ? '-' : '+', (long)(a / 3600), (long)(a % 3600 / 60)];
}

static BOOL parse_offset(NSString *s, NSInteger *out) {
    const char *p = s.UTF8String;
    if (!strncmp(p, "GMT", 3) || !strncmp(p, "UTC", 3)) p += 3;
    if (*p != '+' && *p != '-') return NO;
    int neg = *p++ == '-';
    char digits[8];
    int n = 0;
    for (; *p && n < 7; p++) {
        if (*p == ':') continue;
        if (!isdigit((unsigned char)*p)) return NO;
        digits[n++] = *p;
    }
    if (!n || n > 4 || *p) return NO;
    digits[n] = 0;
    int h, m = 0;
    if (n <= 2) h = atoi(digits);
    else {
        m = atoi(digits + n - 2);
        digits[n - 2] = 0;
        h = atoi(digits);
    }
    NSInteger total = h * 3600 + m * 60;
    *out = neg ? -total : total;
    return YES;
}

- (void)dealloc {
    free(_times);
    free(_idx);
    free(_types);
    free(_abbrs);
}

- (BOOL)_bn_load:(NSString *)name {
    if ([name containsString:@".."] || [name hasPrefix:@"/"]) return NO;
    NSString *path = [@"/usr/share/zoneinfo/" stringByAppendingString:name];
    FILE *f = fopen(path.UTF8String, "rb");
    if (!f) return NO;
    uint8_t *b = NULL;
    size_t n = 0, cap = 0;
    for (;;) {
        if (n == cap) { cap = cap ? cap * 2 : 8192; b = realloc(b, cap); }
        size_t got = fread(b + n, 1, cap - n, f);
        if (!got) break;
        n += got;
    }
    fclose(f);
#define BE32(i) ((int32_t)((uint32_t)b[i] << 24 | (uint32_t)b[(i) + 1] << 16 | (uint32_t)b[(i) + 2] << 8 | b[(i) + 3]))
    if (n < 44 || memcmp(b, "TZif", 4)) { free(b); return NO; }
    int isutc = BE32(20), isstd = BE32(24), leap = BE32(28), timecnt = BE32(32), typecnt = BE32(36), charcnt = BE32(40);
    size_t need = 44 + (size_t)timecnt * 5 + (size_t)typecnt * 6 + (size_t)charcnt + (size_t)leap * 8 + isstd + isutc;
    if (n < need || typecnt <= 0) { free(b); return NO; }
    size_t p = 44;
    _ntimes = timecnt;
    _times = calloc(timecnt ? timecnt : 1, sizeof *_times);
    for (int i = 0; i < timecnt; i++) _times[i] = BE32(p + i * 4);
    p += timecnt * 4;
    _idx = malloc(timecnt ? timecnt : 1);
    memcpy(_idx, b + p, timecnt);
    p += timecnt;
    _ntypes = typecnt;
    _types = calloc(typecnt, sizeof *_types);
    for (int i = 0; i < typecnt; i++) {
        _types[i].offset = BE32(p + i * 6);
        _types[i].dst = b[p + i * 6 + 4];
        _types[i].abbr = b[p + i * 6 + 5];
    }
    p += typecnt * 6;
    _nabbrs = charcnt;
    _abbrs = malloc(charcnt + 1);
    memcpy(_abbrs, b + p, charcnt);
    _abbrs[charcnt] = 0;
#undef BE32
    free(b);
    return YES;
}

- (instancetype)initWithName:(NSString *)name {
    if (!name) return nil;
    if ((self = [super init])) {
        NSInteger off;
        if ([name isEqualToString:@"GMT"] || [name isEqualToString:@"UTC"] || [name isEqualToString:@"Etc/UTC"]) {
            _fixed = YES;
            _name = [name isEqualToString:@"UTC"] ? @"UTC" : @"GMT";
        } else if (parse_offset(name, &off)) {
            _fixed = YES;
            _offset = off;
            _name = gmt_name(off);
        } else if ([self _bn_load:name]) {
            _name = [name copy];
        } else {
            return nil;
        }
    }
    return self;
}
+ (instancetype)timeZoneWithName:(NSString *)name { return [[self alloc] initWithName:name]; }
+ (instancetype)timeZoneForSecondsFromGMT:(NSInteger)seconds {
    NSTimeZone *z = [self new];
    z->_fixed = YES;
    z->_offset = seconds;
    z->_name = gmt_name(seconds);
    return z;
}
+ (instancetype)timeZoneWithAbbreviation:(NSString *)a {
    NSDictionary *map = @{@"GMT": @"GMT", @"UTC": @"UTC", @"EST": @"America/New_York", @"EDT": @"America/New_York",
                          @"CST": @"America/Chicago", @"PST": @"America/Los_Angeles", @"PDT": @"America/Los_Angeles",
                          @"CET": @"Europe/Paris", @"BST": @"Europe/London", @"JST": @"Asia/Tokyo"};
    NSString *name = map[a.uppercaseString];
    return name ? [self timeZoneWithName:name] : nil;
}

static NSTimeZone *default_zone;
+ (NSTimeZone *)systemTimeZone {
    const char *tz = getenv("TZ");
    if (tz && *tz) {
        NSTimeZone *z = [self timeZoneWithName:@(tz[0] == ':' ? tz + 1 : tz)];
        if (z) return z;
    }
    char buf[1024];
    ssize_t n = readlink("/etc/localtime", buf, sizeof buf - 1);
    if (n > 0) {
        buf[n] = 0;
        const char *z = strstr(buf, "zoneinfo/");
        NSTimeZone *t = z ? [self timeZoneWithName:@(z + 9)] : nil;
        if (t) return t;
    }
    return [self timeZoneWithName:@"GMT"];
}
+ (NSTimeZone *)defaultTimeZone { return default_zone ?: [self systemTimeZone]; }
+ (void)setDefaultTimeZone:(NSTimeZone *)z { default_zone = [z copy]; }
+ (NSTimeZone *)localTimeZone { return [self defaultTimeZone]; }

- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)name { return _name; }

- (const TZType *)_bn_typeAt:(NSTimeInterval)t {
    if (_fixed || !_ntypes) return NULL;
    int64_t when = (int64_t)t;
    int lo = 0, hi = _ntimes;
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        if (_times[mid] <= when) lo = mid + 1; else hi = mid;
    }
    if (lo == 0) {
        for (int i = 0; i < _ntypes; i++) if (!_types[i].dst) return &_types[i];
        return &_types[0];
    }
    int i = _idx[lo - 1];
    return i < _ntypes ? &_types[i] : &_types[0];
}
- (NSInteger)secondsFromGMTForDate:(NSDate *)d {
    const TZType *t = [self _bn_typeAt:d.timeIntervalSince1970];
    return t ? t->offset : _offset;
}
- (NSInteger)secondsFromGMT { return [self secondsFromGMTForDate:[NSDate date]]; }
- (NSString *)abbreviationForDate:(NSDate *)d {
    const TZType *t = [self _bn_typeAt:d.timeIntervalSince1970];
    if (!t) return gmt_name(_offset);
    return t->abbr < _nabbrs ? @(_abbrs + t->abbr) : nil;
}
- (NSString *)abbreviation { return [self abbreviationForDate:[NSDate date]]; }
- (BOOL)isDaylightSavingTimeForDate:(NSDate *)d {
    const TZType *t = [self _bn_typeAt:d.timeIntervalSince1970];
    return t ? t->dst != 0 : NO;
}
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSTimeZone class]] && [((NSTimeZone *)o).name isEqualToString:_name]; }
- (NSUInteger)hash { return _name.hash; }
- (NSString *)description {
    return [NSString stringWithFormat:@"%@ (%@) offset %ld", _name, self.abbreviation, (long)self.secondsFromGMT];
}
@end

/* ---- formatters ---- */

@implementation NSFormatter
- (NSString *)stringForObjectValue:(id)obj { return nil; }
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation NSISO8601DateFormatter {
    NSTimeZone *_tz;
}
@synthesize formatOptions = _formatOptions;
- (instancetype)init {
    if ((self = [super init])) {
        _tz = [NSTimeZone timeZoneWithName:@"GMT"];
        _formatOptions = NSISO8601DateFormatWithInternetDateTime;
    }
    return self;
}
- (NSTimeZone *)timeZone { return _tz; }
- (void)setTimeZone:(NSTimeZone *)tz { _tz = tz ?: [NSTimeZone timeZoneWithName:@"GMT"]; }

+ (NSString *)stringFromDate:(NSDate *)date timeZone:(NSTimeZone *)tz formatOptions:(NSISO8601DateFormatOptions)o {
    NSISO8601DateFormatter *f = [self new];
    f.timeZone = tz;
    f.formatOptions = o;
    return [f stringFromDate:date];
}

- (NSString *)stringFromDate:(NSDate *)date {
    NSISO8601DateFormatOptions o = _formatOptions;
    NSTimeInterval t = date.timeIntervalSince1970;
    NSInteger off = [_tz secondsFromGMTForDate:date];
    double local = t + off;
    time_t secs = (time_t)floor(local);
    struct tm tmv;
    gmtime_r(&secs, &tmv);
    NSMutableString *s = [NSMutableString string];
    const char *ds = (o & NSISO8601DateFormatWithDashSeparatorInDate) ? "-" : "";
    const char *ts = (o & NSISO8601DateFormatWithColonSeparatorInTime) ? ":" : "";
    BOOL any = NO;
    if (o & NSISO8601DateFormatWithYear) { [s appendFormat:@"%04d", tmv.tm_year + 1900]; any = YES; }
    if (o & NSISO8601DateFormatWithMonth) { [s appendFormat:@"%s%02d", any ? ds : "", tmv.tm_mon + 1]; any = YES; }
    if (o & NSISO8601DateFormatWithDay) { [s appendFormat:@"%s%02d", any ? ds : "", tmv.tm_mday]; any = YES; }
    if (o & NSISO8601DateFormatWithTime) {
        if (any) [s appendString:(o & NSISO8601DateFormatWithSpaceBetweenDateAndTime) ? @" " : @"T"];
        [s appendFormat:@"%02d%s%02d%s%02d", tmv.tm_hour, ts, tmv.tm_min, ts, tmv.tm_sec];
        if (o & NSISO8601DateFormatWithFractionalSeconds)
            [s appendFormat:@".%03d", (int)lround((local - floor(local)) * 1000) % 1000];
    }
    if (o & NSISO8601DateFormatWithTimeZone) {
        if (off == 0) [s appendString:@"Z"];
        else {
            NSInteger a = off < 0 ? -off : off;
            [s appendFormat:@"%c%02ld%s%02ld", off < 0 ? '-' : '+', (long)(a / 3600),
                            (o & NSISO8601DateFormatWithColonSeparatorInTimeZone) ? ":" : "", (long)(a % 3600 / 60)];
        }
    }
    return s;
}

/* Dates in the shape the options describe, separators optional. */
- (NSDate *)dateFromString:(NSString *)string {
    const char *p = string.UTF8String;
    if (!p) return nil;
    int y = 1970, mo = 1, d = 1, h = 0, mi = 0, se = 0, n;
    double frac = 0;
    NSInteger off = -1;
#define NUM(width, var)                                                         \
    do {                                                                        \
        int v_ = 0;                                                             \
        for (n = 0; n < (width); n++) {                                         \
            if (!isdigit((unsigned char)p[n])) return nil;                      \
            v_ = v_ * 10 + p[n] - '0';                                          \
        }                                                                       \
        p += (width);                                                           \
        (var) = v_;                                                             \
    } while (0)
    NSISO8601DateFormatOptions o = _formatOptions;
    if (o & (NSISO8601DateFormatWithYear | NSISO8601DateFormatWithMonth | NSISO8601DateFormatWithDay)) {
        if (o & NSISO8601DateFormatWithYear) NUM(4, y);
        if (*p == '-') p++;
        if (o & NSISO8601DateFormatWithMonth) NUM(2, mo);
        if (*p == '-') p++;
        if (o & NSISO8601DateFormatWithDay) NUM(2, d);
    }
    if (o & NSISO8601DateFormatWithTime) {
        if (*p == 'T' || *p == 't' || *p == ' ') p++;
        NUM(2, h);
        if (*p == ':') p++;
        NUM(2, mi);
        if (*p == ':') p++;
        NUM(2, se);
        if (*p == '.' || *p == ',') {
            p++;
            double scale = 0.1;
            while (isdigit((unsigned char)*p)) { frac += (*p++ - '0') * scale; scale /= 10; }
        }
    }
    if (*p == 'Z' || *p == 'z') { off = 0; p++; }
    else if (*p == '+' || *p == '-') {
        int neg = *p++ == '-', oh, om = 0;
        NUM(2, oh);
        if (*p == ':') p++;
        if (isdigit((unsigned char)*p)) NUM(2, om);
        off = (oh * 3600 + om * 60) * (neg ? -1 : 1);
    }
#undef NUM
    if (*p || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 24 || mi > 59 || se > 60) return nil;
    struct tm tmv = {0};
    tmv.tm_year = y - 1900;
    tmv.tm_mon = mo - 1;
    tmv.tm_mday = d;
    tmv.tm_hour = h;
    tmv.tm_min = mi;
    tmv.tm_sec = se;
    double utc = (double)timegm(&tmv);
    if (off < 0 && !(o & NSISO8601DateFormatWithTimeZone)) off = [_tz secondsFromGMT];
    if (off == -1) off = 0;
    return [NSDate dateWithTimeIntervalSince1970:utc - off + frac];
}
- (NSString *)stringForObjectValue:(id)obj {
    return [obj isKindOfClass:[NSDate class]] ? [self stringFromDate:obj] : nil;
}
@end

@implementation NSListFormatter
@synthesize itemFormatter = _itemFormatter;
+ (NSString *)localizedStringByJoiningStrings:(NSArray<NSString *> *)strings {
    return [[self new] stringFromItems:strings];
}
- (NSString *)stringFromItems:(NSArray *)items {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (id item in items) {
        NSString *s = _itemFormatter ? [_itemFormatter stringForObjectValue:item] : nil;
        [parts addObject:s ?: [item description]];
    }
    switch (parts.count) {
    case 0: return @"";
    case 1: return parts[0];
    case 2: return [NSString stringWithFormat:@"%@ and %@", parts[0], parts[1]];
    default: {
        NSArray *head = [parts subarrayWithRange:NSMakeRange(0, parts.count - 1)];
        return [NSString stringWithFormat:@"%@, and %@", [head componentsJoinedByString:@", "], parts.lastObject];
    }
    }
}
- (NSString *)stringForObjectValue:(id)obj {
    return [obj isKindOfClass:[NSArray class]] ? [self stringFromItems:obj] : nil;
}
@end
