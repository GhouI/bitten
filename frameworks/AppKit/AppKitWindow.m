/* The rest of NSWindow's state: titlebar and tabbing options, levels,
 * collection behaviour, size limits, frame autosave (in user defaults, as
 * AppKit keeps it), sheets, child windows, and conversions to the screen.
 * There is one screen and no window server stacking, so most of this is
 * state that reads back as set; sizes and frames are honoured. */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <float.h>
#include <stdio.h>
#include <stdlib.h>

void bn_debug_callers(void); /* AppKitCore.m */

static BOOL allows_tabbing = YES;
static const char props_key;

/* Per-window values, keyed by property name. */
static NSMutableDictionary *props(NSWindow *w) {
    NSMutableDictionary *d = objc_getAssociatedObject(w, &props_key);
    if (!d) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(w, &props_key, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return d;
}
static id get(NSWindow *w, NSString *k) { return props(w)[k]; }
static void set(NSWindow *w, NSString *k, id v) {
    if (v) props(w)[k] = v;
    else [props(w) removeObjectForKey:k];
}
static BOOL getb(NSWindow *w, NSString *k, BOOL dflt) {
    NSNumber *n = get(w, k);
    return n ? n.boolValue : dflt;
}
static NSInteger geti(NSWindow *w, NSString *k, NSInteger dflt) {
    NSNumber *n = get(w, k);
    return n ? n.integerValue : dflt;
}
static NSSize gets(NSWindow *w, NSString *k, NSSize dflt) {
    NSValue *v = get(w, k);
    return v ? v.sizeValue : dflt;
}

#define BOOL_PROP(getter, setter, key, dflt)                                   \
    -(BOOL)getter { return getb(self, @key, dflt); }                           \
    -(void)setter:(BOOL)v { set(self, @key, @(v)); }
#define INT_PROP(type, getter, setter, key, dflt)                              \
    -(type)getter { return (type)geti(self, @key, (NSInteger)(dflt)); }        \
    -(void)setter:(type)v { set(self, @key, @((NSInteger)v)); }
#define OBJ_PROP(type, getter, setter, key)                                    \
    -(type)getter { return get(self, @key); }                                  \
    -(void)setter:(type)v { set(self, @key, v); }
#define SIZE_PROP(getter, setter, key, dflt)                                   \
    -(NSSize)getter { return gets(self, @key, dflt); }                         \
    -(void)setter:(NSSize)v { set(self, @key, [NSValue valueWithSize:v]); }

static NSString *autosave_key(NSString *name) { return [@"NSWindow Frame " stringByAppendingString:name]; }

@implementation NSWindow (BittenWindowState)
+ (BOOL)allowsAutomaticWindowTabbing { return allows_tabbing; }
+ (void)setAllowsAutomaticWindowTabbing:(BOOL)allows { allows_tabbing = allows; }
+ (NSWindowUserTabbingPreference)userTabbingPreference { return NSWindowUserTabbingPreferenceManual; }

INT_PROP(NSWindowTabbingMode, tabbingMode, setTabbingMode, "tabbingMode", NSWindowTabbingModeAutomatic)
- (NSWindowTabbingIdentifier)tabbingIdentifier { return get(self, @"tabbingIdentifier") ?: @""; }
- (void)setTabbingIdentifier:(NSWindowTabbingIdentifier)v { set(self, @"tabbingIdentifier", [v copy]); }
INT_PROP(NSWindowTitleVisibility, titleVisibility, setTitleVisibility, "titleVisibility", NSWindowTitleVisible)
BOOL_PROP(titlebarAppearsTransparent, setTitlebarAppearsTransparent, "titlebarAppearsTransparent", NO)
INT_PROP(NSTitlebarSeparatorStyle, titlebarSeparatorStyle, setTitlebarSeparatorStyle, "titlebarSeparatorStyle",
         NSTitlebarSeparatorStyleAutomatic)
INT_PROP(NSWindowToolbarStyle, toolbarStyle, setToolbarStyle, "toolbarStyle", NSWindowToolbarStyleAutomatic)
OBJ_PROP(NSToolbar *, toolbar, setToolbar, "toolbar")
- (NSString *)subtitle { return get(self, @"subtitle") ?: @""; }
- (void)setSubtitle:(NSString *)v { set(self, @"subtitle", [v copy]); }
INT_PROP(NSWindowCollectionBehavior, collectionBehavior, setCollectionBehavior, "collectionBehavior",
         NSWindowCollectionBehaviorDefault)
INT_PROP(NSWindowLevel, level, setLevel, "level", NSNormalWindowLevel)
BOOL_PROP(isOpaque, setOpaque, "opaque", YES)
BOOL_PROP(hasShadow, setHasShadow, "hasShadow", YES)
- (CGFloat)alphaValue {
    NSNumber *n = get(self, @"alphaValue");
    return n ? n.doubleValue : 1.0;
}
- (void)setAlphaValue:(CGFloat)v {
    CGFloat old = self.alphaValue;
    set(self, @"alphaValue", @(v));
    if (getenv("BITTEN_EVENT_DEBUG") && old != v) {
        fprintf(stderr, "bitten: window %s alpha %g -> %g visible %d from", object_getClassName(self), old, v, self.isVisible);
        bn_debug_callers();
    }
    /* a window that became (in)visible this way is shown or taken away */
    if ((old <= 0) != (v <= 0) && self.isVisible) [self _bn_scheduleDisplay];
}
BOOL_PROP(isMovable, setMovable, "movable", YES)
BOOL_PROP(isMovableByWindowBackground, setMovableByWindowBackground, "movableByWindowBackground", NO)
BOOL_PROP(isReleasedWhenClosed, setReleasedWhenClosed, "releasedWhenClosed", YES)
BOOL_PROP(hidesOnDeactivate, setHidesOnDeactivate, "hidesOnDeactivate", NO)
BOOL_PROP(canHide, setCanHide, "canHide", YES)
BOOL_PROP(autorecalculatesKeyViewLoop, setAutorecalculatesKeyViewLoop, "autorecalculatesKeyViewLoop", NO)
BOOL_PROP(allowsToolTipsWhenApplicationIsInactive, setAllowsToolTipsWhenApplicationIsInactive,
          "allowsToolTipsWhenApplicationIsInactive", NO)
BOOL_PROP(ignoresMouseEvents, setIgnoresMouseEvents, "ignoresMouseEvents", NO)
BOOL_PROP(acceptsMouseMovedEvents, setAcceptsMouseMovedEvents, "acceptsMouseMovedEvents", NO)
BOOL_PROP(isExcludedFromWindowsMenu, setExcludedFromWindowsMenu, "excludedFromWindowsMenu", NO)
BOOL_PROP(isRestorable, setRestorable, "restorable", YES)
BOOL_PROP(isDocumentEdited, setDocumentEdited, "documentEdited", NO)
BOOL_PROP(preventsApplicationTerminationWhenModal, setPreventsApplicationTerminationWhenModal,
          "preventsApplicationTerminationWhenModal", YES)
BOOL_PROP(viewsNeedDisplay, setViewsNeedDisplay, "viewsNeedDisplay", NO)
- (NSURL *)representedURL { return get(self, @"representedURL"); }
- (void)setRepresentedURL:(NSURL *)v { set(self, @"representedURL", [v copy]); }
- (NSUserInterfaceItemIdentifier)identifier { return get(self, @"identifier"); }
- (void)setIdentifier:(NSUserInterfaceItemIdentifier)v { set(self, @"identifier", [v copy]); }
INT_PROP(NSWindowAnimationBehavior, animationBehavior, setAnimationBehavior, "animationBehavior",
         NSWindowAnimationBehaviorDefault)
INT_PROP(NSWindowSharingType, sharingType, setSharingType, "sharingType", NSWindowSharingReadOnly)
SIZE_PROP(minSize, setMinSize, "minSize", NSMakeSize(0, 0))
SIZE_PROP(maxSize, setMaxSize, "maxSize", NSMakeSize(FLT_MAX, FLT_MAX))
SIZE_PROP(contentMinSize, setContentMinSize, "contentMinSize", NSMakeSize(0, 0))
SIZE_PROP(contentMaxSize, setContentMaxSize, "contentMaxSize", NSMakeSize(FLT_MAX, FLT_MAX))
SIZE_PROP(aspectRatio, setAspectRatio, "aspectRatio", NSMakeSize(0, 0))
SIZE_PROP(contentAspectRatio, setContentAspectRatio, "contentAspectRatio", NSMakeSize(0, 0))
SIZE_PROP(resizeIncrements, setResizeIncrements, "resizeIncrements", NSMakeSize(1, 1))
- (NSRect)contentLayoutRect {
    NSRect c = [self contentRectForFrameRect:self.frame];
    return NSMakeRect(0, 0, c.size.width, c.size.height);
}
- (NSView *)initialFirstResponder { return [get(self, @"initialFirstResponder") pointerValue]; }
- (void)setInitialFirstResponder:(NSView *)v { set(self, @"initialFirstResponder", [NSValue valueWithPointer:(__bridge void *)v]); }
- (NSWindowController *)windowController { return [get(self, @"windowController") pointerValue]; }
- (void)setWindowController:(NSWindowController *)c {
    set(self, @"windowController", [NSValue valueWithPointer:(__bridge void *)c]);
}

/* ---- frame autosave ---- */
- (NSWindowFrameAutosaveName)frameAutosaveName { return get(self, @"frameAutosaveName") ?: @""; }
- (BOOL)setFrameAutosaveName:(NSWindowFrameAutosaveName)name {
    set(self, @"frameAutosaveName", [name copy]);
    if (name.length) [self setFrameUsingName:name];
    return YES;
}
- (BOOL)setFrameUsingName:(NSWindowFrameAutosaveName)name force:(BOOL)force {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:autosave_key(name)];
    if (!saved) return NO;
    double x, y, w, h;
    if (sscanf(saved.UTF8String, "%lf %lf %lf %lf", &x, &y, &w, &h) != 4) return NO;
    [self setFrame:NSMakeRect(x, y, w, h) display:YES];
    return YES;
}
- (BOOL)setFrameUsingName:(NSWindowFrameAutosaveName)name { return [self setFrameUsingName:name force:NO]; }
- (void)saveFrameUsingName:(NSWindowFrameAutosaveName)name {
    NSRect f = self.frame;
    NSString *s = [NSString stringWithFormat:@"%g %g %g %g 0 0 1440 875 ", f.origin.x, f.origin.y, f.size.width,
                                             f.size.height];
    [[NSUserDefaults standardUserDefaults] setObject:s forKey:autosave_key(name)];
}

