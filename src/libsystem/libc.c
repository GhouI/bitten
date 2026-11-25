/* libSystem basics: program variables, stdio, strings, memory, dyld API. */
#define _GNU_SOURCE
#include <ctype.h>
#include <errno.h>
#include <getopt.h>
#include <inttypes.h>
#include <langinfo.h>
#include <libgen.h>
#include <limits.h>
#include <locale.h>
#include <malloc.h>
#include <math.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/random.h>
#include <unistd.h>
#include <wchar.h>

#include "dx.h"

/* ---- program variables ------------------------------------------------ */

int d_NXArgc;
char **d_NXArgv;
const char *d___progname = "";
static FILE *d_stdinp, *d_stdoutp, *d_stderrp;
static unsigned long d_stack_chk_guard;

DX_EXPORT("_NXArgc", &d_NXArgc);
DX_EXPORT("_NXArgv", &d_NXArgv);
DX_EXPORT("___progname", &d___progname);
DX_EXPORT("_environ", &environ);
DX_EXPORT("___stdinp", &d_stdinp);
DX_EXPORT("___stdoutp", &d_stdoutp);
DX_EXPORT("___stderrp", &d_stderrp);
DX_EXPORT("___stack_chk_guard", &d_stack_chk_guard);
extern void __stack_chk_fail(void);
extern int __cxa_atexit(void (*)(void *), void *, void *);
DX_PASS(__stack_chk_fail);

void dx_libsystem_init(int argc, char **argv, char **envp) {
    (void)envp;
    d_NXArgc = argc;
    d_NXArgv = argv;
    const char *slash = argc ? strrchr(argv[0], '/') : NULL;
    d___progname = argc ? (slash ? slash + 1 : argv[0]) : "";
    d_stdinp = stdin;
    d_stdoutp = stdout;
    d_stderrp = stderr;
    if (getrandom(&d_stack_chk_guard, sizeof d_stack_chk_guard, 0) != sizeof d_stack_chk_guard)
        d_stack_chk_guard = 0x2f5c9d1b00a3e7ULL;
    d_stack_chk_guard &= ~0xffUL; /* keep a terminating zero byte */
}

static char ***d__NSGetEnviron(void) { return &environ; }
DX_FN(_NSGetEnviron);
static int *d__NSGetArgc(void) { return &d_NXArgc; }
DX_FN(_NSGetArgc);
static char ***d__NSGetArgv(void) { return &d_NXArgv; }
DX_FN(_NSGetArgv);
static const char **d__NSGetProgname(void) { return &d___progname; }
DX_FN(_NSGetProgname);
static const char *d_getprogname(void) { return d___progname; }
DX_FN(getprogname);
static void d_setprogname(const char *n) {
    const char *s = strrchr(n, '/');
    d___progname = s ? s + 1 : n;
}
DX_FN(setprogname);
static int d__NSGetExecutablePath(char *buf, uint32_t *size) {
    const char *p = dx_main_path();
    size_t need = strlen(p) + 1;
    if (*size < need) {
        *size = need;
        return -1;
    }
    memcpy(buf, p, need);
    return 0;
}
DX_FN(_NSGetExecutablePath);

/* ---- dyld API ---------------------------------------------------------- */

static uint32_t d__dyld_image_count(void) { return dx_image_count(); }
DX_FN(_dyld_image_count);
static const void *d__dyld_get_image_header(uint32_t i) { return dx_image_header(i); }
DX_FN(_dyld_get_image_header);
static const char *d__dyld_get_image_name(uint32_t i) { return dx_image_name(i); }
DX_FN(_dyld_get_image_name);
static intptr_t d__dyld_get_image_vmaddr_slide(uint32_t i) { return dx_image_slide(i); }
DX_FN(_dyld_get_image_vmaddr_slide);
static void d__dyld_register_func_for_add_image(void (*fn)(const void *mh, intptr_t slide)) {
    for (uint32_t i = 0; i < dx_image_count(); i++) fn(dx_image_header(i), dx_image_slide(i));
}
DX_FN(_dyld_register_func_for_add_image);
static void d__dyld_register_func_for_remove_image(void *fn) { (void)fn; }
DX_FN(_dyld_register_func_for_remove_image);
/* Reported OS: macOS 15.0 (the lowest release current apps still target). */
static uint32_t d_dyld_get_program_sdk_version(void) { return 0x000f0000; }
DX_FN(dyld_get_program_sdk_version);
static uint32_t d_dyld_get_active_platform(void) { return 1; }
DX_FN(dyld_get_active_platform);
static int d__availability_version_check(uint32_t count, void *versions) {
    (void)count;
    (void)versions;
    return 1;
}
DX_FN(_availability_version_check);
static int d___isOSVersionAtLeast(int major, int minor, int patch) {
    (void)minor;
    (void)patch;
    return major <= 15;
}
DX_FN(__isOSVersionAtLeast);
static int d___isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t patch) {
    (void)platform;
    (void)minor;
    (void)patch;
    return major <= 15;
}
DX_FN(__isPlatformVersionAtLeast);

