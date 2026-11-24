#ifndef DX_DISPATCH_INTERNAL_H
#define DX_DISPATCH_INTERNAL_H

#include <limits.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <time.h>

#include "dx.h"
#include "dx_objc.h"

#define DISPATCH_FOREVER UINT64_MAX
#define DISPATCH_NSEC UINT64_C(1000000000)

typedef void (*dispatch_function)(void *);

struct dispatch_queue;

enum dispatch_kind {
    DISPATCH_QUEUE,
    DISPATCH_ATTR,
    DISPATCH_GROUP,
    DISPATCH_SEMAPHORE,
    DISPATCH_SOURCE,
    DISPATCH_DATA,
};

struct dispatch_object {
    void *isa;
    atomic_uint refs;
    enum dispatch_kind kind;
    void (*dispose)(struct dispatch_object *);
    _Atomic(void *) context;
    _Atomic(dispatch_function) finalizer;
    struct dispatch_queue *finalizer_queue;
};

#define DISPATCH_STATIC_OBJECT(type) { .refs = ATOMIC_VAR_INIT(UINT_MAX), .kind = (type) }

void *dispatch_alloc(size_t size);
void *dispatch_copy_block(const void *block);
void dispatch_invoke_block(void *block);
void *dispatch_object_class(const char *name, const char *super);
void dispatch_object_init(struct dispatch_object *object, enum dispatch_kind kind,
                          const char *class_name, const char *super_name,
                          void (*dispose)(struct dispatch_object *));
void dispatch_object_retain(void *object);
void dispatch_object_release(void *object);
struct dispatch_queue *dispatch_default_queue(void);
struct dispatch_queue *dispatch_private_queue(const char *label);
void dispatch_submit(struct dispatch_queue *queue, void *context, dispatch_function fn);
void dispatch_submit_batch(struct dispatch_queue *queue, void *context, dispatch_function fn,
                           bool barrier, size_t count);
size_t dispatch_apply_width(struct dispatch_queue *queue);
bool dispatch_block_is_barrier(const void *block);
int dispatch_start_thread(void *(*fn)(void *), void *context);

uint64_t dispatch_now(clockid_t clock);
struct timespec dispatch_timespec(uint64_t nanos);
clockid_t dispatch_deadline(uint64_t when, struct timespec *deadline);
int dispatch_cond_wait(pthread_cond_t *cond, pthread_mutex_t *lock, uint64_t when);

void dispatch_source_public_retain(struct dispatch_object *object);
void dispatch_source_public_release(struct dispatch_object *object);
void dispatch_source_control(struct dispatch_object *object, int change);
void dispatch_source_set_target(struct dispatch_object *object, struct dispatch_queue *queue);

enum dispatch_control { DISPATCH_SUSPEND, DISPATCH_RESUME, DISPATCH_ACTIVATE };

#endif
