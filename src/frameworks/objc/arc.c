/* Objective-C object lifetime: reference counts, weak references,
 * autorelease pools, the ARC entry points the compiler emits, associated
 * objects, property accessors' helpers, @synchronized, and NSObject. */
#define _GNU_SOURCE
#include <stdlib.h>
#include <malloc.h>
#include <string.h>

#include "objc_internal.h"

/* ---- side table -----------------------------------------------------------
 * Reference counts live outside the objects, in sharded hash tables keyed by
 * address. An object with no entry has a retain count of one. */
#define SHARDS 64
struct rc_entry {
    id obj;          /* NULL: empty, (id)1: deleted */
    uintptr_t extra; /* retain count minus one */
    unsigned deallocating : 1, weakly_referenced : 1, has_assoc : 1;
};
/* A shard's lock is held only for a probe of its table (no calls out), so
 * a spinlock: every retain and release takes one, and an uncontended
 * pthread mutex costs several times as much. */
struct shard {
    _Atomic int lock;
    struct rc_entry *e;
    size_t cap, used, live;
} shards[SHARDS];

static struct shard *shard_for(id obj) { return &shards[((uintptr_t)obj >> 4) % SHARDS]; }
static inline void shard_lock(struct shard *s) {
    while (__atomic_exchange_n(&s->lock, 1, __ATOMIC_ACQUIRE))
        while (__atomic_load_n(&s->lock, __ATOMIC_RELAXED)) __builtin_ia32_pause();
}
static inline void shard_unlock(struct shard *s) { __atomic_store_n(&s->lock, 0, __ATOMIC_RELEASE); }

static struct rc_entry *rc_find(struct shard *s, id obj, int create) {
    if (!s->cap) {
        if (!create) return NULL;
        s->cap = 64;
        s->e = calloc(s->cap, sizeof *s->e);
    }
    if (create && (s->used + 1) * 2 > s->cap) {
        size_t ncap = s->live * 4 > s->cap ? s->cap * 2 : s->cap;
        struct rc_entry *ne = calloc(ncap, sizeof *ne);
        for (size_t i = 0; i < s->cap; i++) {
            if (!s->e[i].obj || s->e[i].obj == (id)1) continue;
            size_t j = ((uintptr_t)s->e[i].obj >> 4) * 0x9E3779B97F4A7C15ULL >> 32 & (ncap - 1);
            while (ne[j].obj) j = (j + 1) & (ncap - 1);
            ne[j] = s->e[i];
        }
        free(s->e);
        s->e = ne;
        s->cap = ncap;
        s->used = s->live;
    }
    size_t i = ((uintptr_t)obj >> 4) * 0x9E3779B97F4A7C15ULL >> 32 & (s->cap - 1);
    struct rc_entry *tomb = NULL;
    while (s->e[i].obj) {
        if (s->e[i].obj == obj) return &s->e[i];
        if (s->e[i].obj == (id)1 && !tomb) tomb = &s->e[i];
        i = (i + 1) & (s->cap - 1);
    }
    if (!create) return NULL;
    struct rc_entry *e = tomb ? tomb : &s->e[i];
    if (!tomb) s->used++;
    s->live++;
    memset(e, 0, sizeof *e);
    e->obj = obj;
    return e;
}

static void rc_remove(struct shard *s, struct rc_entry *e) {
    e->obj = (id)1;
    s->live--;
}

id root_retain(id obj) {
    struct shard *s = shard_for(obj);
    shard_lock(s);
    rc_find(s, obj, 1)->extra++;
    shard_unlock(s);
    if (dx_rr_active) dx_rr_note(obj, 1);
    return obj;
}

int root_try_retain(id obj) {
    struct shard *s = shard_for(obj);
    shard_lock(s);
    struct rc_entry *e = rc_find(s, obj, 1);
    int ok = !e->deallocating;
    if (ok) e->extra++;
    shard_unlock(s);
    if (ok && dx_rr_active) dx_rr_note(obj, 1);
    return ok;
}

void root_release(id obj) {
    if (dx_rr_active) dx_rr_note(obj, -1);
    struct shard *s = shard_for(obj);
    shard_lock(s);
    struct rc_entry *e = rc_find(s, obj, 0);
    if (e && e->extra > 0) {
        e->extra--;
        if (!e->extra && !e->weakly_referenced && !e->has_assoc && !e->deallocating) rc_remove(s, e);
        shard_unlock(s);
        return;
    }
    if (e && e->deallocating) { /* over-release during dealloc: ignore */
        shard_unlock(s);
        return;
    }
    if (!e) e = rc_find(s, obj, 1);
    e->deallocating = 1;
    shard_unlock(s);
    MSG(void, id, SEL)(obj, SEL_dealloc);
}

unsigned long root_retain_count(id obj) {
    struct shard *s = shard_for(obj);
    shard_lock(s);
    struct rc_entry *e = rc_find(s, obj, 0);
    unsigned long n = e ? e->extra + 1 : 1;
    shard_unlock(s);
    return n;
}

/* ---- weak references ------------------------------------------------------ */

struct weak_ref {
    struct weak_ref *next;
    id referent;
    id *slot;
};
/* Weak references and associated objects hang off these buckets by
 * object. A program has tens of thousands of objects with a few of each
 * (views keep several associated values), so the table is large and the
 * address is mixed: short chains keep lookups (and the lock) brief. */
#define WEAK_BUCKETS (1 << 16)
static struct weak_ref *weak_table[WEAK_BUCKETS];
static pthread_mutex_t weak_lock = PTHREAD_MUTEX_INITIALIZER;

static size_t weak_bucket(id obj) { return (size_t)(((uintptr_t)obj >> 4) * 0x9E3779B97F4A7C15ull >> 48) & (WEAK_BUCKETS - 1); }

/* Whether `slot` is a __weak variable pointing at `referent` (for
 * BITTEN_FIND_REFS: a weak reference doesn't keep it alive). */
int dx_objc_is_weak_slot(void *referent, void *slot) {
    int found = 0;
    pthread_mutex_lock(&weak_lock);
    for (struct weak_ref *w = weak_table[weak_bucket((id)referent)]; w && !found; w = w->next)
        found = w->slot == (id *)slot && w->referent == (id)referent;
    pthread_mutex_unlock(&weak_lock);
    return found;
}

static void weak_unregister(id referent, id *slot) {
    for (struct weak_ref **pp = &weak_table[weak_bucket(referent)]; *pp; pp = &(*pp)->next)
        if ((*pp)->slot == slot && (*pp)->referent == referent) {
            struct weak_ref *w = *pp;
            *pp = w->next;
            free(w);
            return;
        }
}

