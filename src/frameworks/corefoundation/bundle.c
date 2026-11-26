/* CoreFoundation's bundle, preference and character-set entry points
 * that sit on Foundation's classes, plus string-encoding names.
 *   - CFBundleCopyInfoDictionaryInDirectory reads Contents/Info.plist (or
 *     Info.plist, or Resources/Info.plist) with NSPropertyListSerialization;
 *   - CFBundleCopyExecutableArchitecturesForURL reads the executable's
 *     Mach-O header (thin or fat) and lists its CPU types;
 *   - CFPreferencesCopyAppValue asks NSUserDefaults (the standard ones, or
 *     a suite for another application id);
 *   - CFCharacterSetCreateWithCharactersInRange is NSCharacterSet's.
 * Foundation's objects are CF objects here (toll-free bridging). */
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "cf.h"
#include "dx_objc.h"

typedef void *id;

/* objc_msgSend, cast at each call to the message's signature. */
static void (*msgp)(void);
#define MSGF(ret, ...) ((ret (*)(__VA_ARGS__))msgp)
static bool have_msg(void) {
    if (!msgp) msgp = (void (*)(void))dx_registry_lookup("_objc_msgSend");
    return msgp != NULL;
}

static id send0(id target, const char *sel) {
    return target && have_msg() ? MSGF(id, id, dx_sel)(target, dx_sel_register(sel)) : NULL;
}
static id cls(const char *name) { return (id)dx_objc_lookup_class(name); }

typedef Boolean (*url_path_fn)(const void *, Boolean, uint8_t *, CFIndex);
static bool url_path(const void *url, char *buf, size_t n) {
    url_path_fn f = (url_path_fn)dx_registry_lookup("_CFURLGetFileSystemRepresentation");
    return url && f && f(url, 1, (uint8_t *)buf, (CFIndex)n);
}

static uint8_t *read_file(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *b = n > 0 && n < (64 << 20) ? malloc((size_t)n) : NULL;
    if (b && fread(b, 1, (size_t)n, f) != (size_t)n) { free(b); b = NULL; }
    fclose(f);
    if (b) *len = (size_t)n;
    return b;
}

/* ---- bundles ---- */

static const void *plist_at(const char *path) {
    size_t n;
    uint8_t *bytes = read_file(path, &n);
    if (!bytes) return NULL;
    struct cf_data *data = d_CFDataCreate(NULL, bytes, (CFIndex)n);
    free(bytes);
    id ser = cls("NSPropertyListSerialization");
    id plist = ser && have_msg() ? MSGF(id, id, dx_sel, id, unsigned long, void *, void *)(
                                       ser, dx_sel_register("propertyListWithData:options:format:error:"), (id)data, 0,
                                       NULL, NULL)
                                 : NULL;
    d_CFRelease(data);
    return plist ? dx_objc_retain(plist) : NULL;
}

static const void *d_CFBundleCopyInfoDictionaryInDirectory(const void *bundleURL) {
    char dir[4096], path[4200];
    if (!url_path(bundleURL, dir, sizeof dir)) return NULL;
    static const char *const places[] = {"Contents/Info.plist", "Info.plist", "Resources/Info.plist", NULL};
    for (int i = 0; places[i]; i++) {
        snprintf(path, sizeof path, "%s/%s", dir, places[i]);
        const void *d = plist_at(path);
        if (d) return d;
    }
    return NULL;
}
DX_FN(CFBundleCopyInfoDictionaryInDirectory);

static const void *d_CFBundleCopyInfoDictionaryForURL(const void *url) {
    char path[4096];
    if (!url_path(url, path, sizeof path)) return NULL;
    size_t n = strlen(path);
    if (n > 6 && !strcmp(path + n - 6, ".plist")) return plist_at(path);
    return d_CFBundleCopyInfoDictionaryInDirectory(url);
}
DX_FN(CFBundleCopyInfoDictionaryForURL);

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[3] << 24 | (uint32_t)p[2] << 16 | (uint32_t)p[1] << 8 | p[0]; }

/* The CPU types of a Mach-O file, thin or fat; a bundle's executable is
 * named by CFBundleExecutable, else the bundle's own name. */
