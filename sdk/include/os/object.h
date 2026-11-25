/* bitten SDK: <os/object.h>. OS objects (logs, dispatch objects...) are
 * Objective-C objects whose classes are named OS_<type>; in Swift they
 * appear under their Swift names (OSLog, DispatchQueue...) and mangle by
 * their Objective-C names (__C.OS_os_log). In C they are opaque pointers. */
#ifndef BITTEN_OS_OBJECT_H
#define BITTEN_OS_OBJECT_H
#if __OBJC__
#import <objc/NSObject.h>
#define OS_OBJECT_DECL_SWIFT_CLASS(type, swiftname) \
    __attribute__((swift_name(#swiftname))) @interface OS_##type : NSObject @end \
    typedef OS_##type *type##_t
#else
#define OS_OBJECT_DECL_SWIFT_CLASS(type, swiftname) typedef struct type##_s *type##_t
#endif
#endif