static int custom_rr(Class c);

/* Classes with their own reference counting (Swift's root class) decide
 * whether a weak reference may be formed or loaded, through the same
 * messages as on macOS. Returns -1 when the class has no say. */
static int ask_custom_weak(id obj, SEL sel) {
    Class c = objc_class_of(obj);
    if (!class_realized(c)) {
        pthread_mutex_lock(&dx_objc_lock);
        realize_class(c);
        pthread_mutex_unlock(&dx_objc_lock);
    }
    if (!custom_rr(c) || !class_lookup_imp(c, sel)) return -1;
    return MSG(char, id, SEL)(obj, sel) != 0;
}

static int is_deallocating(id obj) {
    int allowed = ask_custom_weak(obj, SEL_allowsWeakReference);
    if (allowed >= 0) return !allowed;
    struct shard *s = shard_for(obj);
    shard_lock(s);
    struct rc_entry *e = rc_find(s, obj, 0);
    int d = e && e->deallocating;
    shard_unlock(s);
    return d;
}

extern int dx_objc_weak_custom_rr;
static id store_weak(id *location, id obj) {
    pthread_mutex_lock(&weak_lock);
    id old = *location;
    if (old) weak_unregister(old, location);
    if (obj && is_deallocating(obj)) obj = NULL;
    *location = obj;
    if (obj) {
        struct weak_ref *w = malloc(sizeof *w);
        w->referent = obj;
        w->slot = location;
        size_t b = weak_bucket(obj);
        w->next = weak_table[b];
        weak_table[b] = w;
        struct shard *s = shard_for(obj);
        shard_lock(s);
        rc_find(s, obj, 1)->weakly_referenced = 1;
        shard_unlock(s);
        /* Objects that count their own references (CF's) die without
         * NSObject's dealloc; they clear their weak references through
         * dx_objc_weak_referent_dying. */
        if (custom_rr(objc_class_of(obj))) __atomic_store_n(&dx_objc_weak_custom_rr, 1, __ATOMIC_RELAXED);
    }
    pthread_mutex_unlock(&weak_lock);
    return obj;
}


static void weak_clear(id obj) {
    pthread_mutex_lock(&weak_lock);
    for (struct weak_ref **pp = &weak_table[weak_bucket(obj)]; *pp;) {
        struct weak_ref *w = *pp;
        if (w->referent == obj) {
            *w->slot = NULL;
            *pp = w->next;
            free(w);
        } else pp = &w->next;
    }
    pthread_mutex_unlock(&weak_lock);
}

int dx_objc_weak_custom_rr;
/* Called by objects with their own reference counts as they die: clears
 * the weak references to them. */
void dx_objc_weak_referent_dying(void *obj) {
    struct shard *s = shard_for(obj);
    shard_lock(s);
    struct rc_entry *e = rc_find(s, obj, 0);
    int weak = e && e->weakly_referenced;
    if (e) rc_remove(s, e);
    shard_unlock(s);
    if (weak) weak_clear(obj);
}

static id d_objc_retain(id obj);
static void d_objc_release(id obj);
static id d_objc_autorelease(id obj);

static id d_objc_storeWeak(id *location, id obj) { return store_weak(location, obj); }
DX_FN(objc_storeWeak);
static id d_objc_initWeak(id *location, id obj) {
    *location = NULL;
    return obj ? store_weak(location, obj) : NULL;
}
DX_FN(objc_initWeak);
static void d_objc_destroyWeak(id *location) {
    pthread_mutex_lock(&weak_lock);
    if (*location) weak_unregister(*location, location);
    *location = NULL;
    pthread_mutex_unlock(&weak_lock);
}
DX_FN(objc_destroyWeak);
static id d_objc_loadWeakRetained(id *location) {
    pthread_mutex_lock(&weak_lock);
    id obj = *location;
    if (obj) {
        /* objects with their own retain/release decide for themselves */
        int r = ask_custom_weak(obj, SEL_retainWeakReference);
        if (r < 0 && custom_rr(objc_class_of(obj))) {
            /* Their own retain, not the side table's: a side-table retain
             * would be balanced by a release of their own count. They clear
             * their weak references before they die, so obj is alive. */
            d_objc_retain(obj);
            r = 1;
        }
        if (r < 0) r = root_try_retain(obj);
        if (!r) obj = NULL;
    }
    pthread_mutex_unlock(&weak_lock);
    return obj;
}
DX_FN(objc_loadWeakRetained);
static id d_objc_loadWeak(id *location) { return d_objc_autorelease(d_objc_loadWeakRetained(location)); }
DX_FN(objc_loadWeak);
static void d_objc_copyWeak(id *dst, id *src) {
    id obj = d_objc_loadWeakRetained(src);
    d_objc_initWeak(dst, obj);
    d_objc_release(obj);
}
DX_FN(objc_copyWeak);
static void d_objc_moveWeak(id *dst, id *src) {
    d_objc_copyWeak(dst, src);
    d_objc_destroyWeak(src);
}
DX_FN(objc_moveWeak);
void *dx_objc_init_weak(void **slot, void *obj) { return d_objc_initWeak((id *)slot, obj); }
void *dx_objc_store_weak(void **slot, void *obj) { return store_weak((id *)slot, obj); }
void *dx_objc_load_weak_retained(void **slot) { return d_objc_loadWeakRetained((id *)slot); }
void dx_objc_destroy_weak(void **slot) { d_objc_destroyWeak((id *)slot); }
void dx_objc_copy_weak(void **dst, void **src) { d_objc_copyWeak((id *)dst, (id *)src); }
void dx_objc_move_weak(void **dst, void **src) { d_objc_moveWeak((id *)dst, (id *)src); }

/* ---- associated objects --------------------------------------------------- */

struct assoc {
    struct assoc *next;
    id object;
    const void *key;
    id value;
    uintptr_t policy;
};
static struct assoc *assoc_table[WEAK_BUCKETS];
static pthread_mutex_t assoc_lock = PTHREAD_MUTEX_INITIALIZER;

