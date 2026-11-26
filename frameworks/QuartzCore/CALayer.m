/* Core Animation's layers: the tree, geometry and drawing. A layer tree
 * draws through CoreGraphics with -renderInContext:: background, contents,
 * the layer's own drawing (-drawInContext: or its delegate), sublayers in
 * zPosition order under masksToBounds, then the border. Transforms apply
 * their affine part; shadows, filters and masks are kept but not drawn. */
#import <QuartzCore/QuartzCore.h>
#include <CoreText/CoreText.h>
#include <math.h>
#include <string.h>
#include <sys/param.h>
#include <time.h>

/* ---- C functions ------------------------------------------------------------------- */

const CATransform3D CATransform3DIdentity = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};

bool CATransform3DIsIdentity(CATransform3D t) { return CATransform3DEqualToTransform(t, CATransform3DIdentity); }
bool CATransform3DEqualToTransform(CATransform3D a, CATransform3D b) { return memcmp(&a, &b, sizeof a) == 0; }

CATransform3D CATransform3DMakeTranslation(CGFloat tx, CGFloat ty, CGFloat tz) {
    CATransform3D t = CATransform3DIdentity;
    t.m41 = tx; t.m42 = ty; t.m43 = tz;
    return t;
}
CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz) {
    CATransform3D t = CATransform3DIdentity;
    t.m11 = sx; t.m22 = sy; t.m33 = sz;
    return t;
}
CATransform3D CATransform3DMakeRotation(CGFloat angle, CGFloat x, CGFloat y, CGFloat z) {
    CGFloat len = sqrt(x * x + y * y + z * z);
    if (len == 0) return CATransform3DIdentity;
    x /= len; y /= len; z /= len;
    CGFloat c = cos(angle), s = sin(angle), k = 1 - c;
    CATransform3D t = CATransform3DIdentity;
    t.m11 = c + x * x * k;     t.m12 = x * y * k + z * s; t.m13 = x * z * k - y * s;
    t.m21 = x * y * k - z * s; t.m22 = c + y * y * k;     t.m23 = y * z * k + x * s;
    t.m31 = x * z * k + y * s; t.m32 = y * z * k - x * s; t.m33 = c + z * z * k;
    return t;
}
/* a then b (row vectors, as Core Animation multiplies). */
CATransform3D CATransform3DConcat(CATransform3D a, CATransform3D b) {
    const CGFloat *p = &a.m11, *q = &b.m11;
    CATransform3D r;
    CGFloat *o = &r.m11;
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
            CGFloat v = 0;
            for (int k = 0; k < 4; k++) v += p[i * 4 + k] * q[k * 4 + j];
            o[i * 4 + j] = v;
        }
    return r;
}
CATransform3D CATransform3DTranslate(CATransform3D t, CGFloat tx, CGFloat ty, CGFloat tz) {
    return CATransform3DConcat(CATransform3DMakeTranslation(tx, ty, tz), t);
}
CATransform3D CATransform3DScale(CATransform3D t, CGFloat sx, CGFloat sy, CGFloat sz) {
    return CATransform3DConcat(CATransform3DMakeScale(sx, sy, sz), t);
}
CATransform3D CATransform3DRotate(CATransform3D t, CGFloat angle, CGFloat x, CGFloat y, CGFloat z) {
    return CATransform3DConcat(CATransform3DMakeRotation(angle, x, y, z), t);
}
/* Gauss-Jordan; a singular matrix comes back unchanged, as Apple's does. */
CATransform3D CATransform3DInvert(CATransform3D t) {
    CGFloat a[4][8];
    const CGFloat *m = &t.m11;
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 8; j++) a[i][j] = j < 4 ? m[i * 4 + j] : (j - 4 == i);
    for (int c = 0; c < 4; c++) {
        int p = c;
        for (int r = c + 1; r < 4; r++) if (fabs(a[r][c]) > fabs(a[p][c])) p = r;
        if (fabs(a[p][c]) < 1e-12) return t;
        for (int j = 0; j < 8; j++) { CGFloat x = a[c][j]; a[c][j] = a[p][j]; a[p][j] = x; }
        CGFloat d = a[c][c];
        for (int j = 0; j < 8; j++) a[c][j] /= d;
        for (int r = 0; r < 4; r++) {
            if (r == c) continue;
            CGFloat f = a[r][c];
            for (int j = 0; j < 8; j++) a[r][j] -= f * a[c][j];
        }
    }
    CATransform3D r;
    CGFloat *o = &r.m11;
    for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) o[i * 4 + j] = a[i][j + 4];
    return r;
}
CATransform3D CATransform3DMakeAffineTransform(CGAffineTransform m) {
    CATransform3D t = CATransform3DIdentity;
    t.m11 = m.a; t.m12 = m.b; t.m21 = m.c; t.m22 = m.d; t.m41 = m.tx; t.m42 = m.ty;
    return t;
}
bool CATransform3DIsAffine(CATransform3D t) {
    return t.m13 == 0 && t.m14 == 0 && t.m23 == 0 && t.m24 == 0 && t.m31 == 0 && t.m32 == 0 &&
           t.m33 == 1 && t.m34 == 0 && t.m43 == 0 && t.m44 == 1;
}
CGAffineTransform CATransform3DGetAffineTransform(CATransform3D t) {
    return CGAffineTransformMake(t.m11, t.m12, t.m21, t.m22, t.m41, t.m42);
}

