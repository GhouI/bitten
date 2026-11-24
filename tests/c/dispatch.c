#include "darwin.h"

typedef void *queue_t;
typedef void *attr_t;
typedef void *group_t;
typedef void *semaphore_t;
typedef void *data_t;
typedef void (^block_t)(void);

extern char _dispatch_main_q, _dispatch_queue_attr_concurrent, _dispatch_data_empty;
extern const block_t _dispatch_data_destructor_free;
queue_t dispatch_get_main_queue(void);
queue_t dispatch_get_global_queue(long, unsigned long);
queue_t dispatch_get_current_queue(void);
queue_t dispatch_queue_create(const char *, attr_t);
queue_t dispatch_queue_create_with_target(const char *, attr_t, queue_t);
attr_t dispatch_queue_attr_make_with_qos_class(attr_t, unsigned, int);
attr_t dispatch_queue_attr_make_initially_inactive(attr_t);
const char *dispatch_queue_get_label(queue_t);
unsigned dispatch_queue_get_qos_class(queue_t, int *);
void dispatch_set_target_queue(void *, queue_t);
void dispatch_queue_set_specific(queue_t, const void *, void *, void (*)(void *));
void *dispatch_queue_get_specific(queue_t, const void *);
void *dispatch_get_specific(const void *);
void dispatch_assert_queue(queue_t);
void dispatch_assert_queue_not(queue_t);
void dispatch_async(queue_t, block_t);
void dispatch_sync(queue_t, block_t);
void dispatch_async_and_wait(queue_t, block_t);
void dispatch_barrier_async(queue_t, block_t);
void dispatch_barrier_sync_f(queue_t, void *, void (*)(void *));
void dispatch_apply(size_t, queue_t, void (^)(size_t));
void dispatch_after(uint64_t, queue_t, block_t);
void dispatch_once(long *, block_t);
void dispatch_main(void) __attribute__((noreturn));
uint64_t dispatch_time(uint64_t, int64_t);
uint64_t dispatch_walltime(const void *, int64_t);
void dispatch_set_context(void *, void *);
void *dispatch_get_context(void *);
void dispatch_set_finalizer_f(void *, void (*)(void *));
void dispatch_release(void *);
void dispatch_suspend(void *);
void dispatch_resume(void *);
void dispatch_activate(void *);
group_t dispatch_group_create(void);
void dispatch_group_enter(group_t);
void dispatch_group_leave(group_t);
void dispatch_group_async(group_t, queue_t, block_t);
void dispatch_group_notify(group_t, queue_t, block_t);
long dispatch_group_wait(group_t, uint64_t);
semaphore_t dispatch_semaphore_create(long);
long dispatch_semaphore_wait(semaphore_t, uint64_t);
long dispatch_semaphore_signal(semaphore_t);
block_t dispatch_block_create(unsigned long, block_t);
void dispatch_block_cancel(block_t);
long dispatch_block_testcancel(block_t);
long dispatch_block_wait(block_t, uint64_t);
void dispatch_block_notify(block_t, queue_t, block_t);
void _Block_release(block_t);
data_t dispatch_data_create(const void *, size_t, queue_t, block_t);
size_t dispatch_data_get_size(data_t);
data_t dispatch_data_create_map(data_t, const void **, size_t *);
data_t dispatch_data_create_concat(data_t, data_t);
data_t dispatch_data_create_subrange(data_t, size_t, size_t);
_Bool dispatch_data_apply(data_t, _Bool (^)(data_t, size_t, const void *, size_t));
uint64_t mach_absolute_time(void);
int fork(void);
int waitpid(int, int *, int);
void _exit(int) __attribute__((noreturn));
int kill(int, int);
int usleep(unsigned);
int pthread_main_np(void);
int pthread_create(void **, void *, void *(*)(void *), void *);
int pthread_join(void *, void **);
void *pthread_self(void);

#define CONCURRENT (&_dispatch_queue_attr_concurrent)
#define MS 1000000ll

static uint64_t limit(void) { return dispatch_time(0, 3000 * MS); }