static void d_objc_setAssociatedObject(id object, const void *key, id value, uintptr_t policy) {
    if (!object) return;
    id keep = NULL;
    switch (policy & 0xff) {
    case 1: keep = d_objc_retain(value); break;
    case 3: keep = value ? MSG(id, id, SEL, void *)(value, SEL_copyWithZone, NULL) : NULL; break;
    default: keep = value; break;
    }
    id old = NULL;
    uintptr_t old_policy = 0;
    pthread_mutex_lock(&assoc_lock);
    struct assoc **pp = &assoc_table[weak_bucket(object)];
    for (; *pp; pp = &(*pp)->next)
        if ((*pp)->object == object && (*pp)->key == key) break;
    if (*pp) {
        old = (*pp)->value;
        old_policy = (*pp)->policy;
        if (value) {
            (*pp)->value = keep;
            (*pp)->policy = policy;
        } else {
            struct assoc *a = *pp;
            *pp = a->next;
            free(a);
        }
    } else if (value) {
        struct assoc *a = malloc(sizeof *a);
        a->object = object;
        a->key = key;
        a->value = keep;
        a->policy = policy;
        a->next = assoc_table[weak_bucket(object)];
        assoc_table[weak_bucket(object)] = a;
        struct shard *s = shard_for(object);
        shard_lock(s);
        rc_find(s, object, 1)->has_assoc = 1;
        shard_unlock(s);
    }
    pthread_mutex_unlock(&assoc_lock);
    if (old && (old_policy & 0xff)) d_objc_release(old);
}
DX_FN(objc_setAssociatedObject);

static id d_objc_getAssociatedObject(id object, const void *key) {
    id value = NULL;
    uintptr_t policy = 0;
    pthread_mutex_lock(&assoc_lock);
    for (struct assoc *a = assoc_table[weak_bucket(object)]; a; a = a->next)
        if (a->object == object && a->key == key) {
            value = a->value;
            policy = a->policy;
            if (policy & 0xff) d_objc_retain(value);
            break;
        }
    pthread_mutex_unlock(&assoc_lock);
    if (value && (policy & 0xff)) d_objc_autorelease(value);
    return value;
}
DX_FN(objc_getAssociatedObject);

static void d_objc_removeAssociatedObjects(id object) {
    struct assoc *dead = NULL;
    pthread_mutex_lock(&assoc_lock);
    for (struct assoc **pp = &assoc_table[weak_bucket(object)]; *pp;) {
        struct assoc *a = *pp;
        if (a->object == object) {
            *pp = a->next;
            a->next = dead;
            dead = a;
        } else pp = &a->next;
    }
    pthread_mutex_unlock(&assoc_lock);
    while (dead) {
        struct assoc *a = dead;
        dead = a->next;
        if (a->policy & 0xff) d_objc_release(a->value);
        free(a);
    }
}
DX_FN(objc_removeAssociatedObjects);

/* ---- destruction ---------------------------------------------------------- */

static void *d_objc_destructInstance(id obj) {
    if (!obj) return NULL;
    /* ARC-generated ivar releases and C++ destructors, most-derived first */
    for (Class c = objc_class_of(obj); c; c = c->superclass) {
        pthread_mutex_lock(&dx_objc_lock);
        IMP imp = NULL;
        for (struct mlist *l = RW(c)->methods; l && !imp; l = l->next)
            for (int i = 0; i < l->count; i++)
                if (l->m[i].name == SEL_cxx_destruct) imp = l->m[i].imp;
        pthread_mutex_unlock(&dx_objc_lock);
        if (imp) ((void (*)(id, SEL))imp)(obj, SEL_cxx_destruct);
    }
    dx_objc_object_destroyed(obj);
    return obj;
}
DX_FN(objc_destructInstance);

/* Clears what the runtime keeps about an object outside it: associated
 * objects, __weak variables, its side-table entry. Also used by the Swift
 * runtime, whose objects are freed without objc_destructInstance. */
void dx_objc_object_destroyed(void *object) {
    id obj = object;
    struct shard *s = shard_for(obj);
    shard_lock(s);
    struct rc_entry *e = rc_find(s, obj, 0);
    int weak = e && e->weakly_referenced, assoc = e && e->has_assoc;
    if (!weak && !assoc) {
        /* Most objects: nothing to clear but the entry, under one lock. */
        if (e) rc_remove(s, e);
        shard_unlock(s);
        return;
    }
    shard_unlock(s);
    if (assoc) d_objc_removeAssociatedObjects(obj);
    if (weak) weak_clear(obj);
    shard_lock(s);
    e = rc_find(s, obj, 0);
    if (e) rc_remove(s, e);
    shard_unlock(s);
}

void object_dispose_impl(id obj) {
    if (!obj) return;
    dx_alloc_note(obj->isa, -1);
    dx_live_note(obj, -1);
    if (dx_rr_active) dx_rr_forget(obj);
    d_objc_destructInstance(obj);
    /* BITTEN_HEAP_QUARANTINE=3: keep freed objects' memory, poisoned (debugging) */
    static int zombies = -1;   /* read once: this runs for every object freed */
    if (zombies < 0) {
        const char *q = getenv("BITTEN_HEAP_QUARANTINE");
        zombies = q && q[0] == '3';
    }
    if (zombies) {
        /* the class stays in the second word, for reporting a zombie */
        Class was = obj->isa;
        memset(obj, 0xdd, malloc_usable_size(obj));
        ((Class *)obj)[1] = was;
        return;
    }
    free(obj);
}
static id d_object_dispose(id obj) {
    object_dispose_impl(obj);
    return NULL;
}
DX_FN(object_dispose);
static id d_class_createInstance(Class cls, size_t extra) { return class_create_instance(cls, extra); }
DX_FN(class_createInstance);
static id d_objc_constructInstance(Class cls, void *bytes) {
    if (!cls || !bytes) return NULL;
    id obj = bytes;
    obj->isa = cls;
    return obj;
}
DX_FN(objc_constructInstance);
static id d_object_copy(id obj, size_t extra) {
    if (!obj) return NULL;
    Class c = objc_class_of(obj);
    id copy = class_create_instance(c, extra);
    memcpy((char *)copy + sizeof(void *), (char *)obj + sizeof(void *),
           RW(c)->instance_size - sizeof(void *) + extra);
    return copy;
}
DX_FN(object_copy);

/* ---- retain / release entry points ---------------------------------------- */

static id ns_retain(id self, SEL _cmd);
static void ns_release(id self, SEL _cmd);
static id ns_autorelease(id self, SEL _cmd);

/* Does this class use NSObject's own retain/release? */
static int default_rr(Class cls);
static int custom_rr(Class c) { return !default_rr(c); }
static int default_rr(Class cls) {
    struct class_rw *rw = RW(cls);
    if (!rw->rr_state) {
        int custom = class_lookup_imp(cls, SEL_retain) != (IMP)ns_retain ||
                     class_lookup_imp(cls, SEL_release) != (IMP)ns_release ||
                     class_lookup_imp(cls, SEL_autorelease) != (IMP)ns_autorelease;
        rw->rr_state = custom ? 2 : 1;
    }
    return rw->rr_state == 1;
}

