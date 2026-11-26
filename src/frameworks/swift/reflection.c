/* Reflection for Mirror: the stored properties of structs and classes and
 * the elements of tuples, from the field descriptors and field offsets the
 * compiler emits. The standard library's Mirror (stdlib/Mirror.swift) calls
 * these private entry points and builds `Any` values from the address and
 * type they return. Enum payloads are not reflected yet. */
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

static intptr_t d__bitten_mirror_count(const void *value, const sw_metadata *type) {
    (void)value;
    switch (sw_kind(type)) {
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
