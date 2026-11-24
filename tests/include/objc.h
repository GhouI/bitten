/* Hand-written Objective-C declarations for the Mach-O tests: the root
 * class and runtime functions bitten provides. Not Apple headers. */
#ifndef TESTS_OBJC_H
#define TESTS_OBJC_H
#include "darwin.h"

typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#define nil ((id)0)

@protocol NSObject
- (BOOL)isEqual:(id)other;
- (Class)class;
- (BOOL)respondsToSelector:(SEL)sel;
- (BOOL)isKindOfClass:(Class)cls;
- (BOOL)conformsToProtocol:(Protocol *)p;
@end

__attribute__((objc_root_class))
@interface NSObject <NSObject> {
    Class isa;
}
+ (id)alloc;
+ (id)new;
+ (Class)class;
+ (Class)superclass;
+ (BOOL)instancesRespondToSelector:(SEL)sel;
+ (BOOL)isSubclassOfClass:(Class)cls;
+ (BOOL)resolveInstanceMethod:(SEL)sel;
+ (void)initialize;
+ (void)load;
- (id)init;
- (void)dealloc;
- (id)copy;
- (Class)superclass;
- (unsigned long)hash;
- (unsigned long)retainCount;
- (BOOL)isMemberOfClass:(Class)cls;
- (id)performSelector:(SEL)sel;
- (id)performSelector:(SEL)sel withObject:(id)a;
- (id)forwardingTargetForSelector:(SEL)sel;
@end

@protocol NSCopying
- (id)copyWithZone:(void *)zone;
@end

const char *sel_getName(SEL);
SEL sel_registerName(const char *);
Class objc_getClass(const char *);
const char *class_getName(Class);
Class class_getSuperclass(Class);
Class object_getClass(id);
size_t class_getInstanceSize(Class);
BOOL class_addMethod(Class, SEL, void (*)(void), const char *);
BOOL class_respondsToSelector(Class, SEL);
typedef struct objc_method *Method;
Method class_getInstanceMethod(Class, SEL);
void method_exchangeImplementations(Method, Method);
Class objc_allocateClassPair(Class, const char *, size_t);
void objc_registerClassPair(Class);
void objc_setAssociatedObject(id, const void *, id, unsigned long);
id objc_getAssociatedObject(id, const void *);
void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *);
#endif