/* A retain of an object freed under BITTEN_HEAP_QUARANTINE=3. */
static void zombie(id obj, const char *what) {
    fprintf(stderr, "bitten: %s of freed %s %p\n", what, class_name(((Class *)obj)[1]), (void *)obj);
    abort();
}
static id d_objc_retain(id obj) {
    if (!obj || ((uintptr_t)obj & 1)) return obj;
    Class c = obj->isa;
    if ((uintptr_t)c == 0xddddddddddddddddull) zombie(obj, "retain");
    if (class_realized(c) && default_rr(c)) return root_retain(obj);
    return MSG(id, id, SEL)(obj, SEL_retain);
}
DX_FN(objc_retain);
static void d_objc_release(id obj) {
    if (!obj || ((uintptr_t)obj & 1)) return;
    Class c = obj->isa;
    if (class_realized(c) && default_rr(c)) root_release(obj);
    else MSG(void, id, SEL)(obj, SEL_release);
}
DX_FN(objc_release);
void *dx_objc_retain(void *obj) { return d_objc_retain(obj); }
void dx_objc_release(void *obj) { d_objc_release(obj); }

/* ---- autorelease pools ----------------------------------------------------- */

struct pool {
    id *objs;
    size_t count, cap;
    size_t depth; /* number of pools pushed */
};
static __thread struct pool tls_pool;
static pthread_key_t pool_key;
#define POOL_MARK ((id)(uintptr_t)-1)

static void pool_push_obj(struct pool *p, id obj) {
    if (p->count == p->cap) {
        p->cap = p->cap ? p->cap * 2 : 256;
        p->objs = realloc(p->objs, p->cap * sizeof *p->objs);
    }
    p->objs[p->count++] = obj;
}

static void *d_objc_autoreleasePoolPush(void) {
    struct pool *p = &tls_pool;
    if (!p->cap) pthread_setspecific(pool_key, p);
    pool_push_obj(p, POOL_MARK);
    p->depth++;
    return (void *)(uintptr_t)p->count; /* token: index just past the mark */
}
DX_FN(objc_autoreleasePoolPush);
/* The underscored spellings the compiler emits for @autoreleasepool in
 * Swift on newer SDKs. */
DX_EXPORT("__objc_autoreleasePoolPush", d_objc_autoreleasePoolPush);

static void pool_drain_to(struct pool *p, size_t mark_index) {
    while (p->count > mark_index) {
        id obj = p->objs[--p->count];
        if (obj == POOL_MARK) {
            if (p->depth) p->depth--;
            continue;
        }
        d_objc_release(obj);
    }
}

static void d_objc_autoreleasePoolPop(void *token) {
    struct pool *p = &tls_pool;
    size_t idx = (size_t)(uintptr_t)token;
    if (!idx || idx > p->count) return;
    pool_drain_to(p, idx - 1);
}
DX_FN(objc_autoreleasePoolPop);
DX_EXPORT("__objc_autoreleasePoolPop", d_objc_autoreleasePoolPop);

static void pool_thread_exit(void *arg) {
    struct pool *p = arg;
    pool_drain_to(p, 0);
    free(p->objs);
    p->objs = NULL;
    p->cap = 0;
}

static id d_objc_autorelease(id obj) {
    if (!obj || ((uintptr_t)obj & 1)) return obj;
    Class c = obj->isa;
    if (class_realized(c) && !default_rr(c)) return MSG(id, id, SEL)(obj, SEL_autorelease);
    struct pool *p = &tls_pool;
    if (!p->cap) pthread_setspecific(pool_key, p);
    /* with no pool in place the object waits for thread exit */
    pool_push_obj(p, obj);
    return obj;
}
DX_FN(objc_autorelease);
void *dx_objc_autorelease(void *obj) { return d_objc_autorelease(obj); }

id root_autorelease(id obj) {
    struct pool *p = &tls_pool;
    if (!p->cap) pthread_setspecific(pool_key, p);
    pool_push_obj(p, obj);
    return obj;
}

/* Return-value handshake. A method that returns an autoreleased object
 * tail-calls objc_autoreleaseReturnValue; if the code it will return to
 * immediately hands the value to objc_retainAutoreleasedReturnValue (or
 * objc_unsafeClaimAutoreleasedReturnValue), the object is passed at +1 and
 * never enters a pool. Programs observe this: without it objects live until
 * the next pool drain. The caller is recognised by its instructions:
 *   mov %rax,%rdi ; call <stub or *got> */
static id d_objc_retainAutoreleasedReturnValue(id obj);
static id d_objc_unsafeClaimAutoreleasedReturnValue(id obj);
static __thread int returned_plus_one;

static int caller_accepts_uncached(const uint8_t *ra);
/* The answer for a call site never changes (code doesn't), and the
 * image lookup is a walk over every image: remembered per return
 * address, in one word each (address << 1 | answer), so threads racing
 * on a slot see an old answer or a new one, never a torn one. */
static _Atomic uintptr_t accepts_cache[4096];
static int caller_accepts(const uint8_t *ra) {
    uintptr_t a = (uintptr_t)ra;
    _Atomic uintptr_t *slot = &accepts_cache[(a >> 2) & 4095];
    uintptr_t v = *slot;
    if (v >> 1 == a) return (int)(v & 1);
    int ok = caller_accepts_uncached(ra);
    *slot = a << 1 | (uintptr_t)ok;
    return ok;
}
static int caller_accepts_uncached(const uint8_t *ra) {
    if (!dx_image_for_address(ra, NULL, NULL)) return 0;
    if (ra[0] != 0x48 || ra[1] != 0x89 || ra[2] != 0xc7) return 0;
    const uint8_t *p = ra + 3;
    void *target = NULL;
    if (p[0] == 0xe8 || p[0] == 0xe9) { /* call/jmp rel32, to a stub: jmp *slot(%rip) */
        int32_t rel;
        memcpy(&rel, p + 1, 4);
        const uint8_t *stub = p + 5 + rel;
        if (!dx_image_for_address(stub, NULL, NULL) || stub[0] != 0xff || stub[1] != 0x25) return 0;
        memcpy(&rel, stub + 2, 4);
        target = *(void **)(stub + 6 + rel);
    } else if (p[0] == 0xff && (p[1] == 0x15 || p[1] == 0x25)) { /* call/jmp *slot(%rip) */
        int32_t rel;
        memcpy(&rel, p + 2, 4);
        target = *(void **)(p + 6 + rel);
    }
    return target == (void *)d_objc_retainAutoreleasedReturnValue ||
           target == (void *)d_objc_unsafeClaimAutoreleasedReturnValue;
}

