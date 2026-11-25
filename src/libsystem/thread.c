/* Darwin pthreads on top of host pthreads.
 *
 * Darwin's pthread objects are larger than glibc's and start with a
 * signature word that static initialisers set, so each wrapper keeps the
 * signature and stores the host object behind it. */
#define _GNU_SOURCE
#include <asm/prctl.h>
#include <errno.h>
#include <linux/futex.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include "dx.h"

/* ---- thread blocks ---------------------------------------------------- */

static __thread struct dx_thread *self_block;
static pthread_key_t cleanup_key;
static pthread_once_t cleanup_once = PTHREAD_ONCE_INIT;
static void (*destructors[DX_TSD_SLOTS])(void *);
static unsigned char key_used[DX_TSD_SLOTS];
static pthread_mutex_t key_lock = PTHREAD_MUTEX_INITIALIZER;
static struct dx_thread *main_thread;
int dx_rawsys_enable_thread(void);

void dx_thread_run_destructors(struct dx_thread *t) {
    for (int round = 0; round < 4; round++) {
        int again = 0;
        for (int k = DX_TSD_FIRST_DYNAMIC; k < DX_TSD_SLOTS; k++) {
            void *v = t->tsd[k];
            void (*d)(void *) = destructors[k];
            if (v && d) {
                t->tsd[k] = NULL;
                d(v);
                again = 1;
            }
        }
        if (!again) break;
    }
}

static void thread_cleanup(void *arg) {
    struct dx_thread *t = arg;
    dx_thread_run_destructors(t);
    if (t->detached && t != main_thread) {
        self_block = NULL;
        free(t);
    }
}

static void cleanup_init(void) { pthread_key_create(&cleanup_key, thread_cleanup); }

static void install(struct dx_thread *t) {
    t->tsd[0] = t;
    t->tsd[1] = &t->d_errno;
    t->host = (unsigned long)pthread_self();
    t->tid = (uint64_t)syscall(SYS_gettid);
    pthread_attr_t a;
    if (pthread_getattr_np(pthread_self(), &a) == 0) {
        void *addr;
        size_t size;
        if (pthread_attr_getstack(&a, &addr, &size) == 0) {
            t->stack_hi = (char *)addr + size;
            t->stack_size = size;
        }
        pthread_attr_destroy(&a);
    }
    if (syscall(SYS_arch_prctl, ARCH_SET_GS, (unsigned long)t) != 0)
        dx_fatal("arch_prctl(ARCH_SET_GS) failed: %s", strerror(errno));
    self_block = t;
    if (t != main_thread) dx_rawsys_enable_thread();
    pthread_once(&cleanup_once, cleanup_init);
    pthread_setspecific(cleanup_key, t);
}

struct dx_thread *dx_thread_attach(void) {
    if (self_block) return self_block;
    struct dx_thread *t = calloc(1, sizeof *t);
    t->detached = 1;
    if (!main_thread) main_thread = t;
    install(t);
    return t;
}

struct dx_thread *dx_thread_self(void) {
    struct dx_thread *t = self_block;
    return t ? t : dx_thread_attach();
}

unsigned long dx_tsd_key_alloc(void (*destructor)(void *)) {
    pthread_mutex_lock(&key_lock);
    for (int k = DX_TSD_FIRST_DYNAMIC; k < DX_TSD_SLOTS; k++) {
        if (!key_used[k]) {
            key_used[k] = 1;
            destructors[k] = destructor;
            pthread_mutex_unlock(&key_lock);
            return k;
        }
    }
    pthread_mutex_unlock(&key_lock);
    return 0;
}

static int d_pthread_key_create(unsigned long *key, void (*destructor)(void *)) {
    unsigned long k = dx_tsd_key_alloc(destructor);
    if (!k) return 35; /* EAGAIN */
    *key = k;
    return 0;
}
DX_FN(pthread_key_create);

