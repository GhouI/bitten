/* NSOperation, NSBlockOperation and NSOperationQueue over dispatch.
 *
 * A queue starts ready operations (all dependencies finished) while fewer
 * than maxConcurrentOperationCount are running, each on a dispatch queue
 * (the main queue for +mainQueue, else the underlying queue or a global
 * one). An operation counts as finished when -isFinished says so: plain
 * operations finish when -start returns; asynchronous subclasses override
 * -isFinished, and since key-value observing is not implemented here the
 * queue polls it. */
#import "FoundationInternal.h"
#include <pthread.h>

static pthread_key_t current_queue_key;
static pthread_once_t key_once = PTHREAD_ONCE_INIT;
static void make_key(void) { pthread_key_create(&current_queue_key, NULL); }

@interface NSOperation ()
- (void)_bn_addWaitingQueue:(NSOperationQueue *)queue;
- (void)_bn_observeFinished;
@end

@interface NSOperationQueue ()
- (void)_bn_schedule;
@end

@implementation NSOperation {
    pthread_mutex_t _mutex;
    BOOL _cancelled, _executing, _finished, _completed;
    NSMutableArray<NSOperation *> *_deps;
    NSMutableArray *_waitingQueues; /* queues to poke when this finishes */
    dispatch_group_t _done;
    void (^_completionBlock)(void);
    NSString *_name;
    NSOperationQueuePriority _queuePriority;
    NSQualityOfService _qualityOfService;
}

- (instancetype)init {
    if ((self = [super init])) {
        pthread_mutex_init(&_mutex, NULL);
        _deps = [NSMutableArray array];
        _waitingQueues = [NSMutableArray array];
        _done = dispatch_group_create();
        dispatch_group_enter(_done);
        _qualityOfService = NSQualityOfServiceDefault;
    }
    return self;
}
- (void)dealloc {
    pthread_mutex_destroy(&_mutex);
    if (!_completed) dispatch_group_leave(_done);
    dispatch_release(_done);
}

- (void)start {
    pthread_mutex_lock(&_mutex);
    if (_finished || _executing) {
        pthread_mutex_unlock(&_mutex);
        return;
    }
    BOOL cancelled = _cancelled;
    if (!cancelled) _executing = YES;
    pthread_mutex_unlock(&_mutex);
    if (!cancelled) [self main];
    pthread_mutex_lock(&_mutex);
    _executing = NO;
    _finished = YES;
    pthread_mutex_unlock(&_mutex);
    [self _bn_observeFinished];
}
- (void)main {}

/* Runs once, when the operation is first seen finished. */
- (void)_bn_observeFinished {
    pthread_mutex_lock(&_mutex);
    if (_completed) {
        pthread_mutex_unlock(&_mutex);
        return;
    }
    _completed = YES;
    void (^completion)(void) = _completionBlock;
    NSArray *waiting = [_waitingQueues copy];
    [_waitingQueues removeAllObjects];
    pthread_mutex_unlock(&_mutex);
    if (completion) dispatch_async(dispatch_get_global_queue(0, 0), completion);
    dispatch_group_leave(_done);
    for (NSOperationQueue *q in waiting) [q _bn_schedule];
}
- (void)_bn_addWaitingQueue:(NSOperationQueue *)queue {
    pthread_mutex_lock(&_mutex);
    BOOL done = _completed;
    if (!done && ![_waitingQueues containsObject:queue]) [_waitingQueues addObject:queue];
    pthread_mutex_unlock(&_mutex);
    if (done) [queue _bn_schedule];
}

- (void)cancel {
    pthread_mutex_lock(&_mutex);
    _cancelled = YES;
    pthread_mutex_unlock(&_mutex);
}
- (BOOL)isCancelled { return _cancelled; }
- (BOOL)isExecuting { return _executing; }
- (BOOL)isFinished { return _finished; }
- (BOOL)isConcurrent { return [self isAsynchronous]; }
- (BOOL)isAsynchronous { return NO; }
- (BOOL)isReady {
    pthread_mutex_lock(&_mutex);
    NSArray *deps = [_deps copy];
    pthread_mutex_unlock(&_mutex);
    for (NSOperation *d in deps)
        if (![d isFinished]) return NO;
    return YES;
}

