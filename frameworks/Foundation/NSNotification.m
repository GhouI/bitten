#import "FoundationInternal.h"
#include <pthread.h>

@implementation NSNotification
+ (instancetype)notificationWithName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    return [[self alloc] initWithName:name object:object userInfo:userInfo];
}
+ (instancetype)notificationWithName:(NSNotificationName)name object:(id)object {
    return [[self alloc] initWithName:name object:object userInfo:nil];
}
- (instancetype)initWithName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    if ((self = [super init])) {
        _name = [name copy];
        _object = object;
        _userInfo = [userInfo copy];
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description {
    return [NSString stringWithFormat:@"%s %p {name = %@; object = %@; userInfo = %@}", object_getClassName(self), self, _name, _object, _userInfo];
}
@end

@interface BNObservation : NSObject {
  @public
    __weak id observer;           /* selector-based registrations do not retain */
    void *observer_identity;
    SEL selector;
    NSString *name;
    __weak id object;
    BOOL has_object;
    void (^block)(NSNotification *);
}
@end
@implementation BNObservation
@end

@implementation NSNotificationCenter {
    NSMutableArray<BNObservation *> *_observations;
    NSRecursiveLock *_lock;
}
+ (NSNotificationCenter *)defaultCenter {
    static NSNotificationCenter *shared;
    @synchronized(self) {
        if (!shared) shared = [NSNotificationCenter new];
    }
    return shared;
}
- (instancetype)init {
    if ((self = [super init])) {
        _observations = [NSMutableArray array];
        _lock = [NSRecursiveLock new];
    }
    return self;
}
- (void)addObserver:(id)observer selector:(SEL)selector name:(NSNotificationName)name object:(id)object {
    if (!observer || !selector) return;
    BNObservation *o = [BNObservation new];
    o->observer = observer;
    o->observer_identity = (__bridge void *)observer;
    o->selector = selector;
    o->name = [name copy];
    o->object = object;
    o->has_object = object != nil;
    [_lock lock];
    [_observations addObject:o];
    [_lock unlock];
}
- (id)addObserverForName:(NSNotificationName)name object:(id)object queue:(id)queue usingBlock:(void (^)(NSNotification *))block {
    BNObservation *o = [BNObservation new];
    o->observer_identity = (__bridge void *)o;
    o->name = [name copy];
    o->object = object;
    o->has_object = object != nil;
    o->block = [block copy];
    [_lock lock];
    [_observations addObject:o];
    [_lock unlock];
    return o;
}
- (void)removeObserver:(id)observer { [self removeObserver:observer name:nil object:nil]; }
- (void)removeObserver:(id)observer name:(NSNotificationName)name object:(id)object {
    void *identity = (__bridge void *)observer;
    [_lock lock];
    for (NSUInteger i = _observations.count; i-- > 0;) {
        BNObservation *o = _observations[i];
        if (o->observer_identity != identity && o != observer) continue;
        if (name && ![o->name isEqualToString:name]) continue;
        if (object && o->object != object) continue;
        [_observations removeObjectAtIndex:i];
    }
    [_lock unlock];
}
- (void)postNotification:(NSNotification *)note {
    [_lock lock];
    NSArray<BNObservation *> *snapshot = [_observations copy];
    [_lock unlock];
    for (BNObservation *o in snapshot) {
        if (o->name && ![o->name isEqualToString:note.name]) continue;
        if (o->has_object && o->object != note.object) continue;
        if (o->block) {
            o->block(note);
        } else {
            id target = o->observer;
            if (target) ((void (*)(id, SEL, id))objc_msgSend)(target, o->selector, note);
        }
    }
}
- (void)postNotificationName:(NSNotificationName)name object:(id)object {
    [self postNotification:[NSNotification notificationWithName:name object:object userInfo:nil]];
}
- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    [self postNotification:[NSNotification notificationWithName:name object:object userInfo:userInfo]];
}
@end

/* ---- locks ---- */
@implementation NSLock {
    pthread_mutex_t _mutex;
}
- (instancetype)init {
    if ((self = [super init])) pthread_mutex_init(&_mutex, NULL);
    return self;
}
- (void)dealloc { pthread_mutex_destroy(&_mutex); }
- (void)lock { pthread_mutex_lock(&_mutex); }
- (void)unlock { pthread_mutex_unlock(&_mutex); }
- (BOOL)tryLock { return pthread_mutex_trylock(&_mutex) == 0; }
@end

