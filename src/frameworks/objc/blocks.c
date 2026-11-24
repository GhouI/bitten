/* Blocks runtime: the support library behind C/Objective-C `^{ }` closures.
 * Implements the documented Blocks ABI (block literal and byref layouts,
 * copy/dispose helpers). */
#include <stdlib.h>
#include <string.h>

#include "dx.h"
#include "dx_objc.h"

enum {
    BLOCK_DEALLOCATING = 0x0001,
    BLOCK_REFCOUNT_MASK = 0xfffe,
    BLOCK_NEEDS_FREE = 1 << 24,
    BLOCK_HAS_COPY_DISPOSE = 1 << 25,
    BLOCK_IS_GLOBAL = 1 << 28,
    BLOCK_HAS_SIGNATURE = 1 << 30,
};
enum {
    BLOCK_FIELD_IS_OBJECT = 3,
    BLOCK_FIELD_IS_BLOCK = 7,
    BLOCK_FIELD_IS_BYREF = 8,
    BLOCK_FIELD_IS_WEAK = 16,
    BLOCK_BYREF_CALLER = 128,
};

struct descriptor {
    unsigned long reserved, size;
    /* present when BLOCK_HAS_COPY_DISPOSE: */
    void (*copy)(void *dst, const void *src);
    void (*dispose)(const void *);
};

struct byref {
    void *isa;
    struct byref *forwarding;
    volatile int flags;
    unsigned size;
    /* present when BLOCK_HAS_COPY_DISPOSE: */
    void (*keep)(struct byref *dst, struct byref *src);
    void (*destroy)(struct byref *);
};

/* Block class objects. The Objective-C runtime turns these into real
 * classes at start-up so blocks answer -copy, -retain and -release. */
void *dx_NSConcreteStackBlock[32], *dx_NSConcreteMallocBlock[32], *dx_NSConcreteGlobalBlock[32];
static void *auto_block[32], *finalizing_block[32], *weak_block_variable[32];
DX_EXPORT("__NSConcreteStackBlock", dx_NSConcreteStackBlock);
DX_EXPORT("__NSConcreteMallocBlock", dx_NSConcreteMallocBlock);
DX_EXPORT("__NSConcreteGlobalBlock", dx_NSConcreteGlobalBlock);
DX_EXPORT("__NSConcreteAutoBlock", auto_block);
DX_EXPORT("__NSConcreteFinalizingBlock", finalizing_block);
DX_EXPORT("__NSConcreteWeakBlockVariable", weak_block_variable);

/* Captured Objective-C objects are retained and released through these;
 * the Objective-C runtime installs the real functions. */
static void *retain_nothing(void *o) { return o; }
static void release_nothing(void *o) { (void)o; }
void *(*dx_block_retain_object)(void *) = retain_nothing;
void (*dx_block_release_object)(void *) = release_nothing;

void *dx_block_copy(const void *arg) {
    struct dx_block *b = (struct dx_block *)arg;
    if (!b) return NULL;
    if (b->flags & BLOCK_NEEDS_FREE) {
        __atomic_add_fetch(&b->flags, 2, __ATOMIC_RELAXED);
        return b;
    }
    if (b->flags & BLOCK_IS_GLOBAL) return b;
    struct descriptor *d = b->descriptor;
    struct dx_block *copy = malloc(d->size);
    if (!copy) return NULL;
    memmove(copy, b, d->size);
    copy->flags &= ~(BLOCK_REFCOUNT_MASK | BLOCK_DEALLOCATING);
    copy->flags |= BLOCK_NEEDS_FREE | 2; /* reference count 1 */
    copy->isa = dx_NSConcreteMallocBlock;
    if (b->flags & BLOCK_HAS_COPY_DISPOSE) d->copy(copy, b);
    return copy;
}
DX_EXPORT("__Block_copy", dx_block_copy);

void dx_block_release(const void *arg) {
    struct dx_block *b = (struct dx_block *)arg;
    if (!b || (b->flags & BLOCK_IS_GLOBAL) || !(b->flags & BLOCK_NEEDS_FREE)) return;
    int now = __atomic_sub_fetch(&b->flags, 2, __ATOMIC_ACQ_REL);
    if ((now & BLOCK_REFCOUNT_MASK) != 0) return;
    if (b->flags & BLOCK_HAS_COPY_DISPOSE) ((struct descriptor *)b->descriptor)->dispose(b);
    free(b);
}
DX_EXPORT("__Block_release", dx_block_release);

