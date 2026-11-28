/* A debugging allocator for finding heap overflows in programs run by
 * mrun: every block gets a header (its size and who allocated it) and a
 * red zone after it. free and realloc check the red zone and, when it has
 * been written, report the block and its allocation site and abort.
 *
 *   cc -O1 -g -fno-omit-frame-pointer -shared -fPIC -o build/redzone.so tools/redzone.c -ldl
 *   LD_PRELOAD=build/redzone.so build/mrun ...
 *
 * REDZONE_SCAN=N also checks every live block each N frees (slow; finds
 * an overflow before the damaged block itself is freed).
 *
 * redzone_lookup() finds the live block an address is in, with its call
 * sites: mrun's BITTEN_FIND_REFS uses it to name the malloc blocks that
 * hold a reference. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <execinfo.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAGIC 0x52454452u /* "REDR" */
#define DEAD 0x44454144u
#define ZONE 64
#define FILL 0xA7

struct head {
    uint32_t magic, align_pad; /* bytes between the real block and this header */
    size_t size;
    void *site;                /* the caller of malloc */
    struct head *prev, *next;  /* live blocks (for REDZONE_SCAN) */
    void *up[3];               /* its callers (frame pointers) */
};
_Static_assert(sizeof(struct head) % 16 == 0, "header keeps 16-byte alignment");

static void *(*real_malloc)(size_t);
static void (*real_free)(void *);
static void *(*real_realloc)(void *, size_t);
static int (*real_memalign)(void **, size_t, size_t);
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static struct head *live;
static long scan_every, frees;

/* dlsym itself may allocate: serve those from a small static arena. */
static char boot[1 << 16];
static size_t boot_used;
static int resolving;

static void resolve(void) {
    if (real_malloc || resolving) return;
    resolving = 1;
    real_malloc = dlsym(RTLD_NEXT, "malloc");
    real_free = dlsym(RTLD_NEXT, "free");
    real_realloc = dlsym(RTLD_NEXT, "realloc");
    real_memalign = dlsym(RTLD_NEXT, "posix_memalign");
    const char *s = getenv("REDZONE_SCAN");
    scan_every = s ? atol(s) : 0;
    resolving = 0;
}

/* "symbol+offset (file)" for a host address, else the address. */
static const char *where(void *a, char *buf, size_t len) {
    Dl_info info;
    if (dladdr(a, &info) && info.dli_fname) {
        if (info.dli_sname)
            snprintf(buf, len, "%s+%#lx (%s)", info.dli_sname, (unsigned long)((char *)a - (char *)info.dli_saddr),
                     info.dli_fname);
        else
            snprintf(buf, len, "%#lx (%s)", (unsigned long)((char *)a - (char *)info.dli_fbase), info.dli_fname);
    } else {
        snprintf(buf, len, "%p", a);
    }
    return buf;
}

static void report(const char *what, struct head *h, void *freer) {
    char buf[1024], s1[256], s2[256];
    int n = snprintf(buf, sizeof buf, "redzone: %s: block %p of %zu bytes allocated by %s, freed by %s\n", what,
                     (void *)(h + 1), h->size, where(h->site, s1, sizeof s1), where(freer, s2, sizeof s2));
    if (write(2, buf, (size_t)n) < 0) {}
    unsigned char *z = (unsigned char *)(h + 1) + h->size;
    n = snprintf(buf, sizeof buf, "redzone: zone bytes:");
    for (int i = 0; i < 32; i++) n += snprintf(buf + n, sizeof buf - (size_t)n, " %02x", z[i]);
    buf[n++] = '\n';
    if (write(2, buf, (size_t)n) < 0) {}
    void *bt[24];
    int k = backtrace(bt, 24);
    backtrace_symbols_fd(bt, k, 2);
    abort();
}

static int damaged(struct head *h) {
    unsigned char *z = (unsigned char *)(h + 1) + h->size;
    for (int i = 0; i < ZONE; i++)
        if (z[i] != FILL) return 1;
    return 0;
}

static void scan(void *freer) {
    for (struct head *h = live; h; h = h->next)
        if (damaged(h)) report("red zone written (scan)", h, freer);
}

/* The return addresses of the frames above malloc's caller, by following
 * frame pointers (stops at anything that doesn't look like a frame). */
static void callers(void *out[3]) {
    uintptr_t *fp = __builtin_frame_address(0);
    for (int skip = 0; skip < 2 && fp; skip++) {   /* wrap, then alloc/malloc */
        uintptr_t *next = (uintptr_t *)fp[0];
        fp = next > fp && (uintptr_t)(next - fp) < (1 << 20) ? next : NULL;
    }
    for (int i = 0; i < 3; i++) {
        out[i] = NULL;
        if (!fp) continue;
        uintptr_t *next = (uintptr_t *)fp[0];
        if (!(next > fp && (uintptr_t)(next - fp) < (1 << 20))) { fp = NULL; continue; }
        out[i] = (void *)next[1];
        fp = next;
    }
}