__attribute__((noinline)) static id d_objc_autoreleaseReturnValue(id obj) {
    if (obj && caller_accepts(__builtin_return_address(0))) {
        returned_plus_one = 1;
        return obj;
    }
    return d_objc_autorelease(obj);
}
DX_FN(objc_autoreleaseReturnValue);
__attribute__((noinline)) static id d_objc_retainAutoreleaseReturnValue(id obj) {
    if (obj && caller_accepts(__builtin_return_address(0))) {
        returned_plus_one = 1;
        return d_objc_retain(obj);
    }
    return d_objc_autorelease(d_objc_retain(obj));
}
DX_FN(objc_retainAutoreleaseReturnValue);
static id d_objc_retainAutoreleasedReturnValue(id obj) {
    if (returned_plus_one) {
        returned_plus_one = 0;
        return obj;
    }
    return d_objc_retain(obj);
}
DX_FN(objc_retainAutoreleasedReturnValue);
static id d_objc_unsafeClaimAutoreleasedReturnValue(id obj) {
    if (returned_plus_one) {
        returned_plus_one = 0;
        d_objc_release(obj);
    }
    return obj;
}
DX_FN(objc_unsafeClaimAutoreleasedReturnValue);
static id d_objc_retainAutorelease(id obj) { return d_objc_autorelease(d_objc_retain(obj)); }
DX_FN(objc_retainAutorelease);
static void d_objc_storeStrong(id *location, id obj) {
    id old = *location;
    if (old == obj) return;
    d_objc_retain(obj);
    *location = obj;
    d_objc_release(old);
}
DX_FN(objc_storeStrong);
static id d_objc_retainBlock(id block) { return dx_block_copy(block); }
DX_FN(objc_retainBlock);

static id d_objc_alloc(Class cls) { return cls ? MSG(id, id, SEL)((id)cls, SEL_alloc) : NULL; }
DX_FN(objc_alloc);
static id d_objc_allocWithZone(Class cls) { return cls ? MSG(id, id, SEL, void *)((id)cls, SEL_allocWithZone, NULL) : NULL; }
DX_FN(objc_allocWithZone);
static id d_objc_alloc_init(Class cls) {
    id obj = d_objc_alloc(cls);
    return obj ? MSG(id, id, SEL)(obj, SEL_init) : NULL;
}
DX_FN(objc_alloc_init);
static id d_objc_opt_new(Class cls) { return cls ? MSG(id, id, SEL)((id)cls, SEL_new) : NULL; }
DX_FN(objc_opt_new);
static id d_objc_opt_self(id obj) { return obj ? MSG(id, id, SEL)(obj, SEL_self) : NULL; }
DX_FN(objc_opt_self);
static Class d_objc_opt_class(id obj) { return obj ? MSG(Class, id, SEL)(obj, SEL_class) : NULL; }
DX_FN(objc_opt_class);
static char d_objc_opt_isKindOfClass(id obj, Class cls) {
    return obj ? MSG(char, id, SEL, Class)(obj, SEL_isKindOfClass, cls) : 0;
}
DX_FN(objc_opt_isKindOfClass);
static char d_objc_opt_respondsToSelector(id obj, SEL sel) {
    return obj ? MSG(char, id, SEL, SEL)(obj, SEL_respondsToSelector, sel) : 0;
}
DX_FN(objc_opt_respondsToSelector);

/* ---- property helpers ------------------------------------------------------ */

#define PROP_LOCKS 64
static pthread_mutex_t prop_locks[PROP_LOCKS];
static pthread_mutex_t *prop_lock(void *slot) { return &prop_locks[((uintptr_t)slot >> 4) % PROP_LOCKS]; }

static id d_objc_getProperty(id self, SEL _cmd, ptrdiff_t offset, char atomic) {
    (void)_cmd;
    id *slot = (id *)((char *)self + offset);
    if (!atomic) return *slot;
    pthread_mutex_lock(prop_lock(slot));
    id value = d_objc_retain(*slot);
    pthread_mutex_unlock(prop_lock(slot));
    return d_objc_autorelease(value);
}
DX_FN(objc_getProperty);

static void set_property(id self, ptrdiff_t offset, id value, int atomic, int copy) {
    id *slot = (id *)((char *)self + offset);
    id keep;
    if (copy == 1) keep = value ? MSG(id, id, SEL, void *)(value, SEL_copyWithZone, NULL) : NULL;
    else if (copy == 2) keep = value ? MSG(id, id, SEL, void *)(value, SEL_mutableCopyWithZone, NULL) : NULL;
    else {
        if (*slot == value) return;
        keep = d_objc_retain(value);
    }
    id old;
    if (atomic) {
        pthread_mutex_lock(prop_lock(slot));
        old = *slot;
        *slot = keep;
        pthread_mutex_unlock(prop_lock(slot));
    } else {
        old = *slot;
        *slot = keep;
    }
    d_objc_release(old);
}
static void d_objc_setProperty(id self, SEL _cmd, ptrdiff_t offset, id value, char atomic, signed char copy) {
    (void)_cmd;
    set_property(self, offset, value, atomic, copy);
}
DX_FN(objc_setProperty);
static void d_objc_setProperty_atomic(id self, SEL _cmd, id value, ptrdiff_t offset) { (void)_cmd; set_property(self, offset, value, 1, 0); }
DX_FN(objc_setProperty_atomic);
static void d_objc_setProperty_nonatomic(id self, SEL _cmd, id value, ptrdiff_t offset) { (void)_cmd; set_property(self, offset, value, 0, 0); }
DX_FN(objc_setProperty_nonatomic);
static void d_objc_setProperty_atomic_copy(id self, SEL _cmd, id value, ptrdiff_t offset) { (void)_cmd; set_property(self, offset, value, 1, 1); }
DX_FN(objc_setProperty_atomic_copy);
static void d_objc_setProperty_nonatomic_copy(id self, SEL _cmd, id value, ptrdiff_t offset) { (void)_cmd; set_property(self, offset, value, 0, 1); }
DX_FN(objc_setProperty_nonatomic_copy);
static void d_objc_copyStruct(void *dest, const void *src, ptrdiff_t size, char atomic, char strong) {
    (void)strong;
    if (atomic) pthread_mutex_lock(prop_lock((void *)src));
    memmove(dest, src, (size_t)size);
    if (atomic) pthread_mutex_unlock(prop_lock((void *)src));
}
DX_FN(objc_copyStruct);

