/* bitten's Swift concurrency runtime (libswift_Concurrency's C half).
 *
 *   task.c      tasks: creation, the task allocator, futures, cancellation,
 *               continuations, task-local values, swift_task_switch
 *   executor.c  executors: the global concurrent executor and the main
 *               executor on our libdispatch, default actors, custom
 *               executors written in Swift, timers
 *   group.c     task groups and async let
 *
 * The Swift half is overlays/_Concurrency. Async functions use the
 * swiftasync convention: the async context in r14, `self`/error in r13,
 * every call in return position a guaranteed tail call. gcc cannot emit
 * it, so this directory is built with clang (see the Makefile), and the
 * functions with that convention are marked SW_ASYNC.
 *
 * Layouts compiled code depends on (checked against swiftc 6.3 output,
 * see tests/swiftlib/async*):
 *   - a Job is a heap object {metadata, refcounts}, two scheduler words,
 *     32-bit flags and id, voucher, reserved, then the run function: 64
 *     bytes. A task continues with its resume context at offset 64, which
 *     compiled code reads to find a continuation's context.
 *   - an async context begins {parent, resume function}; a continuation
 *     context continues {flags, await state, error, result pointer,
 *     executor (2 words)}.
 *   - executor references are two words {identity, implementation}.
 * Everything after the first 80 bytes of a task is ours. */
#ifndef BITTEN_CONCURRENCY_H
#define BITTEN_CONCURRENCY_H
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "dx.h"
#include "../swift/swift_internal.h"

#define SW_ASYNC __attribute__((swiftasynccall))
#define SW_ACTX __attribute__((swift_async_context))
#define SW_SELF __attribute__((swift_context))
#define SW_CALL __attribute__((swiftcall))

typedef struct sw_actx sw_actx;
typedef SW_ASYNC void (*sw_resume_fn)(sw_actx *ctx SW_ACTX);
typedef SW_ASYNC void (*sw_throw_resume_fn)(sw_actx *ctx SW_ACTX, void *error SW_SELF);

struct sw_actx {
    sw_actx *parent;
    void *resume_parent; /* a sw_resume_fn or sw_throw_resume_fn */
};

typedef struct {
    void *identity;      /* NULL: the generic executor */
    uintptr_t impl;      /* SerialExecutor witness table | kind bits; 0: default actor */
} sw_executor;

enum {
    SW_EXEC_KIND_MASK = 7,
    SW_EXEC_COMPLEX_EQUALITY = 1,
};

/* ContinuationAsyncContext */
typedef struct {
    sw_actx base;
    size_t flags;                 /* bit 0: can throw */
    _Atomic size_t await_state;   /* SW_CONT_* */
    void *error;                  /* SwiftError*, +1 */
    void *result;                 /* where the resumer stores the value */
    sw_executor resume_executor;
} sw_cont_ctx;
enum { SW_CONT_PENDING = 0, SW_CONT_AWAITED = 1, SW_CONT_RESUMED = 2 };
enum {
    SW_CONTF_CAN_THROW = 1 << 0,
    SW_CONTF_EXECUTOR_OVERRIDE = 1 << 1,
    SW_CONTF_PREAWAITED = 1 << 2,
    SW_CONTF_FORCE_SWITCH = 1 << 3,
};

/* JobFlags */
enum {
    SW_JOB_KIND_TASK = 0,
    SW_JOB_KIND_PRIVATE = 192, /* our own simple jobs */
    SW_JOBF_CHILD = 1u << 24,
    SW_JOBF_FUTURE = 1u << 25,
    SW_JOBF_GROUP_CHILD = 1u << 26,
    SW_JOBF_ASYNC_LET = 1u << 28,
};

/* TaskCreateFlags */
enum {
    SW_TCF_PRIORITY_MASK = 0xff,
    SW_TCF_CHILD = 1 << 8,
    SW_TCF_COPY_LOCALS = 1 << 10,
    SW_TCF_INHERIT_CONTEXT = 1 << 11,
    SW_TCF_ENQUEUE = 1 << 12,
    SW_TCF_ADD_PENDING_UNCONDITIONALLY = 1 << 13,
    SW_TCF_DISCARDING = 1 << 14,
    SW_TCF_FUNCTION_CONSUMED = 1 << 15,
    SW_TCF_IMMEDIATE = 1 << 16,
};

/* TaskOptionRecordKind */
enum {
    SW_OPT_INITIAL_EXECUTOR = 0,
    SW_OPT_GROUP = 1,
    SW_OPT_ASYNC_LET_WITH_BUFFER = 3,
    SW_OPT_TASK_EXECUTOR_UNOWNED = 5,
    SW_OPT_TASK_EXECUTOR_OWNED = 6,
    SW_OPT_TASK_NAME = 7,
};
typedef struct sw_option {
    size_t flags; /* low byte: kind */
    struct sw_option *parent;
    void *payload[2];
} sw_option;

