/* Security: code signing, authorization, transforms, key import and access
 * control. Nothing here is signed and nobody can be authorized:
 *   - static code objects exist for a path; their signing information is
 *     empty (no "unique" hash: unsigned code) and they have no designated
 *     requirement (errSecCSUnsigned);
 *   - authorizations are created, but every right they ask for is denied
 *     (errAuthorizationDenied): there is no administrator to ask;
 *   - transform groups can be built and connected; executing them fails
 *     with errSecUnimplemented, as importing keys (SecItemImport) does, so
 *     signature checks fail closed;
 *   - access control objects hold their protection class and flags. */
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "../corefoundation/cf.h"

typedef int32_t OSStatus;
enum {
    ERR_UNIMPLEMENTED = -4, ERR_PARAM = -50,
    ERR_CS_UNSIGNED = -67062, ERR_CS_OBJECT_REQUIRED = -67069,
    ERR_AUTH_DENIED = -60005, ERR_AUTH_INVALID_REF = -60002, ERR_AUTH_INVALID_SET = -60001,
};

#define CODESIGN_CONSTANTS(X) \
    X(kSecTransformInputAttributeName, "INPUT") \
    X(kSecTransformOutputAttributeName, "OUTPUT") \
    X(kSecTransformDebugAttributeName, "DEBUG") \
    X(kSecTransformTransformName, "NAME") \
    X(kSecTransformAbortAttributeName, "ABORT") \
    X(kSecTransformErrorDomain, "com.apple.security.transforms.error") \
    X(kSecDigestSHA1, "SHA1") \
    X(kSecDigestSHA2, "SHA2") \
    X(kSecDigestMD5, "MD5") \
    X(kSecDigestTypeAttribute, "DigestType") \
    X(kSecDigestLengthAttribute, "DigestLength") \
    X(kSecCodeInfoUnique, "unique") \
    X(kSecCodeInfoIdentifier, "identifier") \
    X(kSecCodeInfoTeamIdentifier, "teamid") \
    X(kSecCodeInfoCertificates, "certificates") \
    X(kSecCodeInfoMainExecutable, "main-executable") \
    X(kSecCodeInfoPList, "info-plist") \
    X(kSecCodeInfoFlags, "flags") \
    X(kSecAttrAccessible, "pdmn") \
    X(kSecAttrAccessibleWhenUnlocked, "ak") \
    X(kSecAttrAccessibleAfterFirstUnlock, "ck") \
    X(kSecAttrAccessibleWhenUnlockedThisDeviceOnly, "aku") \
    X(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, "cku") \
    X(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, "akpu")

#define CS_DECLARE(name, value) static const struct cf_string *d_##name; DX_EXPORT("_" #name, &d_##name);
CODESIGN_CONSTANTS(CS_DECLARE)
#undef CS_DECLARE

__attribute__((constructor)) static void codesign_constants_init(void) {
#define CS_INIT(name, value) d_##name = d___CFStringMakeConstantString(value);
    CODESIGN_CONSTANTS(CS_INIT)
#undef CS_INIT
}

static struct cf_dict *empty_dict(void) {
    return d_CFDictionaryCreate(NULL, NULL, NULL, 0, &d_kCFTypeDictionaryKeyCallBacks,
                                &d_kCFTypeDictionaryValueCallBacks);
}
static void set_error(struct cf_error **error, OSStatus status) {
    if (error) *error = d_CFErrorCreate(NULL, d_kCFErrorDomainOSStatus, status, NULL);
}

/* ---- code signing ---- */

struct sec_code {
    struct cf_object base;
    const void *url;                       /* CFURLRef */
};
static void code_destroy(void *object) {
    struct sec_code *c = object;
    if (c->url) d_CFRelease(c->url);
}
static const struct cf_ops code_ops = {.destroy = code_destroy};
CF_TYPE_ID(SecCode, CF_SEC_CODE);
CF_TYPE_ID(SecStaticCode, CF_SEC_CODE);

static OSStatus d_SecStaticCodeCreateWithPath(const void *url, uint32_t flags, struct sec_code **out) {
    if (!url || !out || d_CFGetTypeID(url) != CF_URL) return ERR_PARAM;
    struct sec_code *c = cf_alloc(NULL, sizeof *c, CF_SEC_CODE, &code_ops);
    if (!c) return -108;
    c->url = d_CFRetain(url);
    *out = c;
    return 0;
}
DX_FN(SecStaticCodeCreateWithPath);

static OSStatus d_SecStaticCodeCreateWithPathAndAttributes(const void *url, uint32_t flags, const void *attrs,
                                                           struct sec_code **out) {
    return d_SecStaticCodeCreateWithPath(url, flags, out);
}
DX_FN(SecStaticCodeCreateWithPathAndAttributes);

