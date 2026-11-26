/* Swift heap objects: allocation, strong/unowned/weak reference counts,
 * boxes, swift_once and exclusivity checks.
 *
 * A native Swift object is {metadata, refcount word}. Compiled code never
 * inlines reference counting on x86-64 Darwin, so the word's encoding is
 * ours. The one constraint comes from statically emitted objects: swiftc
 * emits them with a zero word and an 8-byte once-token just before the
 * object, and calls swift_initStaticObject before first use, which makes
 * them immortal here. Apple's runtime marks immortal objects by setting
 * the low 32 bits; we use the same test so an object written with Apple's
 * immortal pattern is also left alone.
 *
 *   bits  0..31  unowned count: +1 for all strong references together, +1
 *                per unowned reference. The memory is freed when it reaches
 *                zero. All ones: immortal.
 *   bit   32     deiniting: the strong count reached zero (or the compiler
 *                said so with swift_setDeallocating). Strong loads through
 *                weak and unowned references fail from here on.
 *   bit   33     the object has a native weak-reference record (below)
 *   bits 34..63  strong count minus one
 *
 * Weak references (swift_weak*) are bitwise-takable on Darwin: the compiler
 * may move a struct holding one with memcpy. So a weak slot cannot be
 * registered by address the way Objective-C __weak variables are. Instead it
 * points at a small record shared by every weak reference to the object;
 * the record forgets the object when deinit starts and is freed when the
 * last weak reference goes away. */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "dx_objc.h"
#include "swift_internal.h"
#include <malloc.h>
static int quarantine = -1;

#define RC_UNOWNED_MASK 0xFFFFFFFFull
#define RC_DEINITING (1ull << 32)
#define RC_HAS_WEAK (1ull << 33)
#define RC_STRONG_SHIFT 34
#define RC_STRONG_ONE (1ull << RC_STRONG_SHIFT)
#define RC_STRONG_MAX (~0ull >> RC_STRONG_SHIFT)
#define RC_INITIAL 1ull                     /* strong 1, unowned 1 */
#define RC_IMMORTAL (~0ull)                 /* what swift_initStaticObject stores */

static inline int rc_immortal(uint64_t w) { return (w & RC_UNOWNED_MASK) == RC_UNOWNED_MASK; }
static inline uint64_t rc_strong_extra(uint64_t w) { return w >> RC_STRONG_SHIFT; }

/* Pointers with the sign bit set are never heap objects on x86-64 (Apple's
 * runtime makes the same check), and NULL is a no-op everywhere. */
static inline int valid(const void *p) { return (intptr_t)p > 0; }

static inline uint64_t rc_load(const sw_heap_object *o) {
    return __atomic_load_n(&o->refcounts, __ATOMIC_RELAXED);
}
static inline int rc_cas(sw_heap_object *o, uint64_t *old, uint64_t new) {
    return __atomic_compare_exchange_n(&o->refcounts, old, new, 1, __ATOMIC_ACQ_REL, __ATOMIC_RELAXED);
}

static void weak_object_deiniting(sw_heap_object *o);
static void obj_trace(const char *what, sw_heap_object *o);
static const char *trace_obj_name;
/* BITTEN_HEAP_QUARANTINE=1 keeps freed objects' memory, filled with a
 * poison pattern, so a later retain or release of one is reported (with
 * the caller's return addresses) instead of corrupting whatever reused it. */
#include <malloc.h>
#define SW_POISON 0xddddddddddddddddull
static void report_stale(const char *what, const sw_heap_object *o) {
    char line[256];
    int n = snprintf(line, sizeof line, "bitten: %s of freed object %p:", what, (const void *)o);
    void **fp = __builtin_frame_address(0);
    for (int i = 0; i < 14 && fp && n < (int)sizeof line - 20; i++) {
        n += snprintf(line + n, sizeof line - n, " %p", fp[1]);
        void **next = fp[0];
        if (next <= fp || (char *)next - (char *)fp > (1 << 20)) break;
        fp = next;
    }
    fprintf(stderr, "%s\n", line);
}
static void heap_free(sw_heap_object *o) {
    if (trace_obj_name) obj_trace("freed", o);
    if (quarantine < 0) quarantine = getenv("BITTEN_HEAP_QUARANTINE") != NULL;
    if (quarantine) {
        /* the metadata word is left alone (BITTEN_WATCH_OBJ watches it) */
        memset((char *)o + 8, 0xdd, malloc_usable_size(o) - 8);
        return;
    }
    free(o);
}

/* ---- allocation ------------------------------------------------------------ */

/* malloc returns 16-byte aligned blocks; bigger alignments need asking. */
#define MALLOC_ALIGN_MASK 15

static void *slow_alloc(size_t size, size_t align_mask) {
    void *p;
    if (align_mask <= MALLOC_ALIGN_MASK || align_mask == ~(size_t)0) {
        p = malloc(size ? size : 1);
    } else {
        size_t align = align_mask + 1;
        p = aligned_alloc(align, (size + align_mask) & ~align_mask);
    }
    if (!p) dx_fatal("swift: out of memory allocating %zu bytes", size);
    return p;
}
static void *d_swift_slowAlloc(size_t size, size_t align_mask) { return slow_alloc(size, align_mask); }
DX_FN(swift_slowAlloc);

/* Frames of yield-once coroutines (modify/read accessors) that do not fit
 * the caller's fixed buffer. The compiler frees them with free(), so this
 * must be plain malloc. The second argument is a malloc type id, which only
 * selects an allocation zone on macOS. */
static void *d_swift_coroFrameAlloc(size_t size, uint64_t type_id) {
    (void)type_id;
    return malloc(size);
}
DX_FN(swift_coroFrameAlloc);
static void d_swift_slowDealloc(void *p, size_t size, size_t align_mask) {
    if (quarantine < 0) quarantine = getenv("BITTEN_HEAP_QUARANTINE") != NULL;
    if (quarantine && p && getenv("BITTEN_HEAP_QUARANTINE")[0] >= '2') {
        memset(p, 0xdd, malloc_usable_size(p));
        return;
    }
    free(p);
}
DX_FN(swift_slowDealloc);

