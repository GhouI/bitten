#include <string.h>

#include "cf.h"

struct cf_data {
    struct cf_object base;
    uint8_t *bytes;
    CFIndex length;
    size_t capacity;
    Boolean mutable;
};
static void data_destroy(void *object) {
    struct cf_data *d = object;
    free(d->bytes);
}
static Boolean data_equal(const void *left, const void *right) {
    const struct cf_data *a = left, *b = right;
    return a->length == b->length && (!a->length || !memcmp(a->bytes, b->bytes, a->length));
}
static CFHashCode data_hash(const void *object) {
    const struct cf_data *d = object;
    return cf_hash_bytes(d->bytes, d->length);
}
static const struct cf_ops data_ops = {.destroy = data_destroy, .equal = data_equal, .hash = data_hash};
CF_TYPE_ID(CFData, CF_DATA);

static struct cf_data *data_create(const void *allocator, CFIndex capacity, Boolean mutable) {
    if (capacity < 0) return NULL;
    struct cf_data *d = cf_alloc(allocator, sizeof *d, CF_DATA, &data_ops);
    if (!d) return NULL;
    d->mutable = mutable;
    if (capacity) {
        d->bytes = malloc(capacity);
        if (!d->bytes) { d_CFRelease(d); return NULL; }
        d->capacity = capacity;
    }
    return d;
}

struct cf_data *d_CFDataCreate(const void *allocator, const uint8_t *bytes, CFIndex length) {
    if (length && !bytes) return NULL;
    struct cf_data *d = data_create(allocator, length, 0);
    if (d) {
        if (length) memcpy(d->bytes, bytes, length);
        d->length = length;
    }
    return d;
}
DX_FN(CFDataCreate);

static struct cf_data *d_CFDataCreateMutable(const void *allocator, CFIndex capacity) {
    return data_create(allocator, capacity, 1);
}
DX_FN(CFDataCreateMutable);

static struct cf_data *d_CFDataCreateCopy(const void *allocator, const struct cf_data *d) {
    return d ? d_CFDataCreate(allocator, d->bytes, d->length) : NULL;
}
DX_FN(CFDataCreateCopy);

static struct cf_data *d_CFDataCreateMutableCopy(const void *allocator, CFIndex capacity,
                                                const struct cf_data *d) {
    if (!d || capacity < 0) return NULL;
    struct cf_data *copy = data_create(allocator, capacity > d->length ? capacity : d->length, 1);
    if (copy) {
        if (d->length) memcpy(copy->bytes, d->bytes, d->length);
        copy->length = d->length;
    }
    return copy;
}
DX_FN(CFDataCreateMutableCopy);

const uint8_t *d_CFDataGetBytePtr(const struct cf_data *d) { return d ? d->bytes : NULL; }
DX_FN(CFDataGetBytePtr);
CFIndex d_CFDataGetLength(const struct cf_data *d) { return d ? d->length : 0; }
DX_FN(CFDataGetLength);
static uint8_t *d_CFDataGetMutableBytePtr(struct cf_data *d) { return d && d->mutable ? d->bytes : NULL; }
DX_FN(CFDataGetMutableBytePtr);

static void d_CFDataGetBytes(const struct cf_data *d, CFRange range, uint8_t *buffer) {
    if (d && buffer && range.length && cf_range_valid(range, d->length))
        memcpy(buffer, d->bytes + range.location, range.length);
}
DX_FN(CFDataGetBytes);

static Boolean data_reserve(struct cf_data *d, CFIndex length) {
    void *bytes;
    if (!cf_grow(d->bytes, &d->capacity, length, 1, &bytes)) return 0;
    d->bytes = bytes;
    return 1;
}

static void d_CFDataSetLength(struct cf_data *d, CFIndex length) {
    if (!d || !d->mutable || length < 0 || !data_reserve(d, length)) return;
    if (length > d->length) memset(d->bytes + d->length, 0, length - d->length);
    d->length = length;
}
DX_FN(CFDataSetLength);

static void d_CFDataIncreaseLength(struct cf_data *d, CFIndex extra) {
    if (d && extra >= 0 && extra <= LONG_MAX - d->length)
        d_CFDataSetLength(d, d->length + extra);
}
DX_FN(CFDataIncreaseLength);

static void d_CFDataReplaceBytes(struct cf_data *d, CFRange range, const uint8_t *bytes, CFIndex length) {
    if (!d || !d->mutable || !cf_range_valid(range, d->length) || length < 0 ||
        length > LONG_MAX - (d->length - range.length) || (length && !bytes)) return;
    if (!length && !range.length) return;
    uint8_t *copy = NULL;
    if (length && (uintptr_t)bytes - (uintptr_t)d->bytes < d->capacity) {
        copy = malloc(length);
        if (!copy) return;
        memcpy(copy, bytes, length);
        bytes = copy;
    }
    CFIndex total = d->length - range.length + length;
    if (data_reserve(d, total)) {
        uint8_t *p = d->bytes + range.location;
        memmove(p + length, p + range.length, d->length - range.location - range.length);
        if (length) memcpy(p, bytes, length);
        d->length = total;
    }
    free(copy);
}
DX_FN(CFDataReplaceBytes);

static void d_CFDataAppendBytes(struct cf_data *d, const uint8_t *bytes, CFIndex length) {
    if (d) d_CFDataReplaceBytes(d, (CFRange){d->length, 0}, bytes, length);
}
DX_FN(CFDataAppendBytes);

static void d_CFDataDeleteBytes(struct cf_data *d, CFRange range) {
    d_CFDataReplaceBytes(d, range, NULL, 0);
}
DX_FN(CFDataDeleteBytes);