/* ---- @synchronized ---------------------------------------------------------- */

struct sync_node {
    struct sync_node *next;
    id obj;
    pthread_mutex_t lock;
    int users;
};
static struct sync_node *sync_nodes;
static pthread_mutex_t sync_table_lock = PTHREAD_MUTEX_INITIALIZER;

static int d_objc_sync_enter(id obj) {
    if (!obj) return 0;
    pthread_mutex_lock(&sync_table_lock);
    struct sync_node *n = sync_nodes, *spare = NULL;
    for (; n; n = n->next) {
        if (n->obj == obj) break;
        if (!n->users && !spare) spare = n;
    }
    if (!n) {
        n = spare;
        if (!n) {
            n = calloc(1, sizeof *n);
            pthread_mutexattr_t a;
            pthread_mutexattr_init(&a);
            pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
            pthread_mutex_init(&n->lock, &a);
            n->next = sync_nodes;
            sync_nodes = n;
        }
        n->obj = obj;
    }
    n->users++;
    pthread_mutex_unlock(&sync_table_lock);
    pthread_mutex_lock(&n->lock);
    return 0;
}
DX_FN(objc_sync_enter);
static int d_objc_sync_exit(id obj) {
    if (!obj) return 0;
    pthread_mutex_lock(&sync_table_lock);
    struct sync_node *n = sync_nodes;
    while (n && n->obj != obj) n = n->next;
    if (n) {
        pthread_mutex_unlock(&n->lock);
        if (!--n->users) n->obj = NULL;
    }
    pthread_mutex_unlock(&sync_table_lock);
    return n ? 0 : -1;
}
DX_FN(objc_sync_exit);

/* ---- exceptions and misc ---------------------------------------------------- */

static void d_objc_exception_throw(id exception) {
    dx_fatal("objc: uncaught Objective-C exception of class %s (exception unwinding is not implemented)",
             exception ? class_name(objc_class_of(exception)) : "nil");
}
DX_FN(objc_exception_throw);
DX_EXPORT("_objc_exception_rethrow", d_objc_exception_throw);
static void d_objc_terminate(void) { dx_fatal("objc_terminate called"); }
DX_FN(objc_terminate);
static void d_objc_enumerationMutation(id obj) {
    dx_fatal("objc: collection %p of class %s was mutated while being enumerated", (void *)obj,
             obj ? class_name(objc_class_of(obj)) : "nil");
}
DX_FN(objc_enumerationMutation);
static int objc_personality(void) { dx_fatal("objc: exception personality routine called (unwinding is not implemented)"); }
DX_EXPORT("___objc_personality_v0", objc_personality);
static id d_objc_begin_catch(void *exc) { (void)exc; dx_fatal("objc_begin_catch: exceptions are not implemented"); }
DX_FN(objc_begin_catch);
static void d_objc_end_catch(void) {}
DX_FN(objc_end_catch);

/* ---- NSObject ---------------------------------------------------------------- */

struct objc_class dx_NSObject_class, dx_NSObject_meta;
DX_EXPORT("_OBJC_CLASS_$_NSObject", &dx_NSObject_class);
DX_EXPORT("_OBJC_METACLASS_$_NSObject", &dx_NSObject_meta);
static int32_t nsobject_isa_offset = 0;
DX_EXPORT("_OBJC_IVAR_$_NSObject.isa", &nsobject_isa_offset);

static id ns_retain(id self, SEL _cmd) { (void)_cmd; return root_retain(self); }
static void ns_release(id self, SEL _cmd) { (void)_cmd; root_release(self); }
static id ns_autorelease(id self, SEL _cmd) { (void)_cmd; return root_autorelease(self); }
static unsigned long ns_retainCount(id self, SEL _cmd) { (void)_cmd; return root_retain_count(self); }
static void ns_dealloc(id self, SEL _cmd) { (void)_cmd; object_dispose_impl(self); }
static id ns_alloc(id self, SEL _cmd) { (void)_cmd; return class_create_instance((Class)self, 0); }
static id ns_allocWithZone(id self, SEL _cmd, void *zone) { (void)_cmd; (void)zone; return class_create_instance((Class)self, 0); }
static id ns_init(id self, SEL _cmd) { (void)_cmd; return self; }
static id ns_new(id self, SEL _cmd) {
    (void)_cmd;
    id obj = MSG(id, id, SEL)(self, SEL_alloc);
    return obj ? MSG(id, id, SEL)(obj, SEL_init) : NULL;
}
static id ns_self(id self, SEL _cmd) { (void)_cmd; return self; }
static Class ns_class(id self, SEL _cmd) { (void)_cmd; return objc_class_of(self); }
static Class ns_class_cls(id self, SEL _cmd) { (void)_cmd; return (Class)self; }
static Class ns_superclass(id self, SEL _cmd) { (void)_cmd; return objc_class_of(self)->superclass; }
static Class ns_superclass_cls(id self, SEL _cmd) { (void)_cmd; return ((Class)self)->superclass; }
static char ns_isKindOfClass(id self, SEL _cmd, Class cls) {
    (void)_cmd;
    for (Class c = objc_class_of(self); c; c = c->superclass)
        if (c == cls) return 1;
    return 0;
}
static char ns_isMemberOfClass(id self, SEL _cmd, Class cls) { (void)_cmd; return objc_class_of(self) == cls; }
static char ns_isSubclassOfClass(id self, SEL _cmd, Class cls) {
    (void)_cmd;
    for (Class c = (Class)self; c; c = c->superclass)
        if (c == cls) return 1;
    return 0;
}
static char ns_respondsToSelector(id self, SEL _cmd, SEL sel) {
    (void)_cmd;
    return sel && class_lookup_imp(objc_class_of(self), sel) != NULL;
}
static char ns_instancesRespondToSelector(id self, SEL _cmd, SEL sel) {
    (void)_cmd;
    return sel && class_lookup_imp((Class)self, sel) != NULL;
}
static char class_conforms(Class cls, void *proto) {
    char (*conforms)(Class, void *) = dx_registry_lookup("_class_conformsToProtocol");
    for (Class c = cls; c; c = c->superclass)
        if (conforms(c, proto)) return 1;
    return 0;
}
static char ns_conformsToProtocol(id self, SEL _cmd, void *proto) { (void)_cmd; return class_conforms(objc_class_of(self), proto); }
static char ns_conformsToProtocol_cls(id self, SEL _cmd, void *proto) { (void)_cmd; return class_conforms((Class)self, proto); }
static char ns_isEqual(id self, SEL _cmd, id other) { (void)_cmd; return self == other; }
static unsigned long ns_hash(id self, SEL _cmd) { (void)_cmd; return (unsigned long)(uintptr_t)self >> 4; }
static char ns_isProxy(id self, SEL _cmd) { (void)self; (void)_cmd; return 0; }
static void *ns_zone(id self, SEL _cmd) { (void)self; (void)_cmd; return NULL; }
static id ns_copy(id self, SEL _cmd) { (void)_cmd; return MSG(id, id, SEL, void *)(self, SEL_copyWithZone, NULL); }
static id ns_mutableCopy(id self, SEL _cmd) { (void)_cmd; return MSG(id, id, SEL, void *)(self, SEL_mutableCopyWithZone, NULL); }
static id ns_copyWithZone_cls(id self, SEL _cmd, void *z) { (void)_cmd; (void)z; return self; }
static id ns_performSelector(id self, SEL _cmd, SEL sel) { (void)_cmd; return MSG(id, id, SEL)(self, sel); }
static id ns_performSelector1(id self, SEL _cmd, SEL sel, id a) { (void)_cmd; return MSG(id, id, SEL, id)(self, sel, a); }
static id ns_performSelector2(id self, SEL _cmd, SEL sel, id a, id b) { (void)_cmd; return MSG(id, id, SEL, id, id)(self, sel, a, b); }
static IMP ns_methodForSelector(id self, SEL _cmd, SEL sel) { (void)_cmd; return class_lookup_imp(objc_class_of(self), sel); }
static IMP ns_instanceMethodForSelector(id self, SEL _cmd, SEL sel) { (void)_cmd; return class_lookup_imp((Class)self, sel); }
static void ns_nothing(id self, SEL _cmd) { (void)self; (void)_cmd; }
static char ns_no(id self, SEL _cmd, SEL sel) { (void)self; (void)_cmd; (void)sel; return 0; }
static id ns_nil1(id self, SEL _cmd, SEL sel) { (void)self; (void)_cmd; (void)sel; return NULL; }
static id ns_description(id self, SEL _cmd) { (void)self; (void)_cmd; return NULL; /* needs NSString: Foundation */ }
static void ns_doesNotRecognizeSelector(id self, SEL _cmd, SEL sel) {
    (void)_cmd;
    dx_fatal("objc: -[%s %s]: unrecognized selector sent to instance %p", class_name(objc_class_of(self)), sel,
             (void *)self);
}

