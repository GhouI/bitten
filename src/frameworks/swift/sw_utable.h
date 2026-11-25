/* Uniquing tables for runtime-built metadata (tuples, functions,
 * metatypes, existentials): keys are arrays of words, each entry keeps its
 * key next to the value. Header-only and static, like sw_map.h; callers
 * hold the metadata lock. Entries are never removed. */
#ifndef BITTEN_SW_UTABLE_H
#define BITTEN_SW_UTABLE_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct uentry {
    size_t hash, nwords;
    const void *value;
    uintptr_t key[];
};
struct utable {
    struct uentry **slots;
    size_t cap, count;
};

static inline size_t words_hash(const uintptr_t *w, size_t n) {
    uint64_t h = 0xcbf29ce484222325ULL ^ n;
    for (size_t i = 0; i < n; i++) {
        h ^= w[i];
        h *= 0xff51afd7ed558ccdULL;
        h ^= h >> 31;
    }
    return (size_t)h;
}

static inline const void *ufind(struct utable *t, const uintptr_t *key, size_t n, size_t h) {
    if (!t->cap) return NULL;
    for (size_t j = h & (t->cap - 1); t->slots[j]; j = (j + 1) & (t->cap - 1)) {
        struct uentry *e = t->slots[j];
        if (e->hash == h && e->nwords == n && !memcmp(e->key, key, n * sizeof *key))
            return e->value;
    }
    return NULL;
}

static inline void uinsert(struct utable *t, const uintptr_t *key, size_t n, size_t h, const void *value) {
    if ((t->count + 1) * 2 > t->cap) {
        size_t cap = t->cap ? t->cap * 2 : 64;
        struct uentry **s = calloc(cap, sizeof *s);
        for (size_t i = 0; i < t->cap; i++) {
            if (!t->slots[i]) continue;
            size_t j = t->slots[i]->hash & (cap - 1);
            while (s[j]) j = (j + 1) & (cap - 1);
            s[j] = t->slots[i];
        }
        free(t->slots);
        t->slots = s;
        t->cap = cap;
    }
    struct uentry *e = malloc(sizeof *e + n * sizeof *key);
    e->hash = h;
    e->nwords = n;
    e->value = value;
    memcpy(e->key, key, n * sizeof *key);
    size_t j = h & (t->cap - 1);
    while (t->slots[j]) j = (j + 1) & (t->cap - 1);
    t->slots[j] = e;
    t->count++;
}

#endif
