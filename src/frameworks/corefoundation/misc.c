#define _GNU_SOURCE
#include <ctype.h>
#include <errno.h>
#include <string.h>
#include <sys/random.h>
#include <time.h>
#include <unistd.h>

#include "cf.h"

#define CF_STRING_CONSTANT(name) \
    static const struct cf_string *d_##name; \
    DX_EXPORT("_" #name, &d_##name)

CF_STRING_CONSTANT(kCFErrorDomainPOSIX);
const struct cf_string *d_kCFErrorDomainOSStatus;
DX_EXPORT("_kCFErrorDomainOSStatus", &d_kCFErrorDomainOSStatus);
CF_STRING_CONSTANT(kCFErrorDomainMach);
CF_STRING_CONSTANT(kCFErrorDomainCocoa);
const struct cf_string *d_kCFErrorLocalizedDescriptionKey;
DX_EXPORT("_kCFErrorLocalizedDescriptionKey", &d_kCFErrorLocalizedDescriptionKey);
CF_STRING_CONSTANT(kCFErrorLocalizedFailureReasonKey);
CF_STRING_CONSTANT(kCFErrorDescriptionKey);
CF_STRING_CONSTANT(kCFLocaleIdentifier);
CF_STRING_CONSTANT(kCFLocaleLanguageCode);
CF_STRING_CONSTANT(kCFLocaleCountryCode);

__attribute__((constructor)) static void cf_init_strings(void) {
    d_kCFErrorDomainPOSIX = d___CFStringMakeConstantString("NSPOSIXErrorDomain");
    d_kCFErrorDomainOSStatus = d___CFStringMakeConstantString("NSOSStatusErrorDomain");
    d_kCFErrorDomainMach = d___CFStringMakeConstantString("NSMachErrorDomain");
    d_kCFErrorDomainCocoa = d___CFStringMakeConstantString("NSCocoaErrorDomain");
    d_kCFErrorLocalizedDescriptionKey = d___CFStringMakeConstantString("NSLocalizedDescription");
    d_kCFErrorLocalizedFailureReasonKey = d___CFStringMakeConstantString("NSLocalizedFailureReason");
    d_kCFErrorDescriptionKey = d___CFStringMakeConstantString("NSDescription");
    d_kCFLocaleIdentifier = d___CFStringMakeConstantString("kCFLocaleIdentifier");
    d_kCFLocaleLanguageCode = d___CFStringMakeConstantString("kCFLocaleLanguageCode");
    d_kCFLocaleCountryCode = d___CFStringMakeConstantString("kCFLocaleCountryCode");
}

struct cf_date {
    struct cf_object base;
    double time;
};

static Boolean date_equal(const void *left, const void *right) {
    const struct cf_date *a = left, *b = right;
    return a->time == b->time;
}
static CFHashCode date_hash(const void *object) {
    const struct cf_date *d = object;
    double time = d->time == 0 ? 0 : d->time;
    return cf_hash_bytes(&time, sizeof time);
}
static const struct cf_ops date_ops = {.equal = date_equal, .hash = date_hash};
CF_TYPE_ID(CFDate, CF_DATE);

static struct cf_date *d_CFDateCreate(const void *allocator, double time) {
    struct cf_date *d = cf_alloc(allocator, sizeof *d, CF_DATE, &date_ops);
    if (d) d->time = time;
    return d;
}
DX_FN(CFDateCreate);

static double d_CFAbsoluteTimeGetCurrent(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now)) return 0;
    return (double)now.tv_sec - 978307200.0 + now.tv_nsec / 1e9;
}
DX_FN(CFAbsoluteTimeGetCurrent);

static double d_CFDateGetAbsoluteTime(const struct cf_date *d) { return d ? d->time : 0; }
DX_FN(CFDateGetAbsoluteTime);

static double d_CFDateGetTimeIntervalSinceDate(const struct cf_date *a, const struct cf_date *b) {
    return a->time - b->time;
}
DX_FN(CFDateGetTimeIntervalSinceDate);

struct cf_error {
    struct cf_object base;
    struct cf_string *domain;
    CFIndex code;
    struct cf_dict *info;
};

