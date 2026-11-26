/* Parameter packs (Swift 5.9 variadic generics).
 *
 * A generic context with packs (header flag 1) has, after its requirements,
 * a pack shape header {uint16 packs, uint16 shape classes} and one
 * descriptor per pack {uint16 kind (0 metadata, 1 witness table), uint16
 * index in the key arguments, uint16 shape class, uint16 unused}. Its key
 * arguments start with one word per shape class: the length shared by the
 * packs of that class. A pack argument is a pointer to its elements whose
 * low bit says where they live: set, on the heap (uniqued, the length in
 * the word before the elements); clear, on the caller's stack. Packs are
 * moved to the heap before they key a cache or go into metadata. */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "swift_internal.h"

const sw_pack_shape_descriptor *sw_pack_shapes(const sw_generic_context_header *h, unsigned *npacks,
                                               unsigned *nshapes) {
    *npacks = *nshapes = 0;
    if (!h || !(h->flags & 1)) return NULL;
    const uint8_t *params = (const uint8_t *)(h + 1);
    const sw_generic_requirement *reqs = (const void *)(params + ((h->num_params + 3) & ~3u));
    const uint16_t *shape = (const uint16_t *)(reqs + h->num_requirements);
    *npacks = shape[0];
    *nshapes = shape[1];
    return (const sw_pack_shape_descriptor *)(shape + 2);
}

/* ---- uniqued heap packs ---- */

struct pack {
    struct pack *next;
    size_t hash;
    size_t count;           /* immediately before the elements */
    const void *elems[];
};

static struct pack *buckets[256];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static const void *const *unique(const void *const *elems, size_t count) {
    uint64_t h = count * 0x9E3779B97F4A7C15ULL;
    for (size_t i = 0; i < count; i++) {
        h ^= (uintptr_t)elems[i];
        h *= 0xff51afd7ed558ccdULL;
        h ^= h >> 29;
    }
    pthread_mutex_lock(&lock);
    struct pack **b = &buckets[h & 255];
    for (struct pack *p = *b; p; p = p->next)
        if (p->hash == h && p->count == count && !memcmp(p->elems, elems, count * sizeof *elems)) {
            pthread_mutex_unlock(&lock);
            return p->elems;
        }
    struct pack *p = malloc(sizeof *p + (count ? count : 1) * sizeof(void *));
    p->hash = h;
    p->count = count;
    memcpy(p->elems, elems, count * sizeof *elems);
    p->next = *b;
    *b = p;
    pthread_mutex_unlock(&lock);
    return p->elems;
}

/* The heap form (tagged) of a pack, given in either form. */
const void *const *sw_heap_pack(const void *const *pack, size_t count) {
    if ((uintptr_t)pack & 1) return pack;
    return (const void *const *)((uintptr_t)unique(pack, count) | 1);
}

const void *const *sw_pack_elements(const void *const *pack) {
    return (const void *const *)((uintptr_t)pack & ~(uintptr_t)1);
}

size_t sw_pack_count(const void *const *pack) {
    if (!((uintptr_t)pack & 1)) return 0;
    return ((const size_t *)sw_pack_elements(pack))[-1];
}

/* const Metadata * const *swift_allocateMetadataPack(const Metadata * const *ptr, size_t count) */
static const void *const *d_swift_allocateMetadataPack(const void *const *ptr, size_t count) {
    return sw_heap_pack(ptr, count);
}
DX_FN(swift_allocateMetadataPack);

/* const WitnessTable * const *swift_allocateWitnessTablePack(const WitnessTable * const *ptr, size_t count) */
static const void *const *d_swift_allocateWitnessTablePack(const void *const *ptr, size_t count) {
    return sw_heap_pack(ptr, count);
}
DX_FN(swift_allocateWitnessTablePack);

/* A key argument buffer with its packs on the heap. `out` has room for
 * the header's key arguments; returns `args` when there are no packs. */
const void *const *sw_normalize_pack_args(const sw_generic_context_header *h, const void *const *args,
                                          const void **out) {
    unsigned npacks, nshapes;
    const sw_pack_shape_descriptor *d = sw_pack_shapes(h, &npacks, &nshapes);
    if (!d || !args) return args;
    memcpy(out, args, h->num_key_arguments * sizeof *out);
    for (unsigned i = 0; i < npacks; i++) {
        if (d[i].index >= h->num_key_arguments || d[i].shape_class >= nshapes) continue;
        size_t count = (size_t)(uintptr_t)args[d[i].shape_class];
        out[d[i].index] = sw_heap_pack((const void *const *)args[d[i].index], count);
    }
    return out;
}