/* BITTEN_TRACE_OBJ=Name logs where Swift objects whose class name contains
 * Name are allocated and destroyed (raw return addresses, newest first). */
static int trace_obj_inited;
static void obj_trace(const char *what, sw_heap_object *o) {
    if (!trace_obj_inited) {
        trace_obj_name = getenv("BITTEN_TRACE_OBJ");
        trace_obj_inited = 1;
    }
    if (!trace_obj_name || !o || !o->metadata) return;
    uintptr_t k = sw_kind((const sw_metadata *)o->metadata);
    if (k != SW_KIND_CLASS && k <= 0x7FF) return;
    const char *name = sw_type_name((const sw_metadata *)o->metadata, 1);
    if (!name || !strstr(name, trace_obj_name)) return;
    char line[512];
    int n = snprintf(line, sizeof line, "bitten: object %s %p (%s):", what, (void *)o, name);
    void **fp = __builtin_frame_address(0);
    for (int i = 0; i < 12 && fp && n < (int)sizeof line - 20; i++) {
        n += snprintf(line + n, sizeof line - n, " %p", fp[1]);
        void **next = fp[0];
        /* frames without frame pointers break the chain: stay on this stack */
        if (next <= fp || (char *)next - (char *)fp > (1 << 20)) break;
        fp = next;
    }
    fprintf(stderr, "%s\n", line);
}

/* BITTEN_WATCH_OBJ=Name arms a hardware write breakpoint on the first byte
 * (the metadata pointer) of each new object whose class name contains
 * Name, keeping the four newest: a later write to it, which nothing
 * legitimate does, stops the writer with SIGTRAP and a crash report. */
#include <linux/hw_breakpoint.h>
#include <linux/perf_event.h>
#include <sys/syscall.h>
#include <unistd.h>
static const char *watch_obj_name;
static int watch_obj_inited;
static void obj_watch(sw_heap_object *o) {
    static int fds[4] = {-1, -1, -1, -1};
    static unsigned next;
    if (!watch_obj_inited) {
        watch_obj_name = getenv("BITTEN_WATCH_OBJ");
        watch_obj_inited = 1;
    }
    if (!watch_obj_name) return;
    uintptr_t k = sw_kind((const sw_metadata *)o->metadata);
    if (k != SW_KIND_CLASS && k <= 0x7FF) return;
    const char *name = sw_type_name((const sw_metadata *)o->metadata, 1);
    if (!name || !strstr(name, watch_obj_name)) return;
    struct perf_event_attr a;
    memset(&a, 0, sizeof a);
    a.type = PERF_TYPE_BREAKPOINT;
    a.size = sizeof a;
    a.bp_type = HW_BREAKPOINT_W;
    a.bp_addr = (uintptr_t)o;
    a.bp_len = HW_BREAKPOINT_LEN_1;
    a.sample_period = 1;
    a.sigtrap = 1;
    a.remove_on_exec = 1;
    a.exclude_kernel = 1;
    a.exclude_hv = 1;
    unsigned slot = next++ % 4;
    if (fds[slot] >= 0) close(fds[slot]);
    fds[slot] = (int)syscall(SYS_perf_event_open, &a, 0, -1, -1, PERF_FLAG_FD_CLOEXEC);
    if (fds[slot] < 0) fprintf(stderr, "bitten: watch %p failed\n", (void *)o);
    else fprintf(stderr, "bitten: watching %p (%s)\n", (void *)o, name);
}

sw_heap_object *sw_alloc_object(const sw_metadata *m, size_t size, size_t align_mask) {
    sw_heap_object *o = slow_alloc(size, align_mask);
    o->metadata = m;
    o->refcounts = RC_INITIAL;
    if (trace_obj_name || !trace_obj_inited) obj_trace("made", o);
    if (watch_obj_name || !watch_obj_inited) obj_watch(o);
    return o;
}
static sw_heap_object *d_swift_allocObject(const sw_metadata *m, size_t size, size_t align_mask) {
    return sw_alloc_object(m, size, align_mask);
}
DX_FN(swift_allocObject);

/* Stack-promoted objects start with an extra unowned count, so that the
 * final release runs the deinit but nothing ever frees the memory. */
static sw_heap_object *d_swift_initStackObject(const sw_metadata *m, sw_heap_object *o) {
    o->metadata = m;
    o->refcounts = RC_INITIAL + 1;
    return o;
}
DX_FN(swift_initStackObject);

/* Called by the compiler (at -Onone) once a stack object's lifetime ends: by
 * then its deinit must have run and nothing else may still hold it. */
static void d_swift_verifyEndOfLifetime(sw_heap_object *o) {
    uint64_t w = rc_load(o);
    if (rc_strong_extra(w) && !rc_immortal(w))
        dx_fatal("swift: fatal error: stack object %p escaped (it is still referenced at the end of its lifetime)",
                 (void *)o);
}
DX_FN(swift_verifyEndOfLifetime);

/* Statically emitted objects: the once-token sits in the word before the
 * object. The header is written once, atomically, before anyone uses it. */
struct static_init {
    sw_heap_object *o;
    const sw_metadata *m;
};
/* An absolute symbol in Apple's runtime: its address is the refcount word
 * statically initialized objects carry, so binding it hands programs the
 * immortal pattern itself. */
DX_EXPORT("_swiftImmortalRefCount", RC_IMMORTAL);
DX_EXPORT("__swiftImmortalRefCount", RC_IMMORTAL);

static void init_static_object(void *ctx) {
    struct static_init *si = ctx;
    si->o->metadata = si->m;
    __atomic_store_n(&si->o->refcounts, RC_IMMORTAL, __ATOMIC_RELEASE);
}
static void d_swift_once(uintptr_t *predicate, void (*fn)(void *), void *ctx);
static sw_heap_object *d_swift_initStaticObject(const sw_metadata *m, sw_heap_object *o) {
    struct static_init si = {o, m};
    d_swift_once((uintptr_t *)o - 1, init_static_object, &si);
    return o;
}
DX_FN(swift_initStaticObject);

/* ---- strong references ------------------------------------------------------ */

