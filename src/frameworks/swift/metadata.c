/* Swift type metadata: the builtin types' value witnesses and metadata,
 * metadata states and completion, singleton initialisation and struct
 * layout. Generic instantiation is in generic.c, enum layout and tags in
 * enum.c, tuples and metatypes in tuple.c.
 *
 * Metadata the runtime builds (singleton and generic instantiations) goes
 * through states: allocated ("abstract"), then complete once the type's
 * completion function has run without reporting a dependency. Compiled code
 * asks for a state with every request and only ever needs "layout complete"
 * while it is itself completing a type, so the state machine here is kept to
 * those two states plus the bookkeeping that lets a completion function be
 * retried after a dependency was satisfied. */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "swift_internal.h"


/* ---- value witnesses of plain-old-data types ------------------------------ */

static size_t vw_size(const sw_metadata *m) { return sw_vwt_of(m)->size; }

/* A non-inline value lives in a heap box: the buffer holds the box, the
 * value follows the 16-byte object header at the value's alignment. */
static sw_opaque *box_project(void *box, size_t align_mask) {
    return (sw_opaque *)((char *)box + ((sizeof(sw_heap_object) + align_mask) & ~align_mask));
}

sw_opaque *sw_vw_initialize_buffer_with_copy(sw_value_buffer *dst, sw_value_buffer *src,
                                             const sw_metadata *m) {
    const sw_vwt *w = sw_vwt_of(m);
    if (w->flags & SW_VW_IS_NON_INLINE) {
        sw_heap_object *box = (sw_heap_object *)src->w[0];
        sw_retain(box);
        dst->w[0] = box;
        return box_project(box, w->flags & SW_VW_ALIGNMENT_MASK);
    }
    return w->initializeWithCopy((sw_opaque *)dst, (sw_opaque *)src, m);
}

static void pod_destroy(sw_opaque *v, const sw_metadata *m) {}
static sw_opaque *pod_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    memcpy(d, s, vw_size(m));
    return d;
}

/* Extra inhabitants of the builtin types, as the compiler defines them:
 * Builtin.Int1 uses the byte values 2...255 (254 of them, in order),
 * Builtin.RawPointer only the null pointer. Integers and floats have none. */
static unsigned int1_xi_get(const sw_opaque *v, unsigned n, const sw_metadata *m) {
    unsigned b = *(const uint8_t *)v;
    return b >= 2 && b - 2 < n ? b - 1 : 0;
}
static void int1_xi_store(sw_opaque *v, unsigned which, unsigned n, const sw_metadata *m) {
    *(uint8_t *)v = (uint8_t)(which + 1);
}
static unsigned null_xi_get(const sw_opaque *v, unsigned n, const sw_metadata *m) {
    return *(const uintptr_t *)v == 0;
}
static void null_xi_store(sw_opaque *v, unsigned which, unsigned n, const sw_metadata *m) {
    *(uintptr_t *)v = 0;
}

#define TAG_WITNESSES(name, get, store)                                                    \
    static unsigned name##_get_tag(const sw_opaque *v, unsigned empty, const sw_metadata *m) { \
        return sw_get_enum_tag_single_payload(v, empty, m, get);                           \
    }                                                                                      \
    static void name##_store_tag(sw_opaque *v, unsigned which, unsigned empty,             \
                                 const sw_metadata *m) {                                   \
        sw_store_enum_tag_single_payload(v, which, empty, m, store);                      \
    }
TAG_WITNESSES(noxi, NULL, NULL)
TAG_WITNESSES(int1, int1_xi_get, int1_xi_store)
TAG_WITNESSES(null, null_xi_get, null_xi_store)

/* (sw_is_inline, as a constant expression) */
#define POD_FLAGS(size, align) \
    (((align) - 1) | ((size) <= 24 && (align) <= 8 ? 0 : SW_VW_IS_NON_INLINE))
