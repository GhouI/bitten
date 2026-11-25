/* Contracts between the parts of bitten's Swift runtime (src/frameworks/swift).
 *
 *   images.c     __swift5_* sections of every loaded image
 *   heap.c       objects, reference counts, boxes, weak/unowned, once, access
 *   objc.c       SwiftObject root class, unknown/bridge objects, ObjC metadata
 *   metadata.c   value witnesses, struct/enum/class/tuple/function metadata,
 *                singleton and generic instantiation
 *   demangle.c   mangled type names -> metadata, generic environments, type names
 *   protocols.c  conformance lookup, witness tables, associated types
 *   casts.c      dynamic casts
 *   errors.c     error boxes, throwing hooks, fatal error reports
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
/* array.c: gives the empty-array storage its class once libswiftCore loads */
void sw_array_image_added(struct dx_image *img);
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

/* ---- metadata.c, generic.c, enum.c, tuple.c ----------------------------------- */
/* Value witness tables of the builtin types, exported as $sB*WV. The
 * reference types' tables ($sBoWV, $sBOWV, $sBbWV) and the closure one
 * ($syycWV) are defined in heap.c. */
extern const sw_vwt sw_vwt_pod8, sw_vwt_empty, sw_vwt_native_object, sw_vwt_unknown_object,
    sw_vwt_bridge_object;
extern const sw_vwt sw_vwt_thick_closure; /* $syycWV, heap.c */
extern const sw_metadata *const sw_empty_tuple_metadata; /* $sytN */
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

/* Descriptor trailing objects. */
size_t sw_type_descriptor_size(const sw_type_context_descriptor *desc);
const sw_type_generic_context_header *sw_type_generic_header(const sw_type_context_descriptor *desc);
const sw_singleton_metadata_initialization *sw_singleton_init(const sw_type_context_descriptor *desc);

/* Metadata built by the runtime and its completion state. */
struct sw_md_entry {
    const sw_metadata *metadata;
    sw_completion_fn complete;    /* NULL: complete once allocated */
    const void *pattern;          /* passed to `complete` */
    void *context[4];             /* MetadataCompletionContext, kept across retries */
    const sw_metadata **published; /* set to `metadata` once complete (singleton caches) */
    uintptr_t state;              /* SW_STATE_* */
    int busy;                     /* its completion function is running */
};
void sw_md_lock(void);
void sw_md_unlock(void);
struct sw_md_entry *sw_md_entry_new(const sw_metadata *m, sw_completion_fn complete,
                                    const void *pattern);
/* Completes `e` up to state `want`; returns the state reached. */
uintptr_t sw_md_complete(struct sw_md_entry *e, uintptr_t want);

/* Layout helpers shared by struct, enum and tuple layout. */
void sw_basic_layout(sw_type_layout *out, size_t n, const sw_type_layout *const *fields,
                     uint32_t *offsets);
sw_vwt *sw_mutable_vwt(sw_metadata *m, uintptr_t layout_flags);
void sw_publish_layout(sw_vwt *w, const sw_type_layout *l);
sw_opaque *sw_vw_initialize_buffer_with_copy(sw_value_buffer *dst, sw_value_buffer *src,
                                             const sw_metadata *m);
/* Single-payload enum tags in terms of the payload's extra inhabitants
 * (swift_{get,store}EnumTagSinglePayloadGeneric). */
unsigned sw_get_enum_tag_single_payload(const sw_opaque *v, unsigned empty_cases,
                                        const sw_metadata *payload, sw_xi_get_fn get);
void sw_store_enum_tag_single_payload(sw_opaque *v, unsigned which, unsigned empty_cases,
                                      const sw_metadata *payload, sw_xi_store_fn store);

/* ---- demangle.c ---------------------------------------------------------------- */
/* A generic environment: what the generic parameters of a mangled name
 * (x, q_, qd__, ...) stand for. Built from a context descriptor's generic
 * signature (sw_env_init) and then given the arguments either as the
 * context's key arguments (`args`: key parameters, then the witness tables
 * of key protocol requirements, as metadata and accessors lay them out) or
 * as every parameter in order (`flat`). */