const CAFrameRateRange CAFrameRateRangeDefault = {0, 0, 0};
CAFrameRateRange CAFrameRateRangeMake(float minimum, float maximum, float preferred) {
    CAFrameRateRange r = {minimum, maximum, preferred};
    return r;
}
bool CAFrameRateRangeIsEqualToRange(CAFrameRateRange a, CAFrameRateRange b) {
    return a.minimum == b.minimum && a.maximum == b.maximum && a.preferred == b.preferred;
}

/* Seconds of uptime (mach_absolute_time, which ticks in nanoseconds here). */
CFTimeInterval CACurrentMediaTime(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

/* ---- constants -------------------------------------------------------------------------- */

CALayerContentsGravity const kCAGravityCenter = @"center", kCAGravityTop = @"top", kCAGravityBottom = @"bottom",
    kCAGravityLeft = @"left", kCAGravityRight = @"right", kCAGravityTopLeft = @"topLeft",
    kCAGravityTopRight = @"topRight", kCAGravityBottomLeft = @"bottomLeft", kCAGravityBottomRight = @"bottomRight",
    kCAGravityResize = @"resize", kCAGravityResizeAspect = @"resizeAspect",
    kCAGravityResizeAspectFill = @"resizeAspectFill";
CALayerContentsFilter const kCAFilterNearest = @"nearest", kCAFilterLinear = @"linear", kCAFilterTrilinear = @"trilinear";
CALayerCornerCurve const kCACornerCurveCircular = @"circular", kCACornerCurveContinuous = @"continuous";
CAMediaTimingFillMode const kCAFillModeForwards = @"forwards", kCAFillModeBackwards = @"backwards",
    kCAFillModeBoth = @"both", kCAFillModeRemoved = @"removed";
CAMediaTimingFunctionName const kCAMediaTimingFunctionLinear = @"linear", kCAMediaTimingFunctionEaseIn = @"easeIn",
    kCAMediaTimingFunctionEaseOut = @"easeOut", kCAMediaTimingFunctionEaseInEaseOut = @"easeInEaseOut",
    kCAMediaTimingFunctionDefault = @"default";
CAAnimationCalculationMode const kCAAnimationLinear = @"linear", kCAAnimationDiscrete = @"discrete",
    kCAAnimationPaced = @"paced", kCAAnimationCubic = @"cubic", kCAAnimationCubicPaced = @"cubicPaced";
CATransitionType const kCATransitionFade = @"fade", kCATransitionMoveIn = @"moveIn", kCATransitionPush = @"push",
    kCATransitionReveal = @"reveal";
CATransitionSubtype const kCATransitionFromRight = @"fromRight", kCATransitionFromLeft = @"fromLeft",
    kCATransitionFromTop = @"fromTop", kCATransitionFromBottom = @"fromBottom";
NSString *const kCATransition = @"transition", *const kCAOnOrderIn = @"onOrderIn", *const kCAOnOrderOut = @"onOrderOut";
CAShapeLayerFillRule const kCAFillRuleNonZero = @"non-zero", kCAFillRuleEvenOdd = @"even-odd";
CAShapeLayerLineCap const kCALineCapButt = @"butt", kCALineCapRound = @"round", kCALineCapSquare = @"square";
CAShapeLayerLineJoin const kCALineJoinMiter = @"miter", kCALineJoinRound = @"round", kCALineJoinBevel = @"bevel";
CAGradientLayerType const kCAGradientLayerAxial = @"axial", kCAGradientLayerRadial = @"radial",
    kCAGradientLayerConic = @"conic";
CATextLayerAlignmentMode const kCAAlignmentNatural = @"natural", kCAAlignmentLeft = @"left",
    kCAAlignmentRight = @"right", kCAAlignmentCenter = @"center", kCAAlignmentJustified = @"justified";
CATextLayerTruncationMode const kCATruncationNone = @"none", kCATruncationStart = @"start",
    kCATruncationEnd = @"end", kCATruncationMiddle = @"middle";

/* ---- CALayer -------------------------------------------------------------------------------- */

static void set_cg(CFTypeRef *slot, CFTypeRef value) {
    if (value) CFRetain(value);
    if (*slot) CFRelease(*slot);
    *slot = value;
}

@implementation CALayer {
    CGRect _bounds;
    CGPoint _position, _anchorPoint;
    CATransform3D _transform, _sublayerTransform;
    NSMutableArray<CALayer *> *_sublayers;
    __weak CALayer *_superlayer;
    CGColorRef _backgroundColor, _borderColor, _shadowColor;
    CGPathRef _shadowPath;
    NSMutableDictionary<NSString *, CAAnimation *> *_animations;
    NSMutableArray<NSString *> *_animationOrder;
    BOOL _needsDisplay, _needsLayout;
}
@synthesize zPosition = _zPosition, anchorPointZ = _anchorPointZ, hidden = _hidden, doubleSided = _doubleSided,
            geometryFlipped = _geometryFlipped, mask = _mask, masksToBounds = _masksToBounds,
            contents = _contents, contentsRect = _contentsRect, contentsGravity = _contentsGravity,
            contentsScale = _contentsScale, contentsCenter = _contentsCenter, contentsFormat = _contentsFormat,
            contentsHeadroom = _contentsHeadroom, minificationFilter = _minificationFilter,
            magnificationFilter = _magnificationFilter, minificationFilterBias = _minificationFilterBias,
            opaque = _opaque, needsDisplayOnBoundsChange = _needsDisplayOnBoundsChange,
            drawsAsynchronously = _drawsAsynchronously, edgeAntialiasingMask = _edgeAntialiasingMask,
            allowsEdgeAntialiasing = _allowsEdgeAntialiasing, cornerRadius = _cornerRadius,
            maskedCorners = _maskedCorners, cornerCurve = _cornerCurve, borderWidth = _borderWidth,
            opacity = _opacity, allowsGroupOpacity = _allowsGroupOpacity, compositingFilter = _compositingFilter,
            filters = _filters, backgroundFilters = _backgroundFilters, shouldRasterize = _shouldRasterize,
            rasterizationScale = _rasterizationScale, shadowOpacity = _shadowOpacity, shadowOffset = _shadowOffset,
            shadowRadius = _shadowRadius, autoresizingMask = _autoresizingMask, actions = _actions, name = _name,
            delegate = _delegate, style = _style, beginTime = _beginTime, timeOffset = _timeOffset,
            duration = _duration, repeatDuration = _repeatDuration, repeatCount = _repeatCount, speed = _speed,
            autoreverses = _autoreverses, fillMode = _fillMode;

+ (instancetype)layer { return [self new]; }
+ (id)defaultValueForKey:(NSString *)key { return nil; }
+ (BOOL)needsDisplayForKey:(NSString *)key { return NO; }
+ (id<CAAction>)defaultActionForKey:(NSString *)event { return nil; }

- (instancetype)init {
    if ((self = [super init])) {
        _anchorPoint = CGPointMake(0.5, 0.5);
        _transform = _sublayerTransform = CATransform3DIdentity;
        _opacity = 1;
        _contentsRect = CGRectMake(0, 0, 1, 1);
        _contentsCenter = CGRectMake(0, 0, 1, 1);
        _contentsGravity = kCAGravityResize;
        _contentsScale = 1;
        _contentsFormat = @"RGBA8Uint";
        _minificationFilter = _magnificationFilter = kCAFilterLinear;
        _maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        _cornerCurve = kCACornerCurveCircular;
        _doubleSided = YES;
        _allowsGroupOpacity = YES;
        _rasterizationScale = 1;
        _shadowOffset = CGSizeMake(0, -3);
        _shadowRadius = 3;
        _speed = 1;
        _fillMode = kCAFillModeRemoved;
        _edgeAntialiasingMask = kCALayerLeftEdge | kCALayerRightEdge | kCALayerBottomEdge | kCALayerTopEdge;
        CGColorRef black = CGColorCreateGenericGray(0, 1);
        _shadowColor = black;
    }
    return self;
}

- (instancetype)initWithLayer:(id)other {
    if ((self = [self init])) {
        CALayer *l = other;
        _bounds = l->_bounds;
        _position = l->_position;
        _anchorPoint = l->_anchorPoint;
        _transform = l->_transform;
        _opacity = l->_opacity;
        _hidden = l->_hidden;
        set_cg((CFTypeRef *)&_backgroundColor, l->_backgroundColor);
        _contents = l->_contents;
        _cornerRadius = l->_cornerRadius;
        _name = [l->_name copy];
    }
    return self;
}

- (void)dealloc {
    set_cg((CFTypeRef *)&_backgroundColor, NULL);
    set_cg((CFTypeRef *)&_borderColor, NULL);
    set_cg((CFTypeRef *)&_shadowColor, NULL);
    set_cg((CFTypeRef *)&_shadowPath, NULL);
}

/* No animations run, so the presentation is the model. */
- (instancetype)presentationLayer { return self; }
- (instancetype)modelLayer { return self; }

- (CGRect)bounds { return _bounds; }
- (void)setBounds:(CGRect)b {
    BOOL resized = !CGSizeEqualToSize(b.size, _bounds.size);
    _bounds = b;
    if (resized) {
        [self setNeedsLayout];
        if (_needsDisplayOnBoundsChange) [self setNeedsDisplay];
    }
}
- (CGPoint)position { return _position; }
- (void)setPosition:(CGPoint)p { _position = p; }
- (CGPoint)anchorPoint { return _anchorPoint; }
- (void)setAnchorPoint:(CGPoint)p { _anchorPoint = p; }
- (CATransform3D)transform { return _transform; }
- (void)setTransform:(CATransform3D)t { _transform = t; }
- (CATransform3D)sublayerTransform { return _sublayerTransform; }
- (void)setSublayerTransform:(CATransform3D)t { _sublayerTransform = t; }
- (CGAffineTransform)affineTransform { return CATransform3DGetAffineTransform(_transform); }
- (void)setAffineTransform:(CGAffineTransform)m { _transform = CATransform3DMakeAffineTransform(m); }

/* The frame: the bounds through the transform about the anchor point. */
- (CGRect)frame {
    CGRect r = CGRectMake(-_anchorPoint.x * _bounds.size.width, -_anchorPoint.y * _bounds.size.height,
                          _bounds.size.width, _bounds.size.height);
    r = CGRectApplyAffineTransform(r, CATransform3DGetAffineTransform(_transform));
    return CGRectOffset(r, _position.x, _position.y);
}
- (void)setFrame:(CGRect)f {
    f = CGRectStandardize(f);
    CGAffineTransform t = CATransform3DGetAffineTransform(_transform);
    CGSize size = f.size;
    if (!CGAffineTransformIsIdentity(t)) {          /* undo the transform's scale */
        CGFloat sx = sqrt(t.a * t.a + t.b * t.b), sy = sqrt(t.c * t.c + t.d * t.d);
        if (sx > 0) size.width /= sx;
        if (sy > 0) size.height /= sy;
    }
    self.bounds = CGRectMake(_bounds.origin.x, _bounds.origin.y, size.width, size.height);
    _position = CGPointMake(f.origin.x + _anchorPoint.x * f.size.width, f.origin.y + _anchorPoint.y * f.size.height);
}

- (BOOL)contentsAreFlipped {
    BOOL flipped = NO;
    for (CALayer *l = self; l; l = l.superlayer) if (l.geometryFlipped) flipped = !flipped;
    return flipped;
}

- (CGColorRef)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(CGColorRef)c { set_cg((CFTypeRef *)&_backgroundColor, c); }
- (CGColorRef)borderColor { return _borderColor; }
- (void)setBorderColor:(CGColorRef)c { set_cg((CFTypeRef *)&_borderColor, c); }
- (CGColorRef)shadowColor { return _shadowColor; }
- (void)setShadowColor:(CGColorRef)c { set_cg((CFTypeRef *)&_shadowColor, c); }
- (CGPathRef)shadowPath { return _shadowPath; }
- (void)setShadowPath:(CGPathRef)p {
    CGPathRef copy = p ? CGPathCreateCopy(p) : NULL;
    set_cg((CFTypeRef *)&_shadowPath, copy);
    if (copy) CFRelease(copy);
}

/* ---- the tree ---- */

- (CALayer *)superlayer { return _superlayer; }
- (NSArray *)sublayers { return _sublayers.count ? [_sublayers copy] : nil; }
- (void)setSublayers:(NSArray *)layers {
    for (CALayer *l in [_sublayers copy]) [l removeFromSuperlayer];
    for (CALayer *l in layers) [self addSublayer:l];
}
- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned)idx {
    if (!layer || layer == self) return;
    [layer removeFromSuperlayer];
    if (!_sublayers) _sublayers = [NSMutableArray array];
    if (idx > _sublayers.count) idx = (unsigned)_sublayers.count;
    [_sublayers insertObject:layer atIndex:idx];
    layer->_superlayer = self;
    [self setNeedsLayout];
}
- (void)addSublayer:(CALayer *)layer { [self insertSublayer:layer atIndex:(unsigned)_sublayers.count]; }
- (void)insertSublayer:(CALayer *)layer below:(CALayer *)sibling {
    NSUInteger i = sibling ? [_sublayers indexOfObjectIdenticalTo:sibling] : NSNotFound;
    [self insertSublayer:layer atIndex:i == NSNotFound ? 0 : (unsigned)i];
}
- (void)insertSublayer:(CALayer *)layer above:(CALayer *)sibling {
    NSUInteger i = sibling ? [_sublayers indexOfObjectIdenticalTo:sibling] : NSNotFound;
    [self insertSublayer:layer atIndex:i == NSNotFound ? (unsigned)_sublayers.count : (unsigned)(i + 1)];
}
- (void)replaceSublayer:(CALayer *)old with:(CALayer *)layer {
    NSUInteger i = [_sublayers indexOfObjectIdenticalTo:old];
    if (i == NSNotFound) return;
    [old removeFromSuperlayer];
    [self insertSublayer:layer atIndex:(unsigned)i];
}
- (void)removeFromSuperlayer {
    CALayer *s = _superlayer;
    if (!s) return;
    [s->_sublayers removeObjectIdenticalTo:self];
    _superlayer = nil;
    [s setNeedsLayout];
}

