/* Unified logging (os_log) and signposts.
 *
 * Log handles are Objective-C objects of class OS_os_log, as Swift expects
 * (it sees them as the class OSLog). Messages are formatted from the format
 * string and the encoded argument buffer compiled code builds, and written
 * to stderr: errors and faults always, other levels with BITTEN_LOG=1. */
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dx.h"
#include "dx_objc.h"

struct os_log_s {
    void *isa;
    char *subsystem;
    char *category;
    int disabled;
};

struct os_log_s d_os_log_default = {NULL, "", "", 0};
struct os_log_s d_os_log_disabled = {NULL, "", "", 1};
DX_EXPORT("__os_log_default", &d_os_log_default);
DX_EXPORT("__os_log_disabled", &d_os_log_disabled);

static void *log_retain(void *o) { return o; }   /* log handles live forever, as on macOS */
static void log_release(void *o) {}

/* The class lives in exported storage: Swift code refers to
 * _OBJC_CLASS_$_OS_os_log (OSLog) by symbol. Built right after the
 * Objective-C runtime starts. */
static struct { void *w[5]; } os_log_cls, os_log_meta;
DX_EXPORT("_OBJC_CLASS_$_OS_os_log", &os_log_cls);
DX_EXPORT("_OBJC_METACLASS_$_OS_os_log", &os_log_meta);
static void *cls;
__attribute__((constructor(110))) static void log_class_init(void) {
    if (dx_os_object_class_in)
        cls = dx_os_object_class_in(&os_log_cls, &os_log_meta, "OS_os_log", log_retain, log_release);
    d_os_log_default.isa = cls;
    d_os_log_disabled.isa = cls;
}
static void *log_class(void) { return cls; }

static struct os_log_s *d_os_log_create(const char *subsystem, const char *category) {
    struct os_log_s *l = calloc(1, sizeof *l);
    l->isa = log_class();
    l->subsystem = strdup(subsystem ? subsystem : "");
    l->category = strdup(category ? category : "");
    return l;
}
DX_FN(os_log_create);
static struct os_log_s *d__bitten_os_log_default(void) { log_class(); return &d_os_log_default; }
DX_FN(_bitten_os_log_default);
static struct os_log_s *d__bitten_os_log_disabled(void) { log_class(); return &d_os_log_disabled; }
DX_FN(_bitten_os_log_disabled);

static int verbose_logs(void) {
    static int v = -1;
    if (v < 0) {
        const char *e = getenv("BITTEN_LOG");
        v = e && *e && strcmp(e, "0") != 0;
    }
    return v;
}

enum { TYPE_DEFAULT = 0, TYPE_INFO = 1, TYPE_DEBUG = 2, TYPE_ERROR = 0x10, TYPE_FAULT = 0x11 };

static bool d_os_log_type_enabled(struct os_log_s *log, uint8_t type) {
    log_class();
    if (log && log->disabled) return false;
    return type >= TYPE_ERROR || verbose_logs();
}
DX_FN(os_log_type_enabled);

/* An Objective-C object's -description as UTF-8. */
static const char *describe(void *obj) {
    if (!obj) return "(null)";
    dx_sel desc = dx_sel_register("description"), utf8 = dx_sel_register("UTF8String");
    void *(*msg)(void *, dx_sel) = dx_registry_lookup("_objc_msgSend");
    if (!msg) return "<object>";
    void *s = msg(obj, desc);
    const char *c = s ? (const char *)msg(s, utf8) : NULL;
    return c ? c : "<object>";
}

/* The argument buffer: [summary][count] then per argument
 * [descriptor: type << 4 | flags][size][data]. Types: 0 scalar,
 * 2 C string, 3 pointer/data, 4 Objective-C object. */
