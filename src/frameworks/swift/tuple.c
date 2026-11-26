/* Structural type metadata the runtime creates on demand: tuples and
 * metatypes. Each is uniqued (same arguments, same pointer) in a hash
 * table under the metadata lock, and never freed. */
#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>

#include "swift_internal.h"
#include "sw_utable.h"

/* ---- tuples -------------------------------------------------------------------------- */

struct full_tuple {
    const void *layout_string;
    const sw_vwt *vwt;
    sw_tuple_metadata md;
};

static const sw_tuple_metadata *as_tuple(const sw_metadata *m) { return (const sw_tuple_metadata *)m; }

#define FOR_ELEMENTS(m, e)                                                                \
    for (const sw_tuple_element *e = as_tuple(m)->elements,                               \
                                *e##_end = e + as_tuple(m)->num_elements;                 \
         e < e##_end; e++)

static int is_pod(const sw_metadata *m) { return !(sw_vwt_of(m)->flags & SW_VW_IS_NON_POD); }
static int is_bt(const sw_metadata *m) {
    return !(sw_vwt_of(m)->flags & SW_VW_IS_NON_BITWISE_TAKABLE);
}

static void tuple_destroy(sw_opaque *v, const sw_metadata *m) {
    if (is_pod(m)) return;
    FOR_ELEMENTS(m, e) sw_vwt_of(e->type)->destroy((sw_opaque *)((char *)v + e->offset), e->type);
}

#define TUPLE_COPY(name, witness, pod_ok)                                               \
    static sw_opaque *tuple_##name(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {  \
        if (pod_ok(m)) return memcpy(d, s, sw_vwt_of(m)->size);                         \
        FOR_ELEMENTS(m, e)                                                              \
            sw_vwt_of(e->type)->witness((sw_opaque *)((char *)d + e->offset),           \
                                        (sw_opaque *)((char *)s + e->offset), e->type); \
        return d;                                                                       \
    }
TUPLE_COPY(init_copy, initializeWithCopy, is_pod)
TUPLE_COPY(assign_copy, assignWithCopy, is_pod)
TUPLE_COPY(init_take, initializeWithTake, is_bt)
TUPLE_COPY(assign_take, assignWithTake, is_pod)

/* A tuple's extra inhabitants are those of its element with the most (the
 * first such element), as for structs. */
static const sw_metadata *xi_element(const sw_metadata *m, size_t *offset) {
    const sw_metadata *best = NULL;
    unsigned most = 0;
    FOR_ELEMENTS(m, e) {
        unsigned n = sw_vwt_of(e->type)->extraInhabitantCount;
        if (n > most) {
            most = n;
            best = e->type;
            *offset = e->offset;
        }
    }
    return best;
}
static unsigned tuple_xi_get(const sw_opaque *v, unsigned n, const sw_metadata *m) {
    size_t at = 0;
    const sw_metadata *el = xi_element(m, &at);
    return sw_vwt_of(el)->getEnumTagSinglePayload((const sw_opaque *)((const char *)v + at), n, el);
}
static void tuple_xi_store(sw_opaque *v, unsigned which, unsigned n, const sw_metadata *m) {
    size_t at = 0;
    const sw_metadata *el = xi_element(m, &at);
    sw_vwt_of(el)->storeEnumTagSinglePayload((sw_opaque *)((char *)v + at), which, n, el);
}
static unsigned tuple_get_tag(const sw_opaque *v, unsigned empty, const sw_metadata *m) {
    return sw_get_enum_tag_single_payload(v, empty, m, tuple_xi_get);
}
static void tuple_store_tag(sw_opaque *v, unsigned which, unsigned empty, const sw_metadata *m) {
    sw_store_enum_tag_single_payload(v, which, empty, m, tuple_xi_store);
}

static struct utable tuples;