/* ---- coordinates ---- */

/* From this layer's coordinates to its superlayer's. */
- (CGAffineTransform)_bn_toSuper {
    CGAffineTransform t = CGAffineTransformMakeTranslation(-_bounds.origin.x - _anchorPoint.x * _bounds.size.width,
                                                           -_bounds.origin.y - _anchorPoint.y * _bounds.size.height);
    t = CGAffineTransformConcat(t, CATransform3DGetAffineTransform(_transform));
    t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(_position.x, _position.y));
    CALayer *s = _superlayer;
    if (s && !CATransform3DIsIdentity(s->_sublayerTransform)) {
        CGPoint c = CGPointMake(s->_bounds.origin.x + s->_bounds.size.width / 2, s->_bounds.origin.y + s->_bounds.size.height / 2);
        CGAffineTransform st = CGAffineTransformMakeTranslation(-c.x, -c.y);
        st = CGAffineTransformConcat(st, CATransform3DGetAffineTransform(s->_sublayerTransform));
        st = CGAffineTransformConcat(st, CGAffineTransformMakeTranslation(c.x, c.y));
        t = CGAffineTransformConcat(t, st);
    }
    return t;
}
- (CGAffineTransform)_bn_toRoot {
    CGAffineTransform t = CGAffineTransformIdentity;
    for (CALayer *l = self; l.superlayer; l = l.superlayer) t = CGAffineTransformConcat(t, [l _bn_toSuper]);
    return t;
}
- (CGPoint)convertPoint:(CGPoint)p toLayer:(CALayer *)l {
    CGPoint r = CGPointApplyAffineTransform(p, [self _bn_toRoot]);
    return l ? CGPointApplyAffineTransform(r, CGAffineTransformInvert([l _bn_toRoot])) : r;
}
- (CGPoint)convertPoint:(CGPoint)p fromLayer:(CALayer *)l { return l ? [l convertPoint:p toLayer:self] :
    CGPointApplyAffineTransform(p, CGAffineTransformInvert([self _bn_toRoot])); }
