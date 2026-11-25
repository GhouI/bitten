/* Tasks: creation, the task allocator, futures, cancellation, continuations,
 * task-local values and executor switching. See concurrency.h. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "concurrency.h"

__thread sw_task *sw_cur_task;
__thread sw_executor sw_cur_exec;

static size_t align_up(size_t n, size_t a) { return (n + a - 1) & ~(a - 1); }
static const sw_vwt *vwt_of(const sw_metadata *m) { return ((const sw_vwt *const *)m)[-1]; }

static void task_lock(sw_task *t) { pthread_mutex_lock(&t->lock); }
static void task_unlock(sw_task *t) { pthread_mutex_unlock(&t->lock); }

/* ---- the task allocator ------------------------------------------------------------------
 * Async frames are allocated and freed in strict LIFO order per task
 * (swift_task_alloc/dealloc), so each task bump-allocates from a chain of
 * slabs. Every block has a 16-byte header recording its slab and the
 * slab's previous fill level. Outside a task, plain malloc. */
struct sw_slab {
    struct sw_slab *prev;
    size_t capacity;
    size_t used;
    sw_task *owner;
    char data[];
};
struct block_header {
    struct sw_slab *slab; /* NULL: malloc */
    size_t prev_used;
};
#define SLAB_SIZE (16 * 1024)

static void *task_alloc(sw_task *t, size_t size) {
    size = align_up(size ? size : 1, 16) + sizeof(struct block_header);
    struct sw_slab *s = t->slab;
    if (!s || s->capacity - s->used < size) {
        size_t cap = size > SLAB_SIZE ? size : SLAB_SIZE;
        struct sw_slab *n = malloc(sizeof *n + cap);
        if (!n) sw_concurrency_fatal("out of memory in the task allocator");
        n->prev = s;
        n->capacity = cap;
        n->used = 0;
        n->owner = t;
        t->slab = s = n;
    }
    struct block_header *h = (struct block_header *)(s->data + s->used);
    h->slab = s;
    h->prev_used = s->used;
    s->used += size;
    return h + 1;
}

static void task_dealloc(sw_task *t, void *p) {
    struct block_header *h = (struct block_header *)p - 1;
    struct sw_slab *s = h->slab;
    if (!s) {
        free(h);
        return;
    }
    if (s->owner != t)
        sw_concurrency_fatal("swift_task_dealloc: block %p belongs to task %p, current task %p", p,
                             (void *)s->owner, (void *)t);
    if ((char *)h != s->data + h->prev_used || s->used <= h->prev_used)
        sw_concurrency_fatal("swift_task_dealloc: %p is not the last allocation of task %p", p, (void *)t);
    s->used = h->prev_used;
    /* release emptied slabs on top of the chain, keeping the first one */
    while (t->slab && t->slab->used == 0 && t->slab->prev) {
        struct sw_slab *dead = t->slab;
        t->slab = dead->prev;
        free(dead);
    }
}

static void *d_swift_task_alloc(size_t size) {
    sw_task *t = sw_cur_task;
    if (t) return task_alloc(t, size);
    struct block_header *h = malloc(sizeof *h + size);
    h->slab = NULL;
    return h + 1;
}
DX_FN(swift_task_alloc);

static void d_swift_task_dealloc(void *p) {
    struct block_header *h = (struct block_header *)p - 1;
    if (!h->slab) {
        free(h);
        return;
    }
    task_dealloc(sw_cur_task, p);
}
DX_FN(swift_task_dealloc);

/* Frees everything down to and including p. */
static void d_swift_task_dealloc_through(void *p) {
    sw_task *t = sw_cur_task;
    struct block_header *h = (struct block_header *)p - 1;
    if (!h->slab) {
        free(h);
        return;
    }
    while (t->slab && t->slab != h->slab) {
        struct sw_slab *dead = t->slab;
        t->slab = dead->prev;
        free(dead);
    }
    task_dealloc(t, p);
}
DX_FN(swift_task_dealloc_through);

