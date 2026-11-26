/* IOKit: a registry of one service and the power sources Linux reports.
 *   - IOPlatformExpertDevice, the service programs ask for the machine's
 *     identity: IOPlatformUUID from /etc/machine-id (as a UUID string) and
 *     a serial number derived from it;
 *   - matching by IOProviderClass or IONameMatch; iterators over the
 *     matches; no children;
 *   - power sources (IOPS*) from /sys/class/power_supply: each battery as
 *     an "InternalBattery" with its capacity and charging state;
 *   - power assertions are counted and released, and prevent nothing.
 * io_object_t handles are small integers: services are fixed, iterators
 * come from a table and go back on IOObjectRelease. */
#include <ctype.h>
#include <dirent.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../corefoundation/cf.h"

typedef uint32_t io_object_t;
typedef int32_t kern_return_t;
enum { KERN_SUCCESS = 0, KERN_INVALID_ARGUMENT = 4, KERN_NO_SPACE = 3, KERN_RESOURCE_SHORTAGE = 6 };
enum { IO_NOT_FOUND = (int32_t)0xe00002f0 };   /* kIOReturnNotFound */

static const uint32_t d_kIOMainPortDefault = 0, d_kIOMasterPortDefault = 0;
DX_EXPORT("_kIOMainPortDefault", &d_kIOMainPortDefault);
DX_EXPORT("_kIOMasterPortDefault", &d_kIOMasterPortDefault);

/* CoreFoundation's mutable collections, from the registry. */
#define CF_CALL(name, type) ((type)dx_registry_lookup("_" #name))
typedef struct cf_dict *(*dict_create_mutable)(const void *, CFIndex, const void *, const void *);
typedef void (*dict_set)(struct cf_dict *, const void *, const void *);
typedef struct cf_array *(*array_create_mutable)(const void *, CFIndex, const void *);
typedef void (*array_append)(struct cf_array *, const void *);
typedef Boolean (*string_get_cstring)(const struct cf_string *, char *, CFIndex, CFStringEncoding);

static struct cf_string *str(const char *s) { return d_CFStringCreateWithCString(NULL, s, CF_UTF8); }
static struct cf_dict *mutable_dict(void) {
    return CF_CALL(CFDictionaryCreateMutable, dict_create_mutable)(NULL, 0, &d_kCFTypeDictionaryKeyCallBacks,
                                                                  &d_kCFTypeDictionaryValueCallBacks);
}
static void put(struct cf_dict *d, const char *key, const void *value) {
    struct cf_string *k = str(key);
    CF_CALL(CFDictionarySetValue, dict_set)(d, k, value);
    d_CFRelease(k);
    d_CFRelease(value);
}
static void put_int(struct cf_dict *d, const char *key, int v) { put(d, key, d_CFNumberCreate(NULL, 3, &v)); }
static void put_str(struct cf_dict *d, const char *key, const char *v) { put(d, key, str(v)); }
static void put_bool(struct cf_dict *d, const char *key, bool v) {
    const void **slot = dx_registry_lookup(v ? "_kCFBooleanTrue" : "_kCFBooleanFalse");
    put(d, key, d_CFRetain(*slot));
}
static bool cstring(const void *s, char *buf, size_t n) {
    if (!s || d_CFGetTypeID(s) != CF_STRING) return false;
    return CF_CALL(CFStringGetCString, string_get_cstring)(s, buf, (CFIndex)n, CF_UTF8);
}

/* ---- the registry ---- */

enum { SERVICE_PLATFORM = 1, NSERVICES };
static const char *const service_class[NSERVICES] = {[SERVICE_PLATFORM] = "IOPlatformExpertDevice"};
static const char *const service_name[NSERVICES] = {[SERVICE_PLATFORM] = "Bitten1,1"};

static void machine_uuid(char out[37]) {
    char id[64] = {0};
    FILE *f = fopen("/etc/machine-id", "r");
    if (!f) f = fopen("/var/lib/dbus/machine-id", "r");
    if (f) {
        if (!fgets(id, sizeof id, f)) id[0] = 0;
        fclose(f);
    }
    char hex[33];
    size_t n = 0;
    for (char *p = id; *p && n < 32; p++) if (isxdigit((unsigned char)*p)) hex[n++] = (char)toupper((unsigned char)*p);
    while (n < 32) hex[n++] = '0';
    hex[32] = 0;
    snprintf(out, 37, "%.8s-%.4s-%.4s-%.4s-%.12s", hex, hex + 8, hex + 12, hex + 16, hex + 20);
}