- (CGRect)convertRect:(CGRect)r toLayer:(CALayer *)l {
    CGAffineTransform t = [self _bn_toRoot];
    if (l) t = CGAffineTransformConcat(t, CGAffineTransformInvert([l _bn_toRoot]));
    return CGRectApplyAffineTransform(r, t);
}
- (CGRect)convertRect:(CGRect)r fromLayer:(CALayer *)l { return l ? [l convertRect:r toLayer:self] :
    CGRectApplyAffineTransform(r, CGAffineTransformInvert([self _bn_toRoot])); }
- (BOOL)containsPoint:(CGPoint)p { return CGRectContainsPoint(_bounds, p); }
/* p is in the superlayer's coordinates. */
- (CALayer *)hitTest:(CGPoint)p {
    if (_hidden || _opacity <= 0) return nil;
    CGPoint local = CGPointApplyAffineTransform(p, CGAffineTransformInvert([self _bn_toSuper]));
    if (_masksToBounds && ![self containsPoint:local]) return nil;
    for (CALayer *l in [_sublayers reverseObjectEnumerator]) {
        CALayer *hit = [l hitTest:local];
        if (hit) return hit;
    }
    return [self containsPoint:local] ? self : nil;
}

/* ---- display and layout ---- */

- (void)setNeedsDisplay { _needsDisplay = YES; }
- (void)setNeedsDisplayInRect:(CGRect)r { _needsDisplay = YES; }
- (BOOL)needsDisplay { return _needsDisplay; }
- (void)displayIfNeeded { if (_needsDisplay) [self display]; }
- (void)display {
    _needsDisplay = NO;
    id<CALayerDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(displayLayer:)]) [d displayLayer:self];
}
- (void)drawInContext:(CGContextRef)ctx {
    id<CALayerDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(drawLayer:inContext:)]) [d drawLayer:self inContext:ctx];
}
- (CGSize)preferredFrameSize { return _bounds.size; }
- (void)setNeedsLayout { _needsLayout = YES; }
- (BOOL)needsLayout { return _needsLayout; }
- (void)layoutIfNeeded {
    if (_needsLayout) [self layoutSublayers];
    for (CALayer *l in [_sublayers copy]) [l layoutIfNeeded];
}
- (void)layoutSublayers {
    _needsLayout = NO;
    id<CALayerDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(layoutSublayersOfLayer:)]) [d layoutSublayersOfLayer:self];
}

