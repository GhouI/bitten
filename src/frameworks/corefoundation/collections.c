#include <string.h>

#include "cf.h"

static const void *retain_cf(const void *allocator, const void *v) { return d_CFRetain(v); }
static void release_cf(const void *allocator, const void *v) { d_CFRelease(v); }

#define TYPE_CALLBACKS {0, retain_cf, release_cf, d_CFCopyDescription, d_CFEqual}
const struct cf_callbacks d_kCFTypeArrayCallBacks = TYPE_CALLBACKS;
const struct cf_callbacks d_kCFTypeDictionaryValueCallBacks = TYPE_CALLBACKS;
const struct cf_key_callbacks d_kCFTypeDictionaryKeyCallBacks = {TYPE_CALLBACKS, d_CFHash};
static const struct cf_key_callbacks d_kCFTypeSetCallBacks = {TYPE_CALLBACKS, d_CFHash};

static const void *copy_string(const void *allocator, const void *value) {
    return d_CFStringCreateCopy(allocator, value);
}
#define COPY_STRING_CALLBACKS {{0, copy_string, release_cf, d_CFCopyDescription, d_CFEqual}, d_CFHash}
static const struct cf_key_callbacks d_kCFCopyStringDictionaryKeyCallBacks = COPY_STRING_CALLBACKS;
static const struct cf_key_callbacks d_kCFCopyStringSetCallBacks = COPY_STRING_CALLBACKS;

DX_EXPORT("_kCFTypeArrayCallBacks", &d_kCFTypeArrayCallBacks);
DX_EXPORT("_kCFTypeDictionaryValueCallBacks", &d_kCFTypeDictionaryValueCallBacks);
DX_EXPORT("_kCFTypeDictionaryKeyCallBacks", &d_kCFTypeDictionaryKeyCallBacks);
DX_EXPORT("_kCFCopyStringDictionaryKeyCallBacks", &d_kCFCopyStringDictionaryKeyCallBacks);
DX_EXPORT("_kCFTypeSetCallBacks", &d_kCFTypeSetCallBacks);
DX_EXPORT("_kCFCopyStringSetCallBacks", &d_kCFCopyStringSetCallBacks);

static const void *hold(const struct cf_callbacks *cb, const void *allocator, const void *value) {
    return cb->retain ? cb->retain(allocator, value) : value;
}

static void drop(const struct cf_callbacks *cb, const void *allocator, const void *value) {
    if (cb->release) cb->release(allocator, value);
}

static Boolean matches(const struct cf_callbacks *cb, const void *left, const void *right) {
    return left == right || (cb->equal && cb->equal(left, right));
}

struct cf_array {
    struct cf_object base;
    struct cf_callbacks callbacks;
    const void **values;
    CFIndex count;
    size_t capacity;
    Boolean mutable;
};

static void array_destroy(void *object) {
    struct cf_array *a = object;
    for (CFIndex i = 0; i < a->count; i++) drop(&a->callbacks, a->base.allocator, a->values[i]);
    free(a->values);
}
static Boolean array_equal(const void *left, const void *right) {
    const struct cf_array *a = left, *b = right;
    if (a->count != b->count || a->callbacks.equal != b->callbacks.equal) return 0;
    for (CFIndex i = 0; i < a->count; i++)
        if (!matches(&a->callbacks, a->values[i], b->values[i])) return 0;
    return 1;
}
static CFHashCode array_hash(const void *object) {
    const struct cf_array *a = object;
    return a->count;
}
static const struct cf_ops array_ops = {.destroy = array_destroy, .equal = array_equal, .hash = array_hash};
CF_TYPE_ID(CFArray, CF_ARRAY);

static Boolean array_reserve(struct cf_array *a, CFIndex capacity) {
    void *values;
    if (!cf_grow(a->values, &a->capacity, capacity, sizeof *a->values, &values)) return 0;
    a->values = values;
    return 1;
}