static void test_main_queue(void) {
    int child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        queue_t main_queue = dispatch_get_main_queue();
        CHECK(main_queue == &_dispatch_main_q);
        queue_t worker = dispatch_get_global_queue(0, 0);
        static int first;
        dispatch_async(worker, ^{
            CHECK(!pthread_main_np());
            dispatch_async(main_queue, ^{
                CHECK(pthread_main_np());
                CHECK(dispatch_get_current_queue() == main_queue);
                first = 1;
            });
            dispatch_async(main_queue, ^{
                _exit(first == 1 && pthread_main_np() ? 0 : 2);
            });
        });
        dispatch_main();
    }
    int status, result = 0;
    for (int i = 0; i < 500 && result == 0; ++i) {
        result = waitpid(child, &status, 1);
        if (!result) usleep(10000);
    }
    if (!result) {
        kill(child, 9);
        waitpid(child, &status, 0);
    }
    CHECK(result == child && status == 0);
}

static void increment(void *arg) { ++*(int *)arg; }
static void signal_done(void *arg) { dispatch_semaphore_signal(arg); }
static __thread int worker_tls = 31;

static void test_serial(void) {
    queue_t queue = dispatch_queue_create("test.serial", NULL);
    CHECK(strcmp(dispatch_queue_get_label(queue), "test.serial") == 0);
    __block int next = 0, active = 0;
    worker_tls = -1;
    for (int i = 0; i < 512; ++i) {
        dispatch_async(queue, ^{
            CHECK(__atomic_add_fetch(&active, 1, __ATOMIC_RELAXED) == 1);
            CHECK(next++ == i);
            CHECK(worker_tls == 31);
            CHECK(pthread_self() != NULL);
            dispatch_assert_queue(queue);
            CHECK(dispatch_get_current_queue() == queue);
            __atomic_sub_fetch(&active, 1, __ATOMIC_RELAXED);
        });
    }
    dispatch_sync(queue, ^{ CHECK(next++ == 512); });
    dispatch_async_and_wait(queue, ^{ CHECK(next++ == 513); });
    CHECK(next == 514 && active == 0);
    dispatch_assert_queue_not(queue);
    dispatch_release(queue);
}

static void test_parallel_and_barriers(void) {
    queue_t queue = dispatch_queue_create("test.concurrent", CONCURRENT);
    group_t group = dispatch_group_create();
    semaphore_t started = dispatch_semaphore_create(0), gate = dispatch_semaphore_create(0);
    __block int active = 0, finished = 0, barrier = 0;

    for (int i = 0; i < 2; ++i) {
        dispatch_group_async(group, queue, ^{
            __atomic_add_fetch(&active, 1, __ATOMIC_SEQ_CST);
            dispatch_semaphore_signal(started);
            CHECK(dispatch_semaphore_wait(gate, limit()) == 0);
            __atomic_add_fetch(&finished, 1, __ATOMIC_SEQ_CST);
            __atomic_sub_fetch(&active, 1, __ATOMIC_SEQ_CST);
        });
    }
    CHECK(dispatch_semaphore_wait(started, limit()) == 0);
    CHECK(dispatch_semaphore_wait(started, limit()) == 0);
    CHECK(__atomic_load_n(&active, __ATOMIC_SEQ_CST) == 2);

    dispatch_barrier_async(queue, ^{
        CHECK(__atomic_load_n(&active, __ATOMIC_SEQ_CST) == 0);
        CHECK(__atomic_load_n(&finished, __ATOMIC_SEQ_CST) == 2);
        barrier = 1;
        usleep(10000);
        barrier = 2;
    });
    for (int i = 0; i < 16; ++i) dispatch_async(queue, ^{ CHECK(barrier == 2); });
    dispatch_semaphore_signal(gate);
    dispatch_semaphore_signal(gate);
    int synced = 0;
    dispatch_barrier_sync_f(queue, &synced, increment);
    CHECK(synced == 1 && dispatch_group_wait(group, limit()) == 0);
    dispatch_release(gate);
    dispatch_release(started);
    dispatch_release(group);
    dispatch_release(queue);
}

