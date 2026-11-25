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

CGFloat CGRectGetMinX(CGRect r);
CGFloat CGRectGetMidX(CGRect r);
CGFloat CGRectGetMaxX(CGRect r);
CGFloat CGRectGetMinY(CGRect r);
CGFloat CGRectGetMidY(CGRect r);
CGFloat CGRectGetMaxY(CGRect r);
CGFloat CGRectGetWidth(CGRect r);
CGFloat CGRectGetHeight(CGRect r);
bool CGPointEqualToPoint(CGPoint a, CGPoint b);
bool CGSizeEqualToSize(CGSize a, CGSize b);
bool CGRectEqualToRect(CGRect a, CGRect b);
CGRect CGRectStandardize(CGRect r);
bool CGRectIsEmpty(CGRect r);
bool CGRectIsNull(CGRect r);
bool CGRectIsInfinite(CGRect r);
CGRect CGRectInset(CGRect r, CGFloat dx, CGFloat dy);
CGRect CGRectIntegral(CGRect r);
CGRect CGRectUnion(CGRect a, CGRect b);
CGRect CGRectIntersection(CGRect a, CGRect b);
CGRect CGRectOffset(CGRect r, CGFloat dx, CGFloat dy);
void CGRectDivide(CGRect r, CGRect *slice, CGRect *remainder, CGFloat amount, CGRectEdge edge);
bool CGRectContainsPoint(CGRect r, CGPoint p);
bool CGRectContainsRect(CGRect a, CGRect b);
bool CGRectIntersectsRect(CGRect a, CGRect b);

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
CGPoint CGPointApplyAffineTransform(CGPoint p, CGAffineTransform t);
CGSize CGSizeApplyAffineTransform(CGSize s, CGAffineTransform t);
CGRect CGRectApplyAffineTransform(CGRect r, CGAffineTransform t);
#endif
