#define _GNU_SOURCE
#include <errno.h>
#include <iconv.h>
#include <locale.h>
#include <pthread.h>
#include <string.h>
#include <wctype.h>

#include "cf.h"

struct cf_string {
    struct cf_object base;
    char *bytes;
    size_t size;
    CFIndex length;
    CFIndex max_length;
    Boolean mutable;
};

static uint32_t utf8_next(const char **cursor, const char *end) {
    const unsigned char *p = (const unsigned char *)*cursor;
    uint32_t first = *p++, value, minimum;
    int extra;
    if (first < 0x80) {
        *cursor += 1;
        return first;
    }
    if (first < 0xc2 || first > 0xf4) return UINT32_MAX;
    if (first < 0xe0) {
        value = first & 0x1f; minimum = 0x80; extra = 1;
    } else if (first < 0xf0) {
        value = first & 0x0f; minimum = 0x800; extra = 2;
    } else {
        value = first & 7; minimum = 0x10000; extra = 3;
    }
    if ((const unsigned char *)end - p < extra) return UINT32_MAX;
    while (extra--) {
        if ((*p & 0xc0) != 0x80) return UINT32_MAX;
        value = (value << 6) | (*p++ & 0x3f);
    }
    if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff))
        return UINT32_MAX;
    *cursor = (const char *)p;
    return value;
}

static void string_destroy(void *object) {
    struct cf_string *s = object;
    free(s->bytes);
}
static Boolean string_equal(const void *left, const void *right) {
    const struct cf_string *a = left, *b = right;
    return a->size == b->size && !memcmp(a->bytes, b->bytes, a->size);
}
static CFHashCode string_hash(const void *object) {
    const struct cf_string *s = object;
    return cf_hash_bytes(s->bytes, s->size);
}
static struct cf_string *string_describe(const void *object) {
    return d_CFStringCreateCopy(NULL, object);
}
static const struct cf_ops string_ops = {
    .destroy = string_destroy, .equal = string_equal, .hash = string_hash, .describe = string_describe,
};
CF_TYPE_ID(CFString, CF_STRING);

static struct cf_string *string_new(const void *allocator, const char *bytes, size_t size) {
    if (size > LONG_MAX) return NULL;
    const char *p = bytes, *end = bytes + size;
    CFIndex length = 0;
    while (p < end) {
        uint32_t cp = utf8_next(&p, end);
        if (cp == UINT32_MAX) return NULL;
        length += cp >= 0x10000 ? 2 : 1;
    }
    struct cf_string *s = cf_alloc(allocator, sizeof *s, CF_STRING, &string_ops);
    if (!s) return NULL;
    s->bytes = malloc(size + 1);
    if (!s->bytes) { d_CFRelease(s); return NULL; }
    memcpy(s->bytes, bytes, size);
    s->bytes[size] = 0;
    s->size = size;
    s->length = length;
    return s;
}

static const char *encoding_name(CFStringEncoding encoding) {
    switch (encoding) {
    case CF_MAC_ROMAN: return "MACINTOSH";
    case CF_LATIN1: return "ISO-8859-1";
    case CF_ASCII: return "ASCII";
    case CF_UTF8: return "UTF-8";
    case CF_UTF16: case CF_UTF16LE: return "UTF-16LE";
    case CF_UTF16BE: return "UTF-16BE";
    default: return NULL;
    }
}