/* The running program: a code object without a path. */
static OSStatus d_SecCodeCopySelf(uint32_t flags, struct sec_code **out) {
    if (!out) return ERR_PARAM;
    struct sec_code *c = cf_alloc(NULL, sizeof *c, CF_SEC_CODE, &code_ops);
    if (!c) return -108;
    *out = c;
    return 0;
}
DX_FN(SecCodeCopySelf);

static OSStatus d_SecCodeCopyStaticCode(struct sec_code *code, uint32_t flags, struct sec_code **out) {
    if (!code || !out || d_CFGetTypeID(code) != CF_SEC_CODE) return ERR_CS_OBJECT_REQUIRED;
    *out = (struct sec_code *)d_CFRetain(code);
    return 0;
}
DX_FN(SecCodeCopyStaticCode);

/* Unsigned: an empty dictionary (Apple's has no "unique" for unsigned code). */
static OSStatus d_SecCodeCopySigningInformation(struct sec_code *code, uint32_t flags, struct cf_dict **info) {
    if (!code || !info || d_CFGetTypeID(code) != CF_SEC_CODE) return ERR_CS_OBJECT_REQUIRED;
    *info = empty_dict();
    return 0;
}
DX_FN(SecCodeCopySigningInformation);

static OSStatus d_SecCodeCopyDesignatedRequirement(struct sec_code *code, uint32_t flags, const void **req) {
    if (req) *req = NULL;
    if (!code || d_CFGetTypeID(code) != CF_SEC_CODE) return ERR_CS_OBJECT_REQUIRED;
    return ERR_CS_UNSIGNED;
}
DX_FN(SecCodeCopyDesignatedRequirement);

static OSStatus d_SecStaticCodeCheckValidity(struct sec_code *code, uint32_t flags, const void *req) {
    return ERR_CS_UNSIGNED;
}
DX_FN(SecStaticCodeCheckValidity);
static OSStatus d_SecStaticCodeCheckValidityWithErrors(struct sec_code *code, uint32_t flags, const void *req,
                                                       struct cf_error **error) {
    set_error(error, ERR_CS_UNSIGNED);
    return ERR_CS_UNSIGNED;
}
DX_FN(SecStaticCodeCheckValidityWithErrors);
static OSStatus d_SecCodeCheckValidity(struct sec_code *code, uint32_t flags, const void *req) {
    return ERR_CS_UNSIGNED;
}
DX_FN(SecCodeCheckValidity);

/* ---- authorization: refs exist, rights are denied ---- */

struct authorization { uint32_t magic; };
#define AUTH_MAGIC 0x41757468u

struct auth_item { const char *name; size_t value_length; void *value; uint32_t flags; };
struct auth_set { uint32_t count; struct auth_item *items; };
enum { AUTH_FLAG_EXTEND_RIGHTS = 1 << 1 };

static OSStatus d_AuthorizationCreate(const struct auth_set *rights, const struct auth_set *env, uint32_t flags,
                                      struct authorization **out) {
    if (rights && rights->count && (flags & AUTH_FLAG_EXTEND_RIGHTS)) return ERR_AUTH_DENIED;
    if (!out) return 0;
    struct authorization *a = calloc(1, sizeof *a);
    if (!a) return -108;
    a->magic = AUTH_MAGIC;
    *out = a;
    return 0;
}
DX_FN(AuthorizationCreate);

static OSStatus d_AuthorizationFree(struct authorization *a, uint32_t flags) {
    if (!a || a->magic != AUTH_MAGIC) return ERR_AUTH_INVALID_REF;
    a->magic = 0;
    free(a);
    return 0;
}
DX_FN(AuthorizationFree);

static OSStatus d_AuthorizationCopyRights(struct authorization *a, const struct auth_set *rights,
                                          const struct auth_set *env, uint32_t flags, struct auth_set **granted) {
    if (granted) *granted = NULL;
    if (!a || a->magic != AUTH_MAGIC) return ERR_AUTH_INVALID_REF;
    if (!rights) return ERR_AUTH_INVALID_SET;
    if (rights->count) return ERR_AUTH_DENIED;
    if (granted) *granted = calloc(1, sizeof **granted);
    return 0;
}
DX_FN(AuthorizationCopyRights);

static OSStatus d_AuthorizationFreeItemSet(struct auth_set *set) {
    free(set);
    return 0;
}
DX_FN(AuthorizationFreeItemSet);

/* The rights database: no rights are defined. */
static OSStatus d_AuthorizationRightGet(const char *right, struct cf_dict **definition) {
    if (definition) *definition = NULL;
    return right ? ERR_AUTH_DENIED : ERR_PARAM;
}
DX_FN(AuthorizationRightGet);

static OSStatus d_AuthorizationRightSet(struct authorization *a, const char *right, const void *definition,
                                        const void *description, const void *bundle, const void *table) {
    if (!a || a->magic != AUTH_MAGIC) return ERR_AUTH_INVALID_REF;
    return ERR_AUTH_DENIED;
}
DX_FN(AuthorizationRightSet);

