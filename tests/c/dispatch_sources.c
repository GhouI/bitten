#include "darwin.h"

typedef void *queue_t;
typedef void *source_t;
typedef void *semaphore_t;
typedef void *data_t;
typedef void (^block_t)(void);

extern char _dispatch_source_type_timer, _dispatch_source_type_read, _dispatch_source_type_write;
extern char _dispatch_source_type_signal, _dispatch_source_type_proc;
extern char _dispatch_source_type_data_add, _dispatch_source_type_data_or;
queue_t dispatch_queue_create(const char *, void *);
source_t dispatch_source_create(void *, unsigned long, unsigned long, queue_t);
void dispatch_source_set_timer(source_t, uint64_t, uint64_t, uint64_t);
void dispatch_source_set_event_handler(source_t, block_t);
void dispatch_source_set_event_handler_f(source_t, void (*)(void *));
void dispatch_source_set_cancel_handler(source_t, block_t);
void dispatch_source_set_registration_handler(source_t, block_t);
void dispatch_source_cancel(source_t);
long dispatch_source_testcancel(source_t);
unsigned long dispatch_source_get_handle(source_t);
unsigned long dispatch_source_get_mask(source_t);
unsigned long dispatch_source_get_data(source_t);
void dispatch_source_merge_data(source_t, unsigned long);
void dispatch_set_context(void *, void *);
void dispatch_resume(void *);
void dispatch_suspend(void *);
void dispatch_activate(void *);
void dispatch_release(void *);
void dispatch_sync(queue_t, block_t);
uint64_t dispatch_time(uint64_t, int64_t);
uint64_t dispatch_walltime(const void *, int64_t);
semaphore_t dispatch_semaphore_create(long);
long dispatch_semaphore_wait(semaphore_t, uint64_t);
long dispatch_semaphore_signal(semaphore_t);
data_t dispatch_data_create(const void *, size_t, queue_t, block_t);
data_t dispatch_data_create_map(data_t, const void **, size_t *);
void dispatch_read(int, size_t, queue_t, void (^)(data_t, int));
void dispatch_write(int, data_t, queue_t, void (^)(data_t, int));
int pipe(int[2]);
int close(int);
ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
int fork(void);
int waitpid(int, int *, int);
void _exit(int) __attribute__((noreturn));
int kill(int, int);
int getpid(void);
int usleep(unsigned);
void (*signal(int, void (*)(int)))(int);

#define MS 1000000ll
#define PROC_EXIT 0x80000000ul
#define SIGUSR1 30

static uint64_t limit(void) { return dispatch_time(0, 3000 * MS); }

static void test_timer(queue_t queue) {
    semaphore_t stopped = dispatch_semaphore_create(0);
    source_t timer = dispatch_source_create(&_dispatch_source_type_timer, 0, 0, queue);
    CHECK(timer != NULL);
    __block int times = 0, ready = 0;
    dispatch_source_set_registration_handler(timer, ^{ ready = 1; });
    dispatch_source_set_event_handler(timer, ^{
        CHECK(ready == 1 && !dispatch_source_testcancel(timer));
        CHECK(dispatch_source_get_data(timer) >= 1);
        if (++times == 4) dispatch_source_cancel(timer);
    });
    dispatch_source_set_cancel_handler(timer, ^{
        CHECK(dispatch_source_testcancel(timer) && times == 4);
        dispatch_semaphore_signal(stopped);
    });
    dispatch_source_set_timer(timer, dispatch_walltime(NULL, 15 * MS), 8 * MS, 0);
    dispatch_resume(timer);
    CHECK(dispatch_semaphore_wait(stopped, limit()) == 0);
    dispatch_sync(queue, ^{ CHECK(times == 4); });
    dispatch_release(timer);
    dispatch_release(stopped);
}

static void test_read_write_sources(queue_t queue) {
    int p[2];
    CHECK(pipe(p) == 0);
    semaphore_t complete = dispatch_semaphore_create(0);
    source_t r = dispatch_source_create(&_dispatch_source_type_read, p[0], 0, queue);
    source_t w = dispatch_source_create(&_dispatch_source_type_write, p[1], 0, queue);
    CHECK(r && w);
    CHECK(dispatch_source_get_handle(r) == (unsigned)p[0]);
    CHECK(dispatch_source_get_mask(r) == 0);
    int read_fd = p[0], write_fd = p[1];
    dispatch_source_set_event_handler(r, ^{
        CHECK(dispatch_source_get_data(r) >= 3);
        char bytes[3];
        CHECK(read(read_fd, bytes, sizeof bytes) == 3 && memcmp(bytes, "abc", 3) == 0);
        dispatch_source_cancel(r);
    });
    dispatch_source_set_event_handler(w, ^{
        CHECK(dispatch_source_get_data(w) >= 3);
        CHECK(write(write_fd, "abc", 3) == 3);
        dispatch_source_cancel(w);
    });
    dispatch_source_set_cancel_handler(r, ^{
        CHECK(close(read_fd) == 0);
        dispatch_semaphore_signal(complete);
    });
    dispatch_source_set_cancel_handler(w, ^{
        CHECK(close(write_fd) == 0);
        dispatch_semaphore_signal(complete);
    });
    dispatch_activate(r);
    dispatch_activate(w);
    CHECK(dispatch_semaphore_wait(complete, limit()) == 0);
    CHECK(dispatch_semaphore_wait(complete, limit()) == 0);
    dispatch_release(r);
    dispatch_release(w);
    dispatch_release(complete);
}