static void *d_swift_job_allocate(sw_job *job, size_t size) {
    if ((job->flags & 0xff) == SW_JOB_KIND_TASK) return task_alloc((sw_task *)job, size);
    return d_swift_task_alloc(size);
}
DX_FN(swift_job_allocate);
static void d_swift_job_deallocate(sw_job *job, void *p) {
    if ((job->flags & 0xff) == SW_JOB_KIND_TASK) task_dealloc((sw_task *)job, p);
    else d_swift_task_dealloc(p);
}
DX_FN(swift_job_deallocate);

/* ---- task objects -------------------------------------------------------------------------
 * One allocation holds the task, the storage for its result, and its
 * initial async context, preceded by the prefix the start function reads. */
struct ctx_prefix {
    void *indirect_result;
    void *entry;
    void *closure;
    void *error;
};

struct sw_local {
    struct sw_local *next;
    const void *key;
    const sw_metadata *type;
    void *value;
};

struct sw_cancel_record {
    struct sw_cancel_record *next;
    sw_task *task;
    void *fn;      /* SW_CALL void (*)(void *ctx SW_SELF) */
    void *ctx;
    struct sw_group *group; /* a group owned by the task instead of a handler */
};

typedef SW_CALL void (*sw_handler_fn)(void *ctx SW_SELF);

static void free_locals(struct sw_local *l) {
    while (l) {
        struct sw_local *next = l->next;
        vwt_of(l->type)->destroy(l->value, l->type);
        free(l->value);
        free(l);
        l = next;
    }
}

static void task_destroy(void *obj) {
    sw_task *t = obj;
    uint32_t st = atomic_load(&t->status);
    if ((st & SW_TS_COMPLETE) && !(st & SW_TS_ERROR) && t->result_type)
        vwt_of(t->result_type)->destroy(t->result, t->result_type);
    if (t->error) sw_unknown_release(t->error);
    free_locals(t->locals);
    while (t->slab) {
        struct sw_slab *s = t->slab;
        t->slab = s->prev;
        free(s);
    }
    pthread_mutex_destroy(&t->lock);
    if (t->async_let) return; /* storage belongs to the async let */
    void (*dealloc)(void *, size_t, size_t) =
        (void (*)(void *, size_t, size_t))dx_registry_lookup("_swift_deallocObject");
    dealloc(t, 0, 0);
}

static struct {
    sw_heap_metadata_header header;
    uintptr_t kind;
} task_metadata = {{NULL, task_destroy, &sw_vwt_native_object}, SW_KIND_TASK};
const sw_metadata *const sw_task_metadata = (const sw_metadata *)&task_metadata.kind;

static _Atomic uint32_t next_task_id = 1;

typedef SW_ASYNC void (*future_entry_fn)(void *result, sw_actx *ctx SW_ACTX, void *closure SW_SELF);
typedef SW_ASYNC void (*void_entry_fn)(sw_actx *ctx SW_ACTX, void *closure SW_SELF);

static SW_ASYNC void task_start_future(sw_actx *ctx SW_ACTX) {
    struct ctx_prefix *p = (struct ctx_prefix *)ctx - 1;
    return ((future_entry_fn)p->entry)(p->indirect_result, ctx, p->closure);
}

static SW_ASYNC void task_start_discarding(sw_actx *ctx SW_ACTX) {
    struct ctx_prefix *p = (struct ctx_prefix *)ctx - 1;
    return ((void_entry_fn)p->entry)(ctx, p->closure);
}

static void task_finish(sw_task *t, void *error);

/* The resume function of every task's initial context: the task's
 * function has returned, with its error (if any) in r13. */
static SW_ASYNC void task_complete(sw_actx *ctx SW_ACTX, void *error SW_SELF) {
    task_finish(sw_cur_task, error);
}

void *sw_task_deliver(sw_task *f, void *dest) {
    if (!dest) return NULL;
    if (atomic_load(&f->status) & SW_TS_ERROR) return sw_unknown_retain(f->error);
    if (f->result_type) vwt_of(f->result_type)->initializeWithCopy(dest, f->result, f->result_type);
    return NULL;
}

/* A waiting task is resumed through this, so that its continuation
 * function gets the error register it expects. */
