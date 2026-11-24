#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <unistd.h>

#include "dx_dispatch.h"
#include "internal.h"

enum { AUTORELEASE_INHERIT, AUTORELEASE_WORK_ITEM, AUTORELEASE_NEVER };

struct dispatch_attr {
    struct dispatch_object object;
    bool concurrent, inactive;
    unsigned qos, autorelease;
    int relative;
    struct dispatch_attr *next;
};

struct dispatch_specific {
    struct dispatch_specific *next;
    const void *key;
    void *value;
    dispatch_function destroy;
};

struct dispatch_task {
    struct dispatch_task *next;
    uint64_t order;
    dispatch_function fn;
    void *context;
    bool barrier, skip_autorelease;
};

struct dispatch_queue {
    struct dispatch_object object;
    const char *label;
    struct dispatch_queue *target;
    struct dispatch_task *head, *tail;
    struct dispatch_queue *pending_next;
    struct dispatch_specific *specifics;
    size_t running;
    unsigned suspended, qos, autorelease;
    int relative;
    bool concurrent, barrier_running, inactive;
};

struct dispatch_execution {
    struct dispatch_execution *previous;
    struct dispatch_queue **chain;
    size_t count;
};

static struct dispatch_attr concurrent_attr = {
    .object = DISPATCH_STATIC_OBJECT(DISPATCH_ATTR), .concurrent = true,
};
static struct dispatch_queue main_queue = {
    .object = DISPATCH_STATIC_OBJECT(DISPATCH_QUEUE), .label = "com.apple.main-thread",
    .qos = 0x21, .autorelease = AUTORELEASE_WORK_ITEM,
};
static struct dispatch_queue global_queues[] = {
    { .object = DISPATCH_STATIC_OBJECT(DISPATCH_QUEUE), .label = "com.apple.root.user-interactive-qos",
      .qos = 0x21, .concurrent = true },
    { .object = DISPATCH_STATIC_OBJECT(DISPATCH_QUEUE), .label = "com.apple.root.user-initiated-qos",
      .qos = 0x19, .concurrent = true },
    { .object = DISPATCH_STATIC_OBJECT(DISPATCH_QUEUE), .label = "com.apple.root.default-qos",
      .qos = 0x15, .concurrent = true },
    { .object = DISPATCH_STATIC_OBJECT(DISPATCH_QUEUE), .label = "com.apple.root.utility-qos",
      .qos = 0x11, .concurrent = true },
    { .object = DISPATCH_STATIC_OBJECT(DISPATCH_QUEUE), .label = "com.apple.root.background-qos",
      .qos = 0x09, .concurrent = true },
};

DX_EXPORT("_dispatch_queue_attr_concurrent", &concurrent_attr);
DX_EXPORT("_dispatch_main_q", &main_queue);
/* The C names of these objects also carry a leading underscore. */
DX_EXPORT("__dispatch_queue_attr_concurrent", &concurrent_attr);
DX_EXPORT("__dispatch_main_q", &main_queue);

static pthread_mutex_t scheduler_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t metadata_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t attr_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t worker_cond = PTHREAD_COND_INITIALIZER;
static pthread_once_t scheduler_once = PTHREAD_ONCE_INIT;
static struct dispatch_queue *pending_queues;
static struct dispatch_attr *attrs;
static uint64_t last_order;
static size_t worker_count, idle_workers, worker_limit;
static int main_fd = -1;
static bool main_signaled;
static _Thread_local struct dispatch_execution *current_execution;

static void d_dispatch_retain(void *arg);
static void d_dispatch_release(void *arg);
static void *retain_for_objc(void *arg) {
    d_dispatch_retain(arg);
    return arg;
}

void *dispatch_alloc(size_t size) {
    void *p = calloc(1, size);
    if (!p) dx_fatal("dispatch: allocation failed");
    return p;
}

void *dispatch_copy_block(const void *block) {
    void *copy = dx_block_copy(block);
    if (block && !copy) dx_fatal("dispatch: block copy failed");
    return copy;
}

void dispatch_invoke_block(void *arg) {
    struct dx_block *block = arg;
    block->invoke(block);
}

static void invoke_and_release(void *block) {
    dispatch_invoke_block(block);
    dx_block_release(block);
}