- (id<CAAction>)actionForKey:(NSString *)event {
    id<CALayerDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(actionForLayer:forKey:)]) {
        id a = [d actionForLayer:self forKey:event];
        if (a) return a == [NSNull null] ? nil : a;
    }
    id a = _actions[event];
    return a == [NSNull null] ? nil : a;
}

/* ---- animations: kept for -animationForKey:, finished after their duration ---- */

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    if (!anim) return;
    CAAnimation *a = [anim copy];
    if (!key) key = [NSString stringWithFormat:@"_bn_anim_%p", (void *)a];
    if (!_animations) { _animations = [NSMutableDictionary dictionary]; _animationOrder = [NSMutableArray array]; }
    if (!_animations[key]) [_animationOrder addObject:key];
    _animations[key] = a;
    id<CAAnimationDelegate> d = a.delegate;
    if ([d respondsToSelector:@selector(animationDidStart:)]) [d animationDidStart:a];
    CFTimeInterval dur = a.duration > 0 ? a.duration : 0.25;
    if (a.repeatCount > 0 && a.repeatCount < 1e6) dur *= a.repeatCount;
    if (a.autoreverses) dur *= 2;
    __weak CALayer *weakSelf = self;
    BOOL forever = a.repeatCount >= 1e6 || a.repeatDuration > 1e6;
    if (forever) return;                          /* runs until removed */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(dur * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CALayer *s = weakSelf;
        if (!s || s->_animations[key] != a) return;
        if (a.removedOnCompletion) {
            [s->_animations removeObjectForKey:key];
            [s->_animationOrder removeObject:key];
        }
        id<CAAnimationDelegate> del = a.delegate;
        if ([del respondsToSelector:@selector(animationDidStop:finished:)]) [del animationDidStop:a finished:YES];
    });
}
- (void)removeAnimationForKey:(NSString *)key {
    CAAnimation *a = _animations[key];
    if (!a) return;
    [_animations removeObjectForKey:key];
    [_animationOrder removeObject:key];
    id<CAAnimationDelegate> d = a.delegate;
    if ([d respondsToSelector:@selector(animationDidStop:finished:)]) [d animationDidStop:a finished:NO];
}
- (void)removeAllAnimations {
    for (NSString *k in [_animationOrder copy]) [self removeAnimationForKey:k];
}
- (NSArray *)animationKeys { return _animationOrder.count ? [_animationOrder copy] : nil; }
- (CAAnimation *)animationForKey:(NSString *)key { return _animations[key]; }

/* ---- drawing ---- */

- (CGPathRef)_bn_shapeOfBounds CF_RETURNS_RETAINED {
    CGFloat r = fmin(_cornerRadius, fmin(_bounds.size.width, _bounds.size.height) / 2);
    if (r > 0) return CGPathCreateWithRoundedRect(_bounds, r, r, NULL);
    return CGPathCreateWithRect(_bounds, NULL);
}