/* ---- ordering ---- */
- (BOOL)canBecomeKeyWindow { return (self.styleMask & NSWindowStyleMaskTitled) != 0 || self.styleMask == 0; }
- (BOOL)canBecomeMainWindow { return self.canBecomeKeyWindow; }
- (void)makeKeyWindow { [self makeKeyAndOrderFront:nil]; }
- (void)becomeKeyWindow {}
- (void)resignKeyWindow {}
- (void)orderFrontRegardless { [self orderFront:nil]; }
- (void)orderBack:(id)sender { [self orderFront:sender]; }
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin {
    if (place == NSWindowOut) [self orderOut:nil];
    else [self orderFront:nil];
}
- (NSInteger)orderedIndex { return [[NSApp windows] indexOfObjectIdenticalTo:self]; }
- (BOOL)isMiniaturized { return getb(self, @"miniaturized", NO); }
- (BOOL)isZoomed { return getb(self, @"zoomed", NO); }
/* Miniaturized, a window is hidden and the display shows it as a chip
 * (style flag 128) that brings it back. */
- (void)miniaturize:(id)sender {
    if (self.isMiniaturized) return;
    [self _post:NSWindowWillMiniaturizeNotification];
    set(self, @"miniaturized", @YES);
    [self _bn_hideKeepingDisplay];
    [self _bn_sendStyle];
    if ([self.delegate respondsToSelector:@selector(windowDidMiniaturize:)])
        [(id)self.delegate performSelector:@selector(windowDidMiniaturize:) withObject:[NSNotification notificationWithName:NSWindowDidMiniaturizeNotification
                                                                               object:self userInfo:nil]];
    [self _post:NSWindowDidMiniaturizeNotification];
}
- (void)deminiaturize:(id)sender {
    if (!self.isMiniaturized) return;
    set(self, @"miniaturized", @NO);
    [self makeKeyAndOrderFront:sender];
    [self _bn_sendStyle];
    if ([self.delegate respondsToSelector:@selector(windowDidDeminiaturize:)])
        [(id)self.delegate performSelector:@selector(windowDidDeminiaturize:) withObject:[NSNotification notificationWithName:NSWindowDidDeminiaturizeNotification
                                                                                 object:self userInfo:nil]];
    [self _post:NSWindowDidDeminiaturizeNotification];
}
- (void)performMiniaturize:(id)sender { [self miniaturize:sender]; }
- (void)zoom:(id)sender {
    if (self.isZoomed) {
        NSValue *was = get(self, @"unzoomedFrame");
        if (was) [self setFrame:was.rectValue display:YES];
        set(self, @"zoomed", @NO);
    } else {
        set(self, @"unzoomedFrame", [NSValue valueWithRect:self.frame]);
        [self setFrame:[NSScreen mainScreen].visibleFrame display:YES];
        set(self, @"zoomed", @YES);
    }
}
- (void)performZoom:(id)sender { [self zoom:sender]; }
- (void)toggleFullScreen:(id)sender { [self zoom:sender]; }
- (void)toggleToolbarShown:(id)sender {}
- (NSButton *)standardWindowButton:(NSWindowButton)b {
    if (!(self.styleMask & NSWindowStyleMaskTitled)) return nil;
    NSString *k = [NSString stringWithFormat:@"button%lu", (unsigned long)b];
    NSButton *button = get(self, k);
    if (!button) {
        /* Where the display page draws the window's buttons: 12-point dots
         * 20 points apart from 10 points in, centred in the 28-point title
         * bar (frames in title bar coordinates, origin bottom left). */
        CGFloat x = b <= NSWindowZoomButton ? 9 + 20 * (CGFloat)b : 0;
        button = [[NSButton alloc] initWithFrame:NSMakeRect(x, 6, 14, 16)];
        button.bordered = NO;
        button.title = @"";
        set(self, k, button);
    }
    return button;
}
/* A title-bar button made on its own (for a custom title bar). */
+ (NSButton *)standardWindowButton:(NSWindowButton)b forStyleMask:(NSWindowStyleMask)styleMask {
    if (b > NSWindowZoomButton && b != NSWindowDocumentIconButton && b != NSWindowDocumentVersionsButton) return nil;
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 14, 16)];
    button.bordered = NO;
    button.title = @"";
    if (b == NSWindowMiniaturizeButton && !(styleMask & NSWindowStyleMaskMiniaturizable)) button.enabled = NO;
    if (b == NSWindowCloseButton && !(styleMask & NSWindowStyleMaskClosable)) button.enabled = NO;
    if (b == NSWindowZoomButton && !(styleMask & NSWindowStyleMaskResizable)) button.enabled = NO;
    return button;
}