static struct cf_array *array_create(const void *allocator, CFIndex capacity,
                                     const struct cf_callbacks *callbacks, Boolean mutable) {
    if (capacity < 0 || (callbacks && callbacks->version != 0)) return NULL;
    struct cf_array *a = cf_alloc(allocator, sizeof *a, CF_ARRAY, &array_ops);
    if (!a) return NULL;
    if (!array_reserve(a, capacity)) { d_CFRelease(a); return NULL; }
    a->mutable = mutable;
    if (callbacks) a->callbacks = *callbacks;
    return a;
}

struct cf_array *d_CFArrayCreate(const void *allocator, const void **values, CFIndex count,
                                 const struct cf_callbacks *callbacks) {
    if (count && !values) return NULL;
    struct cf_array *a = array_create(allocator, count, callbacks, 0);
    if (!a) return NULL;
    for (CFIndex i = 0; i < count; i++) {
        const void *value = hold(&a->callbacks, a->base.allocator, values[i]);
        if (values[i] && !value) { d_CFRelease(a); return NULL; }
        a->values[a->count++] = value;
    }
    return a;
}
DX_FN(CFArrayCreate);

static struct cf_array *d_CFArrayCreateMutable(const void *allocator, CFIndex capacity,
                                                const struct cf_callbacks *callbacks) {
    return array_create(allocator, capacity, callbacks, 1);
}
DX_FN(CFArrayCreateMutable);

struct cf_array *d_CFArrayCreateCopy(const void *allocator, const struct cf_array *a) {
    return a ? d_CFArrayCreate(allocator, a->values, a->count, &a->callbacks) : NULL;
}
DX_FN(CFArrayCreateCopy);

static struct cf_array *d_CFArrayCreateMutableCopy(const void *allocator, CFIndex capacity,
                                                    const struct cf_array *a) {
    if (!a || capacity < 0) return NULL;
    struct cf_array *copy = d_CFArrayCreateCopy(allocator, a);
    if (copy && !array_reserve(copy, capacity)) { d_CFRelease(copy); return NULL; }
    if (copy) copy->mutable = 1;
    return copy;
}
DX_FN(CFArrayCreateMutableCopy);

CFIndex d_CFArrayGetCount(const struct cf_array *a) { return a ? a->count : 0; }
DX_FN(CFArrayGetCount);

const void *d_CFArrayGetValueAtIndex(const struct cf_array *a, CFIndex index) {
    return a && index >= 0 && index < a->count ? a->values[index] : NULL;
}
DX_FN(CFArrayGetValueAtIndex);

static void d_CFArrayGetValues(const struct cf_array *a, CFRange range, const void **values) {
    if (a && values && range.length && cf_range_valid(range, a->count))
        memcpy(values, a->values + range.location, range.length * sizeof *values);
}
DX_FN(CFArrayGetValues);

static Boolean d_CFArrayContainsValue(const struct cf_array *a, CFRange range, const void *value) {
    if (!a || !cf_range_valid(range, a->count)) return 0;
    for (CFIndex i = range.location; i < range.location + range.length; i++)
        if (matches(&a->callbacks, a->values[i], value)) return 1;
    return 0;
}
DX_FN(CFArrayContainsValue);

static void d_CFArrayInsertValueAtIndex(struct cf_array *a, CFIndex index, const void *value) {
    if (!a || !a->mutable || index < 0 || index > a->count || a->count == LONG_MAX ||
        !array_reserve(a, a->count + 1)) return;
    const void *retained = hold(&a->callbacks, a->base.allocator, value);
    if (value && !retained) return;
    memmove(a->values + index + 1, a->values + index, (a->count - index) * sizeof *a->values);
    a->values[index] = retained;
    a->count++;
}
DX_FN(CFArrayInsertValueAtIndex);

static void d_CFArrayAppendValue(struct cf_array *a, const void *value) {
    if (a) d_CFArrayInsertValueAtIndex(a, a->count, value);
}
DX_FN(CFArrayAppendValue);

static void d_CFArraySetValueAtIndex(struct cf_array *a, CFIndex index, const void *value) {
    if (!a || !a->mutable || index < 0 || index > a->count) return;
    if (index == a->count) { d_CFArrayAppendValue(a, value); return; }
    const void *retained = hold(&a->callbacks, a->base.allocator, value);
    if (value && !retained) return;
    const void *old = a->values[index];
    a->values[index] = retained;
    drop(&a->callbacks, a->base.allocator, old);
}
DX_FN(CFArraySetValueAtIndex);

