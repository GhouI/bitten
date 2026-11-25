/* Existential type metadata (any P & Q, AnyObject, Any, any Error) and
 * existential metatypes (any P.Type), uniqued like the other structural
 * metadata. Their values have three representations, all fixed by the ABI:
 *
 *   opaque   {buffer[3], type, witness tables...}: the value lives in the
 *            3-word buffer if its type is inline, else in a heap box whose
 *            reference is in the buffer; extra inhabitants are those of the
 *            type word (a metatype: even values below 4 GiB)
 *   class    {object, witness tables...}: extra inhabitants of the object
 *            reference (the same encoding)
 *   error    any Error: one reference to an error box
 *
 * Metadata: kind, flags (32 bits), number of protocols (32 bits), the
 * superclass constraint if the flags say so, then the protocols (each a
 * pointer, low bit set for Objective-C protocols). */
#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>

#include "swift_internal.h"
#include "sw_utable.h"

enum {
    EX_NUM_WITNESS_TABLES_MASK = 0x00FFFFFF,
    EX_CLASS_CONSTRAINT_ANY = 0x80000000, /* clear: class-bound */
    EX_HAS_SUPERCLASS = 0x40000000,
    EX_SPECIAL_SHIFT = 24,
    EX_SPECIAL_MASK = 0x3F000000,
    EX_SPECIAL_ERROR = 1,
};

/* Extra inhabitants of a metatype or object reference stored at `at`:
 * inhabitant i is the value i << 1. */
static unsigned ref_xi_at(const sw_opaque *v, size_t at, unsigned n) {
    uintptr_t p = *(const uintptr_t *)((const char *)v + at);
    if (p >= (1ULL << 32) || (p & 1) || (p >> 1) >= n) return 0;
    return (unsigned)(p >> 1) + 1;
}
static void ref_xi_store_at(sw_opaque *v, size_t at, unsigned which) {
    *(uintptr_t *)((char *)v + at) = (uintptr_t)(which - 1) << 1;
}

/* ---- opaque existentials --------------------------------------------------------- */
typedef struct {
    sw_value_buffer buffer;
    const sw_metadata *type;
    const void *wt[];
} opaque_ex;

static size_t ex_size(const sw_metadata *m) { return sw_vwt_of(m)->size; }

static void opaque_destroy(sw_opaque *v, const sw_metadata *m) {
    opaque_ex *e = (opaque_ex *)v;
    const sw_vwt *w = sw_vwt_of(e->type);
    if (w->flags & SW_VW_IS_NON_INLINE)
        sw_release((sw_heap_object *)e->buffer.w[0]);
    else
        w->destroy((sw_opaque *)&e->buffer, e->type);
}
static sw_opaque *opaque_init_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    opaque_ex *dst = (opaque_ex *)d, *src = (opaque_ex *)s;
    memcpy(&dst->type, &src->type, ex_size(m) - sizeof(sw_value_buffer));
    sw_vwt_of(src->type)->initializeBufferWithCopyOfBuffer(&dst->buffer, &src->buffer, src->type);
    return d;
}
static sw_opaque *opaque_init_take(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    return memcpy(d, s, ex_size(m));
}
static sw_opaque *opaque_assign_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    if (d == s) return d;
    char tmp[ex_size(m)];
    opaque_init_copy((sw_opaque *)tmp, s, m);
    opaque_destroy(d, m);
    return memcpy(d, tmp, sizeof tmp);
}
static sw_opaque *opaque_assign_take(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    if (d == s) return d;
    opaque_destroy(d, m);
    return memcpy(d, s, ex_size(m));
}
static unsigned opaque_xi_get(const sw_opaque *v, unsigned n, const sw_metadata *m) {
    return ref_xi_at(v, offsetof(opaque_ex, type), n);
}
static void opaque_xi_store(sw_opaque *v, unsigned which, unsigned n, const sw_metadata *m) {
    ref_xi_store_at(v, offsetof(opaque_ex, type), which);
}
static unsigned opaque_get_tag(const sw_opaque *v, unsigned empty, const sw_metadata *m) {
    return sw_get_enum_tag_single_payload(v, empty, m, opaque_xi_get);
}
static void opaque_store_tag(sw_opaque *v, unsigned which, unsigned empty, const sw_metadata *m) {
    sw_store_enum_tag_single_payload(v, which, empty, m, opaque_xi_store);
}

