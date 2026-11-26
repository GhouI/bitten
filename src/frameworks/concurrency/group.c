/* Task groups and async let. See concurrency.h.
 *
 * A task group lives in storage its owner allocates (32 words,
 * NumWords_TaskGroup). Children are ordinary tasks created with a group
 * option record; the group keeps a reference to each until its result is
 * consumed by next(). An async let is 80 words in the parent's frame
 * (NumWords_AsyncLet): our bookkeeping, then the child task itself when it
 * fits. */
#include <stdlib.h>
#include <string.h>

#include "concurrency.h"

void *sw_task_add_group_record(struct sw_group *g);
void sw_task_remove_group_record(void *record);

static const sw_vwt *vwt_of(const sw_metadata *m) { return ((const sw_vwt *const *)m)[-1]; }

struct sw_group {
    pthread_mutex_t lock;
    const sw_metadata *result_type;
    uint32_t flags;
    int cancelled;
    size_t pending;        /* added and not yet consumed (discarding: not yet finished) */
    sw_task *ready_head, *ready_tail; /* finished, not yet consumed; linked by wait_next */
    sw_task *waiter;       /* the owner, suspended in next() or waitAll */
    int waiter_all;        /* ... waiting for all children */
    sw_task *owner;
    void *record;          /* cancellation record on the owner */
    void *first_error;     /* discarding groups: the first child error */
};
_Static_assert(sizeof(struct sw_group) <= 32 * sizeof(void *), "task group storage");
enum { SW_GROUP_DISCARD_RESULTS = 1 << 8 };

static int discarding(struct sw_group *g) { return (g->flags & SW_GROUP_DISCARD_RESULTS) != 0; }

static void group_init(struct sw_group *g, size_t flags, const sw_metadata *type) {
    memset(g, 0, sizeof *g);
    pthread_mutex_init(&g->lock, NULL);
    g->flags = (uint32_t)flags;
    g->result_type = type;
    g->owner = sw_cur_task;
    if (g->owner) {
        if (atomic_load(&g->owner->status) & SW_TS_CANCELLED) g->cancelled = 1;
        g->record = sw_task_add_group_record(g);
    }
}

static void d_swift_taskGroup_initialize(struct sw_group *g, const sw_metadata *type) {
    group_init(g, 0, type);
}
DX_FN(swift_taskGroup_initialize);
static void d_swift_taskGroup_initializeWithFlags(size_t flags, struct sw_group *g,
                                                  const sw_metadata *type) {
    group_init(g, flags, type);
}
DX_FN(swift_taskGroup_initializeWithFlags);
static void d_swift_taskGroup_initializeWithOptions(size_t flags, struct sw_group *g,
                                                    const sw_metadata *type, sw_option *options) {
    group_init(g, flags, type);
}
DX_FN(swift_taskGroup_initializeWithOptions);

static void d_swift_taskGroup_destroy(struct sw_group *g) {
    if (g->record) sw_task_remove_group_record(g->record);
    while (g->ready_head) {
        sw_task *t = g->ready_head;
        g->ready_head = t->wait_next;
        if (g->owner) sw_task_remove_child(g->owner, t);
        sw_release((sw_heap_object *)t);
    }
    if (g->first_error) sw_unknown_release(g->first_error);
    pthread_mutex_destroy(&g->lock);
}
DX_FN(swift_taskGroup_destroy);

static bool d_swift_taskGroup_addPending(struct sw_group *g, bool unconditionally) {
    pthread_mutex_lock(&g->lock);
    int ok = unconditionally || !g->cancelled;
    if (ok) g->pending++;
    pthread_mutex_unlock(&g->lock);
    return ok;
}
DX_FN(swift_taskGroup_addPending);

/* Called by swift_task_create for a child with a group option. */
void sw_group_attach(struct sw_group *g, sw_task *child, int unconditionally) {
    sw_retain((sw_heap_object *)child); /* until consumed (or, discarding, finished) */
    pthread_mutex_lock(&g->lock);
    int cancelled = g->cancelled;
    /* addTask sets "add pending unconditionally": the child counts as
     * pending from here; addTaskUnlessCancelled counted it already
     * (swift_taskGroup_addPending). */
    if (unconditionally) g->pending++;
    pthread_mutex_unlock(&g->lock);
    if (cancelled) atomic_fetch_or(&child->status, SW_TS_CANCELLED);
}