static int d_pthread_key_delete(unsigned long key) {
    if (key < DX_TSD_FIRST_DYNAMIC || key >= DX_TSD_SLOTS) return 22;
    pthread_mutex_lock(&key_lock);
    key_used[key] = 0;
    destructors[key] = NULL;
    pthread_mutex_unlock(&key_lock);
    return 0;
}
DX_FN(pthread_key_delete);

static int d_pthread_setspecific(unsigned long key, const void *value) {
    if (key >= DX_TSD_SLOTS) return 22;
    dx_thread_self()->tsd[key] = (void *)value;
    return 0;
}
DX_FN(pthread_setspecific);

static void *d_pthread_getspecific(unsigned long key) {
    if (key >= DX_TSD_SLOTS) return NULL;
    return dx_thread_self()->tsd[key];
}
DX_FN(pthread_getspecific);

/* ---- attributes ------------------------------------------------------- */

#define SIG_ATTR 0x54484441L /* 'THDA' */
struct d_attr {
    long sig;
    pthread_attr_t host;
};
_Static_assert(sizeof(struct d_attr) <= 64, "pthread_attr_t must fit Darwin's 64 bytes");

static int d_pthread_attr_init(struct d_attr *a) {
    a->sig = SIG_ATTR;
    return dx_errno_to_darwin(pthread_attr_init(&a->host));
}
DX_FN(pthread_attr_init);
static int d_pthread_attr_destroy(struct d_attr *a) {
    a->sig = 0;
    return dx_errno_to_darwin(pthread_attr_destroy(&a->host));
}
DX_FN(pthread_attr_destroy);
static int d_pthread_attr_getstacksize(struct d_attr *a, size_t *size) {
    return dx_errno_to_darwin(pthread_attr_getstacksize(&a->host, size));
}
DX_FN(pthread_attr_getstacksize);
static int d_pthread_attr_setstacksize(struct d_attr *a, size_t size) {
    if (size < 256 * 1024) size = 256 * 1024; /* host libc needs more stack than Darwin's */
    return dx_errno_to_darwin(pthread_attr_setstacksize(&a->host, size));
}
DX_FN(pthread_attr_setstacksize);
static int d_pthread_attr_setdetachstate(struct d_attr *a, int state) {
    /* Darwin: JOINABLE 1, DETACHED 2 */
    return dx_errno_to_darwin(pthread_attr_setdetachstate(
        &a->host, state == 2 ? PTHREAD_CREATE_DETACHED : PTHREAD_CREATE_JOINABLE));
}
DX_FN(pthread_attr_setdetachstate);
static int d_pthread_attr_getdetachstate(struct d_attr *a, int *state) {
    int s;
    int r = pthread_attr_getdetachstate(&a->host, &s);
    if (!r) *state = s == PTHREAD_CREATE_DETACHED ? 2 : 1;
    return dx_errno_to_darwin(r);
}
DX_FN(pthread_attr_getdetachstate);
static int d_pthread_attr_setscope(struct d_attr *a, int scope) { (void)a; (void)scope; return 0; }
DX_FN(pthread_attr_setscope);
static int d_pthread_attr_setguardsize(struct d_attr *a, size_t n) {
    return dx_errno_to_darwin(pthread_attr_setguardsize(&a->host, n));
}
DX_FN(pthread_attr_setguardsize);
static int d_pthread_attr_set_qos_class_np(struct d_attr *a, int qos, int rel) { (void)a; (void)qos; (void)rel; return 0; }
DX_FN(pthread_attr_set_qos_class_np);
static int d_pthread_set_qos_class_self_np(int qos, int rel) { (void)qos; (void)rel; return 0; }
DX_FN(pthread_set_qos_class_self_np);

/* ---- create / join ---------------------------------------------------- */

static void *trampoline(void *arg) {
    struct dx_thread *t = arg;
    install(t);
    t->result = t->start(t->arg);
    return t->result;
}

