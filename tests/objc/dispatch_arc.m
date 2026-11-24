// Dispatch objects are Objective-C objects: ARC retains and releases
// queues, groups and semaphores, and blocks carry captured objects across
// threads.
#include "objc.h"

@protocol OS_dispatch_object <NSObject>
@end
typedef NSObject<OS_dispatch_object> *dispatch_object_t;
typedef NSObject<OS_dispatch_object> *dispatch_queue_t;
typedef NSObject<OS_dispatch_object> *dispatch_group_t;
typedef NSObject<OS_dispatch_object> *dispatch_semaphore_t;
typedef void (^dispatch_block_t)(void);
typedef unsigned long long dispatch_time_t;
#define DISPATCH_TIME_FOREVER (~0ull)

dispatch_queue_t dispatch_queue_create(const char *label, void *attr);
dispatch_queue_t dispatch_get_global_queue(long identifier, unsigned long flags);
void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);
void dispatch_sync(dispatch_queue_t queue, dispatch_block_t block);
dispatch_group_t dispatch_group_create(void);
void dispatch_group_async(dispatch_group_t group, dispatch_queue_t queue, dispatch_block_t block);
long dispatch_group_wait(dispatch_group_t group, dispatch_time_t timeout);
dispatch_semaphore_t dispatch_semaphore_create(long value);
long dispatch_semaphore_wait(dispatch_semaphore_t sema, dispatch_time_t timeout);
long dispatch_semaphore_signal(dispatch_semaphore_t sema);
const char *dispatch_queue_get_label(dispatch_queue_t queue);
void dispatch_once(long *predicate, dispatch_block_t block);

static int deallocs;
@interface Payload : NSObject
@property (nonatomic) long value;
@end
@implementation Payload
- (void)dealloc { __sync_add_and_fetch(&deallocs, 1); }
@end

@interface Worker : NSObject {
    dispatch_queue_t _queue;   // strong ivar holding a dispatch object
    long _total;
}
- (void)add:(Payload *)p;
- (long)total;
@end
@implementation Worker
- (id)init {
    if ((self = [super init])) _queue = dispatch_queue_create("bitten.test.worker", NULL);
    return self;
}
- (void)add:(Payload *)p { dispatch_async(_queue, ^{ self->_total += p.value; }); }
- (long)total {
    __block long t;
    dispatch_sync(_queue, ^{ t = self->_total; });
    return t;
}
@end

int main(void) {
    @autoreleasepool {
        Worker *w = [Worker new];
        for (long i = 1; i <= 1000; i++) {
            Payload *p = [Payload new];
            p.value = i;
            [w add:p];             // the block keeps p alive until it has run
        }
        CHECK([w total] == 500500);

        dispatch_queue_t q = dispatch_queue_create("bitten.test.q", NULL);
        CHECK(strcmp(dispatch_queue_get_label(q), "bitten.test.q") == 0);
        CHECK([q respondsToSelector:sel_registerName("retain")] && [q isKindOfClass:[NSObject class]]);
        dispatch_group_t g = dispatch_group_create();
        __block long sum = 0;
        dispatch_semaphore_t lock = dispatch_semaphore_create(1);
        for (long i = 0; i < 64; i++) {
            Payload *p = [Payload new];
            p.value = i;
            dispatch_group_async(g, dispatch_get_global_queue(0, 0), ^{
                dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
                sum += p.value;
                dispatch_semaphore_signal(lock);
            });
        }
        CHECK(dispatch_group_wait(g, DISPATCH_TIME_FOREVER) == 0);
        CHECK(sum == 2016);

        static long once;
        __block int ran = 0;
        for (int i = 0; i < 3; i++) dispatch_once(&once, ^{ ran++; });
        CHECK(ran == 1);
    }
    // every payload was released once its block finished; queues were freed by ARC
    for (int i = 0; i < 200 && deallocs != 1064; i++) {
        extern int usleep(unsigned);
        usleep(5000);
    }
    CHECK(deallocs == 1064);
    puts("objc dispatch ok");
    return 0;
}