sw_heap_object *sw_retain(sw_heap_object *o) {
    if (!valid(o)) return o;
    if (quarantine > 0 && o->refcounts == SW_POISON) {
        report_stale("retain", o);
        return o;
    }
    uint64_t w = rc_load(o);
    do {
        if (rc_immortal(w)) return o;
        /* an overflowing count makes the object immortal: it leaks, safely */
        if (rc_strong_extra(w) == RC_STRONG_MAX) {
            __atomic_store_n(&o->refcounts, RC_IMMORTAL, __ATOMIC_RELAXED);
            return o;
        }
    } while (!rc_cas(o, &w, w + RC_STRONG_ONE));
    return o;
}

sw_heap_object *sw_retain_n(sw_heap_object *o, uint32_t n) {
    if (!valid(o) || !n) return o;
    uint64_t w = rc_load(o);
    do {
        if (rc_immortal(w)) return o;
        if (rc_strong_extra(w) > RC_STRONG_MAX - n) {
            __atomic_store_n(&o->refcounts, RC_IMMORTAL, __ATOMIC_RELAXED);
            return o;
        }
    } while (!rc_cas(o, &w, w + (uint64_t)n * RC_STRONG_ONE));
    return o;
}

/* Runs the object's destroyer (class deinit + ivar destruction, or the
 * box/context destroyer), which ends with swift_deallocClassInstance or
 * swift_deallocObject. */
sw_heap_object *volatile sw_last_destroyed;
void sw_destroy(sw_heap_object *o) {
    sw_last_destroyed = o;
    if (trace_obj_name) obj_trace("destroyed", o);
    const sw_heap_metadata_header *h = (const sw_heap_metadata_header *)o->metadata - 1;
    if (!h->destroy) {
        /* No destroyer (metadata built without one): the object leaks. */
        static int told;
        if (!told++) {
            dx_log(0, "swift: object %p of %s has no destroyer; leaking it", (void *)o,
                   sw_type_name((const sw_metadata *)o->metadata, 1));
        }
        return;
    }
    sw_call_with_self(h->destroy, o);
}
/* The strong count reached zero and the object is marked: cut its weak
 * references, then destroy it. */
static void deinit_object(sw_heap_object *o, uint64_t w) {
    if (w & RC_HAS_WEAK) weak_object_deiniting(o);
    sw_destroy(o);
}

void sw_release_n(sw_heap_object *o, uint32_t n) {
    if (!valid(o) || !n) return;
    if (quarantine > 0 && o->refcounts == SW_POISON) {
        report_stale("release", o);
        return;
    }
    uint64_t w = rc_load(o), nw;
    for (;;) {
        if (rc_immortal(w)) return;
        uint64_t extra = rc_strong_extra(w);
        if (extra >= n) {
            nw = w - (uint64_t)n * RC_STRONG_ONE;
            if (rc_cas(o, &w, nw)) return;
            continue;
        }
        /* Releases while deinit runs balance retains made by the deinit
         * itself; one too many must not start a second deinit. */
        if (w & RC_DEINITING) return;
        if (extra + 1 != n)
            dx_fatal("swift: object %p over-released (strong count %llu, releasing %u)", (void *)o,
                     (unsigned long long)extra + 1, n);
        nw = (w & ~(RC_STRONG_MAX << RC_STRONG_SHIFT)) | RC_DEINITING;
        if (rc_cas(o, &w, nw)) break;
    }
    deinit_object(o, nw);
}

void sw_release(sw_heap_object *o) { sw_release_n(o, 1); }

static sw_heap_object *d_swift_retain(sw_heap_object *o) { return sw_retain(o); }
DX_FN(swift_retain);
DX_EXPORT("_swift_nonatomic_retain", d_swift_retain);
static void d_swift_release(sw_heap_object *o) { sw_release_n(o, 1); }
DX_FN(swift_release);
DX_EXPORT("_swift_nonatomic_release", d_swift_release);
static sw_heap_object *d_swift_retain_n(sw_heap_object *o, uint32_t n) { return sw_retain_n(o, n); }
DX_FN(swift_retain_n);
DX_EXPORT("_swift_nonatomic_retain_n", d_swift_retain_n);
static void d_swift_release_n(sw_heap_object *o, uint32_t n) { sw_release_n(o, n); }
DX_FN(swift_release_n);
DX_EXPORT("_swift_nonatomic_release_n", d_swift_release_n);

/* Returns 1 (and retains) unless the object's deinit has started. */
int sw_try_retain(sw_heap_object *o) {
    uint64_t w = rc_load(o);
    do {
        if (rc_immortal(w)) return 1;
        if (w & RC_DEINITING) return 0;
        if (rc_strong_extra(w) == RC_STRONG_MAX) return 1; /* saturate: treat as immortal */
    } while (!rc_cas(o, &w, w + RC_STRONG_ONE));
    return 1;
}
static _Bool d_swift_tryRetain(sw_heap_object *o) { return valid(o) && sw_try_retain(o); }
DX_FN(swift_tryRetain);

int sw_is_deiniting(const sw_heap_object *o) {
    uint64_t w = rc_load(o);
    return !rc_immortal(w) && (w & RC_DEINITING);
}
static _Bool d_swift_isDeallocating(sw_heap_object *o) { return valid(o) && sw_is_deiniting(o); }
DX_FN(swift_isDeallocating);

size_t sw_retain_count(const sw_heap_object *o) {
    uint64_t w = rc_load(o);
    if (rc_immortal(w)) return (size_t)1 << 62;
    if (w & RC_DEINITING) return 0;
    return rc_strong_extra(w) + 1;
}
static size_t d_swift_retainCount(sw_heap_object *o) { return valid(o) ? sw_retain_count(o) : 0; }
DX_FN(swift_retainCount);

/* The compiler emits this before tearing down an object it has proven to be
 * uniquely referenced, instead of releasing it. */
void sw_set_deallocating(sw_heap_object *o) {
    if (!valid(o)) return;
    uint64_t w = rc_load(o);
    do {
        if (rc_immortal(w) || (w & RC_DEINITING)) return;
    } while (!rc_cas(o, &w, w | RC_DEINITING));
    if (w & RC_HAS_WEAK) weak_object_deiniting(o);
}
DX_EXPORT("_swift_setDeallocating", sw_set_deallocating);

