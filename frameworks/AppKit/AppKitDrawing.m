/* AppKit drawing: NSGraphicsContext over a CGContext, colours and rect
 * fills into the current context, NSBezierPath over CGPath, and windows
 * that draw their view tree into a bitmap and hand it to the display
 * (src/frameworks/display: a browser page shows each window). */
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <stdio.h>
#include <objc/runtime.h>
#include <pthread.h>

/* ---- the display's handoff API (exported by bitten's runtime) ---- */
size_t bitten_cg_gstate_depth(CGContextRef c);
void bitten_cg_restore_to_depth(CGContextRef c, size_t depth);
int bitten_display_present(uint32_t window, const void *pixels, size_t width, size_t height, size_t row_bytes,
                           uint32_t bitmap_info, double x, double y, const char *title);
@interface NSAppearance (BittenDrawing)
+ (NSAppearance *)_bn_swapDrawingAppearance:(NSAppearance *)appearance; /* AppKitAppearance.m */
@end
int bitten_display_present_rect(uint32_t window, const void *pixels, size_t width, size_t height, size_t row_bytes,
                                uint32_t bitmap_info, double x, double y, const char *title, size_t rx, size_t ry,
                                size_t rw, size_t rh);
void bitten_display_close(uint32_t window);
int bitten_display_set_style(uint32_t window, uint32_t flags, int32_t level);
void bitten_display_order_front(uint32_t window);

/* ---- NSGraphicsContext ---------------------------------------------------- */
int bn_blend_mode_for_operation(NSCompositingOperation op);

static pthread_key_t current_key;
static pthread_once_t current_once = PTHREAD_ONCE_INIT;
static void make_current_key(void) { pthread_key_create(&current_key, NULL); }

@implementation NSGraphicsContext {
    CGContextRef _cg;
    BOOL _flipped;
    NSCompositingOperation _operation;
    NSImageInterpolation _interpolation;
    BOOL _noAntialias;
    NSPoint _patternPhase;
    NSInteger _renderingIntent;
}
/* The context's drawing state: each setting goes to the CGContext too. */
- (NSCompositingOperation)compositingOperation { return _operation; }
- (void)setCompositingOperation:(NSCompositingOperation)op {
    _operation = op;
    CGContextSetBlendMode(_cg, (CGBlendMode)bn_blend_mode_for_operation(op));
}
- (NSImageInterpolation)imageInterpolation { return _interpolation; }
- (void)setImageInterpolation:(NSImageInterpolation)i {
    _interpolation = i;
    CGContextSetInterpolationQuality(_cg, (CGInterpolationQuality)i);
}
- (BOOL)shouldAntialias { return !_noAntialias; }
- (void)setShouldAntialias:(BOOL)b {
    _noAntialias = !b;
    CGContextSetShouldAntialias(_cg, b);
}
- (NSPoint)patternPhase { return _patternPhase; }
- (void)setPatternPhase:(NSPoint)p {
    _patternPhase = p; /* patterns are not drawn yet; kept for reading back */
}
- (NSInteger)colorRenderingIntent { return _renderingIntent; }
- (void)setColorRenderingIntent:(NSInteger)i { _renderingIntent = i; }
- (NSDictionary *)attributes { return @{}; }
- (void *)graphicsPort { return _cg; }
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)port flipped:(BOOL)flipped {
    NSGraphicsContext *c = [NSGraphicsContext new];
    c->_cg = (CGContextRef)CFRetain(port);
    c->_flipped = flipped;
    return c;
}
- (void)dealloc {
    if (_cg) CFRelease(_cg);
}
+ (NSGraphicsContext *)currentContext {
    pthread_once(&current_once, make_current_key);
    return (__bridge NSGraphicsContext *)pthread_getspecific(current_key);
}
+ (void)setCurrentContext:(NSGraphicsContext *)context {
    pthread_once(&current_once, make_current_key);
    NSGraphicsContext *old = (__bridge_transfer NSGraphicsContext *)pthread_getspecific(current_key);
    (void)old;
    pthread_setspecific(current_key, context ? (__bridge_retained void *)context : NULL);
}
+ (BOOL)currentContextDrawingToScreen { return YES; }
/* As documented, the class methods also save and restore which context is
 * current (per thread), so drawing that saves, switches to another context
 * (an image, a bitmap) and restores returns to where it started. */
static NSMutableArray *context_stack(void) {
    NSMutableDictionary *d = [NSThread currentThread].threadDictionary;
    NSMutableArray *a = d[@"BNGraphicsContextStack"];
    if (!a) d[@"BNGraphicsContextStack"] = a = [NSMutableArray array];
    return a;
}
+ (void)saveGraphicsState {
    NSGraphicsContext *c = [self currentContext];
    [context_stack() addObject:c ?: (id)[NSNull null]];
    [c saveGraphicsState];
}
+ (void)restoreGraphicsState {
    NSMutableArray *a = context_stack();
    if (!a.count) {
        [[self currentContext] restoreGraphicsState];
        return;
    }
    id saved = a.lastObject;
    [a removeLastObject];
    NSGraphicsContext *c = saved == (id)[NSNull null] ? nil : saved;
    [self setCurrentContext:c];
    [c restoreGraphicsState];
}
- (void)saveGraphicsState { CGContextSaveGState(_cg); }
- (void)restoreGraphicsState { CGContextRestoreGState(_cg); }
- (void)flushGraphics {}
- (CGContextRef)CGContext { return _cg; }
- (BOOL)isFlipped { return _flipped; }
- (BOOL)isDrawingToScreen { return YES; }
@end