static SW_ASYNC void resume_after_wait(sw_actx *ctx SW_ACTX) {
    sw_task *t = sw_cur_task;
    if (t->wait_throwing) {
        void *error = t->wait_error;
        t->wait_error = NULL;
        return ((sw_throw_resume_fn)t->wait_resume)(ctx, error);
    }
    return ((sw_resume_fn)t->wait_resume)(ctx);
}

void sw_task_resume_waiter(sw_task *w, void *error) {
    w->wait_error = error;
    w->job.run = (void *)resume_after_wait;
    sw_enqueue_global(&w->job);
}

static void task_finish(sw_task *t, void *error) {
    task_lock(t);
    t->error = error;
    sw_task *waiters = t->waiters;
    t->waiters = NULL;
    atomic_fetch_or(&t->status, SW_TS_COMPLETE | (error ? SW_TS_ERROR : 0));
    task_unlock(t);
    if (t->release_closure && t->closure_context) sw_release(t->closure_context);
    t->closure_context = NULL;
    /* An async let's task may be destroyed by its parent as soon as the
     * parent is woken: read what we need first. */
    struct sw_group *group = t->group;
    int async_let = t->async_let;
    if (group) sw_group_child_completed(group, t);
    while (waiters) {
        sw_task *w = waiters;
        waiters = w->wait_next;
        void *e = sw_task_deliver(t, w->wait_dest);
        sw_task_resume_waiter(w, e);
    }
    if (!async_let) sw_release((sw_heap_object *)t);
}

static uint8_t inherited_priority(void) {
    if (sw_cur_task) return sw_cur_task->max_priority;
    return sw_on_main_thread() ? 0x21 : 0x15;
}

static __thread struct sw_local *thread_locals; /* bindings made outside any task */

static void copy_locals(sw_task *to) {
    struct sw_local **tail = &to->locals;
    struct sw_local *src = sw_cur_task ? sw_cur_task->locals : thread_locals;
    sw_task *owner = sw_cur_task;
    for (;;) {
        for (; src; src = src->next) {
            int seen = 0;
            for (struct sw_local *l = to->locals; l; l = l->next)
                if (l->key == src->key) seen = 1;
            if (seen) continue;
            struct sw_local *n = malloc(sizeof *n);
            const sw_vwt *w = vwt_of(src->type);
            n->next = NULL;
            n->key = src->key;
            n->type = src->type;
            n->value = malloc(w->size ? w->size : 1);
            w->initializeWithCopy(n->value, src->value, src->type);
            *tail = n;
            tail = &n->next;
        }
        if (!owner || !owner->parent) break;
        src = owner->parent->locals;
        owner = owner->parent;
    }
}

