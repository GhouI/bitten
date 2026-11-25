/* Contracts between the parts of bitten's Swift runtime (src/frameworks/swift).
 *
 *   images.c     __swift5_* sections of every loaded image
 *   heap.c       objects, reference counts, boxes, weak/unowned, once, access
 *   objc.c       SwiftObject root class, unknown/bridge objects, ObjC metadata
 *   metadata.c   value witnesses, struct/enum/class/tuple/function metadata,
 *                singleton and generic instantiation
 *   demangle.c   mangled type names -> metadata
 *   protocols.c  conformance lookup, witness tables, dynamic casts
 *
 * Exported entry points use the Swift runtime's own names (DX_EXPORT with the
 * Mach-O underscore). Helpers shared between files are prefixed sw_. */
#ifndef BITTEN_SWIFT_INTERNAL_H
#define BITTEN_SWIFT_INTERNAL_H
#include "dx.h"
#include "swift_abi.h"

/* ---- images.c ------------------------------------------------------------ */
struct sw_section {
    const void *start;
    size_t size;
};
enum {
    SW_SECT_TYPES,    /* __swift5_types: int32 relative refs to type descriptors (low 2 bits: kind) */
    SW_SECT_TYPES2,   /* __swift5_types2 */
    SW_SECT_PROTO,    /* __swift5_proto: int32 relative refs to conformance descriptors */
    SW_SECT_PROTOS,   /* __swift5_protos: int32 relative refs to protocol descriptors */
    SW_SECT_FIELDMD,  /* __swift5_fieldmd: field descriptors, packed */
    SW_SECT_ASSOCTY,
    SW_SECT_BUILTIN,
    SW_SECT_CAPTURE,
    SW_SECT_TYPEREF,
    SW_SECT_REFLSTR,
    SW_SECT_MPENUM,
    SW_SECT_COUNT
};
/* Calls cb for the section `which` of every image loaded so far, and (when
 * `future` is set) for every image loaded later, as it is loaded. */
typedef void (*sw_section_cb)(const struct sw_section *s, void *ctx);
void sw_each_section(int which, sw_section_cb cb, void *ctx, int future);

/* ---- callconv.S ------------------------------------------------------------ */
/* Calls fn with `self` in r13 (and rdi): heap object destroyers
 * (metadata[-2]) and class ivar destroyers are swiftcc functions taking
 * the object as self. */
void sw_call_with_self(const void *fn, void *self);

/* ---- heap.c --------------------------------------------------------------- */
sw_heap_object *sw_alloc_object(const sw_metadata *m, size_t size, size_t align_mask);
sw_heap_object *sw_retain(sw_heap_object *o);
void sw_release(sw_heap_object *o);
int sw_is_deiniting(const sw_heap_object *o);
size_t sw_retain_count(const sw_heap_object *o);
sw_heap_object *sw_retain_n(sw_heap_object *o, uint32_t n);
void sw_release_n(sw_heap_object *o, uint32_t n);
int sw_try_retain(sw_heap_object *o); /* fails once deinit has started */
void sw_set_deallocating(sw_heap_object *o);
void sw_unowned_retain_n(sw_heap_object *o, uint32_t n);
void sw_unowned_release_n(sw_heap_object *o, uint32_t n);
/* Runs the destroyer of an object whose deinit has been decided on. */
void sw_destroy(sw_heap_object *o);

/* ---- objc.c ----------------------------------------------------------------- */
/* Nonzero if obj is a native Swift object (its class descends from
 * SwiftObject and uses Swift reference counting). */
int sw_is_native(const void *obj);
extern struct sw_class_metadata sw_SwiftObject_class; /* _TtCs12_SwiftObject */
/* swift_unknownObjectRetain/Release and swift_bridgeObjectRetain/Release. */
void *sw_unknown_retain(void *obj);
void sw_unknown_release(void *obj);
void *sw_bridge_retain(void *bits);
void sw_bridge_release(void *bits);

/* ---- metadata.c -------------------------------------------------------------- */
/* Value witness tables of the builtin types, exported as $sB*WV. The
 * reference types' tables ($sBoWV, $sBOWV, $sBbWV) and the closure one
 * ($syycWV) are defined in heap.c. */
extern const sw_vwt sw_vwt_pod8, sw_vwt_native_object, sw_vwt_unknown_object, sw_vwt_bridge_object;
extern const sw_vwt sw_vwt_thick_closure; /* $syycWV, heap.c */
const sw_metadata *sw_get_tuple_metadata(size_t n, const sw_metadata *const *elements,
                                     const char *labels);
const sw_metadata *sw_get_metatype_metadata(const sw_metadata *instance);
const sw_metadata *sw_get_generic_metadata(const sw_type_context_descriptor *desc,
                                           const void *const *arguments);
/* Number of key arguments of a generic type descriptor (0 if not generic). */
unsigned sw_generic_key_argument_count(const sw_type_context_descriptor *desc);
/* The descriptor's name, e.g. "Pair"; `qualified` writes "Module.Outer.Pair". */
const char *sw_descriptor_name(const sw_type_context_descriptor *desc);
void sw_descriptor_qualified_name(const sw_context_descriptor *desc, char *buf, size_t len);

/* ---- demangle.c ---------------------------------------------------------------- */
/* Resolves a mangled type name (possibly with symbolic references) in the
 * environment of generic arguments `args` of context `ctx`. NULL if unknown. */
const sw_metadata *sw_type_by_mangled_name(const char *name, size_t len,
                                           const sw_context_descriptor *ctx,
                                           const void *const *args);

/* ---- protocols.c ----------------------------------------------------------------- */
const sw_witness_table *sw_conforms_to(const sw_metadata *type, const sw_protocol_descriptor *proto);

#endif
