// AppKit object model: the application and its delegate, windows, views
// and their hierarchy, hit testing, drawing passes.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static int draws;
@interface Box : NSView
@end
@implementation Box
- (void)drawRect:(NSRect)r { draws++; }
@end

/* What a view sees as the application's current event while handling one. */
static NSEvent *seen_current;
@interface Clicky : NSView
@end
@implementation Clicky
- (void)mouseDown:(NSEvent *)e { seen_current = NSApp.currentEvent; }
@end

@interface Delegate : NSObject <NSApplicationDelegate>
@property int launched;
@end
@implementation Delegate
- (void)applicationDidFinishLaunching:(NSNotification *)n { self.launched++; }
@end

int main(void) {
    NSApplication *app = [NSApplication sharedApplication];
    CHECK(app == NSApp);
    Delegate *d = [Delegate new];
    app.delegate = d;
    [app finishLaunching];
    CHECK(d.launched == 1 && app.active);

    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing:NSBackingStoreBuffered defer:NO];
    CHECK(w.frame.size.height == 328 && w.contentView.frame.size.height == 300);
    Box *outer = [[Box alloc] initWithFrame:NSMakeRect(10, 10, 200, 100)];
    Box *inner = [[Box alloc] initWithFrame:NSMakeRect(5, 5, 50, 50)];
    [outer addSubview:inner];
    [w.contentView addSubview:outer];
    CHECK(inner.window == w && outer.superview == w.contentView && inner.nextResponder == outer);
    [w makeKeyAndOrderFront:nil];
    CHECK(w.visible && w.keyWindow && app.keyWindow == w && draws == 2);
    CHECK([w.contentView hitTest:NSMakePoint(20, 20)] == inner);
    CHECK([w.contentView hitTest:NSMakePoint(100, 80)] == outer);
    NSPoint p = [inner convertPoint:NSMakePoint(1, 1) toView:nil];
    CHECK(p.x == 16 && p.y == 16);
    [inner removeFromSuperview];
    CHECK(inner.window == nil && outer.subviews.count == 0);
    CHECK([NSColor redColor].redComponent == 1 && [NSFont systemFontOfSize:12].pointSize == 12);
    CHECK([NSScreen mainScreen].frame.size.width == 1440);
    CHECK(NSFontWeightBold == 0.4 && [NSWindowDidResizeNotification isEqual:@"NSWindowDidResizeNotification"]);
    [w setContentSize:NSMakeSize(500, 400)];
    CHECK(w.contentView.frame.size.width == 500);

    /* The event being dispatched is the application's current event. */
    Clicky *clicky = [[Clicky alloc] initWithFrame:NSMakeRect(300, 300, 50, 50)];
    [w.contentView addSubview:clicky];
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(310, 310)
                                  modifierFlags:0 timestamp:0 windowNumber:w.windowNumber context:nil
                                    eventNumber:0 clickCount:1 pressure:1];
    [app sendEvent:down];
    CHECK(seen_current == down && app.currentEvent == down);
    puts("AppKit basics ok");
    return 0;
}
