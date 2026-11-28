/* BITTEN_FIND_REFS=Name: who keeps objects alive (leak hunting). Name is
 * part of a class name, or object addresses (0x…, comma separated);
 * BITTEN_FIND_REFS_FILE names a file read at each signal instead (for
 * addresses only known once the program runs).
 *
 * Every Objective-C object and Swift heap object (class instances, boxes,
 * closure contexts) made while this is set is remembered. On SIGUSR2 the
 * live instances of classes whose name contains Name are looked up in
 * memory: each word in a live object, the heap, the stacks and writable
 * image data that points at one is reported with what holds it (an
 * object's class and offset, or the mapping), and so on for the holders,
 * BITTEN_FIND_REFS_DEPTH levels deep (3), for the first
 * BITTEN_FIND_REFS_MAX instances (40).
 *
 *   BITTEN_FIND_REFS=NSHostingView build/mrun app &  kill -USR2 <pid>
 *
 * Objects are not stopped while memory is read; allocation and freeing
 * wait for the scan, other threads keep running.
 *
 * BITTEN_TRACE_RETAINS=Name counts, for each Objective-C object of a class
 * whose name contains Name, its retains less its releases by call stack
 * (eight return addresses); SIGUSR2 prints the stacks that don't balance
 * for each one still alive (an object kept by a retain nobody releases
 * has no reference to find).
 *
 * With tools/redzone.so
 * preloaded, a malloc block that holds a reference is named by where it
 * was allocated (and followed like an object). */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/uio.h>
#include <malloc.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

#include "dx_objc.h"
#include "objc_internal.h"

const char *class_name(Class cls);
unsigned long root_retain_count(id obj);

static const char *wanted;
static const char *rr_wanted;   /* BITTEN_TRACE_RETAINS */
static void rr_dump(void);
static int depth_max = 3;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static int enabled;   /* after the first call: 1 on, 0 off */
static volatile sig_atomic_t requested;

/* Live objects: open addressing, 0 empty, 1 removed. */
static uintptr_t *set;
static size_t cap, used, filled;

static size_t slot(uintptr_t p) { return (size_t)((p >> 4) * 0x9E3779B97F4A7C15ull) & (cap - 1); }
static void grow(void) {
    size_t ncap = cap ? cap * 2 : 1 << 16;
    if (used * 4 < cap) ncap = cap;   /* mostly tombstones: same size */
    uintptr_t *n = calloc(ncap, sizeof *n), *old = set;
    if (!n) return;
    size_t ocap = cap;
    set = n;
    cap = ncap;
    filled = used;
    for (size_t i = 0; i < ocap; i++)
        if (old[i] > 1) {
            size_t j = slot(old[i]);
            while (set[j]) j = (j + 1) & (cap - 1);
            set[j] = old[i];
        }
    free(old);
}
static void add(uintptr_t p) {
    if ((filled + 1) * 2 >= cap) grow();
    if (!cap) return;
    size_t j = slot(p), tomb = (size_t)-1;
    while (set[j]) {
        if (set[j] == p) return;
        if (set[j] == 1 && tomb == (size_t)-1) tomb = j;
        j = (j + 1) & (cap - 1);
    }
    if (tomb != (size_t)-1) j = tomb;
    else filled++;
    set[j] = p;
    used++;
}
static void del(uintptr_t p) {
    if (!cap) return;
    size_t j = slot(p);
    while (set[j]) {
        if (set[j] == p) {
            set[j] = 1;
            used--;
            return;
        }
        j = (j + 1) & (cap - 1);
    }
}

/* A sorted copy of the live objects, with their sizes, for finding the
 * object an address falls in. */
struct obj { uintptr_t at; size_t size; };
static struct obj *objs;
static size_t nobjs;
static int by_at(const void *a, const void *b) {
    uintptr_t x = ((const struct obj *)a)->at, y = ((const struct obj *)b)->at;
    return x < y ? -1 : x > y;
}
static const struct obj *containing(uintptr_t a) {
    size_t lo = 0, hi = nobjs;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (objs[mid].at <= a) lo = mid + 1;
        else hi = mid;
    }
    if (!lo) return NULL;
    const struct obj *o = &objs[lo - 1];
    return a < o->at + o->size ? o : NULL;
}