static void d_CFArrayRemoveValueAtIndex(struct cf_array *a, CFIndex index) {
    if (!a || !a->mutable || index < 0 || index >= a->count) return;
    const void *old = a->values[index];
    a->count--;
    memmove(a->values + index, a->values + index + 1, (a->count - index) * sizeof *a->values);
    drop(&a->callbacks, a->base.allocator, old);
}
DX_FN(CFArrayRemoveValueAtIndex);

static void d_CFArrayRemoveAllValues(struct cf_array *a) {
    if (a && a->mutable)
        while (a->count) d_CFArrayRemoveValueAtIndex(a, a->count - 1);
}
DX_FN(CFArrayRemoveAllValues);

struct cf_entry {
    const void *key, *value;
};
struct cf_dict {
    struct cf_object base;
    struct cf_key_callbacks keys;
    struct cf_callbacks values;
    struct cf_entry *entries;
    CFIndex count;
    size_t capacity;
    Boolean mutable;
};

static CFIndex dict_find(const struct cf_dict *d, const void *key) {
    for (CFIndex i = 0; i < d->count; i++)
        if (matches(&d->keys.value, d->entries[i].key, key)) return i;
    return -1;
}
static void dict_drop(struct cf_dict *d, struct cf_entry entry) {
    drop(&d->keys.value, d->base.allocator, entry.key);
    drop(&d->values, d->base.allocator, entry.value);
}
static void dict_destroy(void *object) {
    struct cf_dict *d = object;
    for (CFIndex i = 0; i < d->count; i++) dict_drop(d, d->entries[i]);
    free(d->entries);
}
static Boolean dict_equal(const void *left, const void *right) {
    const struct cf_dict *a = left, *b = right;
    if (a->count != b->count || a->keys.value.equal != b->keys.value.equal ||
        a->values.equal != b->values.equal) return 0;
    for (CFIndex i = 0; i < a->count; i++) {
        CFIndex j = dict_find(b, a->entries[i].key);
        if (j < 0 || !matches(&a->values, a->entries[i].value, b->entries[j].value)) return 0;
    }
    return 1;
}
static CFHashCode dict_hash(const void *object) {
    const struct cf_dict *d = object;
    return d->count;
}
static const struct cf_ops dict_ops = {.destroy = dict_destroy, .equal = dict_equal, .hash = dict_hash};
CF_TYPE_ID(CFDictionary, CF_DICTIONARY);
CF_TYPE_ID(CFSet, CF_SET);

static Boolean dict_reserve(struct cf_dict *d, CFIndex capacity) {
    void *entries;
    if (!cf_grow(d->entries, &d->capacity, capacity, sizeof *d->entries, &entries)) return 0;
    d->entries = entries;
    return 1;
}

static struct cf_dict *dict_create(const void *allocator, CFIndex capacity, CFTypeID type,
                                   const struct cf_key_callbacks *keys, const struct cf_callbacks *values,
                                   Boolean mutable) {
    if (capacity < 0 || (keys && keys->value.version) || (values && values->version)) return NULL;
    struct cf_dict *d = cf_alloc(allocator, sizeof *d, type, &dict_ops);
    if (!d) return NULL;
    if (!dict_reserve(d, capacity)) { d_CFRelease(d); return NULL; }
    d->mutable = mutable;
    if (keys) d->keys = *keys;
    if (values) d->values = *values;
    return d;
}

static Boolean dict_insert(struct cf_dict *d, CFIndex index, const void *key, const void *value) {
    if (index < 0 && (d->count == LONG_MAX || !dict_reserve(d, d->count + 1))) return 0;
    const void *held_value = hold(&d->values, d->base.allocator, value);
    if (value && !held_value) return 0;
    if (index >= 0) {
        const void *old = d->entries[index].value;
        d->entries[index].value = held_value;
        drop(&d->values, d->base.allocator, old);
    } else {
        const void *held_key = hold(&d->keys.value, d->base.allocator, key);
        if (key && !held_key) {
            drop(&d->values, d->base.allocator, held_value);
            return 0;
        }
        d->entries[d->count++] = (struct cf_entry){held_key, held_value};
    }
    return 1;
}

