/* bitten SDK: CoreGraphics geometry. Written from the public documentation. */
#ifndef BITTEN_CGGEOMETRY_H
#define BITTEN_CGGEOMETRY_H
#include <stdbool.h>
#include <stdint.h>

#ifndef CGFLOAT_DEFINED
#define CGFLOAT_DEFINED 1
typedef double CGFloat;
#define CGFLOAT_IS_DOUBLE 1
#endif

struct CGPoint { CGFloat x; CGFloat y; };
typedef struct CGPoint CGPoint;
struct CGSize { CGFloat width; CGFloat height; };
typedef struct CGSize CGSize;
struct CGVector { CGFloat dx; CGFloat dy; };
typedef struct CGVector CGVector;
struct CGRect { CGPoint origin; CGSize size; };
typedef struct CGRect CGRect;
struct CGAffineTransform { CGFloat a, b, c, d, tx, ty; };
typedef struct CGAffineTransform CGAffineTransform;
typedef enum : uint32_t { CGRectMinXEdge, CGRectMinYEdge, CGRectMaxXEdge, CGRectMaxYEdge } CGRectEdge;

extern const CGPoint CGPointZero;
extern const CGSize CGSizeZero;
extern const CGRect CGRectZero;
extern const CGRect CGRectNull;
extern const CGRect CGRectInfinite;
extern const CGAffineTransform CGAffineTransformIdentity;

static inline CGPoint CGPointMake(CGFloat x, CGFloat y) { CGPoint p = {x, y}; return p; }
static inline CGSize CGSizeMake(CGFloat w, CGFloat h) { CGSize s = {w, h}; return s; }
static inline CGVector CGVectorMake(CGFloat dx, CGFloat dy) { CGVector v = {dx, dy}; return v; }
static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    CGRect r = {{x, y}, {w, h}};
    return r;
}

CGFloat CGRectGetMinX(CGRect r) __attribute__((swift_name("getter:CGRect.minX(self:)")));
CGFloat CGRectGetMidX(CGRect r) __attribute__((swift_name("getter:CGRect.midX(self:)")));
CGFloat CGRectGetMaxX(CGRect r) __attribute__((swift_name("getter:CGRect.maxX(self:)")));
CGFloat CGRectGetMinY(CGRect r) __attribute__((swift_name("getter:CGRect.minY(self:)")));
CGFloat CGRectGetMidY(CGRect r) __attribute__((swift_name("getter:CGRect.midY(self:)")));
CGFloat CGRectGetMaxY(CGRect r) __attribute__((swift_name("getter:CGRect.maxY(self:)")));
CGFloat CGRectGetWidth(CGRect r) __attribute__((swift_name("getter:CGRect.width(self:)")));
CGFloat CGRectGetHeight(CGRect r) __attribute__((swift_name("getter:CGRect.height(self:)")));
bool CGPointEqualToPoint(CGPoint a, CGPoint b) __attribute__((swift_name("CGPoint.equalTo(self:_:)")));
bool CGSizeEqualToSize(CGSize a, CGSize b) __attribute__((swift_name("CGSize.equalTo(self:_:)")));
bool CGRectEqualToRect(CGRect a, CGRect b) __attribute__((swift_name("CGRect.equalTo(self:_:)")));
CGRect CGRectStandardize(CGRect r) __attribute__((swift_name("getter:CGRect.standardized(self:)")));
bool CGRectIsEmpty(CGRect r) __attribute__((swift_name("getter:CGRect.isEmpty(self:)")));
bool CGRectIsNull(CGRect r) __attribute__((swift_name("getter:CGRect.isNull(self:)")));
bool CGRectIsInfinite(CGRect r) __attribute__((swift_name("getter:CGRect.isInfinite(self:)")));
CGRect CGRectInset(CGRect r, CGFloat dx, CGFloat dy) __attribute__((swift_name("CGRect.insetBy(self:dx:dy:)")));
CGRect CGRectIntegral(CGRect r) __attribute__((swift_name("getter:CGRect.integral(self:)")));
CGRect CGRectUnion(CGRect a, CGRect b) __attribute__((swift_name("CGRect.union(self:_:)")));
CGRect CGRectIntersection(CGRect a, CGRect b) __attribute__((swift_name("CGRect.intersection(self:_:)")));
CGRect CGRectOffset(CGRect r, CGFloat dx, CGFloat dy) __attribute__((swift_name("CGRect.offsetBy(self:dx:dy:)")));
void CGRectDivide(CGRect r, CGRect *slice, CGRect *remainder, CGFloat amount, CGRectEdge edge);
bool CGRectContainsPoint(CGRect r, CGPoint p) __attribute__((swift_name("CGRect.contains(self:_:)")));
bool CGRectContainsRect(CGRect a, CGRect b) __attribute__((swift_name("CGRect.contains(self:_:)")));
bool CGRectIntersectsRect(CGRect a, CGRect b) __attribute__((swift_name("CGRect.intersects(self:_:)")));

CGAffineTransform CGAffineTransformMake(CGFloat a, CGFloat b, CGFloat c, CGFloat d, CGFloat tx, CGFloat ty);
CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty);
CGAffineTransform CGAffineTransformMakeScale(CGFloat sx, CGFloat sy);
CGAffineTransform CGAffineTransformMakeRotation(CGFloat angle);
bool CGAffineTransformIsIdentity(CGAffineTransform t);
CGAffineTransform CGAffineTransformTranslate(CGAffineTransform t, CGFloat tx, CGFloat ty);
CGAffineTransform CGAffineTransformScale(CGAffineTransform t, CGFloat sx, CGFloat sy);
CGAffineTransform CGAffineTransformRotate(CGAffineTransform t, CGFloat angle);
CGAffineTransform CGAffineTransformInvert(CGAffineTransform t);
CGAffineTransform CGAffineTransformConcat(CGAffineTransform t1, CGAffineTransform t2);
bool CGAffineTransformEqualToTransform(CGAffineTransform t1, CGAffineTransform t2);
CGPoint CGPointApplyAffineTransform(CGPoint p, CGAffineTransform t) __attribute__((swift_name("CGPoint.applying(self:_:)")));
CGSize CGSizeApplyAffineTransform(CGSize s, CGAffineTransform t) __attribute__((swift_name("CGSize.applying(self:_:)")));
CGRect CGRectApplyAffineTransform(CGRect r, CGAffineTransform t) __attribute__((swift_name("CGRect.applying(self:_:)")));
#endif
