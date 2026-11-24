#import "FoundationInternal.h"

void BNRaise(const char *name, const char *format, ...) {
    char message[1024];
    va_list ap;
    va_start(ap, format);
    vsnprintf(message, sizeof message, format, ap);
    va_end(ap);
    dprintf(2, "*** Terminating app due to uncaught exception '%s', reason: '%s'\n", name, message);
    abort();
}

NSString *BNDescribe(id object) {
    if (!object) return @"(null)";
    NSString *d = [object description];
    return d ? d : @"(null)";
}

/* NSObject itself lives in the Objective-C runtime; Foundation adds the
 * parts that need NSString. */
@interface NSObject (FoundationAdditions)
@end
@implementation NSObject (FoundationAdditions)
- (NSString *)description {
    return [NSString stringWithFormat:@"<%s: %p>", object_getClassName(self), self];
}
- (NSString *)debugDescription {
    return [self description];
}
+ (NSString *)description {
    return [NSString stringWithUTF8String:class_getName(self)];
}
@end

NSString *NSStringFromClass(Class cls) { return cls ? [NSString stringWithUTF8String:class_getName(cls)] : nil; }
NSString *NSStringFromSelector(SEL sel) { return sel ? [NSString stringWithUTF8String:sel_getName(sel)] : nil; }
Class NSClassFromString(NSString *name) { return name ? objc_getClass(name.UTF8String) : Nil; }
SEL NSSelectorFromString(NSString *name) { return name ? sel_registerName(name.UTF8String) : NULL; }

/* The bridged classes (NSNull, NSString, NSArray, ...) are created by
 * CoreFoundation so that CF objects can be instances of them; Foundation
 * supplies their methods as categories. */
@implementation NSNull (Foundation)
+ (NSNull *)null { return (__bridge NSNull *)kCFNull; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return @"<null>"; }
@end

@implementation NSAutoreleasePool {
    void *_token;
}
- (instancetype)init {
    if ((self = [super init])) _token = objc_autoreleasePoolPush();
    return self;
}
- (void)drain {
    if (_token) objc_autoreleasePoolPop(_token);
    _token = NULL;
}
- (void)dealloc { [self drain]; }
@end