static void test_target_and_suspend(void) {
    static int inherited_key, local_key;
    queue_t target = dispatch_queue_create("test.target", NULL);
    attr_t attr = dispatch_queue_attr_make_initially_inactive(CONCURRENT);
    queue_t first = dispatch_queue_create_with_target("test.first", attr, target);
    queue_t second = dispatch_queue_create("test.second", CONCURRENT);
    dispatch_set_target_queue(second, target);
    dispatch_queue_set_specific(target, &inherited_key, (void *)1, NULL);
    dispatch_queue_set_specific(first, &local_key, (void *)2, NULL);
    CHECK(dispatch_queue_get_specific(first, &inherited_key) == NULL);
    CHECK(dispatch_queue_get_specific(first, &local_key) == (void *)2);
    CHECK(dispatch_get_specific(&inherited_key) == NULL);

    dispatch_suspend(second);
    semaphore_t started = dispatch_semaphore_create(0);
    group_t group = dispatch_group_create();
    __block int active = 0;
    for (int i = 0; i < 48; ++i) {
        queue_t queue = i % 2 ? first : second;
        dispatch_group_async(group, queue, ^{
            CHECK(__atomic_add_fetch(&active, 1, __ATOMIC_RELAXED) == 1);
            dispatch_assert_queue(target);
            CHECK(dispatch_get_specific(&inherited_key) == (void *)1);
            CHECK(dispatch_get_specific(&local_key) == (i % 2 ? (void *)2 : NULL));
            if (i == 0) dispatch_semaphore_signal(started);
            __atomic_sub_fetch(&active, 1, __ATOMIC_RELAXED);
        });
    }
    CHECK(dispatch_semaphore_wait(started, dispatch_time(0, 10 * MS)) != 0);
    dispatch_activate(first);
    dispatch_resume(second);
    CHECK(dispatch_group_wait(group, limit()) == 0);
    CHECK(dispatch_semaphore_wait(started, 0) == 0);

    attr = dispatch_queue_attr_make_with_qos_class(NULL, 0x19, -4);
    queue_t qos = dispatch_queue_create("test.qos", attr);
    int relative = 0;
    CHECK(dispatch_queue_get_qos_class(qos, &relative) == 0x19 && relative == -4);

    dispatch_set_context(second, started);
    CHECK(dispatch_get_context(second) == started);
    dispatch_set_finalizer_f(second, signal_done);
    dispatch_release(second);
    CHECK(dispatch_semaphore_wait(started, limit()) == 0);

    dispatch_release(qos);
    dispatch_release(group);
    dispatch_release(started);
    dispatch_release(first);
    dispatch_release(target);
}

static long once;
static int initialized;

static void *contend(void *arg) {
    semaphore_t *semas = arg;
    dispatch_semaphore_signal(semas[0]);
    CHECK(dispatch_semaphore_wait(semas[1], limit()) == 0);
    dispatch_once(&once, ^{
        ++initialized;
        usleep(15000);
        initialized += 6;
    });
    CHECK(initialized == 7);
    return NULL;
}

static void test_once(void) {
    void *threads[8];
    semaphore_t semas[] = { dispatch_semaphore_create(0), dispatch_semaphore_create(0) };
    for (size_t i = 0; i < 8; ++i) CHECK(pthread_create(&threads[i], NULL, contend, semas) == 0);
    for (size_t i = 0; i < 8; ++i) CHECK(dispatch_semaphore_wait(semas[0], limit()) == 0);
    for (size_t i = 0; i < 8; ++i) dispatch_semaphore_signal(semas[1]);
    for (size_t i = 0; i < 8; ++i) CHECK(pthread_join(threads[i], NULL) == 0);
    dispatch_once(&once, ^{ CHECK(0); });
    CHECK(initialized == 7);
    dispatch_release(semas[0]);
    dispatch_release(semas[1]);
}

static void test_group_semaphore_after(void) {
    queue_t queue = dispatch_get_global_queue(0, 0);
    group_t group = dispatch_group_create();
    semaphore_t notify = dispatch_semaphore_create(0);
    CHECK(dispatch_semaphore_create(-1) == NULL);
    CHECK(dispatch_semaphore_wait(notify, 0) != 0);
    CHECK(dispatch_semaphore_wait(notify, dispatch_walltime(NULL, 10 * MS)) != 0);
    CHECK(dispatch_semaphore_signal(notify) == 0);
    CHECK(dispatch_semaphore_wait(notify, 0) == 0);

    dispatch_group_enter(group);
    dispatch_group_notify(group, queue, ^{ dispatch_semaphore_signal(notify); });
    CHECK(dispatch_group_wait(group, dispatch_time(0, 10 * MS)) != 0);
    CHECK(dispatch_semaphore_wait(notify, 0) != 0);
    uint64_t start = mach_absolute_time();
    dispatch_after(dispatch_time(0, 25 * MS), queue, ^{
        uint64_t elapsed = mach_absolute_time() - start;
        CHECK(elapsed >= 20 * MS && elapsed < 3000 * MS);
        dispatch_group_leave(group);
    });
    CHECK(dispatch_group_wait(group, limit()) == 0);
    CHECK(dispatch_semaphore_wait(notify, limit()) == 0);

    semaphore_t signal_returned = dispatch_semaphore_create(0);
    __block long woke = 0;
    dispatch_after(dispatch_time(0, 30 * MS), queue, ^{
        woke = dispatch_semaphore_signal(notify);
        dispatch_semaphore_signal(signal_returned);
    });
    CHECK(dispatch_semaphore_wait(notify, limit()) == 0);
    CHECK(dispatch_semaphore_wait(signal_returned, limit()) == 0 && woke != 0);
    dispatch_release(signal_returned);
    dispatch_release(notify);
    dispatch_release(group);
}

