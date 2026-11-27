/* AppKit: the application, responders, views, windows, events, colours,
 * fonts, screens and menus. Drawing and the window server come in separately
 * (CoreGraphics, the display); this file keeps the object model and the
 * application life cycle. */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void bn_debug_callers(void);
void bn_view_visibility(NSView *view, BOOL visible); /* AppKitControllers.m */
void bn_tree_visibility(NSView *root, BOOL visible);
@interface NSWindow (BittenAppearanceChange)
- (void)_bn_appearanceChanged; /* AppKitAppearance.m */
@end
@interface NSView (BittenContentsDiff)
- (BOOL)_bn_contentsChange:(NSRect *)changed; /* AppKitDrawing.m */
@end
@interface NSWindow (BittenPartialDisplay)
- (void)_bn_invalidateRect:(NSRect)r;
- (void)_bn_scheduleDisplay;
@end
@interface NSView (BittenTrackingState)
- (void)_bn_setTrackingAreasNeedUpdate; /* AppKitEvents.m */
@end

NSApplication *NSApp;

/* ---- NSResponder ---------------------------------------------------------- */

@implementation NSResponder
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)becomeFirstResponder { return YES; }
- (BOOL)resignFirstResponder { return YES; }
/* Unhandled events travel up the responder chain. */
- (void)mouseDown:(NSEvent *)event { [self.nextResponder mouseDown:event]; }
- (void)mouseUp:(NSEvent *)event { [self.nextResponder mouseUp:event]; }
- (void)mouseDragged:(NSEvent *)event { [self.nextResponder mouseDragged:event]; }
- (void)mouseMoved:(NSEvent *)event { [self.nextResponder mouseMoved:event]; }
- (void)rightMouseDown:(NSEvent *)event { [self.nextResponder rightMouseDown:event]; }
- (void)scrollWheel:(NSEvent *)event { [self.nextResponder scrollWheel:event]; }
- (void)keyDown:(NSEvent *)event { [self.nextResponder keyDown:event]; }
- (void)keyUp:(NSEvent *)event { [self.nextResponder keyUp:event]; }
- (void)flagsChanged:(NSEvent *)event { [self.nextResponder flagsChanged:event]; }
@end

/* ---- NSView ------------------------------------------------------------------ */

@interface NSView (BittenForgetWindow)
- (void)_bn_forgetWindow:(NSWindow *)w;
@end
@implementation NSView
/* A window or superview going away leaves its views without one (they
 * don't own it, and may outlive it). */
- (void)_bn_forgetWindow:(NSWindow *)w {
    if (_window != w) return;
    /* the window is going (its -dealloc): no view may reach it any more,
     * so it is forgotten before the views are told they left it */
    _window = nil;
    [self viewWillMoveToWindow:nil];
    for (NSView *s in [_subviews copy]) [s _bn_forgetWindow:w];
    [self viewDidMoveToWindow];
}
- (void)dealloc {
    for (NSView *s in _subviews)
        if (s->_superview == self) s->_superview = nil;
}
- (instancetype)init { return [self initWithFrame:NSZeroRect]; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super init])) {
        _frame = frame;
        _bounds = NSMakeRect(0, 0, frame.size.width, frame.size.height);
        _subviews = [NSMutableArray array];
        _needsDisplay = YES;
    }
    return self;
}
- (NSRect)frame { return _frame; }
/* As in AppKit, setFrame: goes through setFrameOrigin: and setFrameSize:,
 * which subclasses override (calling super). */
- (void)setFrame:(NSRect)frame {
    if (!NSEqualPoints(frame.origin, _frame.origin)) [self setFrameOrigin:frame.origin];
    if (!NSEqualSizes(frame.size, _frame.size)) [self setFrameSize:frame.size];
}
- (void)setFrameOrigin:(NSPoint)origin {
    static const char *debug_class;
    static int inited;
    if (!inited) { debug_class = getenv("BITTEN_FRAME_DEBUG"); inited = 1; }
    if (debug_class && strstr(object_getClassName(self), debug_class)) {
        fprintf(stderr, "bitten: %s origin %s -> %s from", object_getClassName(self),
                NSStringFromPoint(_frame.origin).UTF8String, NSStringFromPoint(origin).UTF8String);
        bn_debug_callers();
    }
    BOOL moved = !NSEqualPoints(origin, _frame.origin);
    if (moved) [self _bn_invalidateOwnArea];   /* where it was */
    _frame.origin = origin;
    _needsDisplay = YES;
    if (moved) [self _bn_invalidateOwnArea];   /* where it is */
    [self _bn_syncLayerGeometry];
}
/* A backing layer has the view's geometry: its bounds are the view's
 * bounds and its frame, in the superview's coordinates, the view's frame. */
- (void)_bn_syncLayerGeometry {
    id l = self.layer;
    if (!l) return;
    [l setValue:[NSValue valueWithRect:_bounds] forKey:@"bounds"];
    NSPoint anchor = [[l valueForKey:@"anchorPoint"] pointValue];
    [l setValue:[NSValue valueWithPoint:NSMakePoint(_frame.origin.x + anchor.x * _frame.size.width,
                                                    _frame.origin.y + anchor.y * _frame.size.height)]
         forKey:@"position"];
}
- (void)setFrameSize:(NSSize)size {
    NSSize old = _frame.size;
    BOOL changed = !NSEqualSizes(old, size);
    if (changed) [self _bn_invalidateOwnArea];
    _frame.size = size;
    _bounds.size = size;
    _needsDisplay = YES;
    if (changed) [self _bn_invalidateOwnArea];
    [self _bn_syncLayerGeometry];
    if (!NSEqualSizes(old, size)) [self _bn_setTrackingAreasNeedUpdate];
    if (!NSEqualSizes(old, size) && self.autoresizesSubviews) [self resizeSubviewsWithOldSize:old];
}

/* Autoresizing: each subview's autoresizing mask says which of its left
 * margin, width and right margin (and bottom margin, height, top margin)
 * absorb a change in its superview's size. The change is shared among the
 * flexible parts in proportion to their current lengths (equally when they
 * are all zero). Views laid out by constraints are left alone. */
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    for (NSView *v in [_subviews copy])
        if (v.translatesAutoresizingMaskIntoConstraints) [v resizeWithOldSuperviewSize:oldSize];
}

