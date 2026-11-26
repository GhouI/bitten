/* AppKit: the application, responders, views, windows, events, colours,
 * fonts, screens and menus. Drawing and the window server come in separately
 * (CoreGraphics, the display); this file keeps the object model and the
 * application life cycle. */
#import <AppKit/AppKit.h>
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
- (void)setWantsLayer:(BOOL)flag { _wantsLayer = flag; }
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
/* The main thread belongs to the main dispatch queue from here on: window
 * server events, timers and Swift's MainActor all arrive there as blocks. */
- (void)run {
    _running = YES;
    [self finishLaunching];
    dispatch_main();
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

@implementation NSFont {
    NSString *_name;
    CGFloat _size;
}
+ (NSFont *)fontWithName:(NSString *)name size:(CGFloat)size {
    NSFont *f = [[self alloc] init];
    f->_name = [name copy];
    f->_size = size > 0 ? size : [self systemFontSize];
    return f;
}
+ (NSFont *)systemFontOfSize:(CGFloat)size { return [self fontWithName:@".AppleSystemUIFont" size:size]; }
+ (NSFont *)systemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return [self fontWithName:weight >= NSFontWeightSemibold ? @".AppleSystemUIFontBold" : @".AppleSystemUIFont"
                         size:size];
}
+ (NSFont *)boldSystemFontOfSize:(CGFloat)size { return [self fontWithName:@".AppleSystemUIFontBold" size:size]; }
+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return [self fontWithName:@".AppleSystemUIFontMonospaced" size:size];
}
+ (NSFont *)userFixedPitchFontOfSize:(CGFloat)size { return [self fontWithName:@"Menlo-Regular" size:size]; }
+ (CGFloat)systemFontSize { return 13; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)fontName { return _name; }
- (CGFloat)pointSize { return _size; }
/* Metrics in the proportions of common UI fonts until real fonts load. */
- (CGFloat)ascender { return _size * 0.95; }
- (CGFloat)descender { return -_size * 0.25; }
- (CGFloat)leading { return 0; }
@end

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
@end

@implementation NSMenuItem {
    BOOL _disabled;
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
    }
    return self;
}
- (BOOL)isEnabled { return !_disabled; }
- (void)setEnabled:(BOOL)e { _disabled = !e; }
@end

/* ---- accessibility ------------------------------------------------------------------------------- */

void NSAccessibilityPostNotification(id element, NSAccessibilityNotificationName notification) {}
void NSAccessibilityPostNotificationWithUserInfo(id element, NSAccessibilityNotificationName notification,
                                                 NSDictionary *userInfo) {}
