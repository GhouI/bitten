#include <stdbool.h>
#include <string.h>

#include "../corefoundation/cf.h"

#define SECURITY_CONSTANTS(X) \
    X(kSecClass, "class") \
    X(kSecClassIdentity, "idnt") \
    X(kSecImportExportPassphrase, "passphrase") \
    X(kSecMatchItemList, "m_ItemList") \
    X(kSecMatchLimit, "m_Limit") \
    X(kSecMatchLimitAll, "m_LimitAll") \
    X(kSecReturnRef, "r_Ref") \
    X(kSecKeyAlgorithmECDSASignatureDigestX962SHA256, "algid:sign:ECDSA:digest-X962:SHA256") \
    X(kSecKeyAlgorithmECDSASignatureDigestX962SHA384, "algid:sign:ECDSA:digest-X962:SHA384") \
    X(kSecKeyAlgorithmECDSASignatureDigestX962SHA512, "algid:sign:ECDSA:digest-X962:SHA512") \
    X(kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256, "algid:sign:RSA:digest-PKCS1v15:SHA256") \
    X(kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA384, "algid:sign:RSA:digest-PKCS1v15:SHA384") \
    X(kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA512, "algid:sign:RSA:digest-PKCS1v15:SHA512") \
    X(kSecKeyAlgorithmRSASignatureDigestPSSSHA256, "algid:sign:RSA:digest-PSS:SHA256") \
    X(kSecKeyAlgorithmRSASignatureDigestPSSSHA384, "algid:sign:RSA:digest-PSS:SHA384") \
    X(kSecKeyAlgorithmRSASignatureDigestPSSSHA512, "algid:sign:RSA:digest-PSS:SHA512")

#define SEC_DECLARE(name, value) static const struct cf_string *d_##name; DX_EXPORT("_" #name, &d_##name);
SECURITY_CONSTANTS(SEC_DECLARE)
#undef SEC_DECLARE

__attribute__((constructor)) static void security_constants_init(void) {
#define SEC_INIT(name, value) d_##name = d___CFStringMakeConstantString(value);
    SECURITY_CONSTANTS(SEC_INIT)
#undef SEC_INIT
}

enum {
    SEC_UNIMPLEMENTED = -4, SEC_PARAM = -50, SEC_ALLOCATE = -108,
    SEC_ITEM_NOT_FOUND = -25300, SEC_NOT_TRUSTED = -67843,
};

struct sec_certificate {
    struct cf_object base;
    struct cf_data *der;
};

static void certificate_destroy(void *object) {
    struct sec_certificate *cert = object;
    d_CFRelease(cert->der);
}
static Boolean certificate_equal(const void *left, const void *right) {
    const struct sec_certificate *a = left, *b = right;
    return d_CFEqual(a->der, b->der);
}
static CFHashCode certificate_hash(const void *object) {
    const struct sec_certificate *cert = object;
    return d_CFHash(cert->der);
}
static const struct cf_ops certificate_ops = {
    .destroy = certificate_destroy, .equal = certificate_equal, .hash = certificate_hash,
};
CF_TYPE_ID(SecCertificate, CF_SEC_CERTIFICATE);

static bool der_sequence(const uint8_t *bytes, size_t n) {
    if (n < 2 || bytes[0] != 0x30) return false;
    size_t len = bytes[1], header = 2;
    if (len & 0x80) {
        size_t count = len & 0x7f;
        if (!count || count > sizeof len || count > n - header || bytes[header] == 0) return false;
        len = 0;
        for (size_t i = 0; i < count; i++) len = (len << 8) | bytes[header++];
        if (len < 128) return false;
    }
    return len && len == n - header;
}

static struct sec_certificate *d_SecCertificateCreateWithData(const void *allocator,
                                                              const struct cf_data *data) {
    if (d_CFGetTypeID(data) != CF_DATA) return NULL;
    const uint8_t *bytes = d_CFDataGetBytePtr(data);
    CFIndex size = d_CFDataGetLength(data);
    if (!der_sequence(bytes, size)) return NULL;
    struct sec_certificate *cert = cf_alloc(allocator, sizeof *cert, CF_SEC_CERTIFICATE, &certificate_ops);
    if (!cert) return NULL;
    cert->der = d_CFDataCreate(allocator, bytes, size);
    if (!cert->der) { d_CFRelease(cert); return NULL; }
    return cert;
}
DX_FN(SecCertificateCreateWithData);

