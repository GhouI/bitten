/* bitten SDK: QuartzCore (Core Animation). Written from the public
 * documentation; the implementation is frameworks/QuartzCore. Layers draw
 * through CoreGraphics (renderInContext:); there is no compositor, so
 * animations finish at once (their delegates still hear of them). */
#ifndef BITTEN_QUARTZCORE_H
#define BITTEN_QUARTZCORE_H
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>

#pragma clang assume_nonnull begin

typedef struct CATransform3D {
    CGFloat m11, m12, m13, m14;
    CGFloat m21, m22, m23, m24;
    CGFloat m31, m32, m33, m34;
    CGFloat m41, m42, m43, m44;
} CATransform3D;
extern const CATransform3D CATransform3DIdentity;
bool CATransform3DIsIdentity(CATransform3D t);
bool CATransform3DEqualToTransform(CATransform3D a, CATransform3D b);
CATransform3D CATransform3DMakeTranslation(CGFloat tx, CGFloat ty, CGFloat tz);
CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz);
CATransform3D CATransform3DMakeRotation(CGFloat angle, CGFloat x, CGFloat y, CGFloat z);
CATransform3D CATransform3DTranslate(CATransform3D t, CGFloat tx, CGFloat ty, CGFloat tz);
CATransform3D CATransform3DScale(CATransform3D t, CGFloat sx, CGFloat sy, CGFloat sz);
CATransform3D CATransform3DRotate(CATransform3D t, CGFloat angle, CGFloat x, CGFloat y, CGFloat z);
CATransform3D CATransform3DConcat(CATransform3D a, CATransform3D b);
CATransform3D CATransform3DInvert(CATransform3D t);
CATransform3D CATransform3DMakeAffineTransform(CGAffineTransform m);
bool CATransform3DIsAffine(CATransform3D t);
CGAffineTransform CATransform3DGetAffineTransform(CATransform3D t);

typedef struct CAFrameRateRange {
    float minimum;
    float maximum;
    float preferred __attribute__((swift_private));
} CAFrameRateRange;
extern const CAFrameRateRange CAFrameRateRangeDefault;
CAFrameRateRange CAFrameRateRangeMake(float minimum, float maximum, float preferred);
bool CAFrameRateRangeIsEqualToRange(CAFrameRateRange a, CAFrameRateRange b);

CFTimeInterval CACurrentMediaTime(void);

typedef NSString *CALayerContentsGravity NS_TYPED_ENUM;
typedef NSString *CALayerContentsFilter NS_TYPED_ENUM;
typedef NSString *CALayerCornerCurve NS_TYPED_ENUM;
typedef NSString *CAMediaTimingFillMode NS_TYPED_ENUM;
typedef NSString *CAMediaTimingFunctionName NS_TYPED_ENUM;
typedef NSString *CAAnimationCalculationMode NS_TYPED_ENUM;
typedef NSString *CATransitionType NS_TYPED_ENUM;
typedef NSString *CATransitionSubtype NS_TYPED_ENUM;
typedef NSString *CAShapeLayerFillRule NS_TYPED_ENUM;
typedef NSString *CAShapeLayerLineCap NS_TYPED_ENUM;
typedef NSString *CAShapeLayerLineJoin NS_TYPED_ENUM;
typedef NSString *CAGradientLayerType NS_TYPED_ENUM;
typedef NSString *CATextLayerAlignmentMode NS_TYPED_ENUM;
typedef NSString *CATextLayerTruncationMode NS_TYPED_ENUM;

extern CALayerContentsGravity const kCAGravityCenter, kCAGravityTop, kCAGravityBottom, kCAGravityLeft,
    kCAGravityRight, kCAGravityTopLeft, kCAGravityTopRight, kCAGravityBottomLeft, kCAGravityBottomRight,
    kCAGravityResize, kCAGravityResizeAspect, kCAGravityResizeAspectFill;
extern CALayerContentsFilter const kCAFilterNearest, kCAFilterLinear, kCAFilterTrilinear;
extern CALayerCornerCurve const kCACornerCurveCircular, kCACornerCurveContinuous;
extern CAMediaTimingFillMode const kCAFillModeForwards, kCAFillModeBackwards, kCAFillModeBoth, kCAFillModeRemoved;
extern CAMediaTimingFunctionName const kCAMediaTimingFunctionLinear, kCAMediaTimingFunctionEaseIn,
    kCAMediaTimingFunctionEaseOut, kCAMediaTimingFunctionEaseInEaseOut, kCAMediaTimingFunctionDefault;
extern CAAnimationCalculationMode const kCAAnimationLinear, kCAAnimationDiscrete, kCAAnimationPaced,
    kCAAnimationCubic, kCAAnimationCubicPaced;
