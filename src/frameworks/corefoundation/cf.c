#include <math.h>
#include <string.h>

#include "cf.h"

/* Generic entry points accept three kinds of object: CF objects, constant
 * strings emitted by the compiler, and ordinary Objective-C objects (which
 * collections with the "CFType" callbacks may hold). */
void *dx_objc_retain(void *);
void dx_objc_release(void *);
unsigned long cf_objc_hash(const void *object);
Boolean cf_objc_equal(const void *left, const void *right);

const void *d_CFRetain(const void *object) {
    struct cf_object *o = (struct cf_object *)object;
    if (!o || cf_is_constant(o)) return object;
    if (!cf_is_cf(o)) return dx_objc_retain(o);
    if (atomic_load_explicit(&o->refs, memory_order_relaxed) != LONG_MAX)
        atomic_fetch_add_explicit(&o->refs, 1, memory_order_relaxed);
    return object;
}
DX_FN(CFRetain);

void d_CFRelease(const void *object) {
    struct cf_object *o = (struct cf_object *)object;
    if (!o || cf_is_constant(o)) return;
    if (!cf_is_cf(o)) {
        dx_objc_release(o);
        return;
    }
    if (atomic_load_explicit(&o->refs, memory_order_relaxed) == LONG_MAX) return;
    if (atomic_fetch_sub_explicit(&o->refs, 1, memory_order_acq_rel) == 1) {
        if (o->ops && o->ops->destroy) o->ops->destroy(o);
        free(o);
    }
}
DX_FN(CFRelease);

CFTypeID d_CFGetTypeID(const void *object) {
    const struct cf_object *o = cf_resolve(object);
    if (!o) return 0;
    return cf_is_cf(o) ? o->type : 1; /* foreign Objective-C objects report the generic type */
}
DX_FN(CFGetTypeID);

static CFIndex d_CFGetRetainCount(const void *object) {
    const struct cf_object *o = object;
    if (!o) return 0;
    if (cf_is_constant(o) || !cf_is_cf(o)) return LONG_MAX;
    return atomic_load_explicit(&o->refs, memory_order_relaxed);
}
DX_FN(CFGetRetainCount);

Boolean d_CFEqual(const void *left, const void *right) {
    if (left == right) return 1;
    if (!left || !right) return 0;
    left = cf_resolve(left);
    right = cf_resolve(right);
    if (left == right) return 1;
    if (!cf_is_cf(left) || !cf_is_cf(right)) return cf_objc_equal(left, right);
    const struct cf_object *o = left;
    return o->type == ((const struct cf_object *)right)->type && o->ops && o->ops->equal &&
           o->ops->equal(left, right);
}
DX_FN(CFEqual);

CFHashCode d_CFHash(const void *object) {
    const struct cf_object *o = cf_resolve(object);
    if (o && !cf_is_cf(o)) return cf_objc_hash(o);
    return o && o->ops && o->ops->hash ? o->ops->hash(o) : (uintptr_t)o;
}
DX_FN(CFHash);

struct cf_string *d_CFCopyDescription(const void *object) {
    const struct cf_object *o = cf_resolve(object);
    if (o && !cf_is_cf(o)) return d_CFStringCreateWithCString(NULL, "<Objective-C object>", CF_UTF8);
    if (o && o->ops && o->ops->describe) return o->ops->describe(o);
    static const char *const names[] = {
        [CF_ALLOCATOR] = "CFAllocator", [CF_BOOLEAN] = "CFBoolean", [CF_NULL] = "CFNull",
        [CF_NUMBER] = "CFNumber", [CF_DATA] = "CFData", [CF_STRING] = "CFString",
        [CF_ARRAY] = "CFArray", [CF_DICTIONARY] = "CFDictionary", [CF_SET] = "CFSet",
        [CF_DATE] = "CFDate", [CF_ERROR] = "CFError", [CF_LOCALE] = "CFLocale",
        [CF_UUID] = "CFUUID", [CF_URL] = "CFURL", [CF_SEC_CERTIFICATE] = "SecCertificate",
        [CF_SEC_POLICY] = "SecPolicy", [CF_SEC_TRUST] = "SecTrust",
        [CF_CG_COLORSPACE] = "CGColorSpace", [CF_CG_COLOR] = "CGColor", [CF_CG_PATH] = "CGPath",
        [CF_CG_CONTEXT] = "CGContext", [CF_CG_IMAGE] = "CGImage", [CF_CG_GRADIENT] = "CGGradient",
        [CF_CG_PROVIDER] = "CGDataProvider", [CF_CG_EVENT] = "CGEvent",
        [CF_ATTRIBUTED_STRING] = "CFAttributedString", [CF_CT_FONT] = "CTFont",
        [CF_CT_DESCRIPTOR] = "CTFontDescriptor", [CF_CT_LINE] = "CTLine", [CF_CT_RUN] = "CTRun",
        [CF_CT_COLLECTION] = "CTFontCollection",
    };
    char buf[64];
    if (!o) return d_CFStringCreateWithCString(NULL, "(null)", CF_UTF8);
    const char *name = o->type < sizeof names / sizeof *names ? names[o->type] : NULL;
    snprintf(buf, sizeof buf, "<%s %p>", name ? name : "CFType", object);
    return d_CFStringCreateWithCString(NULL, buf, CF_UTF8);
}
DX_FN(CFCopyDescription);

