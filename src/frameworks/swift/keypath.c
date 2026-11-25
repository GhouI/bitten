/* Key paths: instantiating the patterns the compiler emits
 * (swift_getKeyPath) and projecting through the resulting objects.
 *
 * A key path object is an instance of one of the standard library's key
 * path classes (stdlib/KeyPath.swift: KeyPath<Root, Value>,
 * WritableKeyPath, ReferenceWritableKeyPath) followed by a buffer that is
 * private to this file: the root and leaf types, then one instantiated
 * component per step (a stored field offset, a computed property's
 * accessors and captured arguments, or an optional chain/force/wrap), then
 * the components' argument areas. Compiled code only passes these objects
 * back to the entry points here and to the library.
 *
 * Patterns (lib/IRGen/GenKeyPath.cpp): int32 relative once-cache or 0,
 * relative generic environment or 0, relative root and leaf type references
 * (mangled name + 1), relative KVC string or 0, a 32-bit buffer header (size
 * of what follows), then the components, each followed by a relative type
 * reference to its result type except the last. Component headers: the
 * discriminator in bits 24-30 and a payload (constants as in the compiler's
 * swift/ABI/KeyPath.h). The argument buffer passed to swift_getKeyPath holds
 * the pattern's generic arguments (key parameters, then witness tables) and
 * then the captured subscript arguments.
 *
 * Accessors use the key path calling conventions: getter(base, args, size)
 * returning the value indirectly (in rax), setter(newValue, base, args,
 * size), and for captured arguments a layout function (args) -> (size,
 * alignMask), an initializer (patternArgs, dest) and a witness table
 * {destroy(args, size), copy(src, dst, size), equals(a, b, size),
 * hash(args, size)}. */
#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>

#include "swift_internal.h"

/* ---- ABI constants -------------------------------------------------------------- */
enum {
    HDR_SIZE_MASK = 0x00FFFFFF,
    CH_PAYLOAD_MASK = 0x00FFFFFF,
    CH_DISCRIMINATOR_SHIFT = 24,
    CH_DISCRIMINATOR_MASK = 0x7F,
    CH_EXTERNAL = 0, CH_STRUCT = 1, CH_COMPUTED = 2, CH_CLASS = 3, CH_OPTIONAL = 4,
    CH_STORED_OFFSET_MASK = 0x007FFFFF,
    CH_MAX_INLINE_OFFSET = 0x007FFFFC,
    CH_UNRESOLVED_INDIRECT_OFFSET = 0x007FFFFD,
    CH_UNRESOLVED_FIELD_OFFSET = 0x007FFFFE,
    CH_OUT_OF_LINE_OFFSET = 0x007FFFFF,
    CH_STORED_MUTABLE = 0x00800000,
    CH_OPTIONAL_CHAIN = 0, CH_OPTIONAL_WRAP = 1, CH_OPTIONAL_FORCE = 2,
    CH_COMPUTED_MUTATING = 0x00800000,
    CH_COMPUTED_SETTABLE = 0x00400000,
    CH_COMPUTED_ID_BY_STORED_PROPERTY = 0x00200000,
    CH_COMPUTED_ID_BY_VTABLE_OFFSET = 0x00100000,
    CH_COMPUTED_HAS_ARGUMENTS = 0x00080000,
    CH_COMPUTED_ID_RESOLUTION_MASK = 0x0000000F,
    CH_ID_RESOLVED = 0, CH_ID_INDIRECT_POINTER = 2, CH_ID_RESOLVED_ABSOLUTE = 3,
    CH_ID_FUNCTION_CALL = 1,
};

/* ---- instantiated key paths ----------------------------------------------------- */
enum { KC_STRUCT, KC_CLASS, KC_COMPUTED, KC_CHAIN, KC_WRAP, KC_FORCE };
enum { KK_READONLY, KK_WRITABLE, KK_REFERENCE };

typedef void (*kp_destroy_fn)(void *args, size_t size);
typedef void (*kp_copy_fn)(const void *src, void *dst, size_t size);
typedef _Bool (*kp_equals_fn)(const void *a, const void *b, size_t size);
typedef intptr_t (*kp_hash_fn)(const void *args, size_t size);
typedef void (*kp_setter_fn)(const sw_opaque *value, sw_opaque *base, const void *args, size_t size);
struct kp_witnesses {
    kp_destroy_fn destroy; /* NULL: trivial */
    kp_copy_fn copy;
    kp_equals_fn equals;
    kp_hash_fn hash;
};