extern CATransitionType const kCATransitionFade, kCATransitionMoveIn, kCATransitionPush, kCATransitionReveal;
extern CATransitionSubtype const kCATransitionFromRight, kCATransitionFromLeft, kCATransitionFromTop,
    kCATransitionFromBottom;
extern NSString *const kCATransition, *const kCAOnOrderIn, *const kCAOnOrderOut;
extern CAShapeLayerFillRule const kCAFillRuleNonZero, kCAFillRuleEvenOdd;
extern CAShapeLayerLineCap const kCALineCapButt, kCALineCapRound, kCALineCapSquare;
extern CAShapeLayerLineJoin const kCALineJoinMiter, kCALineJoinRound, kCALineJoinBevel;
extern CAGradientLayerType const kCAGradientLayerAxial, kCAGradientLayerRadial, kCAGradientLayerConic;
extern CATextLayerAlignmentMode const kCAAlignmentNatural, kCAAlignmentLeft, kCAAlignmentRight,
    kCAAlignmentCenter, kCAAlignmentJustified;
extern CATextLayerTruncationMode const kCATruncationNone, kCATruncationStart, kCATruncationEnd, kCATruncationMiddle;

typedef NS_OPTIONS(NSUInteger, CACornerMask) {
    kCALayerMinXMinYCorner = 1 << 0, kCALayerMaxXMinYCorner = 1 << 1,
    kCALayerMinXMaxYCorner = 1 << 2, kCALayerMaxXMaxYCorner = 1 << 3,
};
typedef NS_OPTIONS(unsigned int, CAEdgeAntialiasingMask) {
    kCALayerLeftEdge = 1 << 0, kCALayerRightEdge = 1 << 1, kCALayerBottomEdge = 1 << 2, kCALayerTopEdge = 1 << 3,
};
typedef NS_OPTIONS(unsigned int, CAAutoresizingMask) {
    kCALayerNotSizable = 0, kCALayerMinXMargin = 1 << 0, kCALayerWidthSizable = 1 << 1,
    kCALayerMaxXMargin = 1 << 2, kCALayerMinYMargin = 1 << 3, kCALayerHeightSizable = 1 << 4,
    kCALayerMaxYMargin = 1 << 5,
};

@protocol CAMediaTiming
@property CFTimeInterval beginTime, timeOffset, duration, repeatDuration;
@property float repeatCount, speed;
@property BOOL autoreverses;
@property (copy) CAMediaTimingFillMode fillMode;
@end

@protocol CAAction
- (void)runActionForKey:(NSString *)event object:(id)anObject arguments:(nullable NSDictionary *)dict;
@end

@class CALayer, CAAnimation;