/* An object's name: its class, or the kind of Swift heap object. */
static const char *name_of(uintptr_t o, char *buf, size_t len) {
    uintptr_t isa = *(const uintptr_t *)o;
    if (isa <= 0x7FF) {
        snprintf(buf, len, "swift heap object (kind %#lx)", (unsigned long)isa);
        return buf;
    }
    if (isa < 0x1000) {
        snprintf(buf, len, "?");
        return buf;
    }
    uintptr_t kind = *(const uintptr_t *)isa;
    if (kind && kind <= 0x7FF) {   /* Swift metadata that isn't a class */
        snprintf(buf, len, "swift %s (metadata %#lx)",
                 kind == 0x400 ? "closure context" : kind == 0x500 ? "box" : "heap object", (unsigned long)isa);
        return buf;
    }
    const char *n = class_name((Class)isa);
    snprintf(buf, len, "%s", n ? n : "?");
    return buf;
}

struct region { uintptr_t lo, hi; char name[96]; };
static struct region regions[1024];
static int nregions;
static void read_maps(void) {
    nregions = 0;
    FILE *f = fopen("/proc/self/maps", "r");
    if (!f) return;
    char line[512];
    while (fgets(line, sizeof line, f) && nregions < 1024) {
        unsigned long lo, hi;
        char perms[8] = "", path[400] = "";
        if (sscanf(line, "%lx-%lx %7s %*s %*s %*s %399[^\n]", &lo, &hi, perms, path) < 3) continue;
        if (perms[0] != 'r' || perms[1] != 'w') continue;
        if (strstr(path, "[vvar") || strstr(path, "[vsyscall")) continue;
        struct region *r = &regions[nregions++];
        r->lo = lo;
        r->hi = hi;
        const char *base = strrchr(path, '/');
        snprintf(r->name, sizeof r->name, "%s", base ? base + 1 : path[0] ? path : "anonymous");
    }
    fclose(f);
}

#define MAXHITS 64
struct hit { uintptr_t at; const struct obj *holder; int region; };

/* tools/redzone.so, when preloaded. Its lock is taken by malloc, which a
 * thread holding ours may wait on: look blocks up only after the scan. */
typedef int (*lookup_fn)(uintptr_t, uintptr_t *, size_t *, void *[4]);
static lookup_fn block_lookup;

static const char *where(void *a, char *buf, size_t len) {
    Dl_info info;
    if (a && dladdr(a, &info) && info.dli_fname) {
        const char *f = strrchr(info.dli_fname, '/');
        if (info.dli_sname)
            snprintf(buf, len, "%s+%#lx", info.dli_sname, (unsigned long)((char *)a - (char *)info.dli_saddr));
        else
            snprintf(buf, len, "%s+%#lx", f ? f + 1 : info.dli_fname, (unsigned long)((char *)a - (char *)info.dli_fbase));
    } else {
        snprintf(buf, len, "%p", a);
    }
    return buf;
}

/* Every word in writable memory equal to `target`. */
/* Memory is copied out before it is read: another thread may unmap a
 * region (a stack, a large block) while it is scanned, and a copy fails
 * where a read would crash. */
static uintptr_t chunk[1 << 17];
static int find(uintptr_t target, struct hit *out) {
    int n = 0;
    pid_t self = getpid();
    for (int r = 0; r < nregions && n < MAXHITS; r++) {
        for (uintptr_t at = regions[r].lo; at < regions[r].hi && n < MAXHITS; at += sizeof chunk) {
            size_t len = regions[r].hi - at < sizeof chunk ? regions[r].hi - at : sizeof chunk;
            struct iovec local = {chunk, len}, remote = {(void *)at, len};
            ssize_t got = process_vm_readv(self, &local, 1, &remote, 1, 0);
            if (got <= 0) break;   /* gone */
            size_t words = (size_t)got / sizeof(uintptr_t);
            for (size_t i = 0; i < words; i++) {
                if (chunk[i] != target) continue;
                uintptr_t a = at + i * sizeof(uintptr_t);
                if (a >= (uintptr_t)chunk && a < (uintptr_t)(chunk + (sizeof chunk / sizeof *chunk))) continue;
                const struct obj *o = containing(a);
                if (o && o->at == target) continue;   /* itself */
                if (a >= (uintptr_t)objs && a < (uintptr_t)(objs + nobjs)) continue;   /* our tables */
                if (a >= (uintptr_t)set && a < (uintptr_t)(set + cap)) continue;
                out[n++] = (struct hit){a, o, r};
                if (n == MAXHITS) break;
            }
        }
    }
    return n;
}