sw_task *sw_task_create_with(size_t flags, sw_option *options, const sw_metadata *result_type,
                             const void *afp, void *closure, void *async_let) {
    sw_executor initial = {0, 0};
    struct sw_group *group = NULL;
    for (sw_option *o = options; o; o = o->parent) {
        switch (o->flags & 0xff) {
        case SW_OPT_INITIAL_EXECUTOR:
            initial.identity = o->payload[0];
            initial.impl = (uintptr_t)o->payload[1];
            break;
        case SW_OPT_GROUP:
            group = o->payload[0];
            break;
        default:
            break; /* task executors, names: not modelled */
        }
    }

    /* the async function pointer: relative function, context size */
    const int32_t *fp = afp;
    void *entry = (char *)afp + fp[0];
    size_t ctx_size = align_up(((const uint32_t *)afp)[1], 16);
    if (ctx_size < sizeof(sw_actx)) ctx_size = sizeof(sw_actx);

    int discarding = (flags & SW_TCF_DISCARDING) != 0;
    if (discarding) result_type = NULL;
    size_t result_align = 16, result_size = 0;
    if (result_type) {
        const sw_vwt *w = vwt_of(result_type);
        size_t a = (w->flags & SW_VW_ALIGNMENT_MASK) + 1;
        if (a > result_align) result_align = a;
        result_size = w->size;
    }
    size_t off_result = align_up(sizeof(sw_task), result_align);
    size_t off_prefix = align_up(off_result + result_size, 16);
    size_t off_ctx = off_prefix + sizeof(struct ctx_prefix);
    size_t total = off_ctx + ctx_size;

    sw_task *t;
    if (async_let) {
        t = async_let;
        memset(t, 0, total);
        t->job.metadata = sw_task_metadata;
        t->job.refcounts = 0; /* never released: owned by the async let */
        t->async_let = 1;
    } else {
        t = (sw_task *)sw_alloc_object(sw_task_metadata, total, result_align - 1);
        memset((char *)t + sizeof(sw_heap_object), 0, total - sizeof(sw_heap_object));
        sw_retain((sw_heap_object *)t); /* the running reference, dropped when it finishes */
    }
    pthread_mutex_init(&t->lock, NULL);
    uint8_t prio = flags & SW_TCF_PRIORITY_MASK;
    if (!prio) prio = inherited_priority();
    if (!prio) prio = 0x15;
    t->base_priority = t->max_priority = prio;
    t->job.flags = SW_JOB_KIND_TASK | ((uint32_t)prio << 8) | SW_JOBF_FUTURE;
    if (flags & SW_TCF_CHILD) t->job.flags |= SW_JOBF_CHILD;
    if (group) t->job.flags |= SW_JOBF_GROUP_CHILD;
    if (async_let) t->job.flags |= SW_JOBF_ASYNC_LET;
    t->job.id = atomic_fetch_add(&next_task_id, 1);
    t->result_type = result_type;
    t->result = (char *)t + off_result;

    struct ctx_prefix *p = (struct ctx_prefix *)((char *)t + off_prefix);
    sw_actx *ctx = (sw_actx *)((char *)t + off_ctx);
    p->indirect_result = t->result;
    p->entry = entry;
    p->closure = closure;
    ctx->parent = NULL;
    ctx->resume_parent = (void *)task_complete;
    t->resume_context = ctx;
    t->job.run = discarding ? (void *)task_start_discarding : (void *)task_start_future;

    /* The closure context was passed +1 unless the function consumes it
     * (or it lives on the creator's stack, for async let). */
    t->closure_context = closure;
    t->release_closure = !async_let && !(flags & SW_TCF_FUNCTION_CONSUMED);

    if ((flags & SW_TCF_CHILD) && sw_cur_task) {
        t->parent = sw_cur_task;
        sw_task_add_child(sw_cur_task, t);
    }
    if (flags & SW_TCF_COPY_LOCALS) copy_locals(t);
    if (group) {
        t->group = group;
        sw_group_attach(group, t, (flags & SW_TCF_ADD_PENDING_UNCONDITIONALLY) != 0);
    }
    t->executor = initial;
    if (flags & SW_TCF_ENQUEUE) sw_enqueue(&t->job, initial);
    return t;
}

typedef struct {
    sw_task *task;
    sw_actx *context;
} task_and_context;

static task_and_context d_swift_task_create(size_t flags, sw_option *options,
                                            const sw_metadata *result_type, const void *afp,
                                            void *closure) {
    void *async_let = NULL;
    for (sw_option *o = options; o; o = o->parent)
        if ((o->flags & 0xff) == SW_OPT_ASYNC_LET_WITH_BUFFER) async_let = o->payload[0];
    sw_task *t = sw_task_create_with(flags, options, result_type, afp, closure, async_let);
    return (task_and_context){t, t->resume_context};
}
DX_FN(swift_task_create);

/* ---- children ------------------------------------------------------------------------------ */
void sw_task_add_child(sw_task *parent, sw_task *child) {
    task_lock(parent);
    child->next_sibling = parent->first_child;
    parent->first_child = child;
    int cancelled = atomic_load(&parent->status) & SW_TS_CANCELLED;
    task_unlock(parent);
    if (cancelled) atomic_fetch_or(&child->status, SW_TS_CANCELLED);
}

void sw_task_remove_child(sw_task *parent, sw_task *child) {
    task_lock(parent);
    for (sw_task **p = &parent->first_child; *p; p = &(*p)->next_sibling) {
        if (*p == child) {
            *p = child->next_sibling;
            break;
        }
    }
    task_unlock(parent);
}

