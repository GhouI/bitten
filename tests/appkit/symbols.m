// System symbol images are drawn from their names: each known name puts
// ink in its square, filled variants knock their glyph out of the fill,
// and unknown names still draw something. SYMBOLS_PPM=path writes the grid.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static const char *names[] = {
    "chevron.right", "chevron.up.chevron.down", "arrow.clockwise.circle", "arrow.up.circle.fill",
    "arrow.uturn.backward", "arrow.triangle.2.circlepath", "xmark", "xmark.circle.fill",
    "plus", "checkmark.circle", "ellipsis", "magnifyingglass",
    "gearshape", "trash", "doc.on.doc", "folder",
    "terminal", "sidebar.left", "square.and.arrow.up", "exclamationmark.triangle",
    "questionmark.circle", "info.circle", "line.3.horizontal", "bolt.horizontal.circle",
    "clock", "globe", "lock", "circle.lefthalf.filled",
    "arrow.up.and.down", "chevron.left.forwardslash.chevron.right", "person", "no.such.symbol",
};
enum { N = sizeof names / sizeof *names, S = 32, COLS = 8 };

int main(void) {
    @autoreleasepool {
        int rows = (N + COLS - 1) / COLS, W = COLS * S, H = rows * S;
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, W * 4, rgb,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGContextSetRGBFillColor(c, 1, 1, 1, 1);
        CGContextFillRect(c, CGRectMake(0, 0, W, H));
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:c flipped:NO]];
        for (int i = 0; i < N; i++) {
            NSImage *img = [NSImage imageWithSystemSymbolName:@(names[i]) accessibilityDescription:nil];
            CHECK(img != nil);
            int col = i % COLS, row = i / COLS;
            [img drawInRect:NSMakeRect(col * S + 4, H - (row + 1) * S + 4, S - 8, S - 8)];
        }
        const unsigned char *px = CGBitmapContextGetData(c);
        for (int i = 0; i < N; i++) {
            int col = i % COLS, row = i / COLS, ink = 0;
            for (int y = row * S; y < (row + 1) * S; y++)
                for (int x = col * S; x < (col + 1) * S; x++) ink += px[(y * W + x) * 4] < 0x80;
            if (ink < 12) printf("no ink for %s\n", names[i]);
            CHECK(ink >= 12);
        }
        /* xmark.circle.fill: the centre is knocked out, the ring around it filled */
        int col = 7 % COLS, row = 7 / COLS, cx = col * S + S / 2, cy = row * S + S / 2;
        CHECK(px[(cy * W + cx) * 4] > 0xC0);
        CHECK(px[(cy * W + cx + 5) * 4] < 0x80);
        if (getenv("SYMBOLS_PPM")) {
            FILE *f = fopen(getenv("SYMBOLS_PPM"), "wb");
            fprintf(f, "P6 %d %d 255\n", W, H);
            for (int i = 0; i < W * H; i++) fputc(px[i * 4 + 2], f), fputc(px[i * 4 + 1], f), fputc(px[i * 4], f);
            fclose(f);
        }
        printf("ok\n");
    }
    return 0;
}
