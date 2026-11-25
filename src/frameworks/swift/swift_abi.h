/* Swift runtime ABI: the layouts the Swift compiler emits and reads directly.
 *
 * Everything here is fixed by the compiler (Swift 5 stable ABI, x86-64
 * Darwin). Compiled code reads metadata fields, value witness tables and
 * descriptors at fixed offsets, so these structures must match it exactly.
 * Anything the compiler never inlines (reference-count encoding, caches,
 * side tables) is ours to define and lives in swift_internal.h instead.
 *
 * Calling conventions: runtime entry points are declared SWIFT_CC(swift) in
 * Apple's headers. On x86-64 swiftcc and the C convention agree for every
 * function that takes no `self` (r13), error (r12) or async context (r14),
 * and two-word results come back in rax:rdx in both. Those are written as
 * plain C. The few that do use r13/r12/r14 must be built with clang and
 * __attribute__((swiftcall)); none exist yet. */
#ifndef BITTEN_SWIFT_ABI_H
#define BITTEN_SWIFT_ABI_H
#include <stddef.h>
#include <stdint.h>

/* ---- relative pointers --------------------------------------------------
 * Descriptors use 32-bit offsets from the field's own address. "Indirectable"
 * relative pointers use bit 0 to mean "the target is a pointer to the real
 * target" (a GOT-like slot, used for cross-image references). */
static inline const void *sw_rel(const int32_t *field) {
    int32_t off = *field;
    return off ? (const char *)field + off : NULL;
}
static inline const void *sw_rel_indirect(const int32_t *field) {
    int32_t off = *field;
    if (!off) return NULL;
    const char *p = (const char *)field + (off & ~1);
    return (off & 1) ? *(const void *const *)p : p;
}
/* Relative direct pointer whose low bits carry flags (mask them off). */
static inline const void *sw_rel_masked(const int32_t *field, int32_t mask) {
    int32_t off = *field & ~mask;
    return off ? (const char *)field + off : NULL;
}

/* ---- metadata kinds ----------------------------------------------------- */
enum {
    SW_KIND_CLASS = 0, /* any value above SW_KIND_LAST_ENUMERATED is an isa pointer */
    SW_KIND_STRUCT = 0x200,
    SW_KIND_ENUM = 0x201,
    SW_KIND_OPTIONAL = 0x202,
    SW_KIND_FOREIGN_CLASS = 0x203,
    SW_KIND_FOREIGN_REFERENCE_TYPE = 0x204,
    SW_KIND_OPAQUE = 0x300,
    SW_KIND_TUPLE = 0x301,
    SW_KIND_FUNCTION = 0x302,
    SW_KIND_EXISTENTIAL = 0x303,
    SW_KIND_METATYPE = 0x304,
    SW_KIND_OBJC_CLASS_WRAPPER = 0x305,
    SW_KIND_EXISTENTIAL_METATYPE = 0x306,
    SW_KIND_EXTENDED_EXISTENTIAL = 0x307,
    SW_KIND_FIXED_ARRAY = 0x308,
    SW_KIND_HEAP_LOCAL_VARIABLE = 0x400,
    SW_KIND_HEAP_GENERIC_LOCAL_VARIABLE = 0x500,
    SW_KIND_ERROR_OBJECT = 0x501,
    SW_KIND_TASK = 0x502,
    SW_KIND_JOB = 0x503,
    SW_KIND_LAST_ENUMERATED = 0x7FF,
};

/* ---- value witnesses ------------------------------------------------------
 * The functions take the type's metadata as their last argument. */
typedef struct sw_metadata sw_metadata;
typedef struct sw_opaque sw_opaque; /* an instance of some type */
typedef struct { void *w[3]; } sw_value_buffer; /* inline storage of existentials */