static void d_CFShow(const void *object) {
    struct cf_string *desc = d_CFCopyDescription(object);
    const char *s = d_CFStringGetCStringPtr(desc, CF_UTF8);
    if (s) fprintf(stderr, "%s\n", s);
    d_CFRelease(desc);
}
DX_FN(CFShow);

static struct cf_object system_allocator = CF_STATIC(CF_ALLOCATOR, NULL);
static struct cf_object malloc_allocator = CF_STATIC(CF_ALLOCATOR, NULL);
static struct cf_object null_allocator = CF_STATIC(CF_ALLOCATOR, NULL);
static const void *d_kCFAllocatorDefault;
const void *d_kCFAllocatorSystemDefault = &system_allocator;
static const void *d_kCFAllocatorMalloc = &malloc_allocator;
const void *d_kCFAllocatorNull = &null_allocator;
DX_EXPORT("_kCFAllocatorDefault", &d_kCFAllocatorDefault);
DX_EXPORT("_kCFAllocatorSystemDefault", &d_kCFAllocatorSystemDefault);
DX_EXPORT("_kCFAllocatorMalloc", &d_kCFAllocatorMalloc);
DX_EXPORT("_kCFAllocatorNull", &d_kCFAllocatorNull);
CF_TYPE_ID(CFAllocator, CF_ALLOCATOR);

static void *d_CFAllocatorAllocate(const void *allocator, CFIndex size, unsigned long hint) {
    return allocator != d_kCFAllocatorNull && size > 0 ? malloc(size) : NULL;
}
DX_FN(CFAllocatorAllocate);

static void d_CFAllocatorDeallocate(const void *allocator, void *ptr) {
    if (allocator != d_kCFAllocatorNull) free(ptr);
}
DX_FN(CFAllocatorDeallocate);

static const void *d_CFAllocatorGetDefault(void) { return d_kCFAllocatorSystemDefault; }
DX_FN(CFAllocatorGetDefault);

static const void *d_CFGetAllocator(const struct cf_object *object) {
    return cf_allocator(object ? object->allocator : NULL);
}
DX_FN(CFGetAllocator);

struct cf_boolean {
    struct cf_object base;
    Boolean value;
};
static struct cf_string *boolean_desc(const void *object) {
    const struct cf_boolean *b = object;
    return d___CFStringMakeConstantString(b->value ? "true" : "false");
}
static const struct cf_ops boolean_ops = {.describe = boolean_desc};
static struct cf_boolean boolean_true = {CF_STATIC(CF_BOOLEAN, &boolean_ops), 1};
static struct cf_boolean boolean_false = {CF_STATIC(CF_BOOLEAN, &boolean_ops), 0};
static struct cf_object null_value = CF_STATIC(CF_NULL, NULL);
static const void *d_kCFBooleanTrue = &boolean_true;
static const void *d_kCFBooleanFalse = &boolean_false;
static const void *d_kCFNull = &null_value;
DX_EXPORT("_kCFBooleanTrue", &d_kCFBooleanTrue);
DX_EXPORT("_kCFBooleanFalse", &d_kCFBooleanFalse);
DX_EXPORT("_kCFNull", &d_kCFNull);
/* The objects themselves, which Swift's literal bridging references. */
DX_EXPORT("___kCFBooleanTrue", &boolean_true);
DX_EXPORT("___kCFBooleanFalse", &boolean_false);
CF_TYPE_ID(CFBoolean, CF_BOOLEAN);
CF_TYPE_ID(CFNull, CF_NULL);

static Boolean d_CFBooleanGetValue(const struct cf_boolean *b) { return b && b->value; }
DX_FN(CFBooleanGetValue);

struct cf_number {
    struct cf_object base;
    CFIndex type;
    long double value;
};