void *dispatch_object_class(const char *name, const char *super) {
    if (!dx_os_object_class) return NULL;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static struct { const char *name; void *isa; } cache[12];
    pthread_mutex_lock(&lock);
    size_t slot = 0;
    while (slot < sizeof cache / sizeof *cache && cache[slot].name &&
           strcmp(cache[slot].name, name) != 0) ++slot;
    if (slot == sizeof cache / sizeof *cache) dx_fatal("dispatch: too many object classes");
    if (!cache[slot].name) {
        cache[slot].name = name;
        cache[slot].isa = dx_os_object_class(name, super, retain_for_objc, d_dispatch_release);
    }
    void *isa = cache[slot].isa;
    pthread_mutex_unlock(&lock);
    return isa;
}

void dispatch_object_init(struct dispatch_object *object, enum dispatch_kind kind,
                          const char *class_name, const char *super_name,
                          void (*dispose)(struct dispatch_object *)) {
    object->isa = dispatch_object_class(class_name, super_name);
    atomic_init(&object->refs, 1);
    object->kind = kind;
    object->dispose = dispose;
    atomic_init(&object->context, NULL);
    atomic_init(&object->finalizer, NULL);
}

void dispatch_object_retain(void *arg) {
    struct dispatch_object *object = arg;
    if (object && atomic_load_explicit(&object->refs, memory_order_relaxed) != UINT_MAX)
        atomic_fetch_add_explicit(&object->refs, 1, memory_order_relaxed);
}

void dispatch_object_release(void *arg) {
    struct dispatch_object *object = arg;
    if (!object || atomic_load_explicit(&object->refs, memory_order_relaxed) == UINT_MAX ||
        atomic_fetch_sub_explicit(&object->refs, 1, memory_order_acq_rel) != 1) return;

    void *context = atomic_load_explicit(&object->context, memory_order_relaxed);
    dispatch_function finalizer = atomic_load_explicit(&object->finalizer, memory_order_relaxed);
    struct dispatch_queue *target = object->finalizer_queue;
    object->dispose(object);
    free(object);
    if (context && finalizer) dispatch_submit(target ? target : dispatch_default_queue(), context, finalizer);
    dispatch_object_release(target);
}

static void d_dispatch_retain(void *arg) {
    struct dispatch_object *object = arg;
    dispatch_object_retain(object);
    if (object && object->kind == DISPATCH_SOURCE) dispatch_source_public_retain(object);
}
DX_FN(dispatch_retain);

static void d_dispatch_release(void *arg) {
    struct dispatch_object *object = arg;
    if (object && object->kind == DISPATCH_SOURCE) dispatch_source_public_release(object);
    dispatch_object_release(object);
}
DX_FN(dispatch_release);

static void d_dispatch_set_context(struct dispatch_object *object, void *context) {
    if (atomic_load_explicit(&object->refs, memory_order_relaxed) != UINT_MAX)
        atomic_store_explicit(&object->context, context, memory_order_relaxed);
}
DX_FN(dispatch_set_context);

static void *d_dispatch_get_context(struct dispatch_object *object) {
    return atomic_load_explicit(&object->context, memory_order_relaxed);
}
DX_FN(dispatch_get_context);

static void d_dispatch_set_finalizer_f(struct dispatch_object *object, dispatch_function fn) {
    if (atomic_load_explicit(&object->refs, memory_order_relaxed) != UINT_MAX)
        atomic_store_explicit(&object->finalizer, fn, memory_order_relaxed);
}
DX_FN(dispatch_set_finalizer_f);

int dispatch_start_thread(void *(*fn)(void *), void *context) {
    int (*create)(void **, void *, void *(*)(void *), void *) = dx_registry_lookup("_pthread_create");
    int (*detach)(void *) = dx_registry_lookup("_pthread_detach");
    if (!create || !detach) dx_fatal("dispatch: Darwin pthreads are unavailable");
    void *thread;
    int error = create(&thread, NULL, fn, context);
    if (!error && detach(thread)) dx_fatal("dispatch: pthread_detach failed");
    return error;
}

static bool on_main_thread(void) {
    return getpid() == gettid();
}

