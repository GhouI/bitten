#import "FoundationInternal.h"

NSExceptionName const NSGenericException = @"NSGenericException";
NSExceptionName const NSRangeException = @"NSRangeException";
NSExceptionName const NSInvalidArgumentException = @"NSInvalidArgumentException";
NSExceptionName const NSInternalInconsistencyException = @"NSInternalInconsistencyException";
NSExceptionName const NSMallocException = @"NSMallocException";

/* Exceptions cannot unwind yet (no unwinder for Mach-O unwind tables), so
 * raising one ends the process with the message macOS would print. */
@implementation NSException
+ (NSException *)exceptionWithName:(NSExceptionName)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo {
    return [[self alloc] initWithName:name reason:reason userInfo:userInfo];
}
+ (void)raise:(NSExceptionName)name format:(NSString *)format, ... {
    va_list ap;
    va_start(ap, format);
    char *reason = BNFormatUTF8(format, ap);
    va_end(ap);
    BNRaise(name.UTF8String, "%s", reason);
}
- (instancetype)initWithName:(NSExceptionName)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo {
    if ((self = [super init])) {
        _name = [name copy];
        _reason = [reason copy];
        _userInfo = [userInfo copy];
    }
    return self;
}
- (void)raise { BNRaise(_name.UTF8String, "%s", _reason ? _reason.UTF8String : ""); }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return _reason ?: _name; }
@end
