/* Swift and Objective-C: the root class every Swift class inherits from,
 * references whose kind (Swift or Objective-C) is only known at run time,
 * and bridge objects.
 *
 * Swift classes are Objective-C classes. swiftc lists them in
 * __objc_classlist with `_TtCs12_SwiftObject` as root, and marks them in the
 * low bits of the class `data` word; our Objective-C runtime realises them
 * lazily like any other class. SwiftObject's memory-management methods use
 * Swift reference counting, so objc_msgSend(-retain), objc_retain (which
 * sees a class with custom retain/release and sends the message) and
 * autorelease pools all end up in heap.c. */
#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>

#include "../objc/objc_internal.h"
#include "swift_internal.h"

static inline int valid(const void *p) { return (intptr_t)p > 0; }
/* Objective-C tagged pointers use bit 0 on x86-64 macOS (and the sign bit
 * on other platforms); neither is a heap object. */
static inline int tagged_or_null(const void *p) {
    return !p || ((uintptr_t)p & SW_OBJC_RESERVED_BITS_MASK);
}

/* ---- the root class ------------------------------------------------------------ */

struct sw_class_metadata sw_SwiftObject_class;
static struct objc_class swift_object_meta;
DX_EXPORT("_OBJC_CLASS_$__TtCs12_SwiftObject", &sw_SwiftObject_class);
DX_EXPORT("_OBJC_METACLASS_$__TtCs12_SwiftObject", &swift_object_meta);

int sw_is_native(const void *obj) {
    if (tagged_or_null(obj) || !valid(obj)) return 0;
    const sw_metadata *m = ((const sw_heap_object *)obj)->metadata;
    /* boxes and closure contexts: heap metadata that is not a class */
    if (m->kind <= SW_KIND_LAST_ENUMERATED) return 1;
    const sw_class_metadata *c = (const sw_class_metadata *)m;
    if (c == &sw_SwiftObject_class) return 1;
    /* A Swift class that inherits from NSObject is a Swift class without
     * Swift reference counting. Dynamic subclasses (made with
     * objc_allocateClassPair) are not marked; they reach Swift counting
     * through SwiftObject's methods instead. */
    return sw_class_is_swift(c) && (c->flags & SW_CLASS_USES_SWIFT_REFCOUNTING);
}

static id so_retain(id self, SEL _cmd) { return (id)sw_retain((sw_heap_object *)self); }
static void so_release(id self, SEL _cmd) { sw_release((sw_heap_object *)self); }
static id so_autorelease(id self, SEL _cmd) { return root_autorelease(self); }
static unsigned long so_retainCount(id self, SEL _cmd) { return sw_retain_count((sw_heap_object *)self); }
static char so_tryRetain(id self, SEL _cmd) {
    return sw_try_retain((sw_heap_object *)self);
}
static char so_isDeallocating(id self, SEL _cmd) { return sw_is_deiniting((sw_heap_object *)self); }
static char so_allowsWeakReference(id self, SEL _cmd) { return !sw_is_deiniting((sw_heap_object *)self); }
/* -dealloc sent directly: tear the object down as a final release would. */
static void so_dealloc(id self, SEL _cmd) {
    sw_set_deallocating((sw_heap_object *)self);
    sw_destroy((sw_heap_object *)self);
}
static id so_description(id self, SEL _cmd) {
    void *(*create)(void *, const char *, uint32_t) = dx_registry_lookup("_CFStringCreateWithCString");
    if (!create) return NULL;
    char buf[256];
    Class c = objc_class_of(self);
    if (class_realized(c) && class_is_meta(c)) snprintf(buf, sizeof buf, "%s", class_name((Class)self));
    else snprintf(buf, sizeof buf, "<%s: %p>", class_name(c), (void *)self);
    return root_autorelease(create(NULL, buf, 0x08000100 /* UTF-8 */));
}

static size_t instance_size(Class cls, size_t *align_mask) {
    const sw_class_metadata *m = (const sw_class_metadata *)cls;
    if (m != &sw_SwiftObject_class && sw_class_is_swift(m)) {
        *align_mask = m->instance_align_mask;
        return m->instance_size;
    }
    *align_mask = 7;
    return sizeof(sw_heap_object);
}
static id so_alloc(id self, SEL _cmd) {
    Class cls = (Class)self;
    size_t am, size = instance_size(cls, &am);
    sw_heap_object *o = sw_alloc_object((const sw_metadata *)cls, size, am);
    memset(o + 1, 0, size - sizeof *o);
    return (id)o;
}
static id so_allocWithZone(id self, SEL _cmd, void *zone) { return so_alloc(self, _cmd); }
static id so_cls_self(id self, SEL _cmd) { return self; }
static void so_nothing(id self, SEL _cmd) {}

