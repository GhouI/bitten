/* bitten SDK: CGPath. */
#ifndef BITTEN_CGPATH_H
#define BITTEN_CGPATH_H
#include <CoreGraphics/CGBase.h>

CG_ASSUME_BEGIN
typedef struct CG_BRIDGED_TYPE(id) CGPath *CGMutablePathRef;
typedef const struct CG_BRIDGED_TYPE(id) CGPath *CGPathRef;

typedef CG_ENUM(int32_t, CGLineJoin) { kCGLineJoinMiter, kCGLineJoinRound, kCGLineJoinBevel };
typedef CG_ENUM(int32_t, CGLineCap) { kCGLineCapButt, kCGLineCapRound, kCGLineCapSquare };
typedef CG_ENUM(int32_t, CGPathElementType) {
    kCGPathElementMoveToPoint, kCGPathElementAddLineToPoint, kCGPathElementAddQuadCurveToPoint,
    kCGPathElementAddCurveToPoint, kCGPathElementCloseSubpath,
};
struct CGPathElement { CGPathElementType type; CGPoint *points; };
typedef struct CGPathElement CGPathElement;
typedef void (*CGPathApplierFunction)(void *_Nullable info, const CGPathElement *element);
typedef void (^CGPathApplyBlock)(const CGPathElement *element);

CFTypeID CGPathGetTypeID(void);
CGMutablePathRef CGPathCreateMutable(void);
CGPathRef _Nullable CGPathCreateCopy(CGPathRef _Nullable path);
CGPathRef _Nullable CGPathCreateCopyByTransformingPath(CGPathRef _Nullable path, const CGAffineTransform *_Nullable t);
CGMutablePathRef _Nullable CGPathCreateMutableCopy(CGPathRef _Nullable path);
CGMutablePathRef _Nullable CGPathCreateMutableCopyByTransformingPath(CGPathRef _Nullable path,
    const CGAffineTransform *_Nullable t);
CGPathRef CGPathCreateWithRect(CGRect rect, const CGAffineTransform *_Nullable t);
CGPathRef CGPathCreateWithEllipseInRect(CGRect rect, const CGAffineTransform *_Nullable t);
CGPathRef CGPathCreateWithRoundedRect(CGRect rect, CGFloat cornerWidth, CGFloat cornerHeight,
    const CGAffineTransform *_Nullable t);
CGPathRef _Nullable CGPathCreateCopyByStrokingPath(CGPathRef _Nullable path, const CGAffineTransform *_Nullable t,
    CGFloat lineWidth, CGLineCap cap, CGLineJoin join, CGFloat miterLimit);
CGPathRef _Nullable CGPathRetain(CGPathRef _Nullable path);
void CGPathRelease(CGPathRef _Nullable path);
bool CGPathEqualToPath(CGPathRef _Nullable a, CGPathRef _Nullable b);
void CGPathMoveToPoint(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m, CGFloat x, CGFloat y);
void CGPathAddLineToPoint(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m, CGFloat x, CGFloat y);
void CGPathAddQuadCurveToPoint(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m,
    CGFloat cpx, CGFloat cpy, CGFloat x, CGFloat y);
void CGPathAddCurveToPoint(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m,
    CGFloat cp1x, CGFloat cp1y, CGFloat cp2x, CGFloat cp2y, CGFloat x, CGFloat y);
void CGPathCloseSubpath(CGMutablePathRef _Nullable path);
void CGPathAddRect(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m, CGRect rect);
void CGPathAddRects(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m,
    const CGRect *_Nullable rects, size_t count);
void CGPathAddLines(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m,
    const CGPoint *_Nullable points, size_t count);
void CGPathAddEllipseInRect(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m, CGRect rect);
void CGPathAddRoundedRect(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m, CGRect rect,
    CGFloat cornerWidth, CGFloat cornerHeight);
void CGPathAddRelativeArc(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m,
    CGFloat x, CGFloat y, CGFloat radius, CGFloat startAngle, CGFloat delta);
void CGPathAddArc(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m, CGFloat x, CGFloat y,
    CGFloat radius, CGFloat startAngle, CGFloat endAngle, bool clockwise);
void CGPathAddArcToPoint(CGMutablePathRef _Nullable path, const CGAffineTransform *_Nullable m,
    CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat radius);
void CGPathAddPath(CGMutablePathRef _Nullable path1, const CGAffineTransform *_Nullable m, CGPathRef _Nullable path2);
bool CGPathIsEmpty(CGPathRef _Nullable path);
bool CGPathIsRect(CGPathRef _Nullable path, CGRect *_Nullable rect);
CGPoint CGPathGetCurrentPoint(CGPathRef _Nullable path);
CGRect CGPathGetBoundingBox(CGPathRef _Nullable path);
CGRect CGPathGetPathBoundingBox(CGPathRef _Nullable path);
bool CGPathContainsPoint(CGPathRef _Nullable path, const CGAffineTransform *_Nullable m, CGPoint point, bool eoFill);
void CGPathApply(CGPathRef _Nullable path, void *_Nullable info, CGPathApplierFunction _Nullable function);
void CGPathApplyWithBlock(CGPathRef path, CGPathApplyBlock block);
CG_ASSUME_END
#endif
