/* NSRunLoop and NSTimer over dispatch.
 *
 * The main run loop is the main dispatch queue: running it waits on the
 * queue's wake descriptor (_dispatch_get_main_queue_port_4CF) and drains
 * it (_dispatch_main_queue_callback_4CF), which is also how timers and
 * performed blocks reach it. Other threads' run loops get a serial queue of
 * their own; their timers fire there. Modes are accepted and ignored: every
 * source runs in every mode. */
#import "FoundationInternal.h"
#include <poll.h>
#include <pthread.h>

int _dispatch_get_main_queue_port_4CF(void);
void _dispatch_main_queue_callback_4CF(void *msg);

NSRunLoopMode const NSDefaultRunLoopMode = @"kCFRunLoopDefaultMode";
NSRunLoopMode const NSRunLoopCommonModes = @"kCFRunLoopCommonModes";

static pthread_key_t loop_key;
static pthread_once_t loop_once = PTHREAD_ONCE_INIT;
static void make_loop_key(void) { pthread_key_create(&loop_key, NULL); }

@interface NSTimer ()
- (void)_bn_scheduleOn:(dispatch_queue_t)queue;
@end

@implementation NSRunLoop {
    dispatch_queue_t _queue;
    BOOL _isMain;
    NSString *_currentMode;
}

+ (NSRunLoop *)mainRunLoop {
    static NSRunLoop *main;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        main = [NSRunLoop new];
        main->_isMain = YES;
        main->_queue = dispatch_get_main_queue();
    });
    return main;
}
+ (NSRunLoop *)currentRunLoop {
    if ([NSThread isMainThread]) return [self mainRunLoop];
    pthread_once(&loop_once, make_loop_key);
    NSRunLoop *loop = (__bridge NSRunLoop *)pthread_getspecific(loop_key);
    if (!loop) {
        loop = [NSRunLoop new];
        loop->_queue = dispatch_queue_create("org.bitten.runloop", NULL);
        pthread_setspecific(loop_key, (__bridge_retained void *)loop); /* lives with the thread */
    }
    return loop;
}

- (dispatch_queue_t)_bn_queue { return _queue; }
- (NSRunLoopMode)currentMode { return _currentMode; }

- (void)addTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode { [timer _bn_scheduleOn:_queue]; }
- (void)performBlock:(void (^)(void))block { dispatch_async(_queue, block); }
- (void)performInModes:(NSArray<NSRunLoopMode> *)modes block:(void (^)(void))block { dispatch_async(_queue, block); }
- (void)performSelector:(SEL)selector target:(id)target argument:(id)arg order:(NSUInteger)order
                  modes:(NSArray<NSRunLoopMode> *)modes {
    dispatch_async(_queue, ^{
        ((void (*)(id, SEL, id))objc_msgSend)(target, selector, arg);
    });
}

/* Runs the loop once, waiting until `limit` at most; YES when something was
 * handled or the wait ended normally. */
