/* pthreads, static-initialised Darwin mutexes, TSD keys and signals. */
#include "darwin.h"

typedef struct { long sig; char opaque[56]; } pthread_mutex_t;
typedef struct { long sig; char opaque[40]; } pthread_cond_t;
typedef void *pthread_t;
#define PTHREAD_MUTEX_INITIALIZER {0x32AAABA7, {0}}
#define PTHREAD_COND_INITIALIZER {0x3CB0B1BB, {0}}
int pthread_create(pthread_t *, void *, void *(*)(void *), void *);
int pthread_join(pthread_t, void **);
int pthread_mutex_lock(pthread_mutex_t *);
int pthread_mutex_unlock(pthread_mutex_t *);
int pthread_cond_wait(pthread_cond_t *, pthread_mutex_t *);
int pthread_cond_broadcast(pthread_cond_t *);
int pthread_key_create(unsigned long *, void (*)(void *));
int pthread_setspecific(unsigned long, const void *);
void *pthread_getspecific(unsigned long);
pthread_t pthread_self(void);
int pthread_kill(pthread_t, int);

struct sigaction { void (*handler)(int, void *, void *); uint32_t mask; int flags; };
int sigaction(int, const struct sigaction *, struct sigaction *);
#define SIGUSR1 30
#define SA_SIGINFO 0x40
struct siginfo { int si_signo, si_errno, si_code; };

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
static int total, started, go;
static unsigned long key;
static int destroyed;
static volatile int got_signal;
__thread int per_thread = 5;

static void dtor(void *p) { destroyed += (int)(long)p; }

static void *worker(void *arg) {
    long id = (long)arg;
    CHECK(per_thread == 5);
    per_thread += (int)id;
    CHECK(pthread_setspecific(key, (void *)id) == 0);
    pthread_mutex_lock(&lock);
    started++;
    pthread_cond_broadcast(&cond);
    while (!go) pthread_cond_wait(&cond, &lock);
    pthread_mutex_unlock(&lock);
    for (int i = 0; i < 10000; i++) {
        pthread_mutex_lock(&lock);
        total++;
        pthread_mutex_unlock(&lock);
    }
    CHECK(pthread_getspecific(key) == (void *)id);
    CHECK(per_thread == 5 + (int)id);
    return (void *)(id * 2);
}

static void on_usr1(int sig, void *info, void *ctx) {
    struct siginfo *si = info;
    if (sig == SIGUSR1 && si->si_signo == SIGUSR1 && ctx) got_signal = 1;
}

int main(void) {
    CHECK(pthread_key_create(&key, dtor) == 0);
    pthread_t t[4];
    for (long i = 0; i < 4; i++) CHECK(pthread_create(&t[i], NULL, worker, (void *)(i + 1)) == 0);
    pthread_mutex_lock(&lock);
    while (started < 4) pthread_cond_wait(&cond, &lock);
    go = 1;
    pthread_cond_broadcast(&cond);
    pthread_mutex_unlock(&lock);
    for (long i = 0; i < 4; i++) {
        void *r;
        CHECK(pthread_join(t[i], &r) == 0);
        CHECK(r == (void *)((i + 1) * 2));
    }
    CHECK(total == 40000);
    CHECK(destroyed == 1 + 2 + 3 + 4);

    struct sigaction sa = {on_usr1, 0, SA_SIGINFO};
    CHECK(sigaction(SIGUSR1, &sa, NULL) == 0);
    CHECK(pthread_kill(pthread_self(), SIGUSR1) == 0);
    CHECK(got_signal == 1);
    puts("threads ok");
    return 0;
}