__attribute__((constructor(102))) static void init_queue_classes(void) {
    dispatch_object_class("OS_dispatch_object", NULL);
    dispatch_object_class("OS_dispatch_queue", "OS_dispatch_object");
    main_queue.object.isa = dispatch_object_class("OS_dispatch_queue_main", "OS_dispatch_queue");
    for (size_t i = 0; i < sizeof global_queues / sizeof *global_queues; ++i)
        global_queues[i].object.isa = dispatch_object_class("OS_dispatch_queue_global", "OS_dispatch_queue");
    concurrent_attr.object.isa = dispatch_object_class("OS_dispatch_queue_attr", "OS_dispatch_object");
}

static void scheduler_init(void) {
    long cpus = sysconf(_SC_NPROCESSORS_ONLN);
    worker_limit = cpus > 64 ? (size_t)cpus : 64;
    main_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (main_fd < 0) dx_fatal("dispatch: cannot create main queue eventfd: %s", strerror(errno));
}

static void ensure_scheduler(void) {
    pthread_once(&scheduler_once, scheduler_init);
}

struct dispatch_queue *dispatch_default_queue(void) {
    ensure_scheduler();
    return &global_queues[2];
}

static bool task_can_run(struct dispatch_queue *origin, struct dispatch_task *task, bool main) {
    if (task->barrier && origin->running) return false;
    bool uses_main = false;
    for (struct dispatch_queue *q = origin; q; q = q->target) {
        if (q->suspended || q->inactive || q->barrier_running || (!q->concurrent && q->running))
            return false;
        if (q->head && q->head->barrier && q->head->order < task->order) return false;
        if (q == &main_queue) uses_main = true;
    }
    return uses_main == main;
}

static struct dispatch_queue **select_queue(bool main) {
    struct dispatch_queue **best = NULL;
    uint64_t first = UINT64_MAX;
    /* Pick the oldest eligible head without moving work off a suspended origin or target. */
    for (struct dispatch_queue **p = &pending_queues; *p; p = &(*p)->pending_next) {
        struct dispatch_task *task = (*p)->head;
        if (task->order < first && task_can_run(*p, task, main)) {
            first = task->order;
            best = p;
        }
    }
    return best;
}

static void notify_main(void) {
    if (main_signaled) return;
    uint64_t one = 1;
    ssize_t n;
    do n = write(main_fd, &one, sizeof one); while (n < 0 && errno == EINTR);
    if (n != sizeof one && errno != EAGAIN) dx_fatal("dispatch: main queue wakeup failed");
    main_signaled = true;
}

static void *worker_main(void *arg);

static void scheduler_wake(void) {
    if (!main_signaled && select_queue(true)) notify_main();
    if (!select_queue(false)) return;
    if (idle_workers) {
        pthread_cond_signal(&worker_cond);
    } else if (worker_count < worker_limit) {
        ++worker_count;
        ++idle_workers;
        int error = dispatch_start_thread(worker_main, NULL);
        if (error) {
            --worker_count;
            --idle_workers;
            if (!worker_count) dx_fatal("dispatch: cannot start a worker (Darwin errno %d)", error);
        }
    }
}

static struct dispatch_task *claim_task(struct dispatch_queue **slot, struct dispatch_execution *run,
                                        struct dispatch_queue **storage, size_t capacity) {
    struct dispatch_queue *origin = *slot;
    struct dispatch_task *task = origin->head;
    origin->head = task->next;
    if (!origin->head) {
        origin->tail = NULL;
        *slot = origin->pending_next;
        origin->pending_next = NULL;
    }
    for (struct dispatch_queue *q = origin; q; q = q->target) ++run->count;
    run->chain = run->count <= capacity ? storage : dispatch_alloc(run->count * sizeof *storage);
    size_t i = 0;
    for (struct dispatch_queue *q = origin; q; q = q->target) {
        run->chain[i++] = q;
        ++q->running;
        if (q != origin) dispatch_object_retain(q);
    }
    origin->barrier_running = task->barrier;
    return task;
}

