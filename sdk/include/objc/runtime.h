/* bitten SDK: <objc/runtime.h>, the Objective-C runtime functions bitten
 * implements. */
#ifndef BITTEN_OBJC_RUNTIME_H
#define BITTEN_OBJC_RUNTIME_H
#include <objc/objc.h>
#include <objc/message.h>

#ifdef __OBJC__
@class Protocol;
#else
typedef struct objc_object Protocol;
#endif
typedef struct objc_method *Method;
typedef struct objc_ivar *Ivar;
typedef struct objc_category *Category;
typedef struct objc_property *objc_property_t;
struct objc_method_description {
    SEL name;
    char *types;
};

typedef unsigned long objc_AssociationPolicy;
enum {
    OBJC_ASSOCIATION_ASSIGN = 0,
    OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1,
    OBJC_ASSOCIATION_COPY_NONATOMIC = 3,
    OBJC_ASSOCIATION_RETAIN = 01401,
    OBJC_ASSOCIATION_COPY = 01403
};

__BEGIN_DECLS
Class objc_getClass(const char *name);
Class objc_lookUpClass(const char *name);
Class objc_getRequiredClass(const char *name);
Class objc_getMetaClass(const char *name);
int objc_getClassList(Class *buffer, int count);
Class *objc_copyClassList(unsigned int *count);
Protocol *objc_getProtocol(const char *name);
Class objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes);
void objc_registerClassPair(Class cls);
void objc_disposeClassPair(Class cls);
id objc_constructInstance(Class cls, void *bytes);
void *objc_destructInstance(id obj);
void objc_enumerationMutation(id obj);

Class object_getClass(id obj);
Class object_setClass(id obj, Class cls);
id object_copy(id obj, size_t size);
id object_dispose(id obj);
id object_getIvar(id obj, Ivar ivar);
void object_setIvar(id obj, Ivar ivar, id value);
void *object_getIndexedIvars(id obj);

const char *class_getName(Class cls);
Class class_getSuperclass(Class cls);
BOOL class_isMetaClass(Class cls);
int class_getVersion(Class cls);
void class_setVersion(Class cls, int version);
size_t class_getInstanceSize(Class cls);
Ivar class_getInstanceVariable(Class cls, const char *name);
Ivar *class_copyIvarList(Class cls, unsigned int *count);
Method class_getInstanceMethod(Class cls, SEL sel);
Method class_getClassMethod(Class cls, SEL sel);
IMP class_getMethodImplementation(Class cls, SEL sel);
BOOL class_respondsToSelector(Class cls, SEL sel);
Method *class_copyMethodList(Class cls, unsigned int *count);
BOOL class_conformsToProtocol(Class cls, Protocol *protocol);
Protocol *__unsafe_unretained *class_copyProtocolList(Class cls, unsigned int *count);
objc_property_t class_getProperty(Class cls, const char *name);
objc_property_t *class_copyPropertyList(Class cls, unsigned int *count);
BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);
IMP class_replaceMethod(Class cls, SEL name, IMP imp, const char *types);
BOOL class_addIvar(Class cls, const char *name, size_t size, uint8_t alignment, const char *types);
BOOL class_addProtocol(Class cls, Protocol *protocol);
id class_createInstance(Class cls, size_t extraBytes);

SEL method_getName(Method m);
IMP method_getImplementation(Method m);
const char *method_getTypeEncoding(Method m);
unsigned int method_getNumberOfArguments(Method m);
char *method_copyReturnType(Method m);
char *method_copyArgumentType(Method m, unsigned int index);
void method_getReturnType(Method m, char *dst, size_t dst_len);
IMP method_setImplementation(Method m, IMP imp);
void method_exchangeImplementations(Method m1, Method m2);

const char *ivar_getName(Ivar v);
const char *ivar_getTypeEncoding(Ivar v);
ptrdiff_t ivar_getOffset(Ivar v);
const char *property_getName(objc_property_t property);
const char *property_getAttributes(objc_property_t property);

const char *protocol_getName(Protocol *proto);
BOOL protocol_isEqual(Protocol *proto, Protocol *other);
BOOL protocol_conformsToProtocol(Protocol *proto, Protocol *other);
struct objc_method_description protocol_getMethodDescription(Protocol *proto, SEL aSel,
                                                             BOOL isRequiredMethod, BOOL isInstanceMethod);
BOOL sel_isMapped(SEL sel);

void objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy);
id objc_getAssociatedObject(id object, const void *key);
void objc_removeAssociatedObjects(id object);

void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *pool);
int objc_sync_enter(id obj);
int objc_sync_exit(id obj);
id objc_loadWeak(id *location);
id objc_storeWeak(id *location, id obj);
__END_DECLS
#endif