/* Block classes: blocks are objects and answer the memory-management
 * messages by using the Blocks runtime. */
extern void *dx_NSConcreteStackBlock[32], *dx_NSConcreteMallocBlock[32], *dx_NSConcreteGlobalBlock[32];
extern void *(*dx_block_retain_object)(void *);
extern void (*dx_block_release_object)(void *);
static id block_retain(id self, SEL _cmd) { (void)_cmd; return dx_block_copy(self); }
static void block_release(id self, SEL _cmd) { (void)_cmd; dx_block_release(self); }
static id block_copy(id self, SEL _cmd) { (void)_cmd; return dx_block_copy(self); }
static id block_copyWithZone(id self, SEL _cmd, void *z) { (void)_cmd; (void)z; return dx_block_copy(self); }
static id block_autorelease(id self, SEL _cmd) { (void)_cmd; return root_autorelease(self); }
static void *block_retain_object(void *o) { return d_objc_retain(o); }
static void block_release_object(void *o) { d_objc_release(o); }

/* OS objects (dispatch, xpc): retain/release are provided by their library. */
static Class os_object_class;
static struct class_rw *os_rw(id self) {
    for (Class c = objc_class_of(self); c; c = c->superclass)
        if (RW(c)->os_retain) return RW(c);
    return NULL;
}
static id os_retain(id self, SEL _cmd) {
    (void)_cmd;
    struct class_rw *rw = os_rw(self);
    return rw ? rw->os_retain(self) : self;
}
static void os_release(id self, SEL _cmd) {
    (void)_cmd;
    struct class_rw *rw = os_rw(self);
    if (rw) rw->os_release(self);
}
static void os_dealloc(id self, SEL _cmd) { (void)self; (void)_cmd; }

void dx_objc_register_class(Class cls);

/* The same, building the class pair in storage the caller exports (as
 * _OBJC_CLASS_$_<name>), for OS object classes Swift code refers to by
 * symbol. Call once, early. */
void *dx_os_object_class_in(void *storage, void *meta_storage, const char *name, void *(*retain)(void *),
                            void (*release)(void *)) {
    Class c = make_class((Class)storage, (Class)meta_storage, os_object_class, name, 0);
    dx_objc_register_class(c);
    RW(c)->os_retain = retain;
    RW(c)->os_release = release;
    return c;
}

/* As dx_os_object_class_in, under a named superclass (which must exist).
 * For the dispatch classes Swift refers to by symbol (src/frameworks/
 * dispatch/swift_classes.c), whose hierarchy is OS_dispatch_object ->
 * OS_dispatch_queue... */
void *dx_os_object_class_in_super(void *storage, void *meta_storage, const char *name,
                                  const char *super_name, void *(*retain)(void *),
                                  void (*release)(void *)) {
    Class super = super_name ? (Class)dx_objc_lookup_class(super_name) : NULL;
    Class c = make_class((Class)storage, (Class)meta_storage, super ? super : os_object_class, name, 0);
    dx_objc_register_class(c);
    RW(c)->os_retain = retain;
    RW(c)->os_release = release;
    return c;
}

void *dx_os_object_class(const char *name, const char *super_name, void *(*retain)(void *),
                         void (*release)(void *)) {
    Class c = (Class)dx_objc_lookup_class(name);
    if (!c) {
        Class super = super_name ? (Class)dx_objc_lookup_class(super_name) : NULL;
        if (super_name && !super) super = dx_os_object_class(super_name, NULL, retain, release);
        c = make_class(NULL, NULL, super ? super : os_object_class, name, 0);
        dx_objc_register_class(c);
    }
    if (retain && !RW(c)->os_retain) {
        RW(c)->os_retain = retain;
        RW(c)->os_release = release;
    }
    return c;
}

