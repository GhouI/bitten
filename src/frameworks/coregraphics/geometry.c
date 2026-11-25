/* CoreGraphics geometry: points, sizes, rectangles and affine transforms.
 * Plain value arithmetic with the documented semantics (null and infinite
 * rectangles, standardised negative sizes). */
#include <float.h>
#include <math.h>
#include <stdbool.h>

#include "dx.h"

typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;
enum { CGRectMinXEdge, CGRectMinYEdge, CGRectMaxXEdge, CGRectMaxYEdge };

static const CGPoint d_CGPointZero = {0, 0};
static const CGSize d_CGSizeZero = {0, 0};
static const CGRect d_CGRectZero = {{0, 0}, {0, 0}};
static const CGRect d_CGRectNull = {{INFINITY, INFINITY}, {0, 0}};
static const CGRect d_CGRectInfinite = {{-DBL_MAX / 2, -DBL_MAX / 2}, {DBL_MAX, DBL_MAX}};
static const CGAffineTransform d_CGAffineTransformIdentity = {1, 0, 0, 1, 0, 0};
DX_EXPORT("_CGPointZero", &d_CGPointZero);
DX_EXPORT("_CGSizeZero", &d_CGSizeZero);
DX_EXPORT("_CGRectZero", &d_CGRectZero);
DX_EXPORT("_CGRectNull", &d_CGRectNull);
DX_EXPORT("_CGRectInfinite", &d_CGRectInfinite);
DX_EXPORT("_CGAffineTransformIdentity", &d_CGAffineTransformIdentity);

static CGRect d_CGRectStandardize(CGRect r) {
    if (r.size.width < 0) { r.origin.x += r.size.width; r.size.width = -r.size.width; }
    if (r.size.height < 0) { r.origin.y += r.size.height; r.size.height = -r.size.height; }
    return r;
}
DX_FN(CGRectStandardize);
static bool d_CGRectIsNull(CGRect r) { return isinf(r.origin.x) && r.origin.x > 0; }
DX_FN(CGRectIsNull);
static bool d_CGRectIsInfinite(CGRect r) {
    return r.origin.x == d_CGRectInfinite.origin.x && r.size.width == d_CGRectInfinite.size.width;
}
DX_FN(CGRectIsInfinite);
static bool d_CGRectIsEmpty(CGRect r) { return d_CGRectIsNull(r) || r.size.width == 0 || r.size.height == 0; }
DX_FN(CGRectIsEmpty);

static CGFloat d_CGRectGetMinX(CGRect r) { r = d_CGRectStandardize(r); return r.origin.x; }
static CGFloat d_CGRectGetMaxX(CGRect r) { r = d_CGRectStandardize(r); return r.origin.x + r.size.width; }
static CGFloat d_CGRectGetMidX(CGRect r) { r = d_CGRectStandardize(r); return r.origin.x + r.size.width / 2; }
static CGFloat d_CGRectGetMinY(CGRect r) { r = d_CGRectStandardize(r); return r.origin.y; }
static CGFloat d_CGRectGetMaxY(CGRect r) { r = d_CGRectStandardize(r); return r.origin.y + r.size.height; }
static CGFloat d_CGRectGetMidY(CGRect r) { r = d_CGRectStandardize(r); return r.origin.y + r.size.height / 2; }
static CGFloat d_CGRectGetWidth(CGRect r) { return fabs(r.size.width); }
static CGFloat d_CGRectGetHeight(CGRect r) { return fabs(r.size.height); }
DX_FN(CGRectGetMinX); DX_FN(CGRectGetMaxX); DX_FN(CGRectGetMidX);
DX_FN(CGRectGetMinY); DX_FN(CGRectGetMaxY); DX_FN(CGRectGetMidY);
DX_FN(CGRectGetWidth); DX_FN(CGRectGetHeight);

static bool d_CGPointEqualToPoint(CGPoint a, CGPoint b) { return a.x == b.x && a.y == b.y; }
static bool d_CGSizeEqualToSize(CGSize a, CGSize b) { return a.width == b.width && a.height == b.height; }
static bool d_CGRectEqualToRect(CGRect a, CGRect b) {
    if (d_CGRectIsNull(a) || d_CGRectIsNull(b)) return d_CGRectIsNull(a) && d_CGRectIsNull(b);
    a = d_CGRectStandardize(a);
    b = d_CGRectStandardize(b);
    return d_CGPointEqualToPoint(a.origin, b.origin) && d_CGSizeEqualToSize(a.size, b.size);
}
DX_FN(CGPointEqualToPoint); DX_FN(CGSizeEqualToSize); DX_FN(CGRectEqualToRect);

