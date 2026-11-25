/* Internal structures of the Objective-C runtime. The compiler-emitted
 * layouts (class, class_ro, method/ivar/property/protocol lists, category)
 * follow the documented modern (non-fragile) x86-64 ABI. */
#ifndef DX_OBJC_INTERNAL_H
#define DX_OBJC_INTERNAL_H
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>

#include "dx.h"
#include "dx_objc.h"

typedef const char *SEL;
typedef struct objc_object {
    struct objc_class *isa;
} *id;
typedef struct objc_class *Class;
typedef void (*IMP)(void);

/* Method cache read by the assembly fast path: header, then mask+1 entries,
 * then a sentinel entry {sel = 1, imp = cache} used to wrap around. */
struct cache_entry {
    SEL sel;
    IMP imp;
};
struct cache {
    uintptr_t mask;
    uintptr_t count;
    struct cache_entry e[];
};

struct objc_class {
    Class isa;
    Class superclass;
    struct cache *cache;
    void *vtable;
    uintptr_t bits; /* class_ro before realisation, our class_rw after; low 3 bits are flags */
};
#define CLASS_DATA_MASK 0x00007ffffffffff8UL

/* ---- compiler-emitted metadata ---- */
#define RO_META 0x1
#define RO_ROOT 0x2
struct class_ro {
    uint32_t flags, instance_start, instance_size, reserved;
    const uint8_t *ivar_layout;
    const char *name;
    void *base_methods;
    struct protocol_list *base_protocols;
    struct ivar_list *ivars;
    const uint8_t *weak_ivar_layout;
    struct property_list *base_properties;
};
struct ivar {
    int32_t *offset;
    const char *name, *type;
    uint32_t alignment_raw, size;
};
struct ivar_list {
    uint32_t entsize, count;
    struct ivar first;
};
struct method_list_hdr {
    uint32_t entsize_flags, count;
};
#define METHOD_LIST_SMALL 0x80000000u
#define METHOD_LIST_DIRECT_SEL 0x40000000u
struct big_method {
    const char *name, *types;
    void *imp;
};
struct small_method {
    int32_t name, types, imp;
};
struct property {
    const char *name, *attributes;
};
struct property_list {
    uint32_t entsize, count;
    struct property first;
};
struct protocol;
struct protocol_list {
    uintptr_t count;
    struct protocol *list[];
};
struct protocol {
    Class isa;
    const char *name;
    struct protocol_list *protocols;
    void *instance_methods, *class_methods, *opt_instance_methods, *opt_class_methods;
    struct property_list *instance_properties;
    uint32_t size, flags;
    const char **extended_types;
    const char *demangled;
    struct property_list *class_properties;
};
struct category {
    const char *name;
    Class cls;
    void *instance_methods, *class_methods;
    struct protocol_list *protocols;
    struct property_list *instance_properties;
    struct property_list *class_properties;
};

/* ---- runtime-side data ---- */
struct method {
    SEL name;
    const char *types;
    IMP imp;
};
typedef struct method *Method;
struct mlist {
    struct mlist *next;
    int count;
    struct method m[];
};

#define RW_REALIZED 0x80000000u
#define RW_META 0x1
#define RW_INITIALIZED 0x2
#define RW_INITIALIZING 0x4
#define RW_DYNAMIC 0x8      /* created with objc_allocateClassPair */
#define RW_REGISTERED 0x10
struct class_rw {
    uint32_t flags; /* first, so it overlays class_ro.flags; bit 31 tells them apart */
    uint32_t instance_size;
    const struct class_ro *ro;
    struct mlist *methods;
    struct protocol **protocols;
    int nprotocols;
    struct property_list **properties;
    int nproperties;
    Class nonmeta; /* for a metaclass: its class */
    Class next_realized;
    int rr_state;   /* 0 unknown, 1 NSObject's retain/release, 2 custom */
    void *(*os_retain)(void *);
    void (*os_release)(void *);
    pthread_t init_thread;
};

static inline struct class_rw *RW(Class c) { return (struct class_rw *)(c->bits & CLASS_DATA_MASK); }
static inline int class_realized(Class c) {
    return c->bits && (RW(c)->flags & RW_REALIZED);
}
static inline int class_is_meta(Class c) { return (RW(c)->flags & RW_META) != 0; }

/* runtime.c */
extern pthread_mutex_t dx_objc_lock; /* recursive */
SEL sel_intern(const char *name);
void realize_class(Class cls);
void ensure_initialized(Class cls);
IMP class_lookup_imp(Class cls, SEL sel); /* NULL when not found; no forwarding */
Class objc_class_of(id obj);
Class make_class(Class storage, Class meta_storage, Class super, const char *name, size_t extra);
void add_method(Class cls, const char *sel, IMP imp, const char *types);
id class_create_instance(Class cls, size_t extra);
const char *class_name(Class cls);
void flush_caches(void);
extern struct objc_class dx_NSObject_class, dx_NSObject_meta;

/* msgsend.S */
/* Declared without a prototype on purpose: every call site casts it to the
 * signature of the message being sent. */
void dx_objc_msgSend(void);
extern void (*const dx_objc_msgSend_ptr)(void);
#define MSG(ret, ...) ((ret (*)(__VA_ARGS__))dx_objc_msgSend_ptr)

/* arc.c */
id root_retain(id obj);
void root_release(id obj);
int root_try_retain(id obj);
unsigned long root_retain_count(id obj);
id root_autorelease(id obj); /* adds to the current pool, no message */
void object_dispose_impl(id obj);
extern SEL SEL_retain, SEL_release, SEL_autorelease, SEL_dealloc, SEL_alloc, SEL_init, SEL_new,
    SEL_class, SEL_copyWithZone, SEL_mutableCopyWithZone, SEL_initialize, SEL_load,
    SEL_cxx_destruct, SEL_cxx_construct, SEL_resolveInstanceMethod, SEL_resolveClassMethod,
    SEL_forwardingTargetForSelector, SEL_respondsToSelector, SEL_isKindOfClass, SEL_self,
    SEL_allocWithZone, SEL_retainCount, SEL_copy, SEL_allowsWeakReference, SEL_retainWeakReference;

#endif
