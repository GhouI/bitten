/* bitten core interfaces shared by the loader and the Darwin-ABI shims. */
#ifndef BITTEN_DX_H
#define BITTEN_DX_H
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

/* ---- export registry -------------------------------------------------
 * Every Darwin symbol we implement is registered under its Mach-O name
 * (leading underscore included). The loader binds imports against this
 * table regardless of which dylib the binary expected the symbol from. */
struct dx_export {
    const char *name;
    void *addr;
};
#define DX_CAT_(a, b) a##b
#define DX_CAT(a, b) DX_CAT_(a, b)
#define DX_EXPORT(sym, target)                                               \
    static const struct dx_export DX_CAT(dx_exp_, __COUNTER__)               \
        __attribute__((used, section("dx_exports"))) = {sym, (void *)(target)}
/* Function with an identical ABI on both systems: hand out the host one. */
#define DX_PASS(fn) DX_EXPORT("_" #fn, fn)
/* Implementation named d_<fn>, exported as _<fn>. */
#define DX_FN(fn) DX_EXPORT("_" #fn, d_##fn)

void *dx_registry_lookup(const char *name);
void dx_registry_each(void (*cb)(const char *name, void *addr, void *ctx), void *ctx);

/* ---- logging ---------------------------------------------------------- */
extern int dx_verbose; /* BITTEN_DEBUG=1..3 */
void dx_log(int level, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
void dx_fatal(const char *fmt, ...) __attribute__((noreturn, format(printf, 1, 2)));
#define DX_TRACE(...) do { if (dx_verbose >= 2) dx_log(2, __VA_ARGS__); } while (0)

/* ---- threads ----------------------------------------------------------
 * Darwin x86-64 keeps thread-specific data in an array addressed through
 * %gs, and compiled code (the Go runtime, thread-local variable thunks)
 * reads slots directly. Each thread owns one of these blocks and %gs
 * points at tsd[0]. glibc keeps using %fs, so both worlds coexist. */
#define DX_TSD_SLOTS 768
#define DX_TSD_FIRST_DYNAMIC 256
struct dx_thread {
    void *tsd[DX_TSD_SLOTS]; /* tsd[0] = self, tsd[1] = &d_errno */
    int d_errno;
    unsigned long host; /* pthread_t */
    void *(*start)(void *);
    void *arg;
    void *result;
    void *stack_hi; /* highest stack address */
    size_t stack_size;
    int detached;
    uint64_t tid;
};
struct dx_thread *dx_thread_self(void);
struct dx_thread *dx_thread_attach(void); /* create + install block for calling thread */
void dx_thread_run_destructors(struct dx_thread *t);

/* ---- errno ------------------------------------------------------------ */
int dx_errno_to_darwin(int host_errno);
int dx_errno_from_darwin(int d);
void dx_set_errno(int darwin_errno);
/* Convert a host -1/errno result into a Darwin one. */
#define DX_RET(expr)                                      \
    ({                                                    \
        __typeof__(expr) dx_r_ = (expr);                  \
        if (dx_r_ == (__typeof__(expr))-1)                \
            dx_set_errno(dx_errno_to_darwin(errno));      \
        dx_r_;                                            \
    })

/* ---- signals ---------------------------------------------------------- */
int dx_sig_to_host(int d);
int dx_sig_from_host(int h);

/* ---- paths -------------------------------------------------------------
 * Darwin paths that have no meaning on the host are redirected. Returns
 * either `path` itself or `buf`. */
const char *dx_path(const char *path, char *buf, size_t buflen);

/* ---- loader ----------------------------------------------------------- */
struct dx_image;
struct dx_image *dx_load_image(const char *path, int flags);
void *dx_image_lookup(struct dx_image *img, const char *name);
void *dx_global_lookup(const char *name);
void dx_run_initializers(void);
int dx_is_macho_file(const char *path);
const char *dx_loader_path(void);
const char *dx_main_path(void);
const char *dx_stub_name(const void *p);
const char *dx_stub_value_name(uintptr_t v);
/* Start and size of a section of a loaded image, by section name (any segment). */
void *dx_image_section(const struct dx_image *img, const char *sect, size_t *size);
const struct dx_image *dx_image_for_address(const void *addr, const char **name_out,
                                            uintptr_t *base_out);
/* Nearest preceding symbol of a loaded image, or NULL. */
const char *dx_symbol_for_address(const void *addr, uintptr_t *sym_addr);
uint32_t dx_image_count(void);
const char *dx_image_name(uint32_t i);
const void *dx_image_header(uint32_t i);
intptr_t dx_image_slide(uint32_t i);

/* Objective-C runtime: a placeholder class (or its metaclass) for a class
 * a program imports but nobody provides. */
void *dx_objc_placeholder_class(const char *name, int want_meta) __attribute__((weak));

extern int dx_argc;
extern char **dx_argv;
extern char **dx_envp;

#endif