#define D_RTLD_DEFAULT ((void *)-2)
#define D_RTLD_NEXT ((void *)-1)
#define D_RTLD_SELF ((void *)-3)
#define D_RTLD_MAIN_ONLY ((void *)-5)
static __thread char dl_error[512];
static __thread int dl_error_set;
static char shim_handle; /* stands for "a library provided by bitten" */

static void *d_dlopen(const char *path, int mode) {
    (void)mode;
    dl_error_set = 0;
    if (!path) return D_RTLD_DEFAULT;
    char buf[PATH_MAX];
    const char *p = dx_path(path, buf, sizeof buf);
    if (access(p, R_OK) == 0 && dx_is_macho_file(p)) {
        struct dx_image *img = dx_load_image(p, 0);
        if (img) {
            dx_run_initializers();
            return img;
        }
    }
    /* System libraries and frameworks are implemented inside bitten. */
    if (!strncmp(path, "/usr/lib/", 9) || !strncmp(path, "/System/Library/", 16) ||
        (!strchr(path, '/') && strstr(path, ".dylib"))) {
        dx_log(1, "dlopen(%s) -> built-in shims", path);
        return &shim_handle;
    }
    snprintf(dl_error, sizeof dl_error, "dlopen(%s): image not found", path);
    dl_error_set = 1;
    dx_log(1, "%s", dl_error);
    return NULL;
}
DX_FN(dlopen);

static void *d_dlsym(void *handle, const char *symbol) {
    char name[1024];
    snprintf(name, sizeof name, "_%s", symbol);
    void *r;
    dl_error_set = 0;
    if (handle == D_RTLD_DEFAULT || handle == D_RTLD_NEXT || handle == D_RTLD_SELF ||
        handle == D_RTLD_MAIN_ONLY || handle == &shim_handle || !handle)
        r = dx_global_lookup(name);
    else {
        r = dx_image_lookup(handle, name);
        if (!r) r = dx_registry_lookup(name);
    }
    if (!r) {
        snprintf(dl_error, sizeof dl_error, "dlsym: symbol not found: %s", symbol);
        dl_error_set = 1;
        dx_log(1, "%s", dl_error);
    }
    return r;
}
DX_FN(dlsym);

static int d_dlclose(void *h) { (void)h; return 0; }
DX_FN(dlclose);
static char *d_dlerror(void) {
    if (!dl_error_set) return NULL;
    dl_error_set = 0;
    return dl_error;
}
DX_FN(dlerror);

struct d_dl_info {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_saddr;
};
const char *dx_symbol_for_address(const void *addr, uintptr_t *sym_addr);
static int d_dladdr(const void *addr, struct d_dl_info *info) {
    const char *name;
    uintptr_t base;
    if (!dx_image_for_address(addr, &name, &base)) return 0;
    info->dli_fname = name;
    info->dli_fbase = (void *)base;
    uintptr_t sa = 0;
    const char *sn = dx_symbol_for_address(addr, &sa);
    info->dli_sname = sn && sn[0] == '_' ? sn + 1 : sn;
    info->dli_saddr = (void *)sa;
    return 1;
}
DX_FN(dladdr);

/* ---- process exit ------------------------------------------------------ */