/* ---- frames ---- */
- (void)setFrameOrigin:(NSPoint)point {
    NSRect f = self.frame;
    f.origin = point;
    [self setFrame:f display:NO];
}
- (void)setFrameTopLeftPoint:(NSPoint)point {
    NSRect f = self.frame;
    f.origin = NSMakePoint(point.x, point.y - f.size.height);
    [self setFrame:f display:NO];
}
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)topLeftPoint {
    NSRect f = self.frame;
    if (topLeftPoint.x == 0 && topLeftPoint.y == 0) return NSMakePoint(f.origin.x, NSMaxY(f));
    [self setFrameTopLeftPoint:topLeftPoint];
    return NSMakePoint(topLeftPoint.x + 20, topLeftPoint.y - 20);
}
- (void)setFrame:(NSRect)frameRect display:(BOOL)displayFlag animate:(BOOL)animateFlag {
    [self setFrame:frameRect display:displayFlag];
}
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen {
    NSRect s = (screen ?: [NSScreen mainScreen]).visibleFrame;
    if (NSMaxY(frameRect) > NSMaxY(s)) frameRect.origin.y = NSMaxY(s) - frameRect.size.height;
    return frameRect;
}
- (NSScreen *)screen { return [NSScreen mainScreen]; }
- (CGFloat)backingScaleFactor { return [NSScreen mainScreen].backingScaleFactor ?: 1; }
- (NSRect)convertRectToScreen:(NSRect)rect {
    return NSOffsetRect(rect, self.frame.origin.x, self.frame.origin.y);
}
- (NSRect)convertRectFromScreen:(NSRect)rect {
    return NSOffsetRect(rect, -self.frame.origin.x, -self.frame.origin.y);
}
- (NSPoint)convertPointToScreen:(NSPoint)p {
    return NSMakePoint(p.x + self.frame.origin.x, p.y + self.frame.origin.y);
}
- (NSPoint)convertPointFromScreen:(NSPoint)p {
    return NSMakePoint(p.x - self.frame.origin.x, p.y - self.frame.origin.y);
}
- (NSRect)convertRectToBacking:(NSRect)rect {
    CGFloat s = self.backingScaleFactor;
    return NSMakeRect(rect.origin.x * s, rect.origin.y * s, rect.size.width * s, rect.size.height * s);
}
- (NSRect)convertRectFromBacking:(NSRect)rect {
    CGFloat s = self.backingScaleFactor;
    return NSMakeRect(rect.origin.x / s, rect.origin.y / s, rect.size.width / s, rect.size.height / s);
}
/* Where the mouse is now, in the window's coordinates. */
- (NSPoint)mouseLocationOutsideOfEventStream { return [self convertPointFromScreen:[NSEvent mouseLocation]]; }