- (void)addDependency:(NSOperation *)op {
    pthread_mutex_lock(&_mutex);
    if (op && ![_deps containsObject:op]) [_deps addObject:op];
    pthread_mutex_unlock(&_mutex);
}
- (void)removeDependency:(NSOperation *)op {
    pthread_mutex_lock(&_mutex);
    [_deps removeObject:op];
    pthread_mutex_unlock(&_mutex);
}
- (NSArray<NSOperation *> *)dependencies {
    pthread_mutex_lock(&_mutex);
    NSArray *d = [_deps copy];
    pthread_mutex_unlock(&_mutex);
    return d;
}

- (void (^)(void))completionBlock { return _completionBlock; }
- (void)setCompletionBlock:(void (^)(void))block { _completionBlock = [block copy]; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name { _name = [name copy]; }
- (NSOperationQueuePriority)queuePriority { return _queuePriority; }
- (void)setQueuePriority:(NSOperationQueuePriority)p { _queuePriority = p; }
- (NSQualityOfService)qualityOfService { return _qualityOfService; }
- (void)setQualityOfService:(NSQualityOfService)q { _qualityOfService = q; }
- (double)threadPriority { return 0.5; }
- (void)setThreadPriority:(double)p {}

- (void)waitUntilFinished {
    /* Asynchronous subclasses finish without telling us; poll them. */
    while (dispatch_group_wait(_done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC)) != 0)
        if ([self isFinished]) [self _bn_observeFinished];
}
@end

@implementation NSBlockOperation {
    NSMutableArray *_blocks;
}
+ (instancetype)blockOperationWithBlock:(void (^)(void))block {
    NSBlockOperation *op = [self new];
    [op addExecutionBlock:block];
    return op;
}
- (instancetype)init {
    if ((self = [super init])) _blocks = [NSMutableArray array];
    return self;
}
- (void)addExecutionBlock:(void (^)(void))block {
    if (!block) BNRaise("NSInvalidArgumentException", "-[NSBlockOperation addExecutionBlock:]: block is nil");
    @synchronized(_blocks) { [_blocks addObject:[block copy]]; }
}
- (NSArray *)executionBlocks {
    @synchronized(_blocks) { return [_blocks copy]; }
}
- (void)main {
    NSArray *blocks = [self executionBlocks];
    if (blocks.count == 1) {
        ((void (^)(void))blocks[0])();
        return;
    }
    dispatch_group_t g = dispatch_group_create();
    for (void (^b)(void) in blocks) dispatch_group_async(g, dispatch_get_global_queue(0, 0), b);
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
    dispatch_release(g);
}
@end

@implementation NSOperationQueue {
    pthread_mutex_t _mutex;
    NSMutableArray<NSOperation *> *_ops;     /* not yet finished, in order */
    NSMutableSet *_started;                  /* of NSValue (pointers) */
    NSInteger _running;
    NSInteger _maxConcurrent;
    BOOL _suspended, _isMain;
    NSString *_name;
    dispatch_queue_t _underlying;
    dispatch_group_t _all;
    NSQualityOfService _qos;
}

+ (NSOperationQueue *)mainQueue {
    static NSOperationQueue *main;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        main = [NSOperationQueue new];
        main->_isMain = YES;
        main->_maxConcurrent = 1;
        main->_name = @"NSOperationQueue Main Queue";
        main->_underlying = dispatch_get_main_queue();
    });
    return main;
}
+ (NSOperationQueue *)currentQueue {
    pthread_once(&key_once, make_key);
    NSOperationQueue *q = (__bridge NSOperationQueue *)pthread_getspecific(current_queue_key);
    if (q) return q;
    return [NSThread isMainThread] ? [self mainQueue] : nil;
}

- (instancetype)init {
    if ((self = [super init])) {
        pthread_mutex_init(&_mutex, NULL);
        _ops = [NSMutableArray array];
        _started = [NSMutableSet set];
        _maxConcurrent = NSOperationQueueDefaultMaxConcurrentOperationCount;
        _all = dispatch_group_create();
        _qos = NSQualityOfServiceDefault;
        _name = [NSString stringWithFormat:@"NSOperationQueue %p", self];
    }
    return self;
}
- (void)dealloc {
    pthread_mutex_destroy(&_mutex);
    dispatch_release(_all);
}

- (dispatch_queue_t)_bn_target {
    return _underlying ? _underlying : dispatch_get_global_queue(0, 0);
}

- (void)_bn_finished:(NSOperation *)op {
    pthread_mutex_lock(&_mutex);
    [_ops removeObject:op];
    [_started removeObject:[NSValue valueWithPointer:(__bridge void *)op]];
    _running--;
    pthread_mutex_unlock(&_mutex);
    dispatch_group_leave(_all);
    [self _bn_schedule];
}

