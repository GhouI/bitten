/* Dynamic casts: `as?`, `as!` and `is` on values whose type is only known at
 * run time.
 *
 * swift_dynamicCast takes a source value with its static type and a
 * destination of the target type. The source is first opened: an
 * existential (`any P`, `AnyObject`, `any Error`, `any P.Type`) is replaced
 * by the value inside and its dynamic type, an Optional by its payload.
 * Then, by target kind:
 *   - same type: a copy;
 *   - Optional: the payload is cast, nil stays nil;
 *   - existential: every protocol must be conformed to (and the class or
 *     superclass constraint met), then the container is built: inline
 *     buffer or box, class reference, error box, or metatype, followed by
 *     the witness tables;
 *   - class: the object's class must descend from the target;
 *   - metatype: the type itself is cast (swift_dynamicCastMetatype).
 * Bridging between Swift values and Objective-C objects (String to
 * NSString...) is the standard library's job and is not done here.
 *
 * The cast is done on a copy of the source; "take" semantics are then
 * honoured by destroying the source, which consumes it the same way. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "swift_internal.h"

enum {
    CAST_UNCONDITIONAL = 1,
    CAST_TAKE_ON_SUCCESS = 2,
    CAST_DESTROY_ON_FAILURE = 4,
};

/* Existential type flags */
enum {
    EX_NUM_WITNESS_TABLES = 0x00FFFFFF,
    EX_SPECIAL_PROTOCOL_SHIFT = 24, /* 6 bits; 1 = Error */
    EX_HAS_SUPERCLASS = 0x40000000,
    EX_CLASS_CONSTRAINT_ANY = 0x80000000, /* clear: class-bound */
};

static void *rt(const char *name) { return dx_registry_lookup(name); }
#define RT(type, var, sym)       \
    static __typeof__(type) var; \
    if (!var) var = (type)rt(sym);

/* ---- classes ------------------------------------------------------------------ */
static int tagged(const void *obj) { return ((uintptr_t)obj & 0x8000000000000001ull) != 0; }

/* The class object of an instance (Swift or Objective-C). */
static const void *class_of(const void *obj) {
    if (!obj) return NULL;
    if (!tagged(obj) && sw_is_native(obj)) {
        const sw_metadata *m = ((const sw_heap_object *)obj)->metadata;
        return sw_kind(m) == SW_KIND_CLASS ? m : NULL; /* boxes are not class instances */
    }
    RT(const void *(*)(const void *), getclass, "_object_getClass");
    return getclass ? getclass(obj) : NULL;
}
/* Metadata for a class object: a Swift class is its own metadata, a plain
 * Objective-C class gets its wrapper. */
static const sw_metadata *class_metadata(const void *cls) {
    if (!cls) return NULL;
    if (sw_class_is_swift(cls)) return cls;
    RT(const sw_metadata *(*)(const void *), wrap, "_swift_getObjCClassMetadata");
    return wrap ? wrap(cls) : cls;
}
static int class_is_kind(const void *cls, const void *target) {
    for (const sw_class_metadata *c = cls; c; c = c->superclass)
        if ((const void *)c == target) return 1;
    return 0;
}
static int is_class_like(const sw_metadata *m) {
    uintptr_t k = sw_kind(m);
    return k == SW_KIND_CLASS || k == SW_KIND_OBJC_CLASS_WRAPPER || k == SW_KIND_FOREIGN_CLASS;
}
static int class_conforms_objc(const void *cls, const void *proto) {
    RT(int (*)(const void *, const void *), conforms, "_class_conformsToProtocol");
    if (!conforms) return 0;
    for (const sw_class_metadata *c = cls; c; c = c->superclass)
        if (conforms(c, proto)) return 1;
    return 0;
}

/* ---- failure reports ------------------------------------------------------------ */
static void cast_failure(const sw_metadata *from, const sw_metadata *to, const char *file, unsigned line) {
    char msg[1024];
    int n = 0;
    if (file && *file) n = snprintf(msg, sizeof msg, "%s:%u: ", file, line);
    snprintf(msg + n, sizeof msg - n, "Could not cast value of type '%s' (%p) to '%s' (%p).\n",
             from ? sw_type_name(from, 1) : "<nil>", (const void *)from, to ? sw_type_name(to, 1) : "?",
             (const void *)to);
    ssize_t r = write(2, msg, strlen(msg));
    (void)r;
    abort();
}

/* ---- class and metatype casts ------------------------------------------------------- */
static const void *d_swift_dynamicCastClass(const void *object, const sw_metadata *target) {
    const void *t = sw_class_of_metadata(target);
    if (!object || !t) return NULL;
    return class_is_kind(class_of(object), t) ? object : NULL;
}
DX_FN(swift_dynamicCastClass);