#define POD_VWT(size, align, xi, tags)                                                     \
    {sw_vw_initialize_buffer_with_copy, pod_destroy, pod_copy, pod_copy, pod_copy, pod_copy, \
     tags##_get_tag, tags##_store_tag, size, (size) ? (size) : 1, POD_FLAGS(size, align), xi}

/* Builtin type metadata as the compiler refers to it: the symbol is the
 * value witness table word, the metadata (address point) follows it. */
struct sw_full_opaque {
    const sw_vwt *vwt;
    uintptr_t kind;
};
struct sw_full_tuple0 {
    const sw_vwt *vwt;
    uintptr_t kind;
    size_t num_elements;
    const char *labels;
};

#define BUILTIN(mangled, cname, size, align, xi, tags)                                    \
    static const sw_vwt vwt_##cname = POD_VWT(size, align, xi, tags);                      \
    static const struct sw_full_opaque md_##cname = {&vwt_##cname, SW_KIND_OPAQUE};        \
    DX_EXPORT("_$s" mangled "WV", &vwt_##cname);                                           \
    DX_EXPORT("_$s" mangled "N", &md_##cname)

BUILTIN("Bi1_", i1, 1, 1, 254, int1);
BUILTIN("Bi7_", i7, 1, 1, 0, noxi);
BUILTIN("Bi8_", i8, 1, 1, 0, noxi);
BUILTIN("Bi16_", i16, 2, 2, 0, noxi);
BUILTIN("Bi32_", i32, 4, 4, 0, noxi);
BUILTIN("Bi63_", i63, 8, 8, 0, noxi);
BUILTIN("Bi64_", i64, 8, 8, 0, noxi);
BUILTIN("Bi128_", i128, 16, 16, 0, noxi);
BUILTIN("Bi256_", i256, 32, 32, 0, noxi);
BUILTIN("Bi512_", i512, 64, 64, 0, noxi);
BUILTIN("Bw", word, 8, 8, 0, noxi);
BUILTIN("Bp", rawptr, 8, 8, 1, null);
BUILTIN("Bf16_", f16, 2, 2, 0, noxi);
BUILTIN("Bf32_", f32, 4, 4, 0, noxi);
BUILTIN("Bf64_", f64, 8, 8, 0, noxi);
BUILTIN("Bf80_", f80, 16, 16, 0, noxi);
BUILTIN("Bf128_", f128, 16, 16, 0, noxi);

const sw_vwt sw_vwt_pod8 = POD_VWT(8, 8, 0, noxi);

/* The empty tuple: size 0, stride 1. */
const sw_vwt sw_vwt_empty = POD_VWT(0, 1, 0, noxi);
static const struct sw_full_tuple0 md_empty_tuple = {&sw_vwt_empty, SW_KIND_TUPLE, 0, NULL};
const sw_metadata *const sw_empty_tuple_metadata = (const sw_metadata *)&md_empty_tuple.kind;
DX_EXPORT("_$sytWV", &sw_vwt_empty);
DX_EXPORT("_$sytN", &md_empty_tuple);

/* ---- metadata states ---------------------------------------------------------
 * One recursive lock serialises all completion work. Completion functions
 * call back into the runtime (field metadata accessors, checkMetadataState)
 * on the same thread, which the recursive lock allows; another thread asking
 * for metadata that is being completed simply waits for the lock. */
static pthread_mutex_t md_lock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;

void sw_md_lock(void) { pthread_mutex_lock(&md_lock); }
void sw_md_unlock(void) { pthread_mutex_unlock(&md_lock); }

/* Entries by metadata address, for swift_checkMetadataState. */
static struct sw_md_entry **by_md;
static size_t by_md_cap, by_md_count;

static size_t ptr_hash(const void *p) {
    uintptr_t x = (uintptr_t)p;
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    return (size_t)x;
}

static void by_md_insert(struct sw_md_entry *e) {
    if ((by_md_count + 1) * 2 > by_md_cap) {
        size_t cap = by_md_cap ? by_md_cap * 2 : 64;
        struct sw_md_entry **t = calloc(cap, sizeof *t);
        for (size_t i = 0; i < by_md_cap; i++) {
            struct sw_md_entry *o = by_md[i];
            if (!o) continue;
            size_t j = ptr_hash(o->metadata) & (cap - 1);
            while (t[j]) j = (j + 1) & (cap - 1);
            t[j] = o;
        }
        free(by_md);
        by_md = t;
        by_md_cap = cap;
    }
    size_t j = ptr_hash(e->metadata) & (by_md_cap - 1);
    while (by_md[j]) j = (j + 1) & (by_md_cap - 1);
    by_md[j] = e;
    by_md_count++;
}

static struct sw_md_entry *by_md_find(const sw_metadata *m) {
    if (!by_md_cap) return NULL;
    size_t j = ptr_hash(m) & (by_md_cap - 1);
    for (struct sw_md_entry *e; (e = by_md[j]); j = (j + 1) & (by_md_cap - 1))
        if (e->metadata == m) return e;
    return NULL;
}

struct sw_md_entry *sw_md_entry_new(const sw_metadata *m, sw_completion_fn complete,
                                    const void *pattern) {
    struct sw_md_entry *e = calloc(1, sizeof *e);
    e->metadata = m;
    e->complete = complete;
    e->pattern = pattern;
    e->state = complete ? SW_STATE_ABSTRACT : SW_STATE_COMPLETE;
    sw_md_lock();
    by_md_insert(e);
    sw_md_unlock();
    return e;
}

/* States are ordered with "complete" lowest. */
static int satisfies(uintptr_t have, uintptr_t want) { return have <= want; }

/* Runs the entry's completion function until it succeeds or the request is
 * satisfied. Dependencies are completed first, recursively. A dependency on
 * metadata this thread is already completing is a layout cycle, which valid
 * Swift cannot produce. */
uintptr_t sw_md_complete(struct sw_md_entry *e, uintptr_t want) {
    want &= SW_REQUEST_STATE_MASK;
    sw_md_lock();
    for (int tries = 0; !satisfies(e->state, want); tries++) {
        if (e->busy) break; /* re-entered while completing it: report the current state */
        if (tries > 1000)
            dx_fatal("swift: metadata %p does not complete (dependency loop)", (void *)e->metadata);
        e->busy = 1;
        sw_response dep = e->complete(e->metadata, e->context, e->pattern);
        e->busy = 0;
        if (!dep.value) {
            e->state = SW_STATE_COMPLETE;
            if (e->published) __atomic_store_n(e->published, e->metadata, __ATOMIC_RELEASE);
            break;
        }
        /* The completion is blocked on dep.value reaching dep.state. */
        struct sw_md_entry *d = by_md_find(dep.value);
        if (d && !satisfies(d->state, dep.state)) {
            if (d->busy)
                dx_fatal("swift: metadata %p and %p depend on each other's layout",
                         (void *)e->metadata, (void *)d->metadata);
            sw_md_complete(d, dep.state);
        }
    }
    uintptr_t st = e->state;
    sw_md_unlock();
    return st;
}

/* MetadataResponse swift_checkMetadataState(MetadataRequest, const Metadata *) */
static sw_response d_swift_checkMetadataState(sw_request req, const sw_metadata *m) {
    sw_md_lock();
    struct sw_md_entry *e = by_md_find(m);
    sw_md_unlock();
    if (!e) return (sw_response){m, SW_STATE_COMPLETE};
    uintptr_t st = e->state;
    if (!satisfies(st, req & SW_REQUEST_STATE_MASK)) st = sw_md_complete(e, req);
    return (sw_response){m, st};
}
DX_FN(swift_checkMetadataState);

/* ---- descriptors --------------------------------------------------------------- */

const char *sw_descriptor_name(const sw_type_context_descriptor *desc) {
    return desc ? sw_rel(&desc->name) : NULL;
}

/* Module, protocol and type descriptors all keep their name at offset 8;
 * extensions, anonymous contexts and opaque types have none. */
static const char *context_name(const sw_context_descriptor *c) {
    unsigned k = sw_ctx_kind(c->flags);
    if (k == SW_CTX_MODULE || k == SW_CTX_PROTOCOL || k >= SW_CTX_CLASS)
        return sw_rel((const int32_t *)c + 2);
    return NULL;
}

void sw_descriptor_qualified_name(const sw_context_descriptor *desc, char *buf, size_t len) {
    const char *parts[32];
    int n = 0;
    for (const sw_context_descriptor *c = desc; c && n < 32;
         c = sw_rel_indirect(&c->parent)) {
        const char *s = context_name(c);
        if (s) parts[n++] = s; /* extensions and anonymous contexts are skipped */
    }
    size_t at = 0;
    if (len) buf[0] = 0;
    while (n-- > 0 && len) {
        int w = snprintf(buf + at, len - at, "%s%s", at ? "." : "", parts[n]);
        if (w < 0 || (size_t)w >= len - at) break;
        at += w;
    }
}

size_t sw_type_descriptor_size(const sw_type_context_descriptor *desc) {
    switch (sw_ctx_kind(desc->flags)) {
    case SW_CTX_STRUCT: return sizeof(sw_struct_descriptor);
    case SW_CTX_ENUM: return sizeof(sw_enum_descriptor);
    case SW_CTX_CLASS: return sizeof(sw_class_descriptor);
    default: return sizeof(sw_type_context_descriptor);
    }
}

const sw_type_generic_context_header *sw_generic_header(const sw_type_context_descriptor *desc) {
    if (!sw_ctx_is_generic(desc->flags)) return NULL;
    return (const void *)((const char *)desc + sw_type_descriptor_size(desc));
}

unsigned sw_generic_key_argument_count(const sw_type_context_descriptor *desc) {
    const sw_type_generic_context_header *g = sw_generic_header(desc);
    return g ? g->base.num_key_arguments : 0;
}

/* Trailing objects after a non-generic type descriptor's fixed fields:
 * [resilient superclass (classes)] [foreign init] [singleton init] ... */
const sw_singleton_metadata_initialization *
sw_singleton_init(const sw_type_context_descriptor *desc) {
    unsigned kf = sw_ctx_kind_flags(desc->flags);
    if ((kf & SW_TYPE_METADATA_INIT_MASK) != SW_TYPE_METADATA_INIT_SINGLETON) return NULL;
    if (sw_ctx_is_generic(desc->flags)) return NULL;
    const char *p = (const char *)desc + sw_type_descriptor_size(desc);
    if (sw_ctx_kind(desc->flags) == SW_CTX_CLASS && (kf & SW_CLASS_HAS_RESILIENT_SUPERCLASS))
        p += sizeof(int32_t);
    return (const sw_singleton_metadata_initialization *)p;
}

/* ---- singleton initialisation ---------------------------------------------------
 * The type's descriptor points at a cache {metadata, private} which compiled
 * accessors read directly: a non-null `metadata` means complete. The private
 * word holds our entry while the metadata is being completed. */
static sw_response d_swift_getSingletonMetadata(sw_request req,
                                                const sw_type_context_descriptor *desc) {
    const sw_singleton_metadata_initialization *init = sw_singleton_init(desc);
    if (!init) dx_fatal("swift_getSingletonMetadata: %s has no singleton initialisation",
                        sw_descriptor_name(desc));
    sw_singleton_metadata_cache *cache = (sw_singleton_metadata_cache *)sw_rel(&init->initialization_cache);
    const sw_metadata *done = __atomic_load_n(&cache->metadata, __ATOMIC_ACQUIRE);
    if (done) return (sw_response){done, SW_STATE_COMPLETE};

    sw_md_lock();
    struct sw_md_entry *e = cache->private_data;
    if (!e) {
        const sw_metadata *m = sw_rel(&init->incomplete_metadata);
        e = sw_md_entry_new(m, (sw_completion_fn)sw_rel(&init->completion_function), NULL);
        e->published = (const sw_metadata **)&cache->metadata;
        cache->private_data = e;
    }
    sw_md_unlock();
    /* Non-blocking requests are completed too: under the global lock nobody
     * else can be working on it, and a request from inside its own
     * completion just reports the current state. */
    uintptr_t st = e->state;
    if (!satisfies(st, req & SW_REQUEST_STATE_MASK)) st = sw_md_complete(e, req);
    return (sw_response){e->metadata, st};
}
DX_FN(swift_getSingletonMetadata);

/* ---- struct layout ------------------------------------------------------------------ */

/* Lays out fields in order, each at its alignment, and accumulates the
 * value witness flags the way the compiler does for fixed layouts. */
void sw_basic_layout(sw_type_layout *out, size_t n, const sw_type_layout *const *fields,
                     uint32_t *offsets) {
    size_t size = 0, align_mask = 0;
    uint32_t inherited = 0, xi = 0;
    for (size_t i = 0; i < n; i++) {
        const sw_type_layout *f = fields[i];
        size_t am = f->flags & SW_VW_ALIGNMENT_MASK;
        size = (size + am) & ~am;
        if (offsets) offsets[i] = (uint32_t)size;
        size += f->size;
        align_mask |= am;
        inherited |= f->flags & (SW_VW_IS_NON_POD | SW_VW_IS_NON_BITWISE_TAKABLE |
                                 SW_VW_IS_NON_COPYABLE | SW_VW_IS_NON_BITWISE_BORROWABLE);
        if (f->extraInhabitantCount > xi) xi = f->extraInhabitantCount;
    }
    size_t stride = (size + align_mask) & ~align_mask;
    out->size = size;
    out->stride = stride ? stride : 1;
    out->flags = (uint32_t)align_mask | inherited |
                 (sw_is_inline(!(inherited & SW_VW_IS_NON_BITWISE_TAKABLE), size, align_mask)
                      ? 0 : SW_VW_IS_NON_INLINE);
    out->extraInhabitantCount = xi;
}

/* The VWT a type's metadata points to while it is being initialised is
 * often the compiler's constant pattern; unless the caller says it may be
 * written, give the metadata its own copy. */
sw_vwt *sw_mutable_vwt(sw_metadata *m, uintptr_t layout_flags) {
    sw_vwt *old = (sw_vwt *)sw_vwt_of(m);
    if (layout_flags & SW_LAYOUT_VWT_MUTABLE) return old;
    size_t sz = (old->flags & SW_VW_HAS_ENUM_WITNESSES) ? sizeof(sw_enum_vwt) : sizeof(sw_vwt);
    sw_vwt *copy = malloc(sz);
    memcpy(copy, old, sz);
    ((const sw_vwt **)m)[-1] = copy;
    return copy;
}

void sw_publish_layout(sw_vwt *w, const sw_type_layout *l) {
    w->size = l->size;
    w->stride = l->stride;
    w->extraInhabitantCount = l->extraInhabitantCount;
    /* flags last: clearing "incomplete" publishes the layout */
    __atomic_store_n(&w->flags, l->flags, __ATOMIC_RELEASE);
}

/* void swift_initStructMetadata(StructMetadata *self, StructLayoutFlags flags,
 *     size_t numFields, const TypeLayout *const *fieldTypes, uint32_t *fieldOffsets) */
static void d_swift_initStructMetadata(sw_metadata *self, uintptr_t flags, size_t n,
                                       const sw_type_layout *const *fields, uint32_t *offsets) {
    sw_type_layout l;
    sw_basic_layout(&l, n, fields, offsets);
    sw_vwt *w = sw_mutable_vwt(self, flags);
    l.flags |= w->flags & SW_VW_HAS_ENUM_WITNESSES;
    sw_publish_layout(w, &l);
}
DX_FN(swift_initStructMetadata);
