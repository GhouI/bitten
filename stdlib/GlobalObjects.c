/* Statically allocated objects of the standard library.
 *
 * Every empty Dictionary and Set shares one storage object, and programs
 * load its address directly (`__swiftEmptyDictionarySingleton`,
 * `__swiftEmptySetSingleton`), so these are C data symbols, as in Apple's
 * runtime. Each is a Swift object: the class metadata of
 * __EmptyDictionarySingleton / __EmptySetSingleton (defined in Swift in
 * this library), an immortal reference count (low 32 bits all ones, which
 * the runtime never changes and never frees), then the storage header of
 * __RawDictionaryStorage / __RawSetStorage and one bitmap word.
 *
 * The table has one bucket (scale 0), empty, and capacity 0 so that any
 * insertion allocates real storage first. Bit 0 of the bitmap is clear (no
 * member); the bits above it are set, which ends iteration and hole
 * searches at bucket 1. The element pointers are never dereferenced (the
 * count is 0) but are not NULL. */
#include <stdint.h>

extern char empty_dictionary_class[] __asm__("_$ss26__EmptyDictionarySingletonCN");
extern char empty_set_class[] __asm__("_$ss19__EmptySetSingletonCN");

#define IMMORTAL (~0ull)

struct empty_dictionary {
    void *isa;
    uint64_t refcounts;
    intptr_t count, capacity;
    int8_t scale, reserved_scale;
    int16_t extra;
    int32_t age;
    intptr_t seed;
    void *raw_keys, *raw_values;
    uintptr_t words[1];
};

struct empty_set {
    void *isa;
    uint64_t refcounts;
    intptr_t count, capacity;
    int8_t scale, reserved_scale;
    int16_t extra;
    int32_t age;
    intptr_t seed;
    void *raw_elements;
    uintptr_t words[1];
};

_Static_assert(__builtin_offsetof(struct empty_dictionary, words) == 64, "dictionary storage header");
_Static_assert(__builtin_offsetof(struct empty_set, words) == 56, "set storage header");

__attribute__((visibility("default"), aligned(16)))
struct empty_dictionary _swiftEmptyDictionarySingleton = {
    .isa = empty_dictionary_class,
    .refcounts = IMMORTAL,
    .raw_keys = (void *)1,
    .raw_values = (void *)1,
    .words = { ~(uintptr_t)1 },
};

__attribute__((visibility("default"), aligned(16)))
struct empty_set _swiftEmptySetSingleton = {
    .isa = empty_set_class,
    .refcounts = IMMORTAL,
    .raw_elements = (void *)1,
    .words = { ~(uintptr_t)1 },
};

/* For the standard library's own Swift code, which cannot take the address
 * of a C global without a Clang module. */
void *_swift_bitten_emptyDictionarySingleton(void) { return &_swiftEmptyDictionarySingleton; }
void *_swift_bitten_emptySetSingleton(void) { return &_swiftEmptySetSingleton; }
