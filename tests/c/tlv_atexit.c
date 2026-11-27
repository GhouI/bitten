#include "darwin.h"

void _tlv_atexit(void (*)(void *), void *);
int pthread_create(void **, const void *, void *(*)(void *), void *);
int pthread_join(void *, void **);
int atexit(void (*)(void));

static _Thread_local int object;
static _Thread_local int order;
static int worker_done;

static void first(void *p) {
    CHECK(p == &object && object == 41 && order == 0);
    order = 1;
}

static void last(void *p) {
    CHECK(p == &object && object == 41 && order == 1);
    object = 42;
    worker_done++;
}

static void register_callbacks(void) {
    object = 41;
    _tlv_atexit(last, &object);
    _tlv_atexit(first, &object);
}

static void *worker(void *unused) {
    (void)unused;
    register_callbacks();
    return NULL;
}

static void check_main_exit(void) {
    CHECK(object == 42 && worker_done == 2);
    puts("tlv destructors ok");
}

int main(void) {
    void *thread = NULL;
    CHECK(pthread_create(&thread, NULL, worker, NULL) == 0);
    CHECK(pthread_join(thread, NULL) == 0);
    CHECK(worker_done == 1 && object == 0);
    CHECK(atexit(check_main_exit) == 0);
    register_callbacks();
    return 0;
}