typedef struct sw_vwt {
    sw_opaque *(*initializeBufferWithCopyOfBuffer)(sw_value_buffer *dst, sw_value_buffer *src,
                                                   const sw_metadata *self);
    void (*destroy)(sw_opaque *obj, const sw_metadata *self);
    sw_opaque *(*initializeWithCopy)(sw_opaque *dst, sw_opaque *src, const sw_metadata *self);
    sw_opaque *(*assignWithCopy)(sw_opaque *dst, sw_opaque *src, const sw_metadata *self);
    sw_opaque *(*initializeWithTake)(sw_opaque *dst, sw_opaque *src, const sw_metadata *self);
    sw_opaque *(*assignWithTake)(sw_opaque *dst, sw_opaque *src, const sw_metadata *self);
    unsigned (*getEnumTagSinglePayload)(const sw_opaque *v, unsigned empty_cases,
                                        const sw_metadata *self);
    void (*storeEnumTagSinglePayload)(sw_opaque *v, unsigned which, unsigned empty_cases,
                                      const sw_metadata *self);
    size_t size;
    size_t stride;
    uint32_t flags;
    uint32_t extraInhabitantCount;
} sw_vwt;

/* Present when flags & SW_VW_HAS_ENUM_WITNESSES. */
typedef struct sw_enum_vwt {
    sw_vwt base;
    unsigned (*getEnumTag)(const sw_opaque *v, const sw_metadata *self);
    void (*destructiveProjectEnumData)(sw_opaque *v, const sw_metadata *self);
    void (*destructiveInjectEnumTag)(sw_opaque *v, unsigned tag, const sw_metadata *self);
} sw_enum_vwt;

enum {
    SW_VW_ALIGNMENT_MASK = 0x000000FF,
    SW_VW_IS_NON_POD = 0x00010000,
    SW_VW_IS_NON_INLINE = 0x00020000,
    SW_VW_HAS_SPARE_BITS = 0x00080000,
    SW_VW_IS_NON_BITWISE_TAKABLE = 0x00100000,
    SW_VW_HAS_ENUM_WITNESSES = 0x00200000,
    SW_VW_INCOMPLETE = 0x00400000,
    SW_VW_IS_NON_COPYABLE = 0x00800000,
    SW_VW_IS_NON_BITWISE_BORROWABLE = 0x01000000,
};

/* The "type layout" the compiler passes to swift_initStructMetadata and
 * friends: a pointer to the `size` field of a value witness table. */
typedef struct sw_type_layout {
    size_t size;
    size_t stride;
    uint32_t flags;
    uint32_t extraInhabitantCount;
} sw_type_layout;

/* ---- metadata -------------------------------------------------------------
 * A metadata pointer points at the kind word. Words before it:
 *   [-1] value witness table          (every type)
 *   [-2] destroy function             (heap metadata: classes, boxes)
 *   [-3] layout string, usually NULL  (classes)
 * Non-heap metadata has only [-1] (plus [-2] layout string since 5.9). */
struct sw_metadata {
    uintptr_t kind; /* or isa pointer for classes */
};
static inline const sw_vwt *sw_vwt_of(const sw_metadata *m) { return ((const sw_vwt *const *)m)[-1]; }
static inline uintptr_t sw_kind(const sw_metadata *m) {
    return m->kind > SW_KIND_LAST_ENUMERATED ? SW_KIND_CLASS : m->kind;
}

typedef struct sw_context_descriptor sw_context_descriptor;
typedef struct sw_type_context_descriptor sw_type_context_descriptor;
typedef struct sw_class_descriptor sw_class_descriptor;

/* Struct and enum metadata: kind, description, then generic arguments and
 * (for structs) the field offset vector, at word offsets the descriptor
 * gives. */
typedef struct sw_value_metadata {
    uintptr_t kind;
    const sw_type_context_descriptor *description;
} sw_value_metadata;

/* Class metadata. The first five words are an Objective-C class. The low two
 * bits of `data` mark a Swift class (1: before the stable ABI, 2: stable);
 * the values below are the separate `flags` field. */