static CGContextRef current_cg(void) { return [NSGraphicsContext currentContext].CGContext; }

/* ---- colours and rects ---- */

@implementation NSColor (BittenDrawing)
- (void)set {
    [self setFill];
    [self setStroke];
}
- (void)setFill {
    CGContextRef c = current_cg();
    if (c) CGContextSetRGBFillColor(c, self.redComponent, self.greenComponent, self.blueComponent, self.alphaComponent);
}
- (void)setStroke {
    CGContextRef c = current_cg();
    if (c) CGContextSetRGBStrokeColor(c, self.redComponent, self.greenComponent, self.blueComponent, self.alphaComponent);
}
/* Made once per colour and kept with it (colours are immutable). */
- (CGColorRef)CGColor {
    static const char key;
    id cached = objc_getAssociatedObject(self, &key);
    if (cached) return (__bridge CGColorRef)cached;
    CGColorRef c = CGColorCreateSRGB(self.redComponent, self.greenComponent, self.blueComponent, self.alphaComponent);
    objc_setAssociatedObject(self, &key, (__bridge_transfer id)c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return c;
}
+ (NSColor *)colorWithCGColor:(CGColorRef)cg {
    const CGFloat *c = CGColorGetComponents(cg);
    size_t n = CGColorGetNumberOfComponents(cg);
    if (n >= 4) return [NSColor colorWithSRGBRed:c[0] green:c[1] blue:c[2] alpha:c[3]];
    if (n == 2) return [NSColor colorWithWhite:c[0] alpha:c[1]];
    return [NSColor blackColor];
}
@end

void NSRectFill(NSRect r) {
    CGContextRef c = current_cg();
    if (c) CGContextFillRect(c, r);
}
/* AppKit's compositing operations as CoreGraphics blend modes. */
int bn_blend_mode_for_operation(NSCompositingOperation op) {
    static const int map[] = {
        16, 17, 0,  18, 19, 20, 21, 22, 23, 24, 25, 26, 0,  27, /* clear .. plusLighter */
        1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, /* multiply .. luminosity */
    };
    return (NSUInteger)op < sizeof map / sizeof *map ? map[op] : 0;
}
void NSRectFillUsingOperation(NSRect r, NSCompositingOperation op) {
    CGContextRef c = current_cg();
    if (!c) return;
    CGContextSaveGState(c);
    CGContextSetBlendMode(c, (CGBlendMode)bn_blend_mode_for_operation(op));
    CGContextFillRect(c, r);
    CGContextRestoreGState(c);
}
void NSFrameRectWithWidth(NSRect r, CGFloat w) {
    CGContextRef c = current_cg();
    if (!c) return;
    /* Inside the rect, like AppKit: four filled strips. */
    CGContextFillRect(c, CGRectMake(r.origin.x, r.origin.y, r.size.width, w));
    CGContextFillRect(c, CGRectMake(r.origin.x, CGRectGetMaxY(r) - w, r.size.width, w));
    CGContextFillRect(c, CGRectMake(r.origin.x, r.origin.y, w, r.size.height));
    CGContextFillRect(c, CGRectMake(CGRectGetMaxX(r) - w, r.origin.y, w, r.size.height));
}
void NSFrameRect(NSRect r) { NSFrameRectWithWidth(r, 1); }
void NSEraseRect(NSRect r) {
    CGContextRef c = current_cg();
    if (!c) return;
    CGContextSaveGState(c);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, r);
    CGContextRestoreGState(c);
}

/* ---- NSBezierPath ---- */

