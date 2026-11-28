// CoreImage's QR code generator: the symbol's size for the message and
// level, its margin, finder and timing patterns. With BITTEN_QR_OUT=dir
// the codes are also written there as PGM images (for a decoder to read;
// OpenCV's QRCodeDetectorAruco reads them all).
#import <CoreImage/CoreImage.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

/* The image's pixels, dark as 1, rows from the top. */
static uint8_t *modules(CIImage *img, int *side) {
    CIContext *ctx = [CIContext context];
    CGImageRef cg = [ctx createCGImage:img fromRect:img.extent];
    CHECK(cg != NULL);
    int w = (int)CGImageGetWidth(cg), h = (int)CGImageGetHeight(cg);
    CHECK(w == h);
    uint8_t *px = calloc((size_t)w * h, 4);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(px, w, h, 8, w * 4, rgb, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(c, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(c);
    CGColorSpaceRelease(rgb);
    CGImageRelease(cg);
    uint8_t *m = malloc((size_t)w * h);
    for (int i = 0; i < w * h; i++) m[i] = px[i * 4] < 128;
    free(px);
    *side = w;
    return m;
}

static void check_finder(const uint8_t *m, int side, int x0, int y0) {
    for (int dy = 0; dy < 7; dy++)
        for (int dx = 0; dx < 7; dx++) {
            int ring = dx == 0 || dy == 0 || dx == 6 || dy == 6;
            int core = dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4;
            CHECK(m[(y0 + dy) * side + x0 + dx] == (ring || core));
        }
}

static void one(const char *text, NSString *level, int wantModules, const char *outName) {
    CIFilter *f = [CIFilter QRCodeGenerator];
    CHECK(f && [f.name isEqualToString:@"CIQRCodeGenerator"] && [f.correctionLevel isEqualToString:@"M"]);
    f.message = [NSData dataWithBytes:text length:strlen(text)];
    if (level) f.correctionLevel = level;
    CIImage *img = f.outputImage;
    CHECK(img != nil);
    int side = 0;
    uint8_t *m = modules(img, &side);
    int n = side - 2;
    CHECK(n == wantModules);
    for (int i = 0; i < side; i++)   /* a light margin all round */
        CHECK(!m[i] && !m[(side - 1) * side + i] && !m[i * side] && !m[i * side + side - 1]);
    check_finder(m, side, 1, 1);
    check_finder(m, side, side - 8, 1);
    check_finder(m, side, 1, side - 8);
    for (int i = 8; i < n - 8; i++) {   /* timing patterns */
        CHECK(m[7 * side + 1 + i] == (i % 2 == 0));
        CHECK(m[(1 + i) * side + 7] == (i % 2 == 0));
    }
    CHECK(m[(1 + n - 8) * side + 1 + 8]);   /* the dark module */
    const char *dir = getenv("BITTEN_QR_OUT");
    if (dir) {
        char path[512];
        snprintf(path, sizeof path, "%s/%s.pgm", dir, outName);
        FILE *fp = fopen(path, "wb");
        int scale = 8;
        fprintf(fp, "P5 %d %d 255\n", (side + 6) * scale, (side + 6) * scale);
        for (int y = 0; y < (side + 6) * scale; y++)
            for (int x = 0; x < (side + 6) * scale; x++) {
                int mx = x / scale - 3, my = y / scale - 3;
                int dark = mx >= 0 && my >= 0 && mx < side && my < side && m[my * side + mx];
                fputc(dark ? 0 : 255, fp);
            }
        fclose(fp);
    }
    free(m);
}

int main(void) {
    @autoreleasepool {
        one("hello", nil, 21, "v1m");                                          /* version 1 */
        one("https://example.com/pair?code=123456", @"H", 37, "v5h");          /* version 5 */
        one("https://example.com/pair?code=123456", @"L", 29, "v3l");          /* version 3 */
        char longer[301];
        for (int i = 0; i < 300; i++) longer[i] = (char)('a' + i % 26);
        longer[300] = 0;
        one(longer, @"Q", 81, "v16q");                                         /* version 16 */
        char huge[3000];
        memset(huge, 'x', sizeof huge - 1);
        huge[sizeof huge - 1] = 0;
        CIFilter *f = [CIFilter QRCodeGenerator];
        f.message = [NSData dataWithBytes:huge length:strlen(huge)];
        f.correctionLevel = @"H";
        CHECK(f.outputImage == nil);   /* more than version 40 holds */
    }
    puts("qrcode ok");
    return 0;
}