/* ---- unowned references ------------------------------------------------------ */

void sw_unowned_retain_n(sw_heap_object *o, uint32_t n) {
    if (!valid(o) || !n) return;
    uint64_t w = rc_load(o);
    do {
        if (rc_immortal(w)) return;
        if ((w & RC_UNOWNED_MASK) + n >= RC_UNOWNED_MASK)
            dx_fatal("swift: unowned reference count of %p overflowed", (void *)o);
    } while (!rc_cas(o, &w, w + n));
}

void sw_unowned_release_n(sw_heap_object *o, uint32_t n) {
    if (!valid(o) || !n) return;
    uint64_t w = rc_load(o);
    do {
        if (rc_immortal(w)) return;
        if ((w & RC_UNOWNED_MASK) < n) dx_fatal("swift: object %p over-released (unowned count)", (void *)o);
    } while (!rc_cas(o, &w, w - n));
    if ((w & RC_UNOWNED_MASK) == n) heap_free(o);
}

static sw_heap_object *d_swift_unownedRetain(sw_heap_object *o) {
    sw_unowned_retain_n(o, 1);
    return o;
}
DX_FN(swift_unownedRetain);
DX_EXPORT("_swift_nonatomic_unownedRetain", d_swift_unownedRetain);
static void d_swift_unownedRelease(sw_heap_object *o) { sw_unowned_release_n(o, 1); }
DX_FN(swift_unownedRelease);
DX_EXPORT("_swift_nonatomic_unownedRelease", d_swift_unownedRelease);
static sw_heap_object *d_swift_unownedRetain_n(sw_heap_object *o, uint32_t n) {
    sw_unowned_retain_n(o, n);
    return o;
}
DX_FN(swift_unownedRetain_n);
DX_EXPORT("_swift_nonatomic_unownedRetain_n", d_swift_unownedRetain_n);
static void d_swift_unownedRelease_n(sw_heap_object *o, uint32_t n) { sw_unowned_release_n(o, n); }
DX_FN(swift_unownedRelease_n);
DX_EXPORT("_swift_nonatomic_unownedRelease_n", d_swift_unownedRelease_n);

__attribute__((noreturn)) static void unowned_dead(const void *o) {
    dx_fatal("swift: fatal error: attempted to read an unowned reference but object %p was already deallocated",
             o);
}
static sw_heap_object *d_swift_unownedRetainStrong(sw_heap_object *o) {
    if (valid(o) && !sw_try_retain(o)) unowned_dead(o);
    return o;
}
DX_FN(swift_unownedRetainStrong);
DX_EXPORT("_swift_nonatomic_unownedRetainStrong", d_swift_unownedRetainStrong);
static void d_swift_unownedRetainStrongAndRelease(sw_heap_object *o) {
    if (!valid(o)) return;
    if (!sw_try_retain(o)) unowned_dead(o);
    sw_unowned_release_n(o, 1);
}
DX_FN(swift_unownedRetainStrongAndRelease);
DX_EXPORT("_swift_nonatomic_unownedRetainStrongAndRelease", d_swift_unownedRetainStrongAndRelease);
static void d_swift_unownedCheck(sw_heap_object *o) {
    if (valid(o) && sw_is_deiniting(o)) unowned_dead(o);
}
DX_FN(swift_unownedCheck);
static size_t d_swift_unownedRetainCount(sw_heap_object *o) {
    if (!valid(o)) return 0;
    uint64_t w = rc_load(o);
    if (rc_immortal(w)) return (size_t)1 << 31;
    /* minus the one held on behalf of the strong references */
    return (w & RC_UNOWNED_MASK) - !(w & RC_DEINITING);
}
DX_FN(swift_unownedRetainCount);

/* ---- deallocation ---------------------------------------------------------------- */

/* Drops the unowned count the strong references held. The memory goes once
 * no unowned reference is left (stack objects hold one more and never go). */
static void d_swift_deallocObject(sw_heap_object *o, size_t size, size_t align_mask) {
    if (!valid(o)) return;
    sw_unowned_release_n(o, 1);
}
DX_FN(swift_deallocObject);

static void d_swift_deallocUninitializedObject(sw_heap_object *o, size_t size, size_t align_mask) {
    if (!valid(o)) return;
    sw_set_deallocating(o);
    sw_unowned_release_n(o, 1);
}
DX_FN(swift_deallocUninitializedObject);

/* The last step of every class's destroyer. A Swift class is also an
 * Objective-C class: __weak variables and associated objects may refer to
 * the instance and have to be cleared before the memory can be reused. */
static void d_swift_deallocClassInstance(sw_heap_object *o, size_t size, size_t align_mask) {
    if (!valid(o) || rc_immortal(rc_load(o))) return;
    if (rc_load(o) & RC_HAS_WEAK) weak_object_deiniting(o);
    dx_objc_object_destroyed(o);
    sw_unowned_release_n(o, 1);
}
DX_FN(swift_deallocClassInstance);

/* A failable or throwing initializer gave up on a partially initialised
 * object: destroy the stored properties of the classes whose initializers
 * completed (those below `m`, the class that failed), then free it without
 * running any deinit. */
static void d_swift_deallocPartialClassInstance(sw_heap_object *o, const sw_class_metadata *m, size_t size,
                                                size_t align_mask) {
    if (!valid(o)) return;
    /* Destroy the ivars of the classes below `m` whose initializers ran. */
    const sw_class_metadata *c = (const sw_class_metadata *)o->metadata;
    for (; c && c != m; c = c->superclass) {
        if (!sw_class_is_swift(c)) break;
        if (c->ivar_destroyer) sw_call_with_self(c->ivar_destroyer, o);
    }
    if (!sw_is_native(o)) {
        /* Objective-C ancestry (e.g. the placeholder Swift allocates before
         * calling a factory method imported as an initializer): give the
         * object the nearest pure Objective-C class, whose -dealloc runs,
         * and release it the Objective-C way. */
        const sw_class_metadata *objc = (const sw_class_metadata *)o->metadata;
        while (objc && sw_class_is_swift(objc)) objc = objc->superclass;
        static void *(*set_class)(void *, const void *);
        if (!set_class) set_class = (void *(*)(void *, const void *))dx_registry_lookup("_object_setClass");
        if (objc && set_class) set_class(o, objc);
        dx_objc_release(o);
        return;
    }
    sw_set_deallocating(o);
    d_swift_deallocClassInstance(o, size, align_mask);
}
DX_FN(swift_deallocPartialClassInstance);

