/* Swift class metadata: generic class instantiation, class layout and
 * Objective-C registration.
 *
 * Class metadata extends around its address point by bounds the descriptor
 * gives (or, with a superclass from another resilient module, bounds the
 * runtime computes and stores): words before it hold the layout string,
 * the destroy function and the value witnesses; after the Objective-C
 * class words and the Swift class header come, for each class from the root
 * down, its generic arguments, field offsets and vtable ("immediate
 * members"). A subclass copies its ancestors' members and then fills in its
 * own and its overrides.
 *
 * Every Swift class is an Objective-C class too. Generic instantiations get
 * their metaclass and class_ro from the pattern's extra data; once fields
 * are laid out, their class_ro gets the instance size, a name and an ivar
 * list whose offsets point into the field offset vector, and the class is
 * realised by our Objective-C runtime. */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "../objc/objc_internal.h"
#include "swift_internal.h"

/* ---- descriptor trailing objects ----------------------------------------------------- */
struct class_info {
    const int32_t *resilient_super; /* TargetResilientSuperclass, or NULL */
    const sw_vtable_header *vtable;
    const sw_method_descriptor *methods;
    uint32_t noverrides;
    const sw_method_override_descriptor *overrides;
};

static void class_info(const sw_class_descriptor *d, struct class_info *ci) {
    memset(ci, 0, sizeof *ci);
    uint32_t flags = d->base.flags, kf = sw_ctx_kind_flags(flags);
    const char *p = (const char *)d + sizeof *d;
    if (sw_ctx_is_generic(flags)) {
        const sw_type_generic_context_header *g = (const void *)p;
        if (g->base.flags)
            dx_fatal("swift: class %s: generic packs, values or conditional invertible "
                     "protocols are not supported", sw_descriptor_name(&d->base));
        p += sizeof *g + ((g->base.num_params + 3u) & ~3u) +
             g->base.num_requirements * sizeof(sw_generic_requirement);
    }
    if (kf & SW_CLASS_HAS_RESILIENT_SUPERCLASS) {
        ci->resilient_super = (const int32_t *)p;
        p += 4;
    }
    unsigned init = kf & SW_TYPE_METADATA_INIT_MASK;
    if (init == SW_TYPE_METADATA_INIT_FOREIGN) p += 4;
    if (init == SW_TYPE_METADATA_INIT_SINGLETON) p += sizeof(sw_singleton_metadata_initialization);
    if (kf & SW_CLASS_HAS_VTABLE) {
        ci->vtable = (const sw_vtable_header *)p;
        ci->methods = (const sw_method_descriptor *)(ci->vtable + 1);
        p = (const char *)(ci->methods + ci->vtable->size);
    }
    if (kf & SW_CLASS_HAS_OVERRIDE_TABLE) {
        ci->noverrides = *(const uint32_t *)p;
        ci->overrides = (const sw_method_override_descriptor *)(p + 4);
    }
}

/* ---- metadata bounds ------------------------------------------------------------------ */
struct bounds {
    intptr_t imm; /* bytes from the address point to the immediate members */
    uint32_t neg, pos;
};

/* A class whose superclass is not a Swift class starts from the bounds of
 * a root class: 3 header words, 10 words of class metadata. */
static const struct bounds root_bounds = {10 * 8, 3, 10};

static struct bounds class_bounds(const sw_class_descriptor *d);

/* The superclass descriptor named by a resilient superclass reference;
 * NULL for an Objective-C superclass. */
static const sw_class_descriptor *resilient_superclass(const sw_class_descriptor *d,
                                                       const int32_t *ref) {
    unsigned kind = (sw_ctx_kind_flags(d->base.flags) >> SW_CLASS_RESILIENT_SUPERCLASS_REF_KIND_SHIFT) & 7;
    const void *p = sw_rel(ref);
    if (kind == 0) return p;                           /* direct type descriptor */
    if (kind == 1) return p ? *(const void *const *)p : NULL; /* indirect */
    return NULL;                                       /* Objective-C class */
}

