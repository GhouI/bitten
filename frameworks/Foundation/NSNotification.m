#import "FoundationInternal.h"
#include <pthread.h>

@implementation NSNotification
+ (instancetype)notificationWithName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    NSNotification *n = [self new];
    n->_name = [name copy];
    n->_object = object;
    n->_userInfo = [userInfo copy];
    return n;
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

/* ---- threads ---- */
static pthread_key_t thread_key;
static NSThread *main_thread_object;

@interface NSThread () {
  @public
    NSMutableDictionary *_dictionary;
    BOOL _main;
    void (^_block)(void);
}
@end

static void thread_key_destroy(void *value) { CFRelease(value); }

static void *thread_entry(void *arg) {
    NSThread *t = (__bridge_transfer NSThread *)arg;
    pthread_setspecific(thread_key, (__bridge_retained void *)t);
    @autoreleasepool {
        if (t.name) pthread_setname_np(t.name.UTF8String);
        t->_block();
        t->_block = nil;
    }
    return NULL;
}

@implementation NSThread
+ (void)initialize {
    if (self != [NSThread class]) return;
    pthread_key_create(&thread_key, thread_key_destroy);
    /* Foundation is first used on the main thread in practice; a thread
     * that is the process's initial thread is the main thread. */
    main_thread_object = [NSThread new];
    main_thread_object->_main = YES;
}
+ (NSThread *)mainThread { return main_thread_object; }
+ (NSThread *)currentThread {
    if (pthread_main_np()) return main_thread_object;
    NSThread *t = (__bridge NSThread *)pthread_getspecific(thread_key);
    if (!t) {
        t = [NSThread new];
        pthread_setspecific(thread_key, (__bridge_retained void *)t);
    }
    return t;
}
+ (BOOL)isMainThread { return pthread_main_np() != 0; }
+ (void)sleepForTimeInterval:(NSTimeInterval)seconds {
    if (seconds <= 0) return;
    struct timespec ts = {(time_t)seconds, (long)((seconds - (double)(time_t)seconds) * 1e9)};
    extern int nanosleep(const struct timespec *, struct timespec *);
    while (nanosleep(&ts, &ts) != 0 && errno == 4) {}
}
+ (void)sleepUntilDate:(NSDate *)date { [self sleepForTimeInterval:date.timeIntervalSinceNow]; }
+ (void)detachNewThreadWithBlock:(void (^)(void))block {
    NSThread *t = [NSThread new];
    t->_block = [block copy];
    pthread_t handle;
    if (pthread_create(&handle, NULL, thread_entry, (__bridge_retained void *)t) == 0) pthread_detach(handle);
    else CFRelease((__bridge CFTypeRef)t);
}
+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument {
    [self detachNewThreadWithBlock:^{ ((void (*)(id, SEL, id))objc_msgSend)(target, selector, argument); }];
}
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
