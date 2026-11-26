/* bitten SDK: the CoreFoundation interface bitten implements. */
#ifndef BITTEN_COREFOUNDATION_H
#define BITTEN_COREFOUNDATION_H
#include <stddef.h>
#include <stdint.h>

#if __OBJC__
#define CF_BRIDGED(T) __attribute__((objc_bridge(T)))
#define CF_BRIDGED_MUTABLE(T) __attribute__((objc_bridge_mutable(T)))
#else
#define CF_BRIDGED(T)
#define CF_BRIDGED_MUTABLE(T)
#endif
#define CF_RETURNS_RETAINED __attribute__((cf_returns_retained))

typedef unsigned char Boolean;
typedef long CFIndex;
typedef unsigned long CFTypeID;
typedef unsigned long CFHashCode;
typedef unsigned long CFOptionFlags;
typedef uint32_t CFStringEncoding;
typedef uint16_t UniChar;
typedef double CFAbsoluteTime;
typedef double CFTimeInterval;
typedef CFIndex CFComparisonResult;
typedef struct {
    CFIndex location, length;
} CFRange;
static inline CFRange CFRangeMake(CFIndex loc, CFIndex len) {
    CFRange r = {loc, len};
    return r;
}

typedef const void *CFTypeRef;
typedef const struct CF_BRIDGED(id) __CFAllocator *CFAllocatorRef;
typedef const struct CF_BRIDGED(NSString) __CFString *CFStringRef;
typedef struct CF_BRIDGED_MUTABLE(NSMutableString) __CFString *CFMutableStringRef;
typedef const struct CF_BRIDGED(NSArray) __CFArray *CFArrayRef;
typedef struct CF_BRIDGED_MUTABLE(NSMutableArray) __CFArray *CFMutableArrayRef;
typedef const struct CF_BRIDGED(NSDictionary) __CFDictionary *CFDictionaryRef;
typedef struct CF_BRIDGED_MUTABLE(NSMutableDictionary) __CFDictionary *CFMutableDictionaryRef;
typedef const struct CF_BRIDGED(NSSet) __CFSet *CFSetRef;
typedef struct CF_BRIDGED_MUTABLE(NSMutableSet) __CFSet *CFMutableSetRef;
typedef const struct CF_BRIDGED(NSData) __CFData *CFDataRef;
typedef struct CF_BRIDGED_MUTABLE(NSMutableData) __CFData *CFMutableDataRef;
typedef const struct CF_BRIDGED(NSNumber) __CFNumber *CFNumberRef;
typedef const struct CF_BRIDGED(NSNumber) __CFBoolean *CFBooleanRef;
typedef const struct CF_BRIDGED(NSDate) __CFDate *CFDateRef;
typedef struct CF_BRIDGED(NSError) __CFError *CFErrorRef;
typedef const struct CF_BRIDGED(NSNull) __CFNull *CFNullRef;
typedef const struct CF_BRIDGED(NSLocale) __CFLocale *CFLocaleRef;
typedef const struct CF_BRIDGED(NSURL) __CFURL *CFURLRef;

enum {
    kCFStringEncodingMacRoman = 0,
    kCFStringEncodingISOLatin1 = 0x0201,
    kCFStringEncodingASCII = 0x0600,
    kCFStringEncodingUTF8 = 0x08000100,
    kCFStringEncodingUTF16 = 0x0100,
    kCFStringEncodingUTF16BE = 0x10000100,
    kCFStringEncodingUTF16LE = 0x14000100
};
enum { kCFCompareCaseInsensitive = 1 };
typedef enum {
    kCFNumberSInt8Type = 1, kCFNumberSInt16Type = 2, kCFNumberSInt32Type = 3, kCFNumberSInt64Type = 4,
    kCFNumberFloat32Type = 5, kCFNumberFloat64Type = 6, kCFNumberCharType = 7, kCFNumberShortType = 8,
    kCFNumberIntType = 9, kCFNumberLongType = 10, kCFNumberLongLongType = 11, kCFNumberFloatType = 12,
    kCFNumberDoubleType = 13, kCFNumberCFIndexType = 14, kCFNumberNSIntegerType = 15,
    kCFNumberCGFloatType = 16
} CFNumberType;

