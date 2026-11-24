#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

#include "internal.h"

#define DISPATCH_MAX_TIME ((uint64_t)INT64_MAX)

uint64_t dispatch_now(clockid_t clock) {
    struct timespec now;
    clock_gettime(clock, &now);
    return (uint64_t)now.tv_sec * DISPATCH_NSEC + (uint64_t)now.tv_nsec;
}

struct timespec dispatch_timespec(uint64_t nanos) {
    return (struct timespec){ .tv_sec = nanos / DISPATCH_NSEC, .tv_nsec = nanos % DISPATCH_NSEC };
}

clockid_t dispatch_deadline(uint64_t when, struct timespec *deadline) {
    bool wall = when > DISPATCH_MAX_TIME && when != DISPATCH_FOREVER;
    *deadline = dispatch_timespec(wall ? -when : when);
    return wall ? CLOCK_REALTIME : CLOCK_MONOTONIC;
}

int dispatch_cond_wait(pthread_cond_t *cond, pthread_mutex_t *lock, uint64_t when) {
    if (when == DISPATCH_FOREVER) return pthread_cond_wait(cond, lock);
    if (!when) return ETIMEDOUT;
    struct timespec deadline;
    clockid_t clock = dispatch_deadline(when, &deadline);
    return pthread_cond_clockwait(cond, lock, clock, &deadline);
}

static uint64_t offset_time(__int128 base, int64_t delta, bool wall) {
    __int128 result = base + delta;
    if (result > DISPATCH_MAX_TIME) return DISPATCH_FOREVER;
    if (result < (wall ? 2 : 1)) result = wall ? 2 : 1;
    return wall ? -(uint64_t)result : (uint64_t)result;
}

static uint64_t d_dispatch_time(uint64_t when, int64_t delta) {
    if (when == DISPATCH_FOREVER) return when;
    if (!when) when = dispatch_now(CLOCK_MONOTONIC);
    bool wall = when > DISPATCH_MAX_TIME;
    return offset_time(wall ? -when : when, delta, wall);
}
DX_FN(dispatch_time);

static uint64_t d_dispatch_walltime(const struct timespec *when, int64_t delta) {
    __int128 base = when ? (__int128)when->tv_sec * DISPATCH_NSEC + when->tv_nsec
                         : dispatch_now(CLOCK_REALTIME);
    return offset_time(base, delta, true);
}
DX_FN(dispatch_walltime);

static pthread_mutex_t once_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t once_cond = PTHREAD_COND_INITIALIZER;

static void d_dispatch_once_f(long *predicate, void *context, dispatch_function fn) {
    if (__atomic_load_n(predicate, __ATOMIC_ACQUIRE) == -1) return;
    long unset = 0;
    if (__atomic_compare_exchange_n(predicate, &unset, 1, false, __ATOMIC_ACQUIRE, __ATOMIC_ACQUIRE)) {
        fn(context);
        pthread_mutex_lock(&once_lock);
        __atomic_store_n(predicate, -1, __ATOMIC_RELEASE);
        pthread_cond_broadcast(&once_cond);
        pthread_mutex_unlock(&once_lock);
    } else if (unset != -1) {
        pthread_mutex_lock(&once_lock);
        while (__atomic_load_n(predicate, __ATOMIC_ACQUIRE) != -1)
            pthread_cond_wait(&once_cond, &once_lock);
        pthread_mutex_unlock(&once_lock);
    }
}
DX_FN(dispatch_once_f);

static void d_dispatch_once(long *predicate, void *block) {
    d_dispatch_once_f(predicate, block, dispatch_invoke_block);
}
DX_FN(dispatch_once);

struct dispatch_waiter {
    pthread_cond_t cond;
    struct dispatch_waiter *next, *previous;
    bool signaled;
};

struct dispatch_semaphore {
    struct dispatch_object object;
    pthread_mutex_t lock;
    struct dispatch_waiter *first, *last;
    long value;
};