static int d_pthread_create(struct dx_thread **out, struct d_attr *attr, void *(*start)(void *),
                            void *arg) {
    struct dx_thread *t = calloc(1, sizeof *t);
    if (!t) return 12;
    t->start = start;
    t->arg = arg;
    pthread_attr_t *ha = NULL;
    if (attr && attr->sig == SIG_ATTR) {
        ha = &attr->host;
        int ds;
        if (!pthread_attr_getdetachstate(ha, &ds)) t->detached = ds == PTHREAD_CREATE_DETACHED;
    }
    /* Publish the handle before the thread can run so callers that read
     * *out from the new thread see it. glibc stores the host id through the
     * pointer before the thread starts, so join/kill on a thread that has
     * not run yet still find it. */
    if (out) *out = t;
    _Static_assert(sizeof(pthread_t) == sizeof t->host, "pthread_t size");
    int r = pthread_create((pthread_t *)&t->host, ha, trampoline, t);
    if (r) {
        free(t);
        return dx_errno_to_darwin(r);
    }
    return 0;
}
DX_FN(pthread_create);

static int d_pthread_join(struct dx_thread *t, void **result) {
    if (!t) return 3;
    int r = pthread_join((pthread_t)t->host, result);
    if (!r) free(t);
    return dx_errno_to_darwin(r);
}
DX_FN(pthread_join);

static int d_pthread_detach(struct dx_thread *t) {
    if (!t) return 3;
    t->detached = 1;
    return dx_errno_to_darwin(pthread_detach((pthread_t)t->host));
}
DX_FN(pthread_detach);

static struct dx_thread *d_pthread_self(void) { return dx_thread_self(); }
DX_FN(pthread_self);
static int d_pthread_equal(struct dx_thread *a, struct dx_thread *b) { return a == b; }
DX_FN(pthread_equal);
static void d_pthread_exit(void *v) {
    dx_thread_self()->result = v;
    pthread_exit(v);
}
DX_FN(pthread_exit);
static int d_pthread_main_np(void) { return dx_thread_self() == main_thread; }
DX_FN(pthread_main_np);
static void *d_pthread_get_stackaddr_np(struct dx_thread *t) { return t ? t->stack_hi : NULL; }
DX_FN(pthread_get_stackaddr_np);
static size_t d_pthread_get_stacksize_np(struct dx_thread *t) { return t ? t->stack_size : 0; }
DX_FN(pthread_get_stacksize_np);
static int d_pthread_threadid_np(struct dx_thread *t, uint64_t *id) {
    if (!t) t = dx_thread_self();
    *id = t->tid;
    return 0;
}
DX_FN(pthread_threadid_np);
static unsigned d_pthread_mach_thread_np(struct dx_thread *t) { return t ? (unsigned)t->tid : 0; }
DX_FN(pthread_mach_thread_np);
static unsigned d_mach_thread_self(void) { return (unsigned)dx_thread_self()->tid; }
DX_FN(mach_thread_self);
static int d_pthread_setname_np(const char *name) {
    char buf[16];
    strncpy(buf, name ? name : "", sizeof buf - 1);
    buf[15] = 0;
    pthread_setname_np(pthread_self(), buf);
    return 0;
}
DX_FN(pthread_setname_np);
static int d_pthread_getname_np(struct dx_thread *t, char *buf, size_t len) {
    if (!t) return 3;
    return dx_errno_to_darwin(pthread_getname_np((pthread_t)t->host, buf, len));
}
DX_FN(pthread_getname_np);
static int d_pthread_kill(struct dx_thread *t, int sig) {
    if (!t) return 3;
    return dx_errno_to_darwin(pthread_kill((pthread_t)t->host, dx_sig_to_host(sig)));
}
DX_FN(pthread_kill);
static void d_pthread_yield_np(void) { sched_yield(); }
DX_FN(pthread_yield_np);
DX_PASS(sched_yield);
static int d_pthread_is_threaded_np(void) { return 1; }
DX_FN(pthread_is_threaded_np);

