/* IOKit (the platform expert, matching, iterators, power sources from a
 * fake /sys/class/power_supply, assertions) and Security's code signing,
 * authorization, transforms and access control. */
#include "darwin.h"

typedef const void *Ref;
typedef unsigned int io_object_t;
int setenv(const char *, const char *, int);
int mkdir(const char *, unsigned short);
int open(const char *, int, ...);
ssize_t write(int, const void *, size_t);
int close(int);
int getpid(void);
Ref CFStringCreateWithCString(Ref, const char *, unsigned int);
unsigned char CFStringGetCString(Ref, char *, long, unsigned int);
unsigned char CFEqual(Ref, Ref);
void CFRelease(Ref);
unsigned long CFGetTypeID(Ref);
unsigned long CFStringGetTypeID(void), CFDictionaryGetTypeID(void), CFArrayGetTypeID(void);
long CFArrayGetCount(Ref);
Ref CFArrayGetValueAtIndex(Ref, long);
long CFDictionaryGetCount(Ref);
Ref CFDictionaryGetValue(Ref, Ref);
unsigned char CFNumberGetValue(Ref, long, void *);
unsigned char CFBooleanGetValue(Ref);
Ref CFURLCreateWithFileSystemPath(Ref, Ref, long, unsigned char);
long CFErrorGetCode(Ref);
#define UTF8 0x08000100

extern const unsigned int kIOMainPortDefault;
void *IOServiceMatching(const char *);
int IOServiceGetMatchingServices(unsigned int, void *, io_object_t *);
io_object_t IOServiceGetMatchingService(unsigned int, void *);
io_object_t IOIteratorNext(io_object_t);
int IOObjectRelease(io_object_t);
int IORegistryEntryGetChildIterator(io_object_t, const char *, io_object_t *);
Ref IORegistryEntryCreateCFProperty(io_object_t, Ref, Ref, unsigned int);
io_object_t IORegistryEntryFromPath(unsigned int, const char *);
Ref IOPSCopyPowerSourcesInfo(void);
Ref IOPSCopyPowerSourcesList(Ref);
Ref IOPSGetPowerSourceDescription(Ref, Ref);
Ref IOPSGetProvidingPowerSourceType(Ref);
int IOPMAssertionCreateWithName(Ref, unsigned int, Ref, unsigned int *);
int IOPMAssertionRelease(unsigned int);
int IOPMCopyAssertionsByProcess(Ref *);

int SecStaticCodeCreateWithPath(Ref, unsigned int, Ref *);
int SecCodeCopySigningInformation(Ref, unsigned int, Ref *);
int SecCodeCopyDesignatedRequirement(Ref, unsigned int, Ref *);
extern Ref kSecCodeInfoUnique, kSecTransformInputAttributeName, kSecDigestSHA1,
    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
int AuthorizationCreate(const void *, const void *, unsigned int, void **);
int AuthorizationCopyRights(void *, const void *, const void *, unsigned int, void **);
int AuthorizationFree(void *, unsigned int);
int AuthorizationRightGet(const char *, Ref *);
Ref SecDigestTransformCreate(Ref, long, Ref *);
Ref SecTransformCreateGroupTransform(void);
Ref SecTransformConnectTransforms(Ref, Ref, Ref, Ref, Ref, Ref *);
Ref SecTransformExecute(Ref, Ref *);
int SecItemImport(Ref, Ref, void *, void *, unsigned int, Ref, Ref, Ref *);
Ref SecAccessControlCreateWithFlags(Ref, Ref, unsigned long, Ref *);
const char *sec_protocol_metadata_get_negotiated_protocol(Ref);

static Ref S(const char *s) { return CFStringCreateWithCString(NULL, s, UTF8); }
static void put(const char *path, const char *text) {
    int fd = open(path, 0x601, 0644);                 /* O_WRONLY|O_CREAT|O_TRUNC */
    CHECK(fd >= 0);
    write(fd, text, strlen(text));
    close(fd);
}

