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
