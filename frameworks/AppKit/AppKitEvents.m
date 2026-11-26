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

static NSTimeInterval now_seconds(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1e6;
}

/* ---- first responders and mouse tracking, per window ---- */

static const char kFirstResponderKey, kTrackingKey;

@implementation NSWindow (BittenEvents)
- (NSResponder *)firstResponder {
    NSResponder *r = objc_getAssociatedObject(self, &kFirstResponderKey);
    return r ?: self;
}
- (BOOL)makeFirstResponder:(NSResponder *)responder {
    NSResponder *current = objc_getAssociatedObject(self, &kFirstResponderKey);
    if (current == responder) return YES;
    if (current && ![current resignFirstResponder]) return NO;
    if (responder && responder != self && ![responder becomeFirstResponder]) return NO;
    objc_setAssociatedObject(self, &kFirstResponderKey, responder == self ? nil : responder,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
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
    case NSEventTypeMouseMoved: {
        NSView *hit = [self.contentView hitTest:event.locationInWindow];
        [hit ?: self.contentView mouseMoved:event];
        break;
    }
    case NSEventTypeScrollWheel: {
        NSView *hit = [self.contentView hitTest:event.locationInWindow];
        [hit ?: self.contentView scrollWheel:event];
        break;
    }
    case NSEventTypeKeyDown: [self.firstResponder keyDown:event]; break;
    case NSEventTypeKeyUp: [self.firstResponder keyUp:event]; break;
    case NSEventTypeFlagsChanged: [self.firstResponder flagsChanged:event]; break;
    default: break;
    }
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
    if (!t) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(t, action, sender);
    return YES;
}
- (void)sendEvent:(NSEvent *)event {
    event = bn_run_local_monitors(event);
    if (!event) return;
    /* Command-key shortcuts go to the main menu first. */
    if (event.type == NSEventTypeKeyDown && (event.modifierFlags & NSEventModifierFlagCommand) &&
        [self.mainMenu performKeyEquivalent:event])
        return;
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
+ (void)_bn_pumpDisplayEvents {
    struct bitten_display_event e;
    while (bitten_display_next_event(&e) == 1) {
        NSWindow *window = nil;
        for (NSWindow *w in [NSApp windows])
            if ((uint32_t)w.windowNumber == e.window) window = w;
        if (!window) continue;
        NSRect content = [window contentRectForFrameRect:window.frame];
        /* The display's coordinates run down from the content's top-left. */
        NSPoint loc = NSMakePoint(e.x, content.size.height - e.y);
        NSEventModifierFlags flags = e.modifiers;
        NSTimeInterval t = now_seconds();
        [NSEvent _bn_setMouseLocation:NSMakePoint(window.frame.origin.x + loc.x, window.frame.origin.y + loc.y)
                                flags:flags];
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
            NSString *chars = [NSString stringWithUTF8String:e.characters] ?: @"";
            event = [NSEvent keyEventWithType:e.type == 6 ? NSEventTypeKeyDown : NSEventTypeKeyUp location:loc
                                modifierFlags:flags timestamp:t windowNumber:window.windowNumber context:nil
                                   characters:chars charactersIgnoringModifiers:chars isARepeat:NO
                                      keyCode:(unsigned short)e.key_code];
            break;
        }
        case 8:
            [window performClose:nil];
            continue;
        case 9:
            [window setContentSize:NSMakeSize(e.width, e.height)];
            continue;
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
    return m;
}
+ (id)addGlobalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(void (^)(NSEvent *))block {
    BNEventMonitor *m = [BNEventMonitor new];
    m.mask = mask;
    m.global = block;
    @synchronized(event_monitors()) { [event_monitors() addObject:m]; }
    return m;
}
+ (void)removeMonitor:(id)monitor {
    @synchronized(event_monitors()) { [event_monitors() removeObjectIdenticalTo:monitor]; }
}
@end
