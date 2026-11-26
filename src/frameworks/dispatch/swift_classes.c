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

void *dispatch_object_class(const char *name, const char *super);   /* queue.c */

struct class_storage { void *w[5]; };

#define CLASSES(X) X(object) X(queue) X(group) X(semaphore) X(source) X(data)

#define STORAGE(type)                                                            \
    static struct class_storage cls_##type, meta_##type;                         \
    DX_EXPORT("_OBJC_CLASS_$_OS_dispatch_" #type, &cls_##type);                  \
    DX_EXPORT("_OBJC_METACLASS_$_OS_dispatch_" #type, &meta_##type);
CLASSES(STORAGE)

/* Swift code can name these classes before any object of the kind exists
 * (messaging the class, reading its metadata), so build all six as soon as
 * the Objective-C runtime and the dispatch root classes are up (queue.c
 * builds OS_dispatch_object and OS_dispatch_queue at priority 102), before
 * any image loads. */
__attribute__((constructor(110))) static void build_exported_classes(void) {
    dispatch_object_class("OS_dispatch_object", NULL);
    dispatch_object_class("OS_dispatch_queue", "OS_dispatch_object");
    dispatch_object_class("OS_dispatch_group", "OS_dispatch_object");
    dispatch_object_class("OS_dispatch_semaphore", "OS_dispatch_object");
    dispatch_object_class("OS_dispatch_source", "OS_dispatch_object");
    dispatch_object_class("OS_dispatch_data", "OS_dispatch_object");
}

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