extern const CFAllocatorRef kCFAllocatorDefault;
extern const CFBooleanRef kCFBooleanTrue, kCFBooleanFalse;
extern const CFNullRef kCFNull;
typedef struct {
    CFIndex version;
    void *retain, *release, *copyDescription, *equal;
} CFArrayCallBacks;
typedef struct {
    CFIndex version;
    void *retain, *release, *copyDescription, *equal, *hash;
} CFDictionaryKeyCallBacks, CFSetCallBacks;
typedef CFArrayCallBacks CFDictionaryValueCallBacks;
extern const CFArrayCallBacks kCFTypeArrayCallBacks;
extern const CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks, kCFCopyStringDictionaryKeyCallBacks;
extern const CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks;
extern const CFSetCallBacks kCFTypeSetCallBacks;

CFTypeRef CFRetain(CFTypeRef cf);
void CFRelease(CFTypeRef cf);
CFTypeID CFGetTypeID(CFTypeRef cf);
Boolean CFEqual(CFTypeRef a, CFTypeRef b);
CFHashCode CFHash(CFTypeRef cf);
CFStringRef CFCopyDescription(CFTypeRef cf) CF_RETURNS_RETAINED;

CFTypeID CFStringGetTypeID(void);
CFStringRef CFStringCreateWithCString(CFAllocatorRef, const char *, CFStringEncoding) CF_RETURNS_RETAINED;
CFStringRef CFStringCreateWithBytes(CFAllocatorRef, const uint8_t *, CFIndex, CFStringEncoding, Boolean) CF_RETURNS_RETAINED;
CFStringRef CFStringCreateCopy(CFAllocatorRef, CFStringRef) CF_RETURNS_RETAINED;
CFMutableStringRef CFStringCreateMutable(CFAllocatorRef, CFIndex) CF_RETURNS_RETAINED;
CFMutableStringRef CFStringCreateMutableCopy(CFAllocatorRef, CFIndex, CFStringRef) CF_RETURNS_RETAINED;
CFIndex CFStringGetLength(CFStringRef);
UniChar CFStringGetCharacterAtIndex(CFStringRef, CFIndex);
void CFStringGetCharacters(CFStringRef, CFRange, UniChar *);
Boolean CFStringGetCString(CFStringRef, char *, CFIndex, CFStringEncoding);
const char *CFStringGetCStringPtr(CFStringRef, CFStringEncoding);
CFIndex CFStringGetMaximumSizeForEncoding(CFIndex, CFStringEncoding);
CFDataRef CFStringCreateExternalRepresentation(CFAllocatorRef, CFStringRef, CFStringEncoding, uint8_t) CF_RETURNS_RETAINED;
CFComparisonResult CFStringCompare(CFStringRef, CFStringRef, CFOptionFlags);
Boolean CFStringHasPrefix(CFStringRef, CFStringRef);
Boolean CFStringHasSuffix(CFStringRef, CFStringRef);
void CFStringAppend(CFMutableStringRef, CFStringRef);
void CFStringAppendCString(CFMutableStringRef, const char *, CFStringEncoding);
void CFStringReplace(CFMutableStringRef, CFRange, CFStringRef);
void CFStringDelete(CFMutableStringRef, CFRange);
void CFStringSetString(CFMutableStringRef, CFStringRef);