static struct cf_string *d_CFStringCreateWithBytes(const void *allocator, const uint8_t *bytes,
                                                   CFIndex length, CFStringEncoding encoding,
                                                   Boolean external) {
    const char *from = encoding_name(encoding);
    if (!from || length < 0 || (length && !bytes)) return NULL;
    if (!length) return string_new(allocator, "", 0);
    if (encoding == CF_UTF8) {
        if (external && length >= 3 && !memcmp(bytes, "\xef\xbb\xbf", 3)) {
            bytes += 3;
            length -= 3;
        }
        return string_new(allocator, (const char *)bytes, length);
    }
    if (encoding == CF_UTF16 && external) {
        if (length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
            bytes += 2;
            length -= 2;
        } else {
            from = "UTF-16BE";
            if (length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
                bytes += 2;
                length -= 2;
            }
        }
    }
    if ((size_t)length > SIZE_MAX / 4) return NULL;
    size_t capacity = (size_t)length * 4;
    char *converted = malloc(capacity ? capacity : 1);
    if (!converted) return NULL;
    iconv_t cd = iconv_open("UTF-8", from);
    struct cf_string *s = NULL;
    if (cd != (iconv_t)-1) {
        char *in = (char *)bytes, *out = converted;
        size_t left = length, remaining = capacity;
        if (iconv(cd, &in, &left, &out, &remaining) != (size_t)-1)
            s = string_new(allocator, converted, capacity - remaining);
        iconv_close(cd);
    }
    free(converted);
    return s;
}
DX_FN(CFStringCreateWithBytes);

struct cf_string *d_CFStringCreateWithCString(const void *allocator, const char *bytes,
                                              CFStringEncoding encoding) {
    return bytes ? d_CFStringCreateWithBytes(allocator, (const uint8_t *)bytes,
                                             strlen(bytes), encoding, 0) : NULL;
}
DX_FN(CFStringCreateWithCString);

struct cf_string *d_CFStringCreateCopy(const void *allocator, const struct cf_string *s) {
    s = CF_STR(s);
    if (!s || allocator == d_kCFAllocatorNull) return NULL;
    if (!s->mutable && s->base.allocator == cf_allocator(allocator)) {
        d_CFRetain(s);
        return (struct cf_string *)s;
    }
    return string_new(allocator, s->bytes, s->size);
}
DX_FN(CFStringCreateCopy);

static CFIndex d_CFStringGetLength(const struct cf_string *s) {
    s = CF_STR(s);
    return s ? s->length : 0;
}
DX_FN(CFStringGetLength);

const char *d_CFStringGetCStringPtr(const struct cf_string *s, CFStringEncoding encoding) {
    s = CF_STR(s);
    if (!s || memchr(s->bytes, 0, s->size)) return NULL;
    if (encoding == CF_UTF8) return s->bytes;
    if ((encoding == CF_ASCII || encoding == CF_MAC_ROMAN || encoding == CF_LATIN1) &&
        s->size == (size_t)s->length) return s->bytes;
    return NULL;
}
DX_FN(CFStringGetCStringPtr);

static CFIndex d_CFStringGetMaximumSizeForEncoding(CFIndex length, CFStringEncoding encoding) {
    if (!encoding_name(encoding) || length < 0) return -1;
    CFIndex width = encoding == CF_UTF8 ? 3 :
        (encoding == CF_UTF16 || encoding == CF_UTF16LE || encoding == CF_UTF16BE) ? 2 : 1;
    return length <= LONG_MAX / width ? length * width : -1;
}
DX_FN(CFStringGetMaximumSizeForEncoding);

static Boolean encode(const struct cf_string *s, CFStringEncoding encoding, Boolean external,
                      uint8_t loss, char *out, size_t *size) {
    const char *to = encoding_name(encoding);
    if (!s || !to) return 0;
    size_t remaining = *size;
    if (encoding == CF_UTF16 && external) {
        if (remaining < 2) return 0;
        *out++ = (char)0xff;
        *out++ = (char)0xfe;
        remaining -= 2;
    }
    if (encoding == CF_UTF8) {
        if (remaining < s->size) return 0;
        memcpy(out, s->bytes, s->size);
        *size = s->size;
        return 1;
    }
    iconv_t cd = iconv_open(to, "UTF-8");
    if (cd == (iconv_t)-1) return 0;
    char *in = s->bytes;
    size_t left = s->size;
    Boolean ok = 1;
    while (left && iconv(cd, &in, &left, &out, &remaining) == (size_t)-1) {
        if (errno != EILSEQ || !loss || !remaining) { ok = 0; break; }
        const char *next = in;
        utf8_next(&next, in + left);
        left -= next - in;
        in = (char *)next;
        *out++ = loss;
        remaining--;
    }
    iconv_close(cd);
    *size -= remaining;
    return ok;
}