/* Key: n, element metadata..., then the label string's bytes (if any). */
static const sw_metadata *get_tuple(size_t n, const sw_metadata *const *elements,
                                    const char *labels, int copy_labels) {
    if (n == 0) return sw_empty_tuple_metadata;
    /* The layout is read from the elements' value witnesses once and kept:
     * an element still being initialized (a struct with resilient fields
     * whose layout is computed at run time) must be finished first. */
    static sw_response (*check)(sw_request, const sw_metadata *);
    if (!check) check = dx_registry_lookup("_swift_checkMetadataState");
    if (check)
        for (size_t i = 0; i < n; i++) check(0, elements[i]);
    size_t llen = labels ? strlen(labels) + 1 : 0;
    size_t nkey = 1 + n + (llen + 7) / 8;
    uintptr_t key[nkey];
    memset(key, 0, sizeof key);
    key[0] = n;
    for (size_t i = 0; i < n; i++) key[1 + i] = (uintptr_t)elements[i];
    if (llen) memcpy(key + 1 + n, labels, llen);
    size_t h = words_hash(key, nkey);

    sw_md_lock();
    const sw_metadata *found = ufind(&tuples, key, nkey, h);
    if (found) {
        sw_md_unlock();
        return found;
    }
    struct full_tuple *t = calloc(1, sizeof *t + n * sizeof(sw_tuple_element));
    sw_vwt *w = calloc(1, sizeof *w);
    const sw_type_layout *layouts[n];
    uint32_t offsets[n];
    for (size_t i = 0; i < n; i++) layouts[i] = (const sw_type_layout *)&sw_vwt_of(elements[i])->size;
    sw_type_layout l;
    sw_basic_layout(&l, n, layouts, offsets);
    *w = (sw_vwt){sw_vw_initialize_buffer_with_copy, tuple_destroy, tuple_init_copy,
                  tuple_assign_copy, tuple_init_take, tuple_assign_take, tuple_get_tag,
                  tuple_store_tag, l.size, l.stride, l.flags, l.extraInhabitantCount};
    t->vwt = w;
    t->md.kind = SW_KIND_TUPLE;
    t->md.num_elements = n;
    t->md.labels = labels && copy_labels ? strdup(labels) : labels;
    for (size_t i = 0; i < n; i++) {
        t->md.elements[i].type = elements[i];
        t->md.elements[i].offset = offsets[i];
    }
    uinsert(&tuples, key, nkey, h, &t->md);
    sw_md_unlock();
    return (const sw_metadata *)&t->md;
}

const sw_metadata *sw_get_tuple_metadata(size_t n, const sw_metadata *const *elements,
                                         const char *labels) {
    return get_tuple(n, elements, labels, 1);
}

enum { TUPLE_NUM_ELEMENTS_MASK = 0xFFFF, TUPLE_NON_CONSTANT_LABELS = 0x10000 };

/* MetadataResponse swift_getTupleTypeMetadata(MetadataRequest, TupleTypeFlags,
 *     const Metadata *const *elements, const char *labels, const ValueWitnessTable *proposed)
 * The proposed witnesses are only a hint; the tuple gets its own table. */
static sw_response d_swift_getTupleTypeMetadata(sw_request req, uintptr_t flags,
                                                const sw_metadata *const *elements,
                                                const char *labels, const sw_vwt *proposed) {
    const sw_metadata *m = get_tuple(flags & TUPLE_NUM_ELEMENTS_MASK, elements, labels,
                                     (flags & TUPLE_NON_CONSTANT_LABELS) != 0);
    return (sw_response){m, SW_STATE_COMPLETE};
}
DX_FN(swift_getTupleTypeMetadata);

static sw_response d_swift_getTupleTypeMetadata2(sw_request req, const sw_metadata *e0,
                                                 const sw_metadata *e1, const char *labels,
                                                 const sw_vwt *proposed) {
    const sw_metadata *el[2] = {e0, e1};
    return (sw_response){get_tuple(2, el, labels, 0), SW_STATE_COMPLETE};
}
DX_FN(swift_getTupleTypeMetadata2);

static sw_response d_swift_getTupleTypeMetadata3(sw_request req, const sw_metadata *e0,
                                                 const sw_metadata *e1, const sw_metadata *e2,
                                                 const char *labels, const sw_vwt *proposed) {
    const sw_metadata *el[3] = {e0, e1, e2};
    return (sw_response){get_tuple(3, el, labels, 0), SW_STATE_COMPLETE};
}
DX_FN(swift_getTupleTypeMetadata3);

/* The layout of a tuple without its metadata, for compiled code that lays
 * out a generic tuple itself (closure contexts, async frames).
 * void swift_getTupleTypeLayout(TypeLayout *result, uint32_t *elementOffsets,
 *     TupleTypeFlags flags, const TypeLayout *const *elements) */
static void d_swift_getTupleTypeLayout(sw_type_layout *out, uint32_t *offsets, uintptr_t flags,
                                       const sw_type_layout *const *elements) {
    sw_basic_layout(out, flags & TUPLE_NUM_ELEMENTS_MASK, elements, offsets);
}
DX_FN(swift_getTupleTypeLayout);