static void run_task(struct dispatch_queue **slot) {
    struct dispatch_queue *storage[8];
    struct dispatch_execution run = { .previous = current_execution };
    struct dispatch_task *task = claim_task(slot, &run, storage, sizeof storage / sizeof *storage);
    scheduler_wake();
    pthread_mutex_unlock(&scheduler_lock);

    current_execution = &run;
    unsigned autorelease = AUTORELEASE_INHERIT;
    for (size_t i = 0; i < run.count && !autorelease; ++i)
        autorelease = run.chain[i]->autorelease;
    void *(*pool_push)(void) = NULL;
    void (*pool_pop)(void *) = NULL;
    if (autorelease == AUTORELEASE_WORK_ITEM && !task->skip_autorelease) {
        pool_push = dx_registry_lookup("_objc_autoreleasePoolPush");
        pool_pop = dx_registry_lookup("_objc_autoreleasePoolPop");
    }
    void *pool = pool_push && pool_pop ? pool_push() : NULL;
    task->fn(task->context);
    if (pool_push && pool_pop) pool_pop(pool);
    current_execution = run.previous;

    pthread_mutex_lock(&scheduler_lock);
    run.chain[0]->barrier_running = false;
    for (size_t i = 0; i < run.count; ++i) --run.chain[i]->running;
    scheduler_wake();
    pthread_mutex_unlock(&scheduler_lock);

    for (size_t i = 0; i < run.count; ++i) dispatch_object_release(run.chain[i]);
    if (run.chain != storage) free(run.chain);
    free(task);
}

static void *worker_main(void *arg) {
    (void)arg;
    pthread_mutex_lock(&scheduler_lock);
    for (;;) {
        uint64_t expiry = dispatch_now(CLOCK_MONOTONIC) + 2 * DISPATCH_NSEC;
        struct dispatch_queue **slot;
        while (!(slot = select_queue(false))) {
            if (dispatch_cond_wait(&worker_cond, &scheduler_lock, expiry) == ETIMEDOUT &&
                !(slot = select_queue(false))) {
                --idle_workers;
                --worker_count;
                pthread_mutex_unlock(&scheduler_lock);
                return NULL;
            }
            if (slot) break;
        }
        --idle_workers;
        run_task(slot);
        pthread_mutex_lock(&scheduler_lock);
        ++idle_workers;
    }
}

static struct dispatch_task *new_task(struct dispatch_queue *queue, void *context,
                                      dispatch_function fn, bool barrier) {
    struct dispatch_task *task = dispatch_alloc(sizeof *task);
    task->fn = fn;
    task->context = context;
    task->barrier = barrier && queue->concurrent && queue->object.dispose;
    dispatch_object_retain(queue);
    return task;
}

static void enqueue_tasks(struct dispatch_queue *queue, struct dispatch_task *head,
                          struct dispatch_task *tail) {
    for (struct dispatch_task *task = head; task; task = task->next) task->order = ++last_order;
    if (queue->tail) {
        queue->tail->next = head;
    } else {
        queue->head = head;
        queue->pending_next = pending_queues;
        pending_queues = queue;
    }
    queue->tail = tail;
}

void dispatch_submit_batch(struct dispatch_queue *queue, void *context, dispatch_function fn,
                           bool barrier, size_t count) {
    if (!count) return;
    ensure_scheduler();
    struct dispatch_task *head = new_task(queue, context, fn, barrier), *tail = head;
    for (size_t i = 1; i < count; ++i) {
        tail->next = new_task(queue, context, fn, barrier);
        tail = tail->next;
    }
    pthread_mutex_lock(&scheduler_lock);
    enqueue_tasks(queue, head, tail);
    scheduler_wake();
    pthread_mutex_unlock(&scheduler_lock);
}

void dispatch_submit(struct dispatch_queue *queue, void *context, dispatch_function fn) {
    dispatch_submit_batch(queue, context, fn, false, 1);
}

static struct dispatch_queue *d_dispatch_get_global_queue(long priority, unsigned long flags) {
    if (flags) return NULL;
    ensure_scheduler();
    switch (priority) {
    case 0x21: return &global_queues[0];
    case 0x19: case 2: return &global_queues[1];
    case 0x15: case 0: return &global_queues[2];
    case 0x11: case -2: return &global_queues[3];
    case 0x09: case INT16_MIN: return &global_queues[4];
    default: return NULL;
    }
}
DX_FN(dispatch_get_global_queue);

static struct dispatch_queue *d_dispatch_get_main_queue(void) {
    ensure_scheduler();
    return &main_queue;
}
DX_FN(dispatch_get_main_queue);

