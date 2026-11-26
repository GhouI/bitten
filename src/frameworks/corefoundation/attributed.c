/* CFAttributedString (and its mutable form): a string with an attribute
 * dictionary for each UTF-16 unit. Units that share attributes share one
 * retained dictionary, so a run is a stretch of equal pointers. Written
 * from Apple's public documentation. */
#include <stdbool.h>
#include <string.h>

#include "cf.h"

#define CALL(ret, name, args) ((ret(*) args)dx_registry_lookup("_" #name))
#define UTF16LE 0x14000100

typedef const void *Ref;

struct cf_attributed {
    struct cf_object base;
    Ref string;                 /* CFString */
    CFIndex length;
    Ref *attrs;                 /* one retained CFDictionary per unit */
    bool mutable;
};

static void attributed_destroy(void *o) {
    struct cf_attributed *a = o;
    for (CFIndex i = 0; i < a->length; i++) d_CFRelease(a->attrs[i]);
    free(a->attrs);
    d_CFRelease(a->string);
}

static Boolean attributed_equal(const void *x, const void *y) {
    const struct cf_attributed *a = x, *b = y;
    if (a->length != b->length || !d_CFEqual(a->string, b->string)) return 0;
    for (CFIndex i = 0; i < a->length; i++)
        if (a->attrs[i] != b->attrs[i] && !d_CFEqual(a->attrs[i], b->attrs[i])) return 0;
    return 1;
}

static CFHashCode attributed_hash(const void *o) { return d_CFHash(((const struct cf_attributed *)o)->string); }
static const struct cf_ops attributed_ops = {attributed_destroy, attributed_equal, attributed_hash, NULL};

static Ref empty_dict(void) {
    return CALL(Ref, CFDictionaryCreate, (Ref, const void **, const void **, CFIndex, const void *, const void *))(
        NULL, NULL, NULL, 0, dx_registry_lookup("_kCFTypeDictionaryKeyCallBacks"),
        dx_registry_lookup("_kCFTypeDictionaryValueCallBacks"));
}

static CFIndex string_length(Ref s) { return s ? CALL(CFIndex, CFStringGetLength, (Ref))(s) : 0; }

static struct cf_attributed *make(Ref string, Ref attributes, bool mutable) {
    struct cf_attributed *a = cf_alloc(NULL, sizeof *a, CF_ATTRIBUTED_STRING, &attributed_ops);
    if (!a) return NULL;
    a->string = string ? d_CFRetain(string) : d_CFStringCreateWithCString(NULL, "", 0x08000100);
    a->length = string_length(a->string);
    a->mutable = mutable;
    a->attrs = calloc((size_t)(a->length ? a->length : 1), sizeof *a->attrs);
    Ref dict = attributes ? CALL(Ref, CFDictionaryCreateCopy, (Ref, Ref))(NULL, attributes) : empty_dict();
    for (CFIndex i = 0; i < a->length; i++) a->attrs[i] = d_CFRetain(dict);
    d_CFRelease(dict);
    return a;
}

static struct cf_attributed *d_CFAttributedStringCreate(Ref alloc, Ref string, Ref attributes) {
    return make(string, attributes, false);
}
DX_FN(CFAttributedStringCreate);

static struct cf_attributed *copy_of(const struct cf_attributed *src, bool mutable) {
    if (!src) return NULL;
    struct cf_attributed *a = make(src->string, NULL, mutable);
    if (!a) return NULL;
    for (CFIndex i = 0; i < a->length; i++) {
        d_CFRelease(a->attrs[i]);
        a->attrs[i] = d_CFRetain(src->attrs[i]);
    }
    return a;
}

static struct cf_attributed *d_CFAttributedStringCreateCopy(Ref alloc, const struct cf_attributed *s) { return copy_of(s, false); }
DX_FN(CFAttributedStringCreateCopy);
static struct cf_attributed *d_CFAttributedStringCreateMutable(Ref alloc, CFIndex max) { return make(NULL, NULL, true); }
DX_FN(CFAttributedStringCreateMutable);
static struct cf_attributed *d_CFAttributedStringCreateMutableCopy(Ref alloc, CFIndex max, const struct cf_attributed *s) {
    return copy_of(s, true);
}
DX_FN(CFAttributedStringCreateMutableCopy);