static Boolean d_CFStringGetCString(const struct cf_string *s, char *buffer, CFIndex capacity,
                                    CFStringEncoding encoding) {
    s = CF_STR(s);
    size_t terminator = encoding == CF_UTF16 || encoding == CF_UTF16BE || encoding == CF_UTF16LE ? 2 : 1;
    if (!buffer || capacity < (CFIndex)terminator) return 0;
    size_t size = capacity - terminator;
    if (!encode(s, encoding, 0, 0, buffer, &size)) { buffer[0] = 0; return 0; }
    memset(buffer + size, 0, terminator);
    return 1;
}
DX_FN(CFStringGetCString);

static struct cf_data *d_CFStringCreateExternalRepresentation(const void *allocator,
                                    const struct cf_string *s, CFStringEncoding encoding, uint8_t loss) {
    s = CF_STR(s);
    if (!s) return NULL;
    CFIndex max = d_CFStringGetMaximumSizeForEncoding(s->length, encoding);
    if (max < 0 || max > LONG_MAX - 2) return NULL;
    size_t size = encoding == CF_UTF8 ? s->size : (size_t)max + 2;
    char *bytes = malloc(size ? size : 1);
    if (!bytes) return NULL;
    struct cf_data *d = NULL;
    if (encode(s, encoding, 1, loss, bytes, &size))
        d = d_CFDataCreate(allocator, (const uint8_t *)bytes, size);
    free(bytes);
    return d;
}
DX_FN(CFStringCreateExternalRepresentation);

static struct cf_string *d_CFStringCreateFromExternalRepresentation(const void *allocator,
                                          const struct cf_data *d, CFStringEncoding encoding) {
    return d && d_CFGetTypeID(d) == CF_DATA ?
        d_CFStringCreateWithBytes(allocator, d_CFDataGetBytePtr(d), d_CFDataGetLength(d), encoding, 1) : NULL;
}
DX_FN(CFStringCreateFromExternalRepresentation);

static void d_CFStringGetCharacters(const struct cf_string *s, CFRange range, uint16_t *buffer) {
    s = CF_STR(s);
    if (!s || !buffer || !cf_range_valid(range, s->length) || !range.length) return;
    const char *p = s->bytes, *end = p + s->size;
    CFIndex index = 0, limit = range.location + range.length;
    while (index < limit) {
        uint32_t cp = utf8_next(&p, end);
        if (cp >= 0x10000) {
            cp -= 0x10000;
            if (index >= range.location) *buffer++ = 0xd800 + (cp >> 10);
            if (++index == limit) break;
            cp = 0xdc00 + (cp & 0x3ff);
        }
        if (index >= range.location) *buffer++ = cp;
        index++;
    }
}
DX_FN(CFStringGetCharacters);

static uint16_t d_CFStringGetCharacterAtIndex(const struct cf_string *s, CFIndex index) {
    s = CF_STR(s);
    uint16_t unit = 0;
    d_CFStringGetCharacters(s, (CFRange){index, 1}, &unit);
    return unit;
}
DX_FN(CFStringGetCharacterAtIndex);

static pthread_once_t case_once = PTHREAD_ONCE_INIT;
static locale_t unicode_locale;
static void init_case_locale(void) { unicode_locale = newlocale(LC_CTYPE_MASK, "C.UTF-8", NULL); }

static uint32_t fold_case(uint32_t cp) {
    if (unicode_locale) return towlower_l(cp, unicode_locale);
    return cp >= 'A' && cp <= 'Z' ? cp + 'a' - 'A' : cp;
}