enum {
    SW_CLASS_IS_SWIFT_PREV_STABLE_ABI = 0x1,
    SW_CLASS_USES_SWIFT_REFCOUNTING = 0x2,
    SW_CLASS_HAS_CUSTOM_OBJC_NAME = 0x4,
    SW_CLASS_IS_STATIC_SPECIALIZATION = 0x8,
    SW_CLASS_IS_CANONICAL_STATIC_SPECIALIZATION = 0x10,
};
typedef void (*sw_ivar_destroyer)(void *object);
typedef struct sw_class_metadata {
    const struct sw_class_metadata *isa; /* metaclass */
    const struct sw_class_metadata *superclass;
    void *cache_data[2];
    uintptr_t data;                       /* class_ro_t* | 1 (pre-5) | 2 (stable Swift) */
    /* Swift-only fields; valid when (data & 3) != 0 */
    uint32_t flags;                       /* SW_CLASS_* */
    uint32_t instance_address_point;
    uint32_t instance_size;
    uint16_t instance_align_mask;
    uint16_t reserved;
    uint32_t class_size;                  /* total bytes of metadata incl. prefix */
    uint32_t class_address_point;         /* bytes of prefix before this point */
    const sw_class_descriptor *description;
    sw_ivar_destroyer ivar_destroyer;
    /* then: per class in the hierarchy, generic args, field offsets, vtable */
} sw_class_metadata;
static inline int sw_class_is_swift(const sw_class_metadata *c) { return (c->data & 3) != 0; }

/* Metadata of a heap object that is not a class (boxes, closure contexts). */
typedef struct sw_heap_metadata_header {
    const void *layout_string;
    void (*destroy)(void *object);
    const sw_vwt *vwt;
} sw_heap_metadata_header;

typedef struct sw_tuple_element {
    const sw_metadata *type;
    size_t offset;
} sw_tuple_element;
typedef struct sw_tuple_metadata {
    uintptr_t kind;
    size_t num_elements;
    const char *labels; /* space-separated, or NULL */
    sw_tuple_element elements[];
} sw_tuple_metadata;

typedef struct sw_metatype_metadata {
    uintptr_t kind;
    const sw_metadata *instance_type;
} sw_metatype_metadata;

/* Wraps a plain Objective-C class that has no Swift metadata. */
typedef struct sw_objc_wrapper_metadata {
    uintptr_t kind;
    const void *cls;
} sw_objc_wrapper_metadata;

/* Function type metadata: kind, flags, result, then params (and optional
 * parameter flags, differentiability, global actor, extended flags...). */
enum {
    SW_FN_NUM_PARAMS_MASK = 0x0000FFFF,
    SW_FN_CONVENTION_MASK = 0x00FF0000, /* 0 swift, 1 block, 2 thin, 3 C */
    SW_FN_CONVENTION_SHIFT = 16,
    SW_FN_THROWS = 0x01000000,
    SW_FN_PARAM_FLAGS = 0x02000000,
    SW_FN_ESCAPING = 0x04000000,
    SW_FN_DIFFERENTIABLE = 0x08000000,
    SW_FN_GLOBAL_ACTOR = 0x10000000,
    SW_FN_ASYNC = 0x20000000,
    SW_FN_SENDABLE = 0x40000000,
    SW_FN_EXTENDED_FLAGS = 0x80000000,
};
typedef struct sw_function_metadata {
    uintptr_t kind;
    uintptr_t flags;
    const sw_metadata *result;
    const sw_metadata *params[];
} sw_function_metadata;

/* Existential (protocol composition) metadata. */
typedef struct sw_existential_metadata {
    uintptr_t kind;
    uint32_t flags; /* num witness tables (low 24), class constraint (bit 31 clear = class), special protocol */
    uint32_t num_protocols;
    /* optional superclass constraint if flags has it, then protocol refs */
} sw_existential_metadata;

/* ---- metadata requests and responses -------------------------------------- */
enum {
    SW_STATE_COMPLETE = 0x00,
    SW_STATE_NON_TRANSITIVE_COMPLETE = 0x01,
    SW_STATE_LAYOUT_COMPLETE = 0x3F,
    SW_STATE_ABSTRACT = 0xFF,
    SW_REQUEST_STATE_MASK = 0xFF,
    SW_REQUEST_NON_BLOCKING = 0x100,
};
typedef uintptr_t sw_request;
typedef struct {
    const sw_metadata *value;
    uintptr_t state;
} sw_response;

