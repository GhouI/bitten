/* bitten SDK: <objc/objc.h>, the basic Objective-C types. */
#ifndef BITTEN_OBJC_OBJC_H
#define BITTEN_OBJC_OBJC_H
#include <sys/cdefs.h>
#include <stddef.h>
#include <stdint.h>

#ifndef __OBJC__
typedef struct objc_class *Class;
struct objc_object {
    Class isa;
};
typedef struct objc_object *id;
typedef struct objc_selector *SEL;
#endif
typedef void (*IMP)(void);

/* On x86-64 macOS BOOL is a signed char (Swift imports it as ObjCBool). */
typedef signed char BOOL;
#define OBJC_BOOL_IS_BOOL 0
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#ifndef nil
#define nil ((id)0)
#endif
#ifndef Nil
#define Nil ((Class)0)
#endif

#define OBJC_ROOT_CLASS __attribute__((objc_root_class))
#define OBJC_EXPORT extern
#define OBJC_SWIFT_UNAVAILABLE(msg) __attribute__((availability(swift, unavailable, message = msg)))

__BEGIN_DECLS
const char * _Nonnull sel_getName(SEL _Nonnull sel);
SEL _Nonnull sel_registerName(const char * _Nonnull str);
SEL _Nonnull sel_getUid(const char * _Nonnull str);
BOOL sel_isEqual(SEL _Nonnull lhs, SEL _Nonnull rhs);
const char * _Nonnull object_getClassName(id _Nullable obj);
BOOL object_isClass(id _Nullable obj);
__END_DECLS
#endif