/* ---- uniqueness -------------------------------------------------------------------- */

static int unique(const sw_heap_object *o) {
    uint64_t w = rc_load(o);
    return !rc_immortal(w) && rc_strong_extra(w) == 0;
}
static _Bool d_swift_isUniquelyReferenced_native(const sw_heap_object *o) { return valid(o) && unique(o); }
DX_FN(swift_isUniquelyReferenced_native);
DX_EXPORT("_swift_isUniquelyReferenced_nonNull_native", d_swift_isUniquelyReferenced_native);

/* The non-native forms accept any object; an Objective-C object is never
 * reported unique (callers then copy, which is always safe). */
static _Bool d_swift_isUniquelyReferencedNonObjC(const sw_heap_object *o) {
    return valid(o) && sw_is_native(o) && unique(o);
}
DX_FN(swift_isUniquelyReferencedNonObjC);
DX_EXPORT("_swift_isUniquelyReferencedNonObjC_nonNull", d_swift_isUniquelyReferencedNonObjC);
DX_EXPORT("_swift_isUniquelyReferenced", d_swift_isUniquelyReferencedNonObjC);
DX_EXPORT("_swift_isUniquelyReferenced_nonNull", d_swift_isUniquelyReferencedNonObjC);

static _Bool d_swift_isUniquelyReferencedNonObjC_nonNull_bridgeObject(uintptr_t bits) {
    if (bits & SW_BRIDGE_TAG_MASK) return 0;
    if (bits & SW_BRIDGE_OBJC_BIT) return 0;
    return d_swift_isUniquelyReferencedNonObjC((const sw_heap_object *)(bits & ~SW_BRIDGE_SPARE_MASK));
}
DX_FN(swift_isUniquelyReferencedNonObjC_nonNull_bridgeObject);
DX_EXPORT("_swift_isUniquelyReferenced_nonNull_bridgeObject",
          d_swift_isUniquelyReferencedNonObjC_nonNull_bridgeObject);

/* withoutActuallyEscaping: the closure context must not have outlived the
 * call. Returns true after reporting (the caller then traps). */
static _Bool d_swift_isEscapingClosureAtFileLocation(const sw_heap_object *o, const char *file, int32_t file_len,
                                                     int32_t line, int32_t column, unsigned type) {
    if (!valid(o) || unique(o)) return 0;
    fprintf(stderr, "%.*s:%d:%d: Fatal error: %s\n", (int)file_len, file ? file : "", line, column,
            type == 1 ? "closure argument passed as @noescape to Objective-C has escaped"
                      : "closure argument was escaped in withoutActuallyEscaping block");
    return 1;
}
DX_FN(swift_isEscapingClosureAtFileLocation);

/* ---- native weak references ----------------------------------------------------------- */

struct weak_record {
    struct weak_record *next; /* hash chain, while the object is alive */
    sw_heap_object *object;   /* NULL once deinit has started */
    size_t refs;              /* weak slots pointing here, +1 while object is set */
};
#define WEAK_BUCKETS 1024
static struct weak_record *weak_table[WEAK_BUCKETS];
static pthread_mutex_t weak_lock = PTHREAD_MUTEX_INITIALIZER;
static size_t weak_bucket(const void *o) { return ((uintptr_t)o >> 4) % WEAK_BUCKETS; }

/* Under weak_lock. NULL if the object is already deiniting. */
static struct weak_record *weak_record_for(sw_heap_object *o) {
    for (struct weak_record *r = weak_table[weak_bucket(o)]; r; r = r->next)
        if (r->object == o) return r;
    uint64_t w = rc_load(o);
    do {
        if (w & RC_DEINITING) return NULL;
    } while (!rc_cas(o, &w, w | RC_HAS_WEAK));
    struct weak_record *r = malloc(sizeof *r);
    r->object = o;
    r->refs = 1;
    r->next = weak_table[weak_bucket(o)];
    weak_table[weak_bucket(o)] = r;
    return r;
}

static void weak_record_drop(struct weak_record *r) {
    if (!--r->refs) free(r);
}

static void weak_object_deiniting(sw_heap_object *o) {
    pthread_mutex_lock(&weak_lock);
    for (struct weak_record **pp = &weak_table[weak_bucket(o)]; *pp; pp = &(*pp)->next)
        if ((*pp)->object == o) {
            struct weak_record *r = *pp;
            *pp = r->next;
            r->object = NULL;
            weak_record_drop(r);
            break;
        }
    pthread_mutex_unlock(&weak_lock);
}

typedef struct sw_weak_ref {
    struct weak_record *record;
} sw_weak_ref;

static sw_weak_ref *d_swift_weakInit(sw_weak_ref *ref, sw_heap_object *o) {
    struct weak_record *r = NULL;
    if (valid(o) && !rc_immortal(rc_load(o))) {
        pthread_mutex_lock(&weak_lock);
        r = weak_record_for(o);
        if (r) r->refs++;
        pthread_mutex_unlock(&weak_lock);
    } else if (valid(o)) {
        /* immortal objects never die: a record that is never cut suffices */
        r = malloc(sizeof *r);
        r->next = NULL;
        r->object = o;
        r->refs = 1;
    }
    ref->record = r;
    return ref;
}
DX_FN(swift_weakInit);

static void d_swift_weakDestroy(sw_weak_ref *ref) {
    struct weak_record *r = ref->record;
    ref->record = NULL;
    if (!r) return;
    pthread_mutex_lock(&weak_lock);
    weak_record_drop(r);
    pthread_mutex_unlock(&weak_lock);
}
DX_FN(swift_weakDestroy);

