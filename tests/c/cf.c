#include "darwin.h"

typedef const void *CFRef;
typedef void *CFMutableRef;
typedef long CFIndex;
typedef unsigned char Boolean;
typedef struct { CFIndex location, length; } CFRange;

struct callbacks {
    CFIndex version;
    const void *(*retain)(CFRef, const void *);
    void (*release)(CFRef, const void *);
    CFRef (*describe)(const void *);
    Boolean (*equal)(const void *, const void *);
};
struct key_callbacks {
    struct callbacks common;
    unsigned long (*hash)(const void *);
};

enum { MAC_ROMAN = 0, UTF16 = 0x100, LATIN1 = 0x201, ASCII = 0x600, UTF8 = 0x08000100,
       UTF16_BE = 0x10000100 };

extern const CFRef kCFAllocatorDefault, kCFAllocatorSystemDefault, kCFAllocatorMalloc, kCFAllocatorNull;
extern const CFRef kCFBooleanTrue, kCFBooleanFalse, kCFNull;
extern const CFRef kCFErrorDomainPOSIX, kCFErrorDomainOSStatus, kCFErrorLocalizedDescriptionKey;
extern const CFRef kCFLocaleCountryCode, kCFLocaleLanguageCode, kCFLocaleIdentifier;
extern const CFRef kSecClass, kSecKeyAlgorithmRSASignatureDigestPSSSHA256;
extern const struct callbacks kCFTypeArrayCallBacks, kCFTypeDictionaryValueCallBacks;
extern const struct key_callbacks kCFTypeDictionaryKeyCallBacks, kCFCopyStringDictionaryKeyCallBacks;
extern const struct key_callbacks kCFTypeSetCallBacks;

CFRef CFRetain(CFRef);
void CFRelease(CFRef);
CFIndex CFGetRetainCount(CFRef);
unsigned long CFGetTypeID(CFRef), CFArrayGetTypeID(void);
unsigned long CFHash(CFRef);
Boolean CFEqual(CFRef, CFRef), CFBooleanGetValue(CFRef);
CFRef CFCopyDescription(CFRef);
void *CFAllocatorAllocate(CFRef, CFIndex, unsigned long);
void CFAllocatorDeallocate(CFRef, void *);

CFRef CFStringCreateWithCString(CFRef, const char *, uint32_t);
CFRef CFStringCreateWithBytes(CFRef, const uint8_t *, CFIndex, uint32_t, Boolean);
CFRef CFStringCreateExternalRepresentation(CFRef, CFRef, uint32_t, uint8_t);
CFRef CFStringCreateFromExternalRepresentation(CFRef, CFRef, uint32_t);
CFRef CFStringCreateCopy(CFRef, CFRef), __CFStringMakeConstantString(const char *);
CFMutableRef CFStringCreateMutableCopy(CFRef, CFIndex, CFRef);
CFIndex CFStringGetLength(CFRef), CFStringGetMaximumSizeForEncoding(CFIndex, uint32_t);
Boolean CFStringGetCString(CFRef, char *, CFIndex, uint32_t);
const char *CFStringGetCStringPtr(CFRef, uint32_t);
void CFStringGetCharacters(CFRef, CFRange, uint16_t *);
uint16_t CFStringGetCharacterAtIndex(CFRef, CFIndex);
CFIndex CFStringCompare(CFRef, CFRef, unsigned long);
Boolean CFStringHasPrefix(CFRef, CFRef), CFStringHasSuffix(CFRef, CFRef);
void CFStringAppend(CFMutableRef, CFRef), CFStringDelete(CFMutableRef, CFRange);

CFRef CFDataCreate(CFRef, const uint8_t *, CFIndex);
CFMutableRef CFDataCreateMutableCopy(CFRef, CFIndex, CFRef);
CFIndex CFDataGetLength(CFRef);
const uint8_t *CFDataGetBytePtr(CFRef);
void CFDataAppendBytes(CFMutableRef, const uint8_t *, CFIndex);

