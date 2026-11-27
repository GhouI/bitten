/* Generic type metadata: instantiation from the compiler's patterns and
 * the cache that makes Pair<Int, Int> the same pointer every time.
 *
 * The cache is keyed by the descriptor and its key arguments (the generic
 * parameters that are not fixed by same-type requirements, followed by the
 * witness tables of their protocol requirements). An entry is inserted
 * before the metadata is completed, so that completion functions that
 * (indirectly) ask for the same type find it and get its current state. */
#define _GNU_SOURCE
#include <alloca.h>
#include <stdlib.h>
#include <string.h>

#include "swift_internal.h"

struct gm_entry {
    const sw_type_context_descriptor *desc;
    size_t hash;
    unsigned nkeys;
    struct sw_md_entry *md;
    const void *keys[];
};

static struct gm_entry **table;
static size_t cap, count;

static size_t key_hash(const sw_type_context_descriptor *desc, const void *const *keys,
                       unsigned n) {
    uint64_t h = (uintptr_t)desc * 0x9E3779B97F4A7C15ULL;
    for (unsigned i = 0; i < n; i++) {
        h ^= (uintptr_t)keys[i];
        h *= 0xff51afd7ed558ccdULL;
        h ^= h >> 32;
    }
    return (size_t)h;
}

static struct gm_entry *find(const sw_type_context_descriptor *desc, const void *const *keys,
                             unsigned n, size_t h) {
    if (!cap) return NULL;
    for (size_t j = h & (cap - 1); table[j]; j = (j + 1) & (cap - 1)) {
        struct gm_entry *e = table[j];
        if (e->hash == h && e->desc == desc && e->nkeys == n &&
            !memcmp(e->keys, keys, n * sizeof *keys))
            return e;
    }
    return NULL;
}

static void insert(struct gm_entry *e) {
    if ((count + 1) * 2 > cap) {
        size_t ncap = cap ? cap * 2 : 64;
        struct gm_entry **t = calloc(ncap, sizeof *t);
        for (size_t i = 0; i < cap; i++) {
            if (!table[i]) continue;
            size_t j = table[i]->hash & (ncap - 1);
            while (t[j]) j = (j + 1) & (ncap - 1);
            t[j] = table[i];
        }
        free(table);
        table = t;
        cap = ncap;
    }
    size_t j = e->hash & (cap - 1);
    while (table[j]) j = (j + 1) & (cap - 1);
    table[j] = e;
    count++;
}

static const sw_generic_metadata_pattern *default_pattern(const sw_type_context_descriptor *desc) {
    const sw_type_generic_context_header *g = sw_type_generic_header(desc);
    return g ? sw_rel(&g->default_instantiation_pattern) : NULL;
}

/* MetadataResponse swift_getGenericMetadata(MetadataRequest request,
 *     const void *const *arguments, const TypeContextDescriptor *description) */
static sw_response d_swift_getGenericMetadata(sw_request req, const void *const *args,
                                              const sw_type_context_descriptor *desc) {
    const sw_type_generic_context_header *g = sw_type_generic_header(desc);
    if (!g) dx_fatal("swift_getGenericMetadata: %s is not generic", sw_descriptor_name(desc));
    unsigned n = g->base.num_key_arguments;
    /* Packs key the cache (and go into the metadata) in their heap form. */
    const void **normal = (g->base.flags & 1) ? alloca((n + 1) * sizeof *normal) : NULL;
    if (normal) args = sw_normalize_pack_args(&g->base, args, normal);
    size_t h = key_hash(desc, args, n);

    /* Entries are never removed: each thread keeps the ones it has used
     * recently, and only a miss takes the lock. */
    static __thread struct gm_entry *recent[256];
    struct gm_entry *e = recent[h & 255];
    if (e && e->desc == desc && e->hash == h && e->nkeys == n && !memcmp(e->keys, args, n * sizeof(void *))) {
        uintptr_t st = e->md->state;
        if (st > (req & SW_REQUEST_STATE_MASK)) st = sw_md_complete(e->md, req);
        return (sw_response){e->md->metadata, st};
    }
    sw_md_lock();
    e = find(desc, args, n, h);
    if (!e) {
        const sw_generic_metadata_pattern *pat = default_pattern(desc);
        sw_metadata_instantiation_fn inst = (sw_metadata_instantiation_fn)sw_rel(&pat->instantiation_function);
        const sw_metadata *m = inst(desc, args, pat);
        e = malloc(sizeof *e + n * sizeof(void *));
        e->desc = desc;
        e->hash = h;
        e->nkeys = n;
        memcpy(e->keys, args, n * sizeof(void *));
        e->md = sw_md_entry_new(m, (sw_completion_fn)sw_rel(&pat->completion_function), pat);
        insert(e);
    }
    sw_md_unlock();
    recent[h & 255] = e;
    uintptr_t st = e->md->state;
    if (st > (req & SW_REQUEST_STATE_MASK)) st = sw_md_complete(e->md, req);
    return (sw_response){e->md->metadata, st};
}
DX_FN(swift_getGenericMetadata);

const sw_metadata *sw_get_generic_metadata(const sw_type_context_descriptor *desc,
                                           const void *const *arguments) {
    return d_swift_getGenericMetadata(SW_STATE_COMPLETE, arguments, desc).value;
}

/* Value metadata header: [-2] layout string, [-1] value witnesses. */
enum { VALUE_HEADER_WORDS = 2, VALUE_METADATA_WORDS = 2 };

/* ValueMetadata *swift_allocateGenericValueMetadata(const ValueTypeDescriptor *,
 *     const void *arguments, const GenericValueMetadataPattern *, size_t extraDataSize)
 * extraDataSize counts everything after {kind, description}: generic
 * arguments, field offsets or payload size, trailing flags. */
static sw_metadata *d_swift_allocateGenericValueMetadata(const sw_type_context_descriptor *desc,
                                                         const void *const *args,
                                                         const sw_generic_value_metadata_pattern *pat,
                                                         size_t extra) {
    size_t words = VALUE_HEADER_WORDS + VALUE_METADATA_WORDS + (extra + 7) / 8;
    void **full = calloc(words, sizeof(void *));
    void **m = full + VALUE_HEADER_WORDS;
    uint32_t pflags = pat->base.flags;
    /* The extra data pattern {relative pattern, uint16 offset, uint16 size}
     * follows the VWT field; its offset counts words after {kind, description}. */
    if (pflags & 1) {
        const int32_t *xd = &pat->value_witnesses + 1;
        const uint16_t *os = (const uint16_t *)(xd + 1);
        memcpy(m + VALUE_METADATA_WORDS + os[0], sw_rel(xd), os[1] * sizeof(void *));
    }
    /* indirectable: a table in another image (a builtin type's) is reached
     * through a pointer slot */
    m[-1] = (void *)sw_rel_indirect(&pat->value_witnesses);
    m[0] = (void *)(uintptr_t)(pflags >> 21);
    m[1] = (void *)desc;
    unsigned n = sw_generic_key_argument_count(desc);
    memcpy(m + VALUE_METADATA_WORDS, args, n * sizeof(void *));
    return (sw_metadata *)m;
}
DX_FN(swift_allocateGenericValueMetadata);