/* ---- context descriptors ---------------------------------------------------- */
enum {
    SW_CTX_MODULE = 0,
    SW_CTX_EXTENSION = 1,
    SW_CTX_ANONYMOUS = 2,
    SW_CTX_PROTOCOL = 3,
    SW_CTX_OPAQUE_TYPE = 4,
    SW_CTX_CLASS = 16,
    SW_CTX_STRUCT = 17,
    SW_CTX_ENUM = 18,
};
/* flags: kind (5 bits) | 0x40 unique | 0x80 generic | version << 8 | kind-specific << 16 */
static inline unsigned sw_ctx_kind(uint32_t flags) { return flags & 0x1F; }
static inline int sw_ctx_is_generic(uint32_t flags) { return (flags & 0x80) != 0; }
static inline int sw_ctx_is_unique(uint32_t flags) { return (flags & 0x40) != 0; }
static inline unsigned sw_ctx_kind_flags(uint32_t flags) { return flags >> 16; }

/* Type context kind-specific flags (high 16 bits of flags). */
enum {
    SW_TYPE_METADATA_INIT_MASK = 0x3, /* 0 none, 1 singleton, 2 foreign */
    SW_TYPE_METADATA_INIT_SINGLETON = 1,
    SW_TYPE_METADATA_INIT_FOREIGN = 2,
    SW_TYPE_HAS_IMPORT_INFO = 0x4,
    SW_TYPE_HAS_CANONICAL_PRESPECIALIZATIONS = 0x8,
    SW_TYPE_HAS_LAYOUT_STRING = 0x10,
    /* classes */
    SW_CLASS_HAS_VTABLE = 0x8000,
    SW_CLASS_HAS_OVERRIDE_TABLE = 0x4000,
    SW_CLASS_HAS_RESILIENT_SUPERCLASS = 0x2000,
    SW_CLASS_ARE_IMMEDIATE_MEMBERS_NEGATIVE = 0x1000,
    SW_CLASS_RESILIENT_SUPERCLASS_REF_KIND_SHIFT = 9, /* 3 bits */
    SW_CLASS_IS_ACTOR = 0x0080,
    SW_CLASS_IS_DEFAULT_ACTOR = 0x0100,
    SW_CLASS_HAS_OBJC_RESILIENT_STUBS = 0x0020, /* see trailing objects */
};

struct sw_context_descriptor {
    uint32_t flags;
    int32_t parent; /* relative indirectable */
};

struct sw_type_context_descriptor {
    uint32_t flags;
    int32_t parent;
    int32_t name;            /* relative direct, C string */
    int32_t access_function; /* relative direct */
    int32_t fields;          /* relative direct, field descriptor */
};

typedef struct sw_struct_descriptor {
    sw_type_context_descriptor base;
    uint32_t num_fields;
    uint32_t field_offset_vector_offset; /* in words, from the metadata address point */
    /* trailing objects */
} sw_struct_descriptor;

typedef struct sw_enum_descriptor {
    sw_type_context_descriptor base;
    uint32_t num_payload_cases_and_payload_size_offset; /* low 24: payload cases, high 8: size offset */
    uint32_t num_empty_cases;
} sw_enum_descriptor;

struct sw_class_descriptor {
    sw_type_context_descriptor base;
    int32_t superclass_type; /* relative direct, mangled name */
    uint32_t metadata_negative_size_in_words; /* or resilient metadata bounds (relative) */
    uint32_t metadata_positive_size_in_words; /* or extra class flags */
    uint32_t num_immediate_members;
    uint32_t num_fields;
    uint32_t field_offset_vector_offset; /* in words */
    /* trailing objects */
};

/* Generic context header, directly after the kind-specific descriptor
 * fields of a generic type (and after a type generic context's
 * instantiation cache / pattern fields for type contexts). */
typedef struct sw_generic_context_header {
    uint16_t num_params;
    uint16_t num_requirements;
    uint16_t num_key_arguments;
    uint16_t flags; /* 1 = has type packs, 2 = has conditional invertible protocols, 4 = has values */
} sw_generic_context_header;

/* For generic type descriptors the trailing objects begin with: */
typedef struct sw_type_generic_context_header {
    int32_t instantiation_cache; /* relative direct -> sw_generic_metadata_instantiation_cache */
    int32_t default_instantiation_pattern; /* relative direct -> pattern */
    sw_generic_context_header base;
    /* then: uint8_t param descriptors[num_params] (padded to 4), then
     * requirements[num_requirements] (sw_generic_requirement) */
} sw_type_generic_context_header;