static struct dispatch_queue *d_dispatch_get_current_queue(void) {
    if (current_execution) return current_execution->chain[0];
    return on_main_thread() ? d_dispatch_get_main_queue() : dispatch_default_queue();
}
DX_FN(dispatch_get_current_queue);

static void queue_dispose(struct dispatch_object *object) {
    struct dispatch_queue *queue = (struct dispatch_queue *)object;
    while (queue->specifics) {
        struct dispatch_specific *item = queue->specifics;
        queue->specifics = item->next;
        if (item->destroy) dispatch_submit(dispatch_default_queue(), item->value, item->destroy);
        free(item);
    }
    free((char *)queue->label);
}

static struct dispatch_queue *d_dispatch_queue_create_with_target(const char *label,
        const struct dispatch_attr *attr, struct dispatch_queue *target) {
    struct dispatch_queue *queue = dispatch_alloc(sizeof *queue);
    queue->concurrent = attr && attr->concurrent;
    queue->inactive = attr && attr->inactive;
    queue->qos = attr ? attr->qos : 0;
    queue->relative = attr ? attr->relative : 0;
    queue->autorelease = attr ? attr->autorelease : AUTORELEASE_INHERIT;
    queue->label = strdup(label ? label : "");
    if (!queue->label) dx_fatal("dispatch: queue label allocation failed");
    if (!target) target = queue->qos ? d_dispatch_get_global_queue(queue->qos, 0) : dispatch_default_queue();
    queue->target = target;
    queue->object.finalizer_queue = target;
    dispatch_object_retain(target);
    dispatch_object_init(&queue->object, DISPATCH_QUEUE,
                         queue->concurrent ? "OS_dispatch_queue_concurrent" : "OS_dispatch_queue_serial",
                         "OS_dispatch_queue", queue_dispose);
    return queue;
}
DX_FN(dispatch_queue_create_with_target);

static struct dispatch_queue *d_dispatch_queue_create(const char *label, const struct dispatch_attr *attr) {
    return d_dispatch_queue_create_with_target(label, attr, NULL);
}
DX_FN(dispatch_queue_create);

struct dispatch_queue *dispatch_private_queue(const char *label) {
    return d_dispatch_queue_create(label, &concurrent_attr);
}

static const char *d_dispatch_queue_get_label(struct dispatch_queue *queue) {
    return (queue ? queue : d_dispatch_get_current_queue())->label;
}
DX_FN(dispatch_queue_get_label);

static unsigned d_dispatch_queue_get_qos_class(struct dispatch_queue *queue, int *relative) {
    if (!queue) queue = d_dispatch_get_current_queue();
    pthread_mutex_lock(&scheduler_lock);
    while (!queue->qos && queue->target) queue = queue->target;
    unsigned qos = queue->qos;
    if (relative) *relative = queue->relative;
    pthread_mutex_unlock(&scheduler_lock);
    return qos;
}
DX_FN(dispatch_queue_get_qos_class);

static struct dispatch_attr *intern_attr(const struct dispatch_attr *value) {
    pthread_mutex_lock(&attr_lock);
    struct dispatch_attr *out;
    for (out = attrs; out; out = out->next) {
        if (out->concurrent == value->concurrent && out->inactive == value->inactive &&
            out->qos == value->qos && out->relative == value->relative &&
            out->autorelease == value->autorelease) break;
    }
    if (!out) {
        out = dispatch_alloc(sizeof *out);
        out->object.isa = concurrent_attr.object.isa;
        atomic_init(&out->object.refs, UINT_MAX);
        atomic_init(&out->object.context, NULL);
        atomic_init(&out->object.finalizer, NULL);
        out->object.kind = DISPATCH_ATTR;
        out->concurrent = value->concurrent;
        out->inactive = value->inactive;
        out->qos = value->qos;
        out->relative = value->relative;
        out->autorelease = value->autorelease;
        out->next = attrs;
        attrs = out;
    }
    pthread_mutex_unlock(&attr_lock);
    return out;
}

static struct dispatch_attr attr_value(const struct dispatch_attr *attr) {
    return attr ? (struct dispatch_attr) {
        .concurrent = attr->concurrent, .inactive = attr->inactive,
        .qos = attr->qos, .relative = attr->relative, .autorelease = attr->autorelease,
    } : (struct dispatch_attr){0};
}