static void format_message(char *out, size_t cap, const char *fmt, const uint8_t *buf, uint32_t size) {
    size_t n = 0;
    const uint8_t *p = buf ? buf + 2 : NULL, *end = buf ? buf + size : NULL;
    unsigned remaining = buf && size >= 2 ? buf[1] : 0;
#define PUT(c) do { if (n + 1 < cap) out[n++] = (c); } while (0)
    for (const char *f = fmt; f && *f; f++) {
        if (*f != '%') {
            PUT(*f);
            continue;
        }
        f++;
        if (*f == '%') {
            PUT('%');
            continue;
        }
        if (*f == '{') { /* {public}, {private}, {bool}... */
            while (*f && *f != '}') f++;
            if (*f) f++;
        }
        while (*f && strchr("-+ #0123456789.*lhqjztL", *f)) f++;
        char conv = *f;
        if (!conv) break;
        char text[256] = "<redacted>";
        if (remaining && p && p + 2 <= end) {
            uint8_t desc = p[0], sz = p[1];
            const uint8_t *data = p + 2;
            if (data + sz > end) break;
            int type = desc >> 4;
            uint64_t v = 0;
            memcpy(&v, data, sz < 8 ? sz : 8);
            if (type == 2) {
                const char *s;
                memcpy(&s, data, sizeof s);
                snprintf(text, sizeof text, "%s", s ? s : "(null)");
            } else if (type == 4) {
                void *o;
                memcpy(&o, data, sizeof o);
                snprintf(text, sizeof text, "%s", describe(o));
            } else if (conv == 'f' || conv == 'g' || conv == 'e') {
                double d;
                memcpy(&d, data, sizeof d);
                snprintf(text, sizeof text, "%g", d);
            } else if (conv == 'u' || conv == 'x' || conv == 'X' || conv == 'p') {
                if (sz == 4) v &= 0xffffffffu;
                snprintf(text, sizeof text, conv == 'u' ? "%llu" : "0x%llx", (unsigned long long)v);
            } else if (conv == 'c') {
                snprintf(text, sizeof text, "%c", (char)v);
            } else {
                long long s = sz == 4 ? (long long)(int32_t)v : sz == 2 ? (int16_t)v : sz == 1 ? (int8_t)v : (long long)v;
                snprintf(text, sizeof text, "%lld", s);
            }
            p = data + sz;
            remaining--;
        }
        for (const char *t = text; *t; t++) PUT(*t);
    }
#undef PUT
    out[n] = 0;
}

static void log_impl(struct os_log_s *log, uint8_t type, const char *format, uint8_t *buf, uint32_t size) {
    if (!d_os_log_type_enabled(log, type)) return;
    char msg[4096];
    format_message(msg, sizeof msg, format, buf, size);
    const char *level = type == TYPE_FAULT ? "fault" : type == TYPE_ERROR ? "error" : type == TYPE_DEBUG ? "debug"
                        : type == TYPE_INFO ? "info" : "default";
    if (log && log->subsystem && *log->subsystem)
        fprintf(stderr, "[%s:%s] %s: %s\n", log->subsystem, log->category, level, msg);
    else
        fprintf(stderr, "%s: %s\n", level, msg);
}

static void d__os_log_impl(void *dso, struct os_log_s *log, uint8_t type, const char *fmt, uint8_t *buf, uint32_t size) {
    log_impl(log, type, fmt, buf, size);
}
DX_EXPORT("__os_log_impl", d__os_log_impl);
DX_EXPORT("__os_log_error_impl", d__os_log_impl);
DX_EXPORT("__os_log_fault_impl", d__os_log_impl);
DX_EXPORT("__os_log_debug_impl", d__os_log_impl);

/* ---- signposts: accepted and dropped ------------------------------------------ */
static bool d_os_signpost_enabled(struct os_log_s *log) { return false; }
DX_FN(os_signpost_enabled);
static uint64_t d_os_signpost_id_generate(struct os_log_s *log) {
    static uint64_t next = 1;
    return __atomic_fetch_add(&next, 1, __ATOMIC_RELAXED);
}
DX_FN(os_signpost_id_generate);
static void d__os_signpost_emit_with_name_impl(void *dso, struct os_log_s *log, uint8_t type, uint64_t id,
                                              const char *name, const char *fmt, uint8_t *buf, uint32_t size) {}
DX_EXPORT("__os_signpost_emit_with_name_impl", d__os_signpost_emit_with_name_impl);