/* ---- futures -------------------------------------------------------------------------------
 * swift_task_future_wait(_throwing) use the "direct continuation"
 * convention: the caller passes its own context (r14), the function to
 * resume and a small scratch context we do not need. */
SW_ASYNC void swift_task_future_wait(void *result, sw_actx *caller SW_ACTX, sw_task *task,
                                     sw_resume_fn resume, sw_actx *call_ctx) {
    sw_task *self = sw_cur_task;
    task_lock(task);
    if (atomic_load(&task->status) & SW_TS_COMPLETE) {
        task_unlock(task);
        sw_task_deliver(task, result);
        return resume(caller);
    }
    self->wait_dest = result;
    self->wait_resume = (void *)resume;
    self->wait_throwing = 0;
    self->resume_context = caller;
    self->wait_next = task->waiters;
    task->waiters = self;
    task_unlock(task);
}
DX_EXPORT("_swift_task_future_wait", swift_task_future_wait);

SW_ASYNC void swift_task_future_wait_throwing(void *result, sw_actx *caller SW_ACTX, sw_task *task,
                                              sw_throw_resume_fn resume, sw_actx *call_ctx) {
    sw_task *self = sw_cur_task;
    task_lock(task);
    if (atomic_load(&task->status) & SW_TS_COMPLETE) {
        task_unlock(task);
        void *error = sw_task_deliver(task, result);
        return resume(caller, error);
    }
    self->wait_dest = result;
    self->wait_resume = (void *)resume;
    self->wait_throwing = 1;
    self->resume_context = caller;
    self->wait_next = task->waiters;
    task->waiters = self;
    task_unlock(task);
}
DX_EXPORT("_swift_task_future_wait_throwing", swift_task_future_wait_throwing);

/* ---- current task, priorities -------------------------------------------------------------- */
static sw_task *d_swift_task_getCurrent(void) { return sw_cur_task; }
DX_FN(swift_task_getCurrent);

static size_t d_swift_task_currentPriority(sw_task *t) { return t ? t->max_priority : 0; }
DX_FN(swift_task_currentPriority);
static size_t d_swift_task_basePriority(sw_task *t) { return t ? t->base_priority : 0; }
DX_FN(swift_task_basePriority);
static size_t d_swift_task_getJobFlags(sw_task *t) { return t->job.flags; }
DX_FN(swift_task_getJobFlags);
static uint64_t d_swift_task_getJobTaskId(sw_job *j) { return j->id; }
DX_FN(swift_task_getJobTaskId);
static size_t d_swift_task_escalate(sw_task *t, size_t prio) {
    if (prio > t->max_priority) t->max_priority = (uint8_t)prio;
    return t->max_priority;
}
DX_FN(swift_task_escalate);

/* ---- cancellation -------------------------------------------------------------------------- */
void sw_task_cancel(sw_task *t) {
    uint32_t old = atomic_fetch_or(&t->status, SW_TS_CANCELLED);
    if (old & (SW_TS_CANCELLED | SW_TS_COMPLETE)) return;
    task_lock(t);
    for (struct sw_cancel_record *r = t->records; r; r = r->next) {
        if (r->group) sw_group_cancel(r->group);
        else ((sw_handler_fn)r->fn)(r->ctx);
    }
    for (sw_task *c = t->first_child; c; c = c->next_sibling) sw_task_cancel(c);
    task_unlock(t);
}

static void d_swift_task_cancel(sw_task *t) { sw_task_cancel(t); }
DX_FN(swift_task_cancel);

static bool d_swift_task_isCancelled(sw_task *t) {
    return t && (atomic_load(&t->status) & SW_TS_CANCELLED) != 0;
}
DX_FN(swift_task_isCancelled);

static struct sw_cancel_record *add_record(sw_task *t, struct sw_cancel_record *r) {
    r->task = t;
    if (!t) return r;
    task_lock(t);
    if (atomic_load(&t->status) & SW_TS_CANCELLED) {
        task_unlock(t);
        if (r->group) sw_group_cancel(r->group);
        else ((sw_handler_fn)r->fn)(r->ctx);
        r->task = NULL; /* not linked */
        return r;
    }
    r->next = t->records;
    t->records = r;
    task_unlock(t);
    return r;
}