struct sw_env {
    const sw_context_descriptor *ctx;
    unsigned nlevels;
    uint16_t levels[16]; /* cumulative parameter count per depth */
    unsigned nparams;
    const uint8_t *params; /* SW_GP_* per parameter */
    unsigned nreqs;
    const sw_generic_requirement *reqs;
    const void *const *args;
    const sw_metadata *const *flat;
    /* Protocol context (names in witness tables prefixed by 0xFF): Self,
     * i.e. generic parameter (0, 0), and its witness table. */
    const sw_metadata *self;
    const sw_witness_table *self_wt;
};
void sw_env_init(struct sw_env *e, const sw_context_descriptor *ctx, const void *const *args);
const sw_metadata *sw_type_in_env(const char *name, size_t len, const struct sw_env *e);
/* Resolves a mangled type name (possibly with symbolic references) in the
 * environment of generic arguments `args` of context `ctx`. NULL if unknown;
 * with BITTEN_DEBUG set, the reason is logged. */
const sw_metadata *sw_type_by_mangled_name(const char *name, size_t len,
                                           const sw_context_descriptor *ctx,
                                           const void *const *args);
/* Length of a NUL-terminated mangled name (symbolic references may contain 0 bytes). */
size_t sw_mangled_name_length(const char *name);
/* Checks generic requirements in an environment; the witness tables of key
 * protocol requirements are appended to key_out[*nkey]. 0 if satisfied. */
int sw_check_requirements(const sw_generic_requirement *reqs, unsigned n, const struct sw_env *e,
                          const void **key_out, unsigned *nkey);
/* Generic context header of any generic context descriptor, else NULL. */
const sw_generic_context_header *sw_generic_header(const sw_context_descriptor *c);
/* Nominal type descriptor and key generic arguments of type metadata. */
const sw_type_context_descriptor *sw_type_descriptor(const sw_metadata *m);
const void *const *sw_generic_args(const sw_metadata *m);
/* Class object behind class metadata (Swift class, ObjC wrapper), else NULL. */
const void *sw_class_of_metadata(const sw_metadata *m);
int sw_is_subclass(const sw_metadata *sub, const sw_metadata *sup);
/* Qualified name of a context as the mangling spells it ("Module.Outer.Name";
 * extensions as the type they extend, anonymous contexts left out). */
void sw_context_name(const sw_context_descriptor *c, char *buf, size_t len);
/* Readable name, e.g. "main.Pair<Swift.Int, main.S>"; cached forever. */
const char *sw_type_name(const sw_metadata *m, int qualified);
const sw_protocol_requirement *sw_protocol_requirements(const sw_protocol_descriptor *p);
const sw_protocol_requirement *sw_assoc_type_requirement(const sw_protocol_descriptor *p,
                                                         const char *name);

/* ---- protocols.c ----------------------------------------------------------------- */
const sw_witness_table *sw_conforms_to(const sw_metadata *type, const sw_protocol_descriptor *proto);
/* swift_getAssociatedTypeWitness for a complete-metadata request. */
const sw_metadata *sw_get_assoc_type_witness(const sw_witness_table *wt, const sw_metadata *type,
                                             const sw_protocol_requirement *req_base,
                                             const sw_protocol_requirement *req);

/* ---- errors.c ------------------------------------------------------------------- */
/* Allocates an error box for a value of `type` (copied or taken from
 * `value` if given); *value_out receives the address of the boxed value. */
sw_heap_object *sw_alloc_error(const sw_metadata *type, const sw_witness_table *conformance,
                               sw_opaque *value, int take, sw_opaque **value_out);
int sw_is_error_box(const void *obj);
/* Value, dynamic type and Error conformance of an error (a box, or an
 * Objective-C object, for which *scratch holds the object). */
void sw_error_value(const void *error, void **scratch, const sw_opaque **value, const sw_metadata **type,
                    const sw_witness_table **conformance);

#endif
