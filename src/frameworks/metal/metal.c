/* Shaders for bitten's software Metal device (frameworks/Metal). A Metal
 * library is compiled once, by tools/metal-compile.py with clang, into a
 * shared object of x86-64 code and a manifest describing each function's
 * arguments and outputs; the result is cached under
 * $HOME/Library/Caches/bitten/metal/<hash of the library>/ and loaded
 * here. The compiled functions are called from the Metal framework through
 * bn_call_<name>(args, out), a plain C function.
 *
 * Compiling needs python3 and a clang that reads Apple's AIR bitcode
 * (BITTEN_CLANG, else clang on PATH, else the Swift toolchain's). */
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "dx.h"

struct bn_metal_lib {
    void *dl;
    char *manifest;
};

static uint64_t fnv64(const uint8_t *p, size_t n) {
    uint64_t h = 1469598103934665603ULL;
    for (size_t i = 0; i < n; i++) {
        h ^= p[i];
        h *= 1099511628211ULL;
    }
    return h;
}

static void mkdirs(const char *path) {
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s", path);
    for (char *p = tmp + 1; *p; p++)
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    mkdir(tmp, 0755);
}

static int exists(const char *p) { return access(p, F_OK) == 0; }

static const char *find_tool(char *buf, size_t n) {
    const char *env = getenv("BITTEN_METAL_COMPILER");
    if (env && *env) return env;
    /* next to mrun: build/mrun -> tools/, or an installed copy */
    snprintf(buf, n, "%s", dx_loader_path());
    char *slash = strrchr(buf, '/');
    if (slash) {
        snprintf(slash, n - (size_t)(slash - buf), "/../tools/metal-compile.py");
        if (exists(buf)) return buf;
        snprintf(slash, n - (size_t)(slash - buf), "/tools/metal-compile.py");
        if (exists(buf)) return buf;
    }
    if (exists("/usr/local/lib/bitten/tools/metal-compile.py")) return "/usr/local/lib/bitten/tools/metal-compile.py";
    return NULL;
}

static const char *find_clang(void) {
    const char *env = getenv("BITTEN_CLANG");
    if (env && *env) return env;
    static const char *const candidates[] = {"/opt/swift/usr/bin/clang", "/usr/bin/clang", "/usr/local/bin/clang", NULL};
    for (int i = 0; candidates[i]; i++)
        if (access(candidates[i], X_OK) == 0) return candidates[i];
    return "clang";
}

static int run_compiler(const char *tool, const char *lib, const char *dir) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        execlp("python3", "python3", tool, lib, dir, find_clang(), (char *)NULL);
        _exit(127);
    }
    int st = 0;
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {
    }
    return WIFEXITED(st) && WEXITSTATUS(st) == 0 ? 0 : -1;
}

static char *read_text(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *s = malloc((size_t)n + 1);
    size_t got = fread(s, 1, (size_t)n, f);
    s[got] = 0;
    fclose(f);
    return s;
}

/* A compiled library for the metallib's bytes, or NULL (and a reason). */
struct bn_metal_lib *bitten_metal_open(const void *data, size_t len, char *why, size_t whylen) {
    const char *home = getenv("HOME");
    char dir[PATH_MAX], so[PATH_MAX + 32], man[PATH_MAX + 32], lib[PATH_MAX + 32], tmp[PATH_MAX + 32];
    snprintf(dir, sizeof dir, "%s/Library/Caches/bitten/metal/%016llx-%zx", home && *home ? home : "/tmp",
             (unsigned long long)fnv64(data, len), len);
    snprintf(so, sizeof so, "%s/shaders.so", dir);
    snprintf(man, sizeof man, "%s/manifest.txt", dir);
    if (!exists(so) || !exists(man)) {
        char toolbuf[PATH_MAX];
        const char *tool = find_tool(toolbuf, sizeof toolbuf);
        if (!tool) {
            snprintf(why, whylen, "tools/metal-compile.py not found");
            return NULL;
        }
        /* build in a scratch directory, then move it into place */
        snprintf(tmp, sizeof tmp, "%s.tmp%d", dir, (int)getpid());
        mkdirs(tmp);
        snprintf(lib, sizeof lib, "%s/library.metallib", tmp);
        FILE *f = fopen(lib, "wb");
        if (!f || fwrite(data, 1, len, f) != len) {
            if (f) fclose(f);
            snprintf(why, whylen, "cannot write %s", lib);
            return NULL;
        }
        fclose(f);
        if (run_compiler(tool, lib, tmp)) {
            snprintf(why, whylen, "compiling the Metal library failed (python3 %s, %s)", tool, find_clang());
            return NULL;
        }
        if (rename(tmp, dir) != 0 && !exists(so)) {
            snprintf(why, whylen, "cannot move %s into place", tmp);
            return NULL;
        }
    }
    void *dl = dlopen(so, RTLD_NOW | RTLD_LOCAL);
    if (!dl) {
        snprintf(why, whylen, "%s", dlerror());
        return NULL;
    }
    struct bn_metal_lib *l = calloc(1, sizeof *l);
    l->dl = dl;
    l->manifest = read_text(man);
    return l;
}
DX_EXPORT("_bitten_metal_open", bitten_metal_open);

const char *bitten_metal_manifest(struct bn_metal_lib *l) { return l && l->manifest ? l->manifest : ""; }
DX_EXPORT("_bitten_metal_manifest", bitten_metal_manifest);

/* bn_call_<name>(const void *args, void *out), or NULL. */
void *bitten_metal_entry(struct bn_metal_lib *l, const char *name) {
    if (!l) return NULL;
    char sym[256];
    snprintf(sym, sizeof sym, "bn_call_%s", name);
    return dlsym(l->dl, sym);
}
DX_EXPORT("_bitten_metal_entry", bitten_metal_entry);