struct kp_comp {
    uint8_t kind;                /* KC_* */
    uint8_t mutable_;            /* stored: var; computed: settable */
    uint8_t mutating;            /* computed: the setter takes the base inout */
    uint8_t id_kind;             /* computed: 0 pointer, 1 stored property index, 2 vtable offset */
    size_t offset;               /* stored */
    const sw_metadata *type;     /* the value this component produces */
    uintptr_t id;                /* computed */
    const void *getter, *setter; /* computed */
    const struct kp_witnesses *wit; /* NULL: arguments compared and copied as bytes */
    void *args;                  /* computed with captured arguments, else NULL */
    size_t argsize;
};

struct kp_body {
    const sw_metadata *root, *leaf;
    const char *kvc;
    uint32_t n;
    int32_t refend; /* index of the last component that reaches through a reference, or -1 */
    uint32_t kind;  /* KK_* */
    uint32_t pad;
    struct kp_comp c[];
};

/* The body follows the object's Swift instance (AnyKeyPath has no stored
 * properties of its own; subclasses add none). */
static size_t body_offset(const sw_metadata *cls) {
    return (((const sw_class_metadata *)cls)->instance_size + 15) & ~(size_t)15;
}
static struct kp_body *body_of(const void *kp) {
    return (struct kp_body *)((char *)kp + body_offset(((const sw_heap_object *)kp)->metadata));
}

static int comp_is_reference(const struct kp_comp *c) {
    return (c->kind == KC_CLASS && c->mutable_) ||
           (c->kind == KC_COMPUTED && c->mutable_ && !c->mutating);
}
static int comp_is_writable(const struct kp_comp *c) {
    return (c->kind == KC_STRUCT && c->mutable_) || (c->kind == KC_COMPUTED && c->mutable_) ||
           c->kind == KC_FORCE;
}
/* What kind of key path a sequence of components makes: writable while
 * every step is; a step through a reference makes everything before it
 * irrelevant to mutability. */
static void classify(struct kp_body *b) {
    b->kind = KK_WRITABLE;
    b->refend = -1;
    for (uint32_t i = 0; i < b->n; i++) {
        const struct kp_comp *c = &b->c[i];
        if (comp_is_reference(c)) {
            b->kind = KK_REFERENCE;
            b->refend = (int32_t)i;
        } else if (!comp_is_writable(c))
            b->kind = KK_READONLY;
    }
    if (b->kind == KK_READONLY) b->refend = -1;
}

static void *aligned_area(char **cursor, size_t size, size_t align_mask) {
    if (align_mask < 15) align_mask = 15;
    uintptr_t p = ((uintptr_t)*cursor + align_mask) & ~(uintptr_t)align_mask;
    *cursor = (char *)p + size;
    return (void *)p;
}

/* Class metadata of the key path class for a kind and root/value types. */
static const sw_metadata *kp_class(uint32_t kind, const sw_metadata *root, const sw_metadata *leaf) {
    static const char *const names[] = {"_$ss7KeyPathCMa", "_$ss15WritableKeyPathCMa",
                                        "_$ss24ReferenceWritableKeyPathCMa"};
    static sw_response (*accessors[3])(size_t, const sw_metadata *, const sw_metadata *);
    if (!accessors[kind]) {
        void *fn = dx_global_lookup(names[kind]);
        if (!fn) dx_fatal("swift: key paths need the standard library (%s)", names[kind]);
        __atomic_store_n(&accessors[kind], fn, __ATOMIC_RELEASE);
    }
    return accessors[kind](0, root, leaf).value;
}

/* A new object of class `cls` with room for n components and `extra`
 * bytes of argument areas. */
static void *kp_alloc(const sw_metadata *cls, uint32_t n, size_t extra, struct kp_body **out) {
    size_t off = body_offset(cls);
    size_t size = off + sizeof(struct kp_body) + n * sizeof(struct kp_comp) + extra + 16;
    sw_heap_object *o = sw_alloc_object(cls, size, 15);
    struct kp_body *b = (struct kp_body *)((char *)o + off);
    memset(b, 0, sizeof *b + n * sizeof(struct kp_comp));
    b->n = n;
    *out = b;
    return o;
}