void dx_objc_arc_init(void) {
    for (int i = 0; i < PROP_LOCKS; i++) pthread_mutex_init(&prop_locks[i], NULL);
    pthread_key_create(&pool_key, pool_thread_exit);

    Class ns = make_class(&dx_NSObject_class, &dx_NSObject_meta, NULL, "NSObject", 0);
    Class meta = ns->isa;
#define I(sel, fn, types) add_method(ns, sel, (IMP)fn, types)
#define C(sel, fn, types) add_method(meta, sel, (IMP)fn, types)
    I("retain", ns_retain, "@16@0:8");
    I("release", ns_release, "Vv16@0:8");
    I("autorelease", ns_autorelease, "@16@0:8");
    I("retainCount", ns_retainCount, "Q16@0:8");
    I("dealloc", ns_dealloc, "v16@0:8");
    I("init", ns_init, "@16@0:8");
    I("self", ns_self, "@16@0:8");
    I("class", ns_class, "#16@0:8");
    I("superclass", ns_superclass, "#16@0:8");
    I("isKindOfClass:", ns_isKindOfClass, "c24@0:8#16");
    I("isMemberOfClass:", ns_isMemberOfClass, "c24@0:8#16");
    I("respondsToSelector:", ns_respondsToSelector, "c24@0:8:16");
    I("conformsToProtocol:", ns_conformsToProtocol, "c24@0:8@16");
    I("isEqual:", ns_isEqual, "c24@0:8@16");
    I("hash", ns_hash, "Q16@0:8");
    I("isProxy", ns_isProxy, "c16@0:8");
    I("zone", ns_zone, "^v16@0:8");
    I("copy", ns_copy, "@16@0:8");
    I("mutableCopy", ns_mutableCopy, "@16@0:8");
    I("performSelector:", ns_performSelector, "@24@0:8:16");
    I("performSelector:withObject:", ns_performSelector1, "@32@0:8:16@24");
    I("performSelector:withObject:withObject:", ns_performSelector2, "@40@0:8:16@24@32");
    I("methodForSelector:", ns_methodForSelector, "^?24@0:8:16");
    I("doesNotRecognizeSelector:", ns_doesNotRecognizeSelector, "v24@0:8:16");
    I("forwardingTargetForSelector:", ns_nil1, "@24@0:8:16");
    I("description", ns_description, "@16@0:8");
    I("debugDescription", ns_description, "@16@0:8");
    I("finalize", ns_nothing, "v16@0:8");
    C("alloc", ns_alloc, "@16@0:8");
    C("allocWithZone:", ns_allocWithZone, "@24@0:8^v16");
    C("new", ns_new, "@16@0:8");
    C("load", ns_nothing, "v16@0:8");
    C("initialize", ns_nothing, "v16@0:8");
    C("self", ns_self, "@16@0:8");
    C("class", ns_class_cls, "#16@0:8");
    C("superclass", ns_superclass_cls, "#16@0:8");
    C("isSubclassOfClass:", ns_isSubclassOfClass, "c24@0:8#16");
    C("isKindOfClass:", ns_isKindOfClass, "c24@0:8#16");
    C("respondsToSelector:", ns_respondsToSelector, "c24@0:8:16");
    C("instancesRespondToSelector:", ns_instancesRespondToSelector, "c24@0:8:16");
    C("instanceMethodForSelector:", ns_instanceMethodForSelector, "^?24@0:8:16");
    C("conformsToProtocol:", ns_conformsToProtocol_cls, "c24@0:8@16");
    C("resolveInstanceMethod:", ns_no, "c24@0:8:16");
    C("resolveClassMethod:", ns_no, "c24@0:8:16");
    C("retain", ns_self, "@16@0:8");
    C("release", ns_nothing, "Vv16@0:8");
    C("autorelease", ns_self, "@16@0:8");
    C("copy", ns_self, "@16@0:8");
    C("copyWithZone:", ns_copyWithZone_cls, "@24@0:8^v16");
    C("isEqual:", ns_isEqual, "c24@0:8@16");
    C("hash", ns_hash, "Q16@0:8");
    C("description", ns_description, "@16@0:8");
#undef I
#undef C
    dx_objc_register_class(ns);

    Class nsblock = make_class(NULL, NULL, ns, "NSBlock", 0);
    add_method(nsblock, "retain", (IMP)block_retain, "@16@0:8");
    add_method(nsblock, "release", (IMP)block_release, "Vv16@0:8");
    add_method(nsblock, "autorelease", (IMP)block_autorelease, "@16@0:8");
    add_method(nsblock, "copy", (IMP)block_copy, "@16@0:8");
    add_method(nsblock, "copyWithZone:", (IMP)block_copyWithZone, "@24@0:8^v16");
    dx_objc_register_class(nsblock);
    static struct objc_class stack_meta, malloc_meta, global_meta;
    dx_objc_register_class(make_class((Class)dx_NSConcreteStackBlock, &stack_meta, nsblock, "__NSStackBlock__", 0));
    dx_objc_register_class(make_class((Class)dx_NSConcreteMallocBlock, &malloc_meta, nsblock, "__NSMallocBlock__", 0));
    dx_objc_register_class(make_class((Class)dx_NSConcreteGlobalBlock, &global_meta, nsblock, "__NSGlobalBlock__", 0));
    dx_block_retain_object = block_retain_object;
    dx_block_release_object = block_release_object;

    os_object_class = make_class(NULL, NULL, ns, "OS_object", 0);
    add_method(os_object_class, "retain", (IMP)os_retain, "@16@0:8");
    add_method(os_object_class, "release", (IMP)os_release, "Vv16@0:8");
    add_method(os_object_class, "dealloc", (IMP)os_dealloc, "v16@0:8");
    dx_objc_register_class(os_object_class);
}

/* Cleanup landing pads end by resuming an unwind. Nothing can start one
 * until exception unwinding over Mach-O unwind tables exists. */
static void d__Unwind_Resume(void *exception) {
    (void)exception;
    dx_fatal("_Unwind_Resume called: exception unwinding is not implemented");
}
DX_FN(_Unwind_Resume);

/* os_retain/os_release: libSystem's retain and release for OS objects
 * (dispatch and XPC objects, os_log handles), which are Objective-C
 * objects here. */
static void *d_os_retain(void *o) { return o ? d_objc_retain(o) : o; }
DX_FN(os_retain);
static void d_os_release(void *o) {
    if (o) d_objc_release(o);
}
DX_FN(os_release);
/* Vouchers (activity and importance tokens passed with IPC) are never made
 * here, so there is never a previous one to hand back. */
static void *d_voucher_adopt(void *voucher) {
    (void)voucher;
    return NULL;
}
DX_FN(voucher_adopt);