static struct bounds class_bounds(const sw_class_descriptor *d) {
    struct class_info ci;
    class_info(d, &ci);
    int negative = sw_ctx_kind_flags(d->base.flags) & SW_CLASS_ARE_IMMEDIATE_MEMBERS_NEGATIVE;
    if (!ci.resilient_super) {
        struct bounds b = {0, d->metadata_negative_size_in_words, d->metadata_positive_size_in_words};
        b.imm = negative ? -(intptr_t)b.neg * 8 : (intptr_t)(b.pos - d->num_immediate_members) * 8;
        return b;
    }
    sw_stored_class_bounds *st = (sw_stored_class_bounds *)sw_rel((const int32_t *)&d->metadata_negative_size_in_words);
    intptr_t imm = __atomic_load_n(&st->immediate_members_offset, __ATOMIC_ACQUIRE);
    if (imm) return (struct bounds){imm, st->negative_size_in_words, st->positive_size_in_words};
    const sw_class_descriptor *sd = resilient_superclass(d, ci.resilient_super);
    struct bounds b = sd ? class_bounds(sd) : root_bounds;
    if (negative) {
        b.neg += d->num_immediate_members;
        b.imm = -(intptr_t)b.neg * 8;
    } else {
        b.imm = (intptr_t)b.pos * 8;
        b.pos += d->num_immediate_members;
    }
    st->negative_size_in_words = b.neg;
    st->positive_size_in_words = b.pos;
    __atomic_store_n(&st->immediate_members_offset, b.imm, __ATOMIC_RELEASE);
    return b;
}

/* Word offsets of a class's members in its (and its subclasses') metadata. */
static size_t imm_word(const sw_class_descriptor *d) { return (size_t)(class_bounds(d).imm / 8); }
static size_t field_offsets_word(const sw_class_descriptor *d) {
    struct class_info ci;
    class_info(d, &ci);
    return d->field_offset_vector_offset + (ci.resilient_super ? imm_word(d) : 0);
}
size_t sw_class_field_offsets_word(const sw_class_descriptor *d) { return field_offsets_word(d); }
static size_t vtable_word(const sw_class_descriptor *d, const struct class_info *ci) {
    return ci->vtable->offset + (ci->resilient_super ? imm_word(d) : 0);
}

/* ---- generic class allocation --------------------------------------------------------- */
static const sw_partial_pattern *extra_pattern(const sw_generic_class_metadata_pattern *pat) {
    return (pat->base.flags & 1) ? (const sw_partial_pattern *)(pat + 1) : NULL;
}
static const sw_partial_pattern *immediate_pattern(const sw_generic_class_metadata_pattern *pat) {
    if (!(pat->base.flags & 0x80000000u)) return NULL;
    return (const sw_partial_pattern *)(pat + 1) + ((pat->base.flags & 1) ? 1 : 0);
}

static void *empty_cache(void) {
    static void *c;
    if (!c) c = dx_registry_lookup("__objc_empty_cache");
    return c;
}

/* ClassMetadata *swift_allocateGenericClassMetadata(const ClassDescriptor *,
 *     const void *arguments, const GenericClassMetadataPattern *) */
static sw_class_metadata *d_swift_allocateGenericClassMetadata(const sw_class_descriptor *desc,
                                                               const void *const *args,
                                                               const sw_generic_class_metadata_pattern *pat) {
    struct bounds b = class_bounds(desc);
    const sw_partial_pattern *xp = extra_pattern(pat), *ip = immediate_pattern(pat);
    size_t extra = xp ? xp->offset_in_words + xp->size_in_words : 0;
    void **full = calloc(b.neg + b.pos + extra, sizeof(void *));
    void **words = full + b.neg;
    sw_class_metadata *m = (sw_class_metadata *)words;
    void **xd = words + b.pos;
    if (xp) memcpy(xd + xp->offset_in_words, sw_rel(&xp->pattern), xp->size_in_words * sizeof(void *));
    char *imm = (char *)m + b.imm;
    if (ip) memcpy(imm + ip->offset_in_words * 8, sw_rel(&ip->pattern), ip->size_in_words * sizeof(void *));

    words[-2] = (void *)sw_rel(&pat->destroy);
    words[-1] = (void *)&sw_vwt_unknown_object;
    struct objc_class *meta = (struct objc_class *)(xd + pat->metaclass_offset);
    meta->bits = (uintptr_t)(xd + pat->metaclass_ro_offset);
    meta->cache = empty_cache();
    m->isa = (const sw_class_metadata *)meta;
    m->superclass = NULL;
    m->cache_data[0] = empty_cache();
    m->cache_data[1] = NULL;
    m->data = (uintptr_t)(xd + pat->class_ro_offset) | 2;
    m->flags = pat->class_flags;
    m->instance_address_point = 0;
    m->instance_size = 0;
    m->instance_align_mask = 0;
    m->reserved = 0;
    m->class_size = (b.neg + b.pos) * 8;
    m->class_address_point = b.neg * 8;
    m->description = desc;
    m->ivar_destroyer = (sw_ivar_destroyer)sw_rel(&pat->ivar_destroyer);
    memcpy(imm, args, sw_generic_key_argument_count(&desc->base) * sizeof(void *));
    return m;
}
DX_FN(swift_allocateGenericClassMetadata);

