// Foundation: NSOperation, NSBlockOperation, NSOperationQueue and
// NSDistributedNotificationCenter.
#import <Foundation/Foundation.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

@interface Watcher : NSObject
@property (nonatomic, strong) NSMutableArray *seen;
@end
@implementation Watcher
- (instancetype)init { if ((self = [super init])) _seen = [NSMutableArray array]; return self; }
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [_seen addObject:@{@"key" : keyPath, @"change" : change}];
}
@end
@interface Model : NSObject
@property (nonatomic) int level;
@end
@implementation Model
@end

@interface Counter : NSObject
@property (atomic) int hits;
- (void)hit:(NSNotification *)n;
@end
@implementation Counter
- (void)hit:(NSNotification *)n { self.hits++; }
@end

int main(void) {
    @autoreleasepool {
        // Order and dependencies on a serial queue.
        NSOperationQueue *q = [NSOperationQueue new];
        q.maxConcurrentOperationCount = 1;
        NSMutableArray *order = [NSMutableArray array];
        NSBlockOperation *a = [NSBlockOperation blockOperationWithBlock:^{ @synchronized(order) { [order addObject:@"a"]; } }];
        NSBlockOperation *b = [NSBlockOperation blockOperationWithBlock:^{ @synchronized(order) { [order addObject:@"b"]; } }];
        NSBlockOperation *c = [NSBlockOperation blockOperationWithBlock:^{ @synchronized(order) { [order addObject:@"c"]; } }];
        [a addDependency:c]; // c must run before a
        __block int completed = 0;
        b.completionBlock = ^{ completed = 1; };
        [q addOperations:@[ a, b, c ] waitUntilFinished:YES];
        CHECK([order isEqual:(@[ @"b", @"c", @"a" ])]);
        CHECK(a.isFinished && b.isFinished && c.isFinished && !a.isExecuting);
        for (int i = 0; i < 100 && !completed; i++) usleep(1000);
        CHECK(completed == 1);
        CHECK(q.operationCount == 0);

        // Concurrency is limited by maxConcurrentOperationCount.
        NSOperationQueue *p = [NSOperationQueue new];
        p.maxConcurrentOperationCount = 2;
        static _Atomic int running, peak, total;
        for (int i = 0; i < 8; i++)
            [p addOperationWithBlock:^{
                int now = atomic_fetch_add(&running, 1) + 1;
                int seen = atomic_load(&peak);
                while (now > seen && !atomic_compare_exchange_weak(&peak, &seen, now)) {}
                usleep(5000);
                atomic_fetch_sub(&running, 1);
                atomic_fetch_add(&total, 1);
            }];
        [p waitUntilAllOperationsAreFinished];
        CHECK(atomic_load(&total) == 8 && atomic_load(&peak) <= 2 && atomic_load(&peak) >= 1);

        // Cancelled operations finish without running.
        NSOperationQueue *s = [NSOperationQueue new];
        s.suspended = YES;
        __block BOOL ran = NO;
        NSBlockOperation *x = [NSBlockOperation blockOperationWithBlock:^{ ran = YES; }];
        [s addOperation:x];
        [x cancel];
        s.suspended = NO;
        [x waitUntilFinished];
        CHECK(!ran && x.isCancelled && x.isFinished);

        // currentQueue inside an operation.
        __block NSOperationQueue *seen = nil;
        [q addOperations:@[ [NSBlockOperation blockOperationWithBlock:^{ seen = [NSOperationQueue currentQueue]; }] ]
            waitUntilFinished:YES];
        CHECK(seen == q);
        CHECK([NSOperationQueue mainQueue] == [NSOperationQueue mainQueue]);
        CHECK([NSOperationQueue currentQueue] == [NSOperationQueue mainQueue]);

        // Distributed notifications are delivered within the process.
        Counter *counter = [Counter new];
        NSDistributedNotificationCenter *dc = [NSDistributedNotificationCenter defaultCenter];
        [dc addObserver:counter selector:@selector(hit:) name:@"org.example.ping" object:nil
            suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
        [dc postNotificationName:@"org.example.ping" object:nil userInfo:nil deliverImmediately:YES];
        CHECK(counter.hits == 1);
        [dc removeObserver:counter];
        // Hash and map tables, strong and weak.
        NSHashTable *strong = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];
        [strong addObject:@"a"];
        [strong addObject:[@"a" mutableCopy]]; // equal: not added again
        [strong addObject:@"b"];
        CHECK(strong.count == 2 && [strong containsObject:@"b"] && ![strong containsObject:@"c"]);
        NSHashTable *weak = [NSHashTable weakObjectsHashTable];
        @autoreleasepool {
            NSObject *temp = [NSObject new];
            [weak addObject:temp];
            CHECK(weak.count == 1);
        }
        CHECK(weak.count == 0); // the member went away
        int members = 0;
        for (id o in strong) members += o != nil;
        CHECK(members == 2);
        NSMapTable *map = [NSMapTable strongToWeakObjectsMapTable];
        NSObject *value = [NSObject new];
        [map setObject:value forKey:@"k"];
        CHECK([map objectForKey:@"k"] == value && map.count == 1);
        value = nil;
        CHECK([map objectForKey:@"k"] == nil && map.count == 0);
        NSMapTable *ident = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
                                                  valueOptions:NSPointerFunctionsStrongMemory];
        NSString *k1 = [@"key" mutableCopy], *k2 = [@"key" mutableCopy];
        [ident setObject:@1 forKey:k1];
        CHECK([ident objectForKey:k2] == nil && [[ident objectForKey:k1] intValue] == 1);
        // Key-value coding and observing.
        Model *model = [Model new];
        [model setValue:@5 forKey:@"level"];
        CHECK(model.level == 5 && [[model valueForKey:@"level"] intValue] == 5);
        Watcher *watcher = [Watcher new];
        [model addObserver:watcher forKeyPath:@"level"
                   options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionInitial
                   context:NULL];
        CHECK(watcher.seen.count == 1 && [watcher.seen[0][@"change"][NSKeyValueChangeNewKey] intValue] == 5);
        [model willChangeValueForKey:@"level"];
        model.level = 9;
        [model didChangeValueForKey:@"level"];
        CHECK(watcher.seen.count == 2);
        NSDictionary *change = watcher.seen[1][@"change"];
        CHECK([change[NSKeyValueChangeOldKey] intValue] == 5 && [change[NSKeyValueChangeNewKey] intValue] == 9);
        [model setValue:@11 forKey:@"level"]; // KVC setters announce the change
        CHECK(watcher.seen.count == 3 && [watcher.seen[2][@"change"][NSKeyValueChangeNewKey] intValue] == 11);
        [model removeObserver:watcher forKeyPath:@"level"];
        [model setValue:@12 forKey:@"level"];
        CHECK(watcher.seen.count == 3);
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"org.example.kvo"];
        Watcher *dw = [Watcher new];
        [defaults addObserver:dw forKeyPath:@"theme" options:NSKeyValueObservingOptionNew context:NULL];
        [defaults setObject:@"dark" forKey:@"theme"];
        CHECK(dw.seen.count == 1 && [dw.seen[0][@"change"][NSKeyValueChangeNewKey] isEqual:@"dark"]);
        [defaults removeObjectForKey:@"theme"];
        [defaults removeObserver:dw forKeyPath:@"theme"];
        printf("ok\n");
    }
    return 0;
}