DX_PASS(exit);
DX_PASS(_exit);
DX_EXPORT("__Exit", _exit);
DX_PASS(abort);
DX_PASS(atexit);
DX_PASS(__cxa_atexit);
static void d___assert_rtn(const char *func, const char *file, int line, const char *expr) {
    dx_fatal("Assertion failed: (%s), function %s, file %s, line %d.", expr, func ? func : "?", file, line);
}
DX_FN(__assert_rtn);
static void d_abort_report_np(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    abort();
}
DX_FN(abort_report_np);

/* ---- memory ------------------------------------------------------------ */

DX_PASS(malloc);
DX_PASS(calloc);
DX_PASS(realloc);
DX_PASS(free);
DX_PASS(posix_memalign);
DX_PASS(valloc);
DX_PASS(aligned_alloc);
static size_t d_malloc_size(const void *p) { return p ? malloc_usable_size((void *)p) : 0; }
DX_FN(malloc_size);
static size_t d_malloc_good_size(size_t n) { return (n + 15) & ~(size_t)15; }
DX_FN(malloc_good_size);
static void *d_reallocf(void *p, size_t n) {
    void *r = realloc(p, n);
    if (!r && n) free(p);
    return r;
}
DX_FN(reallocf);

/* malloc zones: one zone, backed by the host allocator. Callers (sqlite
 * among them) call through the zone's function table directly, so the zone
 * is a real malloc_zone_t. */
struct d_malloc_zone {
    void *reserved1, *reserved2;
    size_t (*size)(struct d_malloc_zone *, const void *);
    void *(*malloc)(struct d_malloc_zone *, size_t);
    void *(*calloc)(struct d_malloc_zone *, size_t, size_t);
    void *(*valloc)(struct d_malloc_zone *, size_t);
    void (*free)(struct d_malloc_zone *, void *);
    void *(*realloc)(struct d_malloc_zone *, void *, size_t);
    void (*destroy)(struct d_malloc_zone *);
    const char *zone_name;
    unsigned (*batch_malloc)(struct d_malloc_zone *, size_t, void **, unsigned);
    void (*batch_free)(struct d_malloc_zone *, void **, unsigned);
    void *introspect;
    unsigned version;
    void *(*memalign)(struct d_malloc_zone *, size_t, size_t);
    void (*free_definite_size)(struct d_malloc_zone *, void *, size_t);
    size_t (*pressure_relief)(struct d_malloc_zone *, size_t);
    int (*claimed_address)(struct d_malloc_zone *, void *);
};
static size_t zone_size(struct d_malloc_zone *z, const void *p) { (void)z; return p ? malloc_usable_size((void *)p) : 0; }
static void *zone_malloc(struct d_malloc_zone *z, size_t n) { (void)z; return malloc(n); }
static void *zone_calloc(struct d_malloc_zone *z, size_t a, size_t b) { (void)z; return calloc(a, b); }
static void *zone_valloc(struct d_malloc_zone *z, size_t n) { (void)z; return valloc(n); }
static void zone_free(struct d_malloc_zone *z, void *p) { (void)z; free(p); }
static void *zone_realloc(struct d_malloc_zone *z, void *p, size_t n) { (void)z; return realloc(p, n); }
static void zone_destroy(struct d_malloc_zone *z) { (void)z; }
static unsigned zone_batch_malloc(struct d_malloc_zone *z, size_t n, void **out, unsigned count) {
    (void)z;
    unsigned i = 0;
    for (; i < count; i++)
        if (!(out[i] = malloc(n))) break;
    return i;
}
static void zone_batch_free(struct d_malloc_zone *z, void **p, unsigned count) {
    (void)z;
    for (unsigned i = 0; i < count; i++) free(p[i]);
}
static void *zone_memalign(struct d_malloc_zone *z, size_t a, size_t n) {
    (void)z;
    void *p = NULL;
    return posix_memalign(&p, a < sizeof(void *) ? sizeof(void *) : a, n) ? NULL : p;
}
static void zone_free_sized(struct d_malloc_zone *z, void *p, size_t n) { (void)z; (void)n; free(p); }
static size_t zone_pressure_relief(struct d_malloc_zone *z, size_t goal) { (void)z; (void)goal; return 0; }
static int zone_claimed(struct d_malloc_zone *z, void *p) { (void)z; return p != NULL; }
static struct d_malloc_zone default_zone_s = {
    NULL, NULL, zone_size, zone_malloc, zone_calloc, zone_valloc, zone_free, zone_realloc,
    zone_destroy, "DefaultMallocZone", zone_batch_malloc, zone_batch_free, NULL, 10,
    zone_memalign, zone_free_sized, zone_pressure_relief, zone_claimed};