static void semaphore_dispose(struct dispatch_object *object) {
    struct dispatch_semaphore *sema = (struct dispatch_semaphore *)object;
    pthread_mutex_destroy(&sema->lock);
}

static struct dispatch_semaphore *d_dispatch_semaphore_create(long value) {
    if (value < 0) return NULL;
    struct dispatch_semaphore *sema = dispatch_alloc(sizeof *sema);
    dispatch_object_init(&sema->object, DISPATCH_SEMAPHORE, "OS_dispatch_semaphore",
                         "OS_dispatch_object", semaphore_dispose);
    pthread_mutex_init(&sema->lock, NULL);
    sema->value = value;
    return sema;
}
DX_FN(dispatch_semaphore_create);

static void remove_waiter(struct dispatch_semaphore *sema, struct dispatch_waiter *waiter) {
    if (waiter->previous) waiter->previous->next = waiter->next;
    else sema->first = waiter->next;
    if (waiter->next) waiter->next->previous = waiter->previous;
    else sema->last = waiter->previous;
}

static long d_dispatch_semaphore_wait(struct dispatch_semaphore *sema, uint64_t when) {
    pthread_mutex_lock(&sema->lock);
    if (sema->value) {
        --sema->value;
        pthread_mutex_unlock(&sema->lock);
        return 0;
    }
    if (!when) {
        pthread_mutex_unlock(&sema->lock);
        return 1;
    }
    struct dispatch_waiter waiter = { .cond = PTHREAD_COND_INITIALIZER, .previous = sema->last };
    if (sema->last) sema->last->next = &waiter;
    else sema->first = &waiter;
    sema->last = &waiter;
    while (!waiter.signaled && dispatch_cond_wait(&waiter.cond, &sema->lock, when) != ETIMEDOUT) {}
    if (!waiter.signaled) remove_waiter(sema, &waiter);
    pthread_mutex_unlock(&sema->lock);
    pthread_cond_destroy(&waiter.cond);
    return !waiter.signaled;
}
DX_FN(dispatch_semaphore_wait);

static long d_dispatch_semaphore_signal(struct dispatch_semaphore *sema) {
    pthread_mutex_lock(&sema->lock);
    struct dispatch_waiter *waiter = sema->first;
    bool woke = waiter != NULL;
    if (waiter) {
        remove_waiter(sema, waiter);
        waiter->signaled = true;
        pthread_cond_signal(&waiter->cond);
    } else {
        if (sema->value == LONG_MAX) dx_fatal("dispatch: semaphore overflow");
        ++sema->value;
    }
    pthread_mutex_unlock(&sema->lock);
    return woke;
}
DX_FN(dispatch_semaphore_signal);

struct dispatch_notice {
    struct dispatch_notice *next;
    struct dispatch_queue *queue;
    void *context;
    dispatch_function fn;
    bool is_block;
};

struct dispatch_notices {
    struct dispatch_notice *head, *tail;
};

static void invoke_and_release(void *block) {
    dispatch_invoke_block(block);
    dx_block_release(block);
}

static void notify(struct dispatch_notices *list, struct dispatch_queue *queue,
                   void *context, dispatch_function fn, bool is_block) {
    struct dispatch_notice *notice = dispatch_alloc(sizeof *notice);
    notice->queue = queue;
    dispatch_object_retain(queue);
    notice->context = context;
    notice->fn = fn;
    notice->is_block = is_block;
    if (list->tail) list->tail->next = notice;
    else list->head = notice;
    list->tail = notice;
}

static struct dispatch_notice *take_notices(struct dispatch_notices *notices) {
    struct dispatch_notice *head = notices->head;
    *notices = (struct dispatch_notices){0};
    return head;
}

