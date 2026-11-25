/* bitten SDK: <objc/NSObject.h>, the root class and the NSObject protocol.
 * Swift sees them through the ObjectiveC module. */
#ifndef BITTEN_OBJC_NSOBJECT_H
#define BITTEN_OBJC_NSOBJECT_H
#include <objc/objc.h>
#include <objc/NSObjCRuntime.h>

#ifdef __OBJC__
@class NSString, Protocol;
struct _NSZone;

@protocol NSObject
- (BOOL)isEqual:(id)object;
@property (readonly) NSUInteger hash;
@property (readonly) Class superclass;
- (Class)class OBJC_SWIFT_UNAVAILABLE("use 'type(of: x)' instead");
- (instancetype)self;
- (id)performSelector:(SEL)aSelector;
- (id)performSelector:(SEL)aSelector withObject:(id)object;
- (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2;
- (BOOL)isProxy;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)isMemberOfClass:(Class)aClass;
- (BOOL)conformsToProtocol:(Protocol *)aProtocol;
- (BOOL)respondsToSelector:(SEL)aSelector;
- (instancetype)retain OBJC_SWIFT_UNAVAILABLE("use automatic reference counting");
- (oneway void)release OBJC_SWIFT_UNAVAILABLE("use automatic reference counting");
- (instancetype)autorelease OBJC_SWIFT_UNAVAILABLE("use automatic reference counting");
- (NSUInteger)retainCount OBJC_SWIFT_UNAVAILABLE("use automatic reference counting");
- (struct _NSZone *)zone OBJC_SWIFT_UNAVAILABLE("zones are not used");
@property (readonly, copy) NSString *description;
@optional
@property (readonly, copy) NSString *debugDescription;
@end

OBJC_ROOT_CLASS
@interface NSObject <NSObject> {
    Class isa;
}
+ (void)load;
+ (void)initialize;
- (instancetype)init;
+ (instancetype)new OBJC_SWIFT_UNAVAILABLE("use object initializers instead");
+ (instancetype)allocWithZone:(struct _NSZone *)zone OBJC_SWIFT_UNAVAILABLE("use object initializers instead");
+ (instancetype)alloc OBJC_SWIFT_UNAVAILABLE("use object initializers instead");
- (void)dealloc OBJC_SWIFT_UNAVAILABLE("use 'deinit' to define a de-initializer");
- (void)finalize;
- (id)copy;
- (id)mutableCopy;
+ (id)copyWithZone:(struct _NSZone *)zone OBJC_SWIFT_UNAVAILABLE("zones are not used");
+ (id)mutableCopyWithZone:(struct _NSZone *)zone OBJC_SWIFT_UNAVAILABLE("zones are not used");
+ (BOOL)instancesRespondToSelector:(SEL)aSelector;
+ (BOOL)conformsToProtocol:(Protocol *)protocol;
- (IMP)methodForSelector:(SEL)aSelector;
+ (IMP)instanceMethodForSelector:(SEL)aSelector;
- (void)doesNotRecognizeSelector:(SEL)aSelector;
- (id)forwardingTargetForSelector:(SEL)aSelector;
+ (BOOL)resolveClassMethod:(SEL)sel;
+ (BOOL)resolveInstanceMethod:(SEL)sel;
+ (NSUInteger)hash;
+ (Class)superclass;
+ (Class)class OBJC_SWIFT_UNAVAILABLE("use 'aClass.self' instead");
+ (NSString *)description;
+ (NSString *)debugDescription;
+ (BOOL)isSubclassOfClass:(Class)aClass;
@end
#endif
#endif