/* ---- mutex ------------------------------------------------------------ */

#define SIG_MUTEX 0x4d555458L /* 'MUTX' */
#define D_MUTEX_SIG_ERRORCHECK 0x32AAABA1L
#define D_MUTEX_SIG_RECURSIVE 0x32AAABA2L
struct d_mutex {
    long sig;
    pthread_mutex_t host;
};
_Static_assert(sizeof(struct d_mutex) <= 64, "pthread_mutex_t must fit Darwin's 64 bytes");

#define SIG_MATTR 0x4d415454L
struct d_mutexattr {
    long sig;
    pthread_mutexattr_t host;
};
_Static_assert(sizeof(struct d_mutexattr) <= 16, "mutexattr");

static pthread_mutex_t lazy_lock = PTHREAD_MUTEX_INITIALIZER;

static int host_mutex_type(int d) {
    switch (d) {
    case 1: return PTHREAD_MUTEX_ERRORCHECK;
    case 2: return PTHREAD_MUTEX_RECURSIVE;
    default: return PTHREAD_MUTEX_NORMAL;
    }
}

static void mutex_lazy(struct d_mutex *m) {
    pthread_mutex_lock(&lazy_lock);
    if (m->sig != SIG_MUTEX) {
        pthread_mutexattr_t a;
        pthread_mutexattr_init(&a);
        if (m->sig == D_MUTEX_SIG_RECURSIVE) pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
        else if (m->sig == D_MUTEX_SIG_ERRORCHECK) pthread_mutexattr_settype(&a, PTHREAD_MUTEX_ERRORCHECK);
        pthread_mutex_init(&m->host, &a);
        pthread_mutexattr_destroy(&a);
        __atomic_store_n(&m->sig, SIG_MUTEX, __ATOMIC_RELEASE);
    }
    pthread_mutex_unlock(&lazy_lock);
}
#define MUTEX(m) do { if (__atomic_load_n(&(m)->sig, __ATOMIC_ACQUIRE) != SIG_MUTEX) mutex_lazy(m); } while (0)

static int d_pthread_mutex_init(struct d_mutex *m, struct d_mutexattr *a) {
    int r = pthread_mutex_init(&m->host, (a && a->sig == SIG_MATTR) ? &a->host : NULL);
    m->sig = SIG_MUTEX;
    return dx_errno_to_darwin(r);
}
DX_FN(pthread_mutex_init);
static int d_pthread_mutex_destroy(struct d_mutex *m) {
    if (m->sig != SIG_MUTEX) return 0;
    m->sig = 0;
    pthread_mutex_destroy(&m->host);
    return 0;
}
DX_FN(pthread_mutex_destroy);
static int d_pthread_mutex_lock(struct d_mutex *m) {
    MUTEX(m);
    return dx_errno_to_darwin(pthread_mutex_lock(&m->host));
}
DX_FN(pthread_mutex_lock);
static int d_pthread_mutex_trylock(struct d_mutex *m) {
    MUTEX(m);
    return dx_errno_to_darwin(pthread_mutex_trylock(&m->host));
}
DX_FN(pthread_mutex_trylock);
static int d_pthread_mutex_unlock(struct d_mutex *m) {
    MUTEX(m);
    return dx_errno_to_darwin(pthread_mutex_unlock(&m->host));
}
DX_FN(pthread_mutex_unlock);