static void deliver_notices(struct dispatch_notice *list, bool submit) {
    while (list) {
        struct dispatch_notice *next = list->next;
        if (submit) {
            bool barrier = list->is_block && dispatch_block_is_barrier(list->context);
            dispatch_submit_batch(list->queue, list->context, list->fn, barrier, 1);
        } else if (list->is_block) {
            dx_block_release(list->context);
        }
        dispatch_object_release(list->queue);
        free(list);
        list = next;
    }
}

struct dispatch_group {
    struct dispatch_object object;
    pthread_mutex_t lock;
    pthread_cond_t cond;
    uint64_t count, generation;
    struct dispatch_notices notices;
};

static void group_dispose(struct dispatch_object *object) {
    struct dispatch_group *group = (struct dispatch_group *)object;
    pthread_cond_destroy(&group->cond);
    pthread_mutex_destroy(&group->lock);
}

static struct dispatch_group *d_dispatch_group_create(void) {
    struct dispatch_group *group = dispatch_alloc(sizeof *group);
    dispatch_object_init(&group->object, DISPATCH_GROUP, "OS_dispatch_group",
                         "OS_dispatch_object", group_dispose);
    pthread_mutex_init(&group->lock, NULL);
    pthread_cond_init(&group->cond, NULL);
    return group;
}
DX_FN(dispatch_group_create);

static void d_dispatch_group_enter(struct dispatch_group *group) {
    dispatch_object_retain(group);
    pthread_mutex_lock(&group->lock);
    ++group->count;
    pthread_mutex_unlock(&group->lock);
}
DX_FN(dispatch_group_enter);

static void d_dispatch_group_leave(struct dispatch_group *group) {
    struct dispatch_notice *ready = NULL;
    pthread_mutex_lock(&group->lock);
    if (!group->count) dx_fatal("dispatch: unbalanced group leave");
    if (--group->count == 0) {
        ++group->generation;
        ready = take_notices(&group->notices);
        pthread_cond_broadcast(&group->cond);
    }
    pthread_mutex_unlock(&group->lock);
    deliver_notices(ready, true);
    dispatch_object_release(group);
}
DX_FN(dispatch_group_leave);

static long d_dispatch_group_wait(struct dispatch_group *group, uint64_t when) {
    pthread_mutex_lock(&group->lock);
    uint64_t generation = group->generation;
    while (group->count && generation == group->generation &&
           dispatch_cond_wait(&group->cond, &group->lock, when) != ETIMEDOUT) {}
    bool timeout = group->count && generation == group->generation;
    pthread_mutex_unlock(&group->lock);
    return timeout;
}
DX_FN(dispatch_group_wait);

static void group_notify(struct dispatch_group *group, struct dispatch_queue *queue,
                         void *context, dispatch_function fn, bool is_block) {
    pthread_mutex_lock(&group->lock);
    bool ready = group->count == 0;
    if (!ready) notify(&group->notices, queue, context, fn, is_block);
    pthread_mutex_unlock(&group->lock);
    if (ready) dispatch_submit_batch(queue, context, fn, is_block && dispatch_block_is_barrier(context), 1);
}

static void d_dispatch_group_notify_f(struct dispatch_group *group, struct dispatch_queue *queue,
                                      void *context, dispatch_function fn) {
    group_notify(group, queue, context, fn, false);
}
DX_FN(dispatch_group_notify_f);

static void d_dispatch_group_notify(struct dispatch_group *group, struct dispatch_queue *queue,
                                    const void *block) {
    group_notify(group, queue, dispatch_copy_block(block), invoke_and_release, true);
}
DX_FN(dispatch_group_notify);

struct group_job {
    struct dispatch_group *group;
    void *context;
    dispatch_function fn;
};

static void group_call(void *arg) {
    struct group_job *job = arg;
    job->fn(job->context);
    d_dispatch_group_leave(job->group);
    free(job);
}

static void group_async(struct dispatch_group *group, struct dispatch_queue *queue,
                        void *context, dispatch_function fn, bool barrier) {
    struct group_job *job = dispatch_alloc(sizeof *job);
    *job = (struct group_job){ .group = group, .context = context, .fn = fn };
    d_dispatch_group_enter(group);
    dispatch_submit_batch(queue, job, group_call, barrier, 1);
}