static struct dispatch_attr *d_dispatch_queue_attr_make_with_qos_class(
        const struct dispatch_attr *attr, unsigned qos, int relative) {
    if (relative > 0 || relative < -15 || !d_dispatch_get_global_queue(qos, 0) ||
        qos < 0x09) return NULL;
    struct dispatch_attr value = attr_value(attr);
    value.qos = qos;
    value.relative = relative;
    return intern_attr(&value);
}
DX_FN(dispatch_queue_attr_make_with_qos_class);

static struct dispatch_attr *d_dispatch_queue_attr_make_with_autorelease_frequency(
        const struct dispatch_attr *attr, unsigned frequency) {
    if (frequency > 2) return NULL;
    struct dispatch_attr value = attr_value(attr);
    value.autorelease = frequency;
    return intern_attr(&value);
}
DX_FN(dispatch_queue_attr_make_with_autorelease_frequency);

static struct dispatch_attr *d_dispatch_queue_attr_make_initially_inactive(const struct dispatch_attr *attr) {
    struct dispatch_attr value = attr_value(attr);
    value.inactive = true;
    return intern_attr(&value);
}
DX_FN(dispatch_queue_attr_make_initially_inactive);

static void d_dispatch_set_target_queue(struct dispatch_object *object, struct dispatch_queue *target) {
    if (atomic_load_explicit(&object->refs, memory_order_relaxed) == UINT_MAX) return;
    if (object->kind == DISPATCH_SOURCE) {
        dispatch_source_set_target(object, target);
        return;
    }
    if (!target) target = dispatch_default_queue();
    dispatch_object_retain(target);

    struct dispatch_queue *previous;
    if (object->kind == DISPATCH_QUEUE) {
        struct dispatch_queue *queue = (struct dispatch_queue *)object;
        pthread_mutex_lock(&scheduler_lock);
        for (struct dispatch_queue *q = target; q; q = q->target)
            if (q == queue) dx_fatal("dispatch: target queue cycle for %s", queue->label);
        previous = queue->target;
        queue->target = target;
        queue->object.finalizer_queue = target;
        scheduler_wake();
        pthread_mutex_unlock(&scheduler_lock);
    } else {
        pthread_mutex_lock(&metadata_lock);
        previous = object->finalizer_queue;
        object->finalizer_queue = target;
        pthread_mutex_unlock(&metadata_lock);
    }
    dispatch_object_release(previous);
}
DX_FN(dispatch_set_target_queue);

static void control(struct dispatch_object *object, enum dispatch_control change) {
    if (object->kind == DISPATCH_SOURCE) {
        dispatch_source_control(object, change);
        return;
    }
    if (object->kind != DISPATCH_QUEUE ||
        atomic_load_explicit(&object->refs, memory_order_relaxed) == UINT_MAX) return;
    struct dispatch_queue *queue = (struct dispatch_queue *)object;
    pthread_mutex_lock(&scheduler_lock);
    if (change == DISPATCH_SUSPEND) {
        ++queue->suspended;
    } else if (change == DISPATCH_ACTIVATE) {
        queue->inactive = false;
    } else if (queue->suspended) {
        --queue->suspended;
    } else {
        dx_fatal("dispatch: unbalanced resume on %s", queue->label);
    }
    scheduler_wake();
    pthread_mutex_unlock(&scheduler_lock);
}

static void d_dispatch_suspend(struct dispatch_object *object) { control(object, DISPATCH_SUSPEND); }
static void d_dispatch_resume(struct dispatch_object *object) { control(object, DISPATCH_RESUME); }
static void d_dispatch_activate(struct dispatch_object *object) { control(object, DISPATCH_ACTIVATE); }
DX_FN(dispatch_suspend);
DX_FN(dispatch_resume);
DX_FN(dispatch_activate);

static struct dispatch_specific **specific_slot(struct dispatch_queue *queue, const void *key) {
    struct dispatch_specific **slot = &queue->specifics;
    while (*slot && (*slot)->key != key) slot = &(*slot)->next;
    return slot;
}