/* Generic parameter descriptor byte: kind (low 6 bits: 0 type, 1 pack, 2 value) | 0x80 has key argument */
enum { SW_GP_KIND_MASK = 0x3F, SW_GP_HAS_KEY_ARGUMENT = 0x80 };

typedef struct sw_generic_requirement {
    uint32_t flags;  /* kind (low 5 bits) | 0x80 key argument | 0x20 is pack | 0x40 is value */
    int32_t param;   /* relative direct, mangled name of the subject */
    int32_t content; /* protocol (relative indirectable, low bit 0 = Swift, bit 1 ObjC), type (mangled), or layout kind */
} sw_generic_requirement;
enum {
    SW_REQ_PROTOCOL = 0,
    SW_REQ_SAME_TYPE = 1,
    SW_REQ_BASE_CLASS = 2,
    SW_REQ_SAME_CONFORMANCE = 3,
    SW_REQ_SAME_SHAPE = 4,
    SW_REQ_INVERTED_PROTOCOLS = 5,
    SW_REQ_LAYOUT = 0x1F,
};

/* Singleton metadata initialisation (trailing object when the type's
 * kind-specific flags say SINGLETON). */
typedef struct sw_singleton_metadata_cache {
    const sw_metadata *metadata;
    void *private_data;
} sw_singleton_metadata_cache;
typedef sw_response (*sw_completion_fn)(const sw_metadata *metadata, void *context,
                                        const void *pattern);
typedef struct sw_singleton_metadata_initialization {
    int32_t initialization_cache;    /* relative direct -> sw_singleton_metadata_cache */
    int32_t incomplete_metadata;     /* relative direct; for classes: or resilient pattern */
    int32_t completion_function;     /* relative direct -> sw_completion_fn */
} sw_singleton_metadata_initialization;

/* Generic metadata instantiation. The pattern (pointed to by the generic
 * header) has the instantiation function, completion function, flags. */
typedef struct sw_generic_metadata_instantiation_cache {
    void *private_data[16]; /* ours: the runtime keeps a pointer to its cache here */
} sw_generic_metadata_instantiation_cache;
typedef const sw_metadata *(*sw_metadata_instantiation_fn)(const sw_type_context_descriptor *desc,
                                                           const void *arguments,
                                                           const void *pattern);
typedef struct sw_generic_metadata_pattern {
    int32_t instantiation_function; /* relative direct */
    int32_t completion_function;    /* relative direct, may be 0 */
    uint32_t flags; /* 0x1 has extra data pattern, 0x2 has trailing flags, value: kind in bits 21..31 */
} sw_generic_metadata_pattern;
typedef struct sw_generic_value_metadata_pattern {
    sw_generic_metadata_pattern base;
    int32_t value_witnesses; /* relative direct -> sw_vwt */
    /* optional extra data pattern {int32 relative pattern, uint16 offset, uint16 size} */
} sw_generic_value_metadata_pattern;
typedef struct sw_generic_class_metadata_pattern {
    sw_generic_metadata_pattern base;
    int32_t destroy;          /* relative direct -> heap object destructor */
    int32_t ivar_destroyer;   /* relative direct */
    uint32_t class_flags;     /* SW_CLASS_* */
    int32_t class_ro_data;    /* relative direct, offset from pattern (rodata) */
    int32_t metaclass_ro_data;
} sw_generic_class_metadata_pattern;

/* ---- heap objects ------------------------------------------------------------
 * Every native Swift object starts with its metadata and a reference-count
 * word. The encoding of the word is the runtime's own business because
 * compiled code never touches it on x86-64 Darwin. Statically emitted
 * objects carry a zero word (and an 8-byte once-token just before the
 * object) until swift_initStaticObject fills the header in (heap.c). */
typedef struct sw_heap_object {
    const sw_metadata *metadata;
    uint64_t refcounts;
} sw_heap_object;