static CFIndex d_CFStringCompare(const struct cf_string *a, const struct cf_string *b, unsigned long options) {
    a = CF_STR(a);
    b = CF_STR(b);
    if (a == b) return 0;
    if (!a || !b) return a ? 1 : -1;
    Boolean insensitive = options & 1;
    if (insensitive) pthread_once(&case_once, init_case_locale);
    const char *p = a->bytes, *q = b->bytes;
    const char *pe = p + a->size, *qe = q + b->size;
    while (p < pe && q < qe) {
        if ((options & 64) && *p >= '0' && *p <= '9' && *q >= '0' && *q <= '9') {
            const char *pa = p, *qa = q;
            while (pa < pe && *pa == '0') pa++;
            while (qa < qe && *qa == '0') qa++;
            p = pa;
            q = qa;
            while (p < pe && *p >= '0' && *p <= '9') p++;
            while (q < qe && *q >= '0' && *q <= '9') q++;
            if (p - pa != q - qa) return p - pa < q - qa ? -1 : 1;
            int order = memcmp(pa, qa, p - pa);
            if (order) return order < 0 ? -1 : 1;
            continue;
        }
        uint32_t x = utf8_next(&p, pe), y = utf8_next(&q, qe);
        if (insensitive) { x = fold_case(x); y = fold_case(y); }
        if (x == y) continue;
        /* Order supplementary characters by their leading UTF-16 code unit. */
        if ((x >= 0x10000) != (y >= 0x10000)) {
            uint32_t xu = x >= 0x10000 ? 0xd800 + ((x - 0x10000) >> 10) : x;
            uint32_t yu = y >= 0x10000 ? 0xd800 + ((y - 0x10000) >> 10) : y;
            return xu < yu ? -1 : 1;
        }
        return x < y ? -1 : 1;
    }
    return (p < pe) - (q < qe);
}
DX_FN(CFStringCompare);

static Boolean d_CFStringHasPrefix(const struct cf_string *s, const struct cf_string *prefix) {
    s = CF_STR(s);
    prefix = CF_STR(prefix);
    return s && prefix && prefix->size <= s->size && !memcmp(s->bytes, prefix->bytes, prefix->size);
}
DX_FN(CFStringHasPrefix);

static Boolean d_CFStringHasSuffix(const struct cf_string *s, const struct cf_string *suffix) {
    s = CF_STR(s);
    suffix = CF_STR(suffix);
    return s && suffix && suffix->size <= s->size &&
           !memcmp(s->bytes + s->size - suffix->size, suffix->bytes, suffix->size);
}
DX_FN(CFStringHasSuffix);

static struct cf_string *d_CFStringCreateMutable(const void *allocator, CFIndex max) {
    if (max < 0) return NULL;
    struct cf_string *s = string_new(allocator, "", 0);
    if (s) { s->mutable = 1; s->max_length = max; }
    return s;
}
DX_FN(CFStringCreateMutable);

static struct cf_string *d_CFStringCreateMutableCopy(const void *allocator, CFIndex max,
                                                      const struct cf_string *original) {
    original = CF_STR(original);
    if (!original || max < 0 || (max && max < original->length)) return NULL;
    struct cf_string *s = string_new(allocator, original->bytes, original->size);
    if (s) { s->mutable = 1; s->max_length = max; }
    return s;
}
DX_FN(CFStringCreateMutableCopy);

static size_t byte_offset(const struct cf_string *s, CFIndex index) {
    const char *p = s->bytes, *end = p + s->size;
    while (index > 0) {
        index -= utf8_next(&p, end) >= 0x10000 ? 2 : 1;
        if (index < 0) return SIZE_MAX;
    }
    return p - s->bytes;
}