static void d_swift_taskGroup_attachChild(struct sw_group *g, sw_task *child) {
    child->group = g;
    sw_group_attach(g, child, 1);
}
DX_FN(swift_taskGroup_attachChild);

/* Marks the group cancelled (new children start cancelled). Its existing
 * children are cancelled by the caller. */
void sw_group_cancel(struct sw_group *g) {
    pthread_mutex_lock(&g->lock);
    g->cancelled = 1;
    pthread_mutex_unlock(&g->lock);
}

static void cancel_children(struct sw_group *g) {
    sw_group_cancel(g);
    sw_task *owner = g->owner;
    if (!owner) return;
    /* children of the owner that belong to this group */
    pthread_mutex_lock(&owner->lock);
    sw_task *list[64];
    size_t n = 0;
    for (sw_task *c = owner->first_child; c; c = c->next_sibling) {
        if (c->group != g) continue;
        if (n == 64) break;
        sw_retain((sw_heap_object *)c);
        list[n++] = c;
    }
    pthread_mutex_unlock(&owner->lock);
    for (size_t i = 0; i < n; i++) {
        sw_task_cancel(list[i]);
        sw_release((sw_heap_object *)list[i]);
    }
    if (n == 64) cancel_children(g); /* more than fit at once: cancelled ones are skipped quickly */
}

static void d_swift_taskGroup_cancelAll(struct sw_group *g) { cancel_children(g); }
DX_FN(swift_taskGroup_cancelAll);
static void d_swift_task_cancel_group_child_tasks(struct sw_group *g) { cancel_children(g); }
DX_FN(swift_task_cancel_group_child_tasks);

static bool d_swift_taskGroup_isCancelled(struct sw_group *g) {
    pthread_mutex_lock(&g->lock);
    int c = g->cancelled;
    pthread_mutex_unlock(&g->lock);
    return c || (g->owner && (atomic_load(&g->owner->status) & SW_TS_CANCELLED));
}
DX_FN(swift_taskGroup_isCancelled);

static bool d_swift_taskGroup_isEmpty(struct sw_group *g) {
    pthread_mutex_lock(&g->lock);
    int empty = g->pending == 0;
    pthread_mutex_unlock(&g->lock);
    return empty;
}
DX_FN(swift_taskGroup_isEmpty);

static bool d_swift_task_hasTaskGroupStatusRecord(void) { return false; }
DX_FN(swift_task_hasTaskGroupStatusRecord);
DX_EXPORT("_swift_taskGroup_hasTaskGroupRecord", d_swift_task_hasTaskGroupStatusRecord);

/* next() returns T?: the value then the Optional tag, or nil. */
static void *deliver_optional(struct sw_group *g, sw_task *child, void *dest) {
    if (!child) {
        vwt_of(g->result_type)->storeEnumTagSinglePayload(dest, 1, 1, g->result_type);
        return NULL;
    }
    void *error = sw_task_deliver(child, dest);
    if (!error) vwt_of(g->result_type)->storeEnumTagSinglePayload(dest, 0, 1, g->result_type);
    return error;
}

static void consumed(struct sw_group *g, sw_task *child) {
    if (g->owner) sw_task_remove_child(g->owner, child);
    sw_release((sw_heap_object *)child);
}

void sw_group_child_completed(struct sw_group *g, sw_task *child) {
    pthread_mutex_lock(&g->lock);
    if (discarding(g)) {
        if (atomic_load(&child->status) & SW_TS_ERROR) {
            if (!g->first_error) g->first_error = sw_unknown_retain(child->error);
        }
        g->pending--;
        sw_task *w = NULL;
        void *error = NULL;
        if (g->waiter && g->pending == 0) {
            w = g->waiter;
            g->waiter = NULL;
            error = g->first_error;
            g->first_error = NULL;
        }
        pthread_mutex_unlock(&g->lock);
        consumed(g, child);
        if (w) sw_task_resume_waiter(w, error);
        return;
    }
    if (g->waiter && !g->waiter_all) {
        sw_task *w = g->waiter;
        g->waiter = NULL;
        g->pending--;
        pthread_mutex_unlock(&g->lock);
        void *error = deliver_optional(g, child, w->wait_dest);
        consumed(g, child);
        sw_task_resume_waiter(w, error);
        return;
    }
    child->wait_next = NULL;
    if (g->ready_tail) g->ready_tail->wait_next = child;
    else g->ready_head = child;
    g->ready_tail = child;
    sw_task *w = NULL;
    if (g->waiter && g->waiter_all) {
        /* waitAll on an accumulating group: drop results as they come */
        sw_task *r = g->ready_head;
        g->ready_head = r->wait_next;
        if (!g->ready_head) g->ready_tail = NULL;
        g->pending--;
        if (g->pending == 0) {
            w = g->waiter;
            g->waiter = NULL;
        }
        pthread_mutex_unlock(&g->lock);
        consumed(g, r);
        if (w) sw_task_resume_waiter(w, NULL);
        return;
    }
    pthread_mutex_unlock(&g->lock);
}