/* ---- pattern instantiation ------------------------------------------------------ */
struct pattern {
    int32_t once;
    int32_t genv;
    int32_t root, leaf;
    int32_t kvc;
    uint32_t header;
};

struct inst {
    const uint32_t *genv;      /* the pattern's generic environment */
    const void *args;          /* swift_getKeyPath's argument buffer */
    unsigned nkey;             /* words of generic arguments at its start */
};

/* A type reference in a pattern: a mangled name (address + 1), or an
 * accessor thunk named by "\xFF\x09" + relative function reference, which
 * takes the argument buffer; an even address is the metadata accessor
 * itself. */
static const void *resolve_ref(const int32_t *field, const struct inst *in) {
    uintptr_t p = (uintptr_t)sw_rel(field);
    if (!p) return NULL;
    if (!(p & 1)) return ((sw_response(*)(size_t))p)(0).value;
    const char *name = (const char *)(p - 1);
    if ((uint8_t)name[0] == 0xFF && name[1] == 9) {
        const void *(*thunk)(const void *) = (const void *(*)(const void *))sw_rel((const int32_t *)(name + 2));
        return thunk(in->args);
    }
    const sw_metadata *m = sw_type_in_genv(name, in->genv, (const void *const *)in->args);
    if (!m) dx_fatal("swift: key path: cannot resolve type %.*s", (int)sw_mangled_name_length(name), name);
    return m;
}

/* Field offset of a stored component; *p advances past its payload. */
static size_t stored_offset(uint32_t h, const uint32_t **p, const sw_metadata *base, int is_class) {
    uint32_t payload = h & CH_STORED_OFFSET_MASK;
    if (payload <= CH_MAX_INLINE_OFFSET) return payload;
    const uint32_t *field = (*p)++;
    switch (payload) {
    case CH_OUT_OF_LINE_OFFSET:
        return *field;
    case CH_UNRESOLVED_FIELD_OFFSET:
        /* byte offset into the base type's metadata of its field offset */
        if (is_class) return *(const size_t *)((const char *)base + *field);
        return *(const uint32_t *)((const char *)base + *field);
    case CH_UNRESOLVED_INDIRECT_OFFSET:
        /* a global variable holding the offset (the class layout decides it) */
        return *(const size_t *)sw_rel_indirect((const int32_t *)field);
    }
    dx_fatal("swift: key path: bad stored component payload %#x", payload);
}

typedef struct { size_t size, align_mask; } kp_layout;

/* Where a computed component's captured arguments come from, worked out
 * before the object exists. */
struct pending {
    int has_args;
    size_t size, align_mask, room;
    void (*init)(const void *src, void *dst); /* the pattern's initializer, or NULL */
    const void *src;                          /* its source: swift_getKeyPath's buffer */
    void **overlay;                           /* then these words... */
    size_t noverlay, overlay_at;              /* ...at this offset */
};

static uintptr_t computed_id(uint32_t h, const int32_t *field) {
    if (h & (CH_COMPUTED_ID_BY_STORED_PROPERTY | CH_COMPUTED_ID_BY_VTABLE_OFFSET))
        return (uintptr_t)(intptr_t)*field;
    switch (h & CH_COMPUTED_ID_RESOLUTION_MASK) {
    case CH_ID_RESOLVED:
        return (uintptr_t)sw_rel(field);
    case CH_ID_INDIRECT_POINTER:
        return *(const uintptr_t *)sw_rel(field);
    case CH_ID_FUNCTION_CALL:
        return ((uintptr_t(*)(const void *))sw_rel(field))(NULL);
    case CH_ID_RESOLVED_ABSOLUTE:
        return (uintptr_t)(uint32_t)*field;
    }
    dx_fatal("swift: key path: bad computed id resolution %#x", h);
}

/* Decodes the component whose header is at p into c (offsets resolved
 * against `base`); returns the position after it. A computed component
 * with captured arguments gets its layout from its layout function called
 * with `env`, and its initializer, in pend. */