static Ref d_CFAttributedStringGetString(const struct cf_attributed *a) { return a ? a->string : NULL; }
DX_FN(CFAttributedStringGetString);
static CFIndex d_CFAttributedStringGetLength(const struct cf_attributed *a) { return a ? a->length : 0; }
DX_FN(CFAttributedStringGetLength);

static CFRange run_at(const struct cf_attributed *a, CFIndex loc) {
    CFIndex lo = loc, hi = loc + 1;
    while (lo > 0 && a->attrs[lo - 1] == a->attrs[loc]) lo--;
    while (hi < a->length && a->attrs[hi] == a->attrs[loc]) hi++;
    return (CFRange){lo, hi - lo};
}

static Ref d_CFAttributedStringGetAttributes(const struct cf_attributed *a, CFIndex loc, CFRange *effective) {
    if (!a || loc < 0 || loc >= a->length) return NULL;
    if (effective) *effective = run_at(a, loc);
    return a->attrs[loc];
}
DX_FN(CFAttributedStringGetAttributes);

static Ref d_CFAttributedStringGetAttribute(const struct cf_attributed *a, CFIndex loc, Ref name, CFRange *effective) {
    if (!a || loc < 0 || loc >= a->length) return NULL;
    Ref v = d_CFDictionaryGetValue(a->attrs[loc], name);
    if (effective) {
        CFIndex lo = loc, hi = loc + 1;
        while (lo > 0 && d_CFDictionaryGetValue(a->attrs[lo - 1], name) == v) lo--;
        while (hi < a->length && d_CFDictionaryGetValue(a->attrs[hi], name) == v) hi++;
        *effective = (CFRange){lo, hi - lo};
    }
    return v;
}
DX_FN(CFAttributedStringGetAttribute);

/* Replace the dictionary of each unit in range by f(old). Units that shared
 * a dictionary still share the new one. */
static void remap(struct cf_attributed *a, CFRange r, Ref (*f)(Ref old, const void *arg), const void *arg) {
    if (!a || !a->mutable || !cf_range_valid(r, a->length)) return;
    for (CFIndex i = r.location; i < r.location + r.length;) {
        Ref old = a->attrs[i];
        Ref new_ = f(old, arg);
        CFIndex j = i;
        while (j < r.location + r.length && a->attrs[j] == old) {
            a->attrs[j] = d_CFRetain(new_);
            d_CFRelease(old);
            j++;
        }
        d_CFRelease(new_);
        i = j;
    }
}

struct merge { Ref dict; Ref key, value; bool clear; };

static Ref mutable_copy(Ref d) {
    return CALL(Ref, CFDictionaryCreateMutableCopy, (Ref, CFIndex, Ref))(NULL, 0, d);
}

static void add_entry(const void *k, const void *v, void *dst) {
    CALL(void, CFDictionarySetValue, (Ref, Ref, Ref))(dst, k, v);
}

static Ref merge_dict(Ref old, const void *arg) {
    const struct merge *m = arg;
    if (m->clear) return m->dict ? CALL(Ref, CFDictionaryCreateCopy, (Ref, Ref))(NULL, m->dict) : empty_dict();
    Ref d = mutable_copy(old);
    if (m->dict) {
        CFIndex n = CALL(CFIndex, CFDictionaryGetCount, (Ref))(m->dict);
        const void **keys = malloc((size_t)(n ? n : 1) * sizeof *keys), **vals = malloc((size_t)(n ? n : 1) * sizeof *vals);
        if (keys && vals) {
            CALL(void, CFDictionaryGetKeysAndValues, (Ref, const void **, const void **))(m->dict, keys, vals);
            for (CFIndex i = 0; i < n; i++) add_entry(keys[i], vals[i], (void *)d);
        }
        free(keys);
        free(vals);
    }
    if (m->key) {
        if (m->value) CALL(void, CFDictionarySetValue, (Ref, Ref, Ref))(d, m->key, m->value);
        else CALL(void, CFDictionaryRemoveValue, (Ref, Ref))(d, m->key);
    }
    return d;
}