/* Direct-continuation convention, like swift_task_future_wait. */
SW_ASYNC void swift_taskGroup_wait_next_throwing(void *result, sw_actx *caller SW_ACTX,
                                                 struct sw_group *g, sw_throw_resume_fn resume,
                                                 sw_actx *call_ctx) {
    sw_task *self = sw_cur_task;
    pthread_mutex_lock(&g->lock);
    sw_task *ready = g->ready_head;
    if (ready) {
        g->ready_head = ready->wait_next;
        if (!g->ready_head) g->ready_tail = NULL;
        g->pending--;
        pthread_mutex_unlock(&g->lock);
        void *error = deliver_optional(g, ready, result);
        consumed(g, ready);
        return resume(caller, error);
    }
    if (g->pending == 0 || discarding(g)) {
        pthread_mutex_unlock(&g->lock);
        deliver_optional(g, NULL, result);
        return resume(caller, NULL);
    }
    self->wait_dest = result;
    self->wait_resume = (void *)resume;
    self->wait_throwing = 1;
    self->resume_context = caller;
    g->waiter = self;
    g->waiter_all = 0;
    pthread_mutex_unlock(&g->lock);
}
DX_EXPORT("_swift_taskGroup_wait_next_throwing", swift_taskGroup_wait_next_throwing);

/* Waits until every child has finished (results are dropped). Resumes
 * with the body's error if given, else a discarding group's first child
 * error. */
SW_ASYNC void swift_taskGroup_waitAll(void *result, sw_actx *caller SW_ACTX, struct sw_group *g,
                                      void *body_error, sw_throw_resume_fn resume,
                                      sw_actx *call_ctx) {
    sw_task *self = sw_cur_task;
    pthread_mutex_lock(&g->lock);
    while (g->ready_head) {
        sw_task *r = g->ready_head;
        g->ready_head = r->wait_next;
        if (!g->ready_head) g->ready_tail = NULL;
        g->pending--;
        consumed(g, r);
    }
    if (g->pending == 0) {
        void *error = body_error ? body_error : g->first_error;
        if (!body_error) g->first_error = NULL;
        pthread_mutex_unlock(&g->lock);
        return resume(caller, error);
    }
    self->wait_dest = NULL;
    self->wait_resume = (void *)resume;
    self->wait_throwing = 1;
    self->resume_context = caller;
    g->waiter = self;
    g->waiter_all = 1;
    pthread_mutex_unlock(&g->lock);
}
DX_EXPORT("_swift_taskGroup_waitAll", swift_taskGroup_waitAll);

/* ---- async let ------------------------------------------------------------------------------ */
struct async_let {
    sw_task *task;
    void *heap;           /* task storage when it did not fit here */
    int has_value;        /* the value has been copied to the result buffer */
    uint32_t pad;
    char space[];         /* the rest of the 640 bytes */
};
#define ASYNC_LET_SIZE (80 * sizeof(void *))
#define ASYNC_LET_SPACE (ASYNC_LET_SIZE - offsetof(struct async_let, space))

static size_t task_storage_size(const sw_metadata *type, const void *afp) {
    size_t a = 16, size = 0;
    if (type) {
        const sw_vwt *w = vwt_of(type);
        if ((w->flags & SW_VW_ALIGNMENT_MASK) + 1 > a) a = (w->flags & SW_VW_ALIGNMENT_MASK) + 1;
        size = w->size;
    }
    size_t ctx = (((const uint32_t *)afp)[1] + 15) & ~(size_t)15;
    return ((sizeof(sw_task) + a - 1) & ~(a - 1)) + ((size + 15) & ~(size_t)15) + 32 + ctx + a;
}