static sw_weak_ref *d_swift_weakAssign(sw_weak_ref *ref, sw_heap_object *o) {
    sw_weak_ref fresh;
    d_swift_weakInit(&fresh, o);
    d_swift_weakDestroy(ref);
    ref->record = fresh.record;
    return ref;
}
DX_FN(swift_weakAssign);

static sw_heap_object *d_swift_weakLoadStrong(sw_weak_ref *ref) {
    struct weak_record *r = ref->record;
    if (!r) return NULL;
    pthread_mutex_lock(&weak_lock);
    sw_heap_object *o = r->object;
    if (o && !sw_try_retain(o)) o = NULL;
    pthread_mutex_unlock(&weak_lock);
    return o;
}
DX_FN(swift_weakLoadStrong);

static sw_heap_object *d_swift_weakTakeStrong(sw_weak_ref *ref) {
    sw_heap_object *o = d_swift_weakLoadStrong(ref);
    d_swift_weakDestroy(ref);
    return o;
}
DX_FN(swift_weakTakeStrong);

static sw_weak_ref *d_swift_weakCopyInit(sw_weak_ref *dst, sw_weak_ref *src) {
    struct weak_record *r = src->record;
    if (r) {
        pthread_mutex_lock(&weak_lock);
        if (r->object) r->refs++;
        else r = NULL; /* already nil: no need to share the record */
        pthread_mutex_unlock(&weak_lock);
    }
    dst->record = r;
    return dst;
}
DX_FN(swift_weakCopyInit);

static sw_weak_ref *d_swift_weakTakeInit(sw_weak_ref *dst, sw_weak_ref *src) {
    dst->record = src->record;
    return dst;
}
DX_FN(swift_weakTakeInit);

static sw_weak_ref *d_swift_weakCopyAssign(sw_weak_ref *dst, sw_weak_ref *src) {
    if (dst == src) return dst;
    sw_weak_ref fresh;
    d_swift_weakCopyInit(&fresh, src);
    d_swift_weakDestroy(dst);
    dst->record = fresh.record;
    return dst;
}
DX_FN(swift_weakCopyAssign);

static sw_weak_ref *d_swift_weakTakeAssign(sw_weak_ref *dst, sw_weak_ref *src) {
    if (dst == src) return dst;
    d_swift_weakDestroy(dst);
    dst->record = src->record;
    return dst;
}
DX_FN(swift_weakTakeAssign);

static size_t d_swift_weakRetainCount(sw_heap_object *o) {
    if (!valid(o) || !(rc_load(o) & RC_HAS_WEAK)) return 0;
    size_t n = 0;
    pthread_mutex_lock(&weak_lock);
    for (struct weak_record *r = weak_table[weak_bucket(o)]; r; r = r->next)
        if (r->object == o) n = r->refs - 1;
    pthread_mutex_unlock(&weak_lock);
    return n;
}
DX_FN(swift_weakRetainCount);

/* ---- value witnesses of the builtin reference types -------------------------------------
 * Builtin.NativeObject ($sBoWV), Builtin.UnknownObject ($sBOWV) and
 * Builtin.BridgeObject ($sBbWV), the tables swiftc uses for class references
 * and class-constrained existentials. Each is a single strong pointer whose extra inhabitants are the even values below 4 GiB (the
 * zero page Darwin reserves on x86-64); odd values are Objective-C tagged
 * pointers, so they stay valid. This matches what swiftc inlines. */
static unsigned pointer_get_enum_tag(const sw_opaque *v, unsigned empty_cases, const sw_metadata *self) {
    if (!empty_cases) return 0;
    uint64_t p;
    memcpy(&p, v, 8);
    if (p & 0xFFFFFFFF00000001ull) return 0;
    return (unsigned)(p >> 1) + 1;
}
static void pointer_store_enum_tag(sw_opaque *v, unsigned which, unsigned empty_cases, const sw_metadata *self) {
    if (!which) return; /* the payload is already in place */
    uint64_t p = (uint64_t)(which - 1) << 1;
    memcpy(v, &p, 8);
}

#define REF_VWT(prefix, retain, release)                                                                \
    static sw_opaque *prefix##_init_buffer(sw_value_buffer *d, sw_value_buffer *s, const sw_metadata *m) { \
        d->w[0] = retain(s->w[0]);                                                                     \
        return (sw_opaque *)d;                                                                         \
    }                                                                                                  \
    static void prefix##_destroy(sw_opaque *o, const sw_metadata *m) { release(*(void **)o); }        \
    static sw_opaque *prefix##_init_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {          \
        *(void **)d = retain(*(void **)s);                                                             \
        return d;                                                                                      \
    }                                                                                                  \
    static sw_opaque *prefix##_assign_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {        \
        void *old = *(void **)d;                                                                       \
        *(void **)d = retain(*(void **)s);                                                             \
        release(old);                                                                                  \
        return d;                                                                                      \
    }                                                                                                  \
    static sw_opaque *prefix##_init_take(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {          \
        *(void **)d = *(void **)s;                                                                     \
        return d;                                                                                      \
    }                                                                                                  \
    static sw_opaque *prefix##_assign_take(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {        \
        void *old = *(void **)d;                                                                       \
        *(void **)d = *(void **)s;                                                                     \
        release(old);                                                                                  \
        return d;                                                                                      \
    }
#define REF_VWT_INIT(prefix)                                                                          \
    {                                                                                                  \
        prefix##_init_buffer, prefix##_destroy, prefix##_init_copy, prefix##_assign_copy,             \
            prefix##_init_take, prefix##_assign_take, pointer_get_enum_tag,                            \
            pointer_store_enum_tag, 8, 8, 7 | SW_VW_IS_NON_POD, 0x7FFFFFFF                          \
    }