@protocol CALayerDelegate <NSObject>
@optional
- (void)displayLayer:(CALayer *)layer;
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx;
- (void)layerWillDraw:(CALayer *)layer;
- (void)layoutSublayersOfLayer:(CALayer *)layer;
- (nullable id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event;
@end

@protocol CAAnimationDelegate <NSObject>
@optional
- (void)animationDidStart:(CAAnimation *)anim;
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;
@end

@interface CAMediaTimingFunction : NSObject
+ (instancetype)functionWithName:(CAMediaTimingFunctionName)name;
+ (instancetype)functionWithControlPoints:(float)c1x :(float)c1y :(float)c2x :(float)c2y;
- (instancetype)initWithControlPoints:(float)c1x :(float)c1y :(float)c2x :(float)c2y;
- (void)getControlPointAtIndex:(size_t)idx values:(float[_Nonnull 2])ptr;
@end

@interface CALayer : NSObject <CAMediaTiming>
+ (instancetype)layer;
- (instancetype)init;
- (instancetype)initWithLayer:(id)layer;
- (nullable instancetype)presentationLayer;
- (instancetype)modelLayer;
+ (nullable id)defaultValueForKey:(NSString *)key;
+ (BOOL)needsDisplayForKey:(NSString *)key;
@property CGRect bounds;
@property CGPoint position;
@property CGFloat zPosition;
@property CGPoint anchorPoint;
@property CGFloat anchorPointZ;
@property CATransform3D transform;
- (CGAffineTransform)affineTransform;
- (void)setAffineTransform:(CGAffineTransform)m;
@property CGRect frame;
@property (getter=isHidden) BOOL hidden;
@property (getter=isDoubleSided) BOOL doubleSided;
@property (getter=isGeometryFlipped) BOOL geometryFlipped;
- (BOOL)contentsAreFlipped;
@property (nullable, readonly) CALayer *superlayer;
- (void)removeFromSuperlayer;
@property (nullable, copy) NSArray<__kindof CALayer *> *sublayers;
- (void)addSublayer:(CALayer *)layer;
- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned)idx;
- (void)insertSublayer:(CALayer *)layer below:(nullable CALayer *)sibling;
- (void)insertSublayer:(CALayer *)layer above:(nullable CALayer *)sibling;
- (void)replaceSublayer:(CALayer *)oldLayer with:(CALayer *)newLayer;
@property CATransform3D sublayerTransform;
@property (nullable, strong) __kindof CALayer *mask;
@property BOOL masksToBounds;
- (CGPoint)convertPoint:(CGPoint)p fromLayer:(nullable CALayer *)l;
- (CGPoint)convertPoint:(CGPoint)p toLayer:(nullable CALayer *)l;
- (CGRect)convertRect:(CGRect)r fromLayer:(nullable CALayer *)l;
- (CGRect)convertRect:(CGRect)r toLayer:(nullable CALayer *)l;
- (nullable __kindof CALayer *)hitTest:(CGPoint)p;
- (BOOL)containsPoint:(CGPoint)p;
@property (nullable, strong) id contents;
@property CGRect contentsRect;
@property (copy) CALayerContentsGravity contentsGravity;
@property CGFloat contentsScale;
@property CGRect contentsCenter;
@property (copy) NSString *contentsFormat;
@property CGFloat contentsHeadroom;
@property (copy) CALayerContentsFilter minificationFilter, magnificationFilter;
@property float minificationFilterBias;
@property (getter=isOpaque) BOOL opaque;
- (void)display;
- (void)setNeedsDisplay;
- (void)setNeedsDisplayInRect:(CGRect)r;
- (BOOL)needsDisplay;
- (void)displayIfNeeded;
@property BOOL needsDisplayOnBoundsChange;
@property BOOL drawsAsynchronously;
- (void)drawInContext:(CGContextRef)ctx;
- (void)renderInContext:(CGContextRef)ctx;
- (CFTimeInterval)convertTime:(CFTimeInterval)t fromLayer:(nullable CALayer *)l;
- (CFTimeInterval)convertTime:(CFTimeInterval)t toLayer:(nullable CALayer *)l;
@property CAEdgeAntialiasingMask edgeAntialiasingMask;
@property BOOL allowsEdgeAntialiasing;
@property (nullable) CGColorRef backgroundColor;
@property CGFloat cornerRadius;
@property CACornerMask maskedCorners;
@property (copy) CALayerCornerCurve cornerCurve;
@property CGFloat borderWidth;
@property (nullable) CGColorRef borderColor;
@property float opacity;
@property BOOL allowsGroupOpacity;
@property (nullable, strong) id compositingFilter;
@property (nullable, copy) NSArray *filters, *backgroundFilters;
@property BOOL shouldRasterize;
@property CGFloat rasterizationScale;
@property (nullable) CGColorRef shadowColor;
@property float shadowOpacity;
@property CGSize shadowOffset;
@property CGFloat shadowRadius;
@property (nullable) CGPathRef shadowPath;
- (CGSize)preferredFrameSize;
- (void)setNeedsLayout;
- (BOOL)needsLayout;
- (void)layoutIfNeeded;
- (void)layoutSublayers;
@property CAAutoresizingMask autoresizingMask;
+ (nullable id<CAAction>)defaultActionForKey:(NSString *)event;
- (nullable id<CAAction>)actionForKey:(NSString *)event;
@property (nullable, copy) NSDictionary<NSString *, id<CAAction>> *actions;
- (void)addAnimation:(CAAnimation *)anim forKey:(nullable NSString *)key;
- (void)removeAllAnimations;
- (void)removeAnimationForKey:(NSString *)key;
- (nullable NSArray<NSString *> *)animationKeys;
- (nullable __kindof CAAnimation *)animationForKey:(NSString *)key;
@property (nullable, copy) NSString *name;
@property (nullable, weak) id<CALayerDelegate> delegate;
@property (nullable, copy) NSDictionary *style;
@end

@interface CAShapeLayer : CALayer
@property (nullable) CGPathRef path;
@property (nullable) CGColorRef fillColor, strokeColor;
@property (copy) CAShapeLayerFillRule fillRule;
@property CGFloat strokeStart, strokeEnd, lineWidth, miterLimit, lineDashPhase;
@property (copy) CAShapeLayerLineCap lineCap;
@property (copy) CAShapeLayerLineJoin lineJoin;
@property (nullable, copy) NSArray<NSNumber *> *lineDashPattern;
@end

@interface CAGradientLayer : CALayer
@property (nullable, copy) NSArray *colors;
@property (nullable, copy) NSArray<NSNumber *> *locations;
@property CGPoint startPoint, endPoint;
@property (copy) CAGradientLayerType type;
@end

@interface CATextLayer : CALayer
@property (nullable, copy) id string;
@property (nullable) CFTypeRef font;
@property CGFloat fontSize;
@property (nullable) CGColorRef foregroundColor;
@property (getter=isWrapped) BOOL wrapped;
@property (copy) CATextLayerTruncationMode truncationMode;
@property (copy) CATextLayerAlignmentMode alignmentMode;
@property BOOL allowsFontSubpixelQuantization;
@end

