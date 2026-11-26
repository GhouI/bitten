/* Swift errors: the boxes `any Error` values live in, and the runtime's
 * hooks around throwing.
 *
 * An `any Error` existential is a single pointer to a heap box holding the
 * value, its type and its Error conformance. Compiled code never looks
 * inside the box: it allocates one with swift_allocError and writes the
 * value at the address returned, and reads it back through
 * swift_getErrorValue. So the layout is this runtime's:
 *
 *   heap object header | type | Error witness table | value (aligned)
 *
 * The box's metadata is heap metadata of kind ErrorObject, which makes it a
 * native object for swift_retain/swift_unknownObjectRetain. On macOS the
 * box is also an NSError subclass so Objective-C can use it; bridging to
 * NSError is left to Foundation's Swift overlay, which does not exist yet.
 * An Objective-C object received where an error is expected (an NSError
 * thrown by Objective-C code) is treated as a class-typed error value. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "swift_internal.h"

typedef struct {
    sw_heap_object header;
    const sw_metadata *type;
    const sw_witness_table *conformance;
} error_box;

static size_t value_offset(const sw_metadata *type, size_t *align_mask) {
    size_t am = sw_vwt_of(type)->flags & SW_VW_ALIGNMENT_MASK;
    if (am < 7) am = 7;
    if (align_mask) *align_mask = am;
    return (sizeof(error_box) + am) & ~am;
}
static sw_opaque *box_value(const error_box *b) {
    return (sw_opaque *)((char *)b + value_offset(b->type, NULL));
}

static void error_destroy(void *obj) {
    error_box *b = obj;
    sw_vwt_of(b->type)->destroy(box_value(b), b->type);
    sw_unowned_release_n(&b->header, 1); /* as swift_deallocObject */
}

static const struct {
    sw_heap_metadata_header header;
    uintptr_t kind;
} error_metadata = {{NULL, error_destroy, &sw_vwt_native_object}, SW_KIND_ERROR_OBJECT};
#define ERROR_METADATA ((const sw_metadata *)&error_metadata.kind)

int sw_is_error_box(const void *obj) {
    return obj && !((uintptr_t)obj & 0x8000000000000001ull) &&
           ((const sw_heap_object *)obj)->metadata == ERROR_METADATA;
}

typedef struct {
    sw_heap_object *object;
    sw_opaque *value;
} box_pair;

sw_heap_object *sw_alloc_error(const sw_metadata *type, const sw_witness_table *conformance,
                               sw_opaque *value, int take, sw_opaque **value_out) {
    size_t am, off = value_offset(type, &am);
    error_box *b = (error_box *)sw_alloc_object(ERROR_METADATA, off + sw_vwt_of(type)->size, am);
    b->type = type;
    b->conformance = conformance;
    sw_opaque *dst = (sw_opaque *)((char *)b + off);
    if (value) {
        if (take) sw_vwt_of(type)->initializeWithTake(dst, value, type);
        else sw_vwt_of(type)->initializeWithCopy(dst, value, type);
    }
    if (value_out) *value_out = dst;
    return &b->header;
}

/* BoxPair swift_allocError(const Metadata *type, const WitnessTable *Error,
 * OpaqueValue *initialValue, bool isTake), returned in rax:rdx. */
static box_pair d_swift_allocError(const sw_metadata *type, const sw_witness_table *conformance,
                                   sw_opaque *value, _Bool take) {
    box_pair r;
    r.object = sw_alloc_error(type, conformance, value, take, &r.value);
    return r;
}
DX_FN(swift_allocError);

/* A box whose value was never initialised (or was moved out). */
static void d_swift_deallocError(error_box *b, const sw_metadata *type) {
    sw_unowned_release_n(&b->header, 1);
}
DX_FN(swift_deallocError);

typedef struct {
    const sw_opaque *value;
    const sw_metadata *type;
    const sw_witness_table *conformance;
} error_value;

static const sw_metadata *objc_object_type(const void *obj) {
    static const void *(*getclass)(const void *);
    static const sw_metadata *(*wrap)(const void *);
    if (!getclass) getclass = (const void *(*)(const void *))dx_registry_lookup("_object_getClass");
    if (!wrap) wrap = (const sw_metadata *(*)(const void *))dx_registry_lookup("_swift_getObjCClassMetadata");
    const void *cls = getclass ? getclass(obj) : NULL;
    return cls && wrap ? wrap(cls) : cls;
}

/* The value, type and conformance of an error, for casts and messages.
 * `scratch` holds the object pointer when the error is an Objective-C
 * object rather than a box. */
void sw_error_value(const void *error, void **scratch, const sw_opaque **value, const sw_metadata **type,
                    const sw_witness_table **conformance) {
    if (sw_is_error_box(error)) {
        const error_box *b = error;
        *value = box_value(b);
        *type = b->type;
        *conformance = b->conformance;
        return;
    }
    *scratch = (void *)error;
    *value = (const sw_opaque *)scratch;
    *type = objc_object_type(error);
    /* An Objective-C error is an NSError, whose Error conformance comes with
     * Foundation's overlay (`extension NSError: Error`). */
    static const sw_protocol_descriptor *error_proto;
    if (!error_proto) error_proto = dx_global_lookup("_$ss5ErrorMp");
    *conformance = *type && error_proto ? sw_conforms_to(*type, error_proto) : NULL;
}