static const void *d_swift_dynamicCastClassUnconditional(const void *object, const sw_metadata *target,
                                                         const char *file, unsigned line, unsigned col) {
    const void *r = d_swift_dynamicCastClass(object, target);
    if (!r) cast_failure(class_metadata(class_of(object)), target, file, line);
    return r;
}
DX_FN(swift_dynamicCastClassUnconditional);

static const sw_metadata *d_swift_dynamicCastMetatype(const sw_metadata *src, const sw_metadata *target) {
    if (src == target) return src;
    if (!src || !target) return NULL;
    if (is_class_like(src) && is_class_like(target)) return sw_is_subclass(src, target) ? src : NULL;
    return NULL;
}
DX_FN(swift_dynamicCastMetatype);

static const sw_metadata *d_swift_dynamicCastMetatypeUnconditional(const sw_metadata *src,
                                                                   const sw_metadata *target, const char *file,
                                                                   unsigned line, unsigned col) {
    const sw_metadata *r = d_swift_dynamicCastMetatype(src, target);
    if (!r) cast_failure(src, target, file, line);
    return r;
}
DX_FN(swift_dynamicCastMetatypeUnconditional);

/* Objective-C protocols: only classes conform. */
static const void *d_swift_dynamicCastObjCProtocolConditional(const void *object, size_t n,
                                                              const void *const *protocols) {
    if (!object) return NULL;
    const void *cls = class_of(object);
    for (size_t i = 0; i < n; i++)
        if (!class_conforms_objc(cls, protocols[i])) return NULL;
    return object;
}
DX_FN(swift_dynamicCastObjCProtocolConditional);
static const void *d_swift_dynamicCastObjCProtocolUnconditional(const void *object, size_t n,
                                                                const void *const *protocols,
                                                                const char *file, unsigned line, unsigned col) {
    const void *r = d_swift_dynamicCastObjCProtocolConditional(object, n, protocols);
    if (!r) {
        char msg[512];
        snprintf(msg, sizeof msg, "%s:%u: Could not cast value of type '%s' (%p) to an Objective-C protocol.\n",
                 file ? file : "", line, object ? sw_type_name(class_metadata(class_of(object)), 1) : "<nil>",
                 object);
        ssize_t w = write(2, msg, strlen(msg));
        (void)w;
        abort();
    }
    return r;
}
DX_FN(swift_dynamicCastObjCProtocolUnconditional);

static const sw_metadata *d_swift_dynamicCastTypeToObjCProtocolConditional(const sw_metadata *type, size_t n,
                                                                           const void *const *protocols) {
    const void *cls = type ? sw_class_of_metadata(type) : NULL;
    if (!cls) return NULL;
    for (size_t i = 0; i < n; i++)
        if (!class_conforms_objc(cls, protocols[i])) return NULL;
    return type;
}
DX_FN(swift_dynamicCastTypeToObjCProtocolConditional);
static const sw_metadata *d_swift_dynamicCastTypeToObjCProtocolUnconditional(
    const sw_metadata *type, size_t n, const void *const *protocols, const char *file, unsigned line,
    unsigned col) {
    const sw_metadata *r = d_swift_dynamicCastTypeToObjCProtocolConditional(type, n, protocols);
    if (!r) cast_failure(type, NULL, file, line);
    return r;
}
DX_FN(swift_dynamicCastTypeToObjCProtocolUnconditional);

/* ---- existentials --------------------------------------------------------------------- */
struct exinfo {
    uint32_t flags;
    unsigned nprotos;
    const sw_metadata *super;
    const uintptr_t *protos; /* ProtocolDescriptorRef: low bit = Objective-C */
};
static void exinfo(const sw_metadata *m, struct exinfo *x) {
    const sw_existential_metadata *e = (const sw_existential_metadata *)m;
    const void *const *tail = (const void *const *)(e + 1);
    x->flags = e->flags;
    x->nprotos = e->num_protocols;
    x->super = (e->flags & EX_HAS_SUPERCLASS) ? tail[0] : NULL;
    x->protos = (const uintptr_t *)(tail + (x->super ? 1 : 0));
}
static int ex_is_error(const struct exinfo *x) { return ((x->flags >> EX_SPECIAL_PROTOCOL_SHIFT) & 0x3F) == 1; }
static int ex_is_class(const struct exinfo *x) { return !(x->flags & EX_CLASS_CONSTRAINT_ANY); }
static unsigned ex_witness_tables(const struct exinfo *x) { return x->flags & EX_NUM_WITNESS_TABLES; }

static sw_opaque *project_buffer(void **buffer, const sw_metadata *type) {
    const sw_vwt *w = sw_vwt_of(type);
    if (!(w->flags & SW_VW_IS_NON_INLINE)) return (sw_opaque *)buffer;
    size_t am = w->flags & SW_VW_ALIGNMENT_MASK;
    return (sw_opaque *)((char *)buffer[0] + ((sizeof(sw_heap_object) + am) & ~am));
}