/* ---- classes with a resilient superclass ------------------------------------------------
 * Their metadata's size depends on the superclass, so the image holds a
 * pattern and the runtime allocates the metadata (the pattern's relocation
 * function calls swift_relocateClassMetadata). The completion function
 * then fills in the superclass, layout and vtable as for any class. */
typedef struct {
    int32_t relocation_function; /* -> Metadata *(desc, pattern) */
    int32_t destroy;
    int32_t ivar_destroyer;
    uint32_t flags;
    int32_t data;      /* -> class_ro_t */
    int32_t metaclass; /* -> the metaclass object */
} sw_resilient_class_pattern;

static sw_class_metadata *d_swift_relocateClassMetadata(const sw_class_descriptor *desc,
                                                        const sw_resilient_class_pattern *pat) {
    struct bounds b = class_bounds(desc);
    void **full = calloc(b.neg + b.pos, sizeof(void *));
    void **words = full + b.neg;
    sw_class_metadata *m = (sw_class_metadata *)words;
    words[-2] = (void *)sw_rel(&pat->destroy);
    words[-1] = (void *)&sw_vwt_unknown_object;
    m->isa = (const sw_class_metadata *)sw_rel(&pat->metaclass);
    m->superclass = NULL;
    m->cache_data[0] = empty_cache();
    m->cache_data[1] = NULL;
    m->data = (uintptr_t)sw_rel(&pat->data) | 2; /* the "Swift class" bit */
    m->flags = pat->flags;
    m->class_size = (b.neg + b.pos) * 8;
    m->class_address_point = b.neg * 8;
    m->description = desc;
    m->ivar_destroyer = (sw_ivar_destroyer)sw_rel(&pat->ivar_destroyer);
    return m;
}
DX_FN(swift_relocateClassMetadata);

/* The incomplete metadata of a class with a resilient superclass, made
 * from its pattern by the pattern's relocation function. */
const sw_metadata *sw_relocate_class(const sw_class_descriptor *desc, const void *pattern) {
    const sw_resilient_class_pattern *pat = pattern;
    typedef const sw_metadata *(*relocator)(const sw_class_descriptor *, const void *);
    relocator fn = (relocator)sw_rel(&pat->relocation_function);
    if (fn) return fn(desc, pattern);
    return (const sw_metadata *)d_swift_relocateClassMetadata(desc, pat);
}

/* ---- initialisation --------------------------------------------------------------------- */

static int is_swift_class(const sw_class_metadata *c) {
    return c && c != &sw_SwiftObject_class && sw_class_is_swift(c) && c->description;
}

/* Copies each Swift ancestor's generic arguments, field offsets and vtable
 * into the subclass: the subclass's own code reads them at the ancestor's
 * offsets. */
static void copy_superclass_members(sw_class_metadata *self, uintptr_t layout_flags) {
    uintptr_t *dst = (uintptr_t *)self;
    /* Everything comes from the immediate superclass, which already holds its
     * ancestors' members with its own overrides applied (copying each
     * ancestor's vtable from that ancestor would lose those overrides). */
    const uintptr_t *src = (const uintptr_t *)self->superclass;
    for (const sw_class_metadata *a = self->superclass; is_swift_class(a); a = a->superclass) {
        const sw_class_descriptor *d = a->description;
        unsigned nargs = sw_generic_key_argument_count(&d->base);
        if (nargs) {
            size_t at = imm_word(d);
            memcpy(dst + at, src + at, nargs * sizeof *dst);
        }
        struct class_info ci;
        class_info(d, &ci);
        if (ci.vtable && !(layout_flags & SW_CLASS_LAYOUT_HAS_STATIC_VTABLE)) {
            size_t at = vtable_word(d, &ci);
            memcpy(dst + at, src + at, ci.vtable->size * sizeof *dst);
        }
        if (d->field_offset_vector_offset) {
            size_t at = field_offsets_word(d);
            memcpy(dst + at, src + at, d->num_fields * sizeof *dst);
        }
    }
}