static void d_CFStringReplace(struct cf_string *s, CFRange range, const struct cf_string *replacement) {
    s = CF_STR(s);
    replacement = CF_STR(replacement);
    if (!s || !s->mutable || !replacement || !cf_range_valid(range, s->length)) return;
    if (replacement->length > LONG_MAX - (s->length - range.length)) return;
    CFIndex length = s->length - range.length + replacement->length;
    if (s->max_length && length > s->max_length) return;
    size_t start = byte_offset(s, range.location), end = byte_offset(s, range.location + range.length);
    if (start == SIZE_MAX || end == SIZE_MAX ||
        replacement->size > (size_t)LONG_MAX - (s->size - (end - start))) return;
    size_t size = s->size - (end - start) + replacement->size;
    char *bytes = malloc(size + 1);
    if (!bytes) return;
    memcpy(bytes, s->bytes, start);
    memcpy(bytes + start, replacement->bytes, replacement->size);
    memcpy(bytes + start + replacement->size, s->bytes + end, s->size - end + 1);
    free(s->bytes);
    s->bytes = bytes;
    s->size = size;
    s->length = length;
}
DX_FN(CFStringReplace);

static void d_CFStringAppend(struct cf_string *s, const struct cf_string *suffix) {
    s = CF_STR(s);
    suffix = CF_STR(suffix);
    if (s) d_CFStringReplace(s, (CFRange){s->length, 0}, suffix);
}
DX_FN(CFStringAppend);

static void d_CFStringAppendCString(struct cf_string *s, const char *suffix, CFStringEncoding encoding) {
    s = CF_STR(s);
    struct cf_string *addition = d_CFStringCreateWithCString(NULL, suffix, encoding);
    d_CFStringAppend(s, addition);
    d_CFRelease(addition);
}
DX_FN(CFStringAppendCString);

static void d_CFStringDelete(struct cf_string *s, CFRange range) {
    s = CF_STR(s);
    d_CFStringReplace(s, range, d___CFStringMakeConstantString(""));
}
DX_FN(CFStringDelete);

static void d_CFStringSetString(struct cf_string *s, const struct cf_string *replacement) {
    s = CF_STR(s);
    replacement = CF_STR(replacement);
    if (s) d_CFStringReplace(s, (CFRange){0, s->length}, replacement);
}
DX_FN(CFStringSetString);

struct constant_string {
    struct cf_string *string;
    struct constant_string *next;
};
static struct constant_string *constant_strings;
static pthread_mutex_t constant_lock = PTHREAD_MUTEX_INITIALIZER;

struct cf_string *d___CFStringMakeConstantString(const char *bytes) {
    if (!bytes) return NULL;
    pthread_mutex_lock(&constant_lock);
    struct constant_string *entry = constant_strings;
    while (entry && strcmp(entry->string->bytes, bytes)) entry = entry->next;
    if (!entry) {
        entry = malloc(sizeof *entry);
        if (entry) {
            entry->string = string_new(NULL, bytes, strlen(bytes));
            if (entry->string) {
                atomic_store_explicit(&entry->string->base.refs, LONG_MAX, memory_order_relaxed);
                entry->next = constant_strings;
                constant_strings = entry;
            } else {
                free(entry);
                entry = NULL;
            }
        }
    }
    pthread_mutex_unlock(&constant_lock);
    return entry ? entry->string : NULL;
}
DX_FN(__CFStringMakeConstantString);

/* A constant string emitted by the compiler (@"..." or CFSTR("...")):
 * { isa, flags, bytes, length }. Build its CF counterpart once; it lives
 * forever, like the constant. */
struct cf_string *cf_string_from_constant(const void *constant) {
    const struct {
        void *isa;
        uint64_t flags;
        const char *bytes;
        long length;
    } *k = constant;
    struct cf_string *s;
    if ((k->flags & 0xff) == 0xd0) /* UTF-16 contents */
        s = d_CFStringCreateWithBytes(NULL, (const uint8_t *)k->bytes, k->length * 2, CF_UTF16LE, 0);
    else {
        s = string_new(NULL, k->bytes, (size_t)k->length);
        if (!s) s = d_CFStringCreateWithBytes(NULL, (const uint8_t *)k->bytes, k->length, CF_LATIN1, 0);
    }
    if (!s) s = string_new(NULL, "", 0);
    atomic_store(&s->base.refs, LONG_MAX);
    return s;
}