CFRef CFArrayCreate(CFRef, const void **, CFIndex, const struct callbacks *);
CFMutableRef CFArrayCreateMutable(CFRef, CFIndex, const struct callbacks *);
CFIndex CFArrayGetCount(CFRef);
CFRef CFArrayGetValueAtIndex(CFRef, CFIndex);
void CFArrayGetValues(CFRef, CFRange, const void **);
void CFArrayAppendValue(CFMutableRef, CFRef), CFArrayRemoveValueAtIndex(CFMutableRef, CFIndex);

CFRef CFDictionaryCreate(CFRef, const void **, const void **, CFIndex,
                          const struct key_callbacks *, const struct callbacks *);
CFMutableRef CFDictionaryCreateMutable(CFRef, CFIndex, const struct key_callbacks *,
                                       const struct callbacks *);
CFRef CFDictionaryGetValue(CFRef, CFRef);
void CFDictionarySetValue(CFMutableRef, CFRef, CFRef), CFDictionaryRemoveValue(CFMutableRef, CFRef);
CFMutableRef CFSetCreateMutable(CFRef, CFIndex, const struct key_callbacks *);
void CFSetAddValue(CFMutableRef, CFRef);
CFIndex CFSetGetCount(CFRef);
Boolean CFSetContainsValue(CFRef, CFRef);

CFRef CFNumberCreate(CFRef, CFIndex, const void *);
CFIndex CFNumberGetType(CFRef);
Boolean CFNumberGetValue(CFRef, CFIndex, void *);
CFRef CFDateCreate(CFRef, double);
double CFDateGetAbsoluteTime(CFRef), CFAbsoluteTimeGetCurrent(void);

CFRef CFErrorCreate(CFRef, CFRef, CFIndex, CFRef), CFErrorGetDomain(CFRef), CFErrorCopyDescription(CFRef);
CFIndex CFErrorGetCode(CFRef);
CFRef CFLocaleCopyCurrent(void), CFLocaleGetValue(CFRef, CFRef);
CFRef CFUUIDCreate(CFRef), CFUUIDCreateString(CFRef, CFRef), CFUUIDCreateFromString(CFRef, CFRef);
CFRef CFURLCreateWithFileSystemPath(CFRef, CFRef, CFIndex, Boolean);
CFRef CFURLGetString(CFRef), CFURLCopyFileSystemPath(CFRef, CFIndex);
Boolean CFURLGetFileSystemRepresentation(CFRef, Boolean, uint8_t *, CFIndex);

CFRef SecCertificateCreateWithData(CFRef, CFRef), SecCertificateCopyData(CFRef);
CFRef SecPolicyCreateSSL(Boolean, CFRef), SecTrustCopyCertificateChain(CFRef);
int32_t SecTrustCreateWithCertificates(CFRef, CFRef, CFRef *), SecTrustSetVerifyDate(CFRef, CFRef);
_Bool SecTrustEvaluateWithError(CFRef, CFRef *);
int32_t SecItemCopyMatching(CFRef, CFRef *), SecItemDelete(CFRef), SecPKCS12Import(CFRef, CFRef, CFRef *);
int32_t SecIdentityCopyCertificate(CFRef, CFRef *), SecIdentityCopyPrivateKey(CFRef, CFRef *);
CFRef SecKeyCreateSignature(CFRef, CFRef, CFRef, CFRef *), SecCopyErrorMessageString(int32_t, void *);

int setenv(const char *, const char *, int);
int unsetenv(const char *);

static int string_is(CFRef s, const char *text) {
    const char *p = CFStringGetCStringPtr(s, UTF8);
    return p && !strcmp(p, text);
}