/* ---- sheets: shown as a window over this one ---- */
- (void)beginSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse))handler {
    NSMutableArray *sheets = get(self, @"sheets") ?: [NSMutableArray array];
    [sheets addObject:sheet];
    set(self, @"sheets", sheets);
    set(sheet, @"sheetParent", [NSValue valueWithPointer:(__bridge void *)self]);
    if (handler) set(sheet, @"sheetHandler", [handler copy]);
    NSRect f = self.frame, s = sheet.frame;
    [sheet setFrameOrigin:NSMakePoint(f.origin.x + (f.size.width - s.size.width) / 2, NSMaxY(f) - s.size.height - 28)];
    [sheet makeKeyAndOrderFront:nil];
}
- (void)beginCriticalSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse))handler {
    [self beginSheet:sheet completionHandler:handler];
}
- (void)endSheet:(NSWindow *)sheet returnCode:(NSModalResponse)code {
    [(NSMutableArray *)get(self, @"sheets") removeObjectIdenticalTo:sheet];
    void (^handler)(NSModalResponse) = get(sheet, @"sheetHandler");
    set(sheet, @"sheetHandler", nil);
    set(sheet, @"sheetParent", nil);
    [sheet orderOut:nil];
    [self makeKeyAndOrderFront:nil];
    if (handler) handler(code);
}
- (void)endSheet:(NSWindow *)sheet { [self endSheet:sheet returnCode:NSModalResponseStop]; }
- (NSWindow *)attachedSheet { return [get(self, @"sheets") lastObject]; }
- (NSArray<NSWindow *> *)sheets { return [get(self, @"sheets") copy] ?: @[]; }
- (NSWindow *)sheetParent { return [get(self, @"sheetParent") pointerValue]; }
- (BOOL)isSheet { return self.sheetParent != nil; }