static const void *d_CFBundleCopyExecutableArchitecturesForURL(const void *url) {
    char path[4096], exe[4400];
    if (!url_path(url, path, sizeof path)) return NULL;
    snprintf(exe, sizeof exe, "%s", path);
    size_t n = 0;
    uint8_t *b = read_file(exe, &n);
    if (!b) {
        const char *name = strrchr(path, '/');
        name = name ? name + 1 : path;
        char base[256];
        snprintf(base, sizeof base, "%s", name);
        char *dot = strrchr(base, '.');
        if (dot) *dot = 0;
        snprintf(exe, sizeof exe, "%s/Contents/MacOS/%s", path, base);
        b = read_file(exe, &n);
    }
    if (!b || n < 8) { free(b); return NULL; }
    int32_t types[16];
    int count = 0;
    uint32_t magic = be32(b);
    if (magic == 0xcafebabe && n >= 8) {
        uint32_t nfat = be32(b + 4);
        for (uint32_t i = 0; i < nfat && i < 16 && 8 + (i + 1) * 20 <= n; i++) types[count++] = (int32_t)be32(b + 8 + i * 20);
    } else if (le32(b) == 0xfeedfacf || le32(b) == 0xfeedface) {
        types[count++] = (int32_t)le32(b + 4);
    }
    free(b);
    if (!count) return NULL;
    const void *nums[16];
    for (int i = 0; i < count; i++) nums[i] = d_CFNumberCreate(NULL, 3, &types[i]);
    struct cf_array *a = d_CFArrayCreate(NULL, nums, count, &d_kCFTypeArrayCallBacks);
    for (int i = 0; i < count; i++) d_CFRelease(nums[i]);
    return a;
}
DX_FN(CFBundleCopyExecutableArchitecturesForURL);

/* ---- preferences ---- */

static const struct cf_string *d_kCFPreferencesCurrentApplication, *d_kCFPreferencesAnyApplication,
    *d_kCFPreferencesCurrentUser, *d_kCFPreferencesAnyUser, *d_kCFPreferencesCurrentHost, *d_kCFPreferencesAnyHost;
DX_EXPORT("_kCFPreferencesCurrentApplication", &d_kCFPreferencesCurrentApplication);
DX_EXPORT("_kCFPreferencesAnyApplication", &d_kCFPreferencesAnyApplication);
DX_EXPORT("_kCFPreferencesCurrentUser", &d_kCFPreferencesCurrentUser);
DX_EXPORT("_kCFPreferencesAnyUser", &d_kCFPreferencesAnyUser);
DX_EXPORT("_kCFPreferencesCurrentHost", &d_kCFPreferencesCurrentHost);
DX_EXPORT("_kCFPreferencesAnyHost", &d_kCFPreferencesAnyHost);
__attribute__((constructor)) static void prefs_init(void) {
    d_kCFPreferencesCurrentApplication = d___CFStringMakeConstantString("kCFPreferencesCurrentApplication");
    d_kCFPreferencesAnyApplication = d___CFStringMakeConstantString("kCFPreferencesAnyApplication");
    d_kCFPreferencesCurrentUser = d___CFStringMakeConstantString("kCFPreferencesCurrentUser");
    d_kCFPreferencesAnyUser = d___CFStringMakeConstantString("kCFPreferencesAnyUser");
    d_kCFPreferencesCurrentHost = d___CFStringMakeConstantString("kCFPreferencesCurrentHost");
    d_kCFPreferencesAnyHost = d___CFStringMakeConstantString("kCFPreferencesAnyHost");
}

static id defaults_for(const struct cf_string *app) {
    id cls_defaults = cls("NSUserDefaults");
    if (!cls_defaults) return NULL;
    if (!app || d_CFEqual(app, d_kCFPreferencesCurrentApplication) || d_CFEqual(app, d_kCFPreferencesAnyApplication))
        return send0(cls_defaults, "standardUserDefaults");
    id alloc = send0(cls_defaults, "alloc");
    id d = alloc ? MSGF(id, id, dx_sel, id)(alloc, dx_sel_register("initWithSuiteName:"), (id)app) : NULL;
    return d ? dx_objc_autorelease(d) : NULL;
}

static const void *d_CFPreferencesCopyAppValue(const struct cf_string *key, const struct cf_string *app) {
    if (!key) return NULL;
    id d = defaults_for(app);
    id v = d ? MSGF(id, id, dx_sel, id)(d, dx_sel_register("objectForKey:"), (id)key) : NULL;
    return v ? dx_objc_retain(v) : NULL;
}
DX_FN(CFPreferencesCopyAppValue);

static void d_CFPreferencesSetAppValue(const struct cf_string *key, const void *value, const struct cf_string *app) {
    id d = key ? defaults_for(app) : NULL;
    if (!d) return;
    if (value) MSGF(void, id, dx_sel, id, id)(d, dx_sel_register("setObject:forKey:"), (id)value, (id)key);
    else MSGF(void, id, dx_sel, id)(d, dx_sel_register("removeObjectForKey:"), (id)key);
}
DX_FN(CFPreferencesSetAppValue);