@interface CAMetalLayer : CALayer
@property (nullable, strong) id device;
@property (nullable, readonly) id preferredDevice;
@property NSUInteger pixelFormat;
@property BOOL framebufferOnly;
@property CGSize drawableSize;
@property NSUInteger maximumDrawableCount;
@property BOOL presentsWithTransaction;
@property (nullable) CGColorSpaceRef colorspace;
@property BOOL wantsExtendedDynamicRangeContent;
@property BOOL displaySyncEnabled;
@property BOOL allowsNextDrawableTimeout;
- (nullable id)nextDrawable;
@end

@interface CAAnimation : NSObject <CAMediaTiming, CAAction, NSCopying>
+ (instancetype)animation;
+ (nullable id)defaultValueForKey:(NSString *)key;
- (BOOL)shouldArchiveValueForKey:(NSString *)key;
@property (nullable, strong) CAMediaTimingFunction *timingFunction;
@property (nullable, strong) id<CAAnimationDelegate> delegate;
@property (getter=isRemovedOnCompletion) BOOL removedOnCompletion;
@property CAFrameRateRange preferredFrameRateRange;
@end

@interface CAPropertyAnimation : CAAnimation
+ (instancetype)animationWithKeyPath:(nullable NSString *)path;
@property (nullable, copy) NSString *keyPath;
@property (getter=isAdditive) BOOL additive;
@property (getter=isCumulative) BOOL cumulative;
@property (nullable, strong) id valueFunction;
@end

@interface CABasicAnimation : CAPropertyAnimation
@property (nullable, strong) id fromValue, toValue, byValue;
@end

@interface CAKeyframeAnimation : CAPropertyAnimation
@property (nullable, copy) NSArray *values;
@property (nullable) CGPathRef path;
@property (nullable, copy) NSArray<NSNumber *> *keyTimes;
@property (nullable, copy) NSArray<CAMediaTimingFunction *> *timingFunctions;
@property (copy) CAAnimationCalculationMode calculationMode;
@property (nullable, copy) NSArray<NSNumber *> *tensionValues, *continuityValues, *biasValues;
@property (nullable, copy) NSString *rotationMode;
@end

@interface CASpringAnimation : CABasicAnimation
- (instancetype)initWithPerceptualDuration:(CFTimeInterval)perceptualDuration bounce:(CGFloat)bounce;
@property CGFloat mass, stiffness, damping, initialVelocity;
@property (readonly) CFTimeInterval settlingDuration;
@property (readonly) CFTimeInterval perceptualDuration;
@property (readonly) CGFloat bounce;
@property BOOL allowsOverdamping;
@end

@interface CATransition : CAAnimation
@property (copy) CATransitionType type;
@property (nullable, copy) CATransitionSubtype subtype;
@property float startProgress, endProgress;
@end

@interface CAAnimationGroup : CAAnimation
@property (nullable, copy) NSArray<CAAnimation *> *animations;
@end

@interface CATransaction : NSObject
+ (void)begin;
+ (void)commit;
+ (void)flush;
+ (void)lock;
+ (void)unlock;
+ (CFTimeInterval)animationDuration;
+ (void)setAnimationDuration:(CFTimeInterval)dur;
+ (nullable CAMediaTimingFunction *)animationTimingFunction;
+ (void)setAnimationTimingFunction:(nullable CAMediaTimingFunction *)function;
+ (BOOL)disableActions;
+ (void)setDisableActions:(BOOL)flag;
+ (nullable void (^)(void))completionBlock;
+ (void)setCompletionBlock:(nullable void (^)(void))block;
+ (nullable id)valueForKey:(NSString *)key;
+ (void)setValue:(nullable id)anObject forKey:(NSString *)key;
@end

/* A display link: calls its target once per frame (60 Hz) on the run loop
 * it is added to. AppKit hands them out (-[NSView displayLinkWithTarget:selector:]). */
@interface CADisplayLink : NSObject
+ (CADisplayLink *)_bn_displayLinkWithTarget:(id)target selector:(SEL)sel;
/* one for a view or window, quiet while its -_bn_displayLinkShowing is NO */
+ (CADisplayLink *)_bn_displayLinkWithTarget:(id)target selector:(SEL)sel source:(nullable id)source;
- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode;
- (void)removeFromRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode;
- (void)invalidate;
@property (readonly) CFTimeInterval timestamp, duration, targetTimestamp;
@property (getter=isPaused) BOOL paused;
@property CAFrameRateRange preferredFrameRateRange;
@end

@interface NSValue (CATransform3DAdditions)
+ (NSValue *)valueWithCATransform3D:(CATransform3D)t;
@property (readonly) CATransform3D CATransform3DValue;
@end

#pragma clang assume_nonnull end
#endif