static void bn_autoresize_axis(CGFloat delta, BOOL flexLo, BOOL flexLen, BOOL flexHi, CGFloat lo, CGFloat len, CGFloat hi,
                               CGFloat *origin, CGFloat *length) {
    int n = flexLo + flexLen + flexHi;
    if (n == 0 || delta == 0) return;
    CGFloat total = (flexLo ? MAX(lo, 0) : 0) + (flexLen ? MAX(len, 0) : 0) + (flexHi ? MAX(hi, 0) : 0);
    CGFloat dLo = 0, dLen = 0;
    if (total > 0) {
        if (flexLo) dLo = delta * MAX(lo, 0) / total;
        if (flexLen) dLen = delta * MAX(len, 0) / total;
    } else {
        if (flexLo) dLo = delta / n;
        if (flexLen) dLen = delta / n;
    }
    *origin += dLo;
    *length = MAX(0, *length + dLen);
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    NSAutoresizingMaskOptions m = _autoresizingMask;
    if (m == NSViewNotSizable || !_superview) return;
    NSSize now = _superview.bounds.size;
    NSRect f = _frame;
    bn_autoresize_axis(now.width - oldSize.width, (m & NSViewMinXMargin) != 0, (m & NSViewWidthSizable) != 0,
                       (m & NSViewMaxXMargin) != 0, f.origin.x, f.size.width, oldSize.width - NSMaxX(f), &f.origin.x,
                       &f.size.width);
    bn_autoresize_axis(now.height - oldSize.height, (m & NSViewMinYMargin) != 0, (m & NSViewHeightSizable) != 0,
                       (m & NSViewMaxYMargin) != 0, f.origin.y, f.size.height, oldSize.height - NSMaxY(f), &f.origin.y,
                       &f.size.height);
    if (!NSEqualRects(f, _frame)) [self setFrame:f];
}
- (NSRect)bounds { return _bounds; }
- (void)setBounds:(NSRect)bounds {
    _bounds = bounds;
    [self _bn_syncLayerGeometry];
}
- (void)setBoundsOrigin:(NSPoint)origin {
    _bounds.origin = origin;
    _needsDisplay = YES;
    [self _bn_syncLayerGeometry];
}
- (void)setBoundsSize:(NSSize)size {
    _bounds.size = size;
    _needsDisplay = YES;
    [self _bn_syncLayerGeometry];
}
- (NSArray *)subviews { return [_subviews copy]; }
- (NSView *)superview { return _superview; }
- (NSWindow *)window { return _window; }
- (BOOL)needsDisplay { return _needsDisplay; }
- (void)setNeedsDisplay:(BOOL)flag {
    _needsDisplay = flag;
    if (!flag) return;
    /* New layer contents redraw only where their pixels changed. */
    NSRect changed;
    if (_window && [self _bn_contentsChange:&changed]) {
        if (!NSIsEmptyRect(changed)) [_window _bn_invalidateRect:changed];
        for (NSView *v = _superview; v; v = v->_superview) v->_needsDisplay = YES;
        return;
    }
    /* A view in a window repaints its own area (with a margin for what a
     * layer draws just outside: shadows, borders), not the whole window. */
    if (_superview && _window) {
        for (NSView *v = _superview; v; v = v->_superview) v->_needsDisplay = YES;
        [self _bn_invalidateOwnArea];
        return;
    }
    if (_superview) _superview.needsDisplay = YES;
    /* (a view out of the tree but still naming a window isn't drawn) */
    else if (_window && (_window.contentView == self || self == [_window _bn_frameView])) [_window _bn_scheduleDisplay];
}
- (void)_bn_invalidateOwnArea {
    if (!_window || !_superview) return;
    [_window _bn_invalidateRect:[self convertRect:NSInsetRect(self.bounds, -12, -12) toView:nil]];
}
- (void)setNeedsDisplayInRect:(NSRect)rect {
    if (_superview && _window && !NSIsEmptyRect(rect)) {
        _needsDisplay = YES;
        for (NSView *v = _superview; v; v = v->_superview) v->_needsDisplay = YES;
        [_window _bn_invalidateRect:[self convertRect:NSInsetRect(rect, -2, -2) toView:nil]];
        return;
    }
    self.needsDisplay = YES;
}
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)hidden { _hidden = hidden; }
- (BOOL)wantsLayer { return _wantsLayer; }
- (void)setWantsLayer:(BOOL)flag {
    _wantsLayer = flag;
    if (flag && !self.layer) self.layer = [self makeBackingLayer];
}
/* Backing layers come from QuartzCore, looked up at run time so AppKit
 * does not link it. */