static OSStatus d_AuthorizationRightRemove(struct authorization *a, const char *right) { return ERR_AUTH_DENIED; }
DX_FN(AuthorizationRightRemove);

/* ---- transforms: built and connected, never executed ---- */

enum { T_READ, T_DIGEST, T_VERIFY, T_GROUP };
struct sec_transform {
    struct cf_object base;
    int kind;
    const void *held[2];                   /* stream; key and signature; digest type */
    int connections;
};
static void transform_destroy(void *object) {
    struct sec_transform *t = object;
    for (int i = 0; i < 2; i++) if (t->held[i]) d_CFRelease(t->held[i]);
}
static const struct cf_ops transform_ops = {.destroy = transform_destroy};
CF_TYPE_ID(SecTransform, CF_SEC_TRANSFORM);

static struct sec_transform *transform(int kind, const void *a, const void *b) {
    struct sec_transform *t = cf_alloc(NULL, sizeof *t, CF_SEC_TRANSFORM, &transform_ops);
    if (!t) return NULL;
    t->kind = kind;
    t->held[0] = a ? d_CFRetain(a) : NULL;
    t->held[1] = b ? d_CFRetain(b) : NULL;
    return t;
}

static struct sec_transform *d_SecTransformCreateReadTransformWithReadStream(const void *stream) {
    return stream ? transform(T_READ, stream, NULL) : NULL;
}
DX_FN(SecTransformCreateReadTransformWithReadStream);

static struct sec_transform *d_SecDigestTransformCreate(const void *type, CFIndex length, struct cf_error **error) {
    return transform(T_DIGEST, type, NULL);
}
DX_FN(SecDigestTransformCreate);

static struct sec_transform *d_SecVerifyTransformCreate(const void *key, const void *signature, struct cf_error **error) {
    if (!key) { set_error(error, ERR_PARAM); return NULL; }
    return transform(T_VERIFY, key, signature);
}
DX_FN(SecVerifyTransformCreate);

static struct sec_transform *d_SecTransformCreateGroupTransform(void) { return transform(T_GROUP, NULL, NULL); }
DX_FN(SecTransformCreateGroupTransform);

static struct sec_transform *d_SecTransformConnectTransforms(struct sec_transform *from, const void *from_name,
                                                             struct sec_transform *to, const void *to_name,
                                                             struct sec_transform *group, struct cf_error **error) {
    if (!from || !to || !group || d_CFGetTypeID(group) != CF_SEC_TRANSFORM) {
        set_error(error, ERR_PARAM);
        return NULL;
    }
    group->connections++;
    return group;
}
DX_FN(SecTransformConnectTransforms);

static Boolean d_SecTransformSetAttribute(struct sec_transform *t, const void *key, const void *value,
                                          struct cf_error **error) {
    return t && d_CFGetTypeID(t) == CF_SEC_TRANSFORM;
}
DX_FN(SecTransformSetAttribute);

static const void *d_SecTransformExecute(struct sec_transform *t, struct cf_error **error) {
    set_error(error, ERR_UNIMPLEMENTED);
    return NULL;
}
DX_FN(SecTransformExecute);

/* ---- keys and access control ---- */

static OSStatus d_SecItemImport(const void *data, const void *filename, int *format, int *type, uint32_t flags,
                                const void *params, const void *keychain, const void **items) {
    if (items) *items = NULL;
    return data ? ERR_UNIMPLEMENTED : ERR_PARAM;
}
DX_FN(SecItemImport);

struct sec_access_control {
    struct cf_object base;
    const void *protection;
    CFIndex flags;
};
static void access_destroy(void *object) {
    struct sec_access_control *a = object;
    if (a->protection) d_CFRelease(a->protection);
}
static const struct cf_ops access_ops = {.destroy = access_destroy};
CF_TYPE_ID(SecAccessControl, CF_SEC_ACCESS_CONTROL);

static struct sec_access_control *d_SecAccessControlCreateWithFlags(const void *allocator, const void *protection,
                                                                    CFIndex flags, struct cf_error **error) {
    if (!protection) { set_error(error, ERR_PARAM); return NULL; }
    struct sec_access_control *a = cf_alloc(allocator, sizeof *a, CF_SEC_ACCESS_CONTROL, &access_ops);
    if (!a) return NULL;
    a->protection = d_CFRetain(protection);
    a->flags = flags;
    return a;
}
DX_FN(SecAccessControlCreateWithFlags);

/* ---- Network's TLS metadata: no ALPN protocol was negotiated ---- */

static const char *d_sec_protocol_metadata_get_negotiated_protocol(const void *metadata) { return NULL; }
DX_FN(sec_protocol_metadata_get_negotiated_protocol);
