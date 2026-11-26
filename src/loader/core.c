/* Registry, logging, path mapping and the command-line entry point. */
#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "dx.h"

int dx_verbose;
extern int dx_stub_mode;

void dx_log(int level, const char *fmt, ...) {
    if (level > dx_verbose) return;
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof buf - 1, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if ((size_t)n > sizeof buf - 2) n = sizeof buf - 2;
    buf[n++] = '\n';
    static const char prefix[] = "bitten: ";
    ssize_t r = write(2, prefix, sizeof prefix - 1);
    r = write(2, buf, n);
    (void)r;
}

void dx_fatal(const char *fmt, ...) {
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof buf - 1, fmt, ap);
    va_end(ap);
    if (n < 0) n = 0;
    if ((size_t)n > sizeof buf - 2) n = sizeof buf - 2;
    buf[n++] = '\n';
    static const char prefix[] = "bitten: fatal: ";
    ssize_t r = write(2, prefix, sizeof prefix - 1);
    r = write(2, buf, n);
    (void)r;
    _exit(134);
}

/* ---- registry --------------------------------------------------------- */

extern const struct dx_export __start_dx_exports[], __stop_dx_exports[];

static const struct dx_export **table;
static size_t table_size;

static uint64_t hash_name(const char *s) {
    uint64_t h = 1469598103934665603ULL;
    for (; *s; s++) h = (h ^ (uint8_t)*s) * 1099511628211ULL;
    return h;
}

static void registry_init(void) {
    size_t n = __stop_dx_exports - __start_dx_exports;
    size_t size = 64;
    while (size < n * 2) size <<= 1;
    const struct dx_export **t = calloc(size, sizeof *t);
    for (const struct dx_export *e = __start_dx_exports; e < __stop_dx_exports; e++) {
        size_t i = hash_name(e->name) & (size - 1);
        while (t[i]) {
            if (!strcmp(t[i]->name, e->name)) dx_fatal("duplicate export %s", e->name);
            i = (i + 1) & (size - 1);
        }
        t[i] = e;
    }
    table_size = size;
    table = t;
}

void *dx_registry_lookup(const char *name) {
    if (!table) registry_init();
    size_t i = hash_name(name) & (table_size - 1);
    while (table[i]) {
        if (!strcmp(table[i]->name, name)) return table[i]->addr;
        i = (i + 1) & (table_size - 1);
    }
    return NULL;
}

void dx_registry_each(void (*cb)(const char *, void *, void *), void *ctx) {
    for (const struct dx_export *e = __start_dx_exports; e < __stop_dx_exports; e++)
        cb(e->name, e->addr, ctx);
}

/* ---- paths ------------------------------------------------------------ */

const char *dx_path(const char *path, char *buf, size_t buflen) {
    if (!path) return path;
    static const char *root;
    static int root_checked;
    if (!root_checked) {
        /* Where bitten's own Mach-O frameworks live: BITTEN_ROOT, else a
         * "root" directory next to mrun, else the installed location. */
        root = getenv("BITTEN_ROOT");
        if (root && !*root) root = NULL;
        if (!root) {
            static char guess[PATH_MAX];
            snprintf(guess, sizeof guess, "%s", dx_loader_path());
            char *slash = strrchr(guess, '/');
            if (slash) {
                strcpy(slash, "/root");
                if (access(guess, F_OK) == 0) root = guess;
            }
            if (!root && access("/usr/local/lib/bitten/root", F_OK) == 0) root = "/usr/local/lib/bitten/root";
        }
        root_checked = 1;
    }
    if (!root || path[0] != '/') return path;
    /* Only bitten's own read-only system files are redirected, and only
     * when the file really is in the framework root. Anything else,
     * including paths a program is about to create, is left alone. */
    static const char *const prefixes[] = {"/System/Library/", "/usr/lib/swift/", NULL};
    for (int i = 0; prefixes[i]; i++) {
        if (strncmp(path, prefixes[i], strlen(prefixes[i]))) continue;
        if (access(path, F_OK) == 0) return path;
        snprintf(buf, buflen, "%s%s", root, path);
        return access(buf, F_OK) == 0 ? buf : path;
    }
    return path;
}

/* ---- main ------------------------------------------------------------- */