/* The class's own vtable entries, then its overrides of ancestors' entries. */
static void init_vtable(sw_class_metadata *self) {
    void **words = (void **)self;
    const sw_class_descriptor *d = self->description;
    struct class_info ci;
    class_info(d, &ci);
    if (ci.vtable) {
        size_t at = vtable_word(d, &ci);
        for (uint32_t i = 0; i < ci.vtable->size; i++)
            words[at + i] = (void *)sw_rel(&ci.methods[i].impl);
    }
    for (uint32_t i = 0; i < ci.noverrides; i++) {
        const sw_method_override_descriptor *o = &ci.overrides[i];
        const sw_class_descriptor *base = sw_rel_indirect(&o->cls);
        const sw_method_descriptor *method = sw_rel_indirect(&o->method);
        if (!base || !method) continue; /* weakly linked and absent */
        struct class_info bi;
        class_info(base, &bi);
        if (!bi.vtable || method < bi.methods || method >= bi.methods + bi.vtable->size)
            dx_fatal("swift: class %s overrides a method outside %s's vtable",
                     sw_descriptor_name(&d->base), sw_descriptor_name(&base->base));
        words[vtable_word(base, &bi) + (size_t)(method - bi.methods)] = (void *)sw_rel(&o->impl);
    }
}

/* The implementation of a vtable method in a class: what a resilient
 * class's method lookup function (`CMu`) returns for a method descriptor. */
static void *d_swift_lookUpClassMethod(const sw_class_metadata *self, const sw_method_descriptor *method,
                                       const sw_class_descriptor *d) {
    struct class_info ci;
    class_info(d, &ci);
    if (!ci.vtable || method < ci.methods || method >= ci.methods + ci.vtable->size)
        dx_fatal("swift: method lookup outside the vtable of %s", sw_descriptor_name(&d->base));
    return ((void *const *)self)[vtable_word(d, &ci) + (size_t)(method - ci.methods)];
}
DX_FN(swift_lookUpClassMethod);

/* Lays out the class's stored properties after its superclass's. */
static void layout_fields(sw_class_metadata *self, size_t n, const sw_type_layout *const *fields,
                          size_t *offsets) {
    size_t size = sizeof(sw_heap_object), am = 7;
    const sw_class_metadata *super = self->superclass;
    if (is_swift_class(super)) {
        size = super->instance_size;
        am = super->instance_align_mask;
    } else if (super) {
        pthread_mutex_lock(&dx_objc_lock);
        realize_class((Class)super);
        size = RW((Class)super)->instance_size;
        pthread_mutex_unlock(&dx_objc_lock);
    }
    for (size_t i = 0; i < n; i++) {
        const sw_type_layout *f = fields[i];
        if (offsets[i] == 0 && f->size == 0) continue; /* empty fields keep offset 0 */
        size_t fam = f->flags & SW_VW_ALIGNMENT_MASK;
        size = (size + fam) & ~fam;
        offsets[i] = size;
        size += f->size;
        if (fam > am) am = fam;
    }
    self->instance_size = (uint32_t)size;
    self->instance_align_mask = (uint16_t)am;
}

static unsigned log2_of_mask(size_t am) {
    unsigned l = 0;
    while ((1ul << l) <= am) l++;
    return l;
}

/* Gives the Objective-C side the computed layout and realises the class:
 * instance start/size in class_ro, ivar offsets pointing at the field
 * offset vector (field offset globals updated too), a name for generic
 * instantiations, the metaclass chain. */