static void remove_record(struct sw_cancel_record *r) {
    sw_task *t = r->task;
    if (t) {
        task_lock(t);
        for (struct sw_cancel_record **p = &t->records; *p; p = &(*p)->next) {
            if (*p == r) {
                *p = r->next;
                break;
            }
        }
        task_unlock(t);
    }
    free(r);
}

/* The handler is a Swift closure: function and context (passed in r13). */
static struct sw_cancel_record *d_swift_task_addCancellationHandler(void *fn, void *ctx) {
    struct sw_cancel_record *r = calloc(1, sizeof *r);
    r->fn = fn;
    r->ctx = ctx;
    return add_record(sw_cur_task, r);
}
DX_FN(swift_task_addCancellationHandler);

static void d_swift_task_removeCancellationHandler(struct sw_cancel_record *r) { remove_record(r); }
DX_FN(swift_task_removeCancellationHandler);

/* Groups owned by a task are cancelled with it. */
void *sw_task_add_group_record(struct sw_group *g) {
    struct sw_cancel_record *r = calloc(1, sizeof *r);
    r->group = g;
    return add_record(sw_cur_task, r);
}
void sw_task_remove_group_record(void *record) { remove_record(record); }

/* Priority escalation is not modelled: handlers are never called. */
static void *d_swift_task_addPriorityEscalationHandler(void *fn, void *ctx) {
    return calloc(1, sizeof(struct sw_cancel_record));
}
DX_FN(swift_task_addPriorityEscalationHandler);
static void d_swift_task_removePriorityEscalationHandler(void *r) { free(r); }
DX_FN(swift_task_removePriorityEscalationHandler);

/* ---- continuations --------------------------------------------------------------------------
 * The continuation context lives in the suspending function's frame. The
 * task's resume context points at it, which is how resumers (and compiled
 * code storing the result) find it. */
static sw_task *d_swift_continuation_init(sw_cont_ctx *ctx, size_t flags) {
    sw_task *t = sw_cur_task;
    ctx->flags = flags & SW_CONTF_CAN_THROW;
    if (flags & SW_CONTF_FORCE_SWITCH) ctx->flags |= 2;
    ctx->error = NULL;
    if (!(flags & SW_CONTF_EXECUTOR_OVERRIDE)) ctx->resume_executor = sw_cur_exec;
    atomic_store(&ctx->await_state, (flags & SW_CONTF_PREAWAITED) ? SW_CONT_AWAITED : SW_CONT_PENDING);
    t->resume_context = &ctx->base;
    t->job.run = ctx->base.resume_parent;
    return t;
}
DX_FN(swift_continuation_init);

SW_ASYNC void swift_continuation_await(sw_cont_ctx *ctx) {
    size_t expected = SW_CONT_PENDING;
    if (atomic_compare_exchange_strong(&ctx->await_state, &expected, SW_CONT_AWAITED))
        return; /* suspended: whoever resumes reschedules the task */
    /* already resumed: carry on */
    if ((ctx->flags & 2) && ctx->resume_executor.identity != sw_cur_exec.identity) {
        sw_task *t = sw_cur_task;
        t->job.run = ctx->base.resume_parent;
        t->resume_context = &ctx->base;
        sw_enqueue(&t->job, ctx->resume_executor);
        return;
    }
    return ((sw_resume_fn)ctx->base.resume_parent)(&ctx->base);
}
DX_EXPORT("_swift_continuation_await", swift_continuation_await);

static void continuation_resume(sw_task *t) {
    sw_cont_ctx *ctx = (sw_cont_ctx *)t->resume_context;
    sw_executor e = ctx->resume_executor;
    size_t expected = SW_CONT_PENDING;
    if (atomic_compare_exchange_strong(&ctx->await_state, &expected, SW_CONT_RESUMED)) return;
    sw_enqueue(&t->job, e);
}

