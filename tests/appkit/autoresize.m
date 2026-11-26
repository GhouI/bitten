// Autoresizing masks: subviews follow their superview's size changes.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        // Fills its superview.
        NSView *fill = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        fill.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        // Keeps its size and its distance from the right and top edges.
        NSView *corner = [[NSView alloc] initWithFrame:NSMakeRect(80, 80, 10, 10)];
        corner.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
        // Not sizable: stays put.
        NSView *fixed = [[NSView alloc] initWithFrame:NSMakeRect(10, 10, 20, 20)];
        // Flexible width and right margin: the change is shared in proportion
        // to their lengths (width 20, right margin 60 -> 1:3).
        NSView *shared = [[NSView alloc] initWithFrame:NSMakeRect(20, 0, 20, 10)];
        shared.autoresizingMask = NSViewWidthSizable | NSViewMaxXMargin;
        // Laid out by constraints: left alone.
        NSView *constrained = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        constrained.autoresizingMask = NSViewWidthSizable;
        constrained.translatesAutoresizingMaskIntoConstraints = NO;
        for (NSView *v in @[ fill, corner, fixed, shared, constrained ]) [root addSubview:v];

        [root setFrameSize:NSMakeSize(180, 140)];
        CHECK(NSEqualRects(fill.frame, NSMakeRect(0, 0, 180, 140)));
        CHECK(NSEqualRects(corner.frame, NSMakeRect(160, 120, 10, 10)));
        CHECK(NSEqualRects(fixed.frame, NSMakeRect(10, 10, 20, 20)));
        CHECK(NSEqualRects(shared.frame, NSMakeRect(20, 0, 40, 10)));
        CHECK(NSEqualRects(constrained.frame, NSMakeRect(0, 0, 100, 100)));

        // A view created at zero size inside a zero-size superview still
        // grows with it (no lengths to weigh: the change is shared equally).
        NSView *zero = [[NSView alloc] initWithFrame:NSZeroRect];
        NSView *inner = [[NSView alloc] initWithFrame:NSZeroRect];
        inner.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [zero addSubview:inner];
        [zero setFrame:NSMakeRect(5, 5, 60, 40)];
        CHECK(NSEqualRects(inner.frame, NSMakeRect(0, 0, 60, 40)));

        // autoresizesSubviews = NO turns it off.
        zero.autoresizesSubviews = NO;
        [zero setFrameSize:NSMakeSize(10, 10)];
        CHECK(NSEqualRects(inner.frame, NSMakeRect(0, 0, 60, 40)));
        puts("appkit autoresize ok");
    }
    return 0;
}