static const void *service_property(io_object_t s, const char *key) {
    if (s != SERVICE_PLATFORM) return NULL;
    char uuid[37];
    machine_uuid(uuid);
    if (!strcmp(key, "IOPlatformUUID")) return str(uuid);
    if (!strcmp(key, "IOPlatformSerialNumber")) {
        char serial[16];
        snprintf(serial, sizeof serial, "BN%.8s", uuid);
        return str(serial);
    }
    if (!strcmp(key, "model") || !strcmp(key, "IOPlatformModel")) return d_CFDataCreate(NULL, (const uint8_t *)"Bitten1,1", 10);
    if (!strcmp(key, "manufacturer")) return d_CFDataCreate(NULL, (const uint8_t *)"bitten", 7);
    return NULL;
}

/* Iterators: handles from 0x100 up. */
#define FIRST_ITERATOR 0x100
#define MAX_ITERATORS 256
static struct iterator { bool used; io_object_t items[NSERVICES]; int count, pos; } iterators[MAX_ITERATORS];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static struct iterator *iterator_of(io_object_t h) {
    if (h < FIRST_ITERATOR || h >= FIRST_ITERATOR + MAX_ITERATORS) return NULL;
    struct iterator *it = &iterators[h - FIRST_ITERATOR];
    return it->used ? it : NULL;
}
static io_object_t new_iterator(const io_object_t *items, int count) {
    pthread_mutex_lock(&lock);
    for (int i = 0; i < MAX_ITERATORS; i++) {
        if (iterators[i].used) continue;
        iterators[i] = (struct iterator){.used = true, .count = count};
        memcpy(iterators[i].items, items, (size_t)count * sizeof *items);
        pthread_mutex_unlock(&lock);
        return FIRST_ITERATOR + (io_object_t)i;
    }
    pthread_mutex_unlock(&lock);
    return 0;
}

static struct cf_dict *matching(const char *key, const char *name) {
    if (!name) return NULL;
    struct cf_dict *d = mutable_dict();
    put_str(d, key, name);
    return d;
}
static struct cf_dict *d_IOServiceMatching(const char *name) { return matching("IOProviderClass", name); }
DX_FN(IOServiceMatching);
static struct cf_dict *d_IOServiceNameMatching(const char *name) { return matching("IONameMatch", name); }
DX_FN(IOServiceNameMatching);

static int match(const struct cf_dict *m, io_object_t *out) {
    char cls[128] = "", name[128] = "";
    if (m) {
        const void *k = str("IOProviderClass"), *n = str("IONameMatch");
        cstring(d_CFDictionaryGetValue(m, k), cls, sizeof cls);
        cstring(d_CFDictionaryGetValue(m, n), name, sizeof name);
        d_CFRelease(k);
        d_CFRelease(n);
    }
    int count = 0;
    for (io_object_t s = 1; s < NSERVICES; s++) {
        bool ok = (cls[0] && (!strcmp(cls, service_class[s]) || !strcmp(cls, "IOService"))) ||
                  (name[0] && !strcmp(name, service_name[s]));
        if (ok) out[count++] = s;
    }
    return count;
}

/* Both consume one reference to the matching dictionary. */
static kern_return_t d_IOServiceGetMatchingServices(uint32_t port, struct cf_dict *m, io_object_t *iter) {
    io_object_t found[NSERVICES];
    int n = match(m, found);
    if (m) d_CFRelease(m);
    if (!iter) return KERN_INVALID_ARGUMENT;
    *iter = new_iterator(found, n);
    return *iter ? KERN_SUCCESS : KERN_NO_SPACE;
}
DX_FN(IOServiceGetMatchingServices);
static io_object_t d_IOServiceGetMatchingService(uint32_t port, struct cf_dict *m) {
    io_object_t found[NSERVICES];
    int n = match(m, found);
    if (m) d_CFRelease(m);
    return n ? found[0] : 0;
}
DX_FN(IOServiceGetMatchingService);

static io_object_t d_IOIteratorNext(io_object_t h) {
    pthread_mutex_lock(&lock);
    struct iterator *it = iterator_of(h);
    io_object_t r = it && it->pos < it->count ? it->items[it->pos++] : 0;
    pthread_mutex_unlock(&lock);
    return r;
}
DX_FN(IOIteratorNext);
static void d_IOIteratorReset(io_object_t h) {
    pthread_mutex_lock(&lock);
    struct iterator *it = iterator_of(h);
    if (it) it->pos = 0;
    pthread_mutex_unlock(&lock);
}
DX_FN(IOIteratorReset);
static Boolean d_IOIteratorIsValid(io_object_t h) { return iterator_of(h) != NULL; }
DX_FN(IOIteratorIsValid);