/* Opens an existential value: the value inside and its dynamic type. */
static int open_existential(sw_opaque *src, const sw_metadata *type, sw_opaque **value,
                            const sw_metadata **dyn, void **scratch) {
    if (sw_kind(type) == SW_KIND_EXISTENTIAL_METATYPE) {
        /* { metatype, witness tables } */
        const sw_metadata *t = *(const sw_metadata *const *)src;
        *value = src;
        *dyn = sw_get_metatype_metadata(t);
        return *dyn != NULL;
    }
    struct exinfo x;
    exinfo(type, &x);
    if (ex_is_error(&x)) {
        const sw_witness_table *conf;
        const sw_opaque *v;
        sw_error_value(*(void **)src, scratch, &v, dyn, &conf);
        *value = (sw_opaque *)v;
        return *dyn != NULL;
    }
    if (ex_is_class(&x)) {
        /* { object, witness tables } */
        *value = src;
        *dyn = class_metadata(class_of(*(void **)src));
        return *dyn != NULL;
    }
    /* { buffer[3], type, witness tables } */
    void **c = (void **)src;
    *dyn = c[3];
    *value = project_buffer(c, *dyn);
    return *dyn != NULL;
}

static int cast(sw_opaque *dest, sw_opaque *src, const sw_metadata *src_type, const sw_metadata *target);

/* Witness tables for `type` (the dynamic type of `value`) against the
 * protocols of existential `x`, in the container's order. */
static int conformances(const struct exinfo *x, const sw_metadata *type, const void **wts) {
    unsigned k = 0;
    for (unsigned i = 0; i < x->nprotos; i++) {
        uintptr_t p = x->protos[i];
        if (p & 1) {
            const void *cls = sw_class_of_metadata(type);
            if (!cls || !class_conforms_objc(cls, (const void *)(p & ~(uintptr_t)1))) return 0;
            continue;
        }
        const sw_witness_table *wt = sw_conforms_to(type, (const sw_protocol_descriptor *)p);
        if (!wt) return 0;
        wts[k++] = wt;
    }
    return 1;
}

static int cast_to_existential(sw_opaque *dest, sw_opaque *src, const sw_metadata *type,
                               const sw_metadata *target) {
    struct exinfo x;
    exinfo(target, &x);
    const void *wts[64];
    if (x.nprotos > 64) return 0;
    int class_value = is_class_like(type);
    if ((ex_is_class(&x) || x.super) && !class_value) return 0;
    if (class_value) {
        /* Use the object's own class: a subclass may conform where the
         * static type does not. */
        const void *obj = *(void **)src;
        if (!obj) return 0;
        type = class_metadata(class_of(obj));
        if (x.super && !sw_is_subclass(type, x.super)) return 0;
    }
    if (!conformances(&x, type, wts)) return 0;
    unsigned nwt = ex_witness_tables(&x);
    if (ex_is_error(&x)) {
        const sw_witness_table *conf = nwt ? wts[0] : NULL;
        *(void **)dest = sw_alloc_error(type, conf, src, 0, NULL);
        return 1;
    }
    if (ex_is_class(&x)) {
        void **c = (void **)dest;
        c[0] = sw_unknown_retain(*(void **)src);
        memcpy(c + 1, wts, nwt * sizeof *wts);
        return 1;
    }
    void **c = (void **)dest;
    const sw_vwt *w = sw_vwt_of(type);
    if (w->flags & SW_VW_IS_NON_INLINE) {
        RT(sw_heap_object * (*)(const sw_metadata *), alloc_box, "_swift_allocBox");
        if (!alloc_box) return 0;
        c[0] = alloc_box(type);
    }
    w->initializeWithCopy(project_buffer(c, type), src, type);
    c[3] = (void *)type;
    memcpy(c + 4, wts, nwt * sizeof *wts);
    return 1;
}

/* `T.Type` value -> `any P.Type`: the metatype's instance type must conform. */
static int cast_to_existential_metatype(sw_opaque *dest, sw_opaque *src, const sw_metadata *type,
                                        const sw_metadata *target) {
    if (sw_kind(type) != SW_KIND_METATYPE) return 0;
    const sw_metadata *inst = *(const sw_metadata *const *)src;
    const sw_metadata *ex = ((const sw_metatype_metadata *)target)->instance_type;
    if (sw_kind(ex) != SW_KIND_EXISTENTIAL) return 0;
    struct exinfo x;
    exinfo(ex, &x);
    const void *wts[64];
    if (x.nprotos > 64) return 0;
    if ((ex_is_class(&x) || x.super) && !is_class_like(inst)) return 0;
    if (x.super && !sw_is_subclass(inst, x.super)) return 0;
    if (!conformances(&x, inst, wts)) return 0;
    void **c = (void **)dest;
    c[0] = (void *)inst;
    memcpy(c + 1, wts, ex_witness_tables(&x) * sizeof *wts);
    return 1;
}