static void d_dispatch_queue_set_specific(struct dispatch_queue *queue, const void *key,
                                          void *value, dispatch_function destroy) {
    if (!key || (!queue->object.dispose && queue != &main_queue)) return;
    struct dispatch_specific *item = NULL;
    if (value) {
        item = dispatch_alloc(sizeof *item);
        item->key = key;
        item->value = value;
        item->destroy = destroy;
    }
    pthread_mutex_lock(&scheduler_lock);
    struct dispatch_specific **slot = specific_slot(queue, key);
    struct dispatch_specific *previous = *slot;
    if (item) {
        item->next = previous ? previous->next : NULL;
        *slot = item;
    } else if (previous) {
        *slot = previous->next;
    }
    pthread_mutex_unlock(&scheduler_lock);
    if (previous) {
        if (previous->destroy) dispatch_submit(dispatch_default_queue(), previous->value, previous->destroy);
        free(previous);
    }
}
DX_FN(dispatch_queue_set_specific);

static void *d_dispatch_queue_get_specific(struct dispatch_queue *queue, const void *key) {
    if (!key) return NULL;
    pthread_mutex_lock(&scheduler_lock);
    struct dispatch_specific *item = *specific_slot(queue, key);
    void *value = item ? item->value : NULL;
    pthread_mutex_unlock(&scheduler_lock);
    return value;
}
DX_FN(dispatch_queue_get_specific);

static void *d_dispatch_get_specific(const void *key) {
    if (!key) return NULL;
    if (!current_execution) {
        return on_main_thread() ? d_dispatch_queue_get_specific(&main_queue, key) : NULL;
    }
    pthread_mutex_lock(&scheduler_lock);
    void *value = NULL;
    for (size_t i = 0; i < current_execution->count; ++i) {
        struct dispatch_specific *item = *specific_slot(current_execution->chain[i], key);
        if (item) {
            value = item->value;
            break;
        }
    }
    pthread_mutex_unlock(&scheduler_lock);
    return value;
}
DX_FN(dispatch_get_specific);

static bool on_queue(struct dispatch_queue *queue) {
    for (struct dispatch_execution *run = current_execution; run; run = run->previous)
        for (size_t i = 0; i < run->count; ++i)
            if (run->chain[i] == queue) return true;
    return queue == &main_queue && on_main_thread();
}

static void d_dispatch_assert_queue(struct dispatch_queue *queue) {
    if (!on_queue(queue)) dx_fatal("dispatch: expected to run on %s", queue->label);
}
DX_FN(dispatch_assert_queue);

static void d_dispatch_assert_queue_not(struct dispatch_queue *queue) {
    if (on_queue(queue)) dx_fatal("dispatch: unexpectedly running on %s", queue->label);
}
DX_FN(dispatch_assert_queue_not);

static void d_dispatch_async_f(struct dispatch_queue *queue, void *context, dispatch_function fn) {
    dispatch_submit(queue, context, fn);
}
DX_FN(dispatch_async_f);

static void d_dispatch_async(struct dispatch_queue *queue, const void *block) {
    dispatch_submit_batch(queue, dispatch_copy_block(block), invoke_and_release,
                          dispatch_block_is_barrier(block), 1);
}
DX_FN(dispatch_async);

static void d_dispatch_barrier_async_f(struct dispatch_queue *queue, void *context, dispatch_function fn) {
    dispatch_submit_batch(queue, context, fn, true, 1);
}
DX_FN(dispatch_barrier_async_f);

static void d_dispatch_barrier_async(struct dispatch_queue *queue, const void *block) {
    dispatch_submit_batch(queue, dispatch_copy_block(block), invoke_and_release, true, 1);
}
DX_FN(dispatch_barrier_async);

struct sync_call {
    pthread_mutex_t lock;
    pthread_cond_t done_cond;
    bool done;
    dispatch_function fn;
    void *context;
};

static void sync_invoke(void *arg) {
    struct sync_call *call = arg;
    call->fn(call->context);
    pthread_mutex_lock(&call->lock);
    call->done = true;
    pthread_cond_signal(&call->done_cond);
    pthread_mutex_unlock(&call->lock);
}

static void check_sync(struct dispatch_queue *queue) {
    for (struct dispatch_queue *q = queue; q; q = q->target)
        if ((!q->concurrent || q->barrier_running || q == queue) && on_queue(q))
            dx_fatal("dispatch: synchronous submission would deadlock on %s", q->label);
}