static CGRect d_CGRectInset(CGRect r, CGFloat dx, CGFloat dy) {
    if (d_CGRectIsNull(r)) return r;
    r = d_CGRectStandardize(r);
    r.origin.x += dx; r.origin.y += dy;
    r.size.width -= 2 * dx; r.size.height -= 2 * dy;
    if (r.size.width < 0 || r.size.height < 0) return d_CGRectNull;
    return r;
}
DX_FN(CGRectInset);
static CGRect d_CGRectOffset(CGRect r, CGFloat dx, CGFloat dy) {
    if (d_CGRectIsNull(r)) return r;
    r = d_CGRectStandardize(r);
    r.origin.x += dx; r.origin.y += dy;
    return r;
}
DX_FN(CGRectOffset);
static CGRect d_CGRectIntegral(CGRect r) {
    if (d_CGRectIsNull(r) || d_CGRectIsInfinite(r)) return r;
    r = d_CGRectStandardize(r);
    CGFloat x0 = floor(r.origin.x), y0 = floor(r.origin.y);
    CGFloat x1 = ceil(r.origin.x + r.size.width), y1 = ceil(r.origin.y + r.size.height);
    CGRect o = {{x0, y0}, {x1 - x0, y1 - y0}};
    return o;
}
DX_FN(CGRectIntegral);
static CGRect d_CGRectUnion(CGRect a, CGRect b) {
    if (d_CGRectIsNull(a)) return d_CGRectStandardize(b);
    if (d_CGRectIsNull(b)) return d_CGRectStandardize(a);
    a = d_CGRectStandardize(a);
    b = d_CGRectStandardize(b);
    CGFloat x0 = fmin(a.origin.x, b.origin.x), y0 = fmin(a.origin.y, b.origin.y);
    CGFloat x1 = fmax(a.origin.x + a.size.width, b.origin.x + b.size.width);
    CGFloat y1 = fmax(a.origin.y + a.size.height, b.origin.y + b.size.height);
    CGRect o = {{x0, y0}, {x1 - x0, y1 - y0}};
    return o;
}
DX_FN(CGRectUnion);
static CGRect d_CGRectIntersection(CGRect a, CGRect b) {
    if (d_CGRectIsNull(a) || d_CGRectIsNull(b)) return d_CGRectNull;
    a = d_CGRectStandardize(a);
    b = d_CGRectStandardize(b);
    CGFloat x0 = fmax(a.origin.x, b.origin.x), y0 = fmax(a.origin.y, b.origin.y);
    CGFloat x1 = fmin(a.origin.x + a.size.width, b.origin.x + b.size.width);
    CGFloat y1 = fmin(a.origin.y + a.size.height, b.origin.y + b.size.height);
    if (x1 < x0 || y1 < y0) return d_CGRectNull;
    CGRect o = {{x0, y0}, {x1 - x0, y1 - y0}};
    return o;
}
DX_FN(CGRectIntersection);
static void d_CGRectDivide(CGRect r, CGRect *slice, CGRect *rem, CGFloat amount, int edge) {
    r = d_CGRectStandardize(r);
    CGRect s = r, m = r;
    if (amount < 0) amount = 0;
    switch (edge) {
    case CGRectMinXEdge:
        if (amount > r.size.width) amount = r.size.width;
        s.size.width = amount; m.origin.x += amount; m.size.width -= amount; break;
    case CGRectMaxXEdge:
        if (amount > r.size.width) amount = r.size.width;
        s.origin.x += r.size.width - amount; s.size.width = amount; m.size.width -= amount; break;
    case CGRectMinYEdge:
        if (amount > r.size.height) amount = r.size.height;
        s.size.height = amount; m.origin.y += amount; m.size.height -= amount; break;
    default:
        if (amount > r.size.height) amount = r.size.height;
        s.origin.y += r.size.height - amount; s.size.height = amount; m.size.height -= amount; break;
    }
    if (slice) *slice = s;
    if (rem) *rem = m;
}
DX_FN(CGRectDivide);
static bool d_CGRectContainsPoint(CGRect r, CGPoint p) {
    if (d_CGRectIsNull(r)) return false;
    r = d_CGRectStandardize(r);
    return p.x >= r.origin.x && p.x < r.origin.x + r.size.width && p.y >= r.origin.y &&
           p.y < r.origin.y + r.size.height;
}
DX_FN(CGRectContainsPoint);
static bool d_CGRectContainsRect(CGRect a, CGRect b) {
    return d_CGRectEqualToRect(d_CGRectUnion(a, b), d_CGRectStandardize(a));
}
DX_FN(CGRectContainsRect);
static bool d_CGRectIntersectsRect(CGRect a, CGRect b) {
    CGRect i = d_CGRectIntersection(a, b);
    return !d_CGRectIsNull(i) && i.size.width > 0 && i.size.height > 0;
}
DX_FN(CGRectIntersectsRect);