CFTypeID CFArrayGetTypeID(void);
CFArrayRef CFArrayCreate(CFAllocatorRef, const void **, CFIndex, const CFArrayCallBacks *) CF_RETURNS_RETAINED;
CFArrayRef CFArrayCreateCopy(CFAllocatorRef, CFArrayRef) CF_RETURNS_RETAINED;
CFMutableArrayRef CFArrayCreateMutable(CFAllocatorRef, CFIndex, const CFArrayCallBacks *) CF_RETURNS_RETAINED;
CFMutableArrayRef CFArrayCreateMutableCopy(CFAllocatorRef, CFIndex, CFArrayRef) CF_RETURNS_RETAINED;
CFIndex CFArrayGetCount(CFArrayRef);
const void *CFArrayGetValueAtIndex(CFArrayRef, CFIndex);
void CFArrayGetValues(CFArrayRef, CFRange, const void **);
void CFArrayAppendValue(CFMutableArrayRef, const void *);
void CFArrayInsertValueAtIndex(CFMutableArrayRef, CFIndex, const void *);
void CFArraySetValueAtIndex(CFMutableArrayRef, CFIndex, const void *);
void CFArrayRemoveValueAtIndex(CFMutableArrayRef, CFIndex);
void CFArrayRemoveAllValues(CFMutableArrayRef);

CFTypeID CFDictionaryGetTypeID(void);
CFDictionaryRef CFDictionaryCreate(CFAllocatorRef, const void **, const void **, CFIndex, const CFDictionaryKeyCallBacks *, const CFDictionaryValueCallBacks *) CF_RETURNS_RETAINED;
CFDictionaryRef CFDictionaryCreateCopy(CFAllocatorRef, CFDictionaryRef) CF_RETURNS_RETAINED;
CFMutableDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef, CFIndex, const CFDictionaryKeyCallBacks *, const CFDictionaryValueCallBacks *) CF_RETURNS_RETAINED;
CFMutableDictionaryRef CFDictionaryCreateMutableCopy(CFAllocatorRef, CFIndex, CFDictionaryRef) CF_RETURNS_RETAINED;
CFIndex CFDictionaryGetCount(CFDictionaryRef);
const void *CFDictionaryGetValue(CFDictionaryRef, const void *);
void CFDictionaryGetKeysAndValues(CFDictionaryRef, const void **, const void **);
void CFDictionarySetValue(CFMutableDictionaryRef, const void *, const void *);
void CFDictionaryRemoveValue(CFMutableDictionaryRef, const void *);
void CFDictionaryRemoveAllValues(CFMutableDictionaryRef);

CFTypeID CFSetGetTypeID(void);
CFMutableSetRef CFSetCreateMutable(CFAllocatorRef, CFIndex, const CFSetCallBacks *) CF_RETURNS_RETAINED;
CFIndex CFSetGetCount(CFSetRef);
Boolean CFSetContainsValue(CFSetRef, const void *);
const void *CFSetGetValue(CFSetRef, const void *);
void CFSetGetValues(CFSetRef, const void **);
void CFSetAddValue(CFMutableSetRef, const void *);
void CFSetRemoveValue(CFMutableSetRef, const void *);
void CFSetRemoveAllValues(CFMutableSetRef);
CFSetRef CFSetCreateCopy(CFAllocatorRef, CFSetRef) CF_RETURNS_RETAINED;

CFTypeID CFDataGetTypeID(void);
CFDataRef CFDataCreate(CFAllocatorRef, const uint8_t *, CFIndex) CF_RETURNS_RETAINED;
CFMutableDataRef CFDataCreateMutable(CFAllocatorRef, CFIndex) CF_RETURNS_RETAINED;
CFMutableDataRef CFDataCreateMutableCopy(CFAllocatorRef, CFIndex, CFDataRef) CF_RETURNS_RETAINED;
CFIndex CFDataGetLength(CFDataRef);
const uint8_t *CFDataGetBytePtr(CFDataRef);
uint8_t *CFDataGetMutableBytePtr(CFMutableDataRef);
void CFDataAppendBytes(CFMutableDataRef, const uint8_t *, CFIndex);
void CFDataSetLength(CFMutableDataRef, CFIndex);
void CFDataIncreaseLength(CFMutableDataRef, CFIndex);
void CFDataReplaceBytes(CFMutableDataRef, CFRange, const uint8_t *, CFIndex);
CFDataRef CFDataCreateCopy(CFAllocatorRef, CFDataRef) CF_RETURNS_RETAINED;