/* size_t swift_getTupleTypeLayout2(TypeLayout *, const TypeLayout *, const TypeLayout *):
 * returns the second element's offset. */
static size_t d_swift_getTupleTypeLayout2(sw_type_layout *out, const sw_type_layout *e0,
                                          const sw_type_layout *e1) {
    const sw_type_layout *el[2] = {e0, e1};
    uint32_t off[2];
    sw_basic_layout(out, 2, el, off);
    return off[1];
}
DX_FN(swift_getTupleTypeLayout2);

/* OffsetPair swift_getTupleTypeLayout3(TypeLayout *, elt0, elt1, elt2): the
 * offsets of the second and third elements, returned in rax:rdx. */
typedef struct {
    size_t first, second;
} offset_pair;
static offset_pair d_swift_getTupleTypeLayout3(sw_type_layout *out, const sw_type_layout *e0,
                                               const sw_type_layout *e1, const sw_type_layout *e2) {
    const sw_type_layout *el[3] = {e0, e1, e2};
    uint32_t off[3];
    sw_basic_layout(out, 3, el, off);
    return (offset_pair){off[1], off[2]};
}
DX_FN(swift_getTupleTypeLayout3);

/* ---- metatypes ------------------------------------------------------------------------
 * A thick metatype value is a metadata pointer. Its extra inhabitants are
 * the values below 4 GiB (the zero page on Darwin x86-64) with the low bit
 * clear (Objective-C reserves it): inhabitant i is the value i << 1. */
static unsigned metatype_xi_get(const sw_opaque *v, unsigned n, const sw_metadata *m) {
    uintptr_t p = *(const uintptr_t *)v;
    if (p >= (1ULL << 32) || (p & 1) || (p >> 1) >= n) return 0;
    return (unsigned)(p >> 1) + 1;
}
static void metatype_xi_store(sw_opaque *v, unsigned which, unsigned n, const sw_metadata *m) {
    *(uintptr_t *)v = (uintptr_t)(which - 1) << 1;
}
static unsigned metatype_get_tag(const sw_opaque *v, unsigned empty, const sw_metadata *m) {
    return sw_get_enum_tag_single_payload(v, empty, m, metatype_xi_get);
}
static void metatype_store_tag(sw_opaque *v, unsigned which, unsigned empty, const sw_metadata *m) {
    sw_store_enum_tag_single_payload(v, which, empty, m, metatype_xi_store);
}
static sw_opaque *word_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    *(uintptr_t *)d = *(uintptr_t *)s;
    return d;
}
static void word_destroy(sw_opaque *v, const sw_metadata *m) {}
static sw_opaque *word_buffer_copy(sw_value_buffer *d, sw_value_buffer *s, const sw_metadata *m) {
    d->w[0] = s->w[0];
    return (sw_opaque *)d;
}
const sw_vwt sw_vwt_metatype = {word_buffer_copy, word_destroy, word_copy, word_copy, word_copy,
                                word_copy, metatype_get_tag, metatype_store_tag, 8, 8, 7,
                                SW_VW_MAX_NUM_EXTRA_INHABITANTS};

struct full_metatype {
    const sw_vwt *vwt;
    sw_metatype_metadata md;
};
static struct utable metatypes;

const sw_metadata *sw_get_metatype_metadata(const sw_metadata *instance) {
    uintptr_t key = (uintptr_t)instance;
    size_t h = words_hash(&key, 1);
    sw_md_lock();
    const sw_metadata *m = ufind(&metatypes, &key, 1, h);
    if (!m) {
        struct full_metatype *f = calloc(1, sizeof *f);
        f->vwt = &sw_vwt_metatype;
        f->md.kind = SW_KIND_METATYPE;
        f->md.instance_type = instance;
        m = (const sw_metadata *)&f->md;
        uinsert(&metatypes, &key, 1, h, m);
    }
    sw_md_unlock();
    return m;
}

/* const MetatypeMetadata *swift_getMetatypeMetadata(const Metadata *instanceType) */
static const sw_metadata *d_swift_getMetatypeMetadata(const sw_metadata *instance) {
    return sw_get_metatype_metadata(instance);
}
DX_FN(swift_getMetatypeMetadata);

/* ---- function types --------------------------------------------------------------------
 * FunctionTypeMetadata: kind, flags (one word), result, parameters, then as
 * the flags say: 32-bit parameter flags (padded to a word), the
 * differentiability kind, the global actor, 32-bit extended flags (padded)
 * and the thrown error type. */