- (CALayer *)makeBackingLayer {
    Class cls = objc_getClass("CALayer");
    id l = cls ? [cls new] : nil;
    if (l) {
        [l setValue:@(self.window ? self.window.backingScaleFactor : 1.0) forKey:@"contentsScale"];
    }
    return l;
}
- (CALayer *)layer { return objc_getAssociatedObject(self, @selector(layer)); }
- (void)setLayer:(CALayer *)layer {
    objc_setAssociatedObject(self, @selector(layer), layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (layer) [(id)layer setValue:self forKey:@"delegate"];
    [self _bn_syncLayerGeometry];
}
- (BOOL)wantsUpdateLayer { return NO; }
- (void)updateLayer {}
- (NSViewLayerContentsRedrawPolicy)layerContentsRedrawPolicy {
    return [objc_getAssociatedObject(self, @selector(layerContentsRedrawPolicy)) integerValue];
}
- (void)setLayerContentsRedrawPolicy:(NSViewLayerContentsRedrawPolicy)p {
    objc_setAssociatedObject(self, @selector(layerContentsRedrawPolicy), @(p), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSViewLayerContentsPlacement)layerContentsPlacement {
    return [objc_getAssociatedObject(self, @selector(layerContentsPlacement)) integerValue];
}
- (void)setLayerContentsPlacement:(NSViewLayerContentsPlacement)p {
    objc_setAssociatedObject(self, @selector(layerContentsPlacement), @(p), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)canDrawSubviewsIntoLayer { return NO; }
- (void)setCanDrawSubviewsIntoLayer:(BOOL)flag {}
- (NSAutoresizingMaskOptions)autoresizingMask { return _autoresizingMask; }
- (void)setAutoresizingMask:(NSAutoresizingMaskOptions)m { _autoresizingMask = m; }
- (BOOL)isFlipped { return NO; }

- (void)_setWindow:(NSWindow *)window {
    if (window == _window) return;
    /* The first responder leaving its window hands first responder status
     * to the window itself, as on macOS: the view is asked to resign, and
     * goes either way (it can't stay first responder of a window it left). */
    if (_window && _window.firstResponder == self && ![_window makeFirstResponder:nil])
        [_window _bn_dropFirstResponder];
    [self viewWillMoveToWindow:window];
    BOOL was = _window.isVisible;
    _window = window;
    static const char *methods_of;
    static int methods_inited;
    if (!methods_inited) { methods_of = getenv("BITTEN_METHODS"); methods_inited = 1; }
    if (window && methods_of && strstr(object_getClassName(self), methods_of)) {
        unsigned n = 0;
        Method *ms = class_copyMethodList(object_getClass(self), &n);
        fprintf(stderr, "bitten: %s methods:", object_getClassName(self));
        for (unsigned i = 0; i < n; i++)
            fprintf(stderr, " %s@%p", sel_getName(method_getName(ms[i])), (void *)method_getImplementation(ms[i]));
        fprintf(stderr, "\n");
        free(ms);
        void (^ivars)(const char *) = ^(const char *when) {
            unsigned ni = 0;
            Ivar *iv = class_copyIvarList(object_getClass(self), &ni);
            fprintf(stderr, "bitten: %s ivars %s:", object_getClassName(self), when);
            for (unsigned i = 0; i < ni; i++)
                fprintf(stderr, " %s@%td=%02x", ivar_getName(iv[i]), ivar_getOffset(iv[i]),
                        ((const unsigned char *)(__bridge void *)self)[ivar_getOffset(iv[i])]);
            fprintf(stderr, "\n");
            free(iv);
        };
        ivars("joining");
        dispatch_async(dispatch_get_main_queue(), ^{ ivars("a turn later"); });
    }
    /* a controller's view appears with a visible window, and goes with it */
    if (window.isVisible != was) bn_view_visibility(self, window.isVisible);
    for (NSView *v in _subviews) [v _setWindow:window];
    if (window) [self _bn_setTrackingAreasNeedUpdate];
    [self viewDidMoveToWindow];
}
- (void)addSubview:(NSView *)view {
    if (!view) return;
    [view removeFromSuperview];
    [_subviews addObject:view];
    view->_superview = self;
    view.nextResponder = self;
    [view _setWindow:_window];
    self.needsDisplay = YES;
}
- (void)addSubview:(NSView *)view positioned:(NSWindowOrderingMode)place relativeTo:(NSView *)other {
    if (!view) return;
    [view removeFromSuperview];
    NSUInteger i = other ? [_subviews indexOfObjectIdenticalTo:other] : NSNotFound;
    if (i == NSNotFound) i = place == NSWindowBelow ? 0 : _subviews.count;
    else if (place == NSWindowAbove) i++;
    [_subviews insertObject:view atIndex:i];
    view->_superview = self;
    view.nextResponder = self;
    [view _setWindow:_window];
    self.needsDisplay = YES;
}
- (void)replaceSubview:(NSView *)old with:(NSView *)replacement {
    NSUInteger i = [_subviews indexOfObjectIdenticalTo:old];
    if (i == NSNotFound) return;
    [old removeFromSuperview];
    if (!replacement) return;
    [replacement removeFromSuperview];
    [_subviews insertObject:replacement atIndex:MIN(i, _subviews.count)];
    replacement->_superview = self;
    replacement.nextResponder = self;
    [replacement _setWindow:_window];
    self.needsDisplay = YES;
}
- (void)setSubviews:(NSArray<NSView *> *)views {
    for (NSView *v in [_subviews copy])
        if (![views containsObject:v]) [v removeFromSuperview];
    [_subviews removeAllObjects];
    for (NSView *v in views) {
        if (v->_superview && v->_superview != self) [v removeFromSuperview];
        [_subviews addObject:v];
        v->_superview = self;
        v.nextResponder = self;
        [v _setWindow:_window];
    }
    self.needsDisplay = YES;
}
- (void)sortSubviewsUsingFunction:(NSComparisonResult (*)(id, id, void *))compare context:(void *)context {
    [_subviews sortUsingComparator:^NSComparisonResult(id a, id b) { return compare(a, b, context); }];
    self.needsDisplay = YES;
}
- (NSView *)ancestorSharedWithView:(NSView *)other {
    for (NSView *a = self; a; a = a->_superview)
        for (NSView *b = other; b; b = b->_superview)
            if (a == b) return a;
    return nil;
}
- (void)removeFromSuperview {
    NSView *s = _superview;
    if (!s) return;
    [s->_subviews removeObject:self];
    _superview = nil;
    [self _setWindow:nil];
    s.needsDisplay = YES;
}
/* Views draw as part of their window (AppKitDrawing.m). */
- (void)display { [_window display]; }
- (void)drawRect:(NSRect)dirtyRect {}
- (void)layout {}
- (void)viewDidMoveToWindow {}
- (void)viewWillMoveToWindow:(NSWindow *)window {}

/* Converts between this view's coordinates and another's (or the window's
 * when `view` is nil), walking up through frames. A frame is in its
 * superview's coordinates; when a view's flippedness differs from its
 * superview's (the window counts as unflipped), its y runs from the other
 * edge of its frame, as in drawing (AppKitDrawing.m). */
static BOOL super_flipped(NSView *v) { return v->_superview ? v->_superview.isFlipped : NO; }
- (NSPoint)_toSuperview:(NSPoint)p {
    NSPoint q;
    q.x = _frame.origin.x + (p.x - _bounds.origin.x);
    q.y = self.isFlipped == super_flipped(self) ? _frame.origin.y + (p.y - _bounds.origin.y)
                                                : _frame.origin.y + _frame.size.height - (p.y - _bounds.origin.y);
    return q;
}
- (NSPoint)_fromSuperview:(NSPoint)q {
    NSPoint p;
    p.x = q.x - _frame.origin.x + _bounds.origin.x;
    p.y = self.isFlipped == super_flipped(self) ? q.y - _frame.origin.y + _bounds.origin.y
                                                : _frame.origin.y + _frame.size.height - q.y + _bounds.origin.y;
    return p;
}
- (NSPoint)_toWindow:(NSPoint)p {
    for (NSView *v = self; v; v = v->_superview) p = [v _toSuperview:p];
    return p;
}
- (NSPoint)_fromWindow:(NSPoint)p {
    NSMutableArray<NSView *> *chain = [NSMutableArray array];
    for (NSView *v = self; v; v = v->_superview) [chain insertObject:v atIndex:0];
    for (NSView *v in chain) p = [v _fromSuperview:p];
    return p;
}
- (NSPoint)convertPoint:(NSPoint)point fromView:(NSView *)view {
    NSPoint w = view ? [view _toWindow:point] : point;
    return [self _fromWindow:w];
}
- (NSPoint)convertPoint:(NSPoint)point toView:(NSView *)view {
    NSPoint w = [self _toWindow:point];
    return view ? [view _fromWindow:w] : w;
}
/* point is in the superview's coordinates, as in AppKit. */
- (NSView *)hitTest:(NSPoint)point {
    if (_hidden || !NSPointInRect(point, _frame)) return nil;
    NSPoint local = [self _fromSuperview:point];
    for (NSView *v in [_subviews reverseObjectEnumerator]) {
        NSView *hit = [v hitTest:local];
        if (hit) return hit;
    }
    return self;
}
@end

/* ---- NSControl --------------------------------------------------------------- */

@implementation NSControl {
    NSString *_stringValue;
    NSFont *_font;
    BOOL _disabled;
}
@synthesize target = _target, action = _action;
- (BOOL)isEnabled { return !_disabled; }
- (void)setEnabled:(BOOL)enabled { _disabled = !enabled; }
- (NSString *)stringValue { return _stringValue ?: @""; }
- (void)setStringValue:(NSString *)s { _stringValue = [s copy]; self.needsDisplay = YES; }
- (double)doubleValue { return [self.stringValue doubleValue]; }
- (void)setDoubleValue:(double)v { self.stringValue = [NSString stringWithFormat:@"%g", v]; }
- (NSInteger)integerValue { return [self.stringValue integerValue]; }
- (void)setIntegerValue:(NSInteger)v { self.stringValue = [NSString stringWithFormat:@"%ld", (long)v]; }
- (NSFont *)font { return _font ?: [NSFont systemFontOfSize:[NSFont systemFontSize]]; }
- (void)setFont:(NSFont *)font { _font = font; }
@end

/* ---- NSWindow ---------------------------------------------------------------- */

static NSMutableArray<NSWindow *> *all_windows;
/* Debugging: the return addresses of the caller's frames, to the end of
 * the line (frames without frame pointers end the walk). */
__attribute__((noinline)) void bn_debug_callers(void) {
    void **fp = __builtin_frame_address(1);
    for (int i = 0; i < 10 && fp; i++) {
        fprintf(stderr, " %p", fp[1]);
        void **next = fp[0];
        if (next <= fp || (char *)next - (char *)fp > (1 << 20)) break;
        fp = next;
    }
    fprintf(stderr, "\n");
}

static NSUInteger next_window_number = 1;

/* The window's frame view, as AppKit's theme frame: the content view's
 * superview, as large as the window. Programs add views to it to draw over
 * the content (window.contentView.superview). */
@interface BNFrameView : NSView
@end
@implementation BNFrameView
@end

@implementation NSWindow {
    NSColor *_backgroundColor;
    BNFrameView *_frameView;
}
- (NSView *)_bn_frameView { return _frameView; }
@synthesize delegate = _delegate;
- (void)dealloc {
    if (getenv("BITTEN_WINDOW_DEBUG")) fprintf(stderr, "bitten: window %s '%s' freed\n", object_getClassName(self), _title.UTF8String ?: "");
    /* Its views leave it, told so (viewWillMoveToWindow: nil, ...), as when
     * AppKit lets a window go: they drop what they set up for it (event
     * monitors, observers). */
    [self _bn_dropFirstResponder];
    [_frameView _bn_forgetWindow:self];
}
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)flag {
    if (getenv("BITTEN_WINDOW_DEBUG")) {
        fprintf(stderr, "bitten: window created with content %s style %#lx from", NSStringFromRect(rect).UTF8String,
                (unsigned long)style);
        bn_debug_callers();
    }
    if ((self = [super init])) {
        _styleMask = style;
        _frame = [self frameRectForContentRect:rect];
        _windowNumber = next_window_number++;
        _title = @"";
        _frameView = [[BNFrameView alloc] initWithFrame:NSMakeRect(0, 0, _frame.size.width, _frame.size.height)];
        _frameView.autoresizesSubviews = NO;   /* the window sizes the content view itself */
        [_frameView _setWindow:self];
        self.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, rect.size.width, rect.size.height)];
        if (!all_windows) all_windows = [NSMutableArray array];
        [all_windows addObject:self];
    }
    return self;
}
- (instancetype)init {
    return [self initWithContentRect:NSMakeRect(0, 0, 480, 320) styleMask:NSWindowStyleMaskTitled
                             backing:NSBackingStoreBuffered defer:NO];
}
/* Title bars are drawn by the display, so the content fills the frame
 * except for a 28-point title bar on titled windows without a full-size
 * content view. */
