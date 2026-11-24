/* bitten SDK: Objective-C runtime interface (objc/runtime.h, objc/message.h). */
#ifndef BITTEN_OBJC_RUNTIME_H
#define BITTEN_OBJC_RUNTIME_H
#include <stddef.h>
#include <stdint.h>

#ifndef __OBJC__
typedef struct objc_object *id;
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
#endif
typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#ifndef nil
#define nil ((id)0)
#endif
#ifndef Nil
#define Nil ((Class)0)
#endif
typedef void (*IMP)(void);
typedef struct objc_method *Method;
typedef struct objc_ivar *Ivar;
typedef struct objc_property *objc_property_t;
struct objc_super {
    __unsafe_unretained id receiver;
    __unsafe_unretained Class super_class;
};

id objc_msgSend(id self, SEL op, ...);
id objc_msgSendSuper(struct objc_super *super, SEL op, ...);

const char *sel_getName(SEL sel);
SEL sel_registerName(const char *name);
BOOL sel_isEqual(SEL a, SEL b);

Class objc_getClass(const char *name);
Class objc_lookUpClass(const char *name);
Class objc_getMetaClass(const char *name);
Class object_getClass(id obj);
Class object_setClass(id obj, Class cls);
const char *object_getClassName(id obj);
BOOL object_isClass(id obj);
const char *class_getName(Class cls);
Class class_getSuperclass(Class cls);
BOOL class_isMetaClass(Class cls);
size_t class_getInstanceSize(Class cls);
Method class_getInstanceMethod(Class cls, SEL sel);
Method class_getClassMethod(Class cls, SEL sel);
IMP class_getMethodImplementation(Class cls, SEL sel);
BOOL class_respondsToSelector(Class cls, SEL sel);
BOOL class_addMethod(Class cls, SEL sel, IMP imp, const char *types);
IMP class_replaceMethod(Class cls, SEL sel, IMP imp, const char *types);
Method *class_copyMethodList(Class cls, unsigned int *count);
BOOL class_conformsToProtocol(Class cls, Protocol *protocol);
id class_createInstance(Class cls, size_t extraBytes);
SEL method_getName(Method m);
IMP method_getImplementation(Method m);
const char *method_getTypeEncoding(Method m);
IMP method_setImplementation(Method m, IMP imp);
void method_exchangeImplementations(Method a, Method b);
unsigned int method_getNumberOfArguments(Method m);
char *method_copyReturnType(Method m);
char *method_copyArgumentType(Method m, unsigned int index);
Class objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes);
void objc_registerClassPair(Class cls);
void *object_getIndexedIvars(id obj);

typedef unsigned long objc_AssociationPolicy;
enum {
    OBJC_ASSOCIATION_ASSIGN = 0,
    OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1,
    OBJC_ASSOCIATION_COPY_NONATOMIC = 3,
    OBJC_ASSOCIATION_RETAIN = 01401,
    OBJC_ASSOCIATION_COPY = 01403
};
void objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy);
id objc_getAssociatedObject(id object, const void *key);
void objc_removeAssociatedObjects(id object);

void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *pool);
#endif