__attribute__((noinline)) static void enqueue_captured(queue_t queue, int *out, int value) {
    int (^captured)(int) = ^(int add) { return value + add; };
    dispatch_async(queue, ^{ *out = captured(11); });
}

static void test_apply_and_blocks(void) {
    int iterations[160] = {0};
    int *counts = iterations;
    dispatch_apply(sizeof iterations / sizeof *iterations, NULL, ^(size_t i) {
        CHECK(i < sizeof iterations / sizeof *iterations);
        __atomic_add_fetch(&counts[i], 1, __ATOMIC_RELAXED);
    });
    for (size_t i = 0; i < sizeof iterations / sizeof *iterations; ++i) CHECK(iterations[i] == 1);

    queue_t queue = dispatch_queue_create("test.blocks", NULL);
    dispatch_suspend(queue);
    __block int value = 7;
    dispatch_async(queue, ^{ value += 4; });
    int result = 0;
    enqueue_captured(queue, &result, 13);
    dispatch_resume(queue);
    dispatch_sync(queue, ^{ CHECK(value == 11); });
    CHECK(result == 24);

    semaphore_t notify = dispatch_semaphore_create(0);
    block_t block = dispatch_block_create(0, ^{ CHECK(0); });
    CHECK(block != NULL && dispatch_block_wait(block, 0) != 0);
    dispatch_block_notify(block, queue, ^{ dispatch_semaphore_signal(notify); });
    dispatch_block_cancel(block);
    CHECK(dispatch_block_testcancel(block));
    dispatch_async(queue, block);
    CHECK(dispatch_block_wait(block, limit()) == 0);
    CHECK(dispatch_semaphore_wait(notify, limit()) == 0);
    _Block_release(block);
    dispatch_release(notify);
    dispatch_release(queue);
}

static void test_data(void) {
    char input[] = "abc";
    data_t left = dispatch_data_create(input, 3, NULL, NULL);
    input[0] = 'X';
    char *heap = malloc(3);
    CHECK(heap != NULL);
    memcpy(heap, "def", 3);
    data_t right = dispatch_data_create(heap, 3, NULL, _dispatch_data_destructor_free);
    data_t combined = dispatch_data_create_concat(left, right);
    dispatch_release(left);
    dispatch_release(right);
    CHECK(dispatch_data_get_size(combined) == 6);

    __block size_t visited = 0;
    CHECK(dispatch_data_apply(combined, ^_Bool(data_t region, size_t offset, const void *bytes, size_t n) {
        CHECK(dispatch_data_get_size(region) == n);
        CHECK(visited == offset && offset + n <= 6);
        CHECK(memcmp(bytes, &"abcdef"[offset], n) == 0);
        visited += n;
        return 1;
    }));
    CHECK(visited == 6);
    CHECK(!dispatch_data_apply(combined, ^_Bool(data_t region, size_t off, const void *p, size_t n) {
        (void)region; (void)off; (void)p; (void)n;
        return 0;
    }));
    data_t sub = dispatch_data_create_subrange(combined, 1, 4);
    dispatch_release(combined);
    const void *p = NULL;
    size_t n = 0;
    data_t map = dispatch_data_create_map(sub, &p, &n);
    dispatch_release(sub);
    CHECK(n == 4 && memcmp(p, "bcde", 4) == 0);
    CHECK(dispatch_data_create(NULL, 0, NULL, NULL) == &_dispatch_data_empty);
    dispatch_release(map);
}

int main(void) {
    test_main_queue();
    test_serial();
    test_parallel_and_barriers();
    test_target_and_suspend();
    test_once();
    test_group_semaphore_after();
    test_apply_and_blocks();
    test_data();
    puts("dispatch ok");
    return 0;
}
