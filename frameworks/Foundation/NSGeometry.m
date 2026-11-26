/* NSGeometry: the zero constants, rectangle arithmetic, string forms
 * ("{{x, y}, {w, h}}") and NSValue's geometry boxes. */
#import "FoundationInternal.h"
#include <math.h>

const NSPoint NSZeroPoint = {0, 0};
const NSSize NSZeroSize = {0, 0};
const NSRect NSZeroRect = {{0, 0}, {0, 0}};
const NSEdgeInsets NSEdgeInsetsZero = {0, 0, 0, 0};

BOOL NSEdgeInsetsEqual(NSEdgeInsets a, NSEdgeInsets b) {
    return a.top == b.top && a.left == b.left && a.bottom == b.bottom && a.right == b.right;
}
NSRect NSOffsetRect(NSRect r, CGFloat dx, CGFloat dy) {
    r.origin.x += dx;
    r.origin.y += dy;
    return r;
}
NSRect NSInsetRect(NSRect r, CGFloat dx, CGFloat dy) {
    r.origin.x += dx;
    r.origin.y += dy;
    r.size.width -= 2 * dx;
    r.size.height -= 2 * dy;
    if (r.size.width < 0 || r.size.height < 0) return NSZeroRect;
    return r;
}
NSRect NSIntegralRect(NSRect r) {
    if (NSIsEmptyRect(r)) return NSZeroRect;
    CGFloat x0 = floor(NSMinX(r)), y0 = floor(NSMinY(r)), x1 = ceil(NSMaxX(r)), y1 = ceil(NSMaxY(r));
    return NSMakeRect(x0, y0, x1 - x0, y1 - y0);
}
NSRect NSUnionRect(NSRect a, NSRect b) {
    if (NSIsEmptyRect(a)) return b;
    if (NSIsEmptyRect(b)) return a;
    CGFloat x0 = fmin(NSMinX(a), NSMinX(b)), y0 = fmin(NSMinY(a), NSMinY(b));
    CGFloat x1 = fmax(NSMaxX(a), NSMaxX(b)), y1 = fmax(NSMaxY(a), NSMaxY(b));
    return NSMakeRect(x0, y0, x1 - x0, y1 - y0);
}
NSRect NSIntersectionRect(NSRect a, NSRect b) {
    CGFloat x0 = fmax(NSMinX(a), NSMinX(b)), y0 = fmax(NSMinY(a), NSMinY(b));
    CGFloat x1 = fmin(NSMaxX(a), NSMaxX(b)), y1 = fmin(NSMaxY(a), NSMaxY(b));
    if (x1 <= x0 || y1 <= y0) return NSZeroRect;
    return NSMakeRect(x0, y0, x1 - x0, y1 - y0);
}
BOOL NSIntersectsRect(NSRect a, NSRect b) { return !NSIsEmptyRect(NSIntersectionRect(a, b)); }
BOOL NSContainsRect(NSRect a, NSRect b) {
    return !NSIsEmptyRect(b) && NSMinX(b) >= NSMinX(a) && NSMinY(b) >= NSMinY(a) && NSMaxX(b) <= NSMaxX(a) &&
           NSMaxY(b) <= NSMaxY(a);
}
BOOL NSMouseInRect(NSPoint p, NSRect r, BOOL flipped) {
    return p.x >= NSMinX(r) && p.x < NSMaxX(r) &&
           (flipped ? p.y >= NSMinY(r) && p.y < NSMaxY(r) : p.y > NSMinY(r) && p.y <= NSMaxY(r));
}
void NSDivideRect(NSRect r, NSRect *slice, NSRect *rem, CGFloat amount, NSRectEdge edge) {
    NSRect s = r, m = r;
    switch (edge) {
    case NSRectEdgeMinX:
        amount = fmin(amount, r.size.width);
        s.size.width = amount;
        m.origin.x += amount;
        m.size.width -= amount;
        break;
    case NSRectEdgeMaxX:
        amount = fmin(amount, r.size.width);
        s.origin.x = NSMaxX(r) - amount;
        s.size.width = amount;
        m.size.width -= amount;
        break;
    case NSRectEdgeMinY:
        amount = fmin(amount, r.size.height);
        s.size.height = amount;
        m.origin.y += amount;
        m.size.height -= amount;
        break;
    case NSRectEdgeMaxY:
        amount = fmin(amount, r.size.height);
        s.origin.y = NSMaxY(r) - amount;
        s.size.height = amount;
        m.size.height -= amount;
        break;
    }
    if (slice) *slice = s;
    if (rem) *rem = m;
}