static void strings(void) {
    const char text[] = "caf\xc3\xa9 \xf0\x9f\x98\x80";
    CFRef s = CFStringCreateWithCString(kCFAllocatorDefault, text, UTF8);
    CHECK(s && CFStringGetLength(s) == 7);
    CHECK(string_is(s, text) && !CFStringGetCStringPtr(s, ASCII));
    char buffer[32];
    CHECK(CFStringGetCString(s, buffer, sizeof buffer, UTF8) && !strcmp(buffer, text));
    CHECK(!CFStringGetCString(s, buffer, sizeof text - 1, UTF8));
    CHECK(!CFStringGetCString(s, buffer, sizeof buffer, ASCII));
    CHECK(CFStringGetMaximumSizeForEncoding(CFStringGetLength(s), UTF8) >= (CFIndex)strlen(text));

    uint16_t units[3];
    CFStringGetCharacters(s, (CFRange){4, 3}, units);
    CHECK(units[0] == ' ' && units[1] == 0xd83d && units[2] == 0xde00);
    CHECK(CFStringGetCharacterAtIndex(s, 3) == 0xe9 && CFStringGetCharacterAtIndex(s, 6) == 0xde00);
    CFRef prefix = __CFStringMakeConstantString("caf"), suffix = __CFStringMakeConstantString("\xf0\x9f\x98\x80");
    CHECK(CFStringHasPrefix(s, prefix) && CFStringHasSuffix(s, suffix));
    CHECK(prefix == __CFStringMakeConstantString("caf"));

    CFRef copy = CFStringCreateCopy(NULL, s);
    CHECK(CFEqual(copy, s) && CFHash(copy) == CFHash(s) && CFStringCompare(copy, s, 0) == 0);
    CFMutableRef mutable = CFStringCreateMutableCopy(NULL, 0, copy);
    CFStringDelete(mutable, (CFRange){4, 3});
    CFStringAppend(mutable, prefix);
    CHECK(string_is(mutable, "caf\xc3\xa9" "caf") && string_is(copy, text));
    /* Many appends (ASCII, then a non-ASCII one), indexing on both sides of
     * it, and a string appended to itself. */
    CFMutableRef built = CFStringCreateMutableCopy(NULL, 0, prefix);
    for (int i = 0; i < 20000; i++) CFStringAppend(built, prefix);
    CHECK(CFStringGetLength(built) == 3 * 20001);
    CFStringAppend(built, suffix);
    CHECK(CFStringGetLength(built) == 3 * 20001 + 2 && CFStringGetCharacterAtIndex(built, 3 * 20001 + 1) == 0xde00);
    CHECK(CFStringGetCharacterAtIndex(built, 3 * 20000 + 2) == 'f');
    CFStringAppend(built, built);
    CHECK(CFStringGetLength(built) == 2 * (3 * 20001 + 2) && CFStringGetCharacterAtIndex(built, 3 * 20001 + 2) == 'c');
    CFRelease(built);

    CFRef external = CFStringCreateExternalRepresentation(NULL, s, UTF8, 0);
    CHECK(CFDataGetLength(external) == (CFIndex)strlen(text));
    CHECK(!memcmp(CFDataGetBytePtr(external), text, strlen(text)));
    CFRef utf16 = CFStringCreateExternalRepresentation(NULL, s, UTF16, 0);
    CHECK(CFDataGetLength(utf16) == 16);
    CFRef again = CFStringCreateFromExternalRepresentation(NULL, utf16, UTF16);
    CHECK(CFEqual(again, s));
    CFRef big_endian = CFStringCreateExternalRepresentation(NULL, s, UTF16_BE, 0);
    CHECK(CFDataGetLength(big_endian) == 14 && CFDataGetBytePtr(big_endian)[1] == 'c');

    const uint8_t latin[] = {0x63, 0x61, 0x66, 0xe9};
    const uint8_t roman[] = {0x63, 0x61, 0x66, 0x8e};
    CFRef latin_string = CFStringCreateWithBytes(NULL, latin, sizeof latin, LATIN1, 0);
    CFRef roman_string = CFStringCreateWithBytes(NULL, roman, sizeof roman, MAC_ROMAN, 0);
    CHECK(string_is(latin_string, "caf\xc3\xa9") && CFEqual(latin_string, roman_string));
    const uint8_t invalid[] = {0xed, 0xa0, 0x80};
    CHECK(!CFStringCreateWithBytes(NULL, invalid, sizeof invalid, UTF8, 0));
    CHECK(!CFStringCreateExternalRepresentation(NULL, s, ASCII, 0));
    CFRef lossy = CFStringCreateExternalRepresentation(NULL, s, ASCII, '?');
    CHECK(CFDataGetLength(lossy) == 6 && !memcmp(CFDataGetBytePtr(lossy), "caf? ?", 6));
    CFRelease(lossy);
    CFRelease(roman_string);
    CFRelease(latin_string);
    CFRelease(big_endian);
    CFRelease(again);
    CFRelease(utf16);
    CFRelease(external);
    CFRelease(mutable);
    CFRelease(copy);
    CFRelease(s);
}