static const uint32_t *decode(const uint32_t *p, struct kp_comp *c, const sw_metadata *base,
                              const void *env, struct pending *pend) {
    uint32_t h = *p++;
    unsigned disc = (h >> CH_DISCRIMINATOR_SHIFT) & CH_DISCRIMINATOR_MASK;
    memset(pend, 0, sizeof *pend);
    switch (disc) {
    case CH_STRUCT:
    case CH_CLASS:
        c->kind = disc == CH_STRUCT ? KC_STRUCT : KC_CLASS;
        c->mutable_ = (h & CH_STORED_MUTABLE) != 0;
        c->offset = stored_offset(h, &p, base, disc == CH_CLASS);
        return p;
    case CH_OPTIONAL:
        switch (h & CH_PAYLOAD_MASK) {
        case CH_OPTIONAL_CHAIN: c->kind = KC_CHAIN; break;
        case CH_OPTIONAL_WRAP: c->kind = KC_WRAP; break;
        case CH_OPTIONAL_FORCE: c->kind = KC_FORCE; break;
        default: dx_fatal("swift: key path: bad optional component %#x", h);
        }
        return p;
    case CH_COMPUTED: {
        c->kind = KC_COMPUTED;
        c->mutable_ = (h & CH_COMPUTED_SETTABLE) != 0;
        c->mutating = (h & CH_COMPUTED_MUTATING) != 0;
        c->id_kind = (h & CH_COMPUTED_ID_BY_STORED_PROPERTY) ? 1 : (h & CH_COMPUTED_ID_BY_VTABLE_OFFSET) ? 2 : 0;
        c->id = computed_id(h, (const int32_t *)p++);
        c->getter = sw_rel((const int32_t *)p++);
        if (c->mutable_) c->setter = sw_rel((const int32_t *)p++);
        if (h & CH_COMPUTED_HAS_ARGUMENTS) {
            kp_layout (*layout)(const void *) = (kp_layout(*)(const void *))sw_rel((const int32_t *)p++);
            c->wit = sw_rel((const int32_t *)p++);
            pend->init = (void (*)(const void *, void *))sw_rel((const int32_t *)p++);
            kp_layout l = layout(env);
            pend->has_args = 1;
            pend->size = pend->room = l.size;
            pend->align_mask = l.align_mask;
            pend->src = env;
        }
        return p;
    }
    }
    dx_fatal("swift: key path: unknown component kind %u (header %#x)", disc, h);
}

/* An external component: the property belongs to another module, which
 * describes it with a property descriptor (a component in its own generic
 * context). A trivial descriptor (header 0) defers to the local component
 * that follows. Otherwise the descriptor's component is used; its
 * arguments are the local component's subscript arguments followed by the
 * descriptor's generic arguments (`nsub` words, resolved here). */
static const uint32_t *decode_external(const uint32_t *p, struct kp_comp *c, const sw_metadata *base,
                                       const struct inst *in, struct pending *pend) {
    uint32_t h = *p++;
    unsigned nsub = h & CH_PAYLOAD_MASK;
    const uint32_t *desc = sw_rel_indirect((const int32_t *)p++);
    void **subs = nsub ? malloc(nsub * sizeof *subs) : NULL;
    for (unsigned i = 0; i < nsub; i++) subs[i] = (void *)resolve_ref((const int32_t *)p++, in);
    p = decode(p, c, base, in->args, pend);
    if (!desc || *desc == 0) {
        free(subs);
        return p;
    }
    struct pending local = *pend;
    struct kp_comp dc = {0};
    decode(desc, &dc, base, subs, pend);
    *c = dc;
    if (!pend->has_args) {
        free(subs);
        return p;
    }
    /* Subscript arguments: what the local initializer writes before the
     * pattern's own generic arguments. */
    size_t indices = 0;
    if (local.has_args) {
        indices = local.size - (in->genv ? in->nkey * sizeof(void *) : 0);
        indices = (indices + 7) & ~(size_t)7;
    }
    pend->init = local.has_args && indices ? local.init : NULL;
    pend->src = in->args;
    pend->size = indices + nsub * sizeof(void *);
    pend->room = local.size > pend->size ? local.size : pend->size;
    if (local.align_mask > pend->align_mask) pend->align_mask = local.align_mask;
    pend->overlay = subs;
    pend->noverlay = nsub;
    pend->overlay_at = indices;
    return p;
}

static const char *kvc_copy(char **cursor, const char *a, const char *b) {
    size_t la = strlen(a), lb = b ? strlen(b) : 0;
    char *s = *cursor;
    memcpy(s, a, la);
    if (b) {
        s[la] = '.';
        memcpy(s + la + 1, b, lb);
        la += lb + 1;
    }
    s[la] = 0;
    *cursor += la + 1;
    return s;
}