static kern_return_t d_IORegistryEntryGetChildIterator(io_object_t entry, const char *plane, io_object_t *iter) {
    if (!iter) return KERN_INVALID_ARGUMENT;
    *iter = new_iterator(NULL, 0);
    return *iter ? KERN_SUCCESS : KERN_NO_SPACE;
}
DX_FN(IORegistryEntryGetChildIterator);
static kern_return_t d_IORegistryEntryGetParentEntry(io_object_t entry, const char *plane, io_object_t *parent) {
    if (parent) *parent = 0;
    return IO_NOT_FOUND;
}
DX_FN(IORegistryEntryGetParentEntry);

/* "IOService:/" is the platform expert, as on a Mac. */
static io_object_t d_IORegistryEntryFromPath(uint32_t port, const char *path) {
    return path && (!strcmp(path, "IOService:/") || !strcmp(path, "IODeviceTree:/")) ? SERVICE_PLATFORM : 0;
}
DX_FN(IORegistryEntryFromPath);
static io_object_t d_IORegistryGetRootEntry(uint32_t port) { return SERVICE_PLATFORM; }
DX_FN(IORegistryGetRootEntry);

static const void *d_IORegistryEntryCreateCFProperty(io_object_t entry, const struct cf_string *key,
                                                     const void *allocator, uint32_t options) {
    char k[128];
    return cstring(key, k, sizeof k) ? service_property(entry, k) : NULL;
}
DX_FN(IORegistryEntryCreateCFProperty);
static const void *d_IORegistryEntrySearchCFProperty(io_object_t entry, const char *plane, const struct cf_string *key,
                                                     const void *allocator, uint32_t options) {
    return d_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
}
DX_FN(IORegistryEntrySearchCFProperty);

static kern_return_t d_IORegistryEntryGetName(io_object_t entry, char name[128]) {
    if (entry <= 0 || entry >= NSERVICES || !name) return KERN_INVALID_ARGUMENT;
    snprintf(name, 128, "%s", service_name[entry]);
    return KERN_SUCCESS;
}
DX_FN(IORegistryEntryGetName);
static Boolean d_IOObjectConformsTo(io_object_t o, const char *cls) {
    return o > 0 && o < NSERVICES && cls && (!strcmp(cls, service_class[o]) || !strcmp(cls, "IOService"));
}
DX_FN(IOObjectConformsTo);

static kern_return_t d_IOObjectRelease(io_object_t o) {
    pthread_mutex_lock(&lock);
    struct iterator *it = iterator_of(o);
    if (it) it->used = false;
    pthread_mutex_unlock(&lock);
    return KERN_SUCCESS;
}
DX_FN(IOObjectRelease);
static kern_return_t d_IOObjectRetain(io_object_t o) { return KERN_SUCCESS; }
DX_FN(IOObjectRetain);

/* ---- power sources ---- */

static bool read_line(const char *dir, const char *file, char *out, size_t n) {
    char path[512];
    snprintf(path, sizeof path, "%s/%s", dir, file);
    FILE *f = fopen(path, "r");
    if (!f) return false;
    bool ok = fgets(out, (int)n, f) != NULL;
    fclose(f);
    if (ok) out[strcspn(out, "\n")] = 0;
    return ok;
}

static const char *power_root(void) {
    const char *r = getenv("BITTEN_POWER_SUPPLY_PATH");
    return r && *r ? r : "/sys/class/power_supply";
}

/* On AC power unless a battery says it is discharging. */
static bool on_ac(void) {
    DIR *d = opendir(power_root());
    if (!d) return true;
    bool ac = true, any_ac = false, ac_online = false;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char dir[512], type[32] = "", v[32] = "";
        snprintf(dir, sizeof dir, "%s/%s", power_root(), e->d_name);
        read_line(dir, "type", type, sizeof type);
        if (!strcmp(type, "Mains")) {
            any_ac = true;
            if (read_line(dir, "online", v, sizeof v) && atoi(v)) ac_online = true;
        } else if (!strcmp(type, "Battery") && read_line(dir, "status", v, sizeof v) && !strcmp(v, "Discharging")) {
            ac = false;
        }
    }
    closedir(d);
    return any_ac ? ac_online : ac;
}

