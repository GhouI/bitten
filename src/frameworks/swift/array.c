/* Bulk operations on runs of values of one type: what the compiler emits for
 * Builtin.copyArray / takeArray* / assign*Array / destroyArray (pointer
 * initialize(from:count:), moveInitialize, deinitialize(count:)...).
 *
 * Plain data is copied with memcpy/memmove; bitwise-takable values are
 * moved with memmove; everything else goes element by element through the
 * type's value witnesses. "FrontToBack"/"BackToFront" give the order for
 * overlapping ranges. */
#include <string.h>

#include "swift_internal.h"

static int is_pod(const sw_vwt *w) { return !(w->flags & SW_VW_IS_NON_POD); }
static int is_bitwise_takable(const sw_vwt *w) { return !(w->flags & SW_VW_IS_NON_BITWISE_TAKABLE); }

static void d_swift_arrayInitWithCopy(char *dst, char *src, size_t n, const sw_metadata *self) {
    const sw_vwt *w = sw_vwt_of(self);
    if (!n) return;
    if (is_pod(w)) {
        memcpy(dst, src, n * w->stride);
        return;
    }
    for (size_t i = 0; i < n; i++)
        w->initializeWithCopy((sw_opaque *)(dst + i * w->stride), (sw_opaque *)(src + i * w->stride), self);
}
DX_FN(swift_arrayInitWithCopy);

static void take(char *dst, char *src, size_t n, const sw_metadata *self, int back_to_front) {
    const sw_vwt *w = sw_vwt_of(self);
    if (!n || dst == src) return;
    if (is_bitwise_takable(w)) {
        memmove(dst, src, n * w->stride);
        return;
    }
    if (back_to_front)
        for (size_t i = n; i-- > 0;)
            w->initializeWithTake((sw_opaque *)(dst + i * w->stride), (sw_opaque *)(src + i * w->stride), self);
    else
        for (size_t i = 0; i < n; i++)
            w->initializeWithTake((sw_opaque *)(dst + i * w->stride), (sw_opaque *)(src + i * w->stride), self);
}
static void d_swift_arrayInitWithTakeNoAlias(char *dst, char *src, size_t n, const sw_metadata *self) {
    take(dst, src, n, self, 0);
}
DX_FN(swift_arrayInitWithTakeNoAlias);
static void d_swift_arrayInitWithTakeFrontToBack(char *dst, char *src, size_t n, const sw_metadata *self) {
    take(dst, src, n, self, 0);
}
DX_FN(swift_arrayInitWithTakeFrontToBack);
static void d_swift_arrayInitWithTakeBackToFront(char *dst, char *src, size_t n, const sw_metadata *self) {
    take(dst, src, n, self, 1);
}
DX_FN(swift_arrayInitWithTakeBackToFront);

static void assign_copy(char *dst, char *src, size_t n, const sw_metadata *self, int back_to_front) {
    const sw_vwt *w = sw_vwt_of(self);
    if (!n) return;
    if (is_pod(w)) {
        memmove(dst, src, n * w->stride);
        return;
    }
    if (back_to_front)
        for (size_t i = n; i-- > 0;)
            w->assignWithCopy((sw_opaque *)(dst + i * w->stride), (sw_opaque *)(src + i * w->stride), self);
    else
        for (size_t i = 0; i < n; i++)
            w->assignWithCopy((sw_opaque *)(dst + i * w->stride), (sw_opaque *)(src + i * w->stride), self);
}
static void d_swift_arrayAssignWithCopyNoAlias(char *dst, char *src, size_t n, const sw_metadata *self) {
    assign_copy(dst, src, n, self, 0);
}
DX_FN(swift_arrayAssignWithCopyNoAlias);
static void d_swift_arrayAssignWithCopyFrontToBack(char *dst, char *src, size_t n, const sw_metadata *self) {
    assign_copy(dst, src, n, self, 0);
}
DX_FN(swift_arrayAssignWithCopyFrontToBack);
static void d_swift_arrayAssignWithCopyBackToFront(char *dst, char *src, size_t n, const sw_metadata *self) {
    assign_copy(dst, src, n, self, 1);
}
DX_FN(swift_arrayAssignWithCopyBackToFront);