static void *instantiate(const struct pattern *pat, const void *args) {
    struct inst in = {sw_rel(&pat->genv), args, 0};
    if (in.genv) in.nkey = sw_genv_key_count(in.genv);
    const sw_metadata *root = resolve_ref(&pat->root, &in), *leaf = resolve_ref(&pat->leaf, &in);
    const uint32_t *p = (const uint32_t *)(pat + 1);
    const uint32_t *end = (const uint32_t *)((const char *)p + (pat->header & HDR_SIZE_MASK));

    /* Components take at least 4 bytes each. */
    size_t max = (size_t)(end - p) + 1;
    struct kp_body *tmp = calloc(1, sizeof *tmp + max * sizeof(struct kp_comp));
    struct pending *pend = calloc(max, sizeof *pend);
    uint32_t n = 0;
    size_t extra = 0;
    const sw_metadata *base = root;
    while (p < end) {
        struct kp_comp *c = &tmp->c[n];
        unsigned disc = (*p >> CH_DISCRIMINATOR_SHIFT) & CH_DISCRIMINATOR_MASK;
        if (disc == CH_EXTERNAL)
            p = decode_external(p, c, base, &in, &pend[n]);
        else
            p = decode(p, c, base, args, &pend[n]);
        c->type = p < end ? resolve_ref((const int32_t *)p++, &in) : leaf;
        if (pend[n].has_args) extra += pend[n].room + pend[n].align_mask + 16;
        base = c->type;
        n++;
    }
    tmp->n = n;
    classify(tmp);
    const char *kvc = sw_rel(&pat->kvc);
    if (kvc) extra += strlen(kvc) + 1;

    struct kp_body *b;
    void *obj = kp_alloc(kp_class(tmp->kind, root, leaf), n, extra, &b);
    b->root = root;
    b->leaf = leaf;
    memcpy(b->c, tmp->c, n * sizeof *b->c);
    classify(b);
    char *cursor = (char *)&b->c[n];
    for (uint32_t i = 0; i < n; i++) {
        struct pending *pd = &pend[i];
        if (!pd->has_args) continue;
        struct kp_comp *c = &b->c[i];
        c->args = aligned_area(&cursor, pd->room, pd->align_mask);
        c->argsize = pd->size;
        if (pd->init) pd->init(pd->src, c->args);
        if (pd->noverlay) memcpy((char *)c->args + pd->overlay_at, pd->overlay, pd->noverlay * sizeof(void *));
        free(pd->overlay);
    }
    if (kvc) b->kvc = kvc_copy(&cursor, kvc, NULL);
    free(tmp);
    free(pend);
    return obj;
}

/* HeapObject *swift_getKeyPath(const void *pattern, const void *arguments):
 * a new key path (+1). Patterns without generic or captured arguments are
 * instantiated once, into an immortal object kept in their cache word. */
