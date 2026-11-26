/* Animations, timing functions, transactions and display links. Nothing
 * is interpolated: a layer keeps its model values and an added animation
 * reports start and, after its duration, a finished stop to its delegate
 * (see -[CALayer addAnimation:forKey:]). Transactions nest per thread; the
 * outermost commit runs the completion block on the main queue. */
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <pthread.h>

@interface CAAnimation ()
- (void)_bn_copyFrom:(id)other;
@end

/* ---- CAMediaTimingFunction ---- */

@implementation CAMediaTimingFunction {
    float _p[4];
}
+ (instancetype)functionWithName:(CAMediaTimingFunctionName)name {
    if ([name isEqualToString:kCAMediaTimingFunctionLinear]) return [self functionWithControlPoints:0 :0 :1 :1];
    if ([name isEqualToString:kCAMediaTimingFunctionEaseIn]) return [self functionWithControlPoints:0.42f :0 :1 :1];
    if ([name isEqualToString:kCAMediaTimingFunctionEaseOut]) return [self functionWithControlPoints:0 :0 :0.58f :1];
    if ([name isEqualToString:kCAMediaTimingFunctionEaseInEaseOut]) return [self functionWithControlPoints:0.42f :0 :0.58f :1];
    return [self functionWithControlPoints:0.25f :0.1f :0.25f :1];
}
+ (instancetype)functionWithControlPoints:(float)c1x :(float)c1y :(float)c2x :(float)c2y {
    return [[self alloc] initWithControlPoints:c1x :c1y :c2x :c2y];
}
- (instancetype)initWithControlPoints:(float)c1x :(float)c1y :(float)c2x :(float)c2y {
    if ((self = [super init])) { _p[0] = c1x; _p[1] = c1y; _p[2] = c2x; _p[3] = c2y; }
    return self;
}
/* Points 0 and 3 are the curve's ends, (0,0) and (1,1). */
- (void)getControlPointAtIndex:(size_t)idx values:(float *)ptr {
    switch (idx) {
    case 0: ptr[0] = 0; ptr[1] = 0; break;
    case 1: ptr[0] = _p[0]; ptr[1] = _p[1]; break;
    case 2: ptr[0] = _p[2]; ptr[1] = _p[3]; break;
    default: ptr[0] = 1; ptr[1] = 1; break;
    }
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<CAMediaTimingFunction: (%g, %g) (%g, %g)>", _p[0], _p[1], _p[2], _p[3]];
}
@end

/* ---- animations ---- */

@implementation CAAnimation
@synthesize timingFunction = _timingFunction, delegate = _delegate, removedOnCompletion = _removedOnCompletion,
            preferredFrameRateRange = _preferredFrameRateRange, beginTime = _beginTime, timeOffset = _timeOffset,
            duration = _duration, repeatDuration = _repeatDuration, repeatCount = _repeatCount, speed = _speed,
            autoreverses = _autoreverses, fillMode = _fillMode;
