/* Events from the display (mouse, keyboard, scrolling, window requests),
 * turned into NSEvents and delivered the way AppKit delivers them: the
 * application sends each to its window; a mouse-down goes to the view under
 * it, which then gets the drags and the mouse-up; keys go to the first
 * responder; close and resize requests act like the title bar's controls. */
#import <AppKit/AppKit.h>
#import <objc/message.h>
static NSEvent *bn_run_local_monitors(NSEvent *event);
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>
#include <sys/time.h>

struct bitten_display_event {
    uint32_t type;
    uint32_t window;
    double x, y;
    double dx, dy;
    uint32_t button;
    uint32_t modifiers;
    uint32_t key_code;
    char characters[32];
    double width, height;
};
int bitten_display_next_event(struct bitten_display_event *out);
int bitten_display_event_fd(void);

@interface NSEvent (BittenPrivate)
+ (void)_bn_setMouseLocation:(NSPoint)p flags:(NSEventModifierFlags)f;
- (void)_bn_setScrollDeltaX:(CGFloat)dx y:(CGFloat)dy;
@end
@interface NSApplication (BittenCurrentEvent)
- (void)_bn_setCurrentEvent:(NSEvent *)event;
@end

static NSTimeInterval now_seconds(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1e6;
}

/* ---- first responders and mouse tracking, per window ---- */

void bn_debug_callers(void); /* AppKitCore.m */
static const char kFirstResponderKey, kTrackingKey;

/* ---- tracking areas ----
 * As the mouse moves over a window, each tracking area it enters or leaves
 * tells its owner (mouseEntered: / mouseExited:), and areas that ask for
 * movement get mouseMoved:. A view is asked to update its areas
 * (updateTrackingAreas) when it joins a window or changes size, as AppKit
 * does when a view's visible rect changes. */
static const char kTrackingAreaKey, kInsideKey, kTrackingDirtyKey;

@implementation NSEvent (BittenTracking)
- (NSTrackingArea *)trackingArea { return objc_getAssociatedObject(self, &kTrackingAreaKey); }
- (void *)userData { return (__bridge void *)self.trackingArea.userInfo; }
- (NSInteger)trackingNumber { return (NSInteger)(__bridge void *)self.trackingArea; }
@end

