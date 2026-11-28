/* Reflection for Mirror: the stored properties of structs and classes and
 * the elements of tuples, from the field descriptors and field offsets the
 * compiler emits. The standard library's Mirror (stdlib/Mirror.swift) calls
 * these private entry points and builds `Any` values from the address and
 * type they return. An enum's case comes from its tag; the payload of a
 * single-payload enum's payload case is reflected (it sits unchanged at the
 * start of the value), a multi-payload enum's is not yet. */
#include <stdlib.h>
#include <string.h>

#include "swift_internal.h"

/* 's' struct, 'c' class, 'e' enum, 'o' optional, 't' tuple, '\0' other. */
static int d__bitten_mirror_display_style(const sw_metadata *type) {
    switch (sw_kind(type)) {
    case SW_KIND_STRUCT: return 's';
    case SW_KIND_ENUM: return 'e';
    case SW_KIND_OPTIONAL: return 'o';
    case SW_KIND_TUPLE: return 't';
    case SW_KIND_FOREIGN_CLASS:
    case SW_KIND_OBJC_CLASS_WRAPPER: return 'c';
    default: return sw_kind(type) == SW_KIND_CLASS || sw_kind(type) > 0x7FF ? 'c' : 0;
    }
}
DX_FN(_bitten_mirror_display_style);

static const sw_field_descriptor *fields_of(const sw_metadata *type) {
    const sw_type_context_descriptor *d = sw_type_descriptor(type);
    return d ? sw_rel(&d->fields) : NULL;
}

static int is_swift_class(const sw_metadata *type) {
    uintptr_t k = sw_kind(type);
    if (k != SW_KIND_CLASS && k <= 0x7FF) return 0;
    return sw_class_is_swift((const sw_class_metadata *)type);
}

/* An enum value's case: its field record (records are in tag order,
 * payload cases first), or NULL. */
static const sw_field_record *enum_case(const void *value, const sw_metadata *type) {
    if (sw_kind(type) != SW_KIND_ENUM) return NULL;
    const sw_vwt *w = sw_vwt_of(type);
    if (!(w->flags & SW_VW_HAS_ENUM_WITNESSES)) return NULL;
    const sw_field_descriptor *fd = fields_of(type);
    if (!fd) return NULL;
    unsigned tag = ((const sw_enum_vwt *)w)->getEnumTag(value, type);
    if (tag >= fd->num_fields) return NULL;
    return (const sw_field_record *)((const char *)fd->fields + (size_t)tag * fd->field_record_size);
}

/* The name of the case an enum value is in (print and Mirror show it). */
static const char *d__bitten_enum_case_name(const void *value, const sw_metadata *type) {
    const sw_field_record *r = enum_case(value, type);
    return r ? sw_rel(&r->field_name) : NULL;
}
DX_FN(_bitten_enum_case_name);

/* The payload's type when it can be read in place: a direct (not
 * indirect) payload case of an enum with a single payload case. */
static const sw_metadata *enum_payload_type(const void *value, const sw_metadata *type) {
    const sw_field_record *r = enum_case(value, type);
    const sw_field_descriptor *fd = fields_of(type);
    if (!r || !fd || fd->kind != 2 || (r->flags & 1)) return NULL;
    const char *mangled = sw_rel(&r->mangled_type);
    if (!mangled) return NULL;
    const sw_type_context_descriptor *ctx = sw_type_descriptor(type);
    return sw_type_by_mangled_name(mangled, sw_mangled_name_length(mangled), (const sw_context_descriptor *)ctx,
                                   sw_generic_args(type));
}

/* Any enum's payload, for Mirror: the value is copied into a fresh buffer
 * and its tag taken off there (destructiveProjectEnumData), leaving the
 * payload at the start, or for an indirect case a box holding it. Returns
 * the buffer and sets the payload's address and type; the caller reads the
 * payload, then hands the buffer to _bitten_enum_payload_free. NULL when
 * the case has no payload (or its type can't be resolved). */
