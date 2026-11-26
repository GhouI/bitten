// AppKit drawing: views draw into their window's bitmap through
// NSGraphicsContext, colours, NSRectFill and NSBezierPath, with frames,
// bounds and flipped views placed as AppKit places them.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

@interface Painter : NSView
@end
@implementation Painter
- (void)drawRect:(NSRect)r {
    [[NSColor redColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 10, 10)); // bottom-left corner of this view
    [[NSColor blueColor] setFill];
    [[NSBezierPath bezierPathWithRect:NSMakeRect(20, 20, 10, 10)] fill];
}
@end

@interface Clicky : NSView
@property int downs, drags, ups, keys;
@property (copy) NSString *typed;
@end
@implementation Clicky
- (BOOL)acceptsFirstResponder { return YES; }
- (void)mouseDown:(NSEvent *)e { self.downs++; }
- (void)mouseDragged:(NSEvent *)e { self.drags++; }
- (void)mouseUp:(NSEvent *)e { self.ups++; }
- (void)keyDown:(NSEvent *)e { self.keys++; self.typed = e.characters; }
@end

@interface FlippedPainter : NSView
@end
@implementation FlippedPainter
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    [[NSColor greenColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 5, 5)); // top-left corner, being flipped
    CHECK([NSGraphicsContext currentContext].isFlipped);
}
@end

/* The colour at (x, y) in AppKit coordinates (origin bottom-left). */
static unsigned pixel(CGContextRef c, int x, int y) {
    size_t h = CGBitmapContextGetHeight(c), stride = CGBitmapContextGetBytesPerRow(c);
    const unsigned char *p = (const unsigned char *)CGBitmapContextGetData(c) + (h - 1 - y) * stride + x * 4;
    /* BGRA in memory (32-bit little-endian, alpha first): return 0xRRGGBB */
    return (unsigned)p[2] << 16 | (unsigned)p[1] << 8 | p[0];
}

int main(void) {
    @autoreleasepool {
        setenv("BITTEN_DISPLAY_PORT", "0", 1); // any free port
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 100, 80)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                    backing:NSBackingStoreBuffered defer:NO];
        w.backgroundColor = [NSColor whiteColor];
        Painter *p = [[Painter alloc] initWithFrame:NSMakeRect(10, 10, 50, 50)];
        [w.contentView addSubview:p];
        FlippedPainter *fp = [[FlippedPainter alloc] initWithFrame:NSMakeRect(70, 50, 20, 20)];
        [w.contentView addSubview:fp];
        [w makeKeyAndOrderFront:nil];
        CGContextRef c = [w _bn_backingContext];
        CHECK(c != NULL);
        CHECK(CGBitmapContextGetWidth(c) == 100 && CGBitmapContextGetHeight(c) == 80);
        CHECK(pixel(c, 0, 0) == 0xFFFFFF);    // background
        CHECK(pixel(c, 12, 12) == 0xFF0000);  // red at the painter's (2, 2)
        CHECK(pixel(c, 35, 35) == 0x0000FF);  // blue path at (25, 25)
        CHECK(pixel(c, 45, 45) == 0xFFFFFF);  // nothing there
        CHECK(pixel(c, 71, 68) == 0x00FF00);  // flipped view: its top-left corner
        CHECK(pixel(c, 71, 51) == 0xFFFFFF);  // not its bottom
        // Clipping: drawing outside a view's frame does not show.
        CHECK(pixel(c, 65, 65) == 0xFFFFFF);
        // Events: a click goes to the view under it, which keeps the drags
        // and the mouse-up and becomes first responder; keys follow.
        Clicky *button = [[Clicky alloc] initWithFrame:NSMakeRect(0, 60, 20, 20)];
        [w.contentView addSubview:button];
        NSEvent *(^mouse)(NSEventType, NSPoint) = ^NSEvent *(NSEventType t, NSPoint p) {
            return [NSEvent mouseEventWithType:t location:p modifierFlags:0 timestamp:0 windowNumber:w.windowNumber
                                       context:nil eventNumber:0 clickCount:1 pressure:1];
        };
        [NSApp sendEvent:mouse(NSEventTypeLeftMouseDown, NSMakePoint(5, 65))];
        [NSApp sendEvent:mouse(NSEventTypeLeftMouseDragged, NSMakePoint(50, 10))]; // outside, still tracked
        [NSApp sendEvent:mouse(NSEventTypeLeftMouseUp, NSMakePoint(50, 10))];
        CHECK(button.downs == 1 && button.drags == 1 && button.ups == 1);
        CHECK(w.firstResponder == button);
        [NSApp sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                      windowNumber:w.windowNumber context:nil characters:@"q"
                       charactersIgnoringModifiers:@"q" isARepeat:NO keyCode:12]];
        CHECK(button.keys == 1 && [button.typed isEqualToString:@"q"]);
        [NSApp sendEvent:mouse(NSEventTypeLeftMouseDown, NSMakePoint(95, 5))]; // empty: the content view
        CHECK(button.downs == 1);
        [w close];
        printf("ok\n");
    }
    return 0;
}