#define default_zone (&default_zone_s)
static void *d_malloc_default_zone(void) { return default_zone; }
DX_FN(malloc_default_zone);
static void *d_malloc_create_zone(size_t start, unsigned flags) { (void)start; (void)flags; return default_zone; }
DX_FN(malloc_create_zone);
static void d_malloc_destroy_zone(void *z) { (void)z; }
DX_FN(malloc_destroy_zone);
static void d_malloc_set_zone_name(void *z, const char *n) { (void)z; (void)n; }
DX_FN(malloc_set_zone_name);
static void *d_malloc_zone_malloc(void *z, size_t n) { (void)z; return malloc(n); }
DX_FN(malloc_zone_malloc);
static void *d_malloc_zone_calloc(void *z, size_t a, size_t b) { (void)z; return calloc(a, b); }
DX_FN(malloc_zone_calloc);
static void *d_malloc_zone_valloc(void *z, size_t n) { (void)z; return valloc(n); }
DX_FN(malloc_zone_valloc);
static void *d_malloc_zone_realloc(void *z, void *p, size_t n) { (void)z; return realloc(p, n); }
DX_FN(malloc_zone_realloc);
static void *d_malloc_zone_memalign(void *z, size_t a, size_t n) {
    (void)z;
    void *p = NULL;
    return posix_memalign(&p, a, n) ? NULL : p;
}
DX_FN(malloc_zone_memalign);
static void d_malloc_zone_free(void *z, void *p) { (void)z; free(p); }
DX_FN(malloc_zone_free);
static void *d_malloc_zone_from_ptr(const void *p) { (void)p; return default_zone; }
DX_FN(malloc_zone_from_ptr);

/* ---- strings ----------------------------------------------------------- */

