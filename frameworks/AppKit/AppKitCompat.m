/* Smaller AppKit API that programs call in passing: view geometry hooks,
 * window and event queries, sheets presented by view controllers, string
 * drawing variants. Where an answer depends on things that do not exist
 * here (Spaces, live resizing, force touch, the window server's other
 * windows), these give the answer of a window that is on the active
 * Space, not being resized, under a plain mouse. */
#import <AppKit/AppKit.h>
#include <objc/message.h>
#include <objc/runtime.h>

/* ---- views ---- */

@implementation NSView (BittenCompat)
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0, 0, 0, 0); }
- (NSRect)alignmentRectForFrame:(NSRect)frame {
    NSEdgeInsets i = self.alignmentRectInsets;
    return NSMakeRect(frame.origin.x + i.left, frame.origin.y + i.bottom, frame.size.width - i.left - i.right,
                      frame.size.height - i.top - i.bottom);
}
- (NSRect)frameForAlignmentRect:(NSRect)rect {
    NSEdgeInsets i = self.alignmentRectInsets;
    return NSMakeRect(rect.origin.x - i.left, rect.origin.y - i.bottom, rect.size.width + i.left + i.right,
                      rect.size.height + i.top + i.bottom);
}
- (BOOL)autoresizesSubviews {
    NSNumber *n = objc_getAssociatedObject(self, @selector(autoresizesSubviews));
    return n ? n.boolValue : YES;
}
- (void)setAutoresizesSubviews:(BOOL)b {
    objc_setAssociatedObject(self, @selector(autoresizesSubviews), @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)canBecomeKeyView { return self.acceptsFirstResponder && !self.isHidden; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)viewDidMoveToSuperview {}
- (void)viewDidHide {}
- (void)viewDidUnhide {}
- (void)viewWillStartLiveResize {}
- (void)viewDidEndLiveResize {}
- (NSMenu *)menuForEvent:(NSEvent *)event { return self.menu; }
- (NSMenuItem *)enclosingMenuItem { return nil; }
- (BOOL)autoscroll:(NSEvent *)event { return NO; }
- (NSPoint)convertPointToLayer:(NSPoint)p { return p; }
- (NSPoint)convertPointFromLayer:(NSPoint)p { return p; }
- (void)quickLookWithEvent:(NSEvent *)event {}
- (void)prepareForReuse {}
@end

@implementation NSControl (BittenCompat)
/* The size the control wants within `size` (its fitting size). */
- (NSSize)sizeThatFits:(NSSize)size {
    NSSize s = self.fittingSize;
    return NSMakeSize(MIN(s.width, size.width), MIN(s.height, size.height));
}
@end

@implementation NSResponder (BittenCompat)
- (void)mouseEntered:(NSEvent *)event { [self.nextResponder mouseEntered:event]; }
- (void)mouseExited:(NSEvent *)event { [self.nextResponder mouseExited:event]; }
- (void)otherMouseDown:(NSEvent *)event { [self.nextResponder otherMouseDown:event]; }
- (void)otherMouseUp:(NSEvent *)event { [self.nextResponder otherMouseUp:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self.nextResponder otherMouseDragged:event]; }
- (void)cursorUpdate:(NSEvent *)event { [self.nextResponder cursorUpdate:event]; }
- (void)quickLookWithEvent:(NSEvent *)event { [self.nextResponder quickLookWithEvent:event]; }
- (NSUndoManager *)undoManager { return self.nextResponder.undoManager; }
@end

/* ---- windows ---- */

@implementation NSWindow (BittenCompat)
- (BOOL)inLiveResize { return [objc_getAssociatedObject(self, @selector(inLiveResize)) boolValue]; }
- (BOOL)isOnActiveSpace { return YES; }
- (NSSize)contentResizeIncrements {
    NSValue *v = objc_getAssociatedObject(self, @selector(contentResizeIncrements));
    return v ? v.sizeValue : NSMakeSize(1, 1);
}
- (void)setContentResizeIncrements:(NSSize)s {
    objc_setAssociatedObject(self, @selector(contentResizeIncrements), [NSValue valueWithSize:s],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)performWindowDragWithEvent:(NSEvent *)event {}
- (void)disableCursorRects {}
- (void)enableCursorRects {}
- (void)invalidateCursorRectsForView:(NSView *)view {}
- (void)selectNextKeyView:(id)sender {}
- (void)selectPreviousKeyView:(id)sender {}
/* Each window keeps its own undo manager unless its delegate supplies one. */
- (NSUndoManager *)undoManager {
    id<NSWindowDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(windowWillReturnUndoManager:)]) {
        NSUndoManager *u = ((NSUndoManager * (*)(id, SEL, NSWindow *))objc_msgSend)(
            d, @selector(windowWillReturnUndoManager:), self);
        if (u) return u;
    }
    NSUndoManager *u = objc_getAssociatedObject(self, @selector(undoManager));
    if (!u) {
        u = [NSUndoManager new];
        objc_setAssociatedObject(self, @selector(undoManager), u, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return u;
}
/* "x y w h sx sy sw sh": the frame and the screen it was on. */
- (NSString *)stringWithSavedFrame {
    NSRect f = self.frame, s = self.screen ? self.screen.frame : [NSScreen mainScreen].frame;
    return [NSString stringWithFormat:@"%.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f ", f.origin.x, f.origin.y, f.size.width,
                                      f.size.height, s.origin.x, s.origin.y, s.size.width, s.size.height];
}
- (void)setFrameFromString:(NSString *)string {
    NSArray *parts = [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
        componentsSeparatedByString:@" "];
    if (parts.count < 4) return;
    NSRect f = NSMakeRect([parts[0] doubleValue], [parts[1] doubleValue], [parts[2] doubleValue], [parts[3] doubleValue]);
    if (f.size.width > 0 && f.size.height > 0) [self setFrame:f display:YES];
}
/* The topmost of our windows under a screen point. */
+ (NSInteger)windowNumberAtPoint:(NSPoint)point belowWindowWithWindowNumber:(NSInteger)below {
    BOOL past = below == 0;
    for (NSWindow *w in [NSApp orderedWindows]) {
        if (!past) {
            past = w.windowNumber == below;
            continue;
        }
        if (w.isVisible && NSPointInRect(point, w.frame)) return w.windowNumber;
    }
    return 0;
}
@end

/* ---- events ---- */

@implementation NSEvent (BittenCompat)
/* Buttons held down now (bit 0 left, bit 1 right), from the events the
 * display has delivered (AppKitEvents.m). */
NSUInteger bn_pressed_buttons;
+ (NSUInteger)pressedMouseButtons { return bn_pressed_buttons; }
+ (NSTimeInterval)doubleClickInterval { return 0.4; }
+ (NSTimeInterval)keyRepeatDelay { return 0.5; }
+ (NSTimeInterval)keyRepeatInterval { return 0.05; }
+ (NSEvent *)eventWithCGEvent:(CGEventRef)event { return nil; }
+ (void)startPeriodicEventsAfterDelay:(NSTimeInterval)delay withPeriod:(NSTimeInterval)period {}
+ (void)stopPeriodicEvents {}
- (CGEventRef)CGEvent { return NULL; }
- (NSInteger)eventNumber { return 0; }
- (float)pressure {
    switch (self.type) {
    case NSEventTypeLeftMouseDown: case NSEventTypeLeftMouseDragged:
    case NSEventTypeRightMouseDown: case NSEventTypeRightMouseDragged: return 1;
    default: return 0;
    }
}
/* Scroll gestures: a wheel here has no phases or momentum. */
- (NSUInteger)phase { return 0; }
- (NSUInteger)momentumPhase { return 0; }
- (BOOL)isDirectionInvertedFromDevice { return NO; }
/* Tracking loops need events delivered while the caller waits; here the
 * loop ends at once, as if the mouse had been released. */
- (void)trackSwipeEventWithOptions:(NSUInteger)options dampenAmountThresholdMin:(CGFloat)minDampenThreshold
                               max:(CGFloat)maxDampenThreshold
                      usingHandler:(void (^)(CGFloat, NSUInteger, BOOL, BOOL *))handler {}
@end

/* ---- view controllers presented as sheets ---- */

static const char kPresentingKey, kSheetWindowKey;

@implementation NSViewController (BittenCompat)
- (NSViewController *)presentingViewController { return objc_getAssociatedObject(self, &kPresentingKey); }
- (void)presentViewControllerAsSheet:(NSViewController *)vc {
    NSWindow *parent = self.view.window;
    NSView *v = vc.view;
    NSSize s = v.fittingSize;
    if (s.width < 1 || s.height < 1) s = v.frame.size;
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, MAX(s.width, 100), MAX(s.height, 60))
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    sheet.contentViewController = vc;
    objc_setAssociatedObject(vc, &kPresentingKey, self, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(vc, &kSheetWindowKey, sheet, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (parent) [parent beginSheet:sheet completionHandler:nil];
    else [sheet makeKeyAndOrderFront:nil];
}
- (void)presentViewControllerAsModalWindow:(NSViewController *)vc { [self presentViewControllerAsSheet:vc]; }
- (void)dismissViewController:(NSViewController *)vc {
    NSWindow *sheet = objc_getAssociatedObject(vc, &kSheetWindowKey);
    if (sheet) {
        if (sheet.sheetParent) [sheet.sheetParent endSheet:sheet];
        [sheet orderOut:nil];
    }
    objc_setAssociatedObject(vc, &kSheetWindowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(vc, &kPresentingKey, nil, OBJC_ASSOCIATION_ASSIGN);
}
- (void)dismissController:(id)sender {
    NSViewController *p = self.presentingViewController;
    if (p) [p dismissViewController:self];
}
@end

/* ---- the application ---- */

@implementation NSApplication (BittenCompat)
/* The Services menu's question; no services here. */
- (id)validRequestorForSendType:(NSPasteboardType)sendType returnType:(NSPasteboardType)returnType { return nil; }
@end

/* ---- drawing variants ---- */

@implementation NSImage (BittenCompat)
- (void)drawInRect:(NSRect)dst fromRect:(NSRect)src operation:(NSCompositingOperation)op fraction:(CGFloat)alpha
    respectFlipped:(BOOL)respect hints:(NSDictionary *)hints {
    NSGraphicsContext *g = [NSGraphicsContext currentContext];
    CGContextRef c = g.CGContext;
    if (respect && g.isFlipped && c) {
        /* Upright in a flipped view: flip the image about its own rect. */
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, 0, NSMinY(dst) + NSMaxY(dst));
        CGContextScaleCTM(c, 1, -1);
        [self drawInRect:dst fromRect:src operation:op fraction:alpha];
        CGContextRestoreGState(c);
        return;
    }
    [self drawInRect:dst fromRect:src operation:op fraction:alpha];
}
- (id)layerContentsForContentsScale:(CGFloat)scale {
    NSRect r = NSMakeRect(0, 0, self.size.width, self.size.height);
    return (__bridge id)[self CGImageForProposedRect:&r context:nil hints:nil];
}
- (CGFloat)recommendedLayerContentsScale:(CGFloat)preferred { return preferred > 0 ? preferred : 1; }
@end

@implementation NSBundle (BittenAppKitCompat)
- (NSImage *)imageForResource:(NSImageName)name {
    NSString *path = [self pathForImageResource:name];
    if (path) return [[NSImage alloc] initWithContentsOfFile:path];
    return [NSImage imageNamed:name];
}
- (NSString *)pathForImageResource:(NSImageName)name {
    if (name.pathExtension.length) return [self pathForResource:name ofType:nil];
    for (NSString *ext in @[ @"png", @"pdf", @"jpg", @"jpeg", @"tiff", @"icns", @"svg" ]) {
        NSString *p = [self pathForResource:name ofType:ext];
        if (p) return p;
    }
    return nil;
}
@end

@implementation NSColor (BittenCompat)
- (void)drawSwatchInRect:(NSRect)rect {
    [self setFill];
    NSRectFill(rect);
}
@end

@implementation NSGradient (BittenCompat)
- (instancetype)initWithColors:(NSArray<NSColor *> *)colors atLocations:(const CGFloat *)locations
                    colorSpace:(NSColorSpace *)space {
    NSMutableArray *l = [NSMutableArray array];
    for (NSUInteger i = 0; i < colors.count; i++) [l addObject:@(locations ? locations[i] : 0)];
    return [self initWithColors:colors locations:l];
}
@end

@implementation NSAttributedString (BittenCompat)
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options {
    return [self boundingRectWithSize:size options:options context:nil];
}
- (void)drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options { [self drawInRect:rect]; }
- (void)drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options context:(id)context {
    [self drawInRect:rect];
}
@end

@implementation NSString (BittenAppKitCompat)
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options attributes:(NSDictionary *)attrs {
    return [[[NSAttributedString alloc] initWithString:self attributes:attrs] boundingRectWithSize:size
                                                                                            options:options
                                                                                            context:nil];
}
- (void)drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options attributes:(NSDictionary *)attrs {
    [self drawInRect:rect withAttributes:attrs];
}
@end

/* ---- display links (QuartzCore's CADisplayLink, looked up at run time) ---- */

static id display_link(id target, SEL sel) {
    Class c = objc_getClass("CADisplayLink");
    if (!c) return nil;
    return ((id (*)(Class, SEL, id, SEL))objc_msgSend)(c, sel_registerName("_bn_displayLinkWithTarget:selector:"),
                                                       target, sel);
}
@implementation NSView (BittenDisplayLink)
- (id)displayLinkWithTarget:(id)target selector:(SEL)selector { return display_link(target, selector); }
@end
@implementation NSWindow (BittenDisplayLink)
- (id)displayLinkWithTarget:(id)target selector:(SEL)selector { return display_link(target, selector); }
@end
@implementation NSScreen (BittenDisplayLink)
- (id)displayLinkWithTarget:(id)target selector:(SEL)selector { return display_link(target, selector); }
- (NSInteger)maximumFramesPerSecond { return 60; }
- (CGFloat)maximumPotentialExtendedDynamicRangeColorComponentValue { return 1; }
- (CGFloat)maximumExtendedDynamicRangeColorComponentValue { return 1; }
@end