NSString *NSStringFromPoint(NSPoint p) { return [NSString stringWithFormat:@"{%g, %g}", p.x, p.y]; }
NSString *NSStringFromSize(NSSize s) { return [NSString stringWithFormat:@"{%g, %g}", s.width, s.height]; }
NSString *NSStringFromRect(NSRect r) {
    return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", r.origin.x, r.origin.y, r.size.width, r.size.height];
}
/* Reads up to n numbers from s, skipping anything else. */
static int numbers(NSString *s, double *out, int n) {
    const char *c = s.UTF8String;
    int k = 0;
    while (c && *c && k < n) {
        char *end;
        double v = strtod(c, &end);
        if (end != c) {
            out[k++] = v;
            c = end;
        } else {
            c++;
        }
    }
    return k;
}
NSRect NSRectFromString(NSString *s) {
    double v[4] = {0};
    numbers(s, v, 4);
    return NSMakeRect(v[0], v[1], v[2], v[3]);
}
NSPoint NSPointFromString(NSString *s) {
    double v[2] = {0};
    numbers(s, v, 2);
    return NSMakePoint(v[0], v[1]);
}
NSSize NSSizeFromString(NSString *s) {
    double v[2] = {0};
    numbers(s, v, 2);
    return NSMakeSize(v[0], v[1]);
}

@implementation NSValue (NSValueGeometryExtensions)
+ (NSValue *)valueWithPoint:(NSPoint)p { return [self valueWithBytes:&p objCType:@encode(NSPoint)]; }
+ (NSValue *)valueWithSize:(NSSize)s { return [self valueWithBytes:&s objCType:@encode(NSSize)]; }
+ (NSValue *)valueWithRect:(NSRect)r { return [self valueWithBytes:&r objCType:@encode(NSRect)]; }
+ (NSValue *)valueWithEdgeInsets:(NSEdgeInsets)e { return [self valueWithBytes:&e objCType:@encode(NSEdgeInsets)]; }
- (NSPoint)pointValue {
    NSPoint p = NSZeroPoint;
    [self getValue:&p];
    return p;
}
- (NSSize)sizeValue {
    NSSize s = NSZeroSize;
    [self getValue:&s];
    return s;
}
- (NSRect)rectValue {
    NSRect r = NSZeroRect;
    [self getValue:&r];
    return r;
}
- (NSEdgeInsets)edgeInsetsValue {
    NSEdgeInsets e = NSEdgeInsetsZero;
    [self getValue:&e];
    return e;
}
@end

NSRange NSUnionRange(NSRange a, NSRange b) {
    NSUInteger lo = a.location < b.location ? a.location : b.location;
    NSUInteger hi = NSMaxRange(a) > NSMaxRange(b) ? NSMaxRange(a) : NSMaxRange(b);
    return NSMakeRange(lo, hi - lo);
}
NSRange NSIntersectionRange(NSRange a, NSRange b) {
    NSUInteger lo = a.location > b.location ? a.location : b.location;
    NSUInteger hi = NSMaxRange(a) < NSMaxRange(b) ? NSMaxRange(a) : NSMaxRange(b);
    return hi > lo ? NSMakeRange(lo, hi - lo) : NSMakeRange(0, 0);
}
NSString *NSStringFromRange(NSRange r) {
    return [NSString stringWithFormat:@"{%lu, %lu}", (unsigned long)r.location, (unsigned long)r.length];
}
NSRange NSRangeFromString(NSString *s) {
    double v[2] = {0};
    numbers(s, v, 2);
    return NSMakeRange((NSUInteger)v[0], (NSUInteger)v[1]);
}