struct cf_dict *d_CFDictionaryCreate(const void *allocator, const void **keys, const void **values,
                                      CFIndex count, const struct cf_key_callbacks *key_callbacks,
                                      const struct cf_callbacks *value_callbacks) {
    if (count && (!keys || !values)) return NULL;
    struct cf_dict *d = dict_create(allocator, count, CF_DICTIONARY, key_callbacks, value_callbacks, 0);
    if (!d) return NULL;
    for (CFIndex i = 0; i < count; i++) {
        if (!dict_insert(d, dict_find(d, keys[i]), keys[i], values[i])) {
            d_CFRelease(d);
            return NULL;
        }
    }
    return d;
}
DX_FN(CFDictionaryCreate);

static struct cf_dict *d_CFDictionaryCreateMutable(const void *allocator, CFIndex capacity,
                                                     const struct cf_key_callbacks *keys,
                                                     const struct cf_callbacks *values) {
    return dict_create(allocator, capacity, CF_DICTIONARY, keys, values, 1);
}
DX_FN(CFDictionaryCreateMutable);

static struct cf_dict *dict_copy(const void *allocator, CFIndex capacity, const struct cf_dict *d,
                                 Boolean mutable) {
    if (!d || capacity < 0) return NULL;
    struct cf_dict *copy = dict_create(allocator, d->count > capacity ? d->count : capacity,
                                       d->base.type, &d->keys, &d->values, mutable);
    if (!copy) return NULL;
    for (CFIndex i = 0; i < d->count; i++) {
        if (!dict_insert(copy, -1, d->entries[i].key, d->entries[i].value)) {
            d_CFRelease(copy);
            return NULL;
        }
    }
    return copy;
}

struct cf_dict *d_CFDictionaryCreateCopy(const void *allocator, const struct cf_dict *d) {
    return dict_copy(allocator, 0, d, 0);
}
DX_FN(CFDictionaryCreateCopy);

static struct cf_dict *d_CFDictionaryCreateMutableCopy(const void *allocator, CFIndex capacity,
                                                         const struct cf_dict *d) {
    return dict_copy(allocator, capacity, d, 1);
}
DX_FN(CFDictionaryCreateMutableCopy);

static CFIndex d_CFDictionaryGetCount(const struct cf_dict *d) { return d ? d->count : 0; }
DX_FN(CFDictionaryGetCount);

const void *d_CFDictionaryGetValue(const struct cf_dict *d, const void *key) {
    CFIndex i = d ? dict_find(d, key) : -1;
    return i >= 0 ? d->entries[i].value : NULL;
}
DX_FN(CFDictionaryGetValue);

static Boolean d_CFDictionaryGetValueIfPresent(const struct cf_dict *d, const void *key, const void **out) {
    CFIndex i = d ? dict_find(d, key) : -1;
    if (i >= 0 && out) *out = d->entries[i].value;
    return i >= 0;
}
DX_FN(CFDictionaryGetValueIfPresent);

static Boolean d_CFDictionaryContainsKey(const struct cf_dict *d, const void *key) {
    return d && dict_find(d, key) >= 0;
}
DX_FN(CFDictionaryContainsKey);

static void d_CFDictionaryGetKeysAndValues(const struct cf_dict *d, const void **keys, const void **values) {
    if (!d) return;
    for (CFIndex i = 0; i < d->count; i++) {
        if (keys) keys[i] = d->entries[i].key;
        if (values) values[i] = d->entries[i].value;
    }
}
DX_FN(CFDictionaryGetKeysAndValues);

static void d_CFDictionarySetValue(struct cf_dict *d, const void *key, const void *value) {
    if (d && d->mutable) dict_insert(d, dict_find(d, key), key, value);
}
DX_FN(CFDictionarySetValue);