/* Strings hold no references: words in their spare capacity are stale. */
static int holds_nothing(const char *name) { return strstr(name, "StringStorage") != NULL; }

static void report(uintptr_t target, int level) {
    struct hit hits[MAXHITS];
    int n = find(target, hits);
    char buf[256], s1[160], s2[160], s3[160], s4[160];
    for (int i = 0; i < n; i++) {
        const struct hit *h = &hits[i];
        uintptr_t from = 0;
        /* a __weak variable: not what keeps it */
        if (dx_objc_is_weak_slot((void *)target, (void *)h->at)) {
            fprintf(stderr, "bitten: refs: %*s<- %#lx (weak)\n", level * 2, "", (unsigned long)h->at);
            continue;
        }
        if (h->holder) {
            const char *name = name_of(h->holder->at, buf, sizeof buf);
            if (holds_nothing(name)) continue;
            fprintf(stderr, "bitten: refs: %*s<- %#lx +%#lx  %s\n", level * 2, "", (unsigned long)h->holder->at,
                    (unsigned long)(h->at - h->holder->at), name);
            from = h->holder->at;
        } else {
            uintptr_t start;
            size_t size;
            void *sites[4];
            if (block_lookup && strcmp(regions[h->region].name, "[heap]") == 0) {
                /* in no live block: freed memory, not a reference */
                if (!block_lookup(h->at, &start, &size, sites)) continue;
                fprintf(stderr, "bitten: refs: %*s<- %#lx +%#lx  malloc block of %zu from %s < %s < %s < %s\n",
                        level * 2, "", (unsigned long)start, (unsigned long)(h->at - start), size,
                        where(sites[0], s1, sizeof s1), where(sites[1], s2, sizeof s2), where(sites[2], s3, sizeof s3),
                        where(sites[3], s4, sizeof s4));
                from = start;
            } else {
                fprintf(stderr, "bitten: refs: %*s<- %#lx in %s\n", level * 2, "", (unsigned long)h->at,
                        regions[h->region].name);
            }
        }
        if (from && level < depth_max) {
            /* the same holder twice (two fields): once */
            int seen = 0;
            for (int k = 0; k < i; k++) seen |= hits[k].holder && hits[k].holder->at == from;
            if (!seen) report(from, level + 1);
        }
    }
}

/* Whether an object is one asked for: its class name contains the text,
 * or (text of 0x addresses, comma separated) it is one of them. Leaves its
 * name in buf. */
static int wants(uintptr_t o, char *buf, size_t len) {
    const char *n = name_of(o, buf, len);
    if (strncmp(wanted, "0x", 2) != 0) return strstr(n, wanted) != NULL;
    for (const char *p = wanted; p && *p;) {
        if (strtoull(p, NULL, 16) == o) return 1;
        p = strchr(p, ',');
        if (p) p++;
    }
    return 0;
}

