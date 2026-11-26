/* NSAnimationContext and animator proxies. Changes made in an animation
 * group take effect at once (there is no compositor to interpolate them);
 * completion handlers run when the outermost group ends, on the next turn
 * of the main loop, as they would after a zero-length animation. */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSAnimationContext {
    NSTimeInterval _duration;
    id _timingFunction;
    BOOL _allowsImplicitAnimation;
    void (^_completionHandler)(void);
}
static NSMutableArray<NSAnimationContext *> *stack(void) {
    NSMutableDictionary *t = [NSThread currentThread].threadDictionary;
    NSMutableArray *s = t[@"BNAnimationContextStack"];
    if (!s) t[@"BNAnimationContextStack"] = s = [NSMutableArray array];
    return s;
}
+ (NSAnimationContext *)currentContext {
    NSMutableArray *s = stack();
    if (!s.count) {
        NSAnimationContext *c = [[NSAnimationContext alloc] init];
        c->_duration = 0.25;
        [s addObject:c];
    }
    return s.lastObject;
}
+ (void)beginGrouping {
    NSAnimationContext *c = [[NSAnimationContext alloc] init];
    c->_duration = 0.25;
    [stack() addObject:c];
}
+ (void)endGrouping {
    NSMutableArray *s = stack();
    if (!s.count) return;
    NSAnimationContext *c = s.lastObject;
    [s removeLastObject];
    void (^done)(void) = c->_completionHandler;
    if (done) dispatch_async(dispatch_get_main_queue(), done);
}
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *))changes completionHandler:(void (^)(void))completion {
    [self beginGrouping];
    NSAnimationContext *c = [self currentContext];
    if (completion) c.completionHandler = completion;
    if (changes) changes(c);
    [self endGrouping];
}
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *))changes {
    [self runAnimationGroup:changes completionHandler:nil];
}
- (NSTimeInterval)duration { return _duration; }
- (void)setDuration:(NSTimeInterval)d { _duration = d; }
- (id)timingFunction { return _timingFunction; }
- (void)setTimingFunction:(id)f { _timingFunction = f; }
- (BOOL)allowsImplicitAnimation { return _allowsImplicitAnimation; }
- (void)setAllowsImplicitAnimation:(BOOL)b { _allowsImplicitAnimation = b; }
- (void (^)(void))completionHandler { return _completionHandler; }
- (void)setCompletionHandler:(void (^)(void))h { _completionHandler = [h copy]; }
@end

/* The animator proxy is the object itself: setting a property through it
 * sets the property. */
@implementation NSView (BittenAnimator)
- (instancetype)animator { return self; }
- (NSDictionary *)animations { return objc_getAssociatedObject(self, @selector(animations)) ?: @{}; }
- (void)setAnimations:(NSDictionary *)a {
    objc_setAssociatedObject(self, @selector(animations), [a copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (id)animationForKey:(NSString *)key { return self.animations[key]; }
+ (id)defaultAnimationForKey:(NSString *)key { return nil; }
@end
@implementation NSWindow (BittenAnimator)
- (instancetype)animator { return self; }
- (NSDictionary *)animations { return objc_getAssociatedObject(self, @selector(animations)) ?: @{}; }
- (void)setAnimations:(NSDictionary *)a {
    objc_setAssociatedObject(self, @selector(animations), [a copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (id)animationForKey:(NSString *)key { return self.animations[key]; }
+ (id)defaultAnimationForKey:(NSString *)key { return nil; }
@end
