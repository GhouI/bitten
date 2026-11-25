/* Executors: where jobs run. See concurrency.h.
 *
 *   generic        {nil, 0}: our libdispatch's global concurrent queues
 *   main           {&_dispatch_main_q, main marker}: the main queue, drained
 *                  by dispatch_main or the application's run loop
 *   default actor  {actor, 0}: a FIFO of jobs inside the actor object,
 *                  drained one job at a time on the global queues
 *   custom         {object, SerialExecutor witness table}: the object's
 *                  enqueue, reached through a Swift helper in _Concurrency */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include "concurrency.h"

/* ---- libdispatch (exported by our own dispatch implementation) ------------------------------- */
typedef void (*dispatch_fn)(void *);
static struct {
    void (*async_f)(void *queue, void *ctx, dispatch_fn fn);
    void *(*get_global_queue)(long priority, unsigned long flags);
    void (*after_f)(uint64_t when, void *queue, void *ctx, dispatch_fn fn);
    uint64_t (*time)(uint64_t when, int64_t delta);
    void (*main)(void);
    void *main_queue;
} dq;
static pthread_once_t dq_once = PTHREAD_ONCE_INIT;

static void dq_init(void) {
    dq.async_f = dx_registry_lookup("_dispatch_async_f");
    dq.get_global_queue = dx_registry_lookup("_dispatch_get_global_queue");
    dq.after_f = dx_registry_lookup("_dispatch_after_f");
    dq.time = dx_registry_lookup("_dispatch_time");
    dq.main = dx_registry_lookup("_dispatch_main");
    void *(*get_main)(void) = dx_registry_lookup("_dispatch_get_main_queue");
    dq.main_queue = get_main();
    if (!dq.async_f || !dq.get_global_queue || !dq.after_f || !dq.time || !dq.main || !dq.main_queue)
        dx_fatal("concurrency: libdispatch entry points missing");
}
static void need_dispatch(void) { pthread_once(&dq_once, dq_init); }