static void collections(void) {
    const uint8_t bytes[] = {1, 0, 2, 3};
    CFRef d = CFDataCreate(NULL, bytes, sizeof bytes);
    CHECK(d && CFDataGetLength(d) == 4 && !memcmp(CFDataGetBytePtr(d), bytes, 4));
    CFMutableRef dm = CFDataCreateMutableCopy(NULL, 0, d);
    CFDataAppendBytes(dm, CFDataGetBytePtr(dm), CFDataGetLength(dm));
    CHECK(CFDataGetLength(dm) == 8 && !memcmp(CFDataGetBytePtr(dm) + 4, bytes, 4));
    CFRelease(dm);

    CHECK(CFGetRetainCount(d) == 1 && CFRetain(d) == d && CFGetRetainCount(d) == 2);
    CFRelease(d);
    const void *input[] = {d, kCFBooleanTrue}, *out[2];
    CFRef array = CFArrayCreate(NULL, input, 2, &kCFTypeArrayCallBacks);
    CHECK(CFArrayGetCount(array) == 2 && CFGetTypeID(array) == CFArrayGetTypeID());
    CHECK(CFArrayGetValueAtIndex(array, 0) == d && CFGetRetainCount(d) == 2);
    CFArrayGetValues(array, (CFRange){0, 2}, out);
    CHECK(out[0] == d && out[1] == kCFBooleanTrue);
    CFMutableRef raw = CFArrayCreateMutable(NULL, 0, NULL);
    CFArrayAppendValue(raw, d);
    CFArrayAppendValue(raw, (const void *)42);
    CHECK(CFGetRetainCount(d) == 2 && CFArrayGetValueAtIndex(raw, 1) == (const void *)42);
    CFRelease(raw);
    CFMutableRef owned = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    CFArrayAppendValue(owned, d);
    CHECK(CFGetRetainCount(d) == 3);
    CFArrayRemoveValueAtIndex(owned, 0);
    CHECK(CFGetRetainCount(d) == 2);
    CFRelease(owned);
    CFRelease(array);
    CHECK(CFGetRetainCount(d) == 1);

    CFRef key = CFStringCreateWithCString(NULL, "data", ASCII);
    CFRef lookup = CFStringCreateWithCString(NULL, "data", UTF8);
    CFRef dict = CFDictionaryCreate(NULL, &key, &d, 1, &kCFTypeDictionaryKeyCallBacks,
                                     &kCFTypeDictionaryValueCallBacks);
    CHECK(CFDictionaryGetValue(dict, lookup) == d && CFGetRetainCount(key) == 2);
    CFRelease(dict);
    CFMutableRef md = CFDictionaryCreateMutable(NULL, 0, &kCFCopyStringDictionaryKeyCallBacks,
                                                 &kCFTypeDictionaryValueCallBacks);
    CFMutableRef growing_key = CFStringCreateMutableCopy(NULL, 0, key);
    CFDictionarySetValue(md, growing_key, d);
    CFStringAppend(growing_key, key);
    CHECK(CFGetRetainCount(growing_key) == 1 && CFDictionaryGetValue(md, lookup) == d);
    CHECK(!CFDictionaryGetValue(md, growing_key));
    CFDictionaryRemoveValue(md, lookup);
    CHECK(CFGetRetainCount(d) == 1);
    CFRelease(growing_key);
    CFRelease(md);
    CFMutableRef set = CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks);
    CFSetAddValue(set, key);
    CFSetAddValue(set, lookup);
    CHECK(CFSetGetCount(set) == 1 && CFSetContainsValue(set, lookup));
    CFRelease(set);
    CFRelease(lookup);
    CFRelease(key);
    CFRelease(d);
}

