/* JPEG through ImageIO: 4:4:4 and 4:2:0 colour, grey with sizes that are
 * not multiples of 8; progressive files are recognised but not decoded. */
#include "darwin.h"
#include "jpeg_samples.h"

typedef const void *Ref;
Ref CFDataCreate(Ref, const uint8_t *, long);
const uint8_t *CFDataGetBytePtr(Ref);
Ref CGImageSourceCreateWithData(Ref, Ref);
size_t CGImageSourceGetCount(Ref);
Ref CGImageSourceCreateImageAtIndex(Ref, size_t, Ref);
size_t CGImageGetWidth(Ref), CGImageGetHeight(Ref);
Ref CGImageGetDataProvider(Ref);
Ref CGDataProviderCopyData(Ref);

static const uint8_t *decode(const unsigned char *bytes, long n, size_t *w, size_t *h) {
    Ref src = CGImageSourceCreateWithData(CFDataCreate(0, bytes, n), 0);
    Ref img = CGImageSourceCreateImageAtIndex(src, 0, 0);
    if (!img) return 0;
    *w = CGImageGetWidth(img);
    *h = CGImageGetHeight(img);
    return CFDataGetBytePtr(CGDataProviderCopyData(CGImageGetDataProvider(img)));
}

static int close_to(const uint8_t *p, int r, int g, int b) {
    int dr = p[0] - r, dg = p[1] - g, db = p[2] - b;
    return dr * dr < 400 && dg * dg < 400 && db * db < 400 && p[3] == 255;
}

int main(void) {
    size_t w, h;
    const uint8_t *p;
    const unsigned char *colour[2] = {jpeg444, jpeg420};
    long sizes[2] = {sizeof jpeg444, sizeof jpeg420};
    for (int i = 0; i < 2; i++) {
        p = decode(colour[i], sizes[i], &w, &h);
        CHECK(p && w == 32 && h == 24);
        CHECK(close_to(p + (4 * 32 + 4) * 4, 255, 0, 0));          /* top left: red */
        CHECK(close_to(p + (4 * 32 + 27) * 4, 0, 0, 255));         /* top right: blue */
        CHECK(close_to(p + (19 * 32 + 4) * 4, 0, 200, 0));         /* bottom left: green */
        CHECK(close_to(p + (19 * 32 + 27) * 4, 250, 250, 250));    /* bottom right */
    }
    p = decode(jpeg_grey, sizeof jpeg_grey, &w, &h);
    CHECK(p && w == 17 && h == 9);
    CHECK(p[0] == p[1] && p[1] == p[2]);                           /* grey */
    CHECK(close_to(p + (7 * 17 + 14) * 4, 250, 250, 250));
    Ref prog = CGImageSourceCreateWithData(CFDataCreate(0, jpeg_progressive, sizeof jpeg_progressive), 0);
    CHECK(CGImageSourceGetCount(prog) == 0);
    puts("jpeg ok");
    return 0;
}