DX_PASS(memcpy); DX_PASS(memmove); DX_PASS(memset); DX_PASS(memcmp); DX_PASS(memchr);
DX_PASS(memrchr); DX_PASS(memmem); DX_PASS(memccpy);
DX_PASS(strlen); DX_PASS(strnlen); DX_PASS(strcmp); DX_PASS(strncmp); DX_PASS(strcpy);
DX_PASS(strncpy); DX_PASS(strcat); DX_PASS(strncat); DX_PASS(strchr); DX_PASS(strrchr);
DX_PASS(strstr); DX_PASS(strdup); DX_PASS(strndup); DX_PASS(strcasecmp); DX_PASS(strncasecmp);
DX_PASS(strcasestr); DX_PASS(strspn); DX_PASS(strcspn); DX_PASS(strpbrk); DX_PASS(strtok);
DX_PASS(strtok_r); DX_PASS(strsep); DX_PASS(strlcpy); DX_PASS(strlcat); DX_PASS(stpcpy);
DX_PASS(stpncpy); DX_PASS(strcoll); DX_PASS(strxfrm);
DX_PASS(strtol); DX_PASS(strtoul); DX_PASS(strtoll); DX_PASS(strtoull); DX_PASS(strtod);
DX_PASS(strtof); DX_PASS(strtold); DX_PASS(strtoimax); DX_PASS(strtoumax);
DX_PASS(atoi); DX_PASS(atol); DX_PASS(atoll); DX_PASS(atof);
DX_PASS(bzero); DX_PASS(bcopy); DX_PASS(bcmp); DX_PASS(ffs); DX_PASS(index); DX_PASS(rindex);
DX_PASS(qsort); DX_PASS(bsearch); DX_PASS(abs); DX_PASS(labs); DX_PASS(llabs);
/* Darwin's qsort_r takes the context first, both in the call and the callback. */
struct qsort_ctx {
    void *thunk;
    int (*cmp)(void *, const void *, const void *);
};
static int qsort_adapter(const void *a, const void *b, void *arg) {
    struct qsort_ctx *q = arg;
    return q->cmp(q->thunk, a, b);
}
static void d_qsort_r(void *base, size_t n, size_t width, void *thunk,
                      int (*cmp)(void *, const void *, const void *)) {
    struct qsort_ctx q = {thunk, cmp};
    qsort_r(base, n, width, qsort_adapter, &q);
}
DX_FN(qsort_r);
DX_EXPORT("___bzero", bzero);
static void *d___memcpy_chk(void *d, const void *s, size_t n, size_t dn) { (void)dn; return memcpy(d, s, n); }
DX_FN(__memcpy_chk);
static void *d___memmove_chk(void *d, const void *s, size_t n, size_t dn) { (void)dn; return memmove(d, s, n); }
DX_FN(__memmove_chk);
static void *d___memset_chk(void *d, int c, size_t n, size_t dn) { (void)dn; return memset(d, c, n); }
DX_FN(__memset_chk);
static char *d___strcpy_chk(char *d, const char *s, size_t dn) { (void)dn; return strcpy(d, s); }
DX_FN(__strcpy_chk);
static char *d___stpcpy_chk(char *d, const char *s, size_t dn) { (void)dn; return stpcpy(d, s); }
DX_FN(__stpcpy_chk);
static char *d___strcat_chk(char *d, const char *s, size_t dn) { (void)dn; return strcat(d, s); }
DX_FN(__strcat_chk);
static char *d___strncpy_chk(char *d, const char *s, size_t n, size_t dn) { (void)dn; return strncpy(d, s, n); }
DX_FN(__strncpy_chk);
static char *d___strncat_chk(char *d, const char *s, size_t n, size_t dn) { (void)dn; return strncat(d, s, n); }
DX_FN(__strncat_chk);
extern int __snprintf_chk(char *, size_t, int, size_t, const char *, ...);
extern int __sprintf_chk(char *, int, size_t, const char *, ...);
extern int __vsnprintf_chk(char *, size_t, int, size_t, const char *, va_list);
extern int __vsprintf_chk(char *, int, size_t, const char *, va_list);
DX_PASS(__snprintf_chk); DX_PASS(__sprintf_chk); DX_PASS(__vsnprintf_chk); DX_PASS(__vsprintf_chk);
static size_t d___strlcpy_chk(char *d, const char *s, size_t n, size_t dn) { (void)dn; return strlcpy(d, s, n); }
DX_FN(__strlcpy_chk);
static size_t d___strlcat_chk(char *d, const char *s, size_t n, size_t dn) { (void)dn; return strlcat(d, s, n); }
DX_FN(__strlcat_chk);

static void d_memset_pattern16(void *b, const void *pat, size_t len) {
    char *p = b;
    while (len >= 16) { memcpy(p, pat, 16); p += 16; len -= 16; }
    if (len) memcpy(p, pat, len);
}
DX_FN(memset_pattern16);
static void d_memset_pattern8(void *b, const void *pat, size_t len) {
    char *p = b;
    while (len >= 8) { memcpy(p, pat, 8); p += 8; len -= 8; }
    if (len) memcpy(p, pat, len);
}
DX_FN(memset_pattern8);
static void d_memset_pattern4(void *b, const void *pat, size_t len) {
    char *p = b;
    while (len >= 4) { memcpy(p, pat, 4); p += 4; len -= 4; }
    if (len) memcpy(p, pat, len);
}
DX_FN(memset_pattern4);

/* ctype: the functions (Darwin's inline macros use the rune table below). */
DX_PASS(isalpha); DX_PASS(isdigit); DX_PASS(isalnum); DX_PASS(isspace); DX_PASS(isupper);
DX_PASS(islower); DX_PASS(isxdigit); DX_PASS(ispunct); DX_PASS(isprint); DX_PASS(isgraph);
DX_PASS(iscntrl); DX_PASS(isblank); DX_PASS(toupper); DX_PASS(tolower);
static int d___tolower(int c) { return tolower(c); }
DX_FN(__tolower);
static int d___toupper(int c) { return toupper(c); }
DX_FN(__toupper);