static void objects(void) {
    CHECK(!kCFAllocatorDefault && kCFAllocatorSystemDefault != kCFAllocatorMalloc &&
          kCFAllocatorMalloc != kCFAllocatorNull && kCFAllocatorSystemDefault != kCFAllocatorNull);
    void *memory = CFAllocatorAllocate(kCFAllocatorMalloc, 16, 0);
    CHECK(memory && !CFAllocatorAllocate(kCFAllocatorNull, 16, 0));
    CFAllocatorDeallocate(kCFAllocatorMalloc, memory);
    CHECK(CFBooleanGetValue(kCFBooleanTrue) && !CFBooleanGetValue(kCFBooleanFalse));
    CHECK(!CFEqual(kCFBooleanTrue, kCFBooleanFalse) && CFGetTypeID(kCFNull) != CFGetTypeID(kCFBooleanTrue));
    CFRef desc = CFCopyDescription(kCFBooleanTrue);
    CHECK(string_is(desc, "true"));
    CFRelease(desc);

    int value = 257;
    int64_t wide = 0;
    signed char small;
    CFRef number = CFNumberCreate(NULL, 9, &value);
    CHECK(CFNumberGetType(number) == 3 && CFNumberGetValue(number, 4, &wide) && wide == 257);
    CHECK(!CFNumberGetValue(number, 1, &small));
    CFRef equal_number = CFNumberCreate(NULL, 4, &wide);
    CHECK(CFEqual(number, equal_number) && CFHash(number) == CFHash(equal_number));
    CFRelease(equal_number);
    CFRelease(number);

    double now = CFAbsoluteTimeGetCurrent();
    CHECK(now > 700000000);
    CFRef date = CFDateCreate(NULL, now);
    CHECK(CFDateGetAbsoluteTime(date) == now);
    CFRelease(date);

    CFRef message = __CFStringMakeConstantString("specific error"), key = kCFErrorLocalizedDescriptionKey;
    CFRef info = CFDictionaryCreate(NULL, &key, &message, 1,
                                     &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRef error = CFErrorCreate(NULL, kCFErrorDomainPOSIX, 2, info);
    CHECK(CFErrorGetCode(error) == 2 && CFEqual(CFErrorGetDomain(error), kCFErrorDomainPOSIX));
    desc = CFErrorCopyDescription(error);
    CHECK(string_is(desc, "specific error"));
    CFRelease(desc);
    CFRelease(error);
    CFRelease(info);

    CHECK(!setenv("LC_ALL", "pt_BR.UTF-8", 1));
    CFRef locale = CFLocaleCopyCurrent();
    CHECK(string_is(CFLocaleGetValue(locale, kCFLocaleLanguageCode), "pt"));
    CHECK(string_is(CFLocaleGetValue(locale, kCFLocaleCountryCode), "BR"));
    CHECK(string_is(CFLocaleGetValue(locale, kCFLocaleIdentifier), "pt_BR"));
    CFRelease(locale);

    CFRef uuid = CFUUIDCreate(NULL), uuid_text = CFUUIDCreateString(NULL, uuid);
    const char *formatted = CFStringGetCStringPtr(uuid_text, ASCII);
    CHECK(formatted && strlen(formatted) == 36 && formatted[14] == '4');
    CFRef parsed = CFUUIDCreateFromString(NULL, uuid_text);
    CHECK(CFEqual(uuid, parsed));
    CFRelease(parsed);
    CFRelease(uuid_text);
    CFRelease(uuid);

    CFRef path = __CFStringMakeConstantString("/tmp/spaced name#");
    CFRef url = CFURLCreateWithFileSystemPath(NULL, path, 0, 0);
    CHECK(string_is(CFURLGetString(url), "file:///tmp/spaced%20name%23"));
    CFRef decoded = CFURLCopyFileSystemPath(url, 0);
    CHECK(CFEqual(path, decoded));
    uint8_t buf[64];
    CHECK(CFURLGetFileSystemRepresentation(url, 1, buf, sizeof buf) &&
          !strcmp((const char *)buf, "/tmp/spaced name#"));
    CFRelease(decoded);
    CFRelease(url);
}

static void security(void) {
    CHECK(!unsetenv("BITTEN_INSECURE_TRUST"));
    const uint8_t der[] = {0x30, 0x03, 0x02, 0x01, 0x01};
    const uint8_t bad[] = {0x30, 0x81, 0x01, 0x00};
    CFRef data = CFDataCreate(NULL, der, sizeof der), invalid = CFDataCreate(NULL, bad, sizeof bad);
    CHECK(!SecCertificateCreateWithData(NULL, invalid));
    CFRelease(invalid);
    CFRef cert = SecCertificateCreateWithData(NULL, data);
    CFRef copy = SecCertificateCopyData(cert);
    CHECK(cert && CFEqual(copy, data));
    CFRelease(copy);

    CFRef policy = SecPolicyCreateSSL(1, __CFStringMakeConstantString("example.test"));
    CFRef trust = NULL, date = CFDateCreate(NULL, 42.0);
    CHECK(policy && !SecTrustCreateWithCertificates(cert, policy, &trust) && trust);
    CHECK(!SecTrustSetVerifyDate(trust, date));
    CFRelease(date);
    CFRef chain = SecTrustCopyCertificateChain(trust);
    CHECK(CFArrayGetCount(chain) == 1 && CFArrayGetValueAtIndex(chain, 0) == cert);
    CFRelease(chain);

    CFRef error = NULL;
    CHECK(!SecTrustEvaluateWithError(trust, &error) && error && CFErrorGetCode(error) == -67843);
    CHECK(CFEqual(CFErrorGetDomain(error), kCFErrorDomainOSStatus));
    CFRef description = CFErrorCopyDescription(error);
    CHECK(string_is(description, "Certificate trust evaluation is not implemented in bitten."));
    CFRelease(description);
    CFRelease(error);
    CHECK(!SecTrustEvaluateWithError(trust, NULL));

    CFRef out = cert;
    CHECK(kSecClass && kSecKeyAlgorithmRSASignatureDigestPSSSHA256);
    CHECK(SecItemCopyMatching(NULL, &out) == -25300 && !out);
    CHECK(SecItemDelete(NULL) == -25300);
    CHECK(SecPKCS12Import(data, NULL, &out) == -4 && !out);
    CHECK(SecIdentityCopyCertificate(NULL, &out) == -50 && !out);
    CHECK(SecIdentityCopyPrivateKey(NULL, &out) == -50 && !out);
    CHECK(!SecKeyCreateSignature(NULL, kSecKeyAlgorithmRSASignatureDigestPSSSHA256, data, &error));
    CHECK(error && CFErrorGetCode(error) == -4);
    CFRelease(error);
    description = SecCopyErrorMessageString(-25300, NULL);
    CHECK(description && CFStringGetLength(description) > 0);
    CFRelease(description);
    CFRelease(trust);
    CFRelease(policy);
    CFRelease(cert);
    CFRelease(data);
}

int main(void) {
    strings();
    collections();
    objects();
    security();
    puts("CoreFoundation and Security ok");
    return 0;
}