static void *wrap(void *base, size_t pad, size_t n, void *site) {
    struct head *h = (struct head *)((char *)base + pad);
    h->magic = MAGIC;
    h->align_pad = (uint32_t)pad;
    h->size = n;
    h->site = site;
    callers(h->up);
    memset((char *)(h + 1) + n, FILL, ZONE);
    pthread_mutex_lock(&lock);
    h->prev = NULL;
    h->next = live;
    if (live) live->prev = h;
    live = h;
    pthread_mutex_unlock(&lock);
    return h + 1;
}

static void unlink_head(struct head *h) {
    pthread_mutex_lock(&lock);
    if (h->prev) h->prev->next = h->next;
    else live = h->next;
    if (h->next) h->next->prev = h->prev;
    pthread_mutex_unlock(&lock);
}

static void *alloc(size_t n, void *site) {
    resolve();
    if (!real_malloc) {
        size_t at = (boot_used + 15) & ~(size_t)15;
        if (at + n > sizeof boot) return NULL;
        boot_used = at + n;
        return boot + at;
    }
    void *base = real_malloc(sizeof(struct head) + n + ZONE);
    return base ? wrap(base, 0, n, site) : NULL;
}

static int ours(void *p) { return (char *)p < boot || (char *)p >= boot + sizeof boot; }

static void release(void *p, void *site) {
    if (!p || !ours(p)) return;
    struct head *h = (struct head *)p - 1;
    if (h->magic == DEAD) report("freed twice", h, site);
    if (h->magic != MAGIC) {
        char buf[128];
        int n = snprintf(buf, sizeof buf, "redzone: free of %p not from malloc (by %p)\n", p, site);
        if (write(2, buf, (size_t)n) < 0) {}
        abort();
    }
    if (damaged(h)) report("red zone written", h, site);
    unlink_head(h);
    h->magic = DEAD;
    if (scan_every && ++frees % scan_every == 0) {
        pthread_mutex_lock(&lock);
        scan(site);
        pthread_mutex_unlock(&lock);
    }
    real_free((char *)h - h->align_pad);
}

void *malloc(size_t n) { return alloc(n, __builtin_return_address(0)); }
void free(void *p) { release(p, __builtin_return_address(0)); }
void *calloc(size_t a, size_t b) {
    size_t n = a * b;
    if (b && n / b != a) return NULL;
    void *p = alloc(n, __builtin_return_address(0));
    if (p) memset(p, 0, n);
    return p;
}
void *realloc(void *p, size_t n) {
    void *site = __builtin_return_address(0);
    if (!p) return alloc(n, site);
    if (!ours(p)) {
        void *q = alloc(n, site);
        if (q) memcpy(q, p, n);
        return q;
    }
    struct head *h = (struct head *)p - 1;
    if (h->magic != MAGIC || damaged(h)) report("red zone written (realloc)", h, site);
    void *q = alloc(n, h->site);
    if (!q) return NULL;
    memcpy(q, p, h->size < n ? h->size : n);
    release(p, site);
    return q;
}
int posix_memalign(void **out, size_t align, size_t n) {
    resolve();
    if (align < 16) align = 16;
    void *base;
    int r = real_memalign(&base, align, align + sizeof(struct head) + n + ZONE);
    if (r) return r;
    /* the header right before an aligned pointer */
    size_t pad = (align - sizeof(struct head) % align) % align;
    *out = wrap(base, pad, n, __builtin_return_address(0));
    return 0;
}
void *aligned_alloc(size_t align, size_t n) {
    void *p;
    return posix_memalign(&p, align, n) ? NULL : p;
}
void *memalign(size_t align, size_t n) { return aligned_alloc(align, n); }
void *valloc(size_t n) { return aligned_alloc(4096, n); }
void *pvalloc(size_t n) { return aligned_alloc(4096, (n + 4095) & ~(size_t)4095); }
size_t malloc_usable_size(void *p) {
    if (!p || !ours(p)) return 0;
    return ((struct head *)p - 1)->size;
}

/* The live block `a` falls in: its start, size and up to four call sites
 * (malloc's caller first). 0 when it is in none. */
int redzone_lookup(uintptr_t a, uintptr_t *start, size_t *size, void *sites[4]) {
    int found = 0;
    pthread_mutex_lock(&lock);
    for (struct head *h = live; h; h = h->next) {
        uintptr_t p = (uintptr_t)(h + 1);
        if (a < p || a >= p + h->size) continue;
        *start = p;
        *size = h->size;
        sites[0] = h->site;
        for (int i = 0; i < 3; i++) sites[i + 1] = h->up[i];
        found = 1;
        break;
    }
    pthread_mutex_unlock(&lock);
    return found;
}
