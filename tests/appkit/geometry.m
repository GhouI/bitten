// View geometry with flipped and unflipped views: point and rect
// conversion through the hierarchy and hit testing.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

@interface Flipped : NSView
@end
@implementation Flipped
- (BOOL)isFlipped { return YES; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        Flipped *f = [[Flipped alloc] initWithFrame:NSMakeRect(10, 20, 100, 100)];
        [root addSubview:f];
        NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(5, 10, 20, 30)];
        [f addSubview:child];

        // f's (0, 0) is its top-left: root y = 20 + 100.
        NSPoint p = [f convertPoint:NSMakePoint(0, 0) toView:root];
        CHECK(p.x == 10 && p.y == 120);
        p = [root convertPoint:NSMakePoint(10, 120) toView:f];
        CHECK(p.x == 0 && p.y == 0);
        // child sits 10 down from f's top; its own (0, 0) is its bottom-left,
        // 10 + 30 down from f's top: root y = 120 - 40 = 80.
        p = [child convertPoint:NSMakePoint(0, 0) toView:root];
        CHECK(p.x == 15 && p.y == 80);
        p = [root convertPoint:NSMakePoint(15, 80) toView:child];
        CHECK(p.x == 0 && p.y == 0);
        NSRect r = [child convertRect:child.bounds toView:root];
        CHECK(NSEqualRects(r, NSMakeRect(15, 80, 20, 30)));

        // Hit testing: root (20, 100) is inside child (root y 80...110).
        CHECK([root hitTest:NSMakePoint(20, 100)] == child);
        CHECK([root hitTest:NSMakePoint(20, 40)] == f);
        CHECK([root hitTest:NSMakePoint(150, 150)] == root);
        puts("appkit geometry ok");
    }
    return 0;
}