/* Methods whose NSObject versions are not about memory and work on any
 * object: shared rather than written twice. */
static const struct {
    const char *sel, *types;
} shared_instance[] = {
    {"init", "@16@0:8"},
    {"self", "@16@0:8"},
    {"class", "#16@0:8"},
    {"superclass", "#16@0:8"},
    {"isKindOfClass:", "c24@0:8#16"},
    {"isMemberOfClass:", "c24@0:8#16"},
    {"respondsToSelector:", "c24@0:8:16"},
    {"conformsToProtocol:", "c24@0:8@16"},
    {"isEqual:", "c24@0:8@16"},
    {"hash", "Q16@0:8"},
    {"isProxy", "c16@0:8"},
    {"zone", "^v16@0:8"},
    {"performSelector:", "@24@0:8:16"},
    {"performSelector:withObject:", "@32@0:8:16@24"},
    {"performSelector:withObject:withObject:", "@40@0:8:16@24@32"},
    {"methodForSelector:", "^?24@0:8:16"},
    {"doesNotRecognizeSelector:", "v24@0:8:16"},
    {"forwardingTargetForSelector:", "@24@0:8:16"},
}, shared_class[] = {
    {"new", "@16@0:8"},
    {"class", "#16@0:8"},
    {"superclass", "#16@0:8"},
    {"isSubclassOfClass:", "c24@0:8#16"},
    {"isKindOfClass:", "c24@0:8#16"},
    {"respondsToSelector:", "c24@0:8:16"},
    {"instancesRespondToSelector:", "c24@0:8:16"},
    {"instanceMethodForSelector:", "^?24@0:8:16"},
    {"conformsToProtocol:", "c24@0:8@16"},
    {"resolveInstanceMethod:", "c24@0:8:16"},
    {"resolveClassMethod:", "c24@0:8:16"},
    {"isEqual:", "c24@0:8@16"},
    {"hash", "Q16@0:8"},
};

__attribute__((constructor(102))) static void swift_object_init(void) {
    Class so = make_class((Class)&sw_SwiftObject_class, &swift_object_meta, NULL, "_TtCs12_SwiftObject", 0);
    RW(so)->instance_size = sizeof(sw_heap_object); /* isa and the reference counts */
    Class meta = so->isa;
    for (size_t i = 0; i < sizeof shared_instance / sizeof *shared_instance; i++)
        add_method(so, shared_instance[i].sel, class_lookup_imp(&dx_NSObject_class, sel_intern(shared_instance[i].sel)),
                   shared_instance[i].types);
    for (size_t i = 0; i < sizeof shared_class / sizeof *shared_class; i++)
        add_method(meta, shared_class[i].sel, class_lookup_imp(&dx_NSObject_meta, sel_intern(shared_class[i].sel)),
                   shared_class[i].types);
#define I(sel, fn, types) add_method(so, sel, (IMP)fn, types)
#define C(sel, fn, types) add_method(meta, sel, (IMP)fn, types)
    I("retain", so_retain, "@16@0:8");
    I("release", so_release, "Vv16@0:8");
    I("autorelease", so_autorelease, "@16@0:8");
    I("retainCount", so_retainCount, "Q16@0:8");
    I("_tryRetain", so_tryRetain, "c16@0:8");
    I("_isDeallocating", so_isDeallocating, "c16@0:8");
    I("allowsWeakReference", so_allowsWeakReference, "c16@0:8");
    I("retainWeakReference", so_tryRetain, "c16@0:8");
    I("dealloc", so_dealloc, "v16@0:8");
    I("description", so_description, "@16@0:8");
    I("debugDescription", so_description, "@16@0:8");
    C("alloc", so_alloc, "@16@0:8");
    C("allocWithZone:", so_allocWithZone, "@24@0:8^v16");
    C("load", so_nothing, "v16@0:8");
    C("initialize", so_nothing, "v16@0:8");
    C("self", so_cls_self, "@16@0:8");
    C("retain", so_cls_self, "@16@0:8");
    C("release", so_nothing, "Vv16@0:8");
    C("autorelease", so_cls_self, "@16@0:8");
    C("description", so_description, "@16@0:8");
    C("debugDescription", so_description, "@16@0:8");
#undef I
#undef C
    void dx_objc_register_class(Class cls);
    dx_objc_register_class(so);
}

/* ---- unknown objects: Swift or Objective-C ---------------------------------------- */