/* ---- class-bound existentials ------------------------------------------------------ */
static void class_destroy(sw_opaque *v, const sw_metadata *m) { sw_unknown_release(*(void **)v); }
static sw_opaque *class_init_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    memcpy(d, s, ex_size(m));
    sw_unknown_retain(*(void **)d);
    return d;
}
static sw_opaque *class_init_take(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    return memcpy(d, s, ex_size(m));
}
static sw_opaque *class_assign_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    void *old = *(void **)d;
    class_init_copy(d, s, m);
    sw_unknown_release(old);
    return d;
}
static sw_opaque *class_assign_take(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    void *old = *(void **)d;
    memcpy(d, s, ex_size(m));
    sw_unknown_release(old);
    return d;
}
static sw_opaque *class_buffer_copy(sw_value_buffer *d, sw_value_buffer *s, const sw_metadata *m) {
    return sw_vw_initialize_buffer_with_copy(d, s, m);
}
static unsigned word0_xi_get(const sw_opaque *v, unsigned n, const sw_metadata *m) {
    return ref_xi_at(v, 0, n);
}
static void word0_xi_store(sw_opaque *v, unsigned which, unsigned n, const sw_metadata *m) {
    ref_xi_store_at(v, 0, which);
}
static unsigned word0_get_tag(const sw_opaque *v, unsigned empty, const sw_metadata *m) {
    return sw_get_enum_tag_single_payload(v, empty, m, word0_xi_get);
}
static void word0_store_tag(sw_opaque *v, unsigned which, unsigned empty, const sw_metadata *m) {
    sw_store_enum_tag_single_payload(v, which, empty, m, word0_xi_store);
}

/* ---- existential metatypes: {metatype, witness tables...}, POD ------------------------ */
static void pod_destroy(sw_opaque *v, const sw_metadata *m) {}
static sw_opaque *pod_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    return memcpy(d, s, ex_size(m));
}

/* Witness tables per representation and number of witness tables. Sizes
 * above the inline buffer need the generic buffer copy (boxing). */
enum { REP_OPAQUE, REP_CLASS, REP_METATYPE, NREPS, MAX_CACHED_WT = 32 };
static const sw_vwt *vwt_cache[NREPS][MAX_CACHED_WT];

static const sw_vwt *existential_vwt(int rep, unsigned nwt) {
    if (nwt < MAX_CACHED_WT && vwt_cache[rep][nwt]) return vwt_cache[rep][nwt];
    sw_vwt *w = calloc(1, sizeof *w);
    size_t words = (rep == REP_OPAQUE ? 4 : 1) + nwt;
    w->size = w->stride = words * sizeof(void *);
    w->extraInhabitantCount = SW_VW_MAX_NUM_EXTRA_INHABITANTS;
    w->flags = 7 | (w->size > sizeof(sw_value_buffer) ? SW_VW_IS_NON_INLINE : 0);
    w->initializeBufferWithCopyOfBuffer = sw_vw_initialize_buffer_with_copy;
    switch (rep) {
    case REP_OPAQUE:
        w->flags |= SW_VW_IS_NON_POD;
        *w = (sw_vwt){sw_vw_initialize_buffer_with_copy, opaque_destroy, opaque_init_copy,
                      opaque_assign_copy, opaque_init_take, opaque_assign_take, opaque_get_tag,
                      opaque_store_tag, w->size, w->stride, w->flags, w->extraInhabitantCount};
        break;
    case REP_CLASS:
        w->flags |= SW_VW_IS_NON_POD;
        *w = (sw_vwt){class_buffer_copy, class_destroy, class_init_copy, class_assign_copy,
                      class_init_take, class_assign_take, word0_get_tag, word0_store_tag,
                      w->size, w->stride, w->flags, w->extraInhabitantCount};
        break;
    default:
        *w = (sw_vwt){sw_vw_initialize_buffer_with_copy, pod_destroy, pod_copy, pod_copy, pod_copy,
                      pod_copy, word0_get_tag, word0_store_tag, w->size, w->stride, w->flags,
                      w->extraInhabitantCount};
        break;
    }
    if (nwt < MAX_CACHED_WT) vwt_cache[rep][nwt] = w;
    return w;
}

/* ---- Any and AnyObject: static, the compiler refers to them by symbol --------------- */
static sw_opaque *any_buffer_copy(sw_value_buffer *d, sw_value_buffer *s, const sw_metadata *m);
const sw_vwt sw_vwt_any = {any_buffer_copy, opaque_destroy, opaque_init_copy, opaque_assign_copy,
                           opaque_init_take, opaque_assign_take, opaque_get_tag, opaque_store_tag,
                           32, 32, 7 | SW_VW_IS_NON_POD | SW_VW_IS_NON_INLINE,
                           SW_VW_MAX_NUM_EXTRA_INHABITANTS};
static sw_opaque *any_buffer_copy(sw_value_buffer *d, sw_value_buffer *s, const sw_metadata *m) {
    return sw_vw_initialize_buffer_with_copy(d, s, m);
}
const sw_vwt sw_vwt_any_object = {class_buffer_copy, class_destroy, class_init_copy,
                                  class_assign_copy, class_init_take, class_assign_take,
                                  word0_get_tag, word0_store_tag, 8, 8, 7 | SW_VW_IS_NON_POD,
                                  SW_VW_MAX_NUM_EXTRA_INHABITANTS};

struct full_existential {
    const sw_vwt *vwt;
    uintptr_t kind;
    uint32_t flags, num_protocols;
    const void *rest[]; /* superclass, protocols */
};
static const struct full_existential md_any = {&sw_vwt_any, SW_KIND_EXISTENTIAL,
                                               EX_CLASS_CONSTRAINT_ANY, 0};