/* Thin and C function pointers: one word, extra inhabitants are the values
 * below 4 GiB (no reserved bits). */
static unsigned fnptr_xi_get(const sw_opaque *v, unsigned n, const sw_metadata *m) {
    uintptr_t p = *(const uintptr_t *)v;
    return p < n ? (unsigned)p + 1 : 0;
}
static void fnptr_xi_store(sw_opaque *v, unsigned which, unsigned n, const sw_metadata *m) {
    *(uintptr_t *)v = which - 1;
}
static unsigned fnptr_get_tag(const sw_opaque *v, unsigned empty, const sw_metadata *m) {
    return sw_get_enum_tag_single_payload(v, empty, m, fnptr_xi_get);
}
static void fnptr_store_tag(sw_opaque *v, unsigned which, unsigned empty, const sw_metadata *m) {
    sw_store_enum_tag_single_payload(v, which, empty, m, fnptr_xi_store);
}
const sw_vwt sw_vwt_thin_function = {word_buffer_copy, word_destroy, word_copy, word_copy,
                                     word_copy, word_copy, fnptr_get_tag, fnptr_store_tag,
                                     8, 8, 7, SW_VW_MAX_NUM_EXTRA_INHABITANTS};

/* Non-escaping closures: function and context, neither owned. */
static sw_opaque *pair_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    memcpy(d, s, 16);
    return d;
}
static sw_opaque *pair_buffer_copy(sw_value_buffer *d, sw_value_buffer *s, const sw_metadata *m) {
    return pair_copy((sw_opaque *)d, (sw_opaque *)s, m);
}
const sw_vwt sw_vwt_noescape_function = {pair_buffer_copy, word_destroy, pair_copy, pair_copy,
                                         pair_copy, pair_copy, fnptr_get_tag, fnptr_store_tag,
                                         16, 16, 7, SW_VW_MAX_NUM_EXTRA_INHABITANTS};

static const sw_vwt *function_vwt(uintptr_t flags) {
    switch ((flags & SW_FN_CONVENTION_MASK) >> SW_FN_CONVENTION_SHIFT) {
    case 0: return (flags & SW_FN_ESCAPING) ? &sw_vwt_thick_closure : &sw_vwt_noescape_function;
    case 1: return &sw_vwt_unknown_object; /* blocks are Objective-C objects */
    default: return &sw_vwt_thin_function;  /* thin, C */
    }
}

struct full_function {
    const sw_vwt *vwt;
    sw_function_metadata md;
};
static struct utable functions;

static const sw_metadata *get_function(uintptr_t flags, uintptr_t diff_kind,
                                       const sw_metadata *const *params, const uint32_t *pflags,
                                       const sw_metadata *result, const sw_metadata *actor,
                                       uint32_t ext_flags, const sw_metadata *thrown) {
    size_t n = flags & SW_FN_NUM_PARAMS_MASK;
    int has_pflags = (flags & SW_FN_PARAM_FLAGS) && pflags;
    int typed_throws = (flags & SW_FN_EXTENDED_FLAGS) && (ext_flags & 1);
    /* Key: flags, result, params, param flags, the optional parts. */
    size_t nkey = 0;
    uintptr_t key[2 * n + 8];
    key[nkey++] = flags;
    key[nkey++] = (uintptr_t)result;
    for (size_t i = 0; i < n; i++) key[nkey++] = (uintptr_t)params[i];
    if (has_pflags)
        for (size_t i = 0; i < n; i++) key[nkey++] = pflags[i];
    if (flags & SW_FN_DIFFERENTIABLE) key[nkey++] = diff_kind;
    if (flags & SW_FN_GLOBAL_ACTOR) key[nkey++] = (uintptr_t)actor;
    if (flags & SW_FN_EXTENDED_FLAGS) key[nkey++] = ext_flags;
    if (typed_throws) key[nkey++] = (uintptr_t)thrown;
    size_t h = words_hash(key, nkey);

    sw_md_lock();
    const sw_metadata *m = ufind(&functions, key, nkey, h);
    if (!m) {
        size_t words = n + (has_pflags ? (n + 1) / 2 : 0) + 6;
        struct full_function *f = calloc(1, sizeof *f + words * sizeof(void *));
        f->vwt = function_vwt(flags);
        f->md.kind = SW_KIND_FUNCTION;
        f->md.flags = flags;
        f->md.result = result;
        uintptr_t *w = (uintptr_t *)f->md.params;
        for (size_t i = 0; i < n; i++) *w++ = (uintptr_t)params[i];
        if (flags & SW_FN_PARAM_FLAGS) {
            if (has_pflags) memcpy(w, pflags, n * sizeof *pflags);
            w += (n + 1) / 2;
        }
        if (flags & SW_FN_DIFFERENTIABLE) *w++ = diff_kind;
        if (flags & SW_FN_GLOBAL_ACTOR) *w++ = (uintptr_t)actor;
        if (flags & SW_FN_EXTENDED_FLAGS) *w++ = ext_flags;
        if (typed_throws) *w++ = (uintptr_t)thrown;
        m = (const sw_metadata *)&f->md;
        uinsert(&functions, key, nkey, h, m);
    }
    sw_md_unlock();
    return m;
}

