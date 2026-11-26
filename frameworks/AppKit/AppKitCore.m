/* AppKit: the application, responders, views, windows, events, colours,
 * fonts, screens and menus. Drawing and the window server come in separately
 * (CoreGraphics, the display); this file keeps the object model and the
 * application life cycle. */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dispatch/dispatch.h>
#include <stdlib.h>

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

@implementation NSView
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
- (void)setFrame:(NSRect)frame {
    _frame = frame;
    _bounds.size = frame.size;
    _needsDisplay = YES;
    id l = self.layer;
    if (l) [l setValue:[NSValue valueWithRect:_bounds] forKey:@"bounds"];
}
- (NSRect)bounds { return _bounds; }
- (void)setBounds:(NSRect)bounds { _bounds = bounds; }
- (NSArray *)subviews { return [_subviews copy]; }
- (NSView *)superview { return _superview; }
- (NSWindow *)window { return _window; }
- (BOOL)needsDisplay { return _needsDisplay; }
- (void)setNeedsDisplay:(BOOL)flag {
    _needsDisplay = flag;
    if (flag) {
        if (_superview) _superview.needsDisplay = YES;
        else [_window _bn_scheduleDisplay];
    }
}
- (void)setNeedsDisplayInRect:(NSRect)rect { self.needsDisplay = YES; }
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
        [l setValue:[NSValue valueWithRect:self.bounds] forKey:@"bounds"];
        [l setValue:@(self.window ? self.window.backingScaleFactor : 1.0) forKey:@"contentsScale"];
    }
    return l;
}
- (CALayer *)layer { return objc_getAssociatedObject(self, @selector(layer)); }
- (void)setLayer:(CALayer *)layer {
    objc_setAssociatedObject(self, @selector(layer), layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (layer) [(id)layer setValue:self forKey:@"delegate"];
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
    [self viewWillMoveToWindow:window];
    _window = window;
    for (NSView *v in _subviews) [v _setWindow:window];
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
 * when `view` is nil), walking up through frames. Flipped views are
 * treated like unflipped ones for now. */
- (NSPoint)_toWindow:(NSPoint)p {
    for (NSView *v = self; v; v = v->_superview) {
        p.x += v->_frame.origin.x - v->_bounds.origin.x;
        p.y += v->_frame.origin.y - v->_bounds.origin.y;
    }
    return p;
}
- (NSPoint)_fromWindow:(NSPoint)p {
    NSPoint origin = [self _toWindow:NSZeroPoint];
    return NSMakePoint(p.x - origin.x, p.y - origin.y);
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
    NSPoint local = NSMakePoint(point.x - _frame.origin.x + _bounds.origin.x,
                                point.y - _frame.origin.y + _bounds.origin.y);
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
static NSUInteger next_window_number = 1;

@implementation NSWindow {
    NSColor *_backgroundColor;
}
@synthesize delegate = _delegate;
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)flag {
    if ((self = [super init])) {
        _styleMask = style;
        _frame = [self frameRectForContentRect:rect];
        _windowNumber = next_window_number++;
        _title = @"";
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
    [_contentView _setWindow:nil];
    _contentView.nextResponder = nil;
    _contentView = view;
    NSRect c = [self contentRectForFrameRect:_frame];
    view.frame = NSMakeRect(0, 0, c.size.width, c.size.height);
    view.nextResponder = self;
    [view _setWindow:self];
}
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t { _title = [t copy]; }
- (NSWindowStyleMask)styleMask { return _styleMask; }
- (void)setStyleMask:(NSWindowStyleMask)m { _styleMask = m; }
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
    BOOL resized = frame.size.width != _frame.size.width || frame.size.height != _frame.size.height;
    _frame = frame;
    NSRect c = [self contentRectForFrameRect:frame];
    _contentView.frame = NSMakeRect(0, 0, c.size.width, c.size.height);
    if (resized) {
        if ([_delegate respondsToSelector:@selector(windowDidResize:)])
            [_delegate windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification
                                                                     object:self userInfo:nil]];
        [self _post:NSWindowDidResizeNotification];
    }
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
    _visible = YES;
    [self display];
}
- (void)makeKeyAndOrderFront:(id)sender {
    for (NSWindow *w in all_windows) w->_key = NO;
    _key = YES;
    [self orderFront:sender];
    [self _post:NSWindowDidBecomeKeyNotification];
}
- (void)orderOut:(id)sender {
    _visible = NO;
    [self _bn_closeDisplay];
}
- (void)close {
    if ([_delegate respondsToSelector:@selector(windowWillClose:)])
        [_delegate windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification
                                                                 object:self userInfo:nil]];
    [self _post:NSWindowWillCloseNotification];
    _visible = NO;
    [self _bn_closeDisplay];
    [all_windows removeObject:self];
}
@end