static CGRect gravity_rect(NSString *g, CGRect b, CGSize content) {
    if (content.width <= 0 || content.height <= 0 || [g isEqualToString:kCAGravityResize]) return b;
    CGFloat sx = b.size.width / content.width, sy = b.size.height / content.height;
    CGSize s = content;
    if ([g isEqualToString:kCAGravityResizeAspect]) { CGFloat k = fmin(sx, sy); s = CGSizeMake(content.width * k, content.height * k); }
    else if ([g isEqualToString:kCAGravityResizeAspectFill]) { CGFloat k = fmax(sx, sy); s = CGSizeMake(content.width * k, content.height * k); }
    CGFloat x = b.origin.x + (b.size.width - s.width) / 2, y = b.origin.y + (b.size.height - s.height) / 2;
    if ([g hasSuffix:@"eft"] || [g isEqualToString:kCAGravityLeft]) x = b.origin.x;
    if ([g hasSuffix:@"ight"]) x = CGRectGetMaxX(b) - s.width;
    if ([g hasPrefix:@"top"]) y = CGRectGetMaxY(b) - s.height;
    if ([g hasPrefix:@"bottom"]) y = b.origin.y;
    return CGRectMake(x, y, s.width, s.height);
}

/* Draw this layer and its sublayers, in this layer's coordinates. */
- (void)_bn_render:(CGContextRef)ctx {
    if (_hidden || _opacity <= 0) return;
    [self layoutIfNeeded];
    [self displayIfNeeded];
    CGContextSaveGState(ctx);
    BOOL group = _opacity < 1;
    if (group) {
        CGContextSetAlpha(ctx, _opacity);
        CGContextBeginTransparencyLayer(ctx, NULL);
    }
    if (_backgroundColor && CGColorGetAlpha(_backgroundColor) > 0) {
        CGPathRef shape = [self _bn_shapeOfBounds];
        CGContextSetFillColorWithColor(ctx, _backgroundColor);
        CGContextAddPath(ctx, shape);
        CGContextFillPath(ctx);
        CGPathRelease(shape);
    }
    CGContextSaveGState(ctx);
    if (_masksToBounds) {
        CGPathRef shape = [self _bn_shapeOfBounds];
        CGContextAddPath(ctx, shape);
        CGContextClip(ctx);
        CGPathRelease(shape);
    }
    id contents = _contents;
    if (contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) {
        CGImageRef img = (__bridge CGImageRef)contents;
        CGSize size = CGSizeMake(CGImageGetWidth(img) / (_contentsScale > 0 ? _contentsScale : 1),
                                 CGImageGetHeight(img) / (_contentsScale > 0 ? _contentsScale : 1));
        CGRect r = gravity_rect(_contentsGravity, _bounds, size);
        if (self.contentsAreFlipped) {
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, 0, CGRectGetMinY(r) + CGRectGetMaxY(r));
            CGContextScaleCTM(ctx, 1, -1);
            CGContextDrawImage(ctx, r, img);
            CGContextRestoreGState(ctx);
        } else {
            CGContextDrawImage(ctx, r, img);
        }
    }
    CGContextSaveGState(ctx);
    [self drawInContext:ctx];
    CGContextRestoreGState(ctx);
    NSArray *subs = [_sublayers sortedArrayUsingComparator:^NSComparisonResult(CALayer *a, CALayer *b) {
        return a.zPosition < b.zPosition ? NSOrderedAscending : a.zPosition > b.zPosition ? NSOrderedDescending : NSOrderedSame;
    }];
    for (CALayer *l in subs) {
        CGContextSaveGState(ctx);
        CGContextConcatCTM(ctx, [l _bn_toSuper]);
        [l _bn_render:ctx];
        CGContextRestoreGState(ctx);
    }
    CGContextRestoreGState(ctx);
    if (_borderWidth > 0 && _borderColor) {
        CGFloat inset = _borderWidth / 2;
        CGRect r = CGRectInset(_bounds, inset, inset);
        CGFloat rad = fmax(0, fmin(_cornerRadius - inset, fmin(r.size.width, r.size.height) / 2));
        CGPathRef p = rad > 0 ? CGPathCreateWithRoundedRect(r, rad, rad, NULL) : CGPathCreateWithRect(r, NULL);
        CGContextSetStrokeColorWithColor(ctx, _borderColor);
        CGContextSetLineWidth(ctx, _borderWidth);
        CGContextAddPath(ctx, p);
        CGContextStrokePath(ctx);
        CGPathRelease(p);
    }
    if (group) CGContextEndTransparencyLayer(ctx);
    CGContextRestoreGState(ctx);
}

- (void)renderInContext:(CGContextRef)ctx {
    if (ctx) [self _bn_render:ctx];
}
@end

/* ---- shape, gradient, text and Metal layers ------------------------------------------------- */

@implementation CAShapeLayer {
    CGPathRef _path;
    CGColorRef _fillColor, _strokeColor;
}
@synthesize fillRule = _fillRule, strokeStart = _strokeStart, strokeEnd = _strokeEnd, lineWidth = _lineWidth,
            miterLimit = _miterLimit, lineDashPhase = _lineDashPhase, lineCap = _lineCap, lineJoin = _lineJoin,
            lineDashPattern = _lineDashPattern;