- (CGFloat)_titleBarHeight {
    return ((_styleMask & NSWindowStyleMaskTitled) && !(_styleMask & NSWindowStyleMaskFullSizeContentView)) ? 28 : 0;
}
- (NSRect)frameRectForContentRect:(NSRect)r {
    r.size.height += [self _titleBarHeight];
    return r;
}
- (NSRect)contentRectForFrameRect:(NSRect)r {
    r.size.height -= [self _titleBarHeight];
    return r;
}
- (NSView *)contentView { return _contentView; }
- (void)setContentView:(NSView *)view {
    NSView *old = _contentView;
    _contentView = view;
    if (old.superview == _frameView) [old removeFromSuperview];
    [old _setWindow:nil];
    old.nextResponder = nil;
    NSRect c = [self contentRectForFrameRect:_frame];
    if (view) {
        /* below anything else in the frame view: views added there draw over it */
        if (view.superview != _frameView) [_frameView addSubview:view positioned:NSWindowBelow relativeTo:nil];
        view.frame = [self _bn_contentViewFrame];
        view.nextResponder = self;
        [view _setWindow:self];
    }
}
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t { _title = [t copy]; }
- (NSWindowStyleMask)styleMask { return _styleMask; }
- (void)setStyleMask:(NSWindowStyleMask)m {
    _styleMask = m;
    _frameView.frame = NSMakeRect(0, 0, _frame.size.width, _frame.size.height);
    _contentView.frame = [self _bn_contentViewFrame];
}
/* Where the content view goes: all the content rect, but below the title
 * bar's strip in a full-size-content window whose toolbar shows items
 * there (the area macOS keeps out of such content's safe area). */
- (NSRect)_bn_contentViewFrame {
    NSRect c = [self contentRectForFrameRect:_frame];
    CGFloat strip = 0;
    if ((_styleMask & NSWindowStyleMaskTitled) && (_styleMask & NSWindowStyleMaskFullSizeContentView)) {
        NSToolbar *t = self.toolbar;
        if (t.isVisible && t.visibleItems.count) strip = 28;
    }
    return NSMakeRect(0, 0, c.size.width, MAX(0, c.size.height - strip));
}
- (NSRect)frame { return _frame; }
- (BOOL)isVisible { return _visible; }
- (BOOL)isKeyWindow { return _key; }
- (NSInteger)windowNumber { return (NSInteger)_windowNumber; }
- (NSColor *)backgroundColor { return _backgroundColor ?: [NSColor windowBackgroundColor]; }
- (void)setBackgroundColor:(NSColor *)c { _backgroundColor = c; }
- (void)_post:(NSNotificationName)name {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self];
}
- (void)setFrame:(NSRect)frame display:(BOOL)flag {
    if (getenv("BITTEN_WINDOW_DEBUG")) {
        fprintf(stderr, "bitten: window %s frame %s -> %s from", object_getClassName(self), NSStringFromRect(_frame).UTF8String,
                NSStringFromRect(frame).UTF8String);
        bn_debug_callers();
    }
    BOOL resized = frame.size.width != _frame.size.width || frame.size.height != _frame.size.height;
    BOOL moved = !NSEqualPoints(frame.origin, _frame.origin);
    _frame = frame;
    NSRect c = [self contentRectForFrameRect:frame];
    _frameView.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
    _contentView.frame = [self _bn_contentViewFrame];
    if (resized) {
        if ([_delegate respondsToSelector:@selector(windowDidResize:)])
            [_delegate windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification
                                                                     object:self userInfo:nil]];
        [self _post:NSWindowDidResizeNotification];
    }
    if (moved) [self _bn_tell:NSWindowDidMoveNotification delegate:@selector(windowDidMove:)];
    if (flag) [self display];
}
- (void)setContentSize:(NSSize)size {
    NSRect f = [self frameRectForContentRect:NSMakeRect(_frame.origin.x, _frame.origin.y, size.width, size.height)];
    [self setFrame:f display:YES];
}
- (void)center {
    NSRect s = [NSScreen mainScreen].visibleFrame;
    _frame.origin = NSMakePoint(s.origin.x + (s.size.width - _frame.size.width) / 2,
                                s.origin.y + (s.size.height - _frame.size.height) / 2);
}
- (void)orderFront:(id)sender {
    if (getenv("BITTEN_EVENT_DEBUG") && !_visible)
        fprintf(stderr, "bitten: window %s %s ordered front\n", object_getClassName(self), NSStringFromRect(_frame).UTF8String);
    BOOL was = _visible;
    _visible = YES;
    if (!was) bn_tree_visibility(_frameView, YES);
    [self display];
    [self _bn_orderFrontOnDisplay];
    if (!was) [self _bn_occlusionChanged];
}
- (void)makeKeyAndOrderFront:(id)sender {
    if (getenv("BITTEN_EVENT_DEBUG")) {
        fprintf(stderr, "bitten: window %s made key from", object_getClassName(self));
        bn_debug_callers();
    }
    [self orderFront:sender];
    [self _bn_becomeKey];
}
/* Key-window changes, as AppKit makes them: the window losing key status
 * hears resignKeyWindow, its delegate's windowDidResignKey: and the
 * notification, then the new one the same for becoming key. */
