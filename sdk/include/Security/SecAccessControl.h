/* bitten SDK: Security's access control objects (security/codesign.c). */
#ifndef BITTEN_SEC_ACCESS_CONTROL_H
#define BITTEN_SEC_ACCESS_CONTROL_H
#include <CoreFoundation/CoreFoundation.h>
typedef struct CF_BRIDGED(id) __SecAccessControl *SecAccessControlRef;
typedef CFOptionFlags SecAccessControlCreateFlags;
enum {
    kSecAccessControlUserPresence = 1u << 0,
    kSecAccessControlBiometryAny = 1u << 1,
    kSecAccessControlBiometryCurrentSet = 1u << 3,
    kSecAccessControlDevicePasscode = 1u << 4,
    kSecAccessControlOr = 1u << 14,
    kSecAccessControlAnd = 1u << 15,
    kSecAccessControlPrivateKeyUsage = 1u << 30,
};
extern const CFStringRef kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
extern const CFStringRef kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
SecAccessControlRef _Nullable SecAccessControlCreateWithFlags(CFAllocatorRef _Nullable allocator, CFTypeRef protection,
                                                              SecAccessControlCreateFlags flags,
                                                              CFErrorRef _Nullable *_Nullable error)
    CF_RETURNS_RETAINED;
CFTypeID SecAccessControlGetTypeID(void);
#endif