struct dx_image *dx_main_image(void);
int dx_run_main(struct dx_image *img, int argc, char **argv, char **envp);
int dx_missing_count(void);
void dx_missing_each(void (*cb)(const char *, const char *, const char *, void *), void *ctx);
void dx_weak_missing_each(void (*cb)(const char *, const char *, const char *, void *), void *ctx);
void dx_report_deps(void (*cb)(const char *, const char *, int, void *), void *ctx);
void dx_libsystem_init(int argc, char **argv, char **envp);
void dx_signal_init(void);
void dx_rawsys_init(void);

static void list_cb(const char *name, void *addr, void *ctx) {
    (void)addr;
    (void)ctx;
    puts(name);
}

static void missing_cb(const char *image, const char *lib, const char *sym, void *ctx) {
    (void)ctx;
    const char *base = strrchr(image, '/');
    printf("MISSING\t%s\t%s\t%s\n", base ? base + 1 : image, lib, sym);
}
static void weak_cb(const char *image, const char *lib, const char *sym, void *ctx) {
    (void)ctx;
    const char *base = strrchr(image, '/');
    printf("WEAK\t%s\t%s\t%s\n", base ? base + 1 : image, lib, sym);
}

static void dep_cb(const char *image, const char *dep, int macho, void *ctx) {
    (void)ctx;
    const char *base = strrchr(image, '/');
    printf("DEP\t%s\t%s\t%s\n", base ? base + 1 : image, dep, macho ? "mach-o" : "built-in");
}

static void usage(void) {
    fputs("usage: mrun [--check] [--list-exports] [--argv0 NAME] <mach-o executable> [args...]\n"
          "\n"
          "Runs an x86-64 macOS (Mach-O) executable on Linux without a VM.\n"
          "\n"
          "  --check          load and bind only; print dependencies and every\n"
          "                   import bitten cannot satisfy, then exit\n"
          "  --list-exports   print the Darwin symbols bitten implements\n"
          "\n"
          "environment:\n"
          "  BITTEN_DEBUG=1|2  loader diagnostics\n"
          "  BITTEN_STUBS=zero unimplemented functions return 0 instead of aborting\n"
          "  BITTEN_ROOT=dir   directory holding Darwin-only paths (/System, ...)\n",
          stderr);
}

int main(int argc, char **argv, char **envp) {
    const char *dbg = getenv("BITTEN_DEBUG");
    if (dbg) dx_verbose = atoi(dbg);
    const char *stubs = getenv("BITTEN_STUBS");
    if (stubs && !strcmp(stubs, "zero")) dx_stub_mode = 1;

    int check = 0, i = 1;
    const char *argv0 = NULL;
    for (; i < argc; i++) {
        if (!strcmp(argv[i], "--check")) check = 1;
        else if (!strcmp(argv[i], "--argv0") && i + 1 < argc) argv0 = argv[++i];
        else if (!strcmp(argv[i], "--list-exports")) {
            dx_registry_each(list_cb, NULL);
            return 0;
        } else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            usage();
            return 0;
        } else if (!strcmp(argv[i], "--")) {
            i++;
            break;
        } else break;
    }
    if (i >= argc) {
        usage();
        return 2;
    }

    const char *image_path = argv[i];
    dx_argc = argc - i;
    dx_argv = argv + i;
    if (argv0) dx_argv[0] = (char *)argv0;
    dx_envp = envp;
    dx_thread_attach();
    dx_signal_init();
    dx_rawsys_init();
    dx_libsystem_init(dx_argc, dx_argv, envp);

    struct dx_image *img = dx_load_image(image_path, 1);
    if (!img) dx_fatal("cannot load %s", image_path);

    if (check) {
        dx_report_deps(dep_cb, NULL);
        dx_missing_each(missing_cb, NULL);
        dx_weak_missing_each(weak_cb, NULL);
        printf("SUMMARY\tmissing=%d\n", dx_missing_count());
        return dx_missing_count() ? 1 : 0;
    }
    if (dx_missing_count())
        dx_log(1, "%d imported symbols are unimplemented; calling one aborts (run with --check to list)",
               dx_missing_count());

    int rc = dx_run_main(img, dx_argc, dx_argv, envp);
    exit(rc);
}