@implementation NSBezierPath {
    CGMutablePathRef _path;
    CGFloat _lineWidth;
    NSLineCapStyle _cap;
    NSLineJoinStyle _join;
    NSUInteger _winding; /* NSWindingRule: 0 non-zero, 1 even-odd */
}
+ (NSBezierPath *)bezierPath { return [self new]; }
- (instancetype)init {
    if ((self = [super init])) {
        _path = CGPathCreateMutable();
        _lineWidth = 1;
    }
    return self;
}
- (void)dealloc { CGPathRelease(_path); }
- (id)copyWithZone:(NSZone *)zone {
    NSBezierPath *p = [NSBezierPath new];
    CGPathRelease(p->_path);
    p->_path = CGPathCreateMutableCopy(_path);
    p->_lineWidth = _lineWidth;
    p->_cap = _cap;
    p->_join = _join;
    return p;
}
+ (NSBezierPath *)bezierPathWithRect:(NSRect)r {
    NSBezierPath *p = [self new];
    [p appendBezierPathWithRect:r];
    return p;
}
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)r {
    NSBezierPath *p = [self new];
    [p appendBezierPathWithOvalInRect:r];
    return p;
}
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)xr yRadius:(CGFloat)yr {
    NSBezierPath *p = [self new];
    [p appendBezierPathWithRoundedRect:r xRadius:xr yRadius:yr];
    return p;
}
+ (void)fillRect:(NSRect)r { NSRectFill(r); }
+ (void)strokeRect:(NSRect)r { [[self bezierPathWithRect:r] stroke]; }
+ (void)strokeLineFromPoint:(NSPoint)a toPoint:(NSPoint)b {
    NSBezierPath *p = [self new];
    [p moveToPoint:a];
    [p lineToPoint:b];
    [p stroke];
}
- (void)moveToPoint:(NSPoint)p { CGPathMoveToPoint(_path, NULL, p.x, p.y); }
- (void)lineToPoint:(NSPoint)p { CGPathAddLineToPoint(_path, NULL, p.x, p.y); }
- (void)curveToPoint:(NSPoint)e controlPoint1:(NSPoint)c1 controlPoint2:(NSPoint)c2 {
    CGPathAddCurveToPoint(_path, NULL, c1.x, c1.y, c2.x, c2.y, e.x, e.y);
}
- (void)closePath { CGPathCloseSubpath(_path); }
- (void)removeAllPoints {
    CGPathRelease(_path);
    _path = CGPathCreateMutable();
}
- (void)appendBezierPath:(NSBezierPath *)other { CGPathAddPath(_path, NULL, other->_path); }
- (void)appendBezierPathWithRect:(NSRect)r { CGPathAddRect(_path, NULL, r); }
- (void)appendBezierPathWithOvalInRect:(NSRect)r { CGPathAddEllipseInRect(_path, NULL, r); }
- (void)appendBezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)xr yRadius:(CGFloat)yr {
    xr = fmin(xr, r.size.width / 2);
    yr = fmin(yr, r.size.height / 2);
    if (xr <= 0 || yr <= 0) {
        CGPathAddRect(_path, NULL, r);
        return;
    }
    CGPathAddRoundedRect(_path, NULL, r, xr, yr);
}
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)radius startAngle:(CGFloat)a0
                                 endAngle:(CGFloat)a1 clockwise:(BOOL)cw {
    CGPathAddArc(_path, NULL, c.x, c.y, radius, a0 * M_PI / 180, a1 * M_PI / 180, cw);
}
/* A circular arc tangent to the lines from the current point to p1 and from
 * p1 to p2 (CGPathAddArcToPoint). */
- (void)appendBezierPathWithArcFromPoint:(NSPoint)p1 toPoint:(NSPoint)p2 radius:(CGFloat)radius {
    CGPathAddArcToPoint(_path, NULL, p1.x, p1.y, p2.x, p2.y, radius);
}
- (NSUInteger)windingRule { return _winding; }
- (void)setWindingRule:(NSUInteger)rule { _winding = rule; }
- (void)_bn_apply:(CGContextRef)c {
    CGContextBeginPath(c);
    CGContextAddPath(c, _path);
}
- (void)fill {
    CGContextRef c = current_cg();
    if (!c) return;
    [self _bn_apply:c];
    if (_winding == 1) CGContextEOFillPath(c);
    else CGContextFillPath(c);
}
- (void)stroke {
    CGContextRef c = current_cg();
    if (!c) return;
    CGContextSaveGState(c);
    CGContextSetLineWidth(c, _lineWidth);
    CGContextSetLineCap(c, (CGLineCap)_cap);
    CGContextSetLineJoin(c, (CGLineJoin)_join);
    [self _bn_apply:c];
    CGContextStrokePath(c);
    CGContextRestoreGState(c);
}
- (void)addClip {
    CGContextRef c = current_cg();
    if (!c) return;
    [self _bn_apply:c];
    if (_winding == 1) CGContextEOClip(c);
    else CGContextClip(c);
}
- (void)setClip { [self addClip]; }
- (CGFloat)lineWidth { return _lineWidth; }
- (void)setLineWidth:(CGFloat)w { _lineWidth = w; }
- (NSLineCapStyle)lineCapStyle { return _cap; }
- (void)setLineCapStyle:(NSLineCapStyle)c { _cap = c; }
- (NSLineJoinStyle)lineJoinStyle { return _join; }
- (void)setLineJoinStyle:(NSLineJoinStyle)j { _join = j; }
- (BOOL)isEmpty { return CGPathIsEmpty(_path); }
- (BOOL)containsPoint:(NSPoint)p { return CGPathContainsPoint(_path, NULL, p, _winding == 1); }   /* 1: NSWindingRuleEvenOdd */
- (NSRect)bounds { return CGPathGetBoundingBox(_path); }
- (CGPathRef)CGPath { return _path; }
@end

/* ---- views draw into the current context ---- */

/* What a view's backing layer adds to the view's drawing: its background,
 * rounded corners (which also clip the content when masksToBounds), its
 * contents image (a CAMetalLayer's presented frame, say), its border and
 * any sublayers the program added itself. The view's own
 * drawing still comes from drawRect:. */
@interface BNBackingLayer : NSObject
@property (getter=isHidden) BOOL hidden;
@property float opacity;
@property CGColorRef backgroundColor, borderColor;
@property CGFloat cornerRadius, borderWidth;
@property BOOL masksToBounds;
@property (copy) NSArray *sublayers;
@property (weak) id delegate;
- (CGAffineTransform)_bn_toSuper;
- (void)_bn_render:(CGContextRef)ctx;
- (void)_bn_drawContents:(CGContextRef)ctx inRect:(CGRect)b flipped:(BOOL)flipped;
@end

static CGPathRef bn_rounded(CGRect r, CGFloat radius) CF_RETURNS_RETAINED {
    radius = fmax(0, fmin(radius, fmin(r.size.width, r.size.height) / 2));
    return radius > 0 ? CGPathCreateWithRoundedRect(r, radius, radius, NULL) : CGPathCreateWithRect(r, NULL);
}
/* Fills the background and saves the state, clipped to the corners when the
 * layer masks; bn_layer_border's caller restores it. */