static NSEvent *tracking_event(NSEventType type, NSEvent *from, NSTrackingArea *area) {
    NSEvent *e = [NSEvent mouseEventWithType:type location:from.locationInWindow modifierFlags:from.modifierFlags
                                   timestamp:from.timestamp windowNumber:from.windowNumber context:nil eventNumber:0
                                  clickCount:0 pressure:0];
    objc_setAssociatedObject(e, &kTrackingAreaKey, area, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return e;
}

@implementation NSView (BittenTrackingState)
- (void)_bn_setTrackingAreasNeedUpdate {
    objc_setAssociatedObject(self, &kTrackingDirtyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* The areas of v and its visible subviews that contain p (window coordinates). */
static void collect_areas(NSView *v, NSPoint p, NSMutableArray *inside) {
    if (v.isHidden) return;
    if ([objc_getAssociatedObject(v, &kTrackingDirtyKey) boolValue]) {
        objc_setAssociatedObject(v, &kTrackingDirtyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [v updateTrackingAreas];
    }
    NSArray *areas = v.trackingAreas;
    if (areas.count) {
        NSPoint local = [v convertPoint:p fromView:nil];
        for (NSTrackingArea *a in areas) {
            NSRect r = (a.options & NSTrackingInVisibleRect) ? v.visibleRect : a.rect;
            if (NSPointInRect(local, r)) [inside addObject:a];
        }
    }
    for (NSView *s in v.subviews) collect_areas(s, p, inside);
}

@implementation NSWindow (BittenTracking)
- (void)_bn_trackMouse:(NSEvent *)event {
    NSMutableArray<NSTrackingArea *> *now = [NSMutableArray array];
    if (self.contentView) collect_areas(self.contentView, event.locationInWindow, now);
    NSMutableArray<NSTrackingArea *> *before = objc_getAssociatedObject(self, &kInsideKey) ?: [NSMutableArray array];
    objc_setAssociatedObject(self, &kInsideKey, now, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSTrackingArea *a in before)
        if ([now indexOfObjectIdenticalTo:a] == NSNotFound && (a.options & NSTrackingMouseEnteredAndExited))
            [a.owner mouseExited:tracking_event(NSEventTypeMouseExited, event, a)];
    for (NSTrackingArea *a in now) {
        BOOL entered = [before indexOfObjectIdenticalTo:a] == NSNotFound;
        if (entered && getenv("BITTEN_EVENT_DEBUG"))
            fprintf(stderr, "bitten: mouse entered a tracking area of %s (options %#lx)\n", object_getClassName(a.owner),
                    (unsigned long)a.options);
        if (entered && (a.options & NSTrackingMouseEnteredAndExited))
            [a.owner mouseEntered:tracking_event(NSEventTypeMouseEntered, event, a)];
        if (entered && (a.options & NSTrackingCursorUpdate) && [a.owner respondsToSelector:@selector(cursorUpdate:)])
            [a.owner cursorUpdate:tracking_event(NSEventTypeCursorUpdate, event, a)];
        if ((a.options & NSTrackingMouseMoved) && event.type == NSEventTypeMouseMoved)
            [a.owner mouseMoved:event];
    }
}
@end

@implementation NSView (BittenKeyEquivalents)
/* A key equivalent is offered to each visible subview until one takes it. */
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    for (NSView *v in self.subviews)
        if (!v.isHidden && [v performKeyEquivalent:event]) return YES;
    return NO;
}
@end

@implementation NSWindow (BittenEvents)
- (BOOL)performKeyEquivalent:(NSEvent *)event { return [self.contentView performKeyEquivalent:event]; }
- (NSResponder *)firstResponder {
    NSResponder *r = objc_getAssociatedObject(self, &kFirstResponderKey);
    return r ?: self;
}
/* Ends editing in a field editor, for `object` (the control it edits) or
 * any: the window takes first responder, without asking the editor (as
 * AppKit forces it). */
- (void)endEditingFor:(id)object {
    NSResponder *current = objc_getAssociatedObject(self, &kFirstResponderKey);
    if (![current isKindOfClass:[NSText class]] || ![(NSTextView *)current isFieldEditor]) return;
    if (object && [(NSTextView *)current delegate] != object) return;
    [current resignFirstResponder];
    objc_setAssociatedObject(self, &kFirstResponderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)makeFirstResponder:(NSResponder *)responder {
    NSResponder *current = objc_getAssociatedObject(self, &kFirstResponderKey);
    if (getenv("BITTEN_EVENT_DEBUG") && current != responder) {
        fprintf(stderr, "bitten: first responder %s -> %s (accepts %d) from", current ? object_getClassName(current) : "window",
                responder ? object_getClassName(responder) : "window", responder ? responder.acceptsFirstResponder : 1);
        bn_debug_callers();
    }
    if (current == responder) return YES;
    if (current && ![current resignFirstResponder]) return NO;
    if (responder && responder != self && ![responder becomeFirstResponder]) return NO;
    objc_setAssociatedObject(self, &kFirstResponderKey, responder == self ? nil : responder,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}
/* No first responder but the window, without asking the current one. */
- (void)_bn_dropFirstResponder {
    objc_setAssociatedObject(self, &kFirstResponderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)performClose:(id)sender {
    id<NSWindowDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(windowShouldClose:)] && ![d windowShouldClose:self]) return;
    [self close];
}

/* Drag and drop (AppKitDragging.m) takes the mouse during a drag. */
extern BOOL bn_dragging_route(NSWindow *w, NSEvent *e);

- (void)sendEvent:(NSEvent *)event {
    if (bn_dragging_route(self, event)) return;
    switch (event.type) {
    case NSEventTypeLeftMouseDown:
    case NSEventTypeRightMouseDown: {
        NSView *hit = [self.contentView hitTest:event.locationInWindow];
        NSView *target = hit ?: self.contentView;
        if (getenv("BITTEN_EVENT_DEBUG")) {
            fprintf(stderr, "bitten: mouse down at %s hits", NSStringFromPoint(event.locationInWindow).UTF8String);
            for (NSView *v = target; v; v = v.superview) fprintf(stderr, " < %s", object_getClassName(v));
            fprintf(stderr, "\n");
            unsigned n = 0;
            Method *ms = class_copyMethodList(object_getClass(target), &n);
            fprintf(stderr, "bitten:   target's own methods:");
            for (unsigned i = 0; i < n; i++) fprintf(stderr, " %s@%p", sel_getName(method_getName(ms[i])), (void *)method_getImplementation(ms[i]));
            free(ms);
            fprintf(stderr, "; %lu gesture recognizers\n", (unsigned long)target.gestureRecognizers.count);
        }
        objc_setAssociatedObject(self, &kTrackingKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!self.isKeyWindow) [self makeKeyAndOrderFront:nil];
        for (NSView *v = target; v; v = v.superview)
            if (v.acceptsFirstResponder) {
                [self makeFirstResponder:v];
                break;
            }
        if (event.type == NSEventTypeLeftMouseDown) [target mouseDown:event];
        else [target rightMouseDown:event];
        break;
    }
    case NSEventTypeLeftMouseDragged:
    case NSEventTypeRightMouseDragged: {
        [self _bn_trackMouse:event];
        NSView *target = objc_getAssociatedObject(self, &kTrackingKey);
        [target ?: self.contentView mouseDragged:event];
        break;
    }
    case NSEventTypeLeftMouseUp:
    case NSEventTypeRightMouseUp: {
        NSView *target = objc_getAssociatedObject(self, &kTrackingKey) ?: self.contentView;
        objc_setAssociatedObject(self, &kTrackingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (event.type == NSEventTypeLeftMouseUp) [target mouseUp:event];
        else [target rightMouseUp:event];
        break;
    }
    case NSEventTypeMouseMoved:
        /* Views see movement through their tracking areas; the first
         * responder also gets it when the window accepts mouse-moved events. */
        [self _bn_trackMouse:event];
        if (self.acceptsMouseMovedEvents) [self.firstResponder mouseMoved:event];
        break;
    case NSEventTypeScrollWheel: {
        NSView *hit = [self.contentView hitTest:event.locationInWindow];
        [hit ?: self.contentView scrollWheel:event];
        break;
    }
    case NSEventTypeKeyDown:
        if (getenv("BITTEN_EVENT_DEBUG"))
            fprintf(stderr, "bitten: key down '%s' (code %u) to %s\n", event.characters.UTF8String ?: "",
                    (unsigned)event.keyCode, self.firstResponder ? object_getClassName(self.firstResponder) : "nothing");
        [self.firstResponder keyDown:event];
        break;
    case NSEventTypeKeyUp: [self.firstResponder keyUp:event]; break;
    case NSEventTypeFlagsChanged: [self.firstResponder flagsChanged:event]; break;
    default: break;
    }
}
@end

/* A key nothing along the responder chain took ends at the window, which
 * offers it as a key equivalent (Escape to a Cancel button, Return to the
 * default button, SwiftUI's .cancelAction / .defaultAction), as AppKit's
 * keyboard interface does; Escape and Return a text view turns into
 * cancelOperation: / insertNewline: that nothing takes go the same way. */
@implementation NSWindow (BittenKeyFallback)
- (void)keyDown:(NSEvent *)event {
    if ([self performKeyEquivalent:event]) return;
    [self.nextResponder keyDown:event];
}
- (void)doCommandBySelector:(SEL)sel {
    if ([self respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, sel, nil);
        return;
    }
    NSEvent *e = NSApp.currentEvent;
    if (e.type == NSEventTypeKeyDown && (sel == @selector(cancelOperation:) || sel == @selector(insertNewline:)) &&
        [self performKeyEquivalent:e])
        return;
    [self.nextResponder doCommandBySelector:sel];
}
@end

@implementation NSResponder (BittenEvents)
- (void)rightMouseUp:(NSEvent *)event { [self.nextResponder rightMouseUp:event]; }
@end

/* ---- the application: events in from the display ---- */

@implementation NSApplication (BittenEvents)
/* The first object along the key window's responder chain (then the
 * window, its delegate, the application and its delegate) that handles
 * `action`. */
- (id)targetForAction:(SEL)action to:(id)target from:(id)sender {
    if (target) return [target respondsToSelector:action] ? target : nil;
    NSWindow *key = self.keyWindow;
    for (NSResponder *r = key.firstResponder; r; r = r.nextResponder)
        if ([r respondsToSelector:action]) return r;
    if (key && [key respondsToSelector:action]) return key;
    if ([key.delegate respondsToSelector:action]) return key.delegate;
    if ([self respondsToSelector:action]) return self;
    if ([self.delegate respondsToSelector:action]) return self.delegate;
    return nil;
}
- (id)targetForAction:(SEL)action { return [self targetForAction:action to:nil from:nil]; }
- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender {
    id t = [self targetForAction:action to:target from:sender];
    if (getenv("BITTEN_EVENT_DEBUG"))
        fprintf(stderr, "bitten: action %s from %s to %s\n", sel_getName(action), sender ? object_getClassName(sender) : "nil",
                t ? object_getClassName(t) : "nobody");
    if (!t) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(t, action, sender);
    return YES;
}
- (void)sendEvent:(NSEvent *)event {
    BOOL debug = getenv("BITTEN_EVENT_DEBUG") && (event.type == NSEventTypeKeyDown || event.type == NSEventTypeFlagsChanged);
    NSEvent *original = event;
    [self _bn_setCurrentEvent:event];
    event = bn_run_local_monitors(event);
    if (!event) {
        if (debug) fprintf(stderr, "bitten: key code %u flags %#lx taken by a local monitor\n", (unsigned)original.keyCode,
                           (unsigned long)original.modifierFlags);
        return;
    }
    /* Command-key shortcuts go to the key window's views first (a
     * shortcut recorder, a button's key equivalent), then the main menu. */
    if (event.type == NSEventTypeKeyDown && (event.modifierFlags & NSEventModifierFlagCommand) &&
        [(event.window ?: self.keyWindow) performKeyEquivalent:event]) {
        if (debug) fprintf(stderr, "bitten: key '%s' flags %#lx taken by a view\n", event.charactersIgnoringModifiers.UTF8String ?: "",
                           (unsigned long)event.modifierFlags);
        return;
    }
    if (event.type == NSEventTypeKeyDown && (event.modifierFlags & NSEventModifierFlagCommand) &&
        [self.mainMenu performKeyEquivalent:event]) {
        if (debug) fprintf(stderr, "bitten: key '%s' flags %#lx taken by the main menu\n", event.charactersIgnoringModifiers.UTF8String ?: "",
                           (unsigned long)event.modifierFlags);
        return;
    }
    if (debug && event.type == NSEventTypeKeyDown && (event.modifierFlags & NSEventModifierFlagCommand))
        fprintf(stderr, "bitten: key '%s' flags %#lx: no menu item, to the window\n",
                event.charactersIgnoringModifiers.UTF8String ?: "", (unsigned long)event.modifierFlags);
    NSWindow *w = event.window;
    if (w) [w sendEvent:event];
    else if (event.type == NSEventTypeKeyDown) [self.keyWindow sendEvent:event];
}

static NSInteger click_count(NSPoint p, NSTimeInterval t) {
    static NSTimeInterval last_time;
    static NSPoint last_point;
    static NSInteger count;
    if (t - last_time < 0.4 && fabs(p.x - last_point.x) < 4 && fabs(p.y - last_point.y) < 4) count++;
    else count = 1;
    last_time = t;
    last_point = p;
    return count;
}

/* Delivers what the display has queued. */
/* The characters a Mac reports for keys that type no text of their own:
 * control characters and the function-key range (NSUpArrowFunctionKey...). */
static NSString *bn_key_characters(unsigned short code) {
    static const struct { unsigned short code; unichar c; } keys[] = {
        {36, '\r'}, {76, 0x03}, {48, '\t'}, {51, 0x7F}, {53, 0x1B}, {117, 0xF728},
        {123, 0xF702}, {124, 0xF703}, {125, 0xF701}, {126, 0xF700},
        {115, 0xF729}, {119, 0xF72B}, {116, 0xF72C}, {121, 0xF72D},
        {122, 0xF704}, {120, 0xF705}, {99, 0xF706}, {118, 0xF707}, {96, 0xF708}, {97, 0xF709},
        {98, 0xF70A}, {100, 0xF70B}, {101, 0xF70C}, {109, 0xF70D}, {103, 0xF70E}, {111, 0xF70F},
    };
    for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++)
        if (keys[i].code == code) return [NSString stringWithFormat:@"%C", keys[i].c];
    return @"";
}

+ (void)_bn_pumpDisplayEvents {
    struct bitten_display_event e;
    while (bitten_display_next_event(&e) == 1) {
        NSWindow *window = nil;
        for (NSWindow *w in [NSApp windows])
            if ((uint32_t)w.windowNumber == e.window) window = w;
        /* Keys the page still sends to a window that has closed (the one it
         * last had focused) go to the key window, as all keys do. */
        if (!window && (e.type == 6 || e.type == 7) && NSApp.keyWindow.isVisible) window = NSApp.keyWindow;
        if (!window) continue;
        NSRect content = [window contentRectForFrameRect:window.frame];
        /* The display's coordinates run down from the content's top-left. */
        NSPoint loc = NSMakePoint(e.x, content.size.height - e.y);
        NSEventModifierFlags flags = e.modifiers;
        NSTimeInterval t = now_seconds();
        [NSEvent _bn_setMouseLocation:NSMakePoint(window.frame.origin.x + loc.x, window.frame.origin.y + loc.y)
                                flags:flags];
        if (getenv("BITTEN_EVENT_DEBUG") && e.type >= 1 && e.type <= 4 && e.type != 3)
            fprintf(stderr, "bitten: display event %u for %s at (%g, %g): in window %s, on screen %s\n", e.type,
                    object_getClassName(window), e.x, e.y, NSStringFromPoint(loc).UTF8String,
                    NSStringFromPoint([NSEvent mouseLocation]).UTF8String);
        NSEvent *event = nil;
        switch (e.type) {
        case 1: case 2: case 3: case 4: {
            NSEventType type;
            BOOL right = e.button == 2;
            if (e.type == 1) type = right ? NSEventTypeRightMouseDown : NSEventTypeLeftMouseDown;
            else if (e.type == 2) type = right ? NSEventTypeRightMouseUp : NSEventTypeLeftMouseUp;
            else if (e.type == 3) type = NSEventTypeMouseMoved;
            else type = right ? NSEventTypeRightMouseDragged : NSEventTypeLeftMouseDragged;
            NSInteger clicks = e.type == 1 ? click_count(loc, t) : 1;
            extern NSUInteger bn_pressed_buttons;
            if (e.type == 1) bn_pressed_buttons |= right ? 2 : 1;
            if (e.type == 2) bn_pressed_buttons &= ~(NSUInteger)(right ? 2 : 1);
            event = [NSEvent mouseEventWithType:type location:loc modifierFlags:flags timestamp:t
                                   windowNumber:window.windowNumber context:nil eventNumber:0
                                     clickCount:clicks pressure:1];
            break;
        }
        case 5:
            event = [NSEvent mouseEventWithType:NSEventTypeScrollWheel location:loc modifierFlags:flags timestamp:t
                                   windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:0
                                       pressure:0];
            [event _bn_setScrollDeltaX:e.dx y:e.dy];
            break;
        case 6: case 7: {
            /* Keys go to the key window (a panel the program made key),
             * whichever window the display had focused. */
            NSWindow *keyed = NSApp.keyWindow.isVisible ? NSApp.keyWindow : window;
            /* Modifier keys alone change the modifier flags; they type nothing. */
            unsigned short code = (unsigned short)e.key_code;
            if (code >= 54 && code <= 63) {
                event = [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:loc modifierFlags:flags timestamp:t
                                     windowNumber:keyed.windowNumber context:nil characters:@""
                      charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
                break;
            }
            NSString *ignoring = [NSString stringWithUTF8String:e.characters] ?: @"";
            if (!ignoring.length) ignoring = bn_key_characters((unsigned short)e.key_code);
            NSString *chars = ignoring;
            /* Control turns a letter (and @[\]^_) into its control character */
            if ((flags & NSEventModifierFlagControl) && ignoring.length == 1) {
                unichar c = [ignoring characterAtIndex:0];
                if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
                if (c >= '@' && c <= '_') chars = [NSString stringWithFormat:@"%C", (unichar)(c - '@')];
            }
            event = [NSEvent keyEventWithType:e.type == 6 ? NSEventTypeKeyDown : NSEventTypeKeyUp location:loc
                                modifierFlags:flags timestamp:t windowNumber:keyed.windowNumber context:nil
                                   characters:chars charactersIgnoringModifiers:ignoring isARepeat:NO
                                      keyCode:(unsigned short)e.key_code];
            break;
        }
        case 8:
            [window performClose:nil];
            continue;
        case 9: {
            [window _bn_liveResizeStep];
            /* Resized by the page's grip: the top left corner stays put. */
            NSRect frame = window.frame;
            NSRect c = [window contentRectForFrameRect:frame];
            c.origin.y += c.size.height - e.height;
            c.size = NSMakeSize(e.width, e.height);
            [window setFrame:[window frameRectForContentRect:c] display:YES];
            continue;
        }
        case 11: [window performMiniaturize:nil]; continue;
        case 12: [window performZoom:nil]; continue;
        case 13: [window deminiaturize:nil]; continue;
        case 10: {
            /* Moved on the display: (x, y) is the content's top left, down from the screen's top. */
            NSRect moved = content;
            moved.origin = NSMakePoint(e.x, NSMaxY([NSScreen mainScreen].frame) - e.y - content.size.height);
            [window setFrameOrigin:[window frameRectForContentRect:moved].origin];
            continue;
        }
        default:
            continue;
        }
        if (event) [NSApp sendEvent:event];
    }
}

/* Starts listening once the display is up (after the first window shows). */
+ (void)_bn_listenToDisplay {
    static dispatch_source_t source;
    if (source) return;
    int fd = bitten_display_event_fd();
    if (fd < 0) return;
    source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{ [NSApplication _bn_pumpDisplayEvents]; });
    dispatch_resume(source);
}
@end

/* ---- event monitors ----
 * Local monitors see this application's events before they are sent and
 * may replace or swallow them; global monitors would see other
 * applications' events, which never reach us. */
@interface BNEventMonitor : NSObject
@property NSEventMask mask;
@property (copy) NSEvent * (^local)(NSEvent *);
@property (copy) void (^global)(NSEvent *);
@end
@implementation BNEventMonitor
@end
static NSMutableArray<BNEventMonitor *> *event_monitors(void) {
    static NSMutableArray *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [NSMutableArray array]; });
    return m;
}
static NSEvent *bn_run_local_monitors(NSEvent *event) {
    NSArray *monitors;
    @synchronized(event_monitors()) { monitors = [event_monitors() copy]; }
    for (BNEventMonitor *m in monitors) {
        if (!m.local || !(m.mask & NSEventMaskFromType(event.type))) continue;
        event = m.local(event);
        if (!event) return nil;
    }
    return event;
}

@implementation NSEvent (BittenMonitors)
+ (id)addLocalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(NSEvent * (^)(NSEvent *))block {
    BNEventMonitor *m = [BNEventMonitor new];
    m.mask = mask;
    m.local = block;
    @synchronized(event_monitors()) { [event_monitors() addObject:m]; }
    if (getenv("BITTEN_MONITOR_DEBUG")) {
        fprintf(stderr, "bitten: local monitor %p added from", (__bridge void *)m);
        bn_debug_callers();
    }
    return m;
}
+ (id)addGlobalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(void (^)(NSEvent *))block {
    BNEventMonitor *m = [BNEventMonitor new];
    m.mask = mask;
    m.global = block;
    @synchronized(event_monitors()) { [event_monitors() addObject:m]; }
    if (getenv("BITTEN_MONITOR_DEBUG")) {
        fprintf(stderr, "bitten: global monitor %p added from", (__bridge void *)m);
        bn_debug_callers();
    }
    return m;
}
+ (void)removeMonitor:(id)monitor {
    if (getenv("BITTEN_MONITOR_DEBUG")) fprintf(stderr, "bitten: monitor %p removed\n", (__bridge void *)monitor);
    @synchronized(event_monitors()) { [event_monitors() removeObjectIdenticalTo:monitor]; }
}
@end

/* A live resize: the page's grip sends sizes while it is dragged and
 * nothing when it is let go, so the resize ends once sizes stop coming. As
 * in AppKit, views hear viewWillStartLiveResize / viewDidEndLiveResize and
 * the window posts its notifications; inLiveResize says it is under way. */
static void bn_tell_live_resize(NSView *v, BOOL start) {
    if (start) [v viewWillStartLiveResize];
    for (NSView *s in [v.subviews copy]) bn_tell_live_resize(s, start);
    if (!start) [v viewDidEndLiveResize];
}
@implementation NSWindow (BittenLiveResize)
- (void)_bn_liveResizeStep {
    static const char kStep;
    NSInteger step = [objc_getAssociatedObject(self, &kStep) integerValue] + 1;
    objc_setAssociatedObject(self, &kStep, @(step), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!self.inLiveResize) {
        objc_setAssociatedObject(self, @selector(inLiveResize), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([self.delegate respondsToSelector:@selector(windowWillStartLiveResize:)])
            [(id)self.delegate performSelector:@selector(windowWillStartLiveResize:)
                                    withObject:[NSNotification notificationWithName:NSWindowWillStartLiveResizeNotification
                                                                             object:self userInfo:nil]];
        [self _post:NSWindowWillStartLiveResizeNotification];
        bn_tell_live_resize(self.contentView, YES);
    }
    __weak NSWindow *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        NSWindow *w = weakSelf;
        if (!w || [objc_getAssociatedObject(w, &kStep) integerValue] != step || !w.inLiveResize) return;
        objc_setAssociatedObject(w, @selector(inLiveResize), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        bn_tell_live_resize(w.contentView, NO);
        if ([w.delegate respondsToSelector:@selector(windowDidEndLiveResize:)])
            [(id)w.delegate performSelector:@selector(windowDidEndLiveResize:)
                                 withObject:[NSNotification notificationWithName:NSWindowDidEndLiveResizeNotification
                                                                          object:w userInfo:nil]];
        [w _post:NSWindowDidEndLiveResizeNotification];
        [w display];   /* a last full frame, drawn as views draw outside a live resize */
    });
}
@end