static void scan(void) {
    const char *file = getenv("BITTEN_FIND_REFS_FILE");
    static char from_file[4096];
    if (file) {
        FILE *f = fopen(file, "r");
        size_t n = f ? fread(from_file, 1, sizeof from_file - 1, f) : 0;
        if (f) fclose(f);
        from_file[n] = 0;
        while (n && (from_file[n - 1] == '\n' || from_file[n - 1] == ' ')) from_file[--n] = 0;
        if (n) wanted = from_file;
    }
    pthread_mutex_lock(&lock);
    objs = malloc((used ? used : 1) * sizeof *objs);
    nobjs = 0;
    for (size_t i = 0; objs && i < cap; i++)
        if (set[i] > 1) objs[nobjs++] = (struct obj){set[i], malloc_usable_size((void *)set[i])};
    if (objs) {
        block_lookup = (lookup_fn)dlsym(RTLD_DEFAULT, "redzone_lookup");
        qsort(objs, nobjs, sizeof *objs, by_at);
        read_maps();
        char buf[256];
        int shown = 0;
        fprintf(stderr, "bitten: refs: %zu live objects, looking for '%s'\n", nobjs, wanted);
        size_t matching = 0;
        for (size_t i = 0; i < nobjs; i++)
            if (wants(objs[i].at, buf, sizeof buf)) matching++;
        static long limit = -1;
        if (limit < 0) { const char *l = getenv("BITTEN_FIND_REFS_MAX"); limit = l && atol(l) > 0 ? atol(l) : 40; }
        fprintf(stderr, "bitten: refs: %zu instances (the first %ld follow)\n", matching, limit);
        /* addresses asked for that aren't objects made here (CF objects,
         * malloc blocks): looked for as they are */
        if (strncmp(wanted, "0x", 2) == 0)
            for (const char *p = wanted; p && *p;) {
                uintptr_t at = (uintptr_t)strtoull(p, NULL, 16);
                const struct obj *o = containing(at);
                if (!o || o->at != at) {
                    fprintf(stderr, "bitten: refs: %#lx (not an object made here)\n", (unsigned long)at);
                    report(at, 1);
                }
                p = strchr(p, ',');
                if (p) p++;
            }
        for (size_t i = 0; i < nobjs && shown < limit; i++) {
            if (!wants(objs[i].at, buf, sizeof buf)) continue;
            const char *n = buf;
            shown++;
            uintptr_t isa = *(const uintptr_t *)objs[i].at;
            int objc = isa > 0x7FF && !(*(const uintptr_t *)isa && *(const uintptr_t *)isa <= 0x7FF);
            fprintf(stderr, "bitten: refs: %#lx %s (retain count %lu)\n", (unsigned long)objs[i].at, n,
                    objc ? root_retain_count((id)objs[i].at) : 0);
            report(objs[i].at, 1);
        }
    }
    free(objs);
    objs = NULL;
    nobjs = 0;
    pthread_mutex_unlock(&lock);
}

static void on_signal(int sig) {
    (void)sig;
    requested = 1;
}
static void *watcher(void *arg) {
    (void)arg;
    for (;;) {
        usleep(200000);
        if (!requested) continue;
        requested = 0;
        if (wanted) scan();
        if (rr_wanted) rr_dump();
    }
    return NULL;
}
static void init(void) {
    wanted = getenv("BITTEN_FIND_REFS");
    if ((!wanted || !*wanted) && getenv("BITTEN_FIND_REFS_FILE")) wanted = "-";
    rr_wanted = getenv("BITTEN_TRACE_RETAINS");
    if (rr_wanted && !*rr_wanted) rr_wanted = NULL;
    if (wanted && !*wanted) wanted = NULL;
    if (!wanted && !rr_wanted) return;
    const char *d = getenv("BITTEN_FIND_REFS_DEPTH");
    if (d && atoi(d) > 0) depth_max = atoi(d);
    signal(SIGUSR2, on_signal);
    pthread_t t;
    pthread_create(&t, NULL, watcher, NULL);
    pthread_detach(t);
    enabled = wanted != NULL;
}

void dx_live_note(const void *obj, int delta) {
    static _Atomic int state;   /* 0 unknown, 1 off, 2 on */
    int st = state;
    if (st == 1) return;
    if (st == 0) {
        pthread_once(&once, init);
        state = enabled ? 2 : 1;
        if (!enabled) return;
    }
    if (!obj) return;
    pthread_mutex_lock(&lock);
    if (delta > 0) add((uintptr_t)obj);
    else del((uintptr_t)obj);
    pthread_mutex_unlock(&lock);
}

/* ---- BITTEN_TRACE_RETAINS ---- */
#define RR_DEPTH 8
struct rr_site { void *pc[RR_DEPTH]; long count; };
struct rr_obj { uintptr_t obj; int n, cap; struct rr_site *sites; };
static struct rr_obj *rr_objs;
static int rr_n, rr_cap;
static pthread_mutex_t rr_lock = PTHREAD_MUTEX_INITIALIZER;
static int rr_on = -1;
/* classes seen: 1 traced, 2 not */
static struct { uintptr_t cls; int v; } rr_cls[4096];

static int rr_traced(uintptr_t cls) {
    size_t j = (cls >> 4) & 4095;
    for (int k = 0; k < 4096; k++, j = (j + 1) & 4095) {
        if (rr_cls[j].cls == cls) return rr_cls[j].v == 1;
        if (!rr_cls[j].cls) {
            const char *n = class_name((Class)cls);
            rr_cls[j].v = n && strstr(n, rr_wanted) ? 1 : 2;
            rr_cls[j].cls = cls;
            return rr_cls[j].v == 1;
        }
    }
    return 0;
}