static void d_dispatch_group_async_f(struct dispatch_group *group, struct dispatch_queue *queue,
                                     void *context, dispatch_function fn) {
    group_async(group, queue, context, fn, false);
}
DX_FN(dispatch_group_async_f);

static void d_dispatch_group_async(struct dispatch_group *group, struct dispatch_queue *queue,
                                   const void *block) {
    group_async(group, queue, dispatch_copy_block(block), invoke_and_release, dispatch_block_is_barrier(block));
}
DX_FN(dispatch_group_async);

struct apply_job {
    struct dispatch_group *group;
    atomic_size_t next;
    size_t limit;
    void *context;
    void (*fn)(void *, size_t);
};

static void apply_worker(void *arg) {
    struct apply_job *job = arg;
    for (;;) {
        size_t index = atomic_load_explicit(&job->next, memory_order_relaxed);
        do {
            if (index == job->limit) goto finished;
        } while (!atomic_compare_exchange_weak_explicit(&job->next, &index, index + 1,
                                                         memory_order_relaxed, memory_order_relaxed));
        job->fn(job->context, index);
    }

finished:
    d_dispatch_group_leave(job->group);
}

static void d_dispatch_apply_f(size_t count, struct dispatch_queue *queue, void *context,
                               void (*fn)(void *, size_t)) {
    if (!count) return;
    if (!queue) queue = dispatch_default_queue();
    size_t width = dispatch_apply_width(queue);
    if (!width) {
        for (size_t i = 0; i < count; ++i) fn(context, i);
        return;
    }
    if (width > count) width = count;
    struct dispatch_group *group = d_dispatch_group_create();
    struct apply_job job = { .group = group, .limit = count, .context = context, .fn = fn };
    for (size_t i = 0; i < width; ++i) d_dispatch_group_enter(group);
    dispatch_submit_batch(queue, &job, apply_worker, false, width);
    d_dispatch_group_wait(group, DISPATCH_FOREVER);
    dispatch_object_release(group);
}
DX_FN(dispatch_apply_f);

static void apply_block(void *arg, size_t index) {
    struct dx_block *block = arg;
    block->invoke(block, index);
}

static void d_dispatch_apply(size_t count, struct dispatch_queue *queue, void *block) {
    d_dispatch_apply_f(count, queue, block, apply_block);
}
DX_FN(dispatch_apply);

enum { BLOCK_HAS_COPY_DISPOSE = 1 << 25, BLOCK_HAS_SIGNATURE = 1 << 30 };
enum { DISPATCH_BLOCK_BARRIER = 1, DISPATCH_BLOCK_VALID_FLAGS = 0x3f };

struct dispatch_block_state {
    pthread_mutex_t lock;
    pthread_cond_t cond;
    struct dispatch_notices notices;
    void *block;
    unsigned long flags;
    bool canceled, done;
};

struct dispatch_block_literal {
    struct dx_block literal;
    struct dispatch_block_state *state;
};

static void block_copy(void *dst, const void *src) {
    ((struct dispatch_block_literal *)dst)->state = ((const struct dispatch_block_literal *)src)->state;
}

static void block_dispose(const void *arg) {
    struct dispatch_block_state *state = ((const struct dispatch_block_literal *)arg)->state;
    deliver_notices(state->notices.head, false);
    dx_block_release(state->block);
    pthread_cond_destroy(&state->cond);
    pthread_mutex_destroy(&state->lock);
    free(state);
}

static const struct {
    unsigned long reserved, size;
    void (*copy)(void *, const void *);
    void (*dispose)(const void *);
    const char *signature;
} block_descriptor = { 0, sizeof(struct dispatch_block_literal), block_copy, block_dispose, "v8@?0" };