/* An array of one dictionary per battery. */
static struct cf_array *d_IOPSCopyPowerSourcesInfo(void) {
    struct cf_array *list = CF_CALL(CFArrayCreateMutable, array_create_mutable)(NULL, 0, &d_kCFTypeArrayCallBacks);
    DIR *d = opendir(power_root());
    if (!d) return list;
    struct dirent *e;
    int index = 0;
    bool ac = on_ac();
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char dir[512], type[32] = "", v[64] = "";
        snprintf(dir, sizeof dir, "%s/%s", power_root(), e->d_name);
        if (!read_line(dir, "type", type, sizeof type) || strcmp(type, "Battery")) continue;
        struct cf_dict *ps = mutable_dict();
        char name[48];
        snprintf(name, sizeof name, "InternalBattery-%d", index++);
        put_str(ps, "Name", name);
        put_str(ps, "Type", "InternalBattery");
        put_str(ps, "Transport Type", "Internal");
        put_bool(ps, "Is Present", !read_line(dir, "present", v, sizeof v) || atoi(v));
        int capacity = read_line(dir, "capacity", v, sizeof v) ? atoi(v) : 100;
        put_int(ps, "Current Capacity", capacity);
        put_int(ps, "Max Capacity", 100);
        char status[32] = "";
        read_line(dir, "status", status, sizeof status);
        put_bool(ps, "Is Charging", !strcmp(status, "Charging"));
        put_bool(ps, "Is Charged", !strcmp(status, "Full") || capacity >= 100);
        put_str(ps, "Power Source State", ac ? "AC Power" : "Battery Power");
        put_int(ps, "Time to Empty", -1);
        put_int(ps, "Time to Full Charge", -1);
        CF_CALL(CFArrayAppendValue, array_append)(list, ps);
        d_CFRelease(ps);
    }
    closedir(d);
    return list;
}
DX_FN(IOPSCopyPowerSourcesInfo);

static const void *d_IOPSCopyPowerSourcesList(const void *blob) {
    return blob && d_CFGetTypeID(blob) == CF_ARRAY ? d_CFArrayCreateCopy(NULL, blob) : NULL;
}
DX_FN(IOPSCopyPowerSourcesList);
/* The source is its own description (not retained: a Get function). */
static const void *d_IOPSGetPowerSourceDescription(const void *blob, const void *ps) {
    return ps && d_CFGetTypeID(ps) == CF_DICTIONARY ? ps : NULL;
}
DX_FN(IOPSGetPowerSourceDescription);
static const void *d_IOPSGetProvidingPowerSourceType(const void *blob) {
    static const struct cf_string *ac, *battery;
    if (!ac) {
        ac = d___CFStringMakeConstantString("AC Power");
        battery = d___CFStringMakeConstantString("Battery Power");
    }
    return on_ac() ? ac : battery;
}
DX_FN(IOPSGetProvidingPowerSourceType);
static double d_IOPSGetTimeRemainingEstimate(void) { return on_ac() ? -2.0 : -1.0; } /* unlimited / unknown */
DX_FN(IOPSGetTimeRemainingEstimate);

/* ---- power management assertions ---- */

static uint32_t next_assertion = 1;
static kern_return_t d_IOPMAssertionCreateWithName(const void *type, uint32_t level, const void *name, uint32_t *id) {
    if (!id) return KERN_INVALID_ARGUMENT;
    *id = __atomic_fetch_add(&next_assertion, 1, __ATOMIC_RELAXED);
    return KERN_SUCCESS;
}
DX_FN(IOPMAssertionCreateWithName);
static kern_return_t d_IOPMAssertionCreateWithDescription(const void *type, const void *name, const void *details,
                                                          const void *reason, const void *bundle, double timeout,
                                                          const void *action, uint32_t *id) {
    return d_IOPMAssertionCreateWithName(type, 255, name, id);
}
DX_FN(IOPMAssertionCreateWithDescription);
static kern_return_t d_IOPMAssertionRelease(uint32_t id) { return KERN_SUCCESS; }
DX_FN(IOPMAssertionRelease);
static kern_return_t d_IOPMAssertionDeclareUserActivity(const void *name, int type, uint32_t *id) {
    return d_IOPMAssertionCreateWithName(NULL, 255, name, id);
}
DX_FN(IOPMAssertionDeclareUserActivity);
/* By process: no assertions anywhere. */
static kern_return_t d_IOPMCopyAssertionsByProcess(struct cf_dict **out) {
    if (!out) return KERN_INVALID_ARGUMENT;
    *out = mutable_dict();
    return KERN_SUCCESS;
}
DX_FN(IOPMCopyAssertionsByProcess);
static kern_return_t d_IOPMCopyAssertionsStatus(struct cf_dict **out) { return d_IOPMCopyAssertionsByProcess(out); }
DX_FN(IOPMCopyAssertionsStatus);