#define D_CTYPE_A 0x00000100L
#define D_CTYPE_C 0x00000200L
#define D_CTYPE_D 0x00000400L
#define D_CTYPE_G 0x00000800L
#define D_CTYPE_L 0x00001000L
#define D_CTYPE_P 0x00002000L
#define D_CTYPE_S 0x00004000L
#define D_CTYPE_U 0x00008000L
#define D_CTYPE_X 0x00010000L
#define D_CTYPE_B 0x00020000L
#define D_CTYPE_R 0x00040000L
static struct d_rune_locale {
    char magic[8];
    char encoding[32];
    void *sgetrune, *sputrune;
    int invalid_rune;
    uint32_t runetype[256];
    int maplower[256];
    int mapupper[256];
    char rest[256];
} d_default_rune_locale;
DX_EXPORT("__DefaultRuneLocale", &d_default_rune_locale);
static struct d_rune_locale *d_current_rune_locale = &d_default_rune_locale;
DX_EXPORT("__CurrentRuneLocale", &d_current_rune_locale);

__attribute__((constructor)) static void rune_init(void) {
    memcpy(d_default_rune_locale.magic, "RuneMagA", 8);
    strcpy(d_default_rune_locale.encoding, "NONE");
    for (int c = 0; c < 256; c++) {
        uint32_t t = 0;
        if (c < 128) {
            if (isalpha(c)) t |= D_CTYPE_A;
            if (iscntrl(c)) t |= D_CTYPE_C;
            if (isdigit(c)) t |= D_CTYPE_D | (c - '0');
            if (isgraph(c)) t |= D_CTYPE_G;
            if (islower(c)) t |= D_CTYPE_L;
            if (ispunct(c)) t |= D_CTYPE_P;
            if (isspace(c)) t |= D_CTYPE_S;
            if (isupper(c)) t |= D_CTYPE_U;
            if (isxdigit(c)) t |= D_CTYPE_X;
            if (c == ' ' || c == '\t') t |= D_CTYPE_B;
            if (isprint(c)) t |= D_CTYPE_R;
        }
        d_default_rune_locale.runetype[c] = t;
        d_default_rune_locale.maplower[c] = c < 128 ? tolower(c) : c;
        d_default_rune_locale.mapupper[c] = c < 128 ? toupper(c) : c;
    }
}
static int d___maskrune(int c, unsigned long f) {
    return (c >= 0 && c < 256) ? (int)(d_default_rune_locale.runetype[c] & f) : 0;
}
DX_FN(__maskrune);

/* ---- stdio -------------------------------------------------------------
 * FILE is opaque to well-behaved callers, so host FILE objects are handed
 * out directly. */
DX_PASS(fprintf); DX_PASS(vfprintf); DX_PASS(printf); DX_PASS(vprintf); DX_PASS(sprintf);
DX_PASS(vsprintf); DX_PASS(snprintf); DX_PASS(vsnprintf); DX_PASS(asprintf); DX_PASS(vasprintf);
DX_PASS(dprintf); DX_PASS(vdprintf); DX_PASS(sscanf); DX_PASS(vsscanf); DX_PASS(fscanf);
DX_PASS(scanf);
DX_PASS(fputc); DX_PASS(fputs); DX_PASS(putc); DX_PASS(putchar); DX_PASS(puts);
DX_PASS(fgetc); DX_PASS(fgets); DX_PASS(getc); DX_PASS(getchar); DX_PASS(ungetc);
DX_PASS(fwrite); DX_PASS(fread); DX_PASS(fflush); DX_PASS(fclose); DX_PASS(fileno);
DX_PASS(fseek); DX_PASS(ftell); DX_PASS(fseeko); DX_PASS(ftello); DX_PASS(rewind);
DX_PASS(feof); DX_PASS(ferror); DX_PASS(clearerr); DX_PASS(setvbuf); DX_PASS(setbuf);
DX_PASS(getline); DX_PASS(getdelim); DX_PASS(fdopen); DX_PASS(tmpfile); DX_PASS(flockfile);
DX_PASS(funlockfile); DX_PASS(pclose); DX_PASS(popen); DX_PASS(setlinebuf);
DX_PASS(putc_unlocked); DX_PASS(getc_unlocked); DX_PASS(putchar_unlocked);
DX_PASS(getchar_unlocked);

