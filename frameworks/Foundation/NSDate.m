#import "FoundationInternal.h"

static inline CFDateRef CFDA(NSDate *d) { return (__bridge CFDateRef)d; }
static id make_date(NSTimeInterval reference) { return (__bridge_transfer id)CFDateCreate(NULL, reference); }

@implementation NSDate (Foundation)
+ (instancetype)date { return make_date(CFAbsoluteTimeGetCurrent()); }
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)s { return make_date(CFAbsoluteTimeGetCurrent() + s); }
+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)s { return make_date(s - NSTimeIntervalSince1970); }
+ (instancetype)dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)s { return make_date(s); }
+ (NSDate *)distantFuture { return make_date(63113904000.0); }
+ (NSDate *)distantPast { return make_date(-63114076800.0); }
+ (NSTimeInterval)timeIntervalSinceReferenceDate { return CFAbsoluteTimeGetCurrent(); }
- (instancetype)init { return make_date(CFAbsoluteTimeGetCurrent()); }
- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)s { return make_date(s); }
- (instancetype)initWithTimeIntervalSince1970:(NSTimeInterval)s { return make_date(s - NSTimeIntervalSince1970); }
- (instancetype)initWithTimeIntervalSinceNow:(NSTimeInterval)s { return make_date(CFAbsoluteTimeGetCurrent() + s); }
- (NSTimeInterval)timeIntervalSinceReferenceDate { return CFDateGetAbsoluteTime(CFDA(self)); }
- (NSTimeInterval)timeIntervalSince1970 { return self.timeIntervalSinceReferenceDate + NSTimeIntervalSince1970; }
- (NSTimeInterval)timeIntervalSinceNow { return self.timeIntervalSinceReferenceDate - CFAbsoluteTimeGetCurrent(); }
- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)other { return self.timeIntervalSinceReferenceDate - other.timeIntervalSinceReferenceDate; }
- (instancetype)dateByAddingTimeInterval:(NSTimeInterval)s { return make_date(self.timeIntervalSinceReferenceDate + s); }
- (NSComparisonResult)compare:(NSDate *)other {
    NSTimeInterval a = self.timeIntervalSinceReferenceDate, b = other.timeIntervalSinceReferenceDate;
    return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
}
- (NSDate *)earlierDate:(NSDate *)other { return [self compare:other] == NSOrderedDescending ? other : self; }
- (NSDate *)laterDate:(NSDate *)other { return [self compare:other] == NSOrderedAscending ? other : self; }
- (BOOL)isEqualToDate:(NSDate *)other { return other && [self compare:other] == NSOrderedSame; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description {
    time_t t = (time_t)self.timeIntervalSince1970;
    struct tm tm;
    char buf[64];
    gmtime_r(&t, &tm);
    strftime(buf, sizeof buf, "%Y-%m-%d %H:%M:%S +0000", &tm);
    return [NSString stringWithUTF8String:buf];
}
@end

NSString *const NSCocoaErrorDomain = @"NSCocoaErrorDomain";
NSString *const NSURLErrorDomain = @"NSURLErrorDomain";
NSString *const NSURLErrorFailingURLErrorKey = @"NSErrorFailingURLKey";
NSString *const NSURLErrorFailingURLStringErrorKey = @"NSErrorFailingURLStringKey";
NSString *const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";
NSString *const NSOSStatusErrorDomain = @"NSOSStatusErrorDomain";
NSString *const NSLocalizedDescriptionKey = @"NSLocalizedDescription";
NSString *const NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReason";
NSString *const NSUnderlyingErrorKey = @"NSUnderlyingError";
NSString *const NSFilePathErrorKey = @"NSFilePath";
NSString *const NSURLErrorKey = @"NSURL";
NSString *const NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestion";
NSString *const NSLocalizedRecoveryOptionsErrorKey = @"NSLocalizedRecoveryOptions";
NSString *const NSRecoveryAttempterErrorKey = @"NSRecoveryAttempter";
NSString *const NSHelpAnchorErrorKey = @"NSHelpAnchor";
NSString *const NSMultipleUnderlyingErrorsKey = @"NSMultipleUnderlyingErrorsKey";
NSString *const NSStringEncodingErrorKey = @"NSStringEncodingErrorKey";
NSString *const NSLocalizedFailureErrorKey = @"NSLocalizedFailure";

@implementation NSError (Foundation)
+ (instancetype)errorWithDomain:(NSErrorDomain)domain code:(NSInteger)code userInfo:(NSDictionary *)userInfo {
    return [[self alloc] initWithDomain:domain code:code userInfo:userInfo];
}
- (instancetype)initWithDomain:(NSErrorDomain)domain code:(NSInteger)code userInfo:(NSDictionary *)userInfo {
    if (!domain) BNRaise("NSInvalidArgumentException", "-[NSError initWithDomain:code:userInfo:]: domain cannot be nil");
    return (__bridge_transfer id)CFErrorCreate(NULL, (__bridge CFStringRef)domain, (CFIndex)code, (__bridge CFDictionaryRef)userInfo);
}
- (NSErrorDomain)domain { return (__bridge NSString *)CFErrorGetDomain((__bridge CFErrorRef)self); }
- (NSInteger)code { return (NSInteger)CFErrorGetCode((__bridge CFErrorRef)self); }
- (NSDictionary *)userInfo {
    NSDictionary *info = (__bridge_transfer NSDictionary *)CFErrorCopyUserInfo((__bridge CFErrorRef)self);
    return info ?: @{};
}
- (NSString *)localizedDescription {
    NSString *d = self.userInfo[NSLocalizedDescriptionKey];
    if (d) return d;
    if ([self.domain isEqualToString:NSPOSIXErrorDomain]) return [NSString stringWithUTF8String:strerror((int)self.code)];
    return [NSString stringWithFormat:@"The operation couldn’t be completed. (%@ error %ld.)", self.domain, (long)self.code];
}
- (NSString *)localizedFailureReason { return self.userInfo[NSLocalizedFailureReasonErrorKey]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description {
    return [NSString stringWithFormat:@"Error Domain=%@ Code=%ld \"%@\"", self.domain, (long)self.code, self.localizedDescription];
}
@end

/* For Foundation's Swift overlay: an error with plain arguments (building
 * userInfo dictionaries from Swift goes through generic bridging). */
@implementation NSError (BittenSwift)
+ (NSError *)_bn_errorWithDomain:(NSString *)domain code:(NSInteger)code
                        filePath:(NSString *)path underlyingPOSIX:(int)posix {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (path) info[NSFilePathErrorKey] = path;
    if (posix) info[NSUnderlyingErrorKey] = [NSError errorWithDomain:NSPOSIXErrorDomain code:posix userInfo:nil];
    return [NSError errorWithDomain:domain code:code userInfo:info];
}
@end