static const struct full_existential md_any_object = {&sw_vwt_any_object, SW_KIND_EXISTENTIAL, 0, 0};
DX_EXPORT("_$sypWV", &sw_vwt_any);
DX_EXPORT("_$sypN", &md_any);
DX_EXPORT("_$syXlWV", &sw_vwt_any_object);
DX_EXPORT("_$syXlN", &md_any_object);

static struct utable existentials, ex_metatypes;

/* ProtocolClassConstraint: 0 class, 1 any. */
static const sw_metadata *get_existential(unsigned class_constraint, const sw_metadata *superclass,
                                          size_t n, const uintptr_t *protocols) {
    if (!superclass && !n)
        return (const sw_metadata *)(class_constraint ? &md_any.kind : &md_any_object.kind);
    uintptr_t key[n + 2];
    key[0] = class_constraint;
    key[1] = (uintptr_t)superclass;
    memcpy(key + 2, protocols, n * sizeof *protocols);
    size_t h = words_hash(key, n + 2);
    sw_md_lock();
    const sw_metadata *m = ufind(&existentials, key, n + 2, h);
    if (!m) {
        int class_bound = !class_constraint || superclass;
        unsigned nwt = 0, special = 0;
        for (size_t i = 0; i < n; i++) {
            if (protocols[i] & 1) { /* Objective-C protocol: class-bound, no witness table */
                class_bound = 1;
                continue;
            }
            nwt++;
            uint32_t kf = ((const sw_protocol_descriptor *)protocols[i])->flags >> 16;
            if (!(kf & 1)) class_bound = 1;
            if (n == 1) special = (kf >> 2) & 0x3F;
        }
        if (class_bound || superclass) special = 0;
        struct full_existential *f = calloc(1, sizeof *f + (n + 1) * sizeof(void *));
        f->kind = SW_KIND_EXISTENTIAL;
        f->flags = nwt | (class_bound ? 0 : EX_CLASS_CONSTRAINT_ANY) |
                   (superclass ? EX_HAS_SUPERCLASS : 0) | special << EX_SPECIAL_SHIFT;
        f->num_protocols = (uint32_t)n;
        const void **p = f->rest;
        if (superclass) *p++ = superclass;
        memcpy(p, protocols, n * sizeof *protocols);
        if (special == EX_SPECIAL_ERROR)
            f->vwt = &sw_vwt_unknown_object; /* one reference to the error box */
        else
            f->vwt = existential_vwt(class_bound ? REP_CLASS : REP_OPAQUE, nwt);
        m = (const sw_metadata *)&f->kind;
        uinsert(&existentials, key, n + 2, h, m);
    }
    sw_md_unlock();
    return m;
}

/* const ExistentialTypeMetadata *swift_getExistentialTypeMetadata(
 *     ProtocolClassConstraint classConstraint, const Metadata *superclassConstraint,
 *     size_t numProtocols, const ProtocolDescriptorRef *protocols)
 * The compiler passes the protocols in a canonical order. */
static const sw_metadata *d_swift_getExistentialTypeMetadata(unsigned class_constraint,
                                                             const sw_metadata *superclass,
                                                             size_t n, const uintptr_t *protocols) {
    return get_existential(class_constraint & 1, superclass, n, protocols);
}
DX_FN(swift_getExistentialTypeMetadata);

/* ExistentialMetatypeMetadata: kind, instance type, flags of the innermost
 * existential. */
typedef struct {
    const sw_vwt *vwt;
    uintptr_t kind;
    const sw_metadata *instance;
    uint32_t flags;
} full_ex_metatype;

static uint32_t existential_flags(const sw_metadata *m) {
    if (sw_kind(m) == SW_KIND_EXISTENTIAL) return ((const struct full_existential *)((const char *)m - sizeof(void *)))->flags;
    if (sw_kind(m) == SW_KIND_EXISTENTIAL_METATYPE)
        return ((const full_ex_metatype *)((const char *)m - sizeof(void *)))->flags;
    return 0;
}

/* const ExistentialMetatypeMetadata *swift_getExistentialMetatypeMetadata(const Metadata *instance) */
static const sw_metadata *d_swift_getExistentialMetatypeMetadata(const sw_metadata *instance) {
    uintptr_t key = (uintptr_t)instance;
    size_t h = words_hash(&key, 1);
    sw_md_lock();
    const sw_metadata *m = ufind(&ex_metatypes, &key, 1, h);
    if (!m) {
        full_ex_metatype *f = calloc(1, sizeof *f);
        f->kind = SW_KIND_EXISTENTIAL_METATYPE;
        f->instance = instance;
        f->flags = existential_flags(instance);
        f->vwt = existential_vwt(REP_METATYPE, f->flags & EX_NUM_WITNESS_TABLES_MASK);
        m = (const sw_metadata *)&f->kind;
        uinsert(&ex_metatypes, &key, 1, h, m);
    }
    sw_md_unlock();
    return m;
}
DX_FN(swift_getExistentialMetatypeMetadata);
