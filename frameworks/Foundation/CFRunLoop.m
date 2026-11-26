/* CFRunLoop over the main dispatch queue, as NSRunLoop is: the main run
 * loop is the main queue drained by -[NSRunLoop runMode:beforeDate:], which
 * tells observers when it is about to wait and when it has woken. Other
 * threads' run loops have no sources of their own. Also the CF constants
 * programs import through Foundation (bundle keys, the shared booleans and
 * empty collections' objects). */
#import <Foundation/Foundation.h>

const CFRunLoopMode kCFRunLoopDefaultMode = (__bridge CFStringRef)@"kCFRunLoopDefaultMode";
const CFRunLoopMode kCFRunLoopCommonModes = (__bridge CFStringRef)@"kCFRunLoopCommonModes";

const CFStringRef kCFBundleInfoDictionaryVersionKey = (__bridge CFStringRef)@"CFBundleInfoDictionaryVersion";
const CFStringRef kCFBundleExecutableKey = (__bridge CFStringRef)@"CFBundleExecutable";
const CFStringRef kCFBundleIdentifierKey = (__bridge CFStringRef)@"CFBundleIdentifier";
const CFStringRef kCFBundleVersionKey = (__bridge CFStringRef)@"CFBundleVersion";
const CFStringRef kCFBundleDevelopmentRegionKey = (__bridge CFStringRef)@"CFBundleDevelopmentRegion";
const CFStringRef kCFBundleNameKey = (__bridge CFStringRef)@"CFBundleName";
const CFStringRef kCFBundleLocalizationsKey = (__bridge CFStringRef)@"CFBundleLocalizations";

@interface __NSCFRunLoopObserver : NSObject {
  @public
    CFOptionFlags _activities;
    BOOL _repeats, _valid;
    CFIndex _order;
    void (^_block)(CFRunLoopObserverRef, CFRunLoopActivity);
}
@end
@implementation __NSCFRunLoopObserver
@end

static NSMutableArray<__NSCFRunLoopObserver *> *main_observers;

/* Called by the main NSRunLoop around each turn. */
void _bn_runloop_notify(CFRunLoopActivity activity) {
    if (!main_observers.count) return;
    NSArray *now = [main_observers copy];
    for (__NSCFRunLoopObserver *o in now) {
        if (!o->_valid || !(o->_activities & activity)) continue;
        o->_block((__bridge CFRunLoopObserverRef)o, activity);
        if (!o->_repeats) {
            o->_valid = NO;
            [main_observers removeObjectIdenticalTo:o];
        }
    }
}

CFRunLoopRef CFRunLoopGetMain(void) { return (__bridge CFRunLoopRef)[NSRunLoop mainRunLoop]; }
CFRunLoopRef CFRunLoopGetCurrent(void) { return (__bridge CFRunLoopRef)[NSRunLoop currentRunLoop]; }
void CFRunLoopRun(void) { [[NSRunLoop currentRunLoop] run]; }
CFRunLoopRunResult CFRunLoopRunInMode(CFRunLoopMode mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {
    [[NSRunLoop currentRunLoop] runMode:(__bridge NSString *)mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
    return returnAfterSourceHandled ? kCFRunLoopRunHandledSource : kCFRunLoopRunTimedOut;
}
void CFRunLoopStop(CFRunLoopRef rl) {}
void CFRunLoopWakeUp(CFRunLoopRef rl) {
    if ((__bridge NSRunLoop *)rl == [NSRunLoop mainRunLoop]) dispatch_async(dispatch_get_main_queue(), ^{});
}
void CFRunLoopPerformBlock(CFRunLoopRef rl, CFTypeRef mode, void (^block)(void)) {
    [(__bridge NSRunLoop *)rl performBlock:block];
}

CFRunLoopObserverRef CFRunLoopObserverCreateWithHandler(CFAllocatorRef allocator, CFOptionFlags activities,
                                                        Boolean repeats, CFIndex order,
                                                        void (^block)(CFRunLoopObserverRef, CFRunLoopActivity)) {
    __NSCFRunLoopObserver *o = [__NSCFRunLoopObserver new];
    o->_activities = activities;
    o->_repeats = repeats;
    o->_order = order;
    o->_valid = YES;
    o->_block = [block copy];
    return (__bridge_retained CFRunLoopObserverRef)o;
}
void CFRunLoopAddObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFRunLoopMode mode) {
    if ((__bridge NSRunLoop *)rl != [NSRunLoop mainRunLoop]) return;
    __NSCFRunLoopObserver *o = (__bridge __NSCFRunLoopObserver *)observer;
    if (!main_observers) main_observers = [NSMutableArray array];
    if ([main_observers indexOfObjectIdenticalTo:o] != NSNotFound) return;
    NSUInteger i = 0;
    while (i < main_observers.count && main_observers[i]->_order <= o->_order) i++;
    [main_observers insertObject:o atIndex:i];
}
void CFRunLoopRemoveObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFRunLoopMode mode) {
    [main_observers removeObjectIdenticalTo:(__bridge id)observer];
}
void CFRunLoopObserverInvalidate(CFRunLoopObserverRef observer) {
    __NSCFRunLoopObserver *o = (__bridge __NSCFRunLoopObserver *)observer;
    o->_valid = NO;
    [main_observers removeObjectIdenticalTo:o];
}
Boolean CFRunLoopObserverIsValid(CFRunLoopObserverRef observer) {
    return ((__bridge __NSCFRunLoopObserver *)observer)->_valid;
}