static int d_pthread_mutexattr_init(struct d_mutexattr *a) {
    a->sig = SIG_MATTR;
    return dx_errno_to_darwin(pthread_mutexattr_init(&a->host));
}
DX_FN(pthread_mutexattr_init);
static int d_pthread_mutexattr_destroy(struct d_mutexattr *a) {
    a->sig = 0;
    return dx_errno_to_darwin(pthread_mutexattr_destroy(&a->host));
}
DX_FN(pthread_mutexattr_destroy);
static int d_pthread_mutexattr_settype(struct d_mutexattr *a, int type) {
    return dx_errno_to_darwin(pthread_mutexattr_settype(&a->host, host_mutex_type(type)));
}
DX_FN(pthread_mutexattr_settype);
static int d_pthread_mutexattr_setpshared(struct d_mutexattr *a, int v) { (void)a; (void)v; return 0; }
DX_FN(pthread_mutexattr_setpshared);

/* ---- condition variables --------------------------------------------- */

#define SIG_COND 0x434f4e44L /* 'COND' */
struct d_cond {
    long sig;
    pthread_cond_t *host;
};
_Static_assert(sizeof(struct d_cond) <= 48, "pthread_cond_t must fit Darwin's 48 bytes");

static void cond_lazy(struct d_cond *c) {
    pthread_mutex_lock(&lazy_lock);
    if (c->sig != SIG_COND) {
        pthread_cond_t *h = malloc(sizeof *h);
        pthread_cond_init(h, NULL);
        c->host = h;
        __atomic_store_n(&c->sig, SIG_COND, __ATOMIC_RELEASE);
    }
    pthread_mutex_unlock(&lazy_lock);
}
#define COND(c) do { if (__atomic_load_n(&(c)->sig, __ATOMIC_ACQUIRE) != SIG_COND) cond_lazy(c); } while (0)

static int d_pthread_cond_init(struct d_cond *c, void *attr) {
    (void)attr;
    c->sig = 0;
    cond_lazy(c);
    return 0;
}
DX_FN(pthread_cond_init);
static int d_pthread_cond_destroy(struct d_cond *c) {
    if (c->sig == SIG_COND) {
        c->sig = 0;
        pthread_cond_destroy(c->host);
        free(c->host);
        c->host = NULL;
    }
    return 0;
}
DX_FN(pthread_cond_destroy);
static int d_pthread_cond_signal(struct d_cond *c) {
    COND(c);
    return dx_errno_to_darwin(pthread_cond_signal(c->host));
}
DX_FN(pthread_cond_signal);
static int d_pthread_cond_broadcast(struct d_cond *c) {
    COND(c);
    return dx_errno_to_darwin(pthread_cond_broadcast(c->host));
}
DX_FN(pthread_cond_broadcast);
static int d_pthread_cond_wait(struct d_cond *c, struct d_mutex *m) {
    COND(c);
    MUTEX(m);
    return dx_errno_to_darwin(pthread_cond_wait(c->host, &m->host));
}
DX_FN(pthread_cond_wait);
static int d_pthread_cond_timedwait(struct d_cond *c, struct d_mutex *m, const struct timespec *abs) {
    COND(c);
    MUTEX(m);
    return dx_errno_to_darwin(pthread_cond_timedwait(c->host, &m->host, abs));
}
DX_FN(pthread_cond_timedwait);
static int d_pthread_cond_timedwait_relative_np(struct d_cond *c, struct d_mutex *m,
                                                const struct timespec *rel) {
    COND(c);
    MUTEX(m);
    if (!rel) return dx_errno_to_darwin(pthread_cond_wait(c->host, &m->host));
    struct timespec abs;
    clock_gettime(CLOCK_REALTIME, &abs);
    abs.tv_sec += rel->tv_sec;
    abs.tv_nsec += rel->tv_nsec;
    if (abs.tv_nsec >= 1000000000L) {
        abs.tv_sec++;
        abs.tv_nsec -= 1000000000L;
    }
    return dx_errno_to_darwin(pthread_cond_timedwait(c->host, &m->host, &abs));
}
DX_FN(pthread_cond_timedwait_relative_np);
static int d_pthread_condattr_init(void *a) { memset(a, 0, 16); return 0; }
DX_FN(pthread_condattr_init);
static int d_pthread_condattr_destroy(void *a) { (void)a; return 0; }
DX_FN(pthread_condattr_destroy);