size_t dispatch_apply_width(struct dispatch_queue *queue) {
    ensure_scheduler();
    pthread_mutex_lock(&scheduler_lock);
    size_t width = 1;
    if (queue->concurrent) {
        if (on_queue(queue)) {
            pthread_mutex_unlock(&scheduler_lock);
            return 0;
        }
        width = worker_limit < 32 ? worker_limit : 32;
    }
    check_sync(queue);
    pthread_mutex_unlock(&scheduler_lock);
    return width;
}

static void sync_submit(struct dispatch_queue *queue, void *context, dispatch_function fn,
                        bool barrier, bool async_and_wait) {
    ensure_scheduler();
    struct sync_call call = {
        .lock = PTHREAD_MUTEX_INITIALIZER, .done_cond = PTHREAD_COND_INITIALIZER,
        .fn = fn, .context = context,
    };
    struct dispatch_task *task = new_task(queue, &call, sync_invoke, barrier);
    task->skip_autorelease = !async_and_wait;

    pthread_mutex_lock(&scheduler_lock);
    check_sync(queue);
    enqueue_tasks(queue, task, task);
    struct dispatch_queue **slot = select_queue(false);
    if (slot && *slot == queue && queue->head == task) {
        run_task(slot);
    } else {
        scheduler_wake();
        pthread_mutex_unlock(&scheduler_lock);
    }

    pthread_mutex_lock(&call.lock);
    while (!call.done) pthread_cond_wait(&call.done_cond, &call.lock);
    pthread_mutex_unlock(&call.lock);
    pthread_cond_destroy(&call.done_cond);
    pthread_mutex_destroy(&call.lock);
}

static void d_dispatch_sync_f(struct dispatch_queue *queue, void *context, dispatch_function fn) {
    sync_submit(queue, context, fn, false, false);
}
DX_FN(dispatch_sync_f);

static void d_dispatch_sync(struct dispatch_queue *queue, void *block) {
    sync_submit(queue, block, dispatch_invoke_block, dispatch_block_is_barrier(block), false);
}
DX_FN(dispatch_sync);

static void d_dispatch_barrier_sync_f(struct dispatch_queue *queue, void *context, dispatch_function fn) {
    sync_submit(queue, context, fn, true, false);
}
DX_FN(dispatch_barrier_sync_f);

static void d_dispatch_barrier_sync(struct dispatch_queue *queue, void *block) {
    sync_submit(queue, block, dispatch_invoke_block, true, false);
}
DX_FN(dispatch_barrier_sync);

static void d_dispatch_async_and_wait_f(struct dispatch_queue *queue, void *context, dispatch_function fn) {
    sync_submit(queue, context, fn, false, true);
}
DX_FN(dispatch_async_and_wait_f);

static void d_dispatch_async_and_wait(struct dispatch_queue *queue, const void *block) {
    sync_submit(queue, dispatch_copy_block(block), invoke_and_release, dispatch_block_is_barrier(block), true);
}
DX_FN(dispatch_async_and_wait);

int dx_dispatch_main_fd(void) {
    ensure_scheduler();
    return main_fd;
}

void dx_dispatch_main_drain(void) {
    ensure_scheduler();
    pthread_mutex_lock(&scheduler_lock);
    struct dispatch_queue **slot;
    while ((slot = select_queue(true))) {
        run_task(slot);
        pthread_mutex_lock(&scheduler_lock);
    }
    if (main_signaled) {
        uint64_t value;
        ssize_t result;
        do result = read(main_fd, &value, sizeof value); while (result < 0 && errno == EINTR);
        main_signaled = false;
    }
    pthread_mutex_unlock(&scheduler_lock);
}

static void d__dispatch_main_queue_callback_4CF(void *unused) {
    (void)unused;
    dx_dispatch_main_drain();
}
DX_FN(_dispatch_main_queue_callback_4CF);

static void d_dispatch_main(void) {
    if (!on_main_thread()) dx_fatal("dispatch_main: must be called on the main thread");
    struct pollfd wake = { .fd = dx_dispatch_main_fd(), .events = POLLIN };
    for (;;) {
        if (poll(&wake, 1, -1) < 0 && errno != EINTR)
            dx_fatal("dispatch_main: poll failed: %s", strerror(errno));
        dx_dispatch_main_drain();
    }
}
DX_FN(dispatch_main);
