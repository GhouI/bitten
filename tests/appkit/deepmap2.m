// The deepmap2 bitmaps of compiled asset catalogs: a hand-made 2x2 ARGB
// blob (alpha plane, a predictor per row, sign-magnitude YCoCg residuals,
// high bytes before low bytes) in a stored LZFSE block decodes to the
// colours it encodes.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)
CGImageRef bn_deepmap2_image(const void *bytes, size_t n);

static void put16(uint8_t *hi, uint8_t *lo, int i, int v) {
    unsigned e = v < 0 ? ((unsigned)-v << 1) | 1 : (unsigned)v << 1;
    hi[i] = (uint8_t)(e >> 8);
    lo[i] = (uint8_t)e;
}

int main(void) {
    @autoreleasepool {
        enum { W = 2, H = 2, N = W * H };
        /* pixels (200,40,0), (0,200,0) / (0,0,200), (200,200,200); YCoCg
         * (Y, Co, Cg) with R = Y - Cg + Co, G = Y + Cg, B = Y - Cg - Co */
        int ycocg[N][3] = {{70, 100, -30}, {100, 0, 100}, {50, -100, -50}, {200, 0, 0}};
        uint8_t raw[N + H + 6 * N];
        uint8_t *alpha = raw, *pred = raw + N, *hi = pred + H, *lo = hi + 3 * N;
        memset(alpha, 255, N);
        alpha[3] = 128;
        pred[0] = 0;
        pred[1] = 3; /* row 1 adds the row above */
        for (int p = 0; p < N; p++)
            for (int c = 0; c < 3; c++) {
                int v = ycocg[p][c];
                if (p >= W) v -= ycocg[p - W][c];
                put16(hi, lo, p * 3 + c, v);
            }
        /* stored LZFSE: "bvx-", raw size, bytes, "bvx$" */
        uint8_t lz[8 + sizeof raw + 4];
        memcpy(lz, "bvx-", 4);
        uint32_t rawlen = sizeof raw;
        memcpy(lz + 4, &rawlen, 4);
        memcpy(lz + 8, raw, sizeof raw);
        memcpy(lz + 8 + sizeof raw, "bvx$", 4);
        uint8_t blob[16 + sizeof lz];
        memcpy(blob, "dmp2", 4);
        blob[4] = 2; blob[5] = 1; blob[6] = 0x0a; blob[7] = 4;
        blob[8] = W; blob[9] = 0; blob[10] = H; blob[11] = 0;
        uint32_t seg = sizeof lz;
        memcpy(blob + 12, &seg, 4);
        memcpy(blob + 16, lz, sizeof lz);
        CGImageRef img = bn_deepmap2_image(blob, sizeof blob);
        CHECK(img != NULL);
        CHECK(CGImageGetWidth(img) == W && CGImageGetHeight(img) == H);
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, W * 4, rgb, kCGImageAlphaPremultipliedLast);
        CGContextDrawImage(c, CGRectMake(0, 0, W, H), img);
        const uint8_t *px = CGBitmapContextGetData(c); /* rows from the top */
        CHECK(px[0] == 200 && px[1] == 40 && px[2] == 0 && px[3] == 255);
        CHECK(px[4] == 0 && px[5] == 200 && px[6] == 0);
        CHECK(px[8] == 0 && px[9] == 0 && px[10] == 200);
        CHECK(px[15] == 128 && px[12] >= 99 && px[12] <= 101); /* grey at half alpha, premultiplied */
        printf("ok\n");
    }
    return 0;
}