- (instancetype)init {
    if ((self = [super init])) {
        _fillColor = CGColorCreateGenericGray(0, 1);
        _fillRule = kCAFillRuleNonZero;
        _strokeEnd = 1;
        _lineWidth = 1;
        _miterLimit = 10;
        _lineCap = kCALineCapButt;
        _lineJoin = kCALineJoinMiter;
    }
    return self;
}
- (void)dealloc {
    set_cg((CFTypeRef *)&_path, NULL);
    set_cg((CFTypeRef *)&_fillColor, NULL);
    set_cg((CFTypeRef *)&_strokeColor, NULL);
}
- (CGPathRef)path { return _path; }
- (void)setPath:(CGPathRef)p {
    CGPathRef copy = p ? CGPathCreateCopy(p) : NULL;
    set_cg((CFTypeRef *)&_path, copy);
    if (copy) CFRelease(copy);
}
- (CGColorRef)fillColor { return _fillColor; }
- (void)setFillColor:(CGColorRef)c { set_cg((CFTypeRef *)&_fillColor, c); }
- (CGColorRef)strokeColor { return _strokeColor; }
- (void)setStrokeColor:(CGColorRef)c { set_cg((CFTypeRef *)&_strokeColor, c); }
- (void)drawInContext:(CGContextRef)ctx {
    [super drawInContext:ctx];
    if (!_path) return;
    if (_fillColor) {
        CGContextSetFillColorWithColor(ctx, _fillColor);
        CGContextAddPath(ctx, _path);
        if ([_fillRule isEqualToString:kCAFillRuleEvenOdd]) CGContextEOFillPath(ctx);
        else CGContextFillPath(ctx);
    }
    if (_strokeColor && _lineWidth > 0) {
        CGContextSetStrokeColorWithColor(ctx, _strokeColor);
        CGContextSetLineWidth(ctx, _lineWidth);
        CGContextSetMiterLimit(ctx, _miterLimit);
        CGContextSetLineCap(ctx, [_lineCap isEqualToString:kCALineCapRound] ? kCGLineCapRound :
                                 [_lineCap isEqualToString:kCALineCapSquare] ? kCGLineCapSquare : kCGLineCapButt);
        CGContextSetLineJoin(ctx, [_lineJoin isEqualToString:kCALineJoinRound] ? kCGLineJoinRound :
                                  [_lineJoin isEqualToString:kCALineJoinBevel] ? kCGLineJoinBevel : kCGLineJoinMiter);
        if (_lineDashPattern.count) {
            CGFloat dashes[16];
            size_t n = 0;
            for (NSNumber *d in _lineDashPattern) if (n < 16) dashes[n++] = d.doubleValue;
            CGContextSetLineDash(ctx, _lineDashPhase, dashes, n);
        }
        CGContextAddPath(ctx, _path);
        CGContextStrokePath(ctx);
    }
}
@end

@implementation CAGradientLayer
@synthesize colors = _colors, locations = _locations, startPoint = _startPoint, endPoint = _endPoint, type = _type;
- (instancetype)init {
    if ((self = [super init])) {
        _startPoint = CGPointMake(0.5, 0);
        _endPoint = CGPointMake(0.5, 1);
        _type = kCAGradientLayerAxial;
    }
    return self;
}
- (void)drawInContext:(CGContextRef)ctx {
    [super drawInContext:ctx];
    if (_colors.count == 0) return;
    CGFloat locs[64];
    size_t n = MIN(_colors.count, (NSUInteger)64);
    BOOL haveLocs = _locations.count >= n;
    for (size_t i = 0; i < n && haveLocs; i++) locs[i] = _locations[i].doubleValue;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)_colors, haveLocs ? locs : NULL);
    CGColorSpaceRelease(space);
    if (!g) return;
    CGRect b = self.bounds;
    CGPoint s = CGPointMake(b.origin.x + _startPoint.x * b.size.width, b.origin.y + _startPoint.y * b.size.height);
    CGPoint e = CGPointMake(b.origin.x + _endPoint.x * b.size.width, b.origin.y + _endPoint.y * b.size.height);
    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, b);
    if ([_type isEqualToString:kCAGradientLayerRadial])
        CGContextDrawRadialGradient(ctx, g, s, 0, s, hypot(e.x - s.x, e.y - s.y), kCGGradientDrawsAfterEndLocation);
    else
        CGContextDrawLinearGradient(ctx, g, s, e, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(ctx);
    CGGradientRelease(g);
}
@end

@implementation CATextLayer {
    CFTypeRef _font;
    CGColorRef _foregroundColor;
}
@synthesize string = _string, fontSize = _fontSize, wrapped = _wrapped, truncationMode = _truncationMode,
            alignmentMode = _alignmentMode, allowsFontSubpixelQuantization = _allowsFontSubpixelQuantization;
- (instancetype)init {
    if ((self = [super init])) {
        _fontSize = 36;
        _foregroundColor = CGColorCreateGenericGray(1, 1);
        _truncationMode = kCATruncationNone;
        _alignmentMode = kCAAlignmentNatural;
    }
    return self;
}
- (void)dealloc {
    set_cg(&_font, NULL);
    set_cg((CFTypeRef *)&_foregroundColor, NULL);
}
- (CFTypeRef)font { return _font; }
- (void)setFont:(CFTypeRef)f { set_cg(&_font, f); }
- (CGColorRef)foregroundColor { return _foregroundColor; }
- (void)setForegroundColor:(CGColorRef)c { set_cg((CFTypeRef *)&_foregroundColor, c); }

