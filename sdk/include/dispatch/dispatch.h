/* bitten SDK: libdispatch, the C interface (src/frameworks/dispatch).
 * Written from the public documentation. Dispatch objects are plain
 * pointers here; the Objective-C object model of Apple's headers
 * (OS_OBJECT) is not used by C and Objective-C code inside bitten. */
#ifndef BITTEN_DISPATCH_H
#define BITTEN_DISPATCH_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct dispatch_object_s *dispatch_object_t;
typedef struct dispatch_queue_s *dispatch_queue_t;
typedef struct dispatch_queue_attr_s *dispatch_queue_attr_t;
typedef struct dispatch_group_s *dispatch_group_t;
typedef struct dispatch_semaphore_s *dispatch_semaphore_t;
typedef struct dispatch_source_s *dispatch_source_t;
typedef const struct dispatch_source_type_s *dispatch_source_type_t;
typedef uint64_t dispatch_time_t;
typedef long dispatch_once_t;
typedef void (^dispatch_block_t)(void);
typedef void (*dispatch_function_t)(void *);
typedef long dispatch_queue_priority_t;

#define DISPATCH_TIME_NOW (0ull)
#define DISPATCH_TIME_FOREVER (~0ull)
#define NSEC_PER_SEC 1000000000ull
#define NSEC_PER_MSEC 1000000ull
#define USEC_PER_SEC 1000000ull
#define NSEC_PER_USEC 1000ull
#define DISPATCH_QUEUE_PRIORITY_HIGH 2
#define DISPATCH_QUEUE_PRIORITY_DEFAULT 0
#define DISPATCH_QUEUE_PRIORITY_LOW (-2)
#define DISPATCH_QUEUE_PRIORITY_BACKGROUND INT16_MIN
#define DISPATCH_QUEUE_SERIAL NULL

extern struct dispatch_queue_s _dispatch_main_q;
extern struct dispatch_queue_attr_s _dispatch_queue_attr_concurrent;
#define DISPATCH_QUEUE_CONCURRENT (&_dispatch_queue_attr_concurrent)
#define dispatch_get_main_queue() (&_dispatch_main_q)

dispatch_queue_t dispatch_get_global_queue(long identifier, unsigned long flags);
dispatch_queue_t dispatch_queue_create(const char *label, dispatch_queue_attr_t attr);
const char *dispatch_queue_get_label(dispatch_queue_t queue);
void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);
void dispatch_async_f(dispatch_queue_t queue, void *context, dispatch_function_t work);
void dispatch_sync(dispatch_queue_t queue, dispatch_block_t block);
void dispatch_sync_f(dispatch_queue_t queue, void *context, dispatch_function_t work);
void dispatch_barrier_async(dispatch_queue_t queue, dispatch_block_t block);
void dispatch_barrier_sync(dispatch_queue_t queue, dispatch_block_t block);
void dispatch_after(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block);
void dispatch_apply(size_t iterations, dispatch_queue_t queue, void (^block)(size_t));
void dispatch_main(void) __attribute__((noreturn));
void dispatch_once(dispatch_once_t *predicate, dispatch_block_t block);
void dispatch_once_f(dispatch_once_t *predicate, void *context, dispatch_function_t function);
dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta);

dispatch_group_t dispatch_group_create(void);
void dispatch_group_async(dispatch_group_t group, dispatch_queue_t queue, dispatch_block_t block);
void dispatch_group_enter(dispatch_group_t group);
void dispatch_group_leave(dispatch_group_t group);
long dispatch_group_wait(dispatch_group_t group, dispatch_time_t timeout);
void dispatch_group_notify(dispatch_group_t group, dispatch_queue_t queue, dispatch_block_t block);

dispatch_semaphore_t dispatch_semaphore_create(long value);
long dispatch_semaphore_wait(dispatch_semaphore_t dsema, dispatch_time_t timeout);
long dispatch_semaphore_signal(dispatch_semaphore_t dsema);

void dispatch_retain(void *object);
void dispatch_release(void *object);
void dispatch_resume(void *object);
void dispatch_suspend(void *object);
void dispatch_activate(void *object);

extern const struct dispatch_source_type_s _dispatch_source_type_timer;
extern const struct dispatch_source_type_s _dispatch_source_type_read;
#define DISPATCH_SOURCE_TYPE_TIMER (&_dispatch_source_type_timer)
#define DISPATCH_SOURCE_TYPE_READ (&_dispatch_source_type_read)
extern const struct dispatch_source_type_s _dispatch_source_type_write;
#define DISPATCH_SOURCE_TYPE_WRITE (&_dispatch_source_type_write)
dispatch_source_t dispatch_source_create(dispatch_source_type_t type, uintptr_t handle, unsigned long mask,
                                         dispatch_queue_t queue);
void dispatch_source_set_event_handler(dispatch_source_t source, dispatch_block_t handler);
void dispatch_source_set_cancel_handler(dispatch_source_t source, dispatch_block_t handler);
void dispatch_source_set_timer(dispatch_source_t source, dispatch_time_t start, uint64_t interval, uint64_t leeway);
void dispatch_source_cancel(dispatch_source_t source);
unsigned long dispatch_source_get_data(dispatch_source_t source);
#endif
