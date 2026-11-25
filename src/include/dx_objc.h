/* Contracts between the Objective-C runtime, the Blocks runtime and the
 * libraries built on them (libdispatch, CoreFoundation, Foundation). */
#ifndef DX_OBJC_H
#define DX_OBJC_H
#include <stddef.h>
#include <stdint.h>

/* ---- Blocks (src/frameworks/objc/blocks.c) ------------------------------
 * A block is called through its invoke pointer with the block itself as the
 * first argument. */
struct dx_block {
    void *isa;
    int flags;
    int reserved;
    void (*invoke)(void *block, ...);
    void *descriptor;
};
void *dx_block_copy(const void *block);    /* _Block_copy */
void dx_block_release(const void *block);  /* _Block_release */

/* ---- OS objects ---------------------------------------------------------
 * Objective-C code built with ARC sends -retain and -release to dispatch,
 * XPC and similar objects, so each such object must start with an isa
 * pointer to a real class. This returns (creating on first use) a class
 * named `name` whose -retain / -release / -dealloc call the given functions
 * with the object. `super_name` may be NULL (the class then inherits from
 * OS_object). Store the result in the object's first pointer-sized field. */
void *dx_os_object_class(const char *name, const char *super_name, void *(*retain)(void *),
                         void (*release)(void *)) __attribute__((weak));
void *dx_os_object_class_in(void *storage, void *meta_storage, const char *name, void *(*retain)(void *),
                            void (*release)(void *)) __attribute__((weak));

/* ---- runtime entry points used by other C code -------------------------- */
typedef struct dx_objc_class *dx_class;
typedef const char *dx_sel; /* selectors are interned C strings */
dx_sel dx_sel_register(const char *name);
dx_class dx_objc_lookup_class(const char *name);
void *dx_objc_retain(void *obj);
void dx_objc_release(void *obj);
void *dx_objc_autorelease(void *obj);
/* objc_initWeak, objc_storeWeak, objc_loadWeakRetained, objc_destroyWeak,
 * objc_copyWeak, objc_moveWeak */
void *dx_objc_init_weak(void **slot, void *obj);
void *dx_objc_store_weak(void **slot, void *obj);
void *dx_objc_load_weak_retained(void **slot);
void dx_objc_destroy_weak(void **slot);
void dx_objc_copy_weak(void **dst, void **src);
void dx_objc_move_weak(void **dst, void **src);
/* Forgets an object that is being freed: clears __weak variables pointing
 * to it and releases its associated objects. */
void dx_objc_object_destroyed(void *obj);

#endif