static struct byref *byref_copy(struct byref *src) {
    if ((src->forwarding->flags & BLOCK_REFCOUNT_MASK) == 0) {
        /* still on the stack: move it to the heap, shared by both sides */
        struct byref *copy = malloc(src->size);
        if (!copy) return src;
        copy->isa = NULL;
        copy->flags = src->flags | BLOCK_NEEDS_FREE | 4; /* caller + stack */
        copy->forwarding = copy;
        copy->size = src->size;
        src->forwarding = copy;
        if (src->flags & BLOCK_HAS_COPY_DISPOSE) {
            copy->keep = src->keep;
            copy->destroy = src->destroy;
            /* a layout word may follow; keep() copies the variable itself */
            size_t fixed = sizeof(struct byref);
            if (src->size > fixed) memmove((char *)copy + fixed, (char *)src + fixed, src->size - fixed);
            src->keep(copy, src);
        } else {
            size_t fixed = offsetof(struct byref, keep);
            memmove((char *)copy + fixed, (char *)src + fixed, src->size - fixed);
        }
    } else if (src->forwarding->flags & BLOCK_NEEDS_FREE) {
        __atomic_add_fetch(&src->forwarding->flags, 2, __ATOMIC_RELAXED);
    }
    return src->forwarding;
}

static void byref_release(struct byref *b) {
    b = b->forwarding;
    if (!(b->flags & BLOCK_NEEDS_FREE)) return;
    int now = __atomic_sub_fetch(&b->flags, 2, __ATOMIC_ACQ_REL);
    if ((now & BLOCK_REFCOUNT_MASK) != 0) return;
    if (b->flags & BLOCK_HAS_COPY_DISPOSE) b->destroy(b);
    free(b);
}

static void d__Block_object_assign(void *dest, const void *object, int flags) {
    void **slot = dest;
    switch (flags & (BLOCK_FIELD_IS_OBJECT | BLOCK_FIELD_IS_BLOCK | BLOCK_FIELD_IS_BYREF |
                     BLOCK_FIELD_IS_WEAK | BLOCK_BYREF_CALLER)) {
    case BLOCK_FIELD_IS_OBJECT:
        *slot = dx_block_retain_object((void *)object);
        break;
    case BLOCK_FIELD_IS_BLOCK:
        *slot = dx_block_copy(object);
        break;
    case BLOCK_FIELD_IS_BYREF:
    case BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK:
        *slot = byref_copy((struct byref *)object);
        break;
    default: /* fields of a __block variable: the variable owns no reference */
        *slot = (void *)object;
        break;
    }
}
DX_FN(_Block_object_assign);

static void d__Block_object_dispose(const void *object, int flags) {
    switch (flags & (BLOCK_FIELD_IS_OBJECT | BLOCK_FIELD_IS_BLOCK | BLOCK_FIELD_IS_BYREF |
                     BLOCK_FIELD_IS_WEAK | BLOCK_BYREF_CALLER)) {
    case BLOCK_FIELD_IS_OBJECT:
        dx_block_release_object((void *)object);
        break;
    case BLOCK_FIELD_IS_BLOCK:
        dx_block_release(object);
        break;
    case BLOCK_FIELD_IS_BYREF:
    case BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK:
        byref_release((struct byref *)object);
        break;
    default:
        break;
    }
}
DX_FN(_Block_object_dispose);

static size_t d_Block_size(void *block) {
    struct dx_block *b = block;
    return ((struct descriptor *)b->descriptor)->size;
}
DX_FN(Block_size);

static const char *d__Block_signature(void *block) {
    struct dx_block *b = block;
    if (!(b->flags & BLOCK_HAS_SIGNATURE)) return NULL;
    void **d = b->descriptor;
    return (b->flags & BLOCK_HAS_COPY_DISPOSE) ? d[4] : d[2];
}
DX_FN(_Block_signature);