static void d_swift_continuation_resume(sw_task *t) { continuation_resume(t); }
DX_FN(swift_continuation_resume);
static void d_swift_continuation_throwingResume(sw_task *t) { continuation_resume(t); }
DX_FN(swift_continuation_throwingResume);
static void d_swift_continuation_throwingResumeWithError(sw_task *t, void *error) {
    ((sw_cont_ctx *)t->resume_context)->error = error;
    continuation_resume(t);
}
DX_FN(swift_continuation_throwingResumeWithError);

static void d_swift_continuation_logFailedCheck(const char *message) {
    fprintf(stderr, "%s\n", message);
}
DX_FN(swift_continuation_logFailedCheck);

/* CheckedContinuation's cell: the continuation, taken exactly once. */
static _Atomic(sw_task *) *d_swift_bitten_continuationCellCreate(sw_task *t) {
    _Atomic(sw_task *) *cell = malloc(sizeof *cell);
    atomic_store(cell, t);
    return cell;
}
DX_FN(swift_bitten_continuationCellCreate);
static sw_task *d_swift_bitten_continuationCellTake(_Atomic(sw_task *) *cell) {
    sw_task *t = atomic_exchange(cell, NULL);
    if (!t)
        sw_concurrency_fatal("SWIFT TASK CONTINUATION MISUSE: tried to resume its continuation "
                             "more than once");
    return t;
}
DX_FN(swift_bitten_continuationCellTake);
static void d_swift_bitten_continuationCellDestroy(_Atomic(sw_task *) *cell) {
    if (atomic_load(cell))
        fprintf(stderr, "SWIFT TASK CONTINUATION MISUSE: leaked its continuation without resuming it. "
                        "This may cause tasks waiting on it to remain suspended forever.\n");
    free(cell);
}
DX_FN(swift_bitten_continuationCellDestroy);

static void resume_later(void *t) { continuation_resume(t); }
static void d_swift_bitten_resumeLater(sw_task *t) { sw_schedule_call(resume_later, t, 0); }
DX_FN(swift_bitten_resumeLater);

/* ---- switching executors --------------------------------------------------------------------
 * Called at every hop (actor entry, return to the caller's actor): run on
 * here if we are already there, else enqueue the task there and suspend. */
SW_ASYNC void swift_task_switch(sw_actx *ctx SW_ACTX, sw_resume_fn resume, void *identity,
                                uintptr_t impl) {
    if (identity == sw_cur_exec.identity) return resume(ctx);
    sw_task *t = sw_cur_task;
    t->job.run = (void *)resume;
    t->resume_context = ctx;
    sw_enqueue(&t->job, (sw_executor){identity, impl});
}
DX_EXPORT("_swift_task_switch", swift_task_switch);

/* ---- task-local values ----------------------------------------------------------------------- */
static void d_swift_task_localValuePush(const void *key, void *value, const sw_metadata *type) {
    struct sw_local *n = malloc(sizeof *n);
    const sw_vwt *w = vwt_of(type);
    n->key = key;
    n->type = type;
    n->value = malloc(w->size ? w->size : 1);
    w->initializeWithTake(n->value, value, type);
    struct sw_local **head = sw_cur_task ? &sw_cur_task->locals : &thread_locals;
    n->next = *head;
    *head = n;
}
DX_FN(swift_task_localValuePush);

static void d_swift_task_localValuePop(void) {
    struct sw_local **head = sw_cur_task ? &sw_cur_task->locals : &thread_locals;
    struct sw_local *n = *head;
    if (!n) return;
    *head = n->next;
    n->next = NULL;
    free_locals(n);
}
DX_FN(swift_task_localValuePop);

static void *d_swift_task_localValueGet(const void *key) {
    sw_task *t = sw_cur_task;
    struct sw_local *l = t ? t->locals : thread_locals;
    for (;;) {
        for (; l; l = l->next)
            if (l->key == key) return l->value;
        if (!t || !t->parent) return NULL;
        t = t->parent;
        l = t->locals;
    }
}
DX_FN(swift_task_localValueGet);

static void d_swift_task_localsCopyTo(sw_task *target) { copy_locals(target); }
DX_FN(swift_task_localsCopyTo);