static void *d_swift_getKeyPath(const struct pattern *pat, const void *args) {
    void **once = pat->once ? (void **)sw_rel(&pat->once) : NULL;
    if (once) {
        void *kp = __atomic_load_n(once, __ATOMIC_ACQUIRE);
        if (kp) return kp;
    }
    void *kp = instantiate(pat, args);
    if (!once) return kp;
    ((sw_heap_object *)kp)->refcounts = ~0ull; /* immortal */
    void *expected = NULL;
    if (!__atomic_compare_exchange_n(once, &expected, kp, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
        return expected; /* another thread was first; ours stays unused */
    return kp;
}
DX_FN(swift_getKeyPath);

/* The copy witness of trivially copyable captured arguments. */
static void d_swift_copyKeyPathTrivialIndices(const void *src, void *dst, size_t size) {
    memcpy(dst, src, size);
}
DX_FN(swift_copyKeyPathTrivialIndices);

/* ---- lifetime, equality, hashing, appending -------------------------------------- */
static void d_swift_kp_destroy(void *kp) {
    struct kp_body *b = body_of(kp);
    for (uint32_t i = 0; i < b->n; i++) {
        struct kp_comp *c = &b->c[i];
        if (c->args && c->wit && c->wit->destroy) c->wit->destroy(c->args, c->argsize);
    }
}
DX_EXPORT("__swift_kp_destroy", d_swift_kp_destroy);

static int args_equal(const struct kp_comp *a, const struct kp_comp *b) {
    if (!a->args != !b->args || a->argsize != b->argsize) return 0;
    if (!a->args) return 1;
    if (a->wit) return a->wit->equals(a->args, b->args, a->argsize);
    return memcmp(a->args, b->args, a->argsize) == 0;
}

static _Bool d_swift_kp_equal(const void *ka, const void *kb) {
    if (((const sw_heap_object *)ka)->metadata != ((const sw_heap_object *)kb)->metadata) return 0;
    const struct kp_body *a = body_of(ka), *b = body_of(kb);
    if (a->root != b->root || a->leaf != b->leaf || a->n != b->n) return 0;
    for (uint32_t i = 0; i < a->n; i++) {
        const struct kp_comp *x = &a->c[i], *y = &b->c[i];
        if (x->kind != y->kind || x->type != y->type) return 0;
        switch (x->kind) {
        case KC_STRUCT:
        case KC_CLASS:
            if (x->offset != y->offset) return 0;
            break;
        case KC_COMPUTED:
            if (x->id_kind != y->id_kind || x->id != y->id || x->mutable_ != y->mutable_ ||
                x->mutating != y->mutating || !args_equal(x, y))
                return 0;
            break;
        }
    }
    return 1;
}
DX_EXPORT("__swift_kp_equal", d_swift_kp_equal);

static uint64_t mix(uint64_t h, uint64_t v) {
    h ^= v + 0x9E3779B97F4A7C15ull + (h << 6) + (h >> 2);
    return h * 0xFF51AFD7ED558CCDull;
}

static intptr_t d_swift_kp_hash(const void *kp) {
    const struct kp_body *b = body_of(kp);
    uint64_t h = mix(mix((uintptr_t)b->root, (uintptr_t)b->leaf), b->n);
    for (uint32_t i = 0; i < b->n; i++) {
        const struct kp_comp *c = &b->c[i];
        h = mix(h, c->kind);
        if (c->kind == KC_STRUCT || c->kind == KC_CLASS) h = mix(h, c->offset);
        if (c->kind == KC_COMPUTED) {
            h = mix(h, c->id);
            if (c->args && c->wit) h = mix(h, (uint64_t)c->wit->hash(c->args, c->argsize));
            else if (c->args)
                for (size_t k = 0; k < c->argsize; k++) h = mix(h, ((const unsigned char *)c->args)[k]);
        }
    }
    return (intptr_t)h;
}
DX_EXPORT("__swift_kp_hash", d_swift_kp_hash);

static void d_swift_kp_types(const void *kp, const sw_metadata **root, const sw_metadata **leaf) {
    const struct kp_body *b = body_of(kp);
    *root = b->root;
    *leaf = b->leaf;
}
DX_EXPORT("__swift_kp_types", d_swift_kp_types);

static const char *d_swift_kp_kvc_string(const void *kp) { return body_of(kp)->kvc; }
DX_EXPORT("__swift_kp_kvc_string", d_swift_kp_kvc_string);

static void copy_args(struct kp_comp *c, char **cursor) {
    if (!c->args) return;
    const void *src = c->args;
    c->args = aligned_area(cursor, c->argsize, 15);
    if (c->wit) c->wit->copy(src, c->args, c->argsize);
    else memcpy(c->args, src, c->argsize);
}

/* A new key path of class `cls` (+1): `root`'s components, then `leaf`'s. */
static void *d_swift_kp_append(const void *kroot, const void *kleaf, const sw_metadata *cls) {
    const struct kp_body *a = body_of(kroot), *z = body_of(kleaf);
    uint32_t n = a->n + z->n;
    size_t extra = 0;
    for (uint32_t i = 0; i < a->n; i++) extra += a->c[i].argsize + 32;
    for (uint32_t i = 0; i < z->n; i++) extra += z->c[i].argsize + 32;
    if (a->kvc && z->kvc) extra += strlen(a->kvc) + strlen(z->kvc) + 2;
    struct kp_body *b;
    void *obj = kp_alloc(cls, n, extra, &b);
    b->root = a->root;
    b->leaf = z->leaf;
    memcpy(b->c, a->c, a->n * sizeof *b->c);
    memcpy(b->c + a->n, z->c, z->n * sizeof *b->c);
    char *cursor = (char *)&b->c[n];
    for (uint32_t i = 0; i < n; i++) copy_args(&b->c[i], &cursor);
    if (a->kvc && z->kvc) b->kvc = kvc_copy(&cursor, a->kvc, z->kvc);
    classify(b);
    return obj;
}
DX_EXPORT("__swift_kp_append", d_swift_kp_append);

/* ---- projection ----------------------------------------------------------------- */
/* An access in progress: temporaries holding computed values (destroyed at
 * the end) and the computed components to write back (in reverse). */
struct temp {
    sw_opaque *p;
    const sw_metadata *type; /* NULL until initialised */
};
struct wb {
    const struct kp_comp *c;
    sw_opaque *base, *value;
};
struct access {
    unsigned ntemps, nwb;
    struct temp *temps;
    struct wb *wb;
};

static struct access *access_new(const struct kp_body *b) {
    unsigned n = b->n + 2;
    struct access *s = calloc(1, sizeof *s + n * (sizeof(struct temp) + sizeof(struct wb)));
    s->temps = (struct temp *)(s + 1);
    s->wb = (struct wb *)(s->temps + n);
    return s;
}

static sw_opaque *temp_new(struct access *s, const sw_metadata *type) {
    const sw_vwt *w = sw_vwt_of(type);
    size_t align = (w->flags & SW_VW_ALIGNMENT_MASK) + 1;
    size_t size = w->size ? w->size : 1;
    void *p = align > 16 ? aligned_alloc(align, (size + align - 1) & ~(align - 1)) : malloc(size);
    s->temps[s->ntemps++] = (struct temp){p, NULL};
    return p;
}
static void temp_initialized(struct access *s, const sw_metadata *type) {
    s->temps[s->ntemps - 1].type = type;
}

static void access_end(struct access *s, int write_back) {
    if (write_back)
        for (unsigned i = s->nwb; i-- > 0;) {
            const struct kp_comp *c = s->wb[i].c;
            ((kp_setter_fn)c->setter)(s->wb[i].value, s->wb[i].base, c->args, c->argsize);
        }
    for (unsigned i = s->ntemps; i-- > 0;) {
        if (s->temps[i].type) sw_vwt_of(s->temps[i].type)->destroy(s->temps[i].p, s->temps[i].type);
        free(s->temps[i].p);
    }
    free(s);
}

static int is_nil(const sw_opaque *v, const sw_metadata *payload) {
    return sw_vwt_of(payload)->getEnumTagSinglePayload(v, 1, payload) != 0;
}
static void check_not_nil(const sw_opaque *v, const sw_metadata *payload) {
    if (is_nil(v, payload))
        dx_fatal("Fatal error: Unexpectedly found nil while unwrapping an Optional value");
}

/* Reads through components [from, to) from *cur; 0 if an optional chain
 * found nil. */
static int project_read(const struct kp_body *b, struct access *s, uint32_t from, uint32_t to,
                        sw_opaque **cur) {
    sw_opaque *p = *cur;
    const sw_metadata *base = from ? b->c[from - 1].type : b->root;
    for (uint32_t i = from; i < to; i++) {
        const struct kp_comp *c = &b->c[i];
        switch (c->kind) {
        case KC_STRUCT:
            p = (sw_opaque *)((char *)p + c->offset);
            break;
        case KC_CLASS:
            p = (sw_opaque *)(*(char **)p + c->offset);
            break;
        case KC_COMPUTED: {
            sw_opaque *t = temp_new(s, c->type);
            sw_call_indirect(c->getter, t, p, c->args, (const void *)c->argsize);
            temp_initialized(s, c->type);
            p = t;
            break;
        }
        case KC_CHAIN:
            if (is_nil(p, c->type)) return 0;
            break;
        case KC_FORCE:
            check_not_nil(p, c->type);
            break;
        case KC_WRAP: {
            const sw_vwt *w = sw_vwt_of(base);
            sw_opaque *t = temp_new(s, c->type);
            w->initializeWithCopy(t, p, base);
            w->storeEnumTagSinglePayload(t, 0, 1, base);
            temp_initialized(s, c->type);
            p = t;
            break;
        }
        }
        base = c->type;
    }
    *cur = p;
    return 1;
}

/* Copies the value at the end of the path into out (uninitialised). */
static void kp_get(const sw_opaque *root, const void *kp, sw_opaque *out) {
    const struct kp_body *b = body_of(kp);
    struct access *s = access_new(b);
    sw_opaque *p = (sw_opaque *)root;
    if (project_read(b, s, 0, b->n, &p)) {
        sw_vwt_of(b->leaf)->initializeWithCopy(out, p, b->leaf);
    } else {
        /* an optional chain found nil: the leaf is Optional<Wrapped> */
        const sw_metadata *wrapped = sw_generic_args(b->leaf)[0];
        sw_vwt_of(wrapped)->storeEnumTagSinglePayload(out, 1, 1, wrapped);
    }
    access_end(s, 0);
}
static void d_swift_kp_get(const sw_opaque *root, const void *kp, sw_opaque *out) { kp_get(root, kp, out); }
DX_EXPORT("__swift_kp_get", d_swift_kp_get);

/* Starts a mutating access and returns the address of the value. The steps
 * up to the last one through a reference are only read: what they lead to
 * is shared, so nothing before it is written back. */
static sw_opaque *kp_begin_modify(sw_opaque *root, const void *kp, struct access **out) {
    const struct kp_body *b = body_of(kp);
    struct access *s = access_new(b);
    sw_opaque *p = root;
    uint32_t from = 0;
    if (b->refend >= 0) {
        from = (uint32_t)b->refend;
        project_read(b, s, 0, from, &p);
    }
    for (uint32_t i = from; i < b->n; i++) {
        const struct kp_comp *c = &b->c[i];
        switch (c->kind) {
        case KC_STRUCT:
            p = (sw_opaque *)((char *)p + c->offset);
            break;
        case KC_CLASS:
            p = (sw_opaque *)(*(char **)p + c->offset);
            break;
        case KC_COMPUTED: {
            if (!c->setter) dx_fatal("swift: key path: writing through a read-only property");
            sw_opaque *t = temp_new(s, c->type);
            sw_call_indirect(c->getter, t, p, c->args, (const void *)c->argsize);
            temp_initialized(s, c->type);
            s->wb[s->nwb++] = (struct wb){c, p, t};
            p = t;
            break;
        }
        case KC_FORCE:
            check_not_nil(p, c->type);
            break;
        default:
            dx_fatal("swift: key path: writing through an optional chain");
        }
    }
    *out = s;
    return p;
}

static sw_opaque *d_swift_kp_begin_modify(sw_opaque *root, const void *kp, struct access **token) {
    return kp_begin_modify(root, kp, token);
}
DX_EXPORT("__swift_kp_begin_modify", d_swift_kp_begin_modify);

static void d_swift_kp_end_access(struct access *token, _Bool write_back) { access_end(token, write_back); }
DX_EXPORT("__swift_kp_end_access", d_swift_kp_end_access);

/* The yield-once coroutines the compiler calls for `root[keyPath: kp]` as
 * an l-value or borrowed value: (buffer, root, keyPath, Root, Value) ->
 * (continuation, address of the value). The continuation takes (buffer,
 * isUnwind); the access lives in buffer[0]. */
typedef struct {
    void *cont;
    sw_opaque *addr;
} kp_yield;

static void modify_continue(void **buffer, _Bool unwind) { access_end(buffer[0], !unwind); }
static void read_continue(void **buffer, _Bool unwind) {
    (void)unwind;
    access_end(buffer[0], 0);
}

static kp_yield d_swift_readAtKeyPath(void **buffer, const sw_opaque *root, const void *kp,
                                      const sw_metadata *R, const sw_metadata *V) {
    (void)R;
    struct access *s = access_new(body_of(kp));
    sw_opaque *t = temp_new(s, V);
    kp_get(root, kp, t);
    temp_initialized(s, V);
    buffer[0] = s;
    return (kp_yield){(void *)read_continue, t};
}
DX_FN(swift_readAtKeyPath);

static kp_yield d_swift_modifyAtWritableKeyPath(void **buffer, sw_opaque *root, const void *kp,
                                                const sw_metadata *R, const sw_metadata *V) {
    (void)R, (void)V;
    struct access *s;
    sw_opaque *p = kp_begin_modify(root, kp, &s);
    buffer[0] = s;
    return (kp_yield){(void *)modify_continue, p};
}
DX_FN(swift_modifyAtWritableKeyPath);
DX_EXPORT("_swift_modifyAtReferenceWritableKeyPath", d_swift_modifyAtWritableKeyPath);