/* Tells the delegate (when it has `sel`) and posts `name`. */
- (void)_bn_tell:(NSNotificationName)name delegate:(SEL)sel {
    NSNotification *n = [NSNotification notificationWithName:name object:self userInfo:nil];
    if (sel && [_delegate respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(_delegate, sel, n);
    [[NSNotificationCenter defaultCenter] postNotification:n];
}
/* The main window: the key window when it can be main; a panel made key
 * leaves the main window main (as in AppKit). */
static const char kMainKey;
- (BOOL)isMainWindow { return [objc_getAssociatedObject(self, &kMainKey) boolValue]; }
- (void)_bn_becomeMain {
    if (self.isMainWindow) return;
    for (NSWindow *w in [all_windows copy])
        if (w != self) [w _bn_resignMain];
    objc_setAssociatedObject(self, &kMainKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self becomeMainWindow];
    [self _bn_tell:NSWindowDidBecomeMainNotification delegate:@selector(windowDidBecomeMain:)];
}
- (void)_bn_resignMain {
    if (!self.isMainWindow) return;
    objc_setAssociatedObject(self, &kMainKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self resignMainWindow];
    [self _bn_tell:NSWindowDidResignMainNotification delegate:@selector(windowDidResignMain:)];
}
- (void)becomeMainWindow {}
- (void)resignMainWindow {}
- (void)makeMainWindow { if (self.canBecomeMainWindow && _visible) [self _bn_becomeMain]; }
/* Whether the window can be seen changed: its occlusion state did. */
- (void)_bn_occlusionChanged {
    [self _bn_tell:NSWindowDidChangeOcclusionStateNotification delegate:@selector(windowDidChangeOcclusionState:)];
}
- (void)_bn_resignKey {
    if (!_key) return;
    _key = NO;
    [self resignKeyWindow];
    NSNotification *n = [NSNotification notificationWithName:NSWindowDidResignKeyNotification object:self userInfo:nil];
    if ([_delegate respondsToSelector:@selector(windowDidResignKey:)]) [_delegate windowDidResignKey:n];
    [[NSNotificationCenter defaultCenter] postNotification:n];
}
- (void)_bn_becomeKey {
    if (_key) return;
    for (NSWindow *w in [all_windows copy])
        if (w != self) [w _bn_resignKey];
    _key = YES;
    [self becomeKeyWindow];
    NSNotification *n = [NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:self userInfo:nil];
    if ([_delegate respondsToSelector:@selector(windowDidBecomeKey:)]) [_delegate windowDidBecomeKey:n];
    [[NSNotificationCenter defaultCenter] postNotification:n];
    if (self.canBecomeMainWindow) [self _bn_becomeMain];
}
/* A key window that goes away passes key status to the frontmost titled
 * window left (the main window, usually). */
- (void)_bn_passKeyOn {
    if (!_key) return;
    [self _bn_resignKey];
    for (NSWindow *w in [all_windows reverseObjectEnumerator])
        if (w != self && w->_visible && (w->_styleMask & NSWindowStyleMaskTitled)) {
            [w _bn_becomeKey];
            break;
        }
}
- (void)orderOut:(id)sender {
    BOOL was = _visible;
    if (_visible) bn_tree_visibility(_frameView, NO);
    _visible = NO;
    [self _bn_closeDisplay];
    [self _bn_resignMain];
    [self _bn_passKeyOn];
    if (was) [self _bn_occlusionChanged];
}
/* Hidden but still known to the display (miniaturized: shown as a chip). */
- (void)_bn_hideKeepingDisplay {
    BOOL was = _visible;
    if (_visible) bn_tree_visibility(_frameView, NO);
    _visible = NO;
    [self _bn_resignMain];
    if (was) [self _bn_occlusionChanged];
    [self _bn_passKeyOn];
}
- (void)close {
    if ([_delegate respondsToSelector:@selector(windowWillClose:)])
        [_delegate windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification
                                                                 object:self userInfo:nil]];
    [self _post:NSWindowWillCloseNotification];
    if (_visible) bn_tree_visibility(_frameView, NO);
    _visible = NO;
    [self _bn_closeDisplay];
    [self _bn_passKeyOn];
    [all_windows removeObject:self];
}
@end

/* ---- NSApplication --------------------------------------------------------------- */

@implementation NSApplication {
    BOOL _running, _active, _launched;
    NSMenu *_mainMenu;
    NSApplicationActivationPolicy _policy;
    NSAppearance *_appearance;
}
@synthesize delegate = _delegate;
- (NSAppearance *)appearance { return _appearance; }
/* Every window follows (those without an appearance of their own). */
- (void)setAppearance:(NSAppearance *)appearance {
    _appearance = appearance;
    for (NSWindow *w in all_windows) [w _bn_appearanceChanged];
}
+ (NSApplication *)sharedApplication {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSApp = [[self alloc] init];
    });
    return NSApp;
}
- (NSArray *)windows { return all_windows ? [all_windows copy] : @[]; }
- (NSWindow *)keyWindow {
    for (NSWindow *w in all_windows)
        if (w.keyWindow) return w;
    return nil;
}
- (NSWindow *)mainWindow {
    for (NSWindow *w in all_windows)
        if (w.isMainWindow) return w;
    return nil;
}
- (NSMenu *)mainMenu { return _mainMenu; }
- (void)setMainMenu:(NSMenu *)m { _mainMenu = m; }
- (BOOL)isRunning { return _running; }
- (BOOL)isActive { return _active; }
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p {
    _policy = p;
    return YES;
}
- (void)_post:(NSNotificationName)name {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self];
}
- (void)activateIgnoringOtherApps:(BOOL)flag { [self activate]; }
- (void)activate {
    if (_active) return;
    [self _post:NSApplicationWillBecomeActiveNotification];
    _active = YES;
    if ([_delegate respondsToSelector:@selector(applicationDidBecomeActive:)])
        [_delegate applicationDidBecomeActive:[NSNotification notificationWithName:NSApplicationDidBecomeActiveNotification
                                                                            object:self userInfo:nil]];
    [self _post:NSApplicationDidBecomeActiveNotification];
}
- (void)finishLaunching {
    if (_launched) return;
    _launched = YES;
    [self _bn_installCoreEventHandlers];
    NSNotification *n = [NSNotification notificationWithName:NSApplicationWillFinishLaunchingNotification
                                                      object:self userInfo:nil];
    if ([_delegate respondsToSelector:@selector(applicationWillFinishLaunching:)])
        [_delegate applicationWillFinishLaunching:n];
    [self _post:NSApplicationWillFinishLaunchingNotification];
    n = [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:self userInfo:nil];
    if ([_delegate respondsToSelector:@selector(applicationDidFinishLaunching:)])
        [_delegate applicationDidFinishLaunching:n];
    [self _post:NSApplicationDidFinishLaunchingNotification];
    [self activate];
}
/* The main thread runs the main run loop from here on, which drains the
 * main dispatch queue: window server events, timers and Swift's MainActor
 * all arrive there as blocks, and run loop observers see each turn. */