static void d_swift_asyncLet_begin(struct async_let *alet, sw_option *options,
                                   const sw_metadata *type, const void *afp, void *closure,
                                   void *result_buffer) {
    size_t need = task_storage_size(type, afp);
    void *storage;
    alet->heap = NULL;
    alet->has_value = 0;
    if (need <= ASYNC_LET_SPACE) {
        storage = (void *)(((uintptr_t)alet->space + 15) & ~(uintptr_t)15);
        if ((char *)storage + need > (char *)alet + ASYNC_LET_SIZE) storage = NULL;
    } else {
        storage = NULL;
    }
    if (!storage) {
        size_t align = 16;
        if (type && (vwt_of(type)->flags & SW_VW_ALIGNMENT_MASK) + 1 > align)
            align = (vwt_of(type)->flags & SW_VW_ALIGNMENT_MASK) + 1;
        alet->heap = storage = aligned_alloc(align, (need + align - 1) & ~(align - 1));
    }
    alet->task = sw_task_create_with(SW_TCF_CHILD | SW_TCF_ENQUEUE, options, type, afp, closure, storage);
}
DX_FN(swift_asyncLet_begin);

/* Waits for the async let's task. The value is copied into the result
 * buffer the first time; later gets find it there. */
SW_ASYNC void swift_asyncLet_get(sw_actx *caller SW_ACTX, struct async_let *alet, void *buffer,
                                 sw_resume_fn resume, sw_actx *call_ctx) {
    if (alet->has_value) return resume(caller);
    alet->has_value = 1;
    return swift_task_future_wait(buffer, caller, alet->task, resume, call_ctx);
}
DX_EXPORT("_swift_asyncLet_get", swift_asyncLet_get);

SW_ASYNC void swift_asyncLet_get_throwing(sw_actx *caller SW_ACTX, struct async_let *alet,
                                          void *buffer, sw_throw_resume_fn resume,
                                          sw_actx *call_ctx) {
    if (alet->has_value) {
        sw_task *t = alet->task;
        void *error = (atomic_load(&t->status) & SW_TS_ERROR) ? sw_unknown_retain(t->error) : NULL;
        return resume(caller, error);
    }
    alet->has_value = 1;
    return swift_task_future_wait_throwing(buffer, caller, alet->task, resume, call_ctx);
}
DX_EXPORT("_swift_asyncLet_get_throwing", swift_asyncLet_get_throwing);

/* The scratch context the caller gave us (two header words, three free). */
struct finish_scratch {
    sw_actx header;
    struct async_let *alet;
    void *buffer;
    sw_resume_fn resume;
};

static void async_let_destroy(struct async_let *alet, void *buffer) {
    sw_task *t = alet->task;
    uint32_t st = atomic_load(&t->status);
    if (alet->has_value && !(st & SW_TS_ERROR) && t->result_type)
        vwt_of(t->result_type)->destroy(buffer, t->result_type);
    if (t->parent) sw_task_remove_child(t->parent, t);
    /* run the task's destroyer by hand: it is not reference counted */
    void (*destroy)(void *) = ((const sw_heap_metadata_header *)t->job.metadata - 1)->destroy;
    destroy(t);
    free(alet->heap);
}

static SW_ASYNC void finish_after_wait(sw_actx *caller SW_ACTX) {
    struct finish_scratch *s = sw_cur_task->wait_scratch;
    sw_resume_fn resume = s->resume;
    async_let_destroy(s->alet, s->buffer);
    return resume(caller);
}

/* Leaving the scope of an async let: cancel the task if it is still
 * running, wait for it, destroy the value if it was ever read. */
SW_ASYNC void swift_asyncLet_finish(sw_actx *caller SW_ACTX, struct async_let *alet, void *buffer,
                                    sw_resume_fn resume, sw_actx *call_ctx) {
    sw_task *t = alet->task;
    sw_task *self = sw_cur_task;
    if (!(atomic_load(&t->status) & SW_TS_COMPLETE)) sw_task_cancel(t);
    pthread_mutex_lock(&t->lock);
    if (!(atomic_load(&t->status) & SW_TS_COMPLETE)) {
        struct finish_scratch *s = (struct finish_scratch *)call_ctx;
        s->alet = alet;
        s->buffer = buffer;
        s->resume = resume;
        self->wait_dest = NULL;
        self->wait_resume = (void *)finish_after_wait;
        self->wait_throwing = 0;
        self->resume_context = caller;
        self->wait_next = t->waiters;
        t->waiters = self;
        self->wait_scratch = s;
        pthread_mutex_unlock(&t->lock);
        return;
    }
    pthread_mutex_unlock(&t->lock);
    async_let_destroy(alet, buffer);
    return resume(caller);
}
DX_EXPORT("_swift_asyncLet_finish", swift_asyncLet_finish);