static struct dispatch_block_state *block_state(const void *arg) {
    const struct dispatch_block_literal *block = arg;
    if (!block || block->literal.descriptor != &block_descriptor) return NULL;
    return block->state;
}

bool dispatch_block_is_barrier(const void *block) {
    struct dispatch_block_state *state = block_state(block);
    return state && (state->flags & DISPATCH_BLOCK_BARRIER);
}

static void block_invoke(void *arg, ...) {
    struct dispatch_block_state *state = block_state(arg);
    pthread_mutex_lock(&state->lock);
    bool canceled = state->canceled;
    pthread_mutex_unlock(&state->lock);
    if (!canceled) dispatch_invoke_block(state->block);

    struct dispatch_notice *ready = NULL;
    pthread_mutex_lock(&state->lock);
    if (!state->done) {
        state->done = true;
        ready = take_notices(&state->notices);
        pthread_cond_broadcast(&state->cond);
    }
    pthread_mutex_unlock(&state->lock);
    deliver_notices(ready, true);
}

static void *d_dispatch_block_create(unsigned long flags, const void *block) {
    if (!block || (flags & ~((unsigned long)DISPATCH_BLOCK_VALID_FLAGS))) return NULL;
    struct dispatch_block_state *state = dispatch_alloc(sizeof *state);
    pthread_mutex_init(&state->lock, NULL);
    pthread_cond_init(&state->cond, NULL);
    state->flags = flags;
    state->block = dispatch_copy_block(block);
    struct dispatch_block_literal wrapper = {
        .literal = { .isa = dx_registry_lookup("__NSConcreteStackBlock"),
                     .flags = BLOCK_HAS_COPY_DISPOSE | BLOCK_HAS_SIGNATURE,
                     .invoke = block_invoke, .descriptor = (void *)&block_descriptor },
        .state = state,
    };
    return dispatch_copy_block(&wrapper);
}
DX_FN(dispatch_block_create);

static void d_dispatch_block_perform(unsigned long flags, void *block) {
    (void)flags;
    dispatch_invoke_block(block);
}
DX_FN(dispatch_block_perform);

static struct dispatch_block_state *require_block(const void *block) {
    struct dispatch_block_state *state = block_state(block);
    if (!state) dx_fatal("dispatch: expected a block created by dispatch_block_create");
    return state;
}

static void d_dispatch_block_cancel(const void *block) {
    struct dispatch_block_state *state = require_block(block);
    pthread_mutex_lock(&state->lock);
    state->canceled = true;
    pthread_mutex_unlock(&state->lock);
}
DX_FN(dispatch_block_cancel);

static long d_dispatch_block_testcancel(const void *block) {
    struct dispatch_block_state *state = require_block(block);
    pthread_mutex_lock(&state->lock);
    bool canceled = state->canceled;
    pthread_mutex_unlock(&state->lock);
    return canceled;
}
DX_FN(dispatch_block_testcancel);

static long d_dispatch_block_wait(const void *block, uint64_t when) {
    struct dispatch_block_state *state = require_block(block);
    pthread_mutex_lock(&state->lock);
    while (!state->done && dispatch_cond_wait(&state->cond, &state->lock, when) != ETIMEDOUT) {}
    bool timeout = !state->done;
    pthread_mutex_unlock(&state->lock);
    return timeout;
}
DX_FN(dispatch_block_wait);

static void d_dispatch_block_notify(const void *block, struct dispatch_queue *queue, const void *callback) {
    struct dispatch_block_state *state = require_block(block);
    void *copy = dispatch_copy_block(callback);
    pthread_mutex_lock(&state->lock);
    bool ready = state->done;
    if (!ready) notify(&state->notices, queue, copy, invoke_and_release, true);
    pthread_mutex_unlock(&state->lock);
    if (ready) dispatch_submit_batch(queue, copy, invoke_and_release, dispatch_block_is_barrier(copy), 1);
}
DX_FN(dispatch_block_notify);