static Boolean d_CFPreferencesGetAppBooleanValue(const struct cf_string *key, const struct cf_string *app, Boolean *valid) {
    const void *v = d_CFPreferencesCopyAppValue(key, app);
    if (valid) *valid = v != NULL;
    if (!v) return 0;
    Boolean b = MSGF(Boolean, id, dx_sel)((id)v, dx_sel_register("boolValue"));
    d_CFRelease(v);
    return b;
}
DX_FN(CFPreferencesGetAppBooleanValue);

static Boolean d_CFPreferencesAppSynchronize(const struct cf_string *app) {
    id d = defaults_for(app);
    return d ? MSGF(Boolean, id, dx_sel)(d, dx_sel_register("synchronize")) : 0;
}
DX_FN(CFPreferencesAppSynchronize);

/* ---- character sets ---- */

typedef struct { unsigned long location, length; } NSRange;

static const void *d_CFCharacterSetCreateWithCharactersInRange(const void *allocator, CFRange r) {
    id set = cls("NSCharacterSet");
    if (!set) return NULL;
    if (!have_msg()) return NULL;
    NSRange nr = {(unsigned long)r.location, (unsigned long)r.length};
    id s = MSGF(id, id, dx_sel, NSRange)(set, dx_sel_register("characterSetWithRange:"), nr);
    return s ? dx_objc_retain(s) : NULL;
}
DX_FN(CFCharacterSetCreateWithCharactersInRange);

/* ---- encodings ---- */

static const struct { const char *name; uint32_t cf, ns; } encodings[] = {
    {"utf-8", 0x08000100, 4},       {"utf8", 0x08000100, 4},       {"us-ascii", 0x0600, 1},
    {"ascii", 0x0600, 1},           {"iso-8859-1", 0x0201, 5},     {"latin1", 0x0201, 5},
    {"utf-16", 0x0100, 10},         {"utf-16be", 0x10000100, 0x90000100}, {"utf-16le", 0x14000100, 0x94000100},
    {"utf-32", 0x0c000100, 0x8c000100}, {"utf-32be", 0x18000100, 0x98000100}, {"utf-32le", 0x1c000100, 0x9c000100},
    {"macintosh", 0, 30},           {"x-mac-roman", 0, 30},        {"windows-1252", 0x0500, 12},
    {"cp1252", 0x0500, 12},         {"windows-1251", 0x0502, 11},  {"windows-1250", 0x0501, 15},
    {"iso-8859-2", 0x0202, 9},      {"shift_jis", 0x0a01, 8},      {"euc-jp", 0x0920, 3},
    {"iso-2022-jp", 0x0820, 21},    {NULL, 0, 0},
};

static uint32_t d_CFStringConvertIANACharSetNameToEncoding(const struct cf_string *name) {
    char buf[64];
    typedef Boolean (*get_cstring)(const struct cf_string *, char *, CFIndex, uint32_t);
    get_cstring g = (get_cstring)dx_registry_lookup("_CFStringGetCString");
    if (!name || !g || !g(name, buf, sizeof buf, CF_UTF8)) return 0xffffffff;
    for (int i = 0; encodings[i].name; i++)
        if (!strcasecmp(buf, encodings[i].name)) return encodings[i].cf;
    return 0xffffffff;                                          /* kCFStringEncodingInvalidId */
}
DX_FN(CFStringConvertIANACharSetNameToEncoding);

static const struct cf_string *d_CFStringConvertEncodingToIANACharSetName(uint32_t enc) {
    for (int i = 0; encodings[i].name; i++)
        if (encodings[i].cf == enc) return d___CFStringMakeConstantString(encodings[i].name);
    return NULL;
}
DX_FN(CFStringConvertEncodingToIANACharSetName);

/* NSStringEncoding: the ones Foundation names, else the CF value with the
 * high bit set, as Apple maps them. */
static unsigned long d_CFStringConvertEncodingToNSStringEncoding(uint32_t enc) {
    for (int i = 0; encodings[i].name; i++)
        if (encodings[i].cf == enc) return encodings[i].ns;
    return 0x80000000ul | enc;
}
DX_FN(CFStringConvertEncodingToNSStringEncoding);

static uint32_t d_CFStringConvertNSStringEncodingToEncoding(unsigned long ns) {
    for (int i = 0; encodings[i].name; i++)
        if (encodings[i].ns == ns) return encodings[i].cf;
    return ns & 0x80000000ul ? (uint32_t)(ns & 0x7fffffff) : 0xffffffff;
}
DX_FN(CFStringConvertNSStringEncodingToEncoding);
