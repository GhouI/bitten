// Compositing operations: a source-atop fill tints only what is already
// drawn (template images are tinted this way); destination-out erases;
// copy replaces.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static const unsigned char *px;
static unsigned argb(int x, int y) {
    const unsigned char *p = px + ((39 - y) * 40 + x) * 4;
    return (unsigned)p[3] << 24 | (unsigned)p[2] << 16 | (unsigned)p[1] << 8 | p[0];
}

int main(void) {
    @autoreleasepool {
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef c = CGBitmapContextCreate(NULL, 40, 40, 8, 160, rgb,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        px = CGBitmapContextGetData(c);
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:c flipped:NO]];
        [[NSColor redColor] setFill];
        NSRectFill(NSMakeRect(10, 10, 10, 10));
        [[NSColor blueColor] setFill];
        NSRectFillUsingOperation(NSMakeRect(0, 0, 40, 40), NSCompositingOperationSourceAtop);
        CHECK(argb(15, 15) == 0xFF0000FF); /* the square, now blue */
        CHECK(argb(30, 30) == 0x00000000); /* still empty */
        [[NSColor blackColor] setFill];
        NSRectFillUsingOperation(NSMakeRect(10, 10, 5, 10), NSCompositingOperationDestinationOut);
        CHECK(argb(12, 15) == 0x00000000); /* erased */
        CHECK(argb(17, 15) == 0xFF0000FF);
        [[NSColor greenColor] setFill];
        NSRectFillUsingOperation(NSMakeRect(30, 30, 5, 5), NSCompositingOperationCopy);
        CHECK((argb(32, 32) & 0xFF00FF00) == 0xFF00FF00);
        printf("ok\n");
    }
    return 0;
}