static const struct cf_data *d_SecCertificateCopyData(const struct sec_certificate *cert) {
    return d_CFGetTypeID(cert) == CF_SEC_CERTIFICATE ? d_CFRetain(cert->der) : NULL;
}
DX_FN(SecCertificateCopyData);

struct sec_policy {
    struct cf_object base;
    struct cf_string *hostname;
    Boolean server;
};
static void policy_destroy(void *object) {
    struct sec_policy *policy = object;
    d_CFRelease(policy->hostname);
}
static Boolean policy_equal(const void *left, const void *right) {
    const struct sec_policy *a = left, *b = right;
    return a->server == b->server && d_CFEqual(a->hostname, b->hostname);
}
static CFHashCode policy_hash(const void *object) {
    const struct sec_policy *policy = object;
    return d_CFHash(policy->hostname) ^ policy->server;
}
static const struct cf_ops policy_ops = {.destroy = policy_destroy, .equal = policy_equal, .hash = policy_hash};
CF_TYPE_ID(SecPolicy, CF_SEC_POLICY);

static struct sec_policy *d_SecPolicyCreateSSL(Boolean server, const struct cf_string *hostname) {
    hostname = CF_STR(hostname);
    if (hostname && d_CFGetTypeID(hostname) != CF_STRING) return NULL;
    struct sec_policy *policy = cf_alloc(NULL, sizeof *policy, CF_SEC_POLICY, &policy_ops);
    if (!policy) return NULL;
    policy->server = !!server;
    if (hostname) {
        policy->hostname = d_CFStringCreateCopy(NULL, hostname);
        if (!policy->hostname) { d_CFRelease(policy); return NULL; }
    }
    return policy;
}
DX_FN(SecPolicyCreateSSL);

struct sec_trust {
    struct cf_object base;
    struct cf_array *chain, *policies;
    const void *verify_date;
};
static void trust_destroy(void *object) {
    struct sec_trust *trust = object;
    d_CFRelease(trust->chain);
    d_CFRelease(trust->policies);
    d_CFRelease(trust->verify_date);
}
static const struct cf_ops trust_ops = {.destroy = trust_destroy};
CF_TYPE_ID(SecTrust, CF_SEC_TRUST);

static int32_t trust_array(const void *input, CFTypeID type, struct cf_array **out) {
    if (d_CFGetTypeID(input) == type) {
        *out = d_CFArrayCreate(NULL, &input, 1, &d_kCFTypeArrayCallBacks);
        return *out ? 0 : SEC_ALLOCATE;
    }
    if (d_CFGetTypeID(input) != CF_ARRAY) return SEC_PARAM;
    CFIndex count = d_CFArrayGetCount(input);
    if (!count) return SEC_PARAM;
    if ((size_t)count > SIZE_MAX / sizeof(void *)) return SEC_ALLOCATE;
    const void **items = malloc((size_t)count * sizeof *items);
    if (!items) return SEC_ALLOCATE;
    for (CFIndex i = 0; i < count; i++) {
        items[i] = d_CFArrayGetValueAtIndex(input, i);
        if (d_CFGetTypeID(items[i]) != type) { free(items); return SEC_PARAM; }
    }
    *out = d_CFArrayCreate(NULL, items, count, &d_kCFTypeArrayCallBacks);
    free(items);
    return *out ? 0 : SEC_ALLOCATE;
}

static int32_t d_SecTrustCreateWithCertificates(const void *certs, const void *policies,
                                                struct sec_trust **out) {
    if (!out) return SEC_PARAM;
    *out = NULL;
    struct sec_trust *trust = cf_alloc(NULL, sizeof *trust, CF_SEC_TRUST, &trust_ops);
    if (!trust) return SEC_ALLOCATE;
    int32_t status = trust_array(certs, CF_SEC_CERTIFICATE, &trust->chain);
    if (!status && policies) status = trust_array(policies, CF_SEC_POLICY, &trust->policies);
    if (status) { d_CFRelease(trust); return status; }
    *out = trust;
    return 0;
}
DX_FN(SecTrustCreateWithCertificates);