/* ---- Optional ---------------------------------------------------------------------------- */
static const sw_metadata *optional_payload(const sw_metadata *m) { return ((const sw_metadata *const *)m)[2]; }

static int cast_to_optional(sw_opaque *dest, sw_opaque *src, const sw_metadata *type, const sw_metadata *target) {
    const sw_metadata *payload = optional_payload(target);
    const sw_vwt *pw = sw_vwt_of(payload);
    if (sw_kind(type) == SW_KIND_OPTIONAL) {
        const sw_metadata *sp = optional_payload(type);
        if (sw_vwt_of(sp)->getEnumTagSinglePayload(src, 1, sp) != 0) {
            pw->storeEnumTagSinglePayload(dest, 1, 1, payload); /* nil stays nil */
            return 1;
        }
        type = sp; /* the payload is at the start of the Optional */
    }
    if (!cast(dest, src, type, payload)) return 0;
    pw->storeEnumTagSinglePayload(dest, 0, 1, payload);
    return 1;
}

/* ---- the general cast --------------------------------------------------------------------- */
static int cast(sw_opaque *dest, sw_opaque *src, const sw_metadata *type, const sw_metadata *target) {
    if (type == target) {
        sw_vwt_of(type)->initializeWithCopy(dest, src, type);
        return 1;
    }
    uintptr_t sk = sw_kind(type);
    if (sk == SW_KIND_EXISTENTIAL || sk == SW_KIND_EXISTENTIAL_METATYPE) {
        sw_opaque *inner;
        const sw_metadata *dyn;
        void *scratch;
        if (!open_existential(src, type, &inner, &dyn, &scratch)) return 0;
        return cast(dest, inner, dyn, target);
    }
    switch (sw_kind(target)) {
    case SW_KIND_OPTIONAL:
        return cast_to_optional(dest, src, type, target);
    case SW_KIND_EXISTENTIAL:
        return cast_to_existential(dest, src, type, target);
    case SW_KIND_EXISTENTIAL_METATYPE:
        return cast_to_existential_metatype(dest, src, type, target);
    case SW_KIND_CLASS: case SW_KIND_OBJC_CLASS_WRAPPER:
        if (is_class_like(type)) {
            const void *obj = d_swift_dynamicCastClass(*(void **)src, target);
            if (!obj) return 0;
            *(void **)dest = sw_unknown_retain((void *)obj);
            return 1;
        }
        break;
    case SW_KIND_METATYPE:
        if (sk == SW_KIND_METATYPE) {
            const sw_metadata *r = d_swift_dynamicCastMetatype(*(const sw_metadata *const *)src,
                                                               ((const sw_metatype_metadata *)target)->instance_type);
            if (!r) return 0;
            *(const sw_metadata **)dest = r;
            return 1;
        }
        break;
    }
    if (sk == SW_KIND_OPTIONAL) {
        /* Unwrap a non-nil Optional and try its payload. */
        const sw_metadata *sp = optional_payload(type);
        if (sw_vwt_of(sp)->getEnumTagSinglePayload(src, 1, sp) != 0) return 0;
        return cast(dest, src, sp, target);
    }
    return 0;
}

/* bool swift_dynamicCast(OpaqueValue *dest, OpaqueValue *src, const Metadata
 * *srcType, const Metadata *targetType, DynamicCastFlags flags) */
static _Bool d_swift_dynamicCast(sw_opaque *dest, sw_opaque *src, const sw_metadata *src_type,
                                 const sw_metadata *target, uintptr_t flags) {
    if (cast(dest, src, src_type, target)) {
        if (flags & CAST_TAKE_ON_SUCCESS) sw_vwt_of(src_type)->destroy(src, src_type);
        return 1;
    }
    if (flags & CAST_UNCONDITIONAL) {
        const sw_metadata *dyn = src_type;
        sw_opaque *inner;
        void *scratch;
        uintptr_t k = sw_kind(src_type);
        if (k == SW_KIND_EXISTENTIAL || k == SW_KIND_EXISTENTIAL_METATYPE)
            if (!open_existential(src, src_type, &inner, &dyn, &scratch)) dyn = src_type;
        cast_failure(dyn, target, NULL, 0);
    }
    if (flags & CAST_DESTROY_ON_FAILURE) sw_vwt_of(src_type)->destroy(src, src_type);
    return 0;
}
DX_FN(swift_dynamicCast);