/* One line, at the top of the bounds (with alignment), in CoreText. */
- (void)drawInContext:(CGContextRef)ctx {
    [super drawInContext:ctx];
    if (!_string) return;
    CTFontRef font = NULL;
    if (_font && CFGetTypeID(_font) == CTFontGetTypeID()) font = CTFontCreateCopyWithAttributes(_font, _fontSize, NULL, NULL);
    else if (_font && CFGetTypeID(_font) == CFStringGetTypeID()) font = CTFontCreateWithName(_font, _fontSize, NULL);
    else font = CTFontCreateWithName((__bridge CFStringRef)@"Helvetica", _fontSize, NULL);
    CFAttributedStringRef text;
    if ([_string isKindOfClass:[NSString class]]) {
        const void *keys[] = {kCTFontAttributeName, kCTForegroundColorAttributeName};
        const void *vals[] = {font, _foregroundColor};
        CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, vals, _foregroundColor ? 2 : 1,
                                                   &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        text = CFAttributedStringCreate(NULL, (__bridge CFStringRef)_string, attrs);
        CFRelease(attrs);
    } else {
        text = CFRetain((__bridge CFTypeRef)_string);
    }
    CTLineRef line = CTLineCreateWithAttributedString(text);
    CGFloat ascent, descent, leading;
    double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
    CGRect b = self.bounds;
    CGFloat x = b.origin.x;
    if ([_alignmentMode isEqualToString:kCAAlignmentCenter]) x += (b.size.width - width) / 2;
    else if ([_alignmentMode isEqualToString:kCAAlignmentRight]) x += b.size.width - width;
    CGContextSaveGState(ctx);
    BOOL flipped = self.contentsAreFlipped;
    CGContextSetTextMatrix(ctx, flipped ? CGAffineTransformMakeScale(1, -1) : CGAffineTransformIdentity);
    CGContextSetTextPosition(ctx, x, flipped ? b.origin.y + ascent : CGRectGetMaxY(b) - ascent);
    CTLineDraw(line, ctx);
    CGContextRestoreGState(ctx);
    CFRelease(line);
    CFRelease(text);
    if (font) CFRelease(font);
}
@end

/* No GPU here: no device, no drawables. Programs that ask for Metal learn
 * it is unavailable (MTLCreateSystemDefaultDevice returns nil). */
@implementation CAMetalLayer {
    CGColorSpaceRef _colorspace;
}
@synthesize device = _device, pixelFormat = _pixelFormat, framebufferOnly = _framebufferOnly,
            drawableSize = _drawableSize, maximumDrawableCount = _maximumDrawableCount,
            presentsWithTransaction = _presentsWithTransaction,
            wantsExtendedDynamicRangeContent = _wantsExtendedDynamicRangeContent,
            displaySyncEnabled = _displaySyncEnabled, allowsNextDrawableTimeout = _allowsNextDrawableTimeout;
- (instancetype)init {
    if ((self = [super init])) {
        _pixelFormat = 80;                         /* MTLPixelFormatBGRA8Unorm */
        _framebufferOnly = YES;
        _maximumDrawableCount = 3;
        _displaySyncEnabled = YES;
        _allowsNextDrawableTimeout = YES;
    }
    return self;
}
- (void)dealloc { set_cg((CFTypeRef *)&_colorspace, NULL); }
- (id)preferredDevice { return nil; }
- (CGColorSpaceRef)colorspace { return _colorspace; }
- (void)setColorspace:(CGColorSpaceRef)c { set_cg((CFTypeRef *)&_colorspace, c); }
- (id)nextDrawable { return nil; }
@end

/* Foundation's NSValue holds the encodings it knows; a transform is kept
 * by a subclass of its own, as concrete NSValues are on Apple's systems. */
@interface BNTransform3DValue : NSValue {
@public
    CATransform3D _t;
}
@end
@implementation BNTransform3DValue
- (const char *)objCType { return @encode(CATransform3D); }
- (void)getValue:(void *)value { memcpy(value, &_t, sizeof _t); }
- (void)getValue:(void *)value size:(NSUInteger)size { memcpy(value, &_t, MIN(size, sizeof _t)); }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)isEqual:(id)o {
    return [o isKindOfClass:[BNTransform3DValue class]] && CATransform3DEqualToTransform(_t, ((BNTransform3DValue *)o)->_t);
}
- (NSUInteger)hash { return (NSUInteger)(_t.m11 * 31 + _t.m22 * 17 + _t.m41 * 7 + _t.m42); }
- (NSString *)description {
    return [NSString stringWithFormat:@"CATransform3D: {{%g, %g, %g, %g}, {%g, %g, %g, %g}, {%g, %g, %g, %g}, {%g, %g, %g, %g}}",
            _t.m11, _t.m12, _t.m13, _t.m14, _t.m21, _t.m22, _t.m23, _t.m24,
            _t.m31, _t.m32, _t.m33, _t.m34, _t.m41, _t.m42, _t.m43, _t.m44];
}
@end

@implementation NSValue (CATransform3DAdditions)
+ (NSValue *)valueWithCATransform3D:(CATransform3D)t {
    BNTransform3DValue *v = [BNTransform3DValue new];
    v->_t = t;
    return v;
}
- (CATransform3D)CATransform3DValue {
    CATransform3D t = CATransform3DIdentity;
    if (!strcmp(self.objCType, @encode(CATransform3D))) [self getValue:&t];
    return t;
}
@end