/* ---- rwlock / once ---------------------------------------------------- */

#define SIG_RWLOCK 0x52574c4bL
struct d_rwlock {
    long sig;
    pthread_rwlock_t host;
};
_Static_assert(sizeof(struct d_rwlock) <= 200, "rwlock");

static void rwlock_lazy(struct d_rwlock *l) {
    pthread_mutex_lock(&lazy_lock);
    if (l->sig != SIG_RWLOCK) {
        pthread_rwlock_init(&l->host, NULL);
        __atomic_store_n(&l->sig, SIG_RWLOCK, __ATOMIC_RELEASE);
    }
    pthread_mutex_unlock(&lazy_lock);
}
#define RWLOCK(l) do { if (__atomic_load_n(&(l)->sig, __ATOMIC_ACQUIRE) != SIG_RWLOCK) rwlock_lazy(l); } while (0)

static int d_pthread_rwlock_init(struct d_rwlock *l, void *a) { (void)a; l->sig = 0; rwlock_lazy(l); return 0; }
DX_FN(pthread_rwlock_init);
static int d_pthread_rwlock_destroy(struct d_rwlock *l) {
    if (l->sig == SIG_RWLOCK) { l->sig = 0; pthread_rwlock_destroy(&l->host); }
    return 0;
}
DX_FN(pthread_rwlock_destroy);
static int d_pthread_rwlock_rdlock(struct d_rwlock *l) { RWLOCK(l); return dx_errno_to_darwin(pthread_rwlock_rdlock(&l->host)); }
DX_FN(pthread_rwlock_rdlock);
static int d_pthread_rwlock_wrlock(struct d_rwlock *l) { RWLOCK(l); return dx_errno_to_darwin(pthread_rwlock_wrlock(&l->host)); }
DX_FN(pthread_rwlock_wrlock);
static int d_pthread_rwlock_tryrdlock(struct d_rwlock *l) { RWLOCK(l); return dx_errno_to_darwin(pthread_rwlock_tryrdlock(&l->host)); }
DX_FN(pthread_rwlock_tryrdlock);
static int d_pthread_rwlock_trywrlock(struct d_rwlock *l) { RWLOCK(l); return dx_errno_to_darwin(pthread_rwlock_trywrlock(&l->host)); }
DX_FN(pthread_rwlock_trywrlock);
static int d_pthread_rwlock_unlock(struct d_rwlock *l) { RWLOCK(l); return dx_errno_to_darwin(pthread_rwlock_unlock(&l->host)); }
DX_FN(pthread_rwlock_unlock);

struct d_once {
    long sig;
    long state; /* 0 = not run, 1 = running, 2 = done */
};
static pthread_mutex_t once_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t once_cond = PTHREAD_COND_INITIALIZER;

static int d_pthread_once(struct d_once *o, void (*fn)(void)) {
    if (__atomic_load_n(&o->state, __ATOMIC_ACQUIRE) == 2) return 0;
    pthread_mutex_lock(&once_lock);
    while (o->state == 1) pthread_cond_wait(&once_cond, &once_lock);
    if (o->state == 0) {
        o->state = 1;
        pthread_mutex_unlock(&once_lock);
        fn();
        pthread_mutex_lock(&once_lock);
        __atomic_store_n(&o->state, 2, __ATOMIC_RELEASE);
        pthread_cond_broadcast(&once_cond);
    }
    pthread_mutex_unlock(&once_lock);
    return 0;
}
DX_FN(pthread_once);

/* ---- ulock (futex-style waits used by the Go runtime and libc++) ------ */

#define UL_OPCODE_MASK 0xff
#define UL_COMPARE_AND_WAIT 1
#define UL_UNFAIR_LOCK 2
#define UL_COMPARE_AND_WAIT_SHARED 3
#define ULF_WAKE_ALL 0x100
#define ULF_NO_ERRNO 0x01000000