void sw_concurrency_fatal(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fputs("Fatal error: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
    fflush(stderr);
    __builtin_trap();
}

static void d_swift_bitten_concurrencyFailure(intptr_t code) {
    switch (code) {
    case 1: sw_concurrency_fatal("Incorrect actor executor assumption");
    case 2: sw_concurrency_fatal("Call of deleted method");
    default: sw_concurrency_fatal("concurrency failure %ld", (long)code);
    }
}
DX_FN(swift_bitten_concurrencyFailure);

int sw_on_main_thread(void) { return syscall(SYS_gettid) == getpid(); }

uint8_t sw_job_priority(const sw_job *job) { return (uint8_t)(job->flags >> 8); }

static size_t d_swift_concurrency_jobPriority(sw_job *job) { return sw_job_priority(job); }
DX_FN(swift_concurrency_jobPriority);

/* ---- the main executor ------------------------------------------------------------------------
 * Its implementation word must be non-zero (zero means "default actor");
 * this marker stands where a SerialExecutor witness table would be. */
static const uintptr_t main_executor_marker[2] __attribute__((aligned(16)));

sw_executor sw_main_executor(void) {
    need_dispatch();
    return (sw_executor){dq.main_queue, (uintptr_t)main_executor_marker};
}
int sw_executor_is_main(sw_executor e) {
    return e.identity && (e.impl & ~(uintptr_t)SW_EXEC_KIND_MASK) == (uintptr_t)main_executor_marker;
}

static sw_executor d_swift_task_getMainExecutor(void) { return sw_main_executor(); }
DX_FN(swift_task_getMainExecutor);
static bool d_swift_task_isMainExecutor(sw_executor e) { return sw_executor_is_main(e); }
DX_FN(swift_task_isMainExecutor);
static sw_executor d_swift_bitten_genericExecutor(void) { return (sw_executor){0, 0}; }
DX_FN(swift_bitten_genericExecutor);

/* ---- running jobs ------------------------------------------------------------------------------ */
void sw_run_job(sw_job *job, sw_executor e) {
    sw_task *prev_task = sw_cur_task;
    sw_executor prev_exec = sw_cur_exec;
    sw_cur_exec = e;
    if ((job->flags & 0xff) == SW_JOB_KIND_TASK) {
        sw_task *t = (sw_task *)job;
        sw_cur_task = t;
        t->executor = e;
        ((sw_resume_fn)job->run)(t->resume_context);
    } else {
        sw_cur_task = NULL;
        ((sw_simple_job_fn)job->run)(job);
    }
    sw_cur_task = prev_task;
    sw_cur_exec = prev_exec;
}

static void d_swift_job_run(sw_job *job, sw_executor e) { sw_run_job(job, e); }
DX_FN(swift_job_run);
/* Task executors are not modelled: the job runs as on its serial executor. */
static void d_swift_job_run_on_task_executor(sw_job *job, sw_executor te) {
    sw_run_job(job, (sw_executor){0, 0});
}
DX_FN(swift_job_run_on_task_executor);
static void d_swift_job_run_on_serial_and_task_executor(sw_job *job, sw_executor se, sw_executor te) {
    sw_run_job(job, se);
}
DX_FN(swift_job_run_on_serial_and_task_executor);

static void run_on_generic(void *job) { sw_run_job(job, (sw_executor){0, 0}); }
static void run_on_main(void *job) { sw_run_job(job, sw_main_executor()); }

static long dispatch_qos(uint8_t p) {
    if (p > 0x19) return 0x21;
    if (p > 0x15) return 0x19;
    if (p > 0x11) return 0x15;
    if (p > 0x09) return 0x11;
    if (p > 0) return 0x09;
    return 0x15;
}

void sw_enqueue_global(sw_job *job) {
    need_dispatch();
    dq.async_f(dq.get_global_queue(dispatch_qos(sw_job_priority(job)), 0), job, run_on_generic);
}

static void enqueue_main(sw_job *job) {
    need_dispatch();
    dq.async_f(dq.main_queue, job, run_on_main);
}

/* ---- default actors -----------------------------------------------------------------------------
 * The 12 words after the object header (NumWords_DefaultActor) hold the
 * actor's lock and job queue. A scheduled actor has a drain pending or
 * running on the global queues and holds a reference to itself. */
struct actor_state {
    pthread_mutex_t lock;
    sw_job *head, *tail;
    int scheduled;
};
_Static_assert(sizeof(struct actor_state) <= 12 * sizeof(void *), "default actor storage");

static struct actor_state *actor_state(void *actor) {
    return (struct actor_state *)((char *)actor + sizeof(sw_heap_object));
}

#define ACTOR_BATCH 64

static void actor_drain(void *actor) {
    struct actor_state *s = actor_state(actor);
    sw_executor self = {actor, 0};
    for (int n = 0;; n++) {
        pthread_mutex_lock(&s->lock);
        sw_job *job = s->head;
        if (!job) {
            s->scheduled = 0;
            pthread_mutex_unlock(&s->lock);
            break;
        }
        if (n == ACTOR_BATCH) {
            /* let other work run; stay scheduled */
            pthread_mutex_unlock(&s->lock);
            need_dispatch();
            dq.async_f(dq.get_global_queue(dispatch_qos(sw_job_priority(job)), 0), actor, actor_drain);
            return;
        }
        s->head = job->next;
        if (!s->head) s->tail = NULL;
        pthread_mutex_unlock(&s->lock);
        job->next = NULL;
        sw_run_job(job, self);
    }
    sw_release(actor);
}

static void actor_enqueue(void *actor, sw_job *job) {
    struct actor_state *s = actor_state(actor);
    job->next = NULL;
    pthread_mutex_lock(&s->lock);
    if (s->tail) s->tail->next = job;
    else s->head = job;
    s->tail = job;
    int start = !s->scheduled;
    s->scheduled = 1;
    pthread_mutex_unlock(&s->lock);
    if (start) {
        sw_retain(actor);
        need_dispatch();
        dq.async_f(dq.get_global_queue(dispatch_qos(sw_job_priority(job)), 0), actor, actor_drain);
    }
}

static void d_swift_defaultActor_initialize(void *actor) {
    struct actor_state *s = actor_state(actor);
    memset(s, 0, sizeof *s);
    pthread_mutex_init(&s->lock, NULL);
}
DX_FN(swift_defaultActor_initialize);
DX_EXPORT("_swift_nonDefaultDistributedActor_initialize", d_swift_defaultActor_initialize);

static void d_swift_defaultActor_destroy(void *actor) {
    pthread_mutex_destroy(&actor_state(actor)->lock);
}
DX_FN(swift_defaultActor_destroy);

static void d_swift_defaultActor_deallocate(void *actor) {
    void (*dealloc)(void *, size_t, size_t) =
        (void (*)(void *, size_t, size_t))dx_registry_lookup("_swift_deallocObject");
    const sw_class_metadata *m = *(const sw_class_metadata *const *)actor;
    dealloc(actor, m->instance_size, m->instance_align_mask);
}
DX_FN(swift_defaultActor_deallocate);
DX_EXPORT("_swift_defaultActor_deallocateResilient", d_swift_defaultActor_deallocate);

static void d_swift_defaultActor_enqueue(sw_job *job, void *actor) { actor_enqueue(actor, job); }
DX_FN(swift_defaultActor_enqueue);

static bool d_swift_distributed_actor_is_remote(void *actor) { return false; }
DX_FN(swift_distributed_actor_is_remote);

/* ---- custom executors (Swift) --------------------------------------------------------------------
 * Helpers in _Concurrency, generic over the executor type: (job, executor,
 * its type, its SerialExecutor witness table). Plain registers both ways. */
typedef void (*enqueue_on_fn)(sw_job *job, void *executor, const sw_metadata *type, const void *wt);
typedef void (*check_isolated_fn)(void *executor, const sw_metadata *type, const void *wt);

static const sw_metadata *object_type(void *obj) {
    const sw_metadata *(*get)(void *) = dx_registry_lookup("_swift_getObjectType");
    return get(obj);
}

static void *swift_helper(const char *name) {
    void *fn = dx_global_lookup(name);
    if (!fn) sw_concurrency_fatal("concurrency: %s not found (is libswift_Concurrency loaded?)", name + 1);
    return fn;
}

static void enqueue_custom(sw_job *job, sw_executor e) {
    static enqueue_on_fn fn;
    if (!fn) fn = swift_helper("__swift_task_enqueueOnExecutor");
    fn(job, e.identity, object_type(e.identity), (const void *)(e.impl & ~(uintptr_t)SW_EXEC_KIND_MASK));
}

void sw_enqueue(sw_job *job, sw_executor e) {
    if (!e.identity) sw_enqueue_global(job);
    else if (!e.impl) actor_enqueue(e.identity, job);
    else if (sw_executor_is_main(e)) enqueue_main(job);
    else enqueue_custom(job, e);
}

static void d_swift_task_enqueue(sw_job *job, sw_executor e) { sw_enqueue(job, e); }
DX_FN(swift_task_enqueue);
static void d_swift_task_enqueueGlobal(sw_job *job) { sw_enqueue_global(job); }
DX_FN(swift_task_enqueueGlobal);
static void d_swift_task_enqueueMainExecutor(sw_job *job) { enqueue_main(job); }
DX_FN(swift_task_enqueueMainExecutor);
static void d_swift_task_enqueueTaskOnExecutor(sw_task *t, sw_executor e) { sw_enqueue(&t->job, e); }
DX_FN(swift_task_enqueueTaskOnExecutor);
static void d_swift_bitten_enqueueTaskOnMain(sw_task *t) { enqueue_main(&t->job); }
DX_FN(swift_bitten_enqueueTaskOnMain);

static void d_swift_task_enqueueGlobalWithDelay(uint64_t delay, sw_job *job) {
    need_dispatch();
    dq.after_f(dq.time(0, (int64_t)delay), dq.get_global_queue(dispatch_qos(sw_job_priority(job)), 0),
               job, run_on_generic);
}
DX_FN(swift_task_enqueueGlobalWithDelay);

/* swift_clock_id: 1 continuous (counts while asleep), 2 suspending */
static clockid_t clock_of(int clock) { return clock == 1 ? CLOCK_BOOTTIME : CLOCK_MONOTONIC; }

static void d_swift_task_enqueueGlobalWithDeadline(long long sec, long long nsec, long long tsec,
                                                   long long tnsec, int clock, sw_job *job) {
    struct timespec now;
    clock_gettime(clock_of(clock), &now);
    long long delta = (sec - now.tv_sec) * 1000000000LL + (nsec - now.tv_nsec);
    d_swift_task_enqueueGlobalWithDelay(delta > 0 ? (uint64_t)delta : 0, job);
}
DX_FN(swift_task_enqueueGlobalWithDeadline);

static void d_swift_get_time(long long *sec, long long *nsec, int clock) {
    struct timespec ts;
    if (clock == 3) clock_gettime(CLOCK_REALTIME, &ts);
    else clock_gettime(clock_of(clock), &ts);
    *sec = ts.tv_sec;
    *nsec = ts.tv_nsec;
}
DX_FN(swift_get_time);

static void d_swift_get_clock_res(long long *sec, long long *nsec, int clock) {
    struct timespec ts;
    clock_getres(clock == 3 ? CLOCK_REALTIME : clock_of(clock), &ts);
    *sec = ts.tv_sec;
    *nsec = ts.tv_nsec;
}
DX_FN(swift_get_clock_res);

/* Simple jobs for the runtime's own deferred work. */
struct call_job {
    sw_job job;
    void (*fn)(void *);
    void *arg;
};
static struct {
    sw_heap_metadata_header header;
    uintptr_t kind;
} job_metadata = {{NULL, NULL, &sw_vwt_native_object}, SW_KIND_JOB};

static void run_call_job(sw_job *job) {
    struct call_job *c = (struct call_job *)job;
    void (*fn)(void *) = c->fn;
    void *arg = c->arg;
    free(c);
    fn(arg);
}

void sw_schedule_call(void (*fn)(void *), void *arg, uint64_t delay_ns) {
    struct call_job *c = calloc(1, sizeof *c);
    c->job.metadata = (const sw_metadata *)&job_metadata.kind;
    c->job.flags = SW_JOB_KIND_PRIVATE | (0x15u << 8);
    c->job.run = (void *)run_call_job;
    c->fn = fn;
    c->arg = arg;
    if (delay_ns) d_swift_task_enqueueGlobalWithDelay(delay_ns, &c->job);
    else sw_enqueue_global(&c->job);
}

/* ---- the async main entry ------------------------------------------------------------------------ */
static void d_swift_task_asyncMainDrainQueue(void) {
    need_dispatch();
    dq.main();
    __builtin_unreachable();
}
DX_FN(swift_task_asyncMainDrainQueue);

/* Runs the global executor's queues from this thread: they already run on
 * their own threads, so this just waits. */
static void d_swift_task_drainGlobalExecutor(void) { d_swift_task_asyncMainDrainQueue(); }
DX_FN(swift_task_drainGlobalExecutor);

/* ---- where are we? ------------------------------------------------------------------------------- */
static sw_executor d_swift_task_getCurrentExecutor(void) {
    if (!sw_cur_exec.identity && !sw_cur_task && sw_on_main_thread()) return sw_main_executor();
    return sw_cur_exec;
}
DX_FN(swift_task_getCurrentExecutor);

static int is_current(sw_executor e) {
    if (e.identity == sw_cur_exec.identity) return 1;
    /* code running on the main thread outside any job is on the main actor */
    if (sw_executor_is_main(e) && sw_on_main_thread() && !sw_cur_exec.identity) return 1;
    return 0;
}

static bool d_swift_task_isCurrentExecutor(sw_executor e) { return is_current(e); }
DX_FN(swift_task_isCurrentExecutor);
static bool d_swift_task_isCurrentExecutorWithFlags(sw_executor e, uint64_t flags) {
    return is_current(e);
}
DX_FN(swift_task_isCurrentExecutorWithFlags);

static bool d_swift_task_isOnExecutor(void *executor, const sw_metadata *type, const void *wt) {
    return is_current((sw_executor){executor, (uintptr_t)wt});
}
DX_FN(swift_task_isOnExecutor);

static bool d_swift_executor_isComplexEquality(sw_executor e) {
    return (e.impl & SW_EXEC_KIND_MASK) == SW_EXEC_COMPLEX_EQUALITY;
}
DX_FN(swift_executor_isComplexEquality);

static void d_swift_task_checkIsolated(sw_executor e) {
    if (is_current(e)) return;
    if (e.identity && e.impl && !sw_executor_is_main(e)) {
        /* a custom executor may know better (checkIsolated crashes if not) */
        static check_isolated_fn fn;
        if (!fn) fn = swift_helper("__task_serialExecutor_checkIsolated");
        fn(e.identity, object_type(e.identity), (const void *)(e.impl & ~(uintptr_t)SW_EXEC_KIND_MASK));
        return;
    }
    sw_concurrency_fatal("Incorrect actor executor assumption");
}
DX_FN(swift_task_checkIsolated);

static int8_t d_swift_task_isIsolatingCurrentContext(sw_executor e) { return is_current(e) ? 1 : -1; }
DX_FN(swift_task_isIsolatingCurrentContext);

/* A synchronous actor-isolated function was called off its actor. As
 * macOS does for programs built in Swift 5 mode, warn and carry on. */
static void d_swift_task_reportUnexpectedExecutor(const char *file, uintptr_t len, bool ascii,
                                                  uintptr_t line, sw_executor e) {
    const char *what = sw_executor_is_main(e) ? "@MainActor function" : "actor-isolated function";
    fprintf(stderr, "warning: data race detected: %s at %.*s:%lu was not called on the %s\n", what,
            (int)len, file, (unsigned long)line,
            sw_executor_is_main(e) ? "main thread" : "same actor");
}
DX_FN(swift_task_reportUnexpectedExecutor);

static size_t d_swift_task_getCurrentThreadPriority(void) { return sw_on_main_thread() ? 0x21 : 0x15; }
DX_FN(swift_task_getCurrentThreadPriority);

/* Calls fn(ctx) on a global queue after `ns` nanoseconds (Task.sleep). */
static void d_bitten_after_f(uint64_t ns, void *ctx, void (*fn)(void *)) {
    need_dispatch();
    dq.after_f(dq.time(0, (int64_t)ns), dq.get_global_queue(0, 0), ctx, fn);
}
DX_EXPORT("_bitten_concurrency_after_f", d_bitten_after_f);