static void d_CFAttributedStringSetAttributes(struct cf_attributed *a, CFRange r, Ref dict, Boolean clear) {
    struct merge m = {dict, NULL, NULL, clear};
    remap(a, r, merge_dict, &m);
}
DX_FN(CFAttributedStringSetAttributes);

static void d_CFAttributedStringSetAttribute(struct cf_attributed *a, CFRange r, Ref name, Ref value) {
    struct merge m = {NULL, name, value, false};
    remap(a, r, merge_dict, &m);
}
DX_FN(CFAttributedStringSetAttribute);

static void d_CFAttributedStringRemoveAttribute(struct cf_attributed *a, CFRange r, Ref name) {
    struct merge m = {NULL, name, NULL, false};
    remap(a, r, merge_dict, &m);
}
DX_FN(CFAttributedStringRemoveAttribute);

/* Replace the characters in range; inserted text takes the attributes of
 * the first replaced unit (or of the unit before, when inserting). */
static void d_CFAttributedStringReplaceString(struct cf_attributed *a, CFRange r, Ref replacement) {
    if (!a || !a->mutable || !cf_range_valid(r, a->length)) return;
    CFIndex rl = string_length(replacement), n = a->length - r.length + rl;
    uint16_t *chars = malloc((size_t)(n ? n : 1) * 2), *old = malloc((size_t)(a->length ? a->length : 1) * 2);
    Ref *attrs = calloc((size_t)(n ? n : 1), sizeof *attrs);
    if (!chars || !old || !attrs) { free(chars); free(old); free(attrs); return; }
    CALL(void, CFStringGetCharacters, (Ref, CFRange, uint16_t *))(a->string, (CFRange){0, a->length}, old);
    memcpy(chars, old, (size_t)r.location * 2);
    if (rl) CALL(void, CFStringGetCharacters, (Ref, CFRange, uint16_t *))(replacement, (CFRange){0, rl}, chars + r.location);
    memcpy(chars + r.location + rl, old + r.location + r.length, (size_t)(a->length - r.location - r.length) * 2);
    Ref fill = r.length ? a->attrs[r.location] : r.location > 0 ? a->attrs[r.location - 1] :
               a->length ? a->attrs[0] : NULL;
    Ref empty = fill ? NULL : empty_dict();
    for (CFIndex i = 0; i < r.location; i++) attrs[i] = d_CFRetain(a->attrs[i]);
    for (CFIndex i = 0; i < rl; i++) attrs[r.location + i] = d_CFRetain(fill ? fill : empty);
    for (CFIndex i = r.location + r.length; i < a->length; i++) attrs[i - r.length + rl] = d_CFRetain(a->attrs[i]);
    if (empty) d_CFRelease(empty);
    for (CFIndex i = 0; i < a->length; i++) d_CFRelease(a->attrs[i]);
    free(a->attrs);
    a->attrs = attrs;
    Ref s = CALL(Ref, CFStringCreateWithBytes, (Ref, const uint8_t *, CFIndex, uint32_t, Boolean))(
        NULL, (const uint8_t *)chars, n * 2, UTF16LE, 0);
    d_CFRelease(a->string);
    a->string = s;
    a->length = n;
    free(chars);
    free(old);
}
DX_FN(CFAttributedStringReplaceString);

static void d_CFAttributedStringReplaceAttributedString(struct cf_attributed *a, CFRange r, const struct cf_attributed *src) {
    if (!a || !src) return;
    d_CFAttributedStringReplaceString(a, r, src->string);
    for (CFIndex i = 0; i < src->length && r.location + i < a->length; i++) {
        d_CFRelease(a->attrs[r.location + i]);
        a->attrs[r.location + i] = d_CFRetain(src->attrs[i]);
    }
}
DX_FN(CFAttributedStringReplaceAttributedString);

static Ref d_CFAttributedStringGetMutableString(struct cf_attributed *a) { return NULL; }   /* not supported */
DX_FN(CFAttributedStringGetMutableString);
static void d_CFAttributedStringBeginEditing(struct cf_attributed *a) {}
DX_FN(CFAttributedStringBeginEditing);
static void d_CFAttributedStringEndEditing(struct cf_attributed *a) {}
DX_FN(CFAttributedStringEndEditing);
CF_TYPE_ID(CFAttributedString, CF_ATTRIBUTED_STRING);