static void d_swift_getErrorValue(const void *error, void **scratch, error_value *out) {
    sw_error_value(error, scratch, &out->value, &out->type, &out->conformance);
}
DX_FN(swift_getErrorValue);

/* Errors are retained and released like any object that may be either
 * Swift or Objective-C. */
static void *d_swift_errorRetain(void *error) { return sw_unknown_retain(error); }
DX_FN(swift_errorRetain);
static void d_swift_errorRelease(void *error) { sw_unknown_release(error); }
DX_FN(swift_errorRelease);

/* ---- describing errors ------------------------------------------------------ */
/* "Module.Type.case" for enums (the case from the type's field
 * descriptor), else the qualified type name. Payloads are not printed. */
static void describe(const sw_opaque *value, const sw_metadata *type, char *buf, size_t len) {
    const char *name = type ? sw_type_name(type, 1) : "<unknown type>";
    snprintf(buf, len, "%s", name);
    if (!type || (sw_kind(type) != SW_KIND_ENUM && sw_kind(type) != SW_KIND_OPTIONAL)) return;
    const sw_vwt *w = sw_vwt_of(type);
    const sw_type_context_descriptor *d = sw_type_descriptor(type);
    const sw_field_descriptor *fd = d ? sw_rel(&d->fields) : NULL;
    if (!(w->flags & SW_VW_HAS_ENUM_WITNESSES) || !fd) return;
    unsigned tag = ((const sw_enum_vwt *)w)->getEnumTag(value, type);
    /* Field records list the payload cases first, then the empty ones,
     * which is also the order of the tags. */
    if (tag >= fd->num_fields) return;
    const sw_field_record *r =
        (const sw_field_record *)((const char *)fd->fields + (size_t)tag * fd->field_record_size);
    const char *cname = sw_rel(&r->field_name);
    if (cname) snprintf(buf, len, "%s.%s", name, cname);
}

static void describe_error(const void *error, char *buf, size_t len) {
    void *scratch;
    const sw_opaque *value;
    const sw_metadata *type;
    const sw_witness_table *conf;
    if (!error) {
        snprintf(buf, len, "nil");
        return;
    }
    sw_error_value(error, &scratch, &value, &type, &conf);
    describe(value, type, buf, len);
}

static void report(const char *msg) {
    ssize_t r = write(2, msg, strlen(msg));
    (void)r;
}

/* ---- throwing hooks ----------------------------------------------------------- */
/* swift_willThrow is called just before a function throws, with the error in
 * the swifterror register (r12) and the context register (r13) live; both
 * must survive. A debugger hook in the real runtime; here it logs at
 * BITTEN_DEBUG=2. The stub moves r12 into the first argument of a C
 * function, which preserves r12 and r13 as callee-saved registers. */
__attribute__((visibility("hidden"), used)) void sw_will_throw(const void *error) {
    if (dx_verbose < 2) return;
    char what[256];
    describe_error(error, what, sizeof what);
    dx_log(2, "swift: throwing %s", what);
}
void sw_will_throw_entry(void);
__asm__(".text\n"
        ".p2align 4\n"
        "sw_will_throw_entry:\n"
        "    movq %r12, %rdi\n"
        "    jmp sw_will_throw\n");
DX_EXPORT("_swift_willThrow", sw_will_throw_entry);

/* Typed throws: the error is a value of a concrete type, not boxed. */
static void d_swift_willThrowTypedImpl(const sw_opaque *value, const sw_metadata *type,
                                       const sw_witness_table *conformance) {
    if (dx_verbose < 2) return;
    char what[256];
    describe(value, type, what, sizeof what);
    dx_log(2, "swift: throwing %s", what);
}
DX_FN(swift_willThrowTypedImpl);

/* An error escaped the top level of a program (`main` with `throws`). */
static void d_swift_errorInMain(const void *error) {
    char what[512], msg[640];
    describe_error(error, what, sizeof what);
    snprintf(msg, sizeof msg, "Fatal error: Error raised at top level: %s\n", what);
    report(msg);
    abort();
}
DX_FN(swift_errorInMain);

/* `try!` on a call that threw. */
static void d_swift_unexpectedError(const void *error, const char *file, long file_len, _Bool ascii,
                                    unsigned long line) {
    char what[512], msg[1024];
    describe_error(error, what, sizeof what);
    snprintf(msg, sizeof msg, "%.*s:%lu: Fatal error: 'try!' expression unexpectedly raised an error: %s\n",
             (int)(file && file_len > 0 ? file_len : 0), file ? file : "", line, what);
    report(msg);
    abort();
}
DX_FN(swift_unexpectedError);

/* An error as an NSError: Foundation's overlay does the conversion
 * (_convertErrorToNSError, taking the error existential's single word). */
static void *d__swift_stdlib_bridgeErrorToNSError(void *error) {
    static void *(*convert)(void *);
    if (!convert) convert = (void *(*)(void *))dx_global_lookup("_$s10Foundation22_convertErrorToNSErrorySo0E0Cs0C0_pF");
    if (!convert) dx_fatal("swift: bridging an error to NSError needs Foundation");
    return convert(error);
}
DX_FN(_swift_stdlib_bridgeErrorToNSError);

/* The OS version as SwiftShims declares it (a C struct of three words);
 * bitten presents macOS 15.0. */
struct sw_os_version { intptr_t major, minor, patch; };
static struct sw_os_version d__swift_stdlib_operatingSystemVersion(void) {
    return (struct sw_os_version){15, 0, 0};
}
DX_FN(_swift_stdlib_operatingSystemVersion);