static void rr_stack(void *pc[RR_DEPTH]) {
    uintptr_t *fp = __builtin_frame_address(0);
    for (int i = 0; i < RR_DEPTH; i++) {
        pc[i] = NULL;
        if (!fp) continue;
        uintptr_t *next = (uintptr_t *)fp[0];
        pc[i] = (void *)fp[1];
        fp = next > fp && (uintptr_t)(next - fp) < (1 << 20) ? next : NULL;
    }
}

void dx_rr_note(void *obj, int delta) {
    if (rr_on < 0) {
        pthread_once(&once, init);
        rr_on = rr_wanted != NULL;
    }
    if (!rr_on || !obj) return;
    uintptr_t isa = *(const uintptr_t *)obj;
    if (isa < 0x1000) return;
    pthread_mutex_lock(&rr_lock);
    if (!rr_traced(isa)) {
        pthread_mutex_unlock(&rr_lock);
        return;
    }
    void *pc[RR_DEPTH];
    rr_stack(pc);
    struct rr_obj *o = NULL;
    for (int i = 0; i < rr_n; i++)
        if (rr_objs[i].obj == (uintptr_t)obj) { o = &rr_objs[i]; break; }
    if (!o) {
        if (rr_n == rr_cap) {
            int cap = rr_cap ? rr_cap * 2 : 64;
            struct rr_obj *t = realloc(rr_objs, (size_t)cap * sizeof *t);
            if (!t) { pthread_mutex_unlock(&rr_lock); return; }
            rr_objs = t;
            rr_cap = cap;
        }
        o = &rr_objs[rr_n++];
        *o = (struct rr_obj){(uintptr_t)obj, 0, 0, NULL};
    }
    /* pc[0] is this function's caller (root_retain/release): skip it */
    struct rr_site *s = NULL;
    for (int i = 0; i < o->n; i++)
        if (!memcmp(o->sites[i].pc, pc + 1, sizeof(void *) * (RR_DEPTH - 1))) { s = &o->sites[i]; break; }
    if (!s) {
        if (o->n == o->cap) {
            int cap = o->cap ? o->cap * 2 : 16;
            struct rr_site *t = realloc(o->sites, (size_t)cap * sizeof *t);
            if (!t) { pthread_mutex_unlock(&rr_lock); return; }
            o->sites = t;
            o->cap = cap;
        }
        s = &o->sites[o->n++];
        memset(s, 0, sizeof *s);
        memcpy(s->pc, pc + 1, sizeof(void *) * (RR_DEPTH - 1));
    }
    s->count += delta;
    pthread_mutex_unlock(&rr_lock);
}

/* An object being freed: its record goes. */
void dx_rr_forget(void *obj) {
    if (rr_on <= 0) return;
    pthread_mutex_lock(&rr_lock);
    for (int i = 0; i < rr_n; i++)
        if (rr_objs[i].obj == (uintptr_t)obj) {
            free(rr_objs[i].sites);
            rr_objs[i] = rr_objs[--rr_n];
            break;
        }
    pthread_mutex_unlock(&rr_lock);
}

static void rr_dump(void) {
    pthread_mutex_lock(&rr_lock);
    char buf[256];
    fprintf(stderr, "bitten: retains: %d traced objects alive\n", rr_n);
    for (int i = 0; i < rr_n; i++) {
        struct rr_obj *o = &rr_objs[i];
        long net = 0;
        for (int k = 0; k < o->n; k++) net += o->sites[k].count;
        fprintf(stderr, "bitten: retains: %#lx %s: %+ld net over %d stacks\n", (unsigned long)o->obj,
                name_of(o->obj, buf, sizeof buf), net, o->n);
        for (int k = 0; k < o->n; k++) {
            if (!o->sites[k].count) continue;
            fprintf(stderr, "bitten: retains:   %+ld", o->sites[k].count);
            for (int d = 0; d < RR_DEPTH - 1 && o->sites[k].pc[d]; d++)
                fprintf(stderr, " %s", where(o->sites[k].pc[d], buf, sizeof buf));
            fprintf(stderr, "\n");
        }
    }
    pthread_mutex_unlock(&rr_lock);
}