static int ulock_result(uint32_t op, long r) {
    if (r >= 0) return (int)r;
    int e = dx_errno_to_darwin(errno);
    if (op & ULF_NO_ERRNO) return -e;
    dx_set_errno(e);
    return -1;
}

static int d___ulock_wait(uint32_t op, void *addr, uint64_t value, uint32_t timeout_us) {
    struct timespec ts, *tp = NULL;
    if (timeout_us) {
        ts.tv_sec = timeout_us / 1000000;
        ts.tv_nsec = (long)(timeout_us % 1000000) * 1000;
        tp = &ts;
    }
    long r = syscall(SYS_futex, addr, FUTEX_WAIT, (uint32_t)value, tp, NULL, 0);
    if (r < 0 && errno == EAGAIN) return 0; /* value already changed: not an error on Darwin */
    return ulock_result(op, r);
}
DX_FN(__ulock_wait);

static int d___ulock_wait2(uint32_t op, void *addr, uint64_t value, uint64_t timeout_ns, uint64_t v2) {
    (void)v2;
    struct timespec ts, *tp = NULL;
    if (timeout_ns) {
        ts.tv_sec = timeout_ns / 1000000000ULL;
        ts.tv_nsec = timeout_ns % 1000000000ULL;
        tp = &ts;
    }
    long r = syscall(SYS_futex, addr, FUTEX_WAIT, (uint32_t)value, tp, NULL, 0);
    if (r < 0 && errno == EAGAIN) return 0;
    return ulock_result(op, r);
}
DX_FN(__ulock_wait2);

static int d___ulock_wake(uint32_t op, void *addr, uint64_t wake_value) {
    (void)wake_value;
    long r = syscall(SYS_futex, addr, FUTEX_WAKE, (op & ULF_WAKE_ALL) ? INT32_MAX : 1, NULL, NULL, 0);
    if (r == 0) {
        /* Darwin reports ENOENT when nobody was waiting. */
        if (op & ULF_NO_ERRNO) return -2;
        dx_set_errno(2);
        return -1;
    }
    return ulock_result(op, r > 0 ? 0 : r);
}
DX_FN(__ulock_wake);

/* os_unfair_lock: a 32-bit word; implemented as a simple futex lock. */
static void d_os_unfair_lock_lock(uint32_t *l) {
    uint32_t z = 0;
    if (__atomic_compare_exchange_n(l, &z, 1, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED)) return;
    for (;;) {
        uint32_t c = __atomic_exchange_n(l, 2, __ATOMIC_ACQUIRE);
        if (c == 0) return;
        syscall(SYS_futex, l, FUTEX_WAIT, 2, NULL, NULL, 0);
    }
}
DX_FN(os_unfair_lock_lock);
static int d_os_unfair_lock_trylock(uint32_t *l) {
    uint32_t z = 0;
    return __atomic_compare_exchange_n(l, &z, 1, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED);
}
DX_FN(os_unfair_lock_trylock);
static void d_os_unfair_lock_unlock(uint32_t *l) {
    if (__atomic_exchange_n(l, 0, __ATOMIC_RELEASE) == 2)
        syscall(SYS_futex, l, FUTEX_WAKE, 1, NULL, NULL, 0);
}
DX_FN(os_unfair_lock_unlock);
/* Ownership isn't recorded (the word holds 0/1/2), so the assertions only
 * check what they can: that the lock is held at all. */
static void d_os_unfair_lock_assert_owner(const uint32_t *l) {
    if (!__atomic_load_n(l, __ATOMIC_RELAXED)) dx_fatal("os_unfair_lock_assert_owner: lock is not held");
}
DX_FN(os_unfair_lock_assert_owner);
static void d_os_unfair_lock_assert_not_owner(const uint32_t *l) { (void)l; }
DX_FN(os_unfair_lock_assert_not_owner);