int main(void) {
    /* the platform expert */
    io_object_t pe = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"));
    CHECK(pe != 0);
    CHECK(IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/") == pe);
    Ref uuid = IORegistryEntryCreateCFProperty(pe, S("IOPlatformUUID"), NULL, 0);
    CHECK(uuid && CFGetTypeID(uuid) == CFStringGetTypeID());
    char buf[64];
    CHECK(CFStringGetCString(uuid, buf, sizeof buf, UTF8) && strlen(buf) == 36 && buf[8] == '-' && buf[23] == '-');
    CHECK(IORegistryEntryCreateCFProperty(pe, S("NoSuchKey"), NULL, 0) == NULL);

    io_object_t it = 0;
    CHECK(IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"), &it) == 0);
    CHECK(IOIteratorNext(it) == pe && IOIteratorNext(it) == 0);
    CHECK(IOObjectRelease(it) == 0);
    CHECK(IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &it) == 0);
    CHECK(IOIteratorNext(it) == 0);
    IOObjectRelease(it);
    CHECK(IORegistryEntryGetChildIterator(pe, "IOService", &it) == 0 && IOIteratorNext(it) == 0);
    IOObjectRelease(it);

    /* power sources: a fake battery, discharging at 42% */
    char root[128], bat[160], ac[160], f[200];
    snprintf(root, sizeof root, "/tmp/bitten-power-%d", getpid());
    snprintf(bat, sizeof bat, "%s/BAT0", root);
    snprintf(ac, sizeof ac, "%s/AC", root);
    mkdir(root, 0755); mkdir(bat, 0755); mkdir(ac, 0755);
    snprintf(f, sizeof f, "%s/type", bat); put(f, "Battery\n");
    snprintf(f, sizeof f, "%s/capacity", bat); put(f, "42\n");
    snprintf(f, sizeof f, "%s/status", bat); put(f, "Discharging\n");
    snprintf(f, sizeof f, "%s/type", ac); put(f, "Mains\n");
    snprintf(f, sizeof f, "%s/online", ac); put(f, "0\n");
    setenv("BITTEN_POWER_SUPPLY_PATH", root, 1);
    Ref blob = IOPSCopyPowerSourcesInfo();
    Ref list = IOPSCopyPowerSourcesList(blob);
    CHECK(list && CFArrayGetCount(list) == 1);
    Ref ps = IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(list, 0));
    CHECK(ps && CFGetTypeID(ps) == CFDictionaryGetTypeID());
    int cap = 0;
    CHECK(CFNumberGetValue(CFDictionaryGetValue(ps, S("Current Capacity")), 3, &cap) && cap == 42);
    CHECK(!CFBooleanGetValue(CFDictionaryGetValue(ps, S("Is Charging"))));
    CHECK(CFEqual(CFDictionaryGetValue(ps, S("Power Source State")), S("Battery Power")));
    CHECK(CFEqual(IOPSGetProvidingPowerSourceType(blob), S("Battery Power")));
    snprintf(f, sizeof f, "%s/online", ac); put(f, "1\n");
    CHECK(CFEqual(IOPSGetProvidingPowerSourceType(blob), S("AC Power")));
    setenv("BITTEN_POWER_SUPPLY_PATH", "/nonexistent", 1);
    Ref none = IOPSCopyPowerSourcesInfo();
    CHECK(CFArrayGetCount(IOPSCopyPowerSourcesList(none)) == 0);

    unsigned int a1 = 0, a2 = 0;
    CHECK(IOPMAssertionCreateWithName(S("PreventUserIdleSystemSleep"), 255, S("test"), &a1) == 0);
    CHECK(IOPMAssertionCreateWithName(S("PreventUserIdleSystemSleep"), 255, S("test"), &a2) == 0 && a2 != a1);
    CHECK(IOPMAssertionRelease(a1) == 0);
    Ref byproc = NULL;
    CHECK(IOPMCopyAssertionsByProcess(&byproc) == 0 && byproc && CFDictionaryGetCount(byproc) == 0);

    /* code signing: unsigned */
    Ref code = NULL, info = NULL, req = (Ref)1;
    CHECK(SecStaticCodeCreateWithPath(CFURLCreateWithFileSystemPath(NULL, S("/bin/sh"), 0, 0), 0, &code) == 0 && code);
    CHECK(SecCodeCopySigningInformation(code, 0, &info) == 0 && info);
    CHECK(CFDictionaryGetValue(info, kSecCodeInfoUnique) == NULL);
    CHECK(SecCodeCopyDesignatedRequirement(code, 0, &req) == -67062 && req == NULL);

    /* authorization: refs yes, rights no */
    void *auth = NULL;
    CHECK(AuthorizationCreate(NULL, NULL, 0, &auth) == 0 && auth);
    struct { const char *name; size_t len; void *value; unsigned int flags; } item = {"system.privilege.admin", 0, NULL, 0};
    struct { unsigned int count; void *items; } rights = {1, &item};
    void *granted = (void *)1;
    CHECK(AuthorizationCopyRights(auth, &rights, NULL, 3, &granted) == -60005 && granted == NULL);
    Ref def = (Ref)1;
    CHECK(AuthorizationRightGet("com.example.right", &def) == -60005 && def == NULL);
    CHECK(AuthorizationFree(auth, 0) == 0);

    /* transforms fail closed; keys don't import */
    Ref err = NULL;
    Ref digest = SecDigestTransformCreate(kSecDigestSHA1, 0, &err);
    Ref group = SecTransformCreateGroupTransform();
    CHECK(digest && group && err == NULL);
    CHECK(SecTransformConnectTransforms(digest, kSecTransformInputAttributeName, digest,
                                        kSecTransformInputAttributeName, group, &err) == group);
    CHECK(SecTransformExecute(group, &err) == NULL && err && CFErrorGetCode(err) == -4);
    Ref items = (Ref)1;
    CHECK(SecItemImport(S("key"), NULL, NULL, NULL, 0, NULL, NULL, &items) == -4 && items == NULL);
    Ref ac_obj = SecAccessControlCreateWithFlags(NULL, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, 0, NULL);
    CHECK(ac_obj != NULL);
    char cku[8];
    CHECK(CFStringGetCString(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, cku, sizeof cku, UTF8) && !strcmp(cku, "cku"));
    CHECK(sec_protocol_metadata_get_negotiated_protocol(NULL) == NULL);

    puts("iokit/security ok");
    return 0;
}