static void d_swift_arrayAssignWithTake(char *dst, char *src, size_t n, const sw_metadata *self) {
    const sw_vwt *w = sw_vwt_of(self);
    if (!n) return;
    if (is_pod(w)) {
        memmove(dst, src, n * w->stride);
        return;
    }
    for (size_t i = 0; i < n; i++)
        w->assignWithTake((sw_opaque *)(dst + i * w->stride), (sw_opaque *)(src + i * w->stride), self);
}
DX_FN(swift_arrayAssignWithTake);

static void d_swift_arrayDestroy(char *begin, size_t n, const sw_metadata *self) {
    const sw_vwt *w = sw_vwt_of(self);
    if (!n || is_pod(w)) return;
    for (size_t i = 0; i < n; i++) w->destroy((sw_opaque *)(begin + i * w->stride), self);
}
DX_FN(swift_arrayDestroy);

/* ---- the empty array ----------------------------------------------------------------
 * Every empty Array, ContiguousArray and ArraySlice references this one
 * immortal storage object: {isa, refcount, count 0, capacity 0}, the
 * header of __ContiguousArrayStorageBase. Compiled code names it directly
 * (`_swiftEmptyArrayStorage`). Its class is the standard library's
 * __EmptyArrayStorage, filled in when libswiftCore is loaded; until then
 * the object is only ever compared and retained (a no-op: immortal). */
struct sw_empty_array_storage {
    sw_heap_object header;
    intptr_t count;
    uintptr_t capacity_and_flags;
};
struct sw_empty_array_storage sw_empty_array_storage = {{NULL, ~0ull}, 0, 0};
DX_EXPORT("__swiftEmptyArrayStorage", &sw_empty_array_storage);

void sw_array_image_added(struct dx_image *img) {
    if (sw_empty_array_storage.header.metadata) return;
    const sw_metadata *cls = dx_image_lookup(img, "_$ss19__EmptyArrayStorageCN");
    if (cls) sw_empty_array_storage.header.metadata = cls;
}

/* ---- buffers and element kinds ---------------------------------------------------------- */

/* ManagedBufferPointer's allocation: an instance of any class with a
 * computed size. */
static sw_heap_object *d_swift_bufferAllocate(const sw_metadata *cls, size_t size, size_t align_mask) {
    return sw_alloc_object(cls, size, align_mask);
}
DX_FN(swift_bufferAllocate);

static int is_class_kind(const sw_metadata *m) {
    uintptr_t k = sw_kind(m);
    return k == SW_KIND_CLASS || k == SW_KIND_OBJC_CLASS_WRAPPER || k == SW_KIND_FOREIGN_CLASS;
}

static _Bool d_swift_isClassType(const sw_metadata *m) { return m && is_class_kind(m); }
DX_FN(swift_isClassType);

/* Whether values of the type are object references an NSArray can hold:
 * classes, and class-bound existentials without witness tables (AnyObject,
 * Objective-C protocols). Called from Swift as a generic function taking a
 * metatype: (the metatype value, its generic argument). */
static _Bool d__swift_isClassOrObjCExistentialType(const sw_metadata *value, const sw_metadata *T) {
    (void)T;
    if (!value) return 0;
    if (is_class_kind(value)) return 1;
    if (sw_kind(value) == SW_KIND_EXISTENTIAL) {
        const sw_existential_metadata *e = (const sw_existential_metadata *)value;
        int class_bound = !(e->flags & 0x80000000u);
        return class_bound && (e->flags & 0xFFFFFFu) == 0;
    }
    return 0;
}
DX_FN(_swift_isClassOrObjCExistentialType);
