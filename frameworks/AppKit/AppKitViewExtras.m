/* NSView's less central state (alpha, tooltips, tracking areas, safe
 * area, frame-change notifications, layout requests, rect conversion),
 * kept as associated values, and NSShadow and NSTrackingArea. */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <math.h>

static id get(id o, const void *key) { return objc_getAssociatedObject(o, key); }
static void set(id o, const void *key, id v) { objc_setAssociatedObject(o, key, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

@implementation NSShadow {
    NSSize _offset;
    CGFloat _blur;
    NSColor *_color;
}
- (instancetype)init {
    self = [super init];
    _color = [NSColor colorWithWhite:0 alpha:1.0 / 3];
    return self;
}
- (NSSize)shadowOffset { return _offset; }
- (void)setShadowOffset:(NSSize)s { _offset = s; }
- (CGFloat)shadowBlurRadius { return _blur; }
- (void)setShadowBlurRadius:(CGFloat)r { _blur = r; }
- (NSColor *)shadowColor { return _color; }
- (void)setShadowColor:(NSColor *)c { _color = c; }
- (void)set {
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (c) CGContextSetShadowWithColor(c, _offset, _blur, _color.CGColor);
}
- (id)copyWithZone:(NSZone *)zone {
    NSShadow *s = [[NSShadow alloc] init];
    s->_offset = _offset;
    s->_blur = _blur;
    s->_color = _color;
    return s;
}
@end

@implementation NSTrackingArea {
    NSRect _rect;
    NSTrackingAreaOptions _options;
    __weak id _owner;
    NSDictionary *_userInfo;
}
- (instancetype)initWithRect:(NSRect)rect options:(NSTrackingAreaOptions)options owner:(id)owner
                    userInfo:(NSDictionary *)userInfo {
    self = [super init];
    _rect = rect;
    _options = options;
    _owner = owner;
    _userInfo = [userInfo copy];
    return self;
}
- (NSRect)rect { return _rect; }
- (NSTrackingAreaOptions)options { return _options; }
- (id)owner { return _owner; }
- (NSDictionary *)userInfo { return _userInfo; }
- (id)copyWithZone:(NSZone *)zone {
    return [[NSTrackingArea alloc] initWithRect:_rect options:_options owner:_owner userInfo:_userInfo];
}
@end

static const char k_alpha, k_tooltip, k_identifier, k_shadow, k_focus, k_tamic, k_postsFrame, k_postsBounds,
    k_clips, k_compositing, k_contentFilters, k_backgroundFilters, k_needsLayout, k_tracking, k_dragTypes, k_tag,
    k_menu, k_additionalInsets;

@implementation NSView (BittenExtras)
- (CGFloat)alphaValue {
    NSNumber *n = get(self, &k_alpha);
    return n ? n.doubleValue : 1;
}
- (void)setAlphaValue:(CGFloat)a {
    set(self, &k_alpha, @(a));
    self.needsDisplay = YES;
}
- (NSString *)toolTip { return get(self, &k_tooltip); }
- (void)setToolTip:(NSString *)t { set(self, &k_tooltip, [t copy]); }
- (NSUserInterfaceItemIdentifier)identifier { return get(self, &k_identifier); }
- (void)setIdentifier:(NSUserInterfaceItemIdentifier)i { set(self, &k_identifier, [i copy]); }
- (NSShadow *)shadow { return get(self, &k_shadow); }
- (void)setShadow:(NSShadow *)s { set(self, &k_shadow, [s copy]); }
- (NSFocusRingType)focusRingType { return [get(self, &k_focus) integerValue]; }
- (void)setFocusRingType:(NSFocusRingType)t { set(self, &k_focus, @(t)); }
- (BOOL)translatesAutoresizingMaskIntoConstraints {
    NSNumber *n = get(self, &k_tamic);
    return n ? n.boolValue : YES;
}
- (void)setTranslatesAutoresizingMaskIntoConstraints:(BOOL)b { set(self, &k_tamic, @(b)); }
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric); }
- (void)invalidateIntrinsicContentSize { self.needsLayout = YES; }
- (NSSize)fittingSize {
    NSSize s = self.intrinsicContentSize;
    return NSMakeSize(s.width == NSViewNoIntrinsicMetric ? self.frame.size.width : s.width,
                      s.height == NSViewNoIntrinsicMetric ? self.frame.size.height : s.height);
}
- (NSEdgeInsets)additionalSafeAreaInsets {
    NSValue *v = get(self, &k_additionalInsets);
    return v ? v.edgeInsetsValue : NSEdgeInsetsZero;
}
- (void)setAdditionalSafeAreaInsets:(NSEdgeInsets)e { set(self, &k_additionalInsets, [NSValue valueWithEdgeInsets:e]); }
- (NSEdgeInsets)safeAreaInsets { return self.additionalSafeAreaInsets; }
- (NSRect)safeAreaRect {
    NSEdgeInsets e = self.safeAreaInsets;
    NSRect b = self.bounds;
    return NSMakeRect(b.origin.x + e.left, b.origin.y + e.bottom, b.size.width - e.left - e.right,
                      b.size.height - e.top - e.bottom);
}
- (BOOL)postsFrameChangedNotifications {
    NSNumber *n = get(self, &k_postsFrame);
    return n ? n.boolValue : YES;
}
- (void)setPostsFrameChangedNotifications:(BOOL)b { set(self, &k_postsFrame, @(b)); }
- (BOOL)postsBoundsChangedNotifications {
    NSNumber *n = get(self, &k_postsBounds);
    return n ? n.boolValue : YES;
}
- (void)setPostsBoundsChangedNotifications:(BOOL)b { set(self, &k_postsBounds, @(b)); }
- (BOOL)clipsToBounds { return [get(self, &k_clips) boolValue]; }
- (void)setClipsToBounds:(BOOL)b { set(self, &k_clips, @(b)); }
- (id)compositingFilter { return get(self, &k_compositing); }
- (void)setCompositingFilter:(id)f { set(self, &k_compositing, f); }
- (NSArray *)contentFilters { return get(self, &k_contentFilters) ?: @[]; }
- (void)setContentFilters:(NSArray *)f { set(self, &k_contentFilters, [f copy]); }
- (NSArray *)backgroundFilters { return get(self, &k_backgroundFilters) ?: @[]; }
- (void)setBackgroundFilters:(NSArray *)f { set(self, &k_backgroundFilters, [f copy]); }
- (BOOL)needsLayout { return [get(self, &k_needsLayout) boolValue]; }
- (void)setNeedsLayout:(BOOL)b {
    set(self, &k_needsLayout, @(b));
    if (b) self.needsDisplay = YES;
}
/* Solves the tree's constraints (AppKitLayout.m), then lets views lay out. */
extern void bn_layout_tree(NSView *root);
- (void)layoutSubtreeIfNeeded {
    NSView *root = self;
    while (root.superview) root = root.superview;
    bn_layout_tree(root);
    [self _bn_layoutSubtree];
}
- (void)_bn_layoutSubtree {
    if (self.needsLayout) {
        self.needsLayout = NO;
        [self layout];
    }
    for (NSView *v in self.subviews) [v _bn_layoutSubtree];
}
- (void)updateTrackingAreas {}
- (NSArray<NSTrackingArea *> *)trackingAreas { return [get(self, &k_tracking) copy] ?: @[]; }
- (void)addTrackingArea:(NSTrackingArea *)a {
    NSMutableArray *t = get(self, &k_tracking);
    if (!t) set(self, &k_tracking, t = [NSMutableArray array]);
    if (a) [t addObject:a];
}
- (void)removeTrackingArea:(NSTrackingArea *)a { [get(self, &k_tracking) removeObject:a]; }
- (void)addCursorRect:(NSRect)rect cursor:(NSCursor *)cursor {}
- (void)removeCursorRect:(NSRect)rect cursor:(NSCursor *)cursor {}
- (void)resetCursorRects {}
- (void)discardCursorRects {}
- (void)registerForDraggedTypes:(NSArray<NSPasteboardType> *)types { set(self, &k_dragTypes, [types copy]); }
- (void)unregisterDraggedTypes { set(self, &k_dragTypes, nil); }
- (NSArray<NSPasteboardType> *)registeredDraggedTypes { return get(self, &k_dragTypes) ?: @[]; }
- (NSScrollView *)enclosingScrollView {
    for (NSView *v = self.superview; v; v = v.superview)
        if ([v isKindOfClass:[NSScrollView class]]) return (NSScrollView *)v;
    return nil;
}
- (NSRect)visibleRect {
    NSRect r = self.bounds;
    for (NSView *v = self; v.superview; v = v.superview) {
        NSRect inSuper = [v convertRect:r toView:v.superview];
        inSuper = NSIntersectionRect(inSuper, v.superview.bounds);
        r = [v convertRect:inSuper fromView:v.superview];
        if (NSIsEmptyRect(r)) return NSZeroRect;
    }
    return r;
}
- (BOOL)isDescendantOf:(NSView *)view {
    for (NSView *v = self; v; v = v.superview)
        if (v == view) return YES;
    return NO;
}
- (BOOL)isHiddenOrHasHiddenAncestor {
    for (NSView *v = self; v; v = v.superview)
        if (v.isHidden) return YES;
    return NO;
}
- (NSInteger)tag { return [get(self, &k_tag) integerValue]; }
- (NSView *)viewWithTag:(NSInteger)tag {
    if (self.tag == tag) return self;
    for (NSView *v in self.subviews) {
        NSView *f = [v viewWithTag:tag];
        if (f) return f;
    }
    return nil;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return NO; }