static CGAffineTransform d_CGAffineTransformMake(CGFloat a, CGFloat b, CGFloat c, CGFloat d, CGFloat tx,
                                                 CGFloat ty) {
    CGAffineTransform t = {a, b, c, d, tx, ty};
    return t;
}
DX_FN(CGAffineTransformMake);
static CGAffineTransform d_CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty) {
    return d_CGAffineTransformMake(1, 0, 0, 1, tx, ty);
}
DX_FN(CGAffineTransformMakeTranslation);
static CGAffineTransform d_CGAffineTransformMakeScale(CGFloat sx, CGFloat sy) {
    return d_CGAffineTransformMake(sx, 0, 0, sy, 0, 0);
}
DX_FN(CGAffineTransformMakeScale);
static CGAffineTransform d_CGAffineTransformMakeRotation(CGFloat angle) {
    CGFloat c = cos(angle), s = sin(angle);
    return d_CGAffineTransformMake(c, s, -s, c, 0, 0);
}
DX_FN(CGAffineTransformMakeRotation);
static bool d_CGAffineTransformIsIdentity(CGAffineTransform t) {
    return t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1 && t.tx == 0 && t.ty == 0;
}
DX_FN(CGAffineTransformIsIdentity);
/* t1 then t2 */
static CGAffineTransform d_CGAffineTransformConcat(CGAffineTransform t1, CGAffineTransform t2) {
    CGAffineTransform r = {
        t1.a * t2.a + t1.b * t2.c,           t1.a * t2.b + t1.b * t2.d,
        t1.c * t2.a + t1.d * t2.c,           t1.c * t2.b + t1.d * t2.d,
        t1.tx * t2.a + t1.ty * t2.c + t2.tx, t1.tx * t2.b + t1.ty * t2.d + t2.ty,
    };
    return r;
}
DX_FN(CGAffineTransformConcat);
static CGAffineTransform d_CGAffineTransformTranslate(CGAffineTransform t, CGFloat tx, CGFloat ty) {
    return d_CGAffineTransformConcat(d_CGAffineTransformMakeTranslation(tx, ty), t);
}
DX_FN(CGAffineTransformTranslate);
static CGAffineTransform d_CGAffineTransformScale(CGAffineTransform t, CGFloat sx, CGFloat sy) {
    return d_CGAffineTransformConcat(d_CGAffineTransformMakeScale(sx, sy), t);
}
DX_FN(CGAffineTransformScale);
static CGAffineTransform d_CGAffineTransformRotate(CGAffineTransform t, CGFloat angle) {
    return d_CGAffineTransformConcat(d_CGAffineTransformMakeRotation(angle), t);
}
DX_FN(CGAffineTransformRotate);
static CGAffineTransform d_CGAffineTransformInvert(CGAffineTransform t) {
    CGFloat det = t.a * t.d - t.b * t.c;
    if (det == 0) return t;
    CGAffineTransform r = {t.d / det, -t.b / det, -t.c / det, t.a / det, 0, 0};
    r.tx = -(t.tx * r.a + t.ty * r.c);
    r.ty = -(t.tx * r.b + t.ty * r.d);
    return r;
}
DX_FN(CGAffineTransformInvert);
static bool d_CGAffineTransformEqualToTransform(CGAffineTransform x, CGAffineTransform y) {
    return x.a == y.a && x.b == y.b && x.c == y.c && x.d == y.d && x.tx == y.tx && x.ty == y.ty;
}
DX_FN(CGAffineTransformEqualToTransform);
static CGPoint d_CGPointApplyAffineTransform(CGPoint p, CGAffineTransform t) {
    CGPoint r = {t.a * p.x + t.c * p.y + t.tx, t.b * p.x + t.d * p.y + t.ty};
    return r;
}
DX_FN(CGPointApplyAffineTransform);
static CGSize d_CGSizeApplyAffineTransform(CGSize s, CGAffineTransform t) {
    CGSize r = {t.a * s.width + t.c * s.height, t.b * s.width + t.d * s.height};
    return r;
}
DX_FN(CGSizeApplyAffineTransform);
static CGRect d_CGRectApplyAffineTransform(CGRect r, CGAffineTransform t) {
    if (d_CGRectIsNull(r)) return r;
    r = d_CGRectStandardize(r);
    CGPoint p[4] = {r.origin,
                    {r.origin.x + r.size.width, r.origin.y},
                    {r.origin.x, r.origin.y + r.size.height},
                    {r.origin.x + r.size.width, r.origin.y + r.size.height}};
    CGFloat x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
    for (int i = 0; i < 4; i++) {
        CGPoint q = d_CGPointApplyAffineTransform(p[i], t);
        x0 = fmin(x0, q.x); y0 = fmin(y0, q.y); x1 = fmax(x1, q.x); y1 = fmax(y1, q.y);
    }
    CGRect o = {{x0, y0}, {x1 - x0, y1 - y0}};
    return o;
}
DX_FN(CGRectApplyAffineTransform);