- (void)run {
    _running = YES;
    [self finishLaunching];
    [[NSRunLoop mainRunLoop] run];
}
- (void)stop:(id)sender { _running = NO; }
- (void)terminate:(id)sender {
    if ([_delegate respondsToSelector:@selector(applicationShouldTerminate:)] &&
        [_delegate applicationShouldTerminate:self] != NSTerminateNow)
        return;
    if ([_delegate respondsToSelector:@selector(applicationWillTerminate:)])
        [_delegate applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification
                                                                          object:self userInfo:nil]];
    [self _post:NSApplicationWillTerminateNotification];
    exit(0);
}
@end

int NSApplicationMain(int argc, const char *argv[]) {
    [[NSApplication sharedApplication] run];
    return 0;
}

/* ---- NSEvent ------------------------------------------------------------------------ */

@implementation NSEvent {
  @public
    NSEventType _type;
    NSEventModifierFlags _flags;
    NSPoint _location;
    NSString *_chars, *_charsIgnoring;
    NSTimeInterval _timestamp;
    NSInteger _windowNumber, _clickCount;
    unsigned short _keyCode;
    CGFloat _dx, _dy;
    BOOL _repeat;
}
static NSPoint mouse_location;
static NSEventModifierFlags current_flags;

+ (NSEvent *)mouseEventWithType:(NSEventType)type location:(NSPoint)location modifierFlags:(NSEventModifierFlags)flags
                      timestamp:(NSTimeInterval)time windowNumber:(NSInteger)wn context:(id)context
                    eventNumber:(NSInteger)n clickCount:(NSInteger)clicks pressure:(float)pressure {
    NSEvent *e = [NSEvent new];
    e->_type = type;
    e->_location = location;
    e->_flags = flags;
    e->_timestamp = time;
    e->_windowNumber = wn;
    e->_clickCount = clicks;
    return e;
}
+ (NSEvent *)keyEventWithType:(NSEventType)type location:(NSPoint)location modifierFlags:(NSEventModifierFlags)flags
                    timestamp:(NSTimeInterval)time windowNumber:(NSInteger)wn context:(id)context
                   characters:(NSString *)chars charactersIgnoringModifiers:(NSString *)unmod
                    isARepeat:(BOOL)repeat keyCode:(unsigned short)code {
    NSEvent *e = [NSEvent new];
    e->_type = type;
    e->_location = location;
    e->_flags = flags;
    e->_timestamp = time;
    e->_windowNumber = wn;
    e->_chars = [chars copy];
    e->_charsIgnoring = [unmod copy];
    e->_repeat = repeat;
    e->_keyCode = code;
    return e;
}
- (NSEventType)type { return _type; }
- (NSEventModifierFlags)modifierFlags { return _flags; }
- (NSTimeInterval)timestamp { return _timestamp; }
- (NSInteger)windowNumber { return _windowNumber; }
- (NSWindow *)window {
    for (NSWindow *w in [NSApp windows])
        if (w.windowNumber == _windowNumber) return w;
    return nil;
}
- (NSPoint)locationInWindow { return _location; }
- (NSInteger)clickCount { return _clickCount; }
- (NSString *)characters { return _chars; }
- (NSString *)charactersIgnoringModifiers { return _charsIgnoring ?: _chars; }
/* The characters this key makes with other modifiers, on the US layout
 * (ANSI virtual key codes): unshifted and shifted characters per key. */
static const struct { unsigned short code; char plain, shifted; } bn_us_keys[] = {
    {0, 'a', 'A'}, {1, 's', 'S'}, {2, 'd', 'D'}, {3, 'f', 'F'}, {4, 'h', 'H'}, {5, 'g', 'G'},
    {6, 'z', 'Z'}, {7, 'x', 'X'}, {8, 'c', 'C'}, {9, 'v', 'V'}, {11, 'b', 'B'}, {12, 'q', 'Q'},
    {13, 'w', 'W'}, {14, 'e', 'E'}, {15, 'r', 'R'}, {16, 'y', 'Y'}, {17, 't', 'T'}, {18, '1', '!'},
    {19, '2', '@'}, {20, '3', '#'}, {21, '4', '$'}, {22, '6', '^'}, {23, '5', '%'}, {24, '=', '+'},
    {25, '9', '('}, {26, '7', '&'}, {27, '-', '_'}, {28, '8', '*'}, {29, '0', ')'}, {30, ']', '}'},
    {31, 'o', 'O'}, {32, 'u', 'U'}, {33, '[', '{'}, {34, 'i', 'I'}, {35, 'p', 'P'}, {37, 'l', 'L'},
    {38, 'j', 'J'}, {39, '\'', '"'}, {40, 'k', 'K'}, {41, ';', ':'}, {42, '\\', '|'}, {43, ',', '<'},
    {44, '/', '?'}, {45, 'n', 'N'}, {46, 'm', 'M'}, {47, '.', '>'}, {50, '`', '~'}, {49, ' ', ' '},
    {36, '\r', '\r'}, {48, '\t', '\t'}, {51, 0x7f, 0x7f}, {53, 0x1b, 0x1b},
};
- (NSString *)charactersByApplyingModifiers:(NSEventModifierFlags)modifiers {
    for (size_t i = 0; i < sizeof bn_us_keys / sizeof *bn_us_keys; i++) {
        if (bn_us_keys[i].code != _keyCode) continue;
        char c = (modifiers & (NSEventModifierFlagShift | NSEventModifierFlagCapsLock)) ? bn_us_keys[i].shifted
                                                                                        : bn_us_keys[i].plain;
        if ((modifiers & NSEventModifierFlagCapsLock) && !(modifiers & NSEventModifierFlagShift) &&
            !(c >= 'A' && c <= 'Z'))
            c = bn_us_keys[i].plain;
        if ((modifiers & NSEventModifierFlagControl) && ((c | 0x20) >= 'a' && (c | 0x20) <= 'z')) c = (char)(c & 0x1f);
        return [NSString stringWithFormat:@"%c", c];
    }
    /* Keys outside the table (arrows, function keys): what the event carries. */
    return self.charactersIgnoringModifiers ?: @"";
}
- (BOOL)isARepeat { return _repeat; }
- (unsigned short)keyCode { return _keyCode; }
- (CGFloat)scrollingDeltaX { return _dx; }
- (CGFloat)scrollingDeltaY { return _dy; }
- (CGFloat)deltaX { return _dx; }
- (CGFloat)deltaY { return _dy; }
- (BOOL)hasPreciseScrollingDeltas { return YES; }
- (NSInteger)buttonNumber {
    switch (_type) {
    case NSEventTypeRightMouseDown: case NSEventTypeRightMouseUp: case NSEventTypeRightMouseDragged: return 1;
    default: return 0;
    }
}
+ (NSPoint)mouseLocation { return mouse_location; }
+ (NSEventModifierFlags)modifierFlags { return current_flags; }
+ (void)_bn_setMouseLocation:(NSPoint)p flags:(NSEventModifierFlags)f {
    mouse_location = p;
    current_flags = f;
}
- (void)_bn_setScrollDeltaX:(CGFloat)dx y:(CGFloat)dy {
    _dx = dx;
    _dy = dy;
}
@end

