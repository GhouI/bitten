#ifndef DX_CF_H
#define DX_CF_H

#include <limits.h>
#include <stdatomic.h>
#include <stdlib.h>

#include "dx.h"

typedef long CFIndex;
typedef unsigned long CFTypeID;
typedef unsigned long CFHashCode;
typedef unsigned char Boolean;
typedef uint32_t CFStringEncoding;
typedef struct { CFIndex location, length; } CFRange;

struct cf_string;
struct cf_data;
struct cf_array;
struct cf_dict;
struct cf_error;

enum cf_type {
    CF_ALLOCATOR = 1, CF_BOOLEAN, CF_NULL, CF_NUMBER, CF_DATA, CF_STRING,
    CF_ARRAY, CF_DICTIONARY, CF_SET, CF_DATE, CF_ERROR, CF_LOCALE, CF_UUID,
    CF_URL, CF_SEC_CERTIFICATE, CF_SEC_POLICY, CF_SEC_TRUST,
};

struct cf_ops {
    void (*destroy)(void *);
    Boolean (*equal)(const void *, const void *);
    CFHashCode (*hash)(const void *);
    struct cf_string *(*describe)(const void *);
};
struct cf_object {
    CFTypeID type;
    _Atomic CFIndex refs;
    const struct cf_ops *ops;
    const void *allocator;
};

#define CF_STATIC(type_id, methods) {type_id, ATOMIC_VAR_INIT(LONG_MAX), methods, NULL}
#define CF_TYPE_ID(name, type_id) \
    static CFTypeID d_##name##GetTypeID(void) { return type_id; } \
    DX_FN(name##GetTypeID)

extern const void *d_kCFAllocatorNull;
extern const void *d_kCFAllocatorSystemDefault;

static inline const void *cf_allocator(const void *allocator) {
    return allocator ? allocator : d_kCFAllocatorSystemDefault;
}

static inline void *cf_alloc(const void *allocator, size_t size, CFTypeID type,
                             const struct cf_ops *ops) {
    if (allocator == d_kCFAllocatorNull) return NULL;
    struct cf_object *object = calloc(1, size);
    if (!object) return NULL;
    object->type = type;
    atomic_init(&object->refs, 1);
    object->ops = ops;
    object->allocator = cf_allocator(allocator);
    return object;
}

static inline Boolean cf_range_valid(CFRange range, CFIndex count) {
    return range.location >= 0 && range.location <= count &&
           range.length >= 0 && range.length <= count - range.location;
}

static inline CFHashCode cf_hash_bytes(const void *bytes, size_t size) {
    const unsigned char *p = bytes;
    CFHashCode hash = 14695981039346656037UL;
    for (size_t i = 0; i < size; i++) hash = (hash ^ p[i]) * 1099511628211UL;
    return hash;
}

static inline Boolean cf_grow(void *old, size_t *capacity, size_t needed, size_t width, void **out) {
    *out = old;
    if (needed <= *capacity) return 1;
    if (needed > SIZE_MAX / width) return 0;
    size_t n = *capacity > SIZE_MAX / width / 2 ? needed : *capacity * 2;
    if (n < 8 && SIZE_MAX / width >= 8) n = 8;
    if (n < needed) n = needed;
    void *p = realloc(old, n * width);
    if (!p) return 0;
    *out = p;
    *capacity = n;
    return 1;
}

const void *d_CFRetain(const void *object);
void d_CFRelease(const void *object);
CFTypeID d_CFGetTypeID(const void *object);
Boolean d_CFEqual(const void *left, const void *right);
CFHashCode d_CFHash(const void *object);
struct cf_string *d_CFCopyDescription(const void *object);

enum {
    CF_MAC_ROMAN = 0, CF_UTF16 = 0x100, CF_LATIN1 = 0x201, CF_ASCII = 0x600,
    CF_UTF8 = 0x08000100, CF_UTF16BE = 0x10000100, CF_UTF16LE = 0x14000100,
};
struct cf_string *d_CFStringCreateWithCString(const void *, const char *, CFStringEncoding);
struct cf_string *d_CFStringCreateCopy(const void *, const struct cf_string *);
const char *d_CFStringGetCStringPtr(const struct cf_string *, CFStringEncoding);
struct cf_string *d___CFStringMakeConstantString(const char *);

struct cf_data *d_CFDataCreate(const void *, const uint8_t *, CFIndex);
const uint8_t *d_CFDataGetBytePtr(const struct cf_data *);
CFIndex d_CFDataGetLength(const struct cf_data *);

struct cf_callbacks {
    CFIndex version;
    const void *(*retain)(const void *, const void *);
    void (*release)(const void *, const void *);
    struct cf_string *(*describe)(const void *);
    Boolean (*equal)(const void *, const void *);
};
extern const struct cf_callbacks d_kCFTypeArrayCallBacks;
struct cf_array *d_CFArrayCreate(const void *, const void **, CFIndex, const struct cf_callbacks *);
struct cf_array *d_CFArrayCreateCopy(const void *, const struct cf_array *);
CFIndex d_CFArrayGetCount(const struct cf_array *);
const void *d_CFArrayGetValueAtIndex(const struct cf_array *, CFIndex);

struct cf_key_callbacks {
    struct cf_callbacks value;
    CFHashCode (*hash)(const void *);
};
extern const struct cf_key_callbacks d_kCFTypeDictionaryKeyCallBacks;
extern const struct cf_callbacks d_kCFTypeDictionaryValueCallBacks;
struct cf_dict *d_CFDictionaryCreate(const void *, const void **, const void **, CFIndex,
                                    const struct cf_key_callbacks *, const struct cf_callbacks *);
struct cf_dict *d_CFDictionaryCreateCopy(const void *, const struct cf_dict *);
const void *d_CFDictionaryGetValue(const struct cf_dict *, const void *);

extern const struct cf_string *d_kCFErrorDomainOSStatus;
extern const struct cf_string *d_kCFErrorLocalizedDescriptionKey;
struct cf_error *d_CFErrorCreate(const void *, const struct cf_string *, CFIndex,
                               const struct cf_dict *);

#endif