static FILE *d_fopen(const char *path, const char *mode) {
    char buf[PATH_MAX];
    return DX_RET(fopen(dx_path(path, buf, sizeof buf), mode));
}
DX_FN(fopen);
DX_EXPORT("_fopen$DARWIN_EXTSN", d_fopen);
static FILE *d_freopen(const char *path, const char *mode, FILE *f) {
    char buf[PATH_MAX];
    return DX_RET(freopen(dx_path(path, buf, sizeof buf), mode, f));
}
DX_FN(freopen);
static void d_perror(const char *s) {
    const char *msg = strerror(dx_errno_from_darwin(dx_thread_self()->d_errno));
    if (s && *s) fprintf(stderr, "%s: %s\n", s, msg);
    else fprintf(stderr, "%s\n", msg);
}
DX_FN(perror);

/* ---- environment, randomness, misc ------------------------------------ */

DX_PASS(getenv); DX_PASS(setenv); DX_PASS(unsetenv); DX_PASS(putenv);
DX_PASS(arc4random); DX_PASS(arc4random_buf); DX_PASS(arc4random_uniform);
DX_PASS(random); DX_PASS(srandom); DX_PASS(rand); DX_PASS(srand); DX_PASS(rand_r);
DX_PASS(drand48); DX_PASS(srand48); DX_PASS(lrand48);
static void d_srandomdev(void) {
    unsigned seed = 0;
    if (getrandom(&seed, sizeof seed, 0) != sizeof seed) seed = (unsigned)getpid();
    srandom(seed);
}
DX_FN(srandomdev);
static int d_getentropy(void *buf, size_t n) { return DX_RET(getentropy(buf, n)); }
DX_FN(getentropy);
static int d_issetugid(void) { return 0; }
DX_FN(issetugid);
DX_PASS(setjmp); DX_PASS(longjmp); DX_PASS(_setjmp); DX_PASS(_longjmp);
DX_EXPORT("_sigsetjmp", __sigsetjmp);
DX_PASS(siglongjmp);
DX_PASS(basename); DX_PASS(dirname);
DX_PASS(getopt); DX_PASS(getopt_long);
DX_EXPORT("_optarg", &optarg);
DX_EXPORT("_optind", &optind);
DX_EXPORT("_opterr", &opterr);
DX_EXPORT("_optopt", &optopt);

/* math (same ABI) */
DX_PASS(sin); DX_PASS(cos); DX_PASS(tan); DX_PASS(asin); DX_PASS(acos); DX_PASS(atan);
DX_PASS(atan2); DX_PASS(sinh); DX_PASS(cosh); DX_PASS(tanh); DX_PASS(exp); DX_PASS(exp2);
DX_PASS(log); DX_PASS(log2); DX_PASS(log10); DX_PASS(log1p); DX_PASS(expm1); DX_PASS(pow);
DX_PASS(sqrt); DX_PASS(cbrt); DX_PASS(hypot); DX_PASS(floor); DX_PASS(ceil); DX_PASS(round);
DX_PASS(trunc); DX_PASS(fmod); DX_PASS(fabs); DX_PASS(frexp); DX_PASS(ldexp); DX_PASS(modf);
DX_PASS(rint); DX_PASS(nearbyint); DX_PASS(lround); DX_PASS(llround); DX_PASS(lrint);
DX_PASS(fmin); DX_PASS(fmax); DX_PASS(copysign); DX_PASS(nan); DX_PASS(remainder);
DX_PASS(sinf); DX_PASS(cosf); DX_PASS(tanf); DX_PASS(expf); DX_PASS(logf); DX_PASS(powf);
DX_PASS(sqrtf); DX_PASS(floorf); DX_PASS(ceilf); DX_PASS(roundf); DX_PASS(truncf);
DX_PASS(fmodf); DX_PASS(fabsf); DX_PASS(atan2f); DX_PASS(log2f); DX_PASS(log10f);
DX_PASS(fminf); DX_PASS(fmaxf); DX_PASS(lroundf); DX_PASS(rintf); DX_PASS(hypotf);
DX_PASS(fma); DX_PASS(fmaf); DX_PASS(remainderf); DX_PASS(nearbyintf);
/* long double is the x87 80-bit format on both systems */
DX_PASS(floorl); DX_PASS(ceill); DX_PASS(truncl); DX_PASS(roundl); DX_PASS(rintl);
DX_PASS(fmodl); DX_PASS(remainderl); DX_PASS(fmal); DX_PASS(sqrtl); DX_PASS(fabsl);

