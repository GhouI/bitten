// Message dispatch, retain/release and weak references under contention.
#include "objc.h"

typedef void *pthread_t;
int pthread_create(pthread_t *, void *, void *(*)(void *), void *);
int pthread_join(pthread_t, void **);

@interface Counter : NSObject {
    long _n;
}
- (long)bump:(long)by;
- (long)m0; - (long)m1; - (long)m2; - (long)m3; - (long)m4; - (long)m5; - (long)m6; - (long)m7;
- (long)m8; - (long)m9; - (long)m10; - (long)m11; - (long)m12; - (long)m13; - (long)m14; - (long)m15;
@end
@implementation Counter
- (long)bump:(long)by { return __sync_add_and_fetch(&_n, by); }
#define M(i) - (long)m##i { return i; }
M(0) M(1) M(2) M(3) M(4) M(5) M(6) M(7) M(8) M(9) M(10) M(11) M(12) M(13) M(14) M(15)
@end
@interface SubCounter : Counter
@end
@implementation SubCounter
- (long)m3 { return 300 + [super m3]; }
@end

static Counter *shared;
static __weak Counter *weak_shared;
static int deallocs;
@interface Tracked : NSObject
@end
@implementation Tracked
- (void)dealloc { __sync_add_and_fetch(&deallocs, 1); }
@end

static void *worker(void *arg) {
    long id_ = (long)arg, sum = 0;
    for (int i = 0; i < 20000; i++) {
        @autoreleasepool {
            // many selectors: the method cache grows while other threads read it
            sum += [shared m0] + [shared m1] + [shared m2] + [shared m3] + [shared m4] + [shared m5] +
                   [shared m6] + [shared m7] + [shared m8] + [shared m9] + [shared m10] + [shared m11] +
                   [shared m12] + [shared m13] + [shared m14] + [shared m15];
            [shared bump:1];
            Counter *strong = weak_shared;     // loadWeakRetained under contention
            if (strong != shared) return (void *)-1;
            Tracked *t = [Tracked new];        // alloc/retain/release traffic
            id keep = t;
            (void)keep;
        }
    }
    (void)id_;
    return (void *)sum;
}

int main(void) {
    shared = [SubCounter new];
    weak_shared = shared;
    pthread_t t[8];
    for (long i = 0; i < 8; i++) CHECK(pthread_create(&t[i], NULL, worker, (void *)i) == 0);
    for (int i = 0; i < 8; i++) {
        void *r;
        CHECK(pthread_join(t[i], &r) == 0);
        CHECK((long)r == 20000L * (120 + 300));
    }
    CHECK([shared bump:0] == 8 * 20000);
    CHECK(deallocs == 8 * 20000);
    shared = nil;
    CHECK(weak_shared == nil);
    puts("objc threads ok");
    return 0;
}