CFTypeID CFNumberGetTypeID(void);
CFTypeID CFBooleanGetTypeID(void);
CFNumberRef CFNumberCreate(CFAllocatorRef, CFNumberType, const void *) CF_RETURNS_RETAINED;
Boolean CFNumberGetValue(CFNumberRef, CFNumberType, void *);
CFNumberType CFNumberGetType(CFNumberRef);
Boolean CFNumberIsFloatType(CFNumberRef);
CFComparisonResult CFNumberCompare(CFNumberRef, CFNumberRef, void *);
Boolean CFBooleanGetValue(CFBooleanRef);

CFDateRef CFDateCreate(CFAllocatorRef, CFAbsoluteTime) CF_RETURNS_RETAINED;
CFAbsoluteTime CFDateGetAbsoluteTime(CFDateRef);
CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);
#define kCFAbsoluteTimeIntervalSince1970 978307200.0

CFErrorRef CFErrorCreate(CFAllocatorRef, CFStringRef domain, CFIndex code, CFDictionaryRef userInfo) CF_RETURNS_RETAINED;
CFStringRef CFErrorGetDomain(CFErrorRef);
CFIndex CFErrorGetCode(CFErrorRef);
CFDictionaryRef CFErrorCopyUserInfo(CFErrorRef) CF_RETURNS_RETAINED;
CFStringRef CFErrorCopyDescription(CFErrorRef) CF_RETURNS_RETAINED;

CFURLRef CFURLCreateWithString(CFAllocatorRef, CFStringRef, CFURLRef base) CF_RETURNS_RETAINED;
CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef, CFStringRef, CFIndex pathStyle, Boolean isDirectory) CF_RETURNS_RETAINED;
CFStringRef CFURLGetString(CFURLRef);

/* CFAttributedString (src/frameworks/corefoundation/attributed.c). */
typedef const struct CF_BRIDGED(id) __CFAttributedString *CFAttributedStringRef;
typedef struct CF_BRIDGED_MUTABLE(id) __CFAttributedString *CFMutableAttributedStringRef;
CFTypeID CFAttributedStringGetTypeID(void);
CFAttributedStringRef CFAttributedStringCreate(CFAllocatorRef, CFStringRef, CFDictionaryRef attributes) CF_RETURNS_RETAINED;
CFAttributedStringRef CFAttributedStringCreateCopy(CFAllocatorRef, CFAttributedStringRef) CF_RETURNS_RETAINED;
CFMutableAttributedStringRef CFAttributedStringCreateMutable(CFAllocatorRef, CFIndex maxLength) CF_RETURNS_RETAINED;
CFMutableAttributedStringRef CFAttributedStringCreateMutableCopy(CFAllocatorRef, CFIndex maxLength, CFAttributedStringRef) CF_RETURNS_RETAINED;
CFStringRef CFAttributedStringGetString(CFAttributedStringRef);
CFIndex CFAttributedStringGetLength(CFAttributedStringRef);
CFDictionaryRef CFAttributedStringGetAttributes(CFAttributedStringRef, CFIndex loc, CFRange *effectiveRange);
CFTypeRef CFAttributedStringGetAttribute(CFAttributedStringRef, CFIndex loc, CFStringRef attrName, CFRange *effectiveRange);
void CFAttributedStringReplaceString(CFMutableAttributedStringRef, CFRange, CFStringRef);
void CFAttributedStringSetAttributes(CFMutableAttributedStringRef, CFRange, CFDictionaryRef, Boolean clearOtherAttributes);
void CFAttributedStringSetAttribute(CFMutableAttributedStringRef, CFRange, CFStringRef attrName, CFTypeRef value);
void CFAttributedStringRemoveAttribute(CFMutableAttributedStringRef, CFRange, CFStringRef attrName);
void CFAttributedStringReplaceAttributedString(CFMutableAttributedStringRef, CFRange, CFAttributedStringRef);
void CFAttributedStringBeginEditing(CFMutableAttributedStringRef);
void CFAttributedStringEndEditing(CFMutableAttributedStringRef);
#endif