/* ---- locale ------------------------------------------------------------ */

/* Darwin LC_*_MASK bit order: COLLATE CTYPE MESSAGES MONETARY NUMERIC TIME */
static int host_locale_mask(int d) {
    int h = 0;
    if (d & 1) h |= LC_COLLATE_MASK;
    if (d & 2) h |= LC_CTYPE_MASK;
    if (d & 4) h |= LC_MESSAGES_MASK;
    if (d & 8) h |= LC_MONETARY_MASK;
    if (d & 16) h |= LC_NUMERIC_MASK;
    if (d & 32) h |= LC_TIME_MASK;
    return h;
}
static locale_t d_newlocale(int mask, const char *name, locale_t base) {
    locale_t l = newlocale(host_locale_mask(mask), name, base);
    if (!l) l = newlocale(host_locale_mask(mask), "C", base);
    return l;
}
DX_FN(newlocale);
DX_PASS(freelocale); DX_PASS(uselocale); DX_PASS(duplocale);
/* Darwin LC_* categories: ALL 0 COLLATE 1 CTYPE 2 MONETARY 3 NUMERIC 4 TIME 5 MESSAGES 6 */
static char *d_setlocale(int cat, const char *name) {
    static const int map[] = {LC_ALL, LC_COLLATE, LC_CTYPE, LC_MONETARY, LC_NUMERIC, LC_TIME, LC_MESSAGES};
    if (cat < 0 || cat > 6) return NULL;
    char *r = setlocale(map[cat], name);
    return r ? r : (name ? setlocale(map[cat], "C") : NULL);
}
DX_FN(setlocale);
DX_PASS(localeconv);

static nl_item host_nl_item(int d) {
    static const nl_item base[] = {CODESET, D_T_FMT, D_FMT, T_FMT, T_FMT_AMPM, AM_STR, PM_STR};
    if (d >= 0 && d <= 6) return base[d];
    if (d >= 7 && d <= 13) return DAY_1 + (d - 7);
    if (d >= 14 && d <= 20) return ABDAY_1 + (d - 14);
    if (d >= 21 && d <= 32) return MON_1 + (d - 21);
    if (d >= 33 && d <= 44) return ABMON_1 + (d - 33);
    switch (d) {
    case 45: return ERA;
    case 46: return ERA_D_FMT;
    case 47: return ERA_D_T_FMT;
    case 48: return ERA_T_FMT;
    case 49: return ALT_DIGITS;
    case 50: return RADIXCHAR;
    case 51: return THOUSEP;
    case 52: return YESEXPR;
    case 53: return NOEXPR;
    case 56: return CRNCYSTR;
    }
    return CODESET;
}
static char *d_nl_langinfo(int item) { return nl_langinfo(host_nl_item(item)); }
DX_FN(nl_langinfo);
static char *d_nl_langinfo_l(int item, locale_t l) {
    return l ? nl_langinfo_l(host_nl_item(item), l) : nl_langinfo(host_nl_item(item));
}
DX_FN(nl_langinfo_l);

DX_PASS(mbstowcs); DX_PASS(wcstombs); DX_PASS(mbrtowc); DX_PASS(wcrtomb); DX_PASS(mbtowc);
DX_PASS(wctomb); DX_PASS(mblen); DX_PASS(wcslen); DX_PASS(wcwidth); DX_PASS(mbsinit);
DX_PASS(mbsrtowcs); DX_PASS(wcscmp); DX_PASS(wmemcpy); DX_PASS(wmemset); DX_PASS(wmemchr);
DX_PASS(wmemcmp); DX_PASS(wmemmove); DX_PASS(btowc); DX_PASS(wctob);