static struct cf_string *d_CFErrorCopyDescription(const struct cf_error *error);
static struct cf_string *error_desc(const void *object) { return d_CFErrorCopyDescription(object); }
static void error_destroy(void *object) {
    struct cf_error *e = object;
    d_CFRelease(e->domain);
    d_CFRelease(e->info);
}
static Boolean error_equal(const void *left, const void *right) {
    const struct cf_error *a = left, *b = right;
    return a->code == b->code && d_CFEqual(a->domain, b->domain) && d_CFEqual(a->info, b->info);
}
static CFHashCode error_hash(const void *object) {
    const struct cf_error *e = object;
    return d_CFHash(e->domain) ^ (CFHashCode)e->code;
}
static const struct cf_ops error_ops = {
    .destroy = error_destroy, .equal = error_equal, .hash = error_hash, .describe = error_desc,
};
CF_TYPE_ID(CFError, CF_ERROR);

struct cf_error *d_CFErrorCreate(const void *allocator, const struct cf_string *domain,
                               CFIndex code, const struct cf_dict *info) {
    if (d_CFGetTypeID(domain) != CF_STRING || (info && d_CFGetTypeID(info) != CF_DICTIONARY))
        return NULL;
    struct cf_error *e = cf_alloc(allocator, sizeof *e, CF_ERROR, &error_ops);
    if (!e) return NULL;
    e->domain = d_CFStringCreateCopy(allocator, domain);
    e->info = info ? d_CFDictionaryCreateCopy(allocator, info)
                   : d_CFDictionaryCreate(allocator, NULL, NULL, 0, &d_kCFTypeDictionaryKeyCallBacks,
                                          &d_kCFTypeDictionaryValueCallBacks);
    if (!e->domain || !e->info) { d_CFRelease(e); return NULL; }
    e->code = code;
    return e;
}
DX_FN(CFErrorCreate);

static CFIndex d_CFErrorGetCode(const struct cf_error *e) { return e ? e->code : 0; }
DX_FN(CFErrorGetCode);

static const struct cf_string *d_CFErrorGetDomain(const struct cf_error *e) { return e ? e->domain : NULL; }
DX_FN(CFErrorGetDomain);

static const struct cf_dict *d_CFErrorCopyUserInfo(const struct cf_error *e) {
    return e ? d_CFRetain(e->info) : NULL;
}
DX_FN(CFErrorCopyUserInfo);

static struct cf_string *d_CFErrorCopyDescription(const struct cf_error *e) {
    if (!e) return NULL;
    const void *message = d_CFDictionaryGetValue(e->info, d_kCFErrorLocalizedDescriptionKey);
    if (d_CFGetTypeID(message) == CF_STRING) return d_CFStringCreateCopy(NULL, message);
    message = d_CFDictionaryGetValue(e->info, d_kCFErrorLocalizedFailureReasonKey);
    if (d_CFGetTypeID(message) != CF_STRING)
        message = d_CFDictionaryGetValue(e->info, d_kCFErrorDescriptionKey);
    const char *detail = d_CFGetTypeID(message) == CF_STRING ? d_CFStringGetCStringPtr(message, CF_UTF8) : NULL;
    if (!detail && d_CFEqual(e->domain, d_kCFErrorDomainPOSIX) && e->code > 0 && e->code <= INT_MAX)
        detail = strerror(dx_errno_from_darwin(e->code));
    const char *domain = d_CFStringGetCStringPtr(e->domain, CF_UTF8);
    char *text = NULL;
    if (asprintf(&text, "The operation couldn’t be completed. (%s error %ld%s%s)",
                 domain ? domain : "CFError", e->code, detail ? " - " : "", detail ? detail : "") < 0)
        return NULL;
    struct cf_string *description = d_CFStringCreateWithCString(NULL, text, CF_UTF8);
    free(text);
    return description;
}
DX_FN(CFErrorCopyDescription);

struct cf_locale {
    struct cf_object base;
    struct cf_string *language, *country, *identifier;
};

static void locale_destroy(void *object) {
    struct cf_locale *locale = object;
    d_CFRelease(locale->language);
    d_CFRelease(locale->country);
    d_CFRelease(locale->identifier);
}
static Boolean locale_equal(const void *left, const void *right) {
    const struct cf_locale *a = left, *b = right;
    return d_CFEqual(a->identifier, b->identifier);
}
static CFHashCode locale_hash(const void *object) {
    const struct cf_locale *locale = object;
    return d_CFHash(locale->identifier);
}
static const struct cf_ops locale_ops = {.destroy = locale_destroy, .equal = locale_equal, .hash = locale_hash};
CF_TYPE_ID(CFLocale, CF_LOCALE);

