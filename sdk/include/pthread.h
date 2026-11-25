/* bitten SDK: <pthread.h>. The object types are in <sys/_types.h>. */
#ifndef BITTEN_PTHREAD_H
#define BITTEN_PTHREAD_H
#include <sys/_types.h>
#include <sched.h>
#include <time.h>
#include <sys/qos.h>

#define _PTHREAD_MUTEX_SIG_init 0x32AAABA7
#define _PTHREAD_COND_SIG_init 0x3CB0B1BB
#define _PTHREAD_ONCE_SIG_init 0x30B1BCBA
#define _PTHREAD_RWLOCK_SIG_init 0x2DA8B3B4
#define PTHREAD_MUTEX_INITIALIZER {_PTHREAD_MUTEX_SIG_init, {0}}
#define PTHREAD_COND_INITIALIZER {_PTHREAD_COND_SIG_init, {0}}
#define PTHREAD_ONCE_INIT {_PTHREAD_ONCE_SIG_init, {0}}
#define PTHREAD_RWLOCK_INITIALIZER {_PTHREAD_RWLOCK_SIG_init, {0}}

#define PTHREAD_MUTEX_NORMAL 0
#define PTHREAD_MUTEX_ERRORCHECK 1
#define PTHREAD_MUTEX_RECURSIVE 2
#define PTHREAD_MUTEX_DEFAULT PTHREAD_MUTEX_NORMAL
#define PTHREAD_CREATE_JOINABLE 1
#define PTHREAD_CREATE_DETACHED 2
#define PTHREAD_PROCESS_SHARED 1
#define PTHREAD_PROCESS_PRIVATE 2
#define PTHREAD_SCOPE_SYSTEM 1
#define PTHREAD_SCOPE_PROCESS 2

__BEGIN_DECLS
int pthread_create(pthread_t *restrict, const pthread_attr_t *restrict, void *(*)(void *), void *restrict);
int pthread_join(pthread_t, void **);
int pthread_detach(pthread_t);
void pthread_exit(void *) __dead2;
pthread_t pthread_self(void);
int pthread_equal(pthread_t, pthread_t);
int pthread_kill(pthread_t, int);
int pthread_once(pthread_once_t *, void (*)(void));
int pthread_main_np(void);
int pthread_is_threaded_np(void);
int pthread_threadid_np(pthread_t, uint64_t *);
int pthread_setname_np(const char *);
int pthread_getname_np(pthread_t, char *, size_t);
void *pthread_get_stackaddr_np(pthread_t);
size_t pthread_get_stacksize_np(pthread_t);
mach_port_t pthread_mach_thread_np(pthread_t);
void pthread_yield_np(void);
int pthread_attr_init(pthread_attr_t *);
int pthread_attr_destroy(pthread_attr_t *);
int pthread_attr_getdetachstate(const pthread_attr_t *, int *);
int pthread_attr_setdetachstate(pthread_attr_t *, int);
int pthread_attr_getstacksize(const pthread_attr_t *restrict, size_t *restrict);
int pthread_attr_setstacksize(pthread_attr_t *, size_t);
int pthread_attr_setguardsize(pthread_attr_t *, size_t);
int pthread_attr_setscope(pthread_attr_t *, int);
int pthread_attr_set_qos_class_np(pthread_attr_t *, qos_class_t, int);
int pthread_set_qos_class_self_np(qos_class_t, int);
int pthread_mutex_init(pthread_mutex_t *restrict, const pthread_mutexattr_t *restrict);
int pthread_mutex_destroy(pthread_mutex_t *);
int pthread_mutex_lock(pthread_mutex_t *);
int pthread_mutex_trylock(pthread_mutex_t *);
int pthread_mutex_unlock(pthread_mutex_t *);
int pthread_mutexattr_init(pthread_mutexattr_t *);
int pthread_mutexattr_destroy(pthread_mutexattr_t *);
int pthread_mutexattr_settype(pthread_mutexattr_t *, int);
int pthread_mutexattr_setpshared(pthread_mutexattr_t *, int);
int pthread_cond_init(pthread_cond_t *restrict, const pthread_condattr_t *restrict);
int pthread_cond_destroy(pthread_cond_t *);
int pthread_cond_wait(pthread_cond_t *restrict, pthread_mutex_t *restrict);
int pthread_cond_timedwait(pthread_cond_t *restrict, pthread_mutex_t *restrict, const struct timespec *restrict);
int pthread_cond_timedwait_relative_np(pthread_cond_t *, pthread_mutex_t *, const struct timespec *);
int pthread_cond_signal(pthread_cond_t *);
int pthread_cond_broadcast(pthread_cond_t *);
int pthread_condattr_init(pthread_condattr_t *);
int pthread_condattr_destroy(pthread_condattr_t *);
int pthread_rwlock_init(pthread_rwlock_t *restrict, const pthread_rwlockattr_t *restrict);
int pthread_rwlock_destroy(pthread_rwlock_t *);
int pthread_rwlock_rdlock(pthread_rwlock_t *);
int pthread_rwlock_tryrdlock(pthread_rwlock_t *);
int pthread_rwlock_wrlock(pthread_rwlock_t *);
int pthread_rwlock_trywrlock(pthread_rwlock_t *);
int pthread_rwlock_unlock(pthread_rwlock_t *);
int pthread_key_create(pthread_key_t *, void (*)(void *));
int pthread_key_delete(pthread_key_t);
int pthread_setspecific(pthread_key_t, const void *);
void *pthread_getspecific(pthread_key_t);
__END_DECLS
#endif