- (BOOL)wantsDefaultClipping { return YES; }
- (BOOL)inLiveResize { return NO; }
- (void)viewDidChangeBackingProperties {}
- (NSMenu *)menu { return get(self, &k_menu); }
- (void)setMenu:(NSMenu *)m { set(self, &k_menu, m); }
- (NSRect)convertRect:(NSRect)r fromView:(NSView *)view {
    NSPoint a = [self convertPoint:r.origin fromView:view];
    NSPoint b = [self convertPoint:NSMakePoint(NSMaxX(r), NSMaxY(r)) fromView:view];
    return NSMakeRect(MIN(a.x, b.x), MIN(a.y, b.y), fabs(b.x - a.x), fabs(b.y - a.y));
}
- (NSRect)convertRect:(NSRect)r toView:(NSView *)view {
    NSPoint a = [self convertPoint:r.origin toView:view];
    NSPoint b = [self convertPoint:NSMakePoint(NSMaxX(r), NSMaxY(r)) toView:view];
    return NSMakeRect(MIN(a.x, b.x), MIN(a.y, b.y), fabs(b.x - a.x), fabs(b.y - a.y));
}
- (CGFloat)_bn_scale { return self.window ? self.window.backingScaleFactor : 1; }
- (NSPoint)convertPointToBacking:(NSPoint)p { CGFloat s = self._bn_scale; return NSMakePoint(p.x * s, p.y * s); }
- (NSPoint)convertPointFromBacking:(NSPoint)p { CGFloat s = self._bn_scale; return NSMakePoint(p.x / s, p.y / s); }
- (NSSize)convertSizeToBacking:(NSSize)z { CGFloat s = self._bn_scale; return NSMakeSize(z.width * s, z.height * s); }
- (NSSize)convertSizeFromBacking:(NSSize)z { CGFloat s = self._bn_scale; return NSMakeSize(z.width / s, z.height / s); }
- (NSRect)convertRectToBacking:(NSRect)r {
    CGFloat s = self._bn_scale;
    return NSMakeRect(r.origin.x * s, r.origin.y * s, r.size.width * s, r.size.height * s);
}
- (NSRect)convertRectFromBacking:(NSRect)r {
    CGFloat s = self._bn_scale;
    return NSMakeRect(r.origin.x / s, r.origin.y / s, r.size.width / s, r.size.height / s);
}
- (NSRect)backingAlignedRect:(NSRect)r options:(NSAlignmentOptions)options {
    NSRect b = [self convertRectToBacking:r];
    CGFloat x0 = round(NSMinX(b)), y0 = round(NSMinY(b)), x1 = round(NSMaxX(b)), y1 = round(NSMaxY(b));
    return [self convertRectFromBacking:NSMakeRect(x0, y0, x1 - x0, y1 - y0)];
}
@end
