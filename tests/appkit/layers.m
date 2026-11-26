// Layer-backed views draw their backing layer's background (with rounded
// corners), its border and their opacity, below their own drawing and
// their subviews.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <objc/message.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static unsigned pixel(CGContextRef c, int x, int y) {
    size_t h = CGBitmapContextGetHeight(c), stride = CGBitmapContextGetBytesPerRow(c);
    const unsigned char *p = (const unsigned char *)CGBitmapContextGetData(c) + (h - 1 - y) * stride + x * 4;
    return (unsigned)p[2] << 16 | (unsigned)p[1] << 8 | p[0];
}
static void set_color(id layer, SEL sel, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    CGColorRef c = CGColorCreateSRGB(r, g, b, a);
    ((void (*)(id, SEL, CGColorRef))objc_msgSend)(layer, sel, c);
    CGColorRelease(c);
}

@interface Dot : NSView
@end
@implementation Dot
- (void)drawRect:(NSRect)r {
    [[NSColor blueColor] setFill];
    NSRectFill(NSMakeRect(20, 20, 4, 4));
}
@end

int main(void) {
    @autoreleasepool {
        setenv("BITTEN_DISPLAY_PORT", "0", 1);
        CHECK(dlopen("/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore", RTLD_NOW) != NULL);
        CHECK(NSClassFromString(@"CALayer") != nil);
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 100, 100)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                    backing:NSBackingStoreBuffered defer:NO];
        w.backgroundColor = [NSColor whiteColor];
        Dot *v = [[Dot alloc] initWithFrame:NSMakeRect(10, 10, 40, 40)];
        v.wantsLayer = YES;
        id layer = v.layer;
        CHECK(layer != nil);
        set_color(layer, @selector(setBackgroundColor:), 1, 0, 0, 1);
        [layer setValue:@10 forKey:@"cornerRadius"];
        [w.contentView addSubview:v];
        // A half-transparent green layer-backed view.
        NSView *g = [[NSView alloc] initWithFrame:NSMakeRect(60, 10, 30, 30)];
        g.wantsLayer = YES;
        set_color(g.layer, @selector(setBackgroundColor:), 0, 1, 0, 1);
        [(id)g.layer setValue:@0.5f forKey:@"opacity"];
        set_color(g.layer, @selector(setBorderColor:), 0, 0, 0, 1);
        [(id)g.layer setValue:@4 forKey:@"borderWidth"];
        [w.contentView addSubview:g];
        [w makeKeyAndOrderFront:nil];
        CGContextRef c = [w _bn_backingContext];
        CHECK(c != NULL);
        CHECK(pixel(c, 25, 40) == 0xFF0000);  // the background
        CHECK(pixel(c, 31, 31) == 0x0000FF);  // the view's own drawing, above it
        CHECK(pixel(c, 11, 11) == 0xFFFFFF);  // outside the rounded corner
        CHECK(pixel(c, 11, 30) == 0xFF0000);  // the straight edge
        unsigned half = pixel(c, 75, 25);
        CHECK((half >> 16) > 0x70 && (half >> 16) < 0x90 && (half & 0xFF) > 0x70 && ((half >> 8) & 0xFF) == 0xFF);
        unsigned edge = pixel(c, 61, 25);     // the border, at half opacity too
        CHECK((edge >> 16) > 0x70 && (edge >> 16) < 0x90 && ((edge >> 8) & 0xFF) < 0x90);
        [w close];
        printf("ok\n");
    }
    return 0;
}