static void *native_retain(void *o) { return sw_retain(o); }
static void native_release(void *o) { sw_release_n(o, 1); }
REF_VWT(native, native_retain, native_release)
REF_VWT(unknown, sw_unknown_retain, sw_unknown_release)
REF_VWT(bridge, sw_bridge_retain, sw_bridge_release)
const sw_vwt sw_vwt_native_object = REF_VWT_INIT(native);
const sw_vwt sw_vwt_unknown_object = REF_VWT_INIT(unknown);
const sw_vwt sw_vwt_bridge_object = REF_VWT_INIT(bridge);
DX_EXPORT("_$sBoWV", &sw_vwt_native_object);
DX_EXPORT("_$sBOWV", &sw_vwt_unknown_object);
DX_EXPORT("_$sBbWV", &sw_vwt_bridge_object);
/* Their metadata ({value witnesses, kind}; the address point is the second
 * word), which the runtime needs when a generic type has a field of one of
 * these types, e.g. _BridgeStorage's Builtin.BridgeObject. */
static const struct { const sw_vwt *vwt; uintptr_t kind; }
    md_native_object = {&sw_vwt_native_object, SW_KIND_OPAQUE},
    md_unknown_object = {&sw_vwt_unknown_object, SW_KIND_OPAQUE},
    md_bridge_object = {&sw_vwt_bridge_object, SW_KIND_OPAQUE};
DX_EXPORT("_$sBoN", &md_native_object);
DX_EXPORT("_$sBON", &md_unknown_object);
DX_EXPORT("_$sBbN", &md_bridge_object);

/* () -> () ($syycWV), the table swiftc uses for any thick closure value:
 * a function pointer and a (nullable) native context. A function pointer
 * has no alignment bits to spare, so its extra inhabitants are simply the
 * values below 4 GiB. */
typedef struct {
    void *fn;
    sw_heap_object *ctx;
} closure;
static sw_opaque *closure_init_buffer(sw_value_buffer *d, sw_value_buffer *s, const sw_metadata *m) {
    d->w[0] = s->w[0];
    d->w[1] = sw_retain(s->w[1]);
    return (sw_opaque *)d;
}
static void closure_destroy(sw_opaque *o, const sw_metadata *m) { sw_release(((closure *)o)->ctx); }
static sw_opaque *closure_init_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    *(closure *)d = *(closure *)s;
    sw_retain(((closure *)d)->ctx);
    return d;
}
static sw_opaque *closure_assign_copy(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    sw_heap_object *old = ((closure *)d)->ctx;
    *(closure *)d = *(closure *)s;
    sw_retain(((closure *)d)->ctx);
    sw_release(old);
    return d;
}
static sw_opaque *closure_init_take(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    *(closure *)d = *(closure *)s;
    return d;
}
static sw_opaque *closure_assign_take(sw_opaque *d, sw_opaque *s, const sw_metadata *m) {
    sw_heap_object *old = ((closure *)d)->ctx;
    *(closure *)d = *(closure *)s;
    sw_release(old);
    return d;
}
static unsigned closure_get_enum_tag(const sw_opaque *v, unsigned empty_cases, const sw_metadata *m) {
    uint64_t fn = (uint64_t)((const closure *)v)->fn;
    if (!empty_cases || fn > 0xFFFFFFFEull) return 0;
    return (unsigned)fn + 1;
}
static void closure_store_enum_tag(sw_opaque *v, unsigned which, unsigned empty_cases, const sw_metadata *m) {
    if (which) ((closure *)v)->fn = (void *)(uintptr_t)(which - 1);
}
const sw_vwt sw_vwt_thick_closure = {
    closure_init_buffer, closure_destroy, closure_init_copy, closure_assign_copy, closure_init_take,
    closure_assign_take, closure_get_enum_tag, closure_store_enum_tag, 16, 16, 7 | SW_VW_IS_NON_POD, 0x7FFFFFFF,
};
DX_EXPORT("_$syycWV", &sw_vwt_thick_closure);

/* ---- boxes ------------------------------------------------------------------------------
 * swift_allocBox makes a heap box for a value of a runtime type (local
 * variables captured by closures, at -Onone and in generic code). Each boxed
 * type gets one box metadata, laid out as the ABI's generic box: heap
 * metadata header, kind, value offset, boxed type. */
typedef struct box_metadata {
    sw_heap_metadata_header header;
    uintptr_t kind; /* SW_KIND_HEAP_GENERIC_LOCAL_VARIABLE; the metadata address point */
    uint32_t offset;
    const sw_metadata *boxed;
    struct box_metadata *next;
} box_metadata;
static box_metadata *box_of(const sw_heap_object *o) {
    return (box_metadata *)((char *)o->metadata - offsetof(box_metadata, kind));
}

typedef struct {
    sw_heap_object *object;
    sw_opaque *value;
} sw_box_pair;

static size_t box_size(const box_metadata *b, size_t *align_mask) {
    const sw_vwt *v = b->boxed ? sw_vwt_of(b->boxed) : NULL;
    size_t am = v ? (v->flags & SW_VW_ALIGNMENT_MASK) : 7;
    if (am < 7) am = 7;
    *align_mask = am;
    return b->offset + (v ? v->size : 0);
}

/* BITTEN_TRACE_BOX=TypeName logs where boxes of types whose name contains
 * TypeName are allocated and freed (raw return addresses, newest first). */
static const char *trace_box_name;
static int trace_box_inited;
static void box_trace(const char *what, sw_heap_object *o, const sw_metadata *type) {
    if (!trace_box_inited) {
        trace_box_name = getenv("BITTEN_TRACE_BOX");
        trace_box_inited = 1;
    }
    if (!trace_box_name || !type) return;
    const char *name = sw_type_name(type, 1);
    if (!name || !strstr(name, trace_box_name)) return;
    char line[512];
    int n = snprintf(line, sizeof line, "bitten: box %s %p (%s):", what, (void *)o, name);
    void **fp = __builtin_frame_address(0);
    for (int i = 0; i < 10 && fp && n < (int)sizeof line - 20; i++) {
        void *ret = fp[1];
        n += snprintf(line + n, sizeof line - n, " %p", ret);
        void **next = fp[0];
        /* frames without frame pointers break the chain: stay on this stack */
        if (next <= fp || (char *)next - (char *)fp > (1 << 20)) break;
        fp = next;
    }
    fprintf(stderr, "%s\n", line);
}