/* ---- child windows ---- */
- (NSWindow *)parentWindow { return [get(self, @"parentWindow") pointerValue]; }
- (void)setParentWindow:(NSWindow *)w { set(self, @"parentWindow", w ? [NSValue valueWithPointer:(__bridge void *)w] : nil); }
- (NSArray<NSWindow *> *)childWindows { return [get(self, @"childWindows") copy] ?: @[]; }
- (void)addChildWindow:(NSWindow *)child ordered:(NSWindowOrderingMode)place {
    NSMutableArray *children = get(self, @"childWindows") ?: [NSMutableArray array];
    if ([children indexOfObjectIdenticalTo:child] == NSNotFound) [children addObject:child];
    set(self, @"childWindows", children);
    child.parentWindow = self;
    [child orderFront:nil];
}
- (void)removeChildWindow:(NSWindow *)child {
    [(NSMutableArray *)get(self, @"childWindows") removeObjectIdenticalTo:child];
    child.parentWindow = nil;
}

/* ---- titlebar accessories and tabs ---- */
- (NSArray *)titlebarAccessoryViewControllers { return [get(self, @"accessories") copy] ?: @[]; }
- (void)setTitlebarAccessoryViewControllers:(NSArray *)a { set(self, @"accessories", [a mutableCopy]); }
- (void)addTitlebarAccessoryViewController:(NSTitlebarAccessoryViewController *)vc {
    NSMutableArray *a = get(self, @"accessories") ?: [NSMutableArray array];
    [a addObject:vc];
    set(self, @"accessories", a);
}
- (void)removeTitlebarAccessoryViewControllerAtIndex:(NSInteger)index {
    NSMutableArray *a = get(self, @"accessories");
    if (index >= 0 && (NSUInteger)index < a.count) [a removeObjectAtIndex:(NSUInteger)index];
}
- (NSArray<NSWindow *> *)tabbedWindows { return nil; }
- (void)addTabbedWindow:(NSWindow *)window ordered:(NSWindowOrderingMode)ordered { [window orderFront:nil]; }
- (void)selectNextTab:(id)sender {}
- (void)selectPreviousTab:(id)sender {}
- (void)mergeAllWindows:(id)sender {}
- (void)invalidateShadow {}
- (void)update {}
@end