/* const FunctionTypeMetadata *swift_getFunctionTypeMetadata(FunctionTypeFlags,
 *     const Metadata *const *parameters, const uint32_t *parameterFlags, const Metadata *result) */
static const sw_metadata *d_swift_getFunctionTypeMetadata(uintptr_t flags,
                                                          const sw_metadata *const *params,
                                                          const uint32_t *pflags,
                                                          const sw_metadata *result) {
    return get_function(flags, 0, params, pflags, result, NULL, 0, NULL);
}
DX_FN(swift_getFunctionTypeMetadata);

static const sw_metadata *d_swift_getFunctionTypeMetadata0(uintptr_t flags, const sw_metadata *result) {
    return get_function(flags, 0, NULL, NULL, result, NULL, 0, NULL);
}
DX_FN(swift_getFunctionTypeMetadata0);

static const sw_metadata *d_swift_getFunctionTypeMetadata1(uintptr_t flags, const sw_metadata *a0,
                                                           const sw_metadata *result) {
    const sw_metadata *p[1] = {a0};
    return get_function(flags, 0, p, NULL, result, NULL, 0, NULL);
}
DX_FN(swift_getFunctionTypeMetadata1);

static const sw_metadata *d_swift_getFunctionTypeMetadata2(uintptr_t flags, const sw_metadata *a0,
                                                           const sw_metadata *a1,
                                                           const sw_metadata *result) {
    const sw_metadata *p[2] = {a0, a1};
    return get_function(flags, 0, p, NULL, result, NULL, 0, NULL);
}
DX_FN(swift_getFunctionTypeMetadata2);

static const sw_metadata *d_swift_getFunctionTypeMetadata3(uintptr_t flags, const sw_metadata *a0,
                                                           const sw_metadata *a1,
                                                           const sw_metadata *a2,
                                                           const sw_metadata *result) {
    const sw_metadata *p[3] = {a0, a1, a2};
    return get_function(flags, 0, p, NULL, result, NULL, 0, NULL);
}
DX_FN(swift_getFunctionTypeMetadata3);

/* (flags, differentiabilityKind, params, paramFlags, result) */
static const sw_metadata *d_swift_getFunctionTypeMetadataDifferentiable(
    uintptr_t flags, uintptr_t diff, const sw_metadata *const *params, const uint32_t *pflags,
    const sw_metadata *result) {
    return get_function(flags, diff, params, pflags, result, NULL, 0, NULL);
}
DX_FN(swift_getFunctionTypeMetadataDifferentiable);

/* (flags, differentiabilityKind, params, paramFlags, result, globalActor) */
static const sw_metadata *d_swift_getFunctionTypeMetadataGlobalActor(
    uintptr_t flags, uintptr_t diff, const sw_metadata *const *params, const uint32_t *pflags,
    const sw_metadata *result, const sw_metadata *actor) {
    return get_function(flags, diff, params, pflags, result, actor, 0, NULL);
}
DX_FN(swift_getFunctionTypeMetadataGlobalActor);

/* (flags, differentiabilityKind, params, paramFlags, result, globalActor,
 *  extendedFlags, thrownError) */
static const sw_metadata *d_swift_getExtendedFunctionTypeMetadata(
    uintptr_t flags, uintptr_t diff, const sw_metadata *const *params, const uint32_t *pflags,
    const sw_metadata *result, const sw_metadata *actor, uint32_t ext, const sw_metadata *thrown) {
    return get_function(flags, diff, params, pflags, result, actor, ext, thrown);
}
DX_FN(swift_getExtendedFunctionTypeMetadata);
