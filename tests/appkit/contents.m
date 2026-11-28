// A layer-backed view shows its layer's contents image, placed by
// contentsGravity and contentsScale and upright in flipped views too; a
// CAMetalLayer-backed view shows the drawable it presents, and presenting
// redraws the window without anything else asking.
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
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

@interface Flipped : NSView
@end
@implementation Flipped
- (BOOL)isFlipped { return YES; }
@end

@interface MetalView : NSView
@end
@implementation MetalView
- (CALayer *)makeBackingLayer { return [NSClassFromString(@"CAMetalLayer") new]; }
@end

int main(void) {
    @autoreleasepool {
        setenv("BITTEN_DISPLAY_PORT", "0", 1);
        CHECK(dlopen("/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore", RTLD_NOW) != NULL);
        CHECK(dlopen("/System/Library/Frameworks/Metal.framework/Versions/A/Metal", RTLD_NOW) != NULL);
        [NSApplication sharedApplication];

        // A 20x20 image: red in its top half, blue in its bottom half.
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef ic = CGBitmapContextCreate(NULL, 20, 20, 8, 80, rgb,
                                                kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGContextSetRGBFillColor(ic, 1, 0, 0, 1);
        CGContextFillRect(ic, CGRectMake(0, 10, 20, 10));
        CGContextSetRGBFillColor(ic, 0, 0, 1, 1);
        CGContextFillRect(ic, CGRectMake(0, 0, 20, 10));
        CGImageRef img = CGBitmapContextCreateImage(ic);
        CGContextRelease(ic);
        CGColorSpaceRelease(rgb);

        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 200, 100)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                    backing:NSBackingStoreBuffered defer:NO];
        w.backgroundColor = [NSColor whiteColor];
        // Stretched over the view (the default gravity, resize).
        NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)];
        plain.wantsLayer = YES;
        [(id)plain.layer setValue:(__bridge id)img forKey:@"contents"];
        [w.contentView addSubview:plain];
        // In a flipped view the image is still upright.
        Flipped *flipped = [[Flipped alloc] initWithFrame:NSMakeRect(50, 0, 40, 40)];
        flipped.wantsLayer = YES;
        [(id)flipped.layer setValue:(__bridge id)img forKey:@"contents"];
        [w.contentView addSubview:flipped];
        // At scale 2 the image is 10x10 points, in the bottom left corner.
        NSView *corner = [[NSView alloc] initWithFrame:NSMakeRect(100, 0, 40, 40)];
        corner.wantsLayer = YES;
        [(id)corner.layer setValue:(__bridge id)img forKey:@"contents"];
        [(id)corner.layer setValue:@"bottomLeft" forKey:@"contentsGravity"];
        [(id)corner.layer setValue:@2 forKey:@"contentsScale"];
        [w.contentView addSubview:corner];
        // A Metal view, nothing presented yet.
        MetalView *mv = [[MetalView alloc] initWithFrame:NSMakeRect(150, 0, 40, 40)];
        mv.wantsLayer = YES;
        id ml = mv.layer;
        CHECK([ml isKindOfClass:NSClassFromString(@"CAMetalLayer")]);
        [w.contentView addSubview:mv];
        [w makeKeyAndOrderFront:nil];

        CGContextRef c = [w _bn_backingContext];
        CHECK(c != NULL);
        CHECK(pixel(c, 20, 30) == 0xFF0000);  // the top half
        CHECK(pixel(c, 20, 10) == 0x0000FF);  // the bottom half
        CHECK(pixel(c, 70, 30) == 0xFF0000);  // flipped: still red on top
        CHECK(pixel(c, 70, 10) == 0x0000FF);
        CHECK(pixel(c, 102, 7) == 0xFF0000);  // the 10x10 copy: its top half
        CHECK(pixel(c, 102, 2) == 0x0000FF);
        CHECK(pixel(c, 115, 15) == 0xFFFFFF); // outside it
        CHECK(pixel(c, 170, 20) == 0xFFFFFF); // the Metal view, empty

        // Present a drawable cleared to green, then let the main queue run.
        typedef id<MTLDevice> (*create_fn)(void) __attribute__((ns_returns_retained)); /* +1, as Metal's header says */
        create_fn create = (create_fn)dlsym(RTLD_DEFAULT, "MTLCreateSystemDefaultDevice");
        CHECK(create != NULL);
        id<MTLDevice> dev = create();
        CHECK(dev != nil);
        [ml setValue:dev forKey:@"device"];
        ((void (*)(id, SEL, CGSize))objc_msgSend)(ml, @selector(setDrawableSize:), CGSizeMake(40, 40));
        id<MTLDrawable> d = ((id (*)(id, SEL))objc_msgSend)(ml, @selector(nextDrawable));
        id<MTLTexture> tex = [(id)d valueForKey:@"texture"];
        CHECK(d != nil && tex.width == 40 && tex.height == 40);
        id<MTLCommandBuffer> cb = [[dev newCommandQueue] commandBuffer];
        MTLRenderPassDescriptor *rp = [NSClassFromString(@"MTLRenderPassDescriptor") renderPassDescriptor];
        rp.colorAttachments[0].texture = tex;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 0, 1);
        [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
        [cb presentDrawable:d];
        [cb commit];
        [cb waitUntilCompleted];
        for (int i = 0; i < 50 && pixel(c, 170, 20) != 0x00FF00; i++)
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        CHECK(pixel(c, 170, 20) == 0x00FF00);  // shown, with no display call from the program
        CHECK(pixel(c, 20, 30) == 0xFF0000);   // the rest of the window as before
        [w close];
        CGImageRelease(img);
        printf("ok\n");
    }
    return 0;
}