static void *d__bitten_enum_payload_copy(const void *value, const sw_metadata *type, const void **payload,
                                         const sw_metadata **payload_type, intptr_t *indirect) {
    *payload = NULL;
    *payload_type = NULL;
    *indirect = 0;
    const sw_field_record *r = enum_case(value, type);
    if (!r) return NULL;
    const char *mangled = sw_rel(&r->mangled_type);
    if (!mangled) return NULL;
    const sw_type_context_descriptor *ctx = sw_type_descriptor(type);
    const sw_metadata *pt = sw_type_by_mangled_name(mangled, sw_mangled_name_length(mangled),
                                                    (const sw_context_descriptor *)ctx, sw_generic_args(type));
    if (!pt) return NULL;
    const sw_vwt *w = sw_vwt_of(type);
    size_t align = (w->flags & SW_VW_ALIGNMENT_MASK) + 1;
    void *buf = aligned_alloc(align < 16 ? 16 : align, w->size ? (w->size + 15) & ~(size_t)15 : 16);
    if (!buf) return NULL;
    w->initializeWithCopy((sw_opaque *)buf, (sw_opaque *)value, type);
    ((const sw_enum_vwt *)w)->destructiveProjectEnumData((sw_opaque *)buf, type);
    *indirect = r->flags & 1;
    if (r->flags & 1) {
        /* indirect: a box, the payload after its heap header */
        const char *box = *(const char *const *)buf;
        size_t palign = (sw_vwt_of(pt)->flags & SW_VW_ALIGNMENT_MASK) + 1;
        *payload = box + ((16 + palign - 1) & ~(palign - 1));
    } else {
        *payload = buf;
    }
    *payload_type = pt;
    return buf;
}
DX_FN(_bitten_enum_payload_copy);
/* Destroys the copied payload (or lets go of the box) and frees the buffer. */
static void d__bitten_enum_payload_free(void *buf, const sw_metadata *payload_type, intptr_t indirect) {
    if (!buf) return;
    if (indirect) sw_release_n(*(sw_heap_object **)buf, 1);
    else sw_vwt_of(payload_type)->destroy((sw_opaque *)buf, payload_type);
    free(buf);
}
DX_FN(_bitten_enum_payload_free);

static intptr_t d__bitten_mirror_count(const void *value, const sw_metadata *type) {
    switch (sw_kind(type)) {
    case SW_KIND_ENUM: {
        const sw_field_record *r = enum_case(value, type);
        return r && sw_rel(&r->mangled_type) ? 1 : 0;
    }
    case SW_KIND_TUPLE: return (intptr_t)((const sw_tuple_metadata *)type)->num_elements;
    case SW_KIND_STRUCT: {
        const sw_field_descriptor *fd = fields_of(type);
        return fd ? fd->num_fields : 0;
    }
    default:
        if (is_swift_class(type)) {
            const sw_field_descriptor *fd = fields_of(type);
            return fd ? fd->num_fields : 0;
        }
        return 0;
    }
}
DX_FN(_bitten_mirror_count);

/* The `index`th tuple label, copied into buf; NULL when unlabeled. */
static const char *tuple_label(const sw_tuple_metadata *t, intptr_t index, char *buf, size_t len) {
    const char *p = t->labels;
    if (!p) return NULL;
    for (intptr_t i = 0; i < index; i++) {
        p = strchr(p, ' ');
        if (!p) return NULL;
        p++;
    }
    const char *end = strchr(p, ' ');
    size_t n = end ? (size_t)(end - p) : strlen(p);
    if (n == 0 || n >= len) return NULL;
    memcpy(buf, p, n);
    buf[n] = 0;
    return buf;
}

/* The address of child `index` of the value at `value` (a struct, a tuple,
 * or a reference to a class instance), its name, and its type (NULL when
 * the field's type cannot be resolved). */
static const void *d__bitten_mirror_child(const void *value, const sw_metadata *type, intptr_t index,
                                          const char **name, const sw_metadata **child_type) {
    static __thread char label[256];
    *name = NULL;
    *child_type = NULL;
    if (sw_kind(type) == SW_KIND_TUPLE) {
        const sw_tuple_metadata *t = (const sw_tuple_metadata *)type;
        if (index < 0 || (size_t)index >= t->num_elements) return NULL;
        *name = tuple_label(t, index, label, sizeof label);
        *child_type = t->elements[index].type;
        return (const char *)value + t->elements[index].offset;
    }
    if (sw_kind(type) == SW_KIND_ENUM) {
        /* the payload, labelled with the case's name */
        const sw_metadata *pt = index == 0 ? enum_payload_type(value, type) : NULL;
        if (!pt) return NULL;
        *name = d__bitten_enum_case_name(value, type);
        *child_type = pt;
        return value;
    }
    const sw_field_descriptor *fd = fields_of(type);
    if (!fd || index < 0 || (uint32_t)index >= fd->num_fields) return NULL;
    const sw_field_record *r = (const sw_field_record *)((const char *)fd->fields + (size_t)index * fd->field_record_size);
    *name = sw_rel(&r->field_name);
    const char *mangled = sw_rel(&r->mangled_type);
    const sw_type_context_descriptor *ctx = sw_type_descriptor(type);
    if (mangled)
        *child_type = sw_type_by_mangled_name(mangled, sw_mangled_name_length(mangled),
                                              (const sw_context_descriptor *)ctx, sw_generic_args(type));
    if (sw_kind(type) == SW_KIND_STRUCT) {
        const sw_struct_descriptor *sd = (const sw_struct_descriptor *)ctx;
        const uint32_t *offsets = (const uint32_t *)((const void *const *)type + sd->field_offset_vector_offset);
        return (const char *)value + offsets[index];
    }
    /* A class: the value is a reference; offsets are words in the metadata. */
    const sw_class_metadata *c = (const sw_class_metadata *)type;
    const char *object = *(const char *const *)value;
    const uintptr_t *offsets = (const uintptr_t *)((const void *const *)c + sw_class_field_offsets_word(c->description));
    return object + offsets[index];
}
DX_FN(_bitten_mirror_child);