static void bn_layer_background(BNBackingLayer *layer, CGContextRef c, CGRect b) {
    CGColorRef bg = layer.backgroundColor;
    if (bg && CGColorGetAlpha(bg) > 0) {
        CGPathRef p = bn_rounded(b, layer.cornerRadius);
        CGContextSaveGState(c);
        CGContextSetFillColorWithColor(c, bg);
        CGContextAddPath(c, p);
        CGContextFillPath(c);
        CGContextRestoreGState(c);
        CGPathRelease(p);
    }
    CGContextSaveGState(c);
    if (layer.masksToBounds && layer.cornerRadius > 0) {
        CGPathRef p = bn_rounded(b, layer.cornerRadius);
        CGContextAddPath(c, p);
        CGContextClip(c);
        CGPathRelease(p);
    }
}
static void bn_layer_sublayers(BNBackingLayer *layer, CGContextRef c, BOOL flipped) {
    /* As in AppKit, a flipped view's backing layer has flipped geometry,
     * so text and contents in its sublayers come out upright. */
    if (layer.sublayers.count && [(id)layer respondsToSelector:@selector(setGeometryFlipped:)] &&
        [[(id)layer valueForKey:@"geometryFlipped"] boolValue] != flipped)
        [(id)layer setValue:@(flipped) forKey:@"geometryFlipped"];
    for (BNBackingLayer *sub in layer.sublayers) {
        if ([sub.delegate isKindOfClass:[NSView class]]) continue;
        CGContextSaveGState(c);
        CGContextConcatCTM(c, [sub _bn_toSuper]);
        [sub _bn_render:c];
        CGContextRestoreGState(c);
    }
}
static void bn_layer_border(BNBackingLayer *layer, CGContextRef c, CGRect b) {
    CGFloat w = layer.borderWidth;
    CGColorRef color = layer.borderColor;
    if (w <= 0 || !color) return;
    CGPathRef p = bn_rounded(CGRectInset(b, w / 2, w / 2), layer.cornerRadius - w / 2);
    CGContextSaveGState(c);
    CGContextSetStrokeColorWithColor(c, color);
    CGContextSetLineWidth(c, w);
    CGContextAddPath(c, p);
    CGContextStrokePath(c);
    CGContextRestoreGState(c);
    CGPathRelease(p);
}

@implementation NSView (BittenDrawing)
/* SwiftUI's hosting views draw their AppKit subviews themselves, between
 * the SwiftUI content below and above them. */
- (BOOL)_bn_drawsOwnSubviews { return NO; }
/* Draws this view and its subviews. On entry the context's coordinates
 * are the superview's bounds space; `parentFlipped` says whether that
 * space runs downward. */
/* BITTEN_DRAW_PROFILE: time spent painting each class (own drawing, not
 * its subviews), summed and printed every 20 window displays. */
static NSMutableDictionary<NSString *, NSNumber *> *draw_profile;
static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}
static void profile_add(id view, double ms) {
    if (!draw_profile) draw_profile = [NSMutableDictionary dictionary];
    NSString *k = NSStringFromClass([view class]);
    draw_profile[k] = @(draw_profile[k].doubleValue + ms);
}
- (void)_bn_drawIn:(CGContextRef)c parentFlipped:(BOOL)parentFlipped {
    if (self.isHidden) return;
    static int profiling = -1;
    if (profiling < 0) profiling = getenv("BITTEN_DRAW_PROFILE") != NULL;
    double t0 = profiling ? now_ms() : 0, kids = 0;
    NSRect f = self.frame, b = self.bounds;
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, f.origin.x, f.origin.y);
    /* Views draw outside their bounds unless they clip (clipsToBounds is
     * NO by default for programs built with the macOS 14 SDK or later);
     * clip views and layers that mask to bounds always clip. */
    if (self.clipsToBounds || ((BNBackingLayer *)self.layer).masksToBounds || [self isKindOfClass:[NSClipView class]] ||
        self.superview == nil)
        CGContextClipToRect(c, CGRectMake(0, 0, f.size.width, f.size.height));
    BOOL flipped = self.isFlipped;
    if (flipped != parentFlipped) {
        CGContextTranslateCTM(c, 0, f.size.height);
        CGContextScaleCTM(c, 1, -1);
    }
    CGContextTranslateCTM(c, -b.origin.x, -b.origin.y);
    BNBackingLayer *layer = (BNBackingLayer *)self.layer;
    /* A view that keeps its looks in its layer updates the layer, when it
     * needs display, instead of drawing (AppKit's wantsUpdateLayer); before
     * the layer is painted, in the view's appearance. */
    BOOL updatesLayer = layer && [self wantsUpdateLayer];
    if (updatesLayer && self.needsDisplay) {
        NSAppearance *before = [NSAppearance _bn_swapDrawingAppearance:self.effectiveAppearance];
        [self updateLayer];
        [NSAppearance _bn_swapDrawingAppearance:before];
    }
    /* The view's alpha and its layer's opacity both fade it and its subviews. */
    CGFloat alpha = self.alphaValue * (layer ? layer.opacity : 1);
    if (alpha <= 0 || layer.isHidden) {
        CGContextRestoreGState(c);
        return;
    }
    BOOL group = alpha < 1;
    if (group) {
        CGContextSetAlpha(c, alpha);
        CGContextBeginTransparencyLayer(c, NULL);
    }
    if (layer) {
        bn_layer_background(layer, c, b);
        /* In the view's upright space: the layer's top is the view's top. */
        CGContextSaveGState(c);
        if (flipped) {
            CGContextTranslateCTM(c, 0, CGRectGetMinY(b) + CGRectGetMaxY(b));
            CGContextScaleCTM(c, 1, -1);
        }
        [layer _bn_drawContents:c inRect:b flipped:NO];
        CGContextRestoreGState(c);
    }
    NSGraphicsContext *previous = [NSGraphicsContext currentContext];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:c flipped:flipped]];
    /* dynamic colours resolve for this view's appearance */
    NSAppearance *drawingBefore = [NSAppearance _bn_swapDrawingAppearance:self.effectiveAppearance];
    size_t depth = bitten_cg_gstate_depth(c);
    if (!updatesLayer) [self drawRect:b];
    if (bitten_cg_gstate_depth(c) != depth && getenv("BITTEN_DEBUG"))
        fprintf(stderr, "bitten: %s drawRect: left %ld graphics states unbalanced\n", object_getClassName(self),
                (long)bitten_cg_gstate_depth(c) - (long)depth);
    bitten_cg_restore_to_depth(c, depth); /* states the drawing saved and left */
    [NSGraphicsContext setCurrentContext:previous];
    [NSAppearance _bn_swapDrawingAppearance:drawingBefore];
    if (layer) {
        depth = bitten_cg_gstate_depth(c);
        bn_layer_sublayers(layer, c, flipped);
        bitten_cg_restore_to_depth(c, depth);
    }
    if (![self _bn_drawsOwnSubviews]) {
        double k0 = profiling ? now_ms() : 0;
        for (NSView *v in self.subviews) [v _bn_drawIn:c parentFlipped:flipped];
        if (profiling) kids = now_ms() - k0;
    }
    if (layer) {
        CGContextRestoreGState(c); /* the corner clip */
        bn_layer_border(layer, c, b);
    }
    if (group) CGContextEndTransparencyLayer(c);
    CGContextRestoreGState(c);
    self.needsDisplay = NO;
    if (profiling) profile_add(self, now_ms() - t0 - kids);
}
@end