static void d_CFDictionaryAddValue(struct cf_dict *d, const void *key, const void *value) {
    if (d && d->mutable && dict_find(d, key) < 0) dict_insert(d, -1, key, value);
}
DX_FN(CFDictionaryAddValue);

static void d_CFDictionaryReplaceValue(struct cf_dict *d, const void *key, const void *value) {
    if (!d || !d->mutable) return;
    CFIndex i = dict_find(d, key);
    if (i >= 0) dict_insert(d, i, key, value);
}
DX_FN(CFDictionaryReplaceValue);

static void d_CFDictionaryRemoveValue(struct cf_dict *d, const void *key) {
    if (!d || !d->mutable) return;
    CFIndex i = dict_find(d, key);
    if (i < 0) return;
    struct cf_entry old = d->entries[i];
    d->entries[i] = d->entries[--d->count];
    dict_drop(d, old);
}
DX_FN(CFDictionaryRemoveValue);

static void d_CFDictionaryRemoveAllValues(struct cf_dict *d) {
    if (d && d->mutable)
        while (d->count) dict_drop(d, d->entries[--d->count]);
}
DX_FN(CFDictionaryRemoveAllValues);

static struct cf_dict *d_CFSetCreate(const void *allocator, const void **values, CFIndex count,
                                     const struct cf_key_callbacks *callbacks) {
    if (count && !values) return NULL;
    struct cf_dict *set = dict_create(allocator, count, CF_SET, callbacks, NULL, 0);
    if (!set) return NULL;
    for (CFIndex i = 0; i < count; i++) {
        if (dict_find(set, values[i]) < 0 && !dict_insert(set, -1, values[i], NULL)) {
            d_CFRelease(set);
            return NULL;
        }
    }
    return set;
}
DX_FN(CFSetCreate);

static struct cf_dict *d_CFSetCreateMutable(const void *allocator, CFIndex capacity,
                                            const struct cf_key_callbacks *callbacks) {
    return dict_create(allocator, capacity, CF_SET, callbacks, NULL, 1);
}
DX_FN(CFSetCreateMutable);

static struct cf_dict *d_CFSetCreateCopy(const void *allocator, const struct cf_dict *set) {
    return dict_copy(allocator, 0, set, 0);
}
DX_FN(CFSetCreateCopy);

DX_EXPORT("_CFSetGetCount", d_CFDictionaryGetCount);
DX_EXPORT("_CFSetContainsValue", d_CFDictionaryContainsKey);
DX_EXPORT("_CFSetRemoveValue", d_CFDictionaryRemoveValue);
DX_EXPORT("_CFSetRemoveAllValues", d_CFDictionaryRemoveAllValues);

static void d_CFSetAddValue(struct cf_dict *set, const void *value) {
    d_CFDictionaryAddValue(set, value, NULL);
}
DX_FN(CFSetAddValue);

static const void *d_CFSetGetValue(const struct cf_dict *set, const void *value) {
    CFIndex i = set ? dict_find(set, value) : -1;
    return i >= 0 ? set->entries[i].key : NULL;
}
DX_FN(CFSetGetValue);

static void d_CFSetGetValues(const struct cf_dict *set, const void **values) {
    d_CFDictionaryGetKeysAndValues(set, values, NULL);
}
DX_FN(CFSetGetValues);

/* The shared empty collections the compiler references for `@[]` and `@{}`
 * literals: the symbols are the objects themselves. */
static struct cf_array empty_array = {.base = CF_STATIC(CF_ARRAY, &array_ops)};
static struct cf_dict empty_dict = {.base = CF_STATIC(CF_DICTIONARY, &dict_ops)};
DX_EXPORT("___NSArray0__", &empty_array);
DX_EXPORT("___NSDictionary0__", &empty_dict);
__attribute__((constructor)) static void empty_collections_init(void) {
    empty_array.callbacks = d_kCFTypeArrayCallBacks;
    empty_dict.keys = d_kCFTypeDictionaryKeyCallBacks;
    empty_dict.values = d_kCFTypeDictionaryValueCallBacks;
}