+ (instancetype)animation { return [self new]; }
+ (id)defaultValueForKey:(NSString *)key { return nil; }
- (BOOL)shouldArchiveValueForKey:(NSString *)key { return YES; }
- (instancetype)init {
    if ((self = [super init])) {
        _removedOnCompletion = YES;
        _speed = 1;
        _fillMode = kCAFillModeRemoved;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    CAAnimation *a = [[[self class] allocWithZone:zone] init];
    [a _bn_copyFrom:self];
    return a;
}
- (void)_bn_copyFrom:(id)other {
    CAAnimation *o = other;
    _timingFunction = o->_timingFunction;
    _delegate = o->_delegate;
    _removedOnCompletion = o->_removedOnCompletion;
    _preferredFrameRateRange = o->_preferredFrameRateRange;
    _beginTime = o->_beginTime;
    _timeOffset = o->_timeOffset;
    _duration = o->_duration;
    _repeatDuration = o->_repeatDuration;
    _repeatCount = o->_repeatCount;
    _speed = o->_speed;
    _autoreverses = o->_autoreverses;
    _fillMode = o->_fillMode;
}
/* As the action for a key: add itself to the layer under that key. */
- (void)runActionForKey:(NSString *)event object:(id)anObject arguments:(NSDictionary *)dict {
    if ([anObject isKindOfClass:[CALayer class]]) [(CALayer *)anObject addAnimation:self forKey:event];
}
@end

@implementation CAPropertyAnimation
@synthesize keyPath = _keyPath, additive = _additive, cumulative = _cumulative, valueFunction = _valueFunction;
+ (instancetype)animationWithKeyPath:(NSString *)path {
    CAPropertyAnimation *a = [self new];
    a.keyPath = path;
    return a;
}
- (void)_bn_copyFrom:(id)other {
    CAPropertyAnimation *o = other;
    [super _bn_copyFrom:o];
    _keyPath = [o->_keyPath copy];
    _additive = o->_additive;
    _cumulative = o->_cumulative;
    _valueFunction = o->_valueFunction;
}
- (NSString *)description { return [NSString stringWithFormat:@"<%@: %p; keyPath = %@>", [self class], (void *)self, _keyPath]; }
@end

@implementation CABasicAnimation
@synthesize fromValue = _fromValue, toValue = _toValue, byValue = _byValue;
- (void)_bn_copyFrom:(id)other {
    CABasicAnimation *o = other;
    [super _bn_copyFrom:o];
    _fromValue = o->_fromValue;
    _toValue = o->_toValue;
    _byValue = o->_byValue;
}
@end

@implementation CAKeyframeAnimation {
    CGPathRef _path;
}
@synthesize values = _values, keyTimes = _keyTimes, timingFunctions = _timingFunctions,
            calculationMode = _calculationMode, tensionValues = _tensionValues,
            continuityValues = _continuityValues, biasValues = _biasValues, rotationMode = _rotationMode;
- (instancetype)init {
    if ((self = [super init])) _calculationMode = kCAAnimationLinear;
    return self;
}
- (void)dealloc { if (_path) CGPathRelease(_path); }
- (CGPathRef)path { return _path; }
- (void)setPath:(CGPathRef)p {
    CGPathRef copy = p ? CGPathCreateCopy(p) : NULL;
    if (_path) CGPathRelease(_path);
    _path = copy;
}
- (void)_bn_copyFrom:(id)other {
    CAKeyframeAnimation *o = other;
    [super _bn_copyFrom:o];
    _values = [o->_values copy];
    self.path = o->_path;
    _keyTimes = [o->_keyTimes copy];
    _timingFunctions = [o->_timingFunctions copy];
    _calculationMode = [o->_calculationMode copy];
    _tensionValues = [o->_tensionValues copy];
    _continuityValues = [o->_continuityValues copy];
    _biasValues = [o->_biasValues copy];
    _rotationMode = [o->_rotationMode copy];
}
@end

/* A damped harmonic oscillator: x'' = -(k/m) x - (c/m) x'. */
@implementation CASpringAnimation
@synthesize mass = _mass, stiffness = _stiffness, damping = _damping, initialVelocity = _initialVelocity,
            allowsOverdamping = _allowsOverdamping;
- (instancetype)init {
    if ((self = [super init])) { _mass = 1; _stiffness = 100; _damping = 10; }
    return self;
}
/* Apple's perceptual parameters: stiffness = (2π/d)², damping from the bounce. */
- (instancetype)initWithPerceptualDuration:(CFTimeInterval)d bounce:(CGFloat)bounce {
    if ((self = [self init])) {
        if (d <= 0) d = 0.5;
        _mass = 1;
        _stiffness = pow(2 * M_PI / d, 2);
        _damping = bounce >= 0 ? (1 - bounce) * 4 * M_PI / d : 4 * M_PI / (d * (1 + bounce));
        self.duration = self.settlingDuration;
    }
    return self;
}
- (CGFloat)perceptualDuration { return _stiffness > 0 ? 2 * M_PI / sqrt(_stiffness / _mass) : 0; }
- (CGFloat)bounce {
    CGFloat d = self.perceptualDuration;
    if (d <= 0) return 0;
    CGFloat crit = 4 * M_PI / d;
    return _damping <= crit ? 1 - _damping / crit : crit / _damping - 1;
}
/* Time until the envelope falls under 0.1% of the start. */
- (CFTimeInterval)settlingDuration {
    if (_mass <= 0 || _stiffness <= 0) return 0;
    CGFloat w0 = sqrt(_stiffness / _mass), zeta = _damping / (2 * sqrt(_stiffness * _mass));
    if (zeta <= 0) return INFINITY;
    CGFloat decay = zeta < 1 ? zeta * w0 : w0 * (zeta - sqrt(zeta * zeta - 1));
    return decay > 0 ? log(1000) / decay : 0;
}
- (void)_bn_copyFrom:(id)other {
    CASpringAnimation *o = other;
    [super _bn_copyFrom:o];
    _mass = o->_mass;
    _stiffness = o->_stiffness;
    _damping = o->_damping;
    _initialVelocity = o->_initialVelocity;
    _allowsOverdamping = o->_allowsOverdamping;
}
@end

@implementation CATransition
@synthesize type = _type, subtype = _subtype, startProgress = _startProgress, endProgress = _endProgress;
- (instancetype)init {
    if ((self = [super init])) { _type = kCATransitionFade; _endProgress = 1; }
    return self;
}
- (void)_bn_copyFrom:(id)other {
    CATransition *o = other;
    [super _bn_copyFrom:o];
    _type = [o->_type copy];
    _subtype = [o->_subtype copy];
    _startProgress = o->_startProgress;
    _endProgress = o->_endProgress;
}
@end

@implementation CAAnimationGroup
@synthesize animations = _animations;
- (void)_bn_copyFrom:(id)other {
    CAAnimationGroup *o = other;
    [super _bn_copyFrom:o];
    _animations = [o->_animations copy];
}
@end

/* ---- CATransaction ---- */

@interface BNTransaction : NSObject {
@public
    NSMutableDictionary *values;
    void (^completion)(void);
}
@end
@implementation BNTransaction
@end

static pthread_key_t stack_key;
static pthread_once_t stack_once = PTHREAD_ONCE_INIT;
static NSRecursiveLock *big_lock;

static void stack_free(void *p) { CFRelease(p); }
static void stack_init(void) {
    pthread_key_create(&stack_key, stack_free);
    big_lock = [NSRecursiveLock new];
}

static NSMutableArray<BNTransaction *> *stack(void) {
    pthread_once(&stack_once, stack_init);
    void *p = pthread_getspecific(stack_key);
    if (!p) {
        p = (__bridge_retained void *)[NSMutableArray array];
        pthread_setspecific(stack_key, p);
    }
    return (__bridge NSMutableArray *)p;
}

/* The innermost transaction, begun implicitly if none is open; an implicit
 * one is committed on the next main-queue turn, as Apple's are. */
static BNTransaction *current(void) {
    NSMutableArray *s = stack();
    if (!s.count) {
        [CATransaction begin];
        dispatch_async(dispatch_get_main_queue(), ^{ [CATransaction flush]; });
    }
    return s.lastObject;
}

@implementation CATransaction
+ (void)begin {
    BNTransaction *t = [BNTransaction new];
    t->values = [NSMutableDictionary dictionary];
    [stack() addObject:t];
}
+ (void)commit {
    NSMutableArray *s = stack();
    BNTransaction *t = s.lastObject;
    if (!t) return;
    [s removeLastObject];
    void (^done)(void) = t->completion;
    if (!done) return;
    BNTransaction *outer = s.lastObject;
    if (outer) {                                   /* runs when the outer one does */
        void (^prev)(void) = outer->completion;
        outer->completion = prev ? ^{ prev(); done(); } : done;
    } else {
        dispatch_async(dispatch_get_main_queue(), done);
    }
}
+ (void)flush {
    while (stack().count) [self commit];
}
+ (void)lock { pthread_once(&stack_once, stack_init); [big_lock lock]; }
+ (void)unlock { [big_lock unlock]; }

+ (id)valueForKey:(NSString *)key {
    for (BNTransaction *t in [stack() reverseObjectEnumerator]) {
        id v = t->values[key];
        if (v) return v;
    }
    return nil;
}
+ (void)setValue:(id)v forKey:(NSString *)key {
    BNTransaction *t = current();
    if (v) t->values[key] = v;
    else [t->values removeObjectForKey:key];
}
+ (CFTimeInterval)animationDuration {
    NSNumber *n = [self valueForKey:@"animationDuration"];
    return n ? n.doubleValue : 0.25;
}
+ (void)setAnimationDuration:(CFTimeInterval)dur { [self setValue:@(dur) forKey:@"animationDuration"]; }
+ (CAMediaTimingFunction *)animationTimingFunction { return [self valueForKey:@"animationTimingFunction"]; }
+ (void)setAnimationTimingFunction:(CAMediaTimingFunction *)f { [self setValue:f forKey:@"animationTimingFunction"]; }
+ (BOOL)disableActions { return [[self valueForKey:@"disableActions"] boolValue]; }
+ (void)setDisableActions:(BOOL)flag { [self setValue:@(flag) forKey:@"disableActions"]; }
+ (void (^)(void))completionBlock {
    NSArray *s = stack();
    BNTransaction *t = s.lastObject;
    if (!t) return nil;
    return t->completion;
}
+ (void)setCompletionBlock:(void (^)(void))block { current()->completion = [block copy]; }
@end

/* ---- CADisplayLink: a 60 Hz timer on the run loop it is added to ---- */

@implementation CADisplayLink {
    __weak id _target;
    SEL _selector;
    NSTimer *_timer;
    CFTimeInterval _timestamp, _duration;
}
@synthesize paused = _paused, preferredFrameRateRange = _preferredFrameRateRange;

+ (CADisplayLink *)_bn_displayLinkWithTarget:(id)target selector:(SEL)sel {
    CADisplayLink *l = [self new];
    l->_target = target;
    l->_selector = sel;
    l->_duration = 1.0 / 60;
    return l;
}
- (CFTimeInterval)timestamp { return _timestamp; }
- (CFTimeInterval)duration { return _duration; }
- (CFTimeInterval)targetTimestamp { return _timestamp + _duration; }

- (CFTimeInterval)_bn_interval {
    float fps = _preferredFrameRateRange.preferred > 0 ? _preferredFrameRateRange.preferred :
                _preferredFrameRateRange.maximum > 0 ? _preferredFrameRateRange.maximum : 60;
    return 1.0 / fps;
}
- (void)_bn_tick:(NSTimer *)timer {
    id target = _target;
    if (!target) { [self invalidate]; return; }
    if (_paused) return;
    _duration = [self _bn_interval];
    _timestamp = CACurrentMediaTime();
    void (*send)(id, SEL, id) = (void (*)(id, SEL, id))[target methodForSelector:_selector];
    if (send) send(target, _selector, self);
}
- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode {
    if (_timer) return;
    /* The timer retains its target, the link, until -invalidate, as
     * Apple's run loop retains an added display link. */
    _timer = [NSTimer timerWithTimeInterval:[self _bn_interval] target:self selector:@selector(_bn_tick:)
                                   userInfo:nil repeats:YES];
    [runloop addTimer:_timer forMode:mode];
}
- (void)removeFromRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode { [self invalidate]; }
- (void)invalidate {
    [_timer invalidate];
    _timer = nil;
}
@end