/* ---- windows: a bitmap per window, shown by the display ---- */

@interface NSApplication (BittenEventsPrivate)
+ (void)_bn_listenToDisplay;
@end

/* BITTEN_VIEW_TREE=1 prints each window's view hierarchy as it is drawn. */
static void bn_dump_tree(NSView *v, int depth) {
    fprintf(stderr, "%*s%s %s%s%s layer=%s%s constraints=%lu\n", depth * 2, "", object_getClassName(v),
            NSStringFromRect(v.frame).UTF8String, v.isHidden ? " hidden" : "", v.isFlipped ? " flipped" : "",
            v.layer ? object_getClassName(v.layer) : "-",
            v.translatesAutoresizingMaskIntoConstraints ? "" : " AL", (unsigned long)v.constraints.count);
    if (v.layer) {
        CALayer *l = (CALayer *)v.layer;
        CATransform3D t = l.transform;
        fprintf(stderr, "%*s  layer pos=(%g,%g) bounds=%s anchor=(%g,%g) scale=(%g,%g) tx=(%g,%g) sublayers=%lu opacity=%g%s\n",
                depth * 2, "", l.position.x, l.position.y, NSStringFromRect(l.bounds).UTF8String, l.anchorPoint.x,
                l.anchorPoint.y, t.m11, t.m22, t.m41, t.m42, (unsigned long)l.sublayers.count, l.opacity,
                l.isHidden ? " hidden" : "");
        if (getenv("BITTEN_VIEW_TREE")[0] == '2')
            fprintf(stderr, "%*s  bg-alpha %g corner %g masks %d border %g shadow %g filters %lu compositing %s\n", depth * 2, "",
                    l.backgroundColor ? CGColorGetAlpha(l.backgroundColor) : 0, l.cornerRadius, l.masksToBounds, l.borderWidth,
                    l.shadowOpacity, (unsigned long)[l.filters count], [[l.compositingFilter description] UTF8String] ?: "-");
        id contents = l.contents;
        if (contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID())
            fprintf(stderr, "%*s  contents %zux%zu gravity %s scale %g alpha-info %u%s\n", depth * 2, "",
                    CGImageGetWidth((__bridge CGImageRef)contents), CGImageGetHeight((__bridge CGImageRef)contents),
                    [l.contentsGravity UTF8String] ?: "-", l.contentsScale,
                    (unsigned)CGImageGetAlphaInfo((__bridge CGImageRef)contents), l.isOpaque ? " opaque" : "");
        for (CALayer *sub in l.sublayers) {
            id d = [sub valueForKey:@"delegate"];
            fprintf(stderr, "%*s  sublayer %s frame=%s delegate=%s sublayers=%lu\n", depth * 2, "", object_getClassName(sub),
                    NSStringFromRect(sub.frame).UTF8String, d ? object_getClassName(d) : "-", (unsigned long)sub.sublayers.count);
        }
    }
    if ([v isKindOfClass:[NSTextField class]]) {
        NSTextField *t = (NSTextField *)v;
        fprintf(stderr, "%*s  text '%s' bezeled=%d bordered=%d background=%d editable=%d font=%s %g\n", depth * 2, "",
                t.stringValue.UTF8String ?: "", t.isBezeled, t.isBordered, t.drawsBackground, t.isEditable,
                t.font.fontName.UTF8String ?: "?", t.font.pointSize);
    }
    for (NSView *s in v.subviews) bn_dump_tree(s, depth + 1);
}

