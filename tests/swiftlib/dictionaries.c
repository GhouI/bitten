// Driver for dictionaries.swift. Besides running the Swift checks, it walks
// native Dictionary and Set storage the way inlined code in programs does:
// header fields at fixed offsets, the occupancy bitmap after the header,
// lookups by `hash(seed) & mask` with linear probing.
#include "darwin.h"

unsigned long swd_empty_storage(void);
unsigned long swd_empty_set_storage(void);
unsigned long swd_squares(long n);
unsigned long swd_set_of(long n);
long swd_seed_hash(long key, long seed);
long swd_basics(void);
long swd_growth(void);
long swd_cow(void);
long swd_objects(void);
long swd_iteration(void);
long swd_api(void);
long swd_sets(void);

extern char _swiftEmptyDictionarySingleton[];
extern char _swiftEmptySetSingleton[];

static int deaths[4096];
void swd_note_deinit(long id) {
    if (id >= 0 && id < 4096) deaths[id]++;
}

#define FIELD(s, off, type) (*(type *)((char *)(s) + (off)))

static int occupied(const unsigned long *words, long b) { return (words[b >> 6] >> (b & 63)) & 1; }

static void check_empty(void) {
    char *d = (char *)swd_empty_storage(), *s = (char *)swd_empty_set_storage();
    CHECK(d == _swiftEmptyDictionarySingleton);
    CHECK(s == _swiftEmptySetSingleton);
    CHECK(FIELD(d, 16, long) == 0 && FIELD(d, 24, long) == 0 && FIELD(d, 32, signed char) == 0);
    CHECK(FIELD(d, 64, unsigned long) == ~1ul);
    CHECK(FIELD(s, 16, long) == 0 && FIELD(s, 56, unsigned long) == ~1ul);
    /* Immortal: the reference count word is all ones and stays so. */
    CHECK(FIELD(d, 8, unsigned long) == ~0ul && FIELD(s, 8, unsigned long) == ~0ul);
}

static void check_dictionary_layout(void) {
    long n = 300;
    char *s = (char *)swd_squares(n);
    long count = FIELD(s, 16, long), capacity = FIELD(s, 24, long);
    int scale = FIELD(s, 32, signed char);
    long seed = FIELD(s, 40, long);
    long *keys = FIELD(s, 48, long *), *values = FIELD(s, 56, long *);
    const unsigned long *words = (const unsigned long *)(s + 64);
    long buckets = 1l << scale, mask = buckets - 1;
    CHECK(count == n && capacity >= n && capacity < buckets);
    /* The bitmap has exactly `count` members, each a key and its square. */
    long seen = 0;
    for (long b = 0; b < buckets; b++) {
        if (!occupied(words, b)) continue;
        seen++;
        CHECK(values[b] == keys[b] * keys[b]);
    }
    CHECK(seen == n);
    /* Lookups as inlined code does them. */
    for (long k = 0; k < n + 20; k++) {
        long b = swd_seed_hash(k, seed) & mask, found = -1;
        while (occupied(words, b)) {
            if (keys[b] == k) { found = b; break; }
            b = (b + 1) & mask;
        }
        CHECK(k < n ? (found >= 0 && values[found] == k * k) : found < 0);
    }
}

static void check_set_layout(void) {
    long n = 100;
    char *s = (char *)swd_set_of(n);
    int scale = FIELD(s, 32, signed char);
    long seed = FIELD(s, 40, long);
    long *elements = FIELD(s, 48, long *);
    const unsigned long *words = (const unsigned long *)(s + 56);
    long buckets = 1l << scale, mask = buckets - 1;
    CHECK(FIELD(s, 16, long) == n);
    CHECK((char *)elements >= s + 56 + 8 * ((buckets + 63) / 64));
    for (long k = 0; k < 3 * n; k++) {
        long b = swd_seed_hash(k, seed) & mask, found = 0;
        while (occupied(words, b)) {
            if (elements[b] == k) { found = 1; break; }
            b = (b + 1) & mask;
        }
        CHECK(found == (k % 3 == 0));
    }
}

static void report(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    CHECK(bad == 0);
}

int main(void) {
    check_empty();
    check_dictionary_layout();
    check_set_layout();
    report("basics", swd_basics());
    report("growth", swd_growth());
    report("cow", swd_cow());
    report("objects", swd_objects());
    /* Every Box died exactly once, plus once for each temporary made for a
     * lookup: key 5 was looked up twice, 6 once (the stored key stays,
     * the new one is dropped), 7 three times, 303 and 1000... once. */
    for (int i = 0; i < 20; i++) {
        int expect = i == 5 ? 3 : i == 6 ? 2 : i == 7 ? 4 : 1;
        if (deaths[i] != expect) printf("key %d died %d times\n", i, deaths[i]);
        CHECK(deaths[i] == expect && deaths[100 + i] == 1);
    }
    CHECK(deaths[206] == 1);
    for (int i = 300; i < 310; i++) CHECK(deaths[i] == (i == 303 ? 2 : 1));
    for (int i = 1000; i < 1200; i++) CHECK(deaths[i] == 2 && deaths[i + 1000] == 1);
    report("iteration", swd_iteration());
    report("api", swd_api());
    report("sets", swd_sets());
    puts("swift stdlib dictionaries ok");
    return 0;
}