static void box_destroy(void *obj) {
    sw_heap_object *o = obj;
    box_metadata *b = box_of(o);
    box_trace("freed", o, b->boxed);
    if (b->boxed) sw_vwt_of(b->boxed)->destroy((sw_opaque *)((char *)o + b->offset), b->boxed);
    d_swift_deallocObject(o, 0, 0);
}

#define BOX_BUCKETS 256
static box_metadata *box_table[BOX_BUCKETS];
static pthread_mutex_t box_lock = PTHREAD_MUTEX_INITIALIZER;

static const sw_metadata *box_metadata_for(const sw_metadata *type) {
    size_t h = ((uintptr_t)type >> 4) % BOX_BUCKETS;
    pthread_mutex_lock(&box_lock);
    box_metadata *b = box_table[h];
    while (b && b->boxed != type) b = b->next;
    if (!b) {
        b = calloc(1, sizeof *b);
        b->header.destroy = box_destroy;
        b->header.vwt = &sw_vwt_native_object;
        b->kind = SW_KIND_HEAP_GENERIC_LOCAL_VARIABLE;
        size_t am = sw_vwt_of(type)->flags & SW_VW_ALIGNMENT_MASK;
        b->offset = (uint32_t)((sizeof(sw_heap_object) + am) & ~am);
        b->boxed = type;
        b->next = box_table[h];
        box_table[h] = b;
    }
    pthread_mutex_unlock(&box_lock);
    return (const sw_metadata *)&b->kind;
}

static sw_box_pair d_swift_allocBox(const sw_metadata *type) {
    const sw_metadata *m = box_metadata_for(type);
    box_metadata *b = (box_metadata *)((char *)m - offsetof(box_metadata, kind));
    size_t am, size = box_size(b, &am);
    sw_heap_object *o = sw_alloc_object(m, size, am);
    box_trace("made", o, type);
    return (sw_box_pair){o, (sw_opaque *)((char *)o + b->offset)};
}
DX_FN(swift_allocBox);

/* A box whose value was never initialised, or was already destroyed. */
static void d_swift_deallocBox(sw_heap_object *o) { d_swift_deallocObject(o, 0, 0); }
DX_FN(swift_deallocBox);

static sw_opaque *d_swift_projectBox(sw_heap_object *o) {
    /* boxes of empty types may be nil: any address will do for them */
    if (!o) return NULL;
    return (sw_opaque *)((char *)o + box_of(o)->offset);
}
DX_FN(swift_projectBox);

/* `buffer` is an existential buffer holding a reference to a box. Make sure
 * the box is not shared before it is written to (copy-on-write). */
static sw_box_pair d_swift_makeBoxUnique(sw_value_buffer *buffer, const sw_metadata *type, size_t align_mask) {
    sw_heap_object *box = buffer->w[0];
    size_t offset = (sizeof(sw_heap_object) + align_mask) & ~align_mask;
    sw_opaque *value = (sw_opaque *)((char *)box + offset);
    if (unique(box)) return (sw_box_pair){box, value};
    sw_box_pair fresh = d_swift_allocBox(type);
    sw_vwt_of(type)->initializeWithCopy(fresh.value, value, type);
    buffer->w[0] = fresh.object;
    sw_release_n(box, 1);
    return fresh;
}
DX_FN(swift_makeBoxUnique);

/* One immortal box serves every value of an empty type. */
static struct {
    box_metadata md;
    sw_heap_object object;
} empty_box = {
    .md = {.header = {NULL, box_destroy, &sw_vwt_native_object},
           .kind = SW_KIND_HEAP_GENERIC_LOCAL_VARIABLE,
           .offset = sizeof(sw_heap_object)},
    .object = {(const sw_metadata *)&empty_box.md.kind, RC_IMMORTAL},
};
static sw_heap_object *d_swift_allocEmptyBox(void) { return &empty_box.object; }
DX_FN(swift_allocEmptyBox);

/* Fills the vtable slots of methods that were deleted (unavailable
 * initializers and the like): calling one is a bug in the program. */
static void d_swift_deletedMethodError(void) { dx_fatal("swift: fatal error: call of deleted method"); }
DX_FN(swift_deletedMethodError);

/* ---- swift_once ---------------------------------------------------------------------------
 * The predicate is one word. Compiled code tests it inline against ~0
 * ("cmpq $-1, token; jne slow") before calling here, as with dispatch_once
 * on Darwin, so ~0 must mean done. 0 is the initial state, 1 is "running". */
static pthread_mutex_t once_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t once_cond = PTHREAD_COND_INITIALIZER;
#define ONCE_DONE (~(uintptr_t)0)
#define ONCE_RUNNING ((uintptr_t)1)

static void d_swift_once(uintptr_t *predicate, void (*fn)(void *), void *ctx) {
    if (__atomic_load_n(predicate, __ATOMIC_ACQUIRE) == ONCE_DONE) return;
    pthread_mutex_lock(&once_lock);
    while (*predicate == ONCE_RUNNING) pthread_cond_wait(&once_cond, &once_lock);
    if (*predicate == ONCE_DONE) {
        pthread_mutex_unlock(&once_lock);
        return;
    }
    *predicate = ONCE_RUNNING;
    pthread_mutex_unlock(&once_lock);
    fn(ctx);
    pthread_mutex_lock(&once_lock);
    __atomic_store_n(predicate, ONCE_DONE, __ATOMIC_RELEASE);
    pthread_cond_broadcast(&once_cond);
    pthread_mutex_unlock(&once_lock);
}
DX_FN(swift_once);

/* ---- exclusivity ----------------------------------------------------------------------------
 * swift_beginAccess/swift_endAccess let the runtime catch overlapping
 * accesses to the same variable, a diagnostic for programs that are already
 * wrong. They are accepted without tracking: a correct program behaves the
 * same, an incorrect one is not stopped. The buffer the compiler passes is
 * scratch space owned by the runtime; it is cleared so endAccess has nothing
 * stale to look at. */
static void d_swift_beginAccess(void *pointer, sw_value_buffer *buffer, uintptr_t flags, void *pc) {
    if (buffer) memset(buffer, 0, sizeof *buffer);
}
DX_FN(swift_beginAccess);
static void d_swift_endAccess(sw_value_buffer *buffer) {}
DX_FN(swift_endAccess);