/* A view whose layer shows an image (a Metal view's presented frame) and
 * is told to redisplay: compare the image with the one it showed before.
 * Returns NO when the whole window should redraw (the first frame, a size
 * change, no image); otherwise *changed is the area whose pixels differ
 * (empty: none), in the window's content coordinates. */
static const char kShownContentsKey;
@implementation NSView (BittenContentsDiff)
- (BOOL)_bn_contentsChange:(NSRect *)changed {
    CALayer *layer = self.layer;
    id contents = layer.contents;
    if (!self.window || !contents || CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) return NO;
    id previous = objc_getAssociatedObject(self, &kShownContentsKey);
    objc_setAssociatedObject(self, &kShownContentsKey, contents, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!previous || previous == contents) return previous == contents && (*changed = NSZeroRect, YES);
    CGImageRef a = (__bridge CGImageRef)previous, b = (__bridge CGImageRef)contents;
    size_t w = CGImageGetWidth(b), h = CGImageGetHeight(b), bpr = CGImageGetBytesPerRow(b);
    if (CGImageGetWidth(a) != w || CGImageGetHeight(a) != h || CGImageGetBytesPerRow(a) != bpr ||
        CGImageGetBitsPerPixel(a) != 32 || CGImageGetBitsPerPixel(b) != 32 || !w || !h)
        return NO;
    CFDataRef da = CGDataProviderCopyData(CGImageGetDataProvider(a)), db = CGDataProviderCopyData(CGImageGetDataProvider(b));
    BOOL ok = da && db && (size_t)CFDataGetLength(da) >= bpr * h && (size_t)CFDataGetLength(db) >= bpr * h;
    long x0 = (long)w, x1 = -1, y0 = (long)h, y1 = -1;
    if (ok) {
        const uint8_t *pa = CFDataGetBytePtr(da), *pb = CFDataGetBytePtr(db);
        for (size_t y = 0; y < h; y++) {
            const uint32_t *ra = (const uint32_t *)(pa + y * bpr), *rb = (const uint32_t *)(pb + y * bpr);
            if (!memcmp(ra, rb, w * 4)) continue;
            if ((long)y < y0) y0 = (long)y;
            y1 = (long)y;
            for (size_t x = 0; x < w; x++)
                if (ra[x] != rb[x]) {
                    if ((long)x < x0) x0 = (long)x;
                    if ((long)x > x1) x1 = (long)x;
                }
        }
    }
    if (da) CFRelease(da);
    if (db) CFRelease(db);
    if (!ok) return NO;
    if (y1 < 0) {
        *changed = NSZeroRect;
        return YES;
    }
    /* image rows run down from the top of the layer's bounds (resized to fill them) */
    if (![layer.contentsGravity isEqualToString:@"resize"]) return NO; /* kCAGravityResize (QuartzCore is not linked) */
    NSRect bounds = self.bounds;
    CGFloat sx = bounds.size.width / w, sy = bounds.size.height / h;
    NSRect r = NSMakeRect(bounds.origin.x + x0 * sx, 0, (x1 + 1 - x0) * sx, (y1 + 1 - y0) * sy);
    r.origin.y = self.isFlipped ? bounds.origin.y + y0 * sy : bounds.origin.y + bounds.size.height - (y1 + 1) * sy;
    *changed = [self convertRect:r toView:nil];
    return YES;
}
@end

/* A window's backing bitmap, released with the window (or when replaced). */
@interface BNBacking : NSObject {
@public
    CGContextRef _ctx;
}
@end
@implementation BNBacking
- (void *)pointerValue { return _ctx; }
- (void)dealloc {
    if (_ctx) CGContextRelease(_ctx);
}
@end

@implementation NSWindow (BittenDisplay)
static const char kBackingKey;
static const char kScheduledKey;