/* ---- NSColor -------------------------------------------------------------------------- */

@implementation NSColor {
    CGFloat _r, _g, _b, _a;
}
+ (NSColor *)colorWithSRGBRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    NSColor *c = [[self alloc] init];
    c->_r = r; c->_g = g; c->_b = b; c->_a = a;
    return c;
}
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    return [self colorWithSRGBRed:r green:g blue:b alpha:a];
}
+ (NSColor *)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    return [self colorWithSRGBRed:r green:g blue:b alpha:a];
}
+ (NSColor *)colorWithWhite:(CGFloat)w alpha:(CGFloat)a { return [self colorWithSRGBRed:w green:w blue:w alpha:a]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (CGFloat)redComponent { return _r; }
- (CGFloat)greenComponent { return _g; }
- (CGFloat)blueComponent { return _b; }
- (CGFloat)alphaComponent { return _a; }
- (NSColor *)colorWithAlphaComponent:(CGFloat)a { return [NSColor colorWithSRGBRed:_r green:_g blue:_b alpha:a]; }
/* The fixed named colours (the system colours that change with the
 * appearance are in AppKitDynamicColor.m). */
+ (NSColor *)blackColor { return [self colorWithWhite:0 alpha:1]; }
+ (NSColor *)whiteColor { return [self colorWithWhite:1 alpha:1]; }
+ (NSColor *)clearColor { return [self colorWithWhite:0 alpha:0]; }
+ (NSColor *)grayColor { return [self colorWithWhite:0.5 alpha:1]; }
+ (NSColor *)redColor { return [self colorWithSRGBRed:1 green:0 blue:0 alpha:1]; }
+ (NSColor *)greenColor { return [self colorWithSRGBRed:0 green:1 blue:0 alpha:1]; }
+ (NSColor *)blueColor { return [self colorWithSRGBRed:0 green:0 blue:1 alpha:1]; }
+ (NSColor *)controlAccentColor { return [self colorWithSRGBRed:0 green:0.48 blue:1 alpha:1]; }
+ (NSColor *)selectedContentBackgroundColor { return [self controlAccentColor]; }
@end

/* ---- NSFont ------------------------------------------------------------------------------ */

/* NSFont: AppKitFonts.m (toll-free bridged to CTFont). */

/* ---- NSScreen ---------------------------------------------------------------------------------- */

@implementation NSScreen
/* One screen; its size comes from BITTEN_SCREEN=WxH (default 1440x900). */
+ (NSScreen *)mainScreen {
    static NSScreen *main;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        main = [[NSScreen alloc] init];
    });
    return main;
}
+ (NSArray *)screens { return @[ [self mainScreen] ]; }
- (NSRect)frame {
    double w = 1440, h = 900;
    const char *env = getenv("BITTEN_SCREEN");
    if (env) {
        char *x;
        double ew = strtod(env, &x);
        if (*x == 'x') {
            double eh = strtod(x + 1, NULL);
            if (ew > 0 && eh > 0) { w = ew; h = eh; }
        }
    }
    return NSMakeRect(0, 0, w, h);
}
- (NSRect)visibleFrame {
    NSRect f = self.frame;
    f.size.height -= 25; /* menu bar */
    return f;
}
- (CGFloat)backingScaleFactor { return 1; }
@end

/* ---- NSGraphicsContext ------------------------------------------------------------------------ */


/* ---- NSMenu and NSMenuItem ----------------------------------------------------------------------- */

@interface NSMenuItem (BittenOwner)
- (void)_bn_setMenu:(NSMenu *)menu;
@end
@interface NSMenu (BittenOwner)
- (void)_bn_setSupermenu:(NSMenu *)menu;
@end