static struct cf_locale *d_CFLocaleCopyCurrent(void) {
    const char *env = getenv("LC_ALL");
    if (!env || !*env) env = getenv("LANG");
    char language[9] = "en", country[4] = "US";
    if (env) {
        size_t n = strspn(env, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");
        if (n >= 2 && n < sizeof language) {
            for (size_t i = 0; i < n; i++) language[i] = tolower((unsigned char)env[i]);
            language[n] = 0;
            for (const char *p = env + n; *p == '_' || *p == '-'; p += n) {
                p++;
                n = strcspn(p, "_-.@");
                if (n == 2 && isalpha((unsigned char)p[0]) && isalpha((unsigned char)p[1])) {
                    country[0] = toupper((unsigned char)p[0]);
                    country[1] = toupper((unsigned char)p[1]);
                    break;
                }
                if (n == 3 && strspn(p, "0123456789") == 3) {
                    memcpy(country, p, 3);
                    break;
                }
            }
        }
    }
    char identifier[sizeof language + sizeof country];
    snprintf(identifier, sizeof identifier, "%s_%s", language, country);
    struct cf_locale *locale = cf_alloc(NULL, sizeof *locale, CF_LOCALE, &locale_ops);
    if (!locale) return NULL;
    locale->language = d_CFStringCreateWithCString(NULL, language, CF_UTF8);
    locale->country = d_CFStringCreateWithCString(NULL, country, CF_UTF8);
    locale->identifier = d_CFStringCreateWithCString(NULL, identifier, CF_UTF8);
    if (!locale->language || !locale->country || !locale->identifier) {
        d_CFRelease(locale);
        return NULL;
    }
    return locale;
}
DX_FN(CFLocaleCopyCurrent);

static const struct cf_string *d_CFLocaleGetIdentifier(const struct cf_locale *locale) {
    return locale ? locale->identifier : NULL;
}
DX_FN(CFLocaleGetIdentifier);

static const void *d_CFLocaleGetValue(const struct cf_locale *locale, const struct cf_string *key) {
    if (!locale || !key) return NULL;
    if (d_CFEqual(key, d_kCFLocaleLanguageCode)) return locale->language;
    if (d_CFEqual(key, d_kCFLocaleCountryCode)) return locale->country;
    if (d_CFEqual(key, d_kCFLocaleIdentifier)) return locale->identifier;
    return NULL;
}
DX_FN(CFLocaleGetValue);

struct cf_uuid {
    struct cf_object base;
    uint8_t bytes[16];
};
static Boolean uuid_equal(const void *left, const void *right) {
    const struct cf_uuid *a = left, *b = right;
    return !memcmp(a->bytes, b->bytes, sizeof a->bytes);
}
static CFHashCode uuid_hash(const void *object) {
    const struct cf_uuid *u = object;
    return cf_hash_bytes(u->bytes, sizeof u->bytes);
}
static const struct cf_ops uuid_ops = {.equal = uuid_equal, .hash = uuid_hash};
CF_TYPE_ID(CFUUID, CF_UUID);

static struct cf_uuid *d_CFUUIDCreate(const void *allocator) {
    struct cf_uuid *u = cf_alloc(allocator, sizeof *u, CF_UUID, &uuid_ops);
    if (!u) return NULL;
    size_t filled = 0;
    while (filled < sizeof u->bytes) {
        ssize_t n = getrandom(u->bytes + filled, sizeof u->bytes - filled, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { d_CFRelease(u); return NULL; }
        filled += n;
    }
    u->bytes[6] = (u->bytes[6] & 0xf) | 0x40;
    u->bytes[8] = (u->bytes[8] & 0x3f) | 0x80;
    return u;
}
DX_FN(CFUUIDCreate);

static const char hex[] = "0123456789ABCDEF";

static int hex_value(unsigned char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if ((c | 32) >= 'a' && (c | 32) <= 'f') return (c | 32) - 'a' + 10;
    return -1;
}

static struct cf_string *d_CFUUIDCreateString(const void *allocator, const struct cf_uuid *u) {
    if (!u) return NULL;
    char text[37], *p = text;
    for (size_t i = 0; i < sizeof u->bytes; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10) *p++ = '-';
        *p++ = hex[u->bytes[i] >> 4];
        *p++ = hex[u->bytes[i] & 15];
    }
    *p = 0;
    return d_CFStringCreateWithCString(allocator, text, CF_ASCII);
}
DX_FN(CFUUIDCreateString);

static struct cf_uuid *d_CFUUIDCreateFromString(const void *allocator, const struct cf_string *s) {
    const char *p = d_CFStringGetCStringPtr(s, CF_ASCII);
    if (!p || strlen(p) != 36) return NULL;
    uint8_t bytes[16];
    for (size_t i = 0; i < sizeof bytes; i++) {
        if ((i == 4 || i == 6 || i == 8 || i == 10) && *p++ != '-') return NULL;
        int hi = hex_value(*p++), lo = hex_value(*p++);
        if (hi < 0 || lo < 0) return NULL;
        bytes[i] = (hi << 4) | lo;
    }
    struct cf_uuid *u = cf_alloc(allocator, sizeof *u, CF_UUID, &uuid_ops);
    if (u) memcpy(u->bytes, bytes, sizeof bytes);
    return u;
}
DX_FN(CFUUIDCreateFromString);

struct cf_url {
    struct cf_object base;
    struct cf_string *string;
    const struct cf_url *relative_to;
};

static void url_destroy(void *object) {
    struct cf_url *url = object;
    d_CFRelease(url->string);
    d_CFRelease(url->relative_to);
}
static Boolean url_equal(const void *left, const void *right) {
    const struct cf_url *a = left, *b = right;
    return d_CFEqual(a->string, b->string) && d_CFEqual(a->relative_to, b->relative_to);
}
static CFHashCode url_hash(const void *object) {
    const struct cf_url *url = object;
    return d_CFHash(url->string) ^ d_CFHash(url->relative_to);
}
static struct cf_string *url_desc(const void *object) {
    return d_CFStringCreateCopy(NULL, ((const struct cf_url *)object)->string);
}
static const struct cf_ops url_ops = {.destroy = url_destroy, .equal = url_equal, .hash = url_hash,
                                      .describe = url_desc};
CF_TYPE_ID(CFURL, CF_URL);

static const char *url_scheme_end(const char *p) {
    if (!isalpha((unsigned char)*p)) return NULL;
    p++;
    while (*p && (isalnum((unsigned char)*p) || *p == '+' || *p == '-' || *p == '.')) p++;
    return *p == ':' ? p : NULL;
}

static struct cf_url *d_CFURLCreateWithString(const void *allocator, const struct cf_string *string,
                                              const struct cf_url *base) {
    const char *s = d_CFStringGetCStringPtr(string, CF_UTF8);
    if (!s) return NULL;
    struct cf_url *url = cf_alloc(allocator, sizeof *url, CF_URL, &url_ops);
    if (!url) return NULL;
    url->string = d_CFStringCreateCopy(allocator, string);
    if (!url->string) { d_CFRelease(url); return NULL; }
    if (!url_scheme_end(s)) url->relative_to = d_CFRetain(base);
    return url;
}
DX_FN(CFURLCreateWithString);

static struct cf_url *file_url(const void *allocator, const char *path, Boolean dir,
                               const struct cf_url *base) {
    static const char prefix[] = "file://";
    size_t n = strlen(path);
    if (!n || n > (SIZE_MAX - sizeof prefix - 2) / 3) return NULL;
    char *text = malloc(3 * n + sizeof prefix + 2);
    if (!text) return NULL;
    char *out = text;
    if (*path == '/') {
        memcpy(out, prefix, sizeof prefix - 1);
        out += sizeof prefix - 1;
    }
    for (const unsigned char *p = (const unsigned char *)path; *p; p++) {
        unsigned char c = *p;
        if ((c < 128 && isalnum(c)) || c == '-' || c == '_' || c == '.' || c == '~' || c == '/') {
            *out++ = c;
        } else {
            *out++ = '%';
            *out++ = hex[c >> 4];
            *out++ = hex[c & 15];
        }
    }
    if (dir && out[-1] != '/') *out++ = '/';
    *out = 0;
    struct cf_string *s = d_CFStringCreateWithCString(NULL, text, CF_UTF8);
    struct cf_url *url = d_CFURLCreateWithString(allocator, s, base);
    d_CFRelease(s);
    free(text);
    return url;
}

static struct cf_url *d_CFURLCreateWithFileSystemPath(const void *allocator,
                                                      const struct cf_string *path, CFIndex style,
                                                      Boolean dir) {
    const char *text = d_CFStringGetCStringPtr(path, CF_UTF8);
    if (style != 0 || !text || !*text) return NULL;
    if (*text == '/') return file_url(allocator, text, dir, NULL);
    char *cwd = getcwd(NULL, 0);
    struct cf_url *base = cwd ? file_url(NULL, cwd, 1, NULL) : NULL;
    free(cwd);
    if (!base) return NULL;
    struct cf_url *url = file_url(allocator, text, dir, base);
    d_CFRelease(base);
    return url;
}
DX_FN(CFURLCreateWithFileSystemPath);

static const struct cf_string *d_CFURLGetString(const struct cf_url *url) { return url ? url->string : NULL; }
DX_FN(CFURLGetString);

static const struct cf_url *d_CFURLGetBaseURL(const struct cf_url *url) {
    return url ? url->relative_to : NULL;
}
DX_FN(CFURLGetBaseURL);

static char *url_path(const struct cf_url *url, Boolean resolve) {
    if (!url) return NULL;
    const char *text = d_CFStringGetCStringPtr(url->string, CF_UTF8);
    const char *scheme = url_scheme_end(text);
    if (scheme) {
        if (scheme - text != 4 || strncasecmp(text, "file", 4)) return NULL;
        text = scheme + 1;
    }
    if (text[0] == '/' && text[1] == '/') {
        const char *slash = strchr(text + 2, '/');
        if (!slash || (slash != text + 2 &&
                       (slash - text != 11 || strncasecmp(text + 2, "localhost", 9)))) return NULL;
        text = slash;
    }
    size_t n = strcspn(text, "?#");
    char *base = NULL;
    size_t prefix = 0;
    if (resolve && url->relative_to && *text != '/') {
        base = url_path(url->relative_to, 1);
        if (!base) return NULL;
        char *slash = strrchr(base, '/');
        if (slash) prefix = slash - base + 1;
    }
    if (n >= SIZE_MAX - prefix) { free(base); return NULL; }
    char *path = malloc(prefix + n + 1);
    if (!path) { free(base); return NULL; }
    if (prefix) memcpy(path, base, prefix);
    free(base);
    char *out = path + prefix;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = text[i];
        if (c == '%' && n - i >= 3) {
            int hi = hex_value(text[i + 1]), lo = hex_value(text[i + 2]);
            if (hi >= 0 && lo >= 0) {
                c = (hi << 4) | lo;
                if (!c) { free(path); return NULL; }
                i += 2;
            }
        }
        *out++ = c;
    }
    *out = 0;
    return path;
}

static struct cf_string *d_CFURLCopyFileSystemPath(const struct cf_url *url, CFIndex style) {
    if (style != 0) return NULL;
    char *path = url_path(url, 0);
    if (!path) return NULL;
    size_t size = strlen(path);
    if (size > 1 && path[size - 1] == '/') path[size - 1] = 0;
    struct cf_string *s = d_CFStringCreateWithCString(NULL, path, CF_UTF8);
    free(path);
    return s;
}
DX_FN(CFURLCopyFileSystemPath);

static Boolean d_CFURLGetFileSystemRepresentation(const struct cf_url *url, Boolean resolve,
                                                  uint8_t *buffer, CFIndex capacity) {
    if (!buffer || capacity <= 0) return 0;
    char *path = url_path(url, resolve);
    if (!path) return 0;
    size_t size = strlen(path);
    if (size > 1 && path[size - 1] == '/') path[--size] = 0;
    Boolean fits = size < (size_t)capacity;
    if (fits) memcpy(buffer, path, size + 1);
    free(path);
    return fits;
}
DX_FN(CFURLGetFileSystemRepresentation);
