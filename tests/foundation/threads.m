// NSThread: subclasses override -main; block and target/selector threads;
// start, executing/finished, cancel, quality of service, the will-exit
// notification and +currentThread inside the thread.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

static _Atomic int ran;
static NSThread *seenCurrent;

@interface Worker : NSThread
@end
@implementation Worker
- (void)main {
    seenCurrent = [NSThread currentThread];
    while (!self.isCancelled) usleep(1000);
    ran = 1;
}
@end

@interface Target : NSObject
@property (atomic) id got;
@end
@implementation Target
- (void)run:(id)arg { self.got = arg; }
@end

static void wait_finished(NSThread *t) {
    for (int i = 0; i < 2000 && !t.isFinished; i++) usleep(1000);
}

int main(void) {
    @autoreleasepool {
        __block int exits = 0;
        id obs = [[NSNotificationCenter defaultCenter] addObserverForName:NSThreadWillExitNotification object:nil queue:nil
                                                               usingBlock:^(NSNotification *n) { __sync_fetch_and_add(&exits, 1); }];

        Worker *w = [Worker new];
        w.qualityOfService = NSQualityOfServiceUtility;
        w.name = @"worker";
        CHECK(w.qualityOfService == NSQualityOfServiceUtility);
        CHECK(!w.isExecuting && !w.isFinished && !w.isCancelled);
        [w start];
        for (int i = 0; i < 2000 && !w.isExecuting; i++) usleep(1000);
        CHECK(w.isExecuting);
        [w cancel];
        wait_finished(w);
        CHECK(w.isFinished && w.isCancelled && ran == 1);
        CHECK(seenCurrent == w);
        CHECK(NSThread.isMultiThreaded);

        __block _Atomic int blockRan = 0;
        NSThread *b = [[NSThread alloc] initWithBlock:^{ blockRan = 1; }];
        [b start];
        wait_finished(b);
        CHECK(blockRan == 1);

        Target *target = [Target new];
        NSThread *s = [[NSThread alloc] initWithTarget:target selector:@selector(run:) object:@"hello"];
        [s start];
        wait_finished(s);
        CHECK([target.got isEqual:@"hello"]);

        for (int i = 0; i < 2000 && exits < 3; i++) usleep(1000);
        CHECK(exits == 3);
        [[NSNotificationCenter defaultCenter] removeObserver:obs];
        CHECK([NSThread currentThread].isMainThread && [NSThread currentThread].isExecuting);
        puts("foundation threads ok");
    }
    return 0;
}