static void register_objc(sw_class_metadata *self, size_t n, const sw_type_layout *const *fields,
                          size_t *offsets) {
    Class cls = (Class)self, meta = (Class)self->isa;
    const sw_class_metadata *super = self->superclass;
    pthread_mutex_lock(&dx_objc_lock);
    if (meta && !meta->superclass && super) meta->superclass = super->isa ? (Class)super->isa : NULL;
    if (meta && !meta->cache) meta->cache = empty_cache();
    if (!self->cache_data[0]) self->cache_data[0] = empty_cache();
    if (!class_realized(cls)) {
        struct class_ro *ro = (struct class_ro *)(self->data & CLASS_DATA_MASK);
        uint32_t start = sizeof(sw_heap_object);
        if (is_swift_class(super)) start = super->instance_size;
        else if (super) start = RW((Class)super)->instance_size;
        ro->instance_start = start;
        ro->instance_size = self->instance_size;
        if (!ro->name) {
            char *name = strdup(sw_type_name((const sw_metadata *)self, 1));
            ro->name = name;
            if (meta && !class_realized(meta)) {
                struct class_ro *mro = (struct class_ro *)(meta->bits & CLASS_DATA_MASK);
                if (mro && !mro->name) mro->name = name;
            }
        }
        if (ro->ivars && n) {
            const struct ivar_list *old = ro->ivars;
            size_t sz = sizeof *old + (old->count ? old->count - 1 : 0) * old->entsize;
            struct ivar_list *iv = malloc(sz);
            memcpy(iv, old, sz);
            for (size_t i = 0; i < n && i < iv->count; i++) {
                struct ivar *v = (struct ivar *)((char *)&iv->first + i * iv->entsize);
                /* The field offset global is constant (read-only) when the
                 * compiler knew the offset; write it only if it is wrong. */
                if (v->offset && *(size_t *)v->offset != offsets[i]) *(size_t *)v->offset = offsets[i];
                v->offset = (int32_t *)&offsets[i];                 /* little-endian low half */
                if (v->size != fields[i]->size) {
                    v->size = (uint32_t)fields[i]->size;
                    v->type = NULL;
                    v->alignment_raw = log2_of_mask(fields[i]->flags & SW_VW_ALIGNMENT_MASK);
                }
            }
            ro->ivars = iv;
        }
    } else {
        RW(cls)->instance_size = self->instance_size;
    }
    realize_class(cls);
    pthread_mutex_unlock(&dx_objc_lock);
}

static const sw_metadata *resolve_superclass(sw_class_metadata *self) {
    const sw_class_descriptor *d = self->description;
    const char *name = sw_rel(&d->superclass_type);
    if (!name) return (const sw_metadata *)&sw_SwiftObject_class; /* Swift root classes */
    const sw_metadata *m = sw_type_by_mangled_name(name, sw_mangled_name_length(name),
                                                   (const sw_context_descriptor *)d,
                                                   sw_generic_args((const sw_metadata *)self));
    if (!m) dx_fatal("swift: cannot resolve the superclass of %s", sw_descriptor_name(&d->base));
    return sw_class_of_metadata(m);
}

/* MetadataDependency swift_initClassMetadata2(ClassMetadata *self,
 *     ClassLayoutFlags, size_t numFields, const TypeLayout *const *fieldTypes,
 *     size_t *fieldOffsets) */
static sw_response d_swift_initClassMetadata2(sw_class_metadata *self, uintptr_t flags, size_t n,
                                              const sw_type_layout *const *fields, size_t *offsets) {
    self->superclass = (const sw_class_metadata *)resolve_superclass(self);
    if (!((const void **)self)[-1]) ((const void **)self)[-1] = &sw_vwt_unknown_object;
    copy_superclass_members(self, flags);
    if (!(flags & SW_CLASS_LAYOUT_HAS_STATIC_VTABLE)) init_vtable(self);
    layout_fields(self, n, fields, offsets);
    register_objc(self, n, fields, offsets);
    return (sw_response){NULL, 0};
}
DX_FN(swift_initClassMetadata2);

/* void swift_initClassMetadata(...): the pre-5.4 entry point, same work. */
static void d_swift_initClassMetadata(sw_class_metadata *self, uintptr_t flags, size_t n,
                                      const sw_type_layout *const *fields, size_t *offsets) {
    d_swift_initClassMetadata2(self, flags, n, fields, offsets);
}
DX_FN(swift_initClassMetadata);

/* MetadataDependency swift_updateClassMetadata2(...): a class whose
 * metadata is otherwise static (superclass, vtable) but whose field layout
 * depends on resilient types. */
static sw_response d_swift_updateClassMetadata2(sw_class_metadata *self, uintptr_t flags, size_t n,
                                                const sw_type_layout *const *fields,
                                                size_t *offsets) {
    if (!self->superclass) self->superclass = (const sw_class_metadata *)resolve_superclass(self);
    if (!((const void **)self)[-1]) ((const void **)self)[-1] = &sw_vwt_unknown_object;
    layout_fields(self, n, fields, offsets);
    register_objc(self, n, fields, offsets);
    return (sw_response){NULL, 0};
}
DX_FN(swift_updateClassMetadata2);

static void d_swift_updateClassMetadata(sw_class_metadata *self, uintptr_t flags, size_t n,
                                        const sw_type_layout *const *fields, size_t *offsets) {
    d_swift_updateClassMetadata2(self, flags, n, fields, offsets);
}
DX_FN(swift_updateClassMetadata);