- (void)_bn_run:(NSOperation *)op {
    pthread_once(&key_once, make_key);
    void *previous = pthread_getspecific(current_queue_key);
    pthread_setspecific(current_queue_key, (__bridge void *)self);
    [op start];
    pthread_setspecific(current_queue_key, previous);
    [self _bn_waitForFinish:op];
}
- (void)_bn_waitForFinish:(NSOperation *)op {
    if ([op isFinished]) {
        [op _bn_observeFinished];
        [self _bn_finished:op];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC), dispatch_get_global_queue(0, 0), ^{
        [self _bn_waitForFinish:op];
    });
}

- (void)_bn_schedule {
    for (;;) {
        NSOperation *next = nil;
        pthread_mutex_lock(&_mutex);
        if (!_suspended && (_maxConcurrent < 0 || _running < _maxConcurrent)) {
            NSOperation *best = nil;
            for (NSOperation *op in _ops) {
                if ([_started containsObject:[NSValue valueWithPointer:(__bridge void *)op]]) continue;
                BOOL ready = YES;
                for (NSOperation *d in [op dependencies]) {
                    if (![d isFinished]) {
                        ready = NO;
                        [d _bn_addWaitingQueue:self];
                    }
                }
                if (!ready) continue;
                if (!best || op.queuePriority > best.queuePriority) best = op;
            }
            if (best) {
                [_started addObject:[NSValue valueWithPointer:(__bridge void *)best]];
                _running++;
                next = best;
            }
        }
        pthread_mutex_unlock(&_mutex);
        if (!next) return;
        dispatch_async([self _bn_target], ^{ [self _bn_run:next]; });
    }
}

- (void)addOperation:(NSOperation *)op {
    if (!op) BNRaise("NSInvalidArgumentException", "-[NSOperationQueue addOperation:]: operation is nil");
    pthread_mutex_lock(&_mutex);
    if ([_ops containsObject:op] || op.isFinished || op.isExecuting) {
        pthread_mutex_unlock(&_mutex);
        BNRaise("NSInvalidArgumentException",
                "-[NSOperationQueue addOperation:]: operation is finished, is executing or is already in a queue");
    }
    [_ops addObject:op];
    pthread_mutex_unlock(&_mutex);
    dispatch_group_enter(_all);
    [self _bn_schedule];
}
- (void)addOperations:(NSArray<NSOperation *> *)ops waitUntilFinished:(BOOL)wait {
    for (NSOperation *op in ops) [self addOperation:op];
    if (wait)
        for (NSOperation *op in ops) [op waitUntilFinished];
}
- (void)addOperationWithBlock:(void (^)(void))block {
    [self addOperation:[NSBlockOperation blockOperationWithBlock:block]];
}
- (void)addBarrierBlock:(void (^)(void))barrier {
    NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:barrier];
    for (NSOperation *other in [self operations]) [op addDependency:other];
    [self addOperation:op];
}

- (NSArray<__kindof NSOperation *> *)operations {
    pthread_mutex_lock(&_mutex);
    NSArray *a = [_ops copy];
    pthread_mutex_unlock(&_mutex);
    return a;
}
- (NSUInteger)operationCount { return [self operations].count; }
- (void)cancelAllOperations {
    for (NSOperation *op in [self operations]) [op cancel];
}
- (void)waitUntilAllOperationsAreFinished {
    for (NSOperation *op in [self operations]) [op waitUntilFinished];
    dispatch_group_wait(_all, DISPATCH_TIME_FOREVER);
}

- (NSInteger)maxConcurrentOperationCount { return _maxConcurrent; }
- (void)setMaxConcurrentOperationCount:(NSInteger)n {
    _maxConcurrent = n;
    [self _bn_schedule];
}
- (BOOL)isSuspended { return _suspended; }
- (void)setSuspended:(BOOL)suspended {
    _suspended = suspended;
    if (!suspended) [self _bn_schedule];
}
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name { _name = [name copy]; }
- (NSQualityOfService)qualityOfService { return _qos; }
- (void)setQualityOfService:(NSQualityOfService)q { _qos = q; }
- (dispatch_queue_t)underlyingQueue { return _underlying; }
- (void)setUnderlyingQueue:(dispatch_queue_t)q {
    if (_isMain) BNRaise("NSInvalidArgumentException", "the main queue's underlying queue cannot be changed");
    _underlying = q;
}
@end