static CFIndex number_type(CFIndex type) {
    switch (type) {
    case 7: return 1;              /* char */
    case 8: return 2;              /* short */
    case 9: return 3;              /* int */
    case 10: case 11: case 14: case 15: return 4; /* long, long long, CFIndex, NSInteger */
    case 12: return 5;             /* float */
    case 13: case 16: return 6;    /* double, CGFloat */
    default: return type;
    }
}

static Boolean number_equal(const void *left, const void *right) {
    const struct cf_number *a = left, *b = right;
    return a->value == b->value || (isnan(a->value) && isnan(b->value));
}

static CFHashCode number_hash(const void *object) {
    const struct cf_number *n = object;
    double value = isnan(n->value) ? NAN : n->value == 0 ? 0 : (double)n->value;
    return cf_hash_bytes(&value, sizeof value);
}

static struct cf_string *number_desc(const void *object) {
    const struct cf_number *n = object;
    char buf[64];
    snprintf(buf, sizeof buf, "%.21Lg", n->value);
    return d_CFStringCreateWithCString(NULL, buf, CF_UTF8);
}
static const struct cf_ops number_ops = {.equal = number_equal, .hash = number_hash, .describe = number_desc};
CF_TYPE_ID(CFNumber, CF_NUMBER);

struct cf_number *d_CFNumberCreate(const void *allocator, CFIndex type, const void *value) {
    type = number_type(type);
    if (!value || type < 1 || type > 6) return NULL;
    long double num;
#define READ_NUMBER(code, c_type) \
    case code: { c_type x; memcpy(&x, value, sizeof x); num = x; break; }
    switch (type) {
    READ_NUMBER(1, int8_t)
    READ_NUMBER(2, int16_t)
    READ_NUMBER(3, int32_t)
    READ_NUMBER(4, int64_t)
    READ_NUMBER(5, float)
    READ_NUMBER(6, double)
    default: return NULL;
    }
#undef READ_NUMBER
    struct cf_number *n = cf_alloc(allocator, sizeof *n, CF_NUMBER, &number_ops);
    if (n) {
        n->type = type;
        n->value = num;
    }
    return n;
}
DX_FN(CFNumberCreate);

Boolean d_CFNumberGetValue(const struct cf_number *n, CFIndex type, void *out) {
    n = CF_STR(n);
    if (!n || !out) return 0;
    long double value = n->value;
#define WRITE_INT(code, c_type, min, max) \
    case code: { \
        c_type x = isnan(value) ? 0 : value < min ? min : value > max ? max : (c_type)value; \
        memcpy(out, &x, sizeof x); \
        return (long double)x == value; \
    }
#define WRITE_FLOAT(code, c_type) \
    case code: { \
        c_type x = (c_type)value; \
        memcpy(out, &x, sizeof x); \
        return (long double)x == value || isnan(value); \
    }
    switch (number_type(type)) {
    WRITE_INT(1, int8_t, INT8_MIN, INT8_MAX)
    WRITE_INT(2, int16_t, INT16_MIN, INT16_MAX)
    WRITE_INT(3, int32_t, INT32_MIN, INT32_MAX)
    WRITE_INT(4, int64_t, INT64_MIN, INT64_MAX)
    WRITE_FLOAT(5, float)
    WRITE_FLOAT(6, double)
    default: return 0;
    }
#undef WRITE_INT
#undef WRITE_FLOAT
}
DX_FN(CFNumberGetValue);

static CFIndex d_CFNumberGetType(const struct cf_number *n) { n = CF_STR(n); return n ? n->type : 0; }
DX_FN(CFNumberGetType);

static Boolean d_CFNumberIsFloatType(const struct cf_number *n) { n = CF_STR(n); return n && n->type >= 5; }
DX_FN(CFNumberIsFloatType);

static CFIndex d_CFNumberGetByteSize(const struct cf_number *n) {
    n = CF_STR(n);
    static const CFIndex sizes[] = {0, 1, 2, 4, 8, 4, 8};
    return n ? sizes[n->type] : 0;
}
DX_FN(CFNumberGetByteSize);

static CFIndex d_CFNumberCompare(const struct cf_number *a, const struct cf_number *b, void *context) {
    a = CF_STR(a);
    b = CF_STR(b);
    if (isnan(a->value)) return isnan(b->value) ? 0 : signbit(b->value) ? 1 : -1;
    if (isnan(b->value)) return signbit(a->value) ? -1 : 1;
    return (a->value > b->value) - (a->value < b->value);
}
DX_FN(CFNumberCompare);