@implementation NSRecursiveLock {
    pthread_mutex_t _mutex;
}
- (instancetype)init {
    if ((self = [super init])) {
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_mutex, &attr);
        pthread_mutexattr_destroy(&attr);
    }
    return self;
}
- (void)dealloc { pthread_mutex_destroy(&_mutex); }
- (void)lock { pthread_mutex_lock(&_mutex); }
- (void)unlock { pthread_mutex_unlock(&_mutex); }
- (BOOL)tryLock { return pthread_mutex_trylock(&_mutex) == 0; }
@end

@implementation NSCondition {
    pthread_mutex_t _mutex;
    pthread_cond_t _cond;
}
- (instancetype)init {
    if ((self = [super init])) {
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    return self;
}
- (void)dealloc {
    pthread_cond_destroy(&_cond);
    pthread_mutex_destroy(&_mutex);
}
- (void)lock { pthread_mutex_lock(&_mutex); }
- (void)unlock { pthread_mutex_unlock(&_mutex); }
- (void)wait { pthread_cond_wait(&_cond, &_mutex); }
- (BOOL)waitUntilDate:(NSDate *)limit {
    NSTimeInterval t = limit.timeIntervalSince1970;
    struct timespec ts = {(time_t)t, (long)((t - (double)(time_t)t) * 1e9)};
    return pthread_cond_timedwait(&_cond, &_mutex, &ts) == 0;
}
- (void)signal { pthread_cond_signal(&_cond); }
- (void)broadcast { pthread_cond_broadcast(&_cond); }
@end

/* ---- threads ----
 * An NSThread runs -main on a new pthread once started; -main calls the
 * block or target/selector it was created with (subclasses override it).
 * The thread object is retained for the thread's life and is
 * +currentThread there. */
NSNotificationName const NSThreadWillExitNotification = @"NSThreadWillExitNotification";
NSNotificationName const NSWillBecomeMultiThreadedNotification = @"NSWillBecomeMultiThreadedNotification";
NSNotificationName const NSDidBecomeSingleThreadedNotification = @"NSDidBecomeSingleThreadedNotification";

static pthread_key_t thread_key;
static NSThread *main_thread_object;
static int became_multithreaded;

@interface NSThread () {
  @public
    NSMutableDictionary *_dictionary;
    BOOL _main;
    void (^_block)(void);
    id _target;
    SEL _selector;
    id _argument;
    _Atomic int _state; /* 0 new, 1 executing, 2 finished */
    _Atomic BOOL _cancelled;
    NSQualityOfService _qos;
    double _priority;
    NSUInteger _stackSize;
}
@end

static void thread_key_destroy(void *value) { CFRelease(value); }

static void thread_will_exit(NSThread *t) {
    [[NSNotificationCenter defaultCenter] postNotificationName:NSThreadWillExitNotification object:t];
    t->_state = 2;
}

static void *thread_entry(void *arg) {
    NSThread *t = (__bridge NSThread *)arg; /* +1, released by thread_key_destroy */
    pthread_setspecific(thread_key, arg);
    @autoreleasepool {
        if (t.name) pthread_setname_np(t.name.UTF8String);
        t->_state = 1;
        [t main];
        thread_will_exit(t);
        t->_block = nil;
        t->_target = nil;
        t->_argument = nil;
    }
    return NULL;
}

@implementation NSThread
@synthesize name = _name;
+ (void)initialize {
    if (self != [NSThread class]) return;
    pthread_key_create(&thread_key, thread_key_destroy);
    /* Foundation is first used on the main thread in practice; a thread
     * that is the process's initial thread is the main thread. */
    main_thread_object = [NSThread new];
    main_thread_object->_main = YES;
    main_thread_object->_state = 1;
    main_thread_object->_qos = NSQualityOfServiceUserInteractive;
}
- (instancetype)init {
    if ((self = [super init])) {
        _qos = NSQualityOfServiceDefault;
        _priority = 0.5;
        _stackSize = 512 * 1024;
    }
    return self;
}
- (instancetype)initWithBlock:(void (^)(void))block {
    if ((self = [self init])) _block = [block copy];
    return self;
}
- (instancetype)initWithTarget:(id)target selector:(SEL)selector object:(id)argument {
    if ((self = [self init])) {
        _target = target;
        _selector = selector;
        _argument = argument;
    }
    return self;
}
+ (NSThread *)mainThread { return main_thread_object; }
+ (NSThread *)currentThread {
    if (pthread_main_np()) return main_thread_object;
    NSThread *t = (__bridge NSThread *)pthread_getspecific(thread_key);
    if (!t) {
        t = [NSThread new];
        t->_state = 1;
        pthread_setspecific(thread_key, (__bridge_retained void *)t);
    }
    return t;
}
+ (BOOL)isMainThread { return pthread_main_np() != 0; }
+ (BOOL)isMultiThreaded { return became_multithreaded != 0; }
+ (void)sleepForTimeInterval:(NSTimeInterval)seconds {
    if (seconds <= 0) return;
    struct timespec ts = {(time_t)seconds, (long)((seconds - (double)(time_t)seconds) * 1e9)};
    extern int nanosleep(const struct timespec *, struct timespec *);
    while (nanosleep(&ts, &ts) != 0 && errno == 4) {}
}
+ (void)sleepUntilDate:(NSDate *)date { [self sleepForTimeInterval:date.timeIntervalSinceNow]; }
+ (void)exit {
    NSThread *t = [self currentThread];
    if (t->_main) exit(0);
    thread_will_exit(t);
    pthread_exit(NULL);
}
+ (double)threadPriority { return [self currentThread].threadPriority; }
+ (BOOL)setThreadPriority:(double)p {
    [self currentThread].threadPriority = p;
    return YES;
}
+ (NSArray<NSNumber *> *)callStackReturnAddresses { return @[]; }
+ (NSArray<NSString *> *)callStackSymbols { return @[]; }
+ (void)detachNewThreadWithBlock:(void (^)(void))block { [[[NSThread alloc] initWithBlock:block] start]; }
+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument {
    [[[NSThread alloc] initWithTarget:target selector:selector object:argument] start];
}
- (void)main {
    if (_block) _block();
    else if (_target && _selector) ((void (*)(id, SEL, id))objc_msgSend)(_target, _selector, _argument);
}
- (void)start {
    int expected = 0;
    if (!__atomic_compare_exchange_n((int *)&_state, &expected, 1, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        [NSException raise:NSInvalidArgumentException format:@"*** -[NSThread start]: attempt to start the thread again"];
        return;
    }
    if (!__atomic_exchange_n(&became_multithreaded, 1, __ATOMIC_ACQ_REL))
        [[NSNotificationCenter defaultCenter] postNotificationName:NSWillBecomeMultiThreadedNotification object:nil];
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    if (_stackSize >= 16384) pthread_attr_setstacksize(&attr, _stackSize);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t handle;
    void *arg = (__bridge_retained void *)self;
    if (pthread_create(&handle, &attr, thread_entry, arg) != 0) {
        CFRelease(arg);
        _state = 2;
    }
    pthread_attr_destroy(&attr);
}
- (void)cancel { _cancelled = YES; }
- (BOOL)isCancelled { return _cancelled; }
- (BOOL)isExecuting { return _state == 1; }
- (BOOL)isFinished { return _state == 2; }
- (NSQualityOfService)qualityOfService { return _qos; }
- (void)setQualityOfService:(NSQualityOfService)q { _qos = q; }
- (double)threadPriority { return _priority; }
- (void)setThreadPriority:(double)p { _priority = p; }
- (NSUInteger)stackSize { return _stackSize; }
- (void)setStackSize:(NSUInteger)s { _stackSize = s; }
- (NSMutableDictionary *)threadDictionary {
    if (!_dictionary) _dictionary = [NSMutableDictionary dictionary];
    return _dictionary;
}
- (BOOL)isMainThread { return _main; }
@end

/* Distributed notifications reach other processes on macOS. Inside the
 * container nothing else listens, so this center delivers within the
 * process, which keeps an app's own observers working. */
@implementation NSDistributedNotificationCenter
+ (NSDistributedNotificationCenter *)defaultCenter {
    static NSDistributedNotificationCenter *shared;
    @synchronized(self) {
        if (!shared) shared = [NSDistributedNotificationCenter new];
    }
    return shared;
}
+ (NSDistributedNotificationCenter *)notificationCenterForType:(NSString *)type { return [self defaultCenter]; }
- (void)addObserver:(id)observer selector:(SEL)selector name:(NSNotificationName)name object:(NSString *)object
    suspensionBehavior:(NSUInteger)behavior {
    [self addObserver:observer selector:selector name:name object:object];
}
- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object userInfo:(NSDictionary *)userInfo
          deliverImmediately:(BOOL)immediately {
    [self postNotificationName:name object:object userInfo:userInfo];
}
- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object userInfo:(NSDictionary *)userInfo
                     options:(NSUInteger)options {
    [self postNotificationName:name object:object userInfo:userInfo];
}
@synthesize suspended = _suspended;
@end
