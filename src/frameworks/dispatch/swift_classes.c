/* The dispatch classes Swift code refers to by symbol.
 *
 * Swift sees dispatch objects as Objective-C classes (DispatchQueue is
 * OS_dispatch_queue, see sdk/include/dispatch/swift.h) and compiled code
 * names them through _OBJC_CLASS_$_OS_dispatch_<type>. Those classes are
 * built here, in exported storage, by dispatch_object_class() (queue.c),
 * which asks this file for storage before creating a class at run time; so
 * the class a dispatch object points to and the one Swift code binds to are
 * the same object. Other dispatch classes (OS_dispatch_queue_serial...) are
 * still created at run time, as subclasses of these. */
#include <string.h>

#include "dx.h"

struct class_storage { void *w[5]; };

#define CLASSES(X) X(object) X(queue) X(group) X(semaphore) X(source) X(data)

#define STORAGE(type)                                                            \
    static struct class_storage cls_##type, meta_##type;                         \
    DX_EXPORT("_OBJC_CLASS_$_OS_dispatch_" #type, &cls_##type);                  \
    DX_EXPORT("_OBJC_METACLASS_$_OS_dispatch_" #type, &meta_##type);
CLASSES(STORAGE)

int dispatch_exported_class_storage(const char *name, void **storage, void **meta) {
#define MATCH(type)                                                              \
    if (!strcmp(name, "OS_dispatch_" #type)) {                                   \
        *storage = &cls_##type;                                                  \
        *meta = &meta_##type;                                                    \
        return 1;                                                                \
    }
    CLASSES(MATCH)
    return 0;
}