/* ---- pointer bits (x86-64) -------------------------------------------------
 * Spare bits of a heap object pointer: the top byte and the alignment bits.
 * swiftc packs enum tags there (a multi-payload enum of class references
 * keeps its payload under 0x00FFFFFFFFFFFFF8). Objective-C reserves bit 63
 * and bit 0 for tagged pointers. A Builtin.BridgeObject is a pointer with
 * extra information in the spare bits: bit 62 says "Objective-C object",
 * and values with a reserved bit set (tagged pointers, immortal String
 * storage) are not references at all. */
#define SW_SPARE_BITS_MASK 0xFF00000000000007ull
#define SW_OBJC_RESERVED_BITS_MASK 0x8000000000000001ull
#define SW_BRIDGE_TAG_MASK SW_OBJC_RESERVED_BITS_MASK
#define SW_BRIDGE_OBJC_BIT 0x4000000000000000ull
#define SW_BRIDGE_SPARE_MASK (SW_SPARE_BITS_MASK & ~SW_OBJC_RESERVED_BITS_MASK)

/* ---- field descriptors (__swift5_fieldmd) --------------------------------- */
typedef struct sw_field_record {
    uint32_t flags;         /* 0x1 indirect case, 0x2 var, 0x4 artificial */
    int32_t mangled_type;   /* relative direct, mangled name (may be 0) */
    int32_t field_name;     /* relative direct, C string */
} sw_field_record;
typedef struct sw_field_descriptor {
    int32_t mangled_type_name;
    int32_t superclass;
    uint16_t kind;          /* 0 struct, 1 class, 2 enum, 3 multi-payload enum, 4 protocol, 5 class protocol, 6 objc protocol, 7 objc class */
    uint16_t field_record_size;
    uint32_t num_fields;
    sw_field_record fields[];
} sw_field_descriptor;

/* ---- protocols and conformances (__swift5_protos, __swift5_proto) ------------ */
typedef struct sw_protocol_descriptor {
    uint32_t flags;
    int32_t parent;
    int32_t name;
    uint32_t num_requirements_in_signature;
    uint32_t num_requirements;
    int32_t associated_type_names; /* relative direct, space-separated */
    /* then requirement signature, then sw_protocol_requirement[num_requirements] */
} sw_protocol_descriptor;
typedef struct sw_protocol_requirement {
    uint32_t flags; /* kind low 4 bits: 0 base protocol, 1 method, 2 init, 3 getter, 4 setter, 5 read coroutine, 6 modify coroutine, 7 associated type access fn, 8 associated conformance access fn; 0x10 instance, 0x20 async */
    int32_t default_implementation;
} sw_protocol_requirement;

typedef struct sw_conformance_descriptor {
    int32_t protocol;        /* relative indirectable -> sw_protocol_descriptor */
    int32_t type_ref;        /* meaning depends on flags (TypeReferenceKind) */
    int32_t witness_table_pattern; /* relative direct */
    uint32_t flags;
    /* trailing: retroactive context, conditional requirements, resilient
     * witnesses, generic witness table, global actor */
} sw_conformance_descriptor;
enum {
    SW_CONF_TYPE_REF_KIND_SHIFT = 3,
    SW_CONF_TYPE_REF_KIND_MASK = 0x7 << 3, /* 0 direct type descriptor, 1 indirect type descriptor, 2 direct ObjC class name, 3 indirect ObjC class */
    SW_CONF_IS_RETROACTIVE = 0x1 << 6,
    SW_CONF_IS_SYNTHESIZED_NON_UNIQUE = 0x1 << 7,
    SW_CONF_NUM_CONDITIONAL_REQUIREMENTS_SHIFT = 8, /* 8 bits */
    SW_CONF_HAS_RESILIENT_WITNESSES = 0x1 << 16,
    SW_CONF_HAS_GENERIC_WITNESS_TABLE = 0x1 << 17,
    SW_CONF_IS_CONFORMANCE_OF_PROTOCOL = 0x1 << 18,
    SW_CONF_HAS_GLOBAL_ACTOR_ISOLATION = 0x1 << 19,
};

/* A witness table starts with a pointer to its conformance descriptor. */
typedef struct sw_witness_table {
    const sw_conformance_descriptor *description;
} sw_witness_table;

#endif