typedef struct sw_job sw_job;
typedef void (*sw_simple_job_fn)(sw_job *job);

struct sw_job {
    const sw_metadata *metadata;
    uint64_t refcounts;
    sw_job *next;          /* SchedulerPrivate[0]: queue links */
    void *sched1;          /* SchedulerPrivate[1] */
    uint32_t flags;
    uint32_t id;
    void *voucher;
    void *reserved;
    void *run;             /* task: sw_resume_fn; other jobs: sw_simple_job_fn */
};
_Static_assert(sizeof(struct sw_job) == 64, "Job is 8 words");
_Static_assert(offsetof(struct sw_job, id) == 36, "Job id offset");

struct sw_group;
struct sw_local;
struct sw_cancel_record;

typedef struct sw_task sw_task;
struct sw_task {
    struct sw_job job;
    sw_actx *resume_context;      /* offset 64, read by compiled code */
    void *reserved64;
    /* ---- private ---- */
    pthread_mutex_t lock;
    _Atomic uint32_t status;      /* SW_TS_* */
    uint8_t base_priority;
    uint8_t max_priority;
    sw_executor executor;         /* where the task runs, set by swift_job_run */
    sw_task *parent;              /* structured children: async let, groups */
    sw_task *first_child;
    sw_task *next_sibling;
    struct sw_group *group;       /* group of a group child */
    struct sw_cancel_record *records;
    struct sw_local *locals;
    /* task allocator */
    struct sw_slab *slab;
    /* future */
    const sw_metadata *result_type;
    void *result;                 /* the value, inside the task allocation */
    void *error;                  /* SwiftError*, +1, when the task threw */
    sw_task *waiters;             /* tasks waiting on this one, linked by wait_next */
    void *closure_context;        /* released when the task finishes (unless consumed) */
    int release_closure;
    int async_let;                /* owned by an async let: not reference counted by it */
    /* while this task waits */
    void *wait_dest;              /* where the awaited value goes */
    sw_task *wait_next;
    void *wait_resume;            /* the waiter's own continuation function */
    void *wait_error;             /* error handed to a throwing continuation */
    int wait_throwing;
    void *wait_scratch;           /* runtime continuations' own state */
};

enum {
    SW_TS_CANCELLED = 1 << 0,
    SW_TS_COMPLETE = 1 << 1,
    SW_TS_ERROR = 1 << 2,
    SW_TS_RUNNING = 1 << 3,
};

/* ---- task.c --------------------------------------------------------------- */
extern __thread sw_task *sw_cur_task;
extern __thread sw_executor sw_cur_exec;
sw_task *sw_task_create_with(size_t flags, sw_option *options, const sw_metadata *result_type,
                             const void *afp, void *closure, void *async_let);
void sw_task_add_child(sw_task *parent, sw_task *child);
void sw_task_remove_child(sw_task *parent, sw_task *child);
void sw_task_cancel(sw_task *t);
/* Resumes `t`, which waits on a value: the value or error is already in
 * place. Throwing waits get `error` (+1) in their error register. */
void sw_task_resume_waiter(sw_task *t, void *error);
/* Copies a completed future's outcome into its waiter; returns the error
 * (+1) if it threw. With no destination, only waits: nothing is copied. */
void *sw_task_deliver(sw_task *future, void *dest);
SW_ASYNC void swift_task_future_wait(void *result, sw_actx *caller SW_ACTX, sw_task *task,
                                     sw_resume_fn resume, sw_actx *call_ctx);
SW_ASYNC void swift_task_future_wait_throwing(void *result, sw_actx *caller SW_ACTX, sw_task *task,
                                              sw_throw_resume_fn resume, sw_actx *call_ctx);

/* ---- executor.c ----------------------------------------------------------- */
void sw_enqueue(sw_job *job, sw_executor e);
void sw_enqueue_global(sw_job *job);
void sw_run_job(sw_job *job, sw_executor e);
int sw_executor_is_main(sw_executor e);
sw_executor sw_main_executor(void);
int sw_on_main_thread(void);
/* Enqueue a simple job that calls fn(arg) on the global executor, after
 * `delay_ns` (0: now). */
void sw_schedule_call(void (*fn)(void *), void *arg, uint64_t delay_ns);
uint8_t sw_job_priority(const sw_job *job);
void sw_concurrency_fatal(const char *fmt, ...) __attribute__((noreturn, format(printf, 1, 2)));

/* ---- group.c ------------------------------------------------------------- */
void sw_group_child_completed(struct sw_group *g, sw_task *child);
void sw_group_attach(struct sw_group *g, sw_task *child, int unconditionally);
void sw_group_cancel(struct sw_group *g);

#endif