- (BOOL)runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limit {
    NSTimeInterval wait = limit ? [limit timeIntervalSinceNow] : 0;
    if (wait < 0) wait = 0;
    if (!_isMain || ![NSThread isMainThread]) {
        /* A background loop's sources run on its own queue. */
        [NSThread sleepForTimeInterval:wait > 1 ? 1 : wait];
        return YES;
    }
    NSString *saved = _currentMode;
    _currentMode = mode;
    struct pollfd fd = {.fd = _dispatch_get_main_queue_port_4CF(), .events = POLLIN};
    int ms = wait > 86400 ? 86400000 : (int)(wait * 1000);
    poll(&fd, 1, ms);
    _dispatch_main_queue_callback_4CF(NULL);
    _currentMode = saved;
    return YES;
}
- (void)runUntilDate:(NSDate *)limit {
    while ([limit timeIntervalSinceNow] > 0)
        [self runMode:NSDefaultRunLoopMode beforeDate:limit];
}
- (void)run {
    for (;;) [self runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
}
- (void)acceptInputForMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limit {
    [self runMode:mode beforeDate:limit];
}
- (NSDate *)limitDateForMode:(NSRunLoopMode)mode { return [NSDate distantFuture]; }
@end

@implementation NSTimer {
    dispatch_source_t _source;
    void (^_block)(NSTimer *);
    id _target;
    SEL _selector;
    id _userInfo;
    NSTimeInterval _interval, _tolerance;
    NSDate *_fireDate;
    BOOL _repeats, _valid;
}

- (instancetype)_initWithFireDate:(NSDate *)date interval:(NSTimeInterval)ti repeats:(BOOL)repeats {
    if ((self = [super init])) {
        _fireDate = date;
        _interval = ti > 0 ? ti : 0.0001;
        _repeats = repeats;
        _valid = YES;
    }
    return self;
}
- (instancetype)initWithFireDate:(NSDate *)date interval:(NSTimeInterval)ti repeats:(BOOL)repeats
                           block:(void (^)(NSTimer *))block {
    if ((self = [self _initWithFireDate:date interval:ti repeats:repeats])) _block = [block copy];
    return self;
}
- (instancetype)initWithFireDate:(NSDate *)date interval:(NSTimeInterval)ti target:(id)target selector:(SEL)s
                        userInfo:(id)ui repeats:(BOOL)rep {
    if ((self = [self _initWithFireDate:date interval:ti repeats:rep])) {
        _target = target;
        _selector = s;
        _userInfo = ui;
    }
    return self;
}
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti repeats:(BOOL)repeats block:(void (^)(NSTimer *))block {
    return [[self alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:ti] interval:ti repeats:repeats block:block];
}
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti repeats:(BOOL)repeats block:(void (^)(NSTimer *))block {
    NSTimer *t = [self timerWithTimeInterval:ti repeats:repeats block:block];
    [[NSRunLoop currentRunLoop] addTimer:t forMode:NSDefaultRunLoopMode];
    return t;
}
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)t selector:(SEL)s userInfo:(id)ui repeats:(BOOL)rep {
    return [[self alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:ti] interval:ti target:t selector:s
                                 userInfo:ui repeats:rep];
}
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)t selector:(SEL)s userInfo:(id)ui
                                    repeats:(BOOL)rep {
    NSTimer *timer = [self timerWithTimeInterval:ti target:t selector:s userInfo:ui repeats:rep];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    return timer;
}

- (void)_bn_scheduleOn:(dispatch_queue_t)queue {
    @synchronized(self) {
        if (!_valid || _source) return;
        _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        NSTimeInterval delay = [_fireDate timeIntervalSinceNow];
        if (delay < 0) delay = 0;
        dispatch_source_set_timer(_source, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                                  _repeats ? (uint64_t)(_interval * NSEC_PER_SEC) : DISPATCH_TIME_FOREVER,
                                  (uint64_t)(_tolerance * NSEC_PER_SEC));
        /* The source keeps the timer alive while it is scheduled, as a run
         * loop retains its timers. */
        NSTimer *timer = self;
        dispatch_source_set_event_handler(_source, ^{ [timer fire]; });
        dispatch_resume(_source);
    }
}

- (void)fire {
    if (!_valid) return;
    if (_block) _block(self);
    else if (_target) ((void (*)(id, SEL, id))objc_msgSend)(_target, _selector, self);
    if (_repeats) _fireDate = [NSDate dateWithTimeIntervalSinceNow:_interval];
    else [self invalidate];
}
- (void)invalidate {
    dispatch_source_t source;
    @synchronized(self) {
        _valid = NO;
        source = _source;
        _source = NULL;
        _target = nil;
        _userInfo = nil;
    }
    if (source) {
        /* Drop the handler (and with it the timer) once cancelled. */
        dispatch_source_set_event_handler(source, ^{});
        dispatch_source_cancel(source);
        dispatch_release(source);
    }
}
- (BOOL)isValid { return _valid; }
- (NSDate *)fireDate { return _fireDate; }
- (void)setFireDate:(NSDate *)date {
    _fireDate = date;
    @synchronized(self) {
        if (_source) {
            NSTimeInterval delay = [date timeIntervalSinceNow];
            if (delay < 0) delay = 0;
            dispatch_source_set_timer(_source, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                                      _repeats ? (uint64_t)(_interval * NSEC_PER_SEC) : DISPATCH_TIME_FOREVER,
                                      (uint64_t)(_tolerance * NSEC_PER_SEC));
        }
    }
}
- (NSTimeInterval)timeInterval { return _repeats ? _interval : 0; }
- (NSTimeInterval)tolerance { return _tolerance; }
- (void)setTolerance:(NSTimeInterval)t { _tolerance = t; }
- (id)userInfo { return _userInfo; }
@end