- (CGContextRef)_bn_backing:(NSSize)size {
    NSValue *v = objc_getAssociatedObject(self, &kBackingKey);
    CGContextRef c = v ? (CGContextRef)v.pointerValue : NULL;
    size_t w = (size_t)ceil(size.width), h = (size_t)ceil(size.height);
    if (c && CGBitmapContextGetWidth(c) == w && CGBitmapContextGetHeight(c) == h) return c;
    if (!w || !h) {
        objc_setAssociatedObject(self, &kBackingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return NULL;
    }
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    c = CGBitmapContextCreate(NULL, w, h, 8, w * 4, rgb, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(rgb);
    BNBacking *backing = [BNBacking new];
    backing->_ctx = c;
    objc_setAssociatedObject(self, &kBackingKey, backing, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   /* the old one goes */
    return c;
}

/* ---- partial redraws ----
 * A window redraws everything unless all it has been asked since its last
 * frame is to repaint rects (a layer's new contents differing from the old
 * in a small area: a terminal's cursor): then the frame is drawn clipped
 * to their union over the previous one, which the backing still holds. */
static const char kDirtyKey; /* NSValue rect, content coordinates; absent: nothing partial pending */
static const char kFullKey;  /* @YES: the next frame repaints everything */
- (void)_bn_invalidateRect:(NSRect)r {
    if (![objc_getAssociatedObject(self, &kFullKey) boolValue]) {
        NSValue *v = objc_getAssociatedObject(self, &kDirtyKey);
        NSRect u = v ? NSUnionRect(v.rectValue, r) : r;
        objc_setAssociatedObject(self, &kDirtyKey, [NSValue valueWithRect:u], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self _bn_queueDisplay];
}

/* Draws the content view hierarchy and shows the result. */
- (void)display {
    objc_setAssociatedObject(self, &kFullKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _bn_displayPending];
}
static const char kDrawingKey;
- (void)_bn_displayPending {
    /* A display asked for while this window draws (a view changing the
     * window as it draws) comes after this frame, not inside it. */
    if ([objc_getAssociatedObject(self, &kDrawingKey) boolValue]) {
        [self _bn_queueDisplay];
        return;
    }
    objc_setAssociatedObject(self, &kDrawingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _bn_drawPending];
    objc_setAssociatedObject(self, &kDrawingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)_bn_drawPending {
    BOOL full = [objc_getAssociatedObject(self, &kFullKey) boolValue];
    NSValue *dirtyValue = objc_getAssociatedObject(self, &kDirtyKey);
    objc_setAssociatedObject(self, &kFullKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kDirtyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!full && !dirtyValue) return;
    if (getenv("BITTEN_DISPLAY_DEBUG"))
        fprintf(stderr, "bitten: display %s visible %d alpha %g\n", self.title.UTF8String ?: "", self.isVisible,
                self.alphaValue);
    if (!self.isVisible) return;
    /* fully transparent: nothing to show (windows kept ordered in but
     * faded out, as panels shown on demand often are) */
    if (self.alphaValue <= 0) {
        [self _bn_closeDisplay];
        return;
    }
    [self.contentView layoutSubtreeIfNeeded];
    NSRect content = [self contentRectForFrameRect:self.frame];
    NSValue *before = objc_getAssociatedObject(self, &kBackingKey);
    CGContextRef c = [self _bn_backing:content.size];
    if (!c) return;
    if (!before || before.pointerValue != c) full = YES; /* a new backing has no previous frame */
    /* Drawing that restores more graphics states than it saved pops this
     * frame's own state and leaves a view's flip behind in the reused
     * context; start such a frame from a fresh one (it repaints everything). */
    if (!CGAffineTransformIsIdentity(CGContextGetCTM(c))) {
        if (getenv("BITTEN_DEBUG")) fprintf(stderr, "bitten: window %ld: unbalanced graphics state; context reset\n", (long)self.windowNumber);
        objc_setAssociatedObject(self, &kBackingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   /* released */
        c = [self _bn_backing:content.size];
        if (!c) return;
        full = YES;
    }
    CGContextSaveGState(c);
    NSRect dirty = NSZeroRect;
    if (!full) {
        dirty = NSIntersectionRect(NSInsetRect(dirtyValue.rectValue, -2, -2),
                                          NSMakeRect(0, 0, content.size.width, content.size.height));
        if (NSIsEmptyRect(dirty)) {
            CGContextRestoreGState(c);
            return;
        }
        if (getenv("BITTEN_DISPLAY_DEBUG"))
            fprintf(stderr, "bitten: partial display %s %s\n", self.title.UTF8String ?: "", NSStringFromRect(dirty).UTF8String);
        CGContextClipToRect(c, dirty);
    }
    NSColor *bg = self.backgroundColor;
    NSAppearance *drawingBefore = [NSAppearance _bn_swapDrawingAppearance:self.effectiveAppearance];
    CGColorRef bgColor = CGColorRetain(bg.CGColor);
    [NSAppearance _bn_swapDrawingAppearance:drawingBefore];
    /* The background replaces what the frame repaints: what is not opaque
     * starts transparent (cleared in the bitmap, rather than blended over
     * the last frame), then the colour goes on if it shows at all. */
    if (CGColorGetAlpha(bgColor) < 1) {
        uint8_t *data = CGBitmapContextGetData(c);
        size_t bw = CGBitmapContextGetWidth(c), bh = CGBitmapContextGetHeight(c), bpr = CGBitmapContextGetBytesPerRow(c);
        NSRect r = full ? NSMakeRect(0, 0, bw, bh) : NSIntegralRect(dirty);
        size_t x0 = (size_t)MAX(0, r.origin.x), x1 = (size_t)MIN((CGFloat)bw, NSMaxX(r));
        size_t y0 = (size_t)MAX(0, r.origin.y), y1 = (size_t)MIN((CGFloat)bh, NSMaxY(r));
        if (data && x1 > x0)
            for (size_t y = y0; y < y1; y++) memset(data + (bh - 1 - y) * bpr + x0 * 4, 0, (x1 - x0) * 4);
    }
    if (CGColorGetAlpha(bgColor) > 0) {
        CGContextSetFillColorWithColor(c, bgColor);
        CGContextFillRect(c, CGRectMake(0, 0, content.size.width, content.size.height));
    }
    CGColorRelease(bgColor);
    if (getenv("BITTEN_VIEW_TREE")) bn_dump_tree(self.contentView, 0);
    double frame0 = now_ms();
    [self.contentView _bn_drawIn:c parentFlipped:NO];
    CGContextRestoreGState(c);
    if (draw_profile) {
        static int frames;
        static double total;
        total += now_ms() - frame0;
        if (++frames % 20 == 0) {
            fprintf(stderr, "bitten: draw profile, %d frames, %.0f ms each:\n", frames, total / frames);
            NSArray *keys = [draw_profile keysSortedByValueUsingSelector:@selector(compare:)];
            for (NSString *k in keys.reverseObjectEnumerator.allObjects)
                if (draw_profile[k].doubleValue / frames > 1)
                    fprintf(stderr, "bitten:   %8.1f ms  %s\n", draw_profile[k].doubleValue / frames, k.UTF8String);
        }
    }
    [self _bn_sendStyle];
    if (getenv("BITTEN_DISPLAY_DEBUG")) {
        const uint8_t *px = CGBitmapContextGetData(c);
        size_t w = CGBitmapContextGetWidth(c), h = CGBitmapContextGetHeight(c), bpr = CGBitmapContextGetBytesPerRow(c), opaque = 0;
        for (size_t y = 0; y < h; y++)
            for (size_t x = 0; x < w; x++) opaque += px[y * bpr + x * 4 + 3] != 0;
        fprintf(stderr, "bitten: presented %s %zux%zu, %zu pixels not transparent\n", self.title.UTF8String ?: "", w, h, opaque);
    }
    /* The page's coordinates run down from the top of the main screen. */
    NSRect screen = [NSScreen mainScreen].frame;
    double top = CGRectGetMaxY(screen) - CGRectGetMaxY(self.frame);
    size_t bw = CGBitmapContextGetWidth(c), bh = CGBitmapContextGetHeight(c);
    uint32_t info = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
    if (full) {
        bitten_display_present((uint32_t)self.windowNumber, CGBitmapContextGetData(c), bw, bh,
                               CGBitmapContextGetBytesPerRow(c), info, self.frame.origin.x, top, self.title.UTF8String ?: "");
    } else {
        /* only the repainted rect goes to the display (its rows run down from the top) */
        size_t x0 = (size_t)floor(NSMinX(dirty)), x1 = (size_t)ceil(NSMaxX(dirty));
        size_t y0 = (size_t)floor(bh - NSMaxY(dirty)), y1 = (size_t)ceil(bh - NSMinY(dirty));
        bitten_display_present_rect((uint32_t)self.windowNumber, CGBitmapContextGetData(c), bw, bh,
                                    CGBitmapContextGetBytesPerRow(c), info, self.frame.origin.x, top,
                                    self.title.UTF8String ?: "", x0, y0, x1 - x0, y1 - y0);
    }
    [NSApplication _bn_listenToDisplay];
}

/* How the display should show this window: without a title bar and frame
 * when it has none, with the bar over the content when the content runs
 * under it, see-through when it is not opaque, and stacked by its
 * level (floating panels above normal windows). Sent when it changes. */
static const char kStyleKey;
- (void)_bn_sendStyle {
    uint32_t flags = 0;
    if (!(self.styleMask & NSWindowStyleMaskTitled)) flags |= 1;
    else if (self.styleMask & NSWindowStyleMaskFullSizeContentView) flags |= 4;
    if (self.titleVisibility == NSWindowTitleHidden) flags |= 8;
    CGFloat bgAlpha = self.backgroundColor ? self.backgroundColor.alphaComponent : 1;
    if (!self.isOpaque || bgAlpha < 1) flags |= 2;
    /* which of the title bar's controls the window has */
    BOOL titled = (self.styleMask & NSWindowStyleMaskTitled) != 0;
    if (titled && (self.styleMask & NSWindowStyleMaskResizable)) flags |= 16 | 64;
    if (titled && (self.styleMask & NSWindowStyleMaskMiniaturizable)) flags |= 32;
    if (self.isMiniaturized) flags |= 128;
    int32_t level = (int32_t)self.level;
    uint64_t packed = (uint64_t)flags << 32 | (uint32_t)level;
    NSNumber *sent = objc_getAssociatedObject(self, &kStyleKey);
    if (sent && sent.unsignedLongLongValue == packed) return;
    objc_setAssociatedObject(self, &kStyleKey, @(packed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    bitten_display_set_style((uint32_t)self.windowNumber, flags, level);
}
/* Raises the window within its level on the display (without focus). */
- (void)_bn_orderFrontOnDisplay { bitten_display_order_front((uint32_t)self.windowNumber); }

/* Redraws on the next turn of the main queue, once per batch of changes. */
- (void)_bn_scheduleDisplay {
    objc_setAssociatedObject(self, &kFullKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _bn_queueDisplay];
}
- (void)_bn_queueDisplay {
    if ([objc_getAssociatedObject(self, &kScheduledKey) boolValue]) return;
    objc_setAssociatedObject(self, &kScheduledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(self, &kScheduledKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self _bn_displayPending];
    });
}
- (void)displayIfNeeded { [self display]; }
/* The window's backing bitmap (for tests and screenshots). */
- (CGContextRef)_bn_backingContext {
    NSValue *v = objc_getAssociatedObject(self, &kBackingKey);
    return v ? (CGContextRef)v.pointerValue : NULL;
}
- (void)_bn_closeDisplay {
    bitten_display_close((uint32_t)self.windowNumber);
    /* the display forgets the window: its style is sent again with it */
    objc_setAssociatedObject(self, &kStyleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* Intersects the current clip with r. */
void NSRectClip(NSRect r) {
    CGContextRef c = current_cg();
    if (c) CGContextClipToRect(c, r);
}
void NSRectClipList(const NSRect *rects, NSInteger count) {
    CGContextRef c = current_cg();
    if (c && count > 0) CGContextClipToRects(c, rects, (size_t)count);
}
/* The alert sound: there is no audio output. */
void NSBeep(void) {}