static int got_signal;
static void on_signal(int sig) {
    if (sig == SIGUSR1) __atomic_store_n(&got_signal, 1, __ATOMIC_RELAXED);
}

static void test_signal(queue_t queue) {
    CHECK(signal(SIGUSR1, on_signal) != (void *)-1);
    semaphore_t registered = dispatch_semaphore_create(0), happened = dispatch_semaphore_create(0);
    source_t source = dispatch_source_create(&_dispatch_source_type_signal, SIGUSR1, 0, queue);
    CHECK(source != NULL);
    dispatch_source_set_registration_handler(source, ^{ dispatch_semaphore_signal(registered); });
    dispatch_source_set_event_handler(source, ^{
        CHECK(dispatch_source_get_data(source) >= 1);
        dispatch_source_cancel(source);
        dispatch_semaphore_signal(happened);
    });
    dispatch_activate(source);
    CHECK(dispatch_semaphore_wait(registered, limit()) == 0);
    CHECK(kill(getpid(), SIGUSR1) == 0);
    CHECK(dispatch_semaphore_wait(happened, limit()) == 0);
    for (int i = 0; i < 200 && !__atomic_load_n(&got_signal, __ATOMIC_RELAXED); ++i) usleep(1000);
    CHECK(__atomic_load_n(&got_signal, __ATOMIC_RELAXED) == 1);
    dispatch_release(source);
    dispatch_release(registered);
    dispatch_release(happened);
}

struct proc_context { source_t source; semaphore_t complete; };

static void on_exit(void *arg) {
    struct proc_context *context = arg;
    CHECK(dispatch_source_get_data(context->source) == PROC_EXIT);
    dispatch_source_cancel(context->source);
    dispatch_semaphore_signal(context->complete);
}

static void test_proc(queue_t queue) {
    int p[2];
    CHECK(pipe(p) == 0);
    int child = fork();
    CHECK(child >= 0);
    if (!child) {
        close(p[1]);
        char byte;
        _exit(read(p[0], &byte, 1) == 1 ? 0 : 1);
    }
    CHECK(close(p[0]) == 0);
    struct proc_context context = {
        dispatch_source_create(&_dispatch_source_type_proc, child, PROC_EXIT, queue),
        dispatch_semaphore_create(0),
    };
    CHECK(context.source != NULL && dispatch_source_get_mask(context.source) == PROC_EXIT);
    dispatch_set_context(context.source, &context);
    dispatch_source_set_event_handler_f(context.source, on_exit);
    dispatch_resume(context.source);
    CHECK(write(p[1], "x", 1) == 1 && close(p[1]) == 0);
    CHECK(dispatch_semaphore_wait(context.complete, limit()) == 0);
    int status;
    CHECK(waitpid(child, &status, 0) == child && status == 0);
    dispatch_release(context.source);
    dispatch_release(context.complete);
}

static void test_user_data(queue_t queue, void *type, unsigned long expected) {
    source_t source = dispatch_source_create(type, 0, 0, queue);
    CHECK(source != NULL);
    semaphore_t done = dispatch_semaphore_create(0);
    dispatch_source_set_event_handler(source, ^{
        CHECK(dispatch_source_get_data(source) == expected);
        dispatch_source_cancel(source);
        dispatch_semaphore_signal(done);
    });
    dispatch_activate(source);
    dispatch_suspend(source);
    dispatch_source_merge_data(source, 3);
    dispatch_source_merge_data(source, 6);
    CHECK(dispatch_semaphore_wait(done, 0) != 0);
    dispatch_resume(source);
    CHECK(dispatch_semaphore_wait(done, limit()) == 0);
    dispatch_release(source);
    dispatch_release(done);
}

static void test_io(queue_t queue) {
    int p[2];
    CHECK(pipe(p) == 0);
    data_t input = dispatch_data_create("hello", 5, NULL, NULL);
    semaphore_t done = dispatch_semaphore_create(0);
    dispatch_read(p[0], 5, queue, ^(data_t data, int error) {
        CHECK(!error);
        const void *bytes;
        size_t length;
        data_t map = dispatch_data_create_map(data, &bytes, &length);
        CHECK(length == 5 && memcmp(bytes, "hello", length) == 0);
        dispatch_release(map);
        dispatch_semaphore_signal(done);
    });
    dispatch_write(p[1], input, queue, ^(data_t rest, int error) {
        CHECK(!error && rest == NULL);
        dispatch_semaphore_signal(done);
    });
    dispatch_release(input);
    CHECK(dispatch_semaphore_wait(done, limit()) == 0);
    CHECK(dispatch_semaphore_wait(done, limit()) == 0);
    CHECK(close(p[0]) == 0 && close(p[1]) == 0);
    dispatch_release(done);
}

int main(void) {
    queue_t queue = dispatch_queue_create("test.sources", NULL);
    test_timer(queue);
    test_read_write_sources(queue);
    test_signal(queue);
    test_proc(queue);
    test_user_data(queue, &_dispatch_source_type_data_add, 9);
    test_user_data(queue, &_dispatch_source_type_data_or, 7);
    test_io(queue);
    dispatch_release(queue);
    puts("dispatch sources ok");
    return 0;
}