static int32_t d_SecTrustSetVerifyDate(struct sec_trust *trust, const void *date) {
    if (d_CFGetTypeID(trust) != CF_SEC_TRUST || d_CFGetTypeID(date) != CF_DATE) return SEC_PARAM;
    const void *old = trust->verify_date;
    trust->verify_date = d_CFRetain(date);
    d_CFRelease(old);
    return 0;
}
DX_FN(SecTrustSetVerifyDate);

static const struct cf_array *d_SecTrustCopyCertificateChain(const struct sec_trust *trust) {
    return d_CFGetTypeID(trust) == CF_SEC_TRUST ? d_CFRetain(trust->chain) : NULL;
}
DX_FN(SecTrustCopyCertificateChain);

static void security_error(struct cf_error **out, CFIndex code, const char *message) {
    if (!out) return;
    const void *key = d_kCFErrorLocalizedDescriptionKey;
    const void *value = d___CFStringMakeConstantString(message);
    struct cf_dict *info = value ? d_CFDictionaryCreate(NULL, &key, &value, 1,
                    &d_kCFTypeDictionaryKeyCallBacks, &d_kCFTypeDictionaryValueCallBacks) : NULL;
    *out = d_CFErrorCreate(NULL, d_kCFErrorDomainOSStatus, code, info);
    d_CFRelease(info);
}

static bool d_SecTrustEvaluateWithError(const struct sec_trust *trust, struct cf_error **error) {
    if (error) *error = NULL;
    if (d_CFGetTypeID(trust) != CF_SEC_TRUST) {
        security_error(error, SEC_PARAM, "Invalid certificate trust object.");
        return false;
    }
    const char *insecure = getenv("BITTEN_INSECURE_TRUST");
    if (insecure && !strcmp(insecure, "1")) {
        static atomic_flag warned = ATOMIC_FLAG_INIT;
        if (!atomic_flag_test_and_set_explicit(&warned, memory_order_relaxed))
            dx_log(0, "WARNING: BITTEN_INSECURE_TRUST=1 accepts certificates without verification");
        return true;
    }
    security_error(error, SEC_NOT_TRUSTED, "Certificate trust evaluation is not implemented in bitten.");
    return false;
}
DX_FN(SecTrustEvaluateWithError);

static int32_t d_SecItemCopyMatching(const struct cf_dict *query, const void **out) {
    if (out) *out = NULL;
    return SEC_ITEM_NOT_FOUND;
}
DX_FN(SecItemCopyMatching);

static int32_t d_SecItemDelete(const struct cf_dict *query) { return SEC_ITEM_NOT_FOUND; }
DX_FN(SecItemDelete);

static int32_t d_SecPKCS12Import(const struct cf_data *data, const struct cf_dict *options,
                                 struct cf_array **out) {
    if (out) *out = NULL;
    return SEC_UNIMPLEMENTED;
}
DX_FN(SecPKCS12Import);

static int32_t d_SecIdentityCopyCertificate(const void *identity, struct sec_certificate **out) {
    if (out) *out = NULL;
    return SEC_PARAM;
}
DX_FN(SecIdentityCopyCertificate);

static int32_t d_SecIdentityCopyPrivateKey(const void *identity, void **out) {
    if (out) *out = NULL;
    return SEC_PARAM;
}
DX_FN(SecIdentityCopyPrivateKey);

static struct cf_data *d_SecKeyCreateSignature(const void *key, const struct cf_string *algorithm,
                                               const struct cf_data *data, struct cf_error **error) {
    algorithm = CF_STR(algorithm);
    security_error(error, SEC_UNIMPLEMENTED, "Key signatures are not implemented in bitten.");
    return NULL;
}
DX_FN(SecKeyCreateSignature);

static struct cf_string *d_SecCopyErrorMessageString(int32_t status, void *reserved) {
    const char *message;
    char unknown[48];
    switch (status) {
    case 0: message = "No error."; break;
    case SEC_UNIMPLEMENTED: message = "The operation is not implemented."; break;
    case SEC_PARAM: message = "An invalid parameter was passed."; break;
    case SEC_ALLOCATE: message = "Unable to allocate memory."; break;
    case SEC_ITEM_NOT_FOUND: message = "The item could not be found."; break;
    case SEC_NOT_TRUSTED: message = "The certificate was not trusted."; break;
    default:
        snprintf(unknown, sizeof unknown, "Security error %d.", status);
        message = unknown;
        break;
    }
    return d_CFStringCreateWithCString(NULL, message, CF_UTF8);
}
DX_FN(SecCopyErrorMessageString);
