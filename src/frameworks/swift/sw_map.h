/* A small open-addressing hash map from a pair of words to a pointer, used
 * for the runtime's caches (type names, conformances, witness tables).
 * Header-only and static so each file of the runtime has its own private
 * copy; callers do their own locking. Entries are never removed. */
#ifndef BITTEN_SW_MAP_H
#define BITTEN_SW_MAP_H
#include <stdint.h>
#include <stdlib.h>

struct sw_map_ent {
    uintptr_t a, b;
    void *v;
    int used;
};
struct sw_map {
    struct sw_map_ent *e;
    size_t cap, n;
};

static inline size_t sw_map_hash(uintptr_t a, uintptr_t b) {
    uint64_t h = (uint64_t)a * 0x9E3779B97F4A7C15ull ^ ((uint64_t)b + 0x632BE59BD9B4E019ull) * 0xC2B2AE3D27D4EB4Full;
    return (size_t)(h ^ (h >> 29));
}

static inline struct sw_map_ent *sw_map_slot(const struct sw_map *m, uintptr_t a, uintptr_t b) {
    size_t i = sw_map_hash(a, b) & (m->cap - 1);
    while (m->e[i].used && (m->e[i].a != a || m->e[i].b != b)) i = (i + 1) & (m->cap - 1);
    return &m->e[i];
}

/* Returns the stored value, or NULL (with *found = 0) when absent. */
static inline void *sw_map_get(const struct sw_map *m, uintptr_t a, uintptr_t b, int *found) {
    if (found) *found = 0;
    if (!m->cap) return NULL;
    struct sw_map_ent *s = sw_map_slot(m, a, b);
    if (!s->used) return NULL;
    if (found) *found = 1;
    return s->v;
}

static inline void sw_map_put(struct sw_map *m, uintptr_t a, uintptr_t b, void *v) {
    if ((m->n + 1) * 10 >= m->cap * 7) {
        struct sw_map old = *m;
        m->cap = old.cap ? old.cap * 2 : 64;
        m->e = calloc(m->cap, sizeof *m->e);
        m->n = 0;
        for (size_t i = 0; i < old.cap; i++)
            if (old.e[i].used) {
                struct sw_map_ent *s = sw_map_slot(m, old.e[i].a, old.e[i].b);
                *s = old.e[i];
                m->n++;
            }
        free(old.e);
    }
    struct sw_map_ent *s = sw_map_slot(m, a, b);
    if (!s->used) m->n++;
    s->a = a;
    s->b = b;
    s->v = v;
    s->used = 1;
}

/* FNV-1a over a byte range: string keys go in as (hash, tag) pairs and the
 * caller verifies the string on a hit. */
static inline uintptr_t sw_hash_bytes(const char *s, size_t n) {
    uint64_t h = 0xcbf29ce484222325ull;
    for (size_t i = 0; i < n; i++) h = (h ^ (unsigned char)s[i]) * 0x100000001b3ull;
    return (uintptr_t)h;
}

#endif