void *sw_unknown_retain(void *obj) {
    if (tagged_or_null(obj)) return obj;
    if (sw_is_native(obj)) return sw_retain(obj);
    return dx_objc_retain(obj);
}
void sw_unknown_release(void *obj) {
    if (tagged_or_null(obj)) return;
    if (sw_is_native(obj)) sw_release(obj);
    else dx_objc_release(obj);
}
static void *d_swift_unknownObjectRetain(void *obj) { return sw_unknown_retain(obj); }
DX_FN(swift_unknownObjectRetain);
DX_EXPORT("_swift_nonatomic_unknownObjectRetain", d_swift_unknownObjectRetain);
static void d_swift_unknownObjectRelease(void *obj) { sw_unknown_release(obj); }
DX_FN(swift_unknownObjectRelease);
DX_EXPORT("_swift_nonatomic_unknownObjectRelease", d_swift_unknownObjectRelease);

static void *d_swift_unknownObjectRetain_n(void *obj, uint32_t n) {
    if (tagged_or_null(obj)) return obj;
    if (sw_is_native(obj)) return sw_retain_n(obj, n);
    while (n--) dx_objc_retain(obj);
    return obj;
}
DX_FN(swift_unknownObjectRetain_n);
DX_EXPORT("_swift_nonatomic_unknownObjectRetain_n", d_swift_unknownObjectRetain_n);
static void d_swift_unknownObjectRelease_n(void *obj, uint32_t n) {
    if (tagged_or_null(obj)) return;
    if (sw_is_native(obj)) {
        sw_release_n(obj, n);
        return;
    }
    while (n--) dx_objc_release(obj);
}
DX_FN(swift_unknownObjectRelease_n);
DX_EXPORT("_swift_nonatomic_unknownObjectRelease_n", d_swift_unknownObjectRelease_n);

/* ---- bridge objects ------------------------------------------------------------------
 * A Builtin.BridgeObject is a reference with flags in its spare bits (see
 * swift_abi.h). Values with a reserved bit set are left alone: Objective-C
 * tagged pointers and the immortal storage of String literals. */
static void *bridge_target(uintptr_t bits) { return (void *)(bits & ~SW_BRIDGE_SPARE_MASK); }

void *sw_bridge_retain(void *bits) {
    uintptr_t b = (uintptr_t)bits;
    if (!b || (b & SW_BRIDGE_TAG_MASK)) return bits;
    if (b & SW_BRIDGE_OBJC_BIT) dx_objc_retain(bridge_target(b));
    else sw_retain(bridge_target(b));
    return bits;
}
void sw_bridge_release(void *bits) {
    uintptr_t b = (uintptr_t)bits;
    if (!b || (b & SW_BRIDGE_TAG_MASK)) return;
    if (b & SW_BRIDGE_OBJC_BIT) dx_objc_release(bridge_target(b));
    else sw_release(bridge_target(b));
}
static void *d_swift_bridgeObjectRetain(void *bits) { return sw_bridge_retain(bits); }
DX_FN(swift_bridgeObjectRetain);
DX_EXPORT("_swift_nonatomic_bridgeObjectRetain", d_swift_bridgeObjectRetain);
static void d_swift_bridgeObjectRelease(void *bits) { sw_bridge_release(bits); }
DX_FN(swift_bridgeObjectRelease);
DX_EXPORT("_swift_nonatomic_bridgeObjectRelease", d_swift_bridgeObjectRelease);
static void *d_swift_bridgeObjectRetain_n(void *bits, uint32_t n) {
    uintptr_t b = (uintptr_t)bits;
    if (!b || (b & SW_BRIDGE_TAG_MASK)) return bits;
    if (b & SW_BRIDGE_OBJC_BIT) d_swift_unknownObjectRetain_n(bridge_target(b), n);
    else sw_retain_n(bridge_target(b), n);
    return bits;
}
DX_FN(swift_bridgeObjectRetain_n);
DX_EXPORT("_swift_nonatomic_bridgeObjectRetain_n", d_swift_bridgeObjectRetain_n);
static void d_swift_bridgeObjectRelease_n(void *bits, uint32_t n) {
    uintptr_t b = (uintptr_t)bits;
    if (!b || (b & SW_BRIDGE_TAG_MASK)) return;
    if (b & SW_BRIDGE_OBJC_BIT) d_swift_unknownObjectRelease_n(bridge_target(b), n);
    else sw_release_n(bridge_target(b), n);
}
DX_FN(swift_bridgeObjectRelease_n);
DX_EXPORT("_swift_nonatomic_bridgeObjectRelease_n", d_swift_bridgeObjectRelease_n);