/* ---- NSApplication --------------------------------------------------------------- */

@implementation NSApplication {
    BOOL _running, _active, _launched;
    NSMenu *_mainMenu;
    NSApplicationActivationPolicy _policy;
}
@synthesize delegate = _delegate, appearance = _appearance;
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
- (NSWindow *)mainWindow { return self.keyWindow; }
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
- (NSEvent *)nextEventMatchingMask:(NSEventMask)mask untilDate:(NSDate *)expiration
                            inMode:(NSRunLoopMode)mode dequeue:(BOOL)deqFlag {
    return nil;
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
/* The named colours of the light appearance. */
+ (NSColor *)blackColor { return [self colorWithWhite:0 alpha:1]; }
+ (NSColor *)whiteColor { return [self colorWithWhite:1 alpha:1]; }
+ (NSColor *)clearColor { return [self colorWithWhite:0 alpha:0]; }
+ (NSColor *)grayColor { return [self colorWithWhite:0.5 alpha:1]; }
+ (NSColor *)redColor { return [self colorWithSRGBRed:1 green:0 blue:0 alpha:1]; }
+ (NSColor *)greenColor { return [self colorWithSRGBRed:0 green:1 blue:0 alpha:1]; }
+ (NSColor *)blueColor { return [self colorWithSRGBRed:0 green:0 blue:1 alpha:1]; }
+ (NSColor *)labelColor { return [self colorWithWhite:0 alpha:0.85]; }
+ (NSColor *)secondaryLabelColor { return [self colorWithWhite:0 alpha:0.5]; }
+ (NSColor *)textColor { return [self blackColor]; }
+ (NSColor *)textBackgroundColor { return [self whiteColor]; }
+ (NSColor *)windowBackgroundColor { return [self colorWithWhite:0.93 alpha:1]; }
+ (NSColor *)controlBackgroundColor { return [self whiteColor]; }
+ (NSColor *)controlAccentColor { return [self colorWithSRGBRed:0 green:0.48 blue:1 alpha:1]; }
+ (NSColor *)separatorColor { return [self colorWithWhite:0 alpha:0.1]; }
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

@implementation NSMenu {
    NSMutableArray *_items;
}
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
- (void)addItem:(NSMenuItem *)item { [_items addObject:item]; }
- (NSMenuItem *)addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    [self addItem:i];
    return i;
}
- (void)removeAllItems { [_items removeAllObjects]; }
- (void)insertItem:(NSMenuItem *)item atIndex:(NSInteger)index {
    [_items insertObject:item atIndex:(NSUInteger)MAX(0, MIN(index, (NSInteger)_items.count))];
}
- (void)removeItem:(NSMenuItem *)item { [_items removeObjectIdenticalTo:item]; }
- (void)removeItemAtIndex:(NSInteger)index {
    if (index >= 0 && (NSUInteger)index < _items.count) [_items removeObjectAtIndex:(NSUInteger)index];
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
- (void)setItems:(NSArray<NSMenuItem *> *)items { _items = [items mutableCopy]; }
- (NSMenu *)supermenu { return nil; }
- (void)setSupermenu:(NSMenu *)m {}
- (BOOL)autoenablesItems { return YES; }
- (void)setAutoenablesItems:(BOOL)a {}
- (void)update {}
static const NSEventModifierFlags bn_shortcut_mask = NSEventModifierFlagCommand | NSEventModifierFlagShift |
                                                     NSEventModifierFlagOption | NSEventModifierFlagControl;
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
            [self performActionForItemAtIndex:[self indexOfItem:item]];
            return YES;
        }
    }
    return NO;
}
- (void)performActionForItemAtIndex:(NSInteger)index {
    NSMenuItem *item = [self itemAtIndex:index];
    if (!item.action) return;
    if (item.target) ((void (*)(id, SEL, id))objc_msgSend)(item.target, item.action, item);
    else [NSApp sendAction:item.action to:nil from:item];
}
@end

@implementation NSMenuItem {
    BOOL _disabled, _hidden;
    NSEventModifierFlags _mask;
    NSInteger _state;
    NSImage *_image;
    NSString *_toolTip;
}
@synthesize title = _title, action = _action, target = _target, keyEquivalent = _keyEquivalent,
            submenu = _submenu, tag = _tag, representedObject = _representedObject;
+ (NSMenuItem *)separatorItem { return [[self alloc] initWithTitle:@"" action:NULL keyEquivalent:@""]; }
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
- (NSMenu *)menu { return nil; }
- (NSEventModifierFlags)keyEquivalentModifierMask { return _mask; }
- (void)setKeyEquivalentModifierMask:(NSEventModifierFlags)m { _mask = m; }
- (BOOL)hasSubmenu { return _submenu != nil; }
- (BOOL)isSeparatorItem { return !_title.length && !_action && !_submenu; }
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