@implementation NSMenu {
    NSMutableArray *_items;
    __weak NSMenu *_supermenu;
}
/* Items know their menu, and submenus the menu holding them. */
- (void)_bn_adopt:(NSMenuItem *)item {
    [item _bn_setMenu:self];
    [item.submenu _bn_setSupermenu:self];
}
- (void)_bn_release:(NSMenuItem *)item {
    if (item.menu == self) [item _bn_setMenu:nil];
    if (item.submenu.supermenu == self) [item.submenu _bn_setSupermenu:nil];
}
- (void)_bn_setSupermenu:(NSMenu *)menu { _supermenu = menu; }
@synthesize title = _title;
- (instancetype)init { return [self initWithTitle:@""]; }
- (instancetype)initWithTitle:(NSString *)title {
    if ((self = [super init])) {
        _title = [title copy];
        _items = [NSMutableArray array];
    }
    return self;
}
- (NSArray *)itemArray { return [_items copy]; }
- (NSInteger)numberOfItems { return (NSInteger)_items.count; }
- (void)addItem:(NSMenuItem *)item {
    if (!item) return;
    [_items addObject:item];
    [self _bn_adopt:item];
}
- (NSMenuItem *)addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    [self addItem:i];
    return i;
}
- (void)removeAllItems {
    for (NSMenuItem *i in _items) [self _bn_release:i];
    [_items removeAllObjects];
}
- (void)insertItem:(NSMenuItem *)item atIndex:(NSInteger)index {
    if (!item) return;
    [_items insertObject:item atIndex:(NSUInteger)MAX(0, MIN(index, (NSInteger)_items.count))];
    [self _bn_adopt:item];
}
- (void)removeItem:(NSMenuItem *)item {
    if ([_items indexOfObjectIdenticalTo:item] == NSNotFound) return;
    [_items removeObjectIdenticalTo:item];
    [self _bn_release:item];
}
- (void)removeItemAtIndex:(NSInteger)index {
    if (index < 0 || (NSUInteger)index >= _items.count) return;
    NSMenuItem *item = _items[(NSUInteger)index];
    [_items removeObjectAtIndex:(NSUInteger)index];
    [self _bn_release:item];
}
- (NSMenuItem *)itemAtIndex:(NSInteger)index {
    return index >= 0 && (NSUInteger)index < _items.count ? _items[(NSUInteger)index] : nil;
}
- (NSMenuItem *)itemWithTitle:(NSString *)title {
    for (NSMenuItem *i in _items) if ([i.title isEqualToString:title]) return i;
    return nil;
}
- (NSMenuItem *)itemWithTag:(NSInteger)tag {
    for (NSMenuItem *i in _items) if (i.tag == tag) return i;
    return nil;
}
- (NSInteger)indexOfItem:(NSMenuItem *)item {
    NSUInteger i = [_items indexOfObjectIdenticalTo:item];
    return i == NSNotFound ? -1 : (NSInteger)i;
}
- (NSArray<NSMenuItem *> *)items { return [_items copy]; }
- (void)setItems:(NSArray<NSMenuItem *> *)items {
    for (NSMenuItem *i in _items) [self _bn_release:i];
    _items = [items mutableCopy] ?: [NSMutableArray array];
    for (NSMenuItem *i in _items) [self _bn_adopt:i];
}
- (NSMenu *)supermenu { return _supermenu; }
- (void)setSupermenu:(NSMenu *)m { _supermenu = m; }
- (BOOL)autoenablesItems { return YES; }
- (void)setAutoenablesItems:(BOOL)a {}
- (void)update {}
static const NSEventModifierFlags bn_shortcut_mask = NSEventModifierFlagCommand | NSEventModifierFlagShift |
                                                     NSEventModifierFlagOption | NSEventModifierFlagControl;
/* As menus auto-enable their items (AppKit validates them before a key
 * equivalent is matched): an item counts when something handles its
 * action, its target or else the responder chain, and that something's
 * validateMenuItem: (or validateUserInterfaceItem:) agrees. */
static BOOL bn_item_valid(NSMenuItem *item) {
    SEL a = item.action;
    if (!a) return NO;
    id t = item.target;
    if (t && ![t respondsToSelector:a]) return NO;
    if (!t) t = [NSApp targetForAction:a to:nil from:item];
    if (!t) return NO;
    SEL v = @selector(validateMenuItem:);
    if (![t respondsToSelector:v]) v = @selector(validateUserInterfaceItem:);
    if ([t respondsToSelector:v]) return ((BOOL (*)(id, SEL, id))objc_msgSend)(t, v, item);
    return YES;
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) return NO;
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;
    NSEventModifierFlags mods = event.modifierFlags & bn_shortcut_mask;
    for (NSMenuItem *item in [_items copy]) {
        if (item.submenu && [item.submenu performKeyEquivalent:event]) return YES;
        if (!item.keyEquivalent.length || !item.isEnabled || item.isHidden) continue;
        NSString *want = item.keyEquivalent;
        NSEventModifierFlags wantMods = item.keyEquivalentModifierMask & bn_shortcut_mask;
        /* An uppercase key equivalent implies shift. */
        if (![want.lowercaseString isEqualToString:want]) wantMods |= NSEventModifierFlagShift;
        if ([want.lowercaseString isEqualToString:key] && wantMods == mods) {
            if (!bn_item_valid(item)) continue;
            [self performActionForItemAtIndex:[self indexOfItem:item]];
            return YES;
        }
    }
    return NO;
}
- (void)performActionForItemAtIndex:(NSInteger)index {
    NSMenuItem *item = [self itemAtIndex:index];
    if (getenv("BITTEN_EVENT_DEBUG"))
        fprintf(stderr, "bitten: menu '%s' performs item %ld '%s' (%s) action %p target %s\n", self.title.UTF8String ?: "",
                (long)index, item.title.UTF8String ?: "", object_getClassName(item), (void *)item.action,
                item.target ? object_getClassName(item.target) : "nil");
    if (!item.action) return;
    if (item.target) ((void (*)(id, SEL, id))objc_msgSend)(item.target, item.action, item);
    else [NSApp sendAction:item.action to:nil from:item];
}
@end

@implementation NSMenuItem {
    BOOL _disabled, _hidden, _separator;
    __weak NSMenu *_menu;
    NSEventModifierFlags _mask;
    NSInteger _state;
    NSImage *_image;
    NSString *_toolTip;
}
@synthesize title = _title, action = _action, target = _target, keyEquivalent = _keyEquivalent,
            submenu = _submenu, tag = _tag, representedObject = _representedObject;
+ (NSMenuItem *)separatorItem {
    NSMenuItem *i = [[self alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    i->_separator = YES;
    return i;
}
- (instancetype)init { return [self initWithTitle:@"" action:NULL keyEquivalent:@""]; }
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key {
    if ((self = [super init])) {
        _title = [title copy];
        _action = action;
        _keyEquivalent = [key copy];
        _mask = NSEventModifierFlagCommand;
    }
    return self;
}
- (NSMenu *)menu { return _menu; }
- (void)_bn_setMenu:(NSMenu *)menu { _menu = menu; }
- (void)setSubmenu:(NSMenu *)submenu {
    if (_submenu.supermenu == _menu) [_submenu _bn_setSupermenu:nil];
    _submenu = submenu;
    if (_menu) [submenu _bn_setSupermenu:_menu];
}
- (NSEventModifierFlags)keyEquivalentModifierMask { return _mask; }
- (void)setKeyEquivalentModifierMask:(NSEventModifierFlags)m { _mask = m; }
- (BOOL)hasSubmenu { return _submenu != nil; }
- (BOOL)isSeparatorItem { return _separator; }
- (NSInteger)state { return _state; }
- (void)setState:(NSInteger)s { _state = s; }
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)h { _hidden = h; }
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)i { _image = i; }
- (NSString *)toolTip { return _toolTip; }
- (void)setToolTip:(NSString *)t { _toolTip = [t copy]; }
- (BOOL)isEnabled { return !_disabled; }
- (void)setEnabled:(BOOL)e { _disabled = !e; }
@end

/* ---- accessibility ------------------------------------------------------------------------------- */

void NSAccessibilityPostNotification(id element, NSAccessibilityNotificationName notification) {}
void NSAccessibilityPostNotificationWithUserInfo(id element, NSAccessibilityNotificationName notification,
                                                 NSDictionary *userInfo) {}
