/* ImageIO (PNG sources: RGBA with filters, an interlaced 2-bit palette
 * with tRNS, 16-bit grey), Accelerate (vDSP's real FFT packing and
 * scaling, vImage conversions) and ServiceManagement's refusals. */
#include "darwin.h"

typedef const void *Ref;
double cos(double), sin(double), fabs(double);
Ref CFDataCreate(Ref, const uint8_t *, long);
const uint8_t *CFDataGetBytePtr(Ref);
long CFDataGetLength(Ref);
void CFRelease(Ref);
unsigned char CFEqual(Ref, Ref);
Ref CFStringCreateWithCString(Ref, const char *, unsigned int);
Ref CFDictionaryGetValue(Ref, Ref);
unsigned char CFNumberGetValue(Ref, long, void *);
long CFErrorGetCode(Ref);
int compress(uint8_t *, unsigned long *, const uint8_t *, unsigned long);
unsigned long crc32(unsigned long, const uint8_t *, unsigned int);
Ref CGImageSourceCreateWithData(Ref, Ref);
size_t CGImageSourceGetCount(Ref);
Ref CGImageSourceGetType(Ref);
int CGImageSourceGetStatus(Ref);
Ref CGImageSourceCreateImageAtIndex(Ref, size_t, Ref);
Ref CGImageSourceCopyPropertiesAtIndex(Ref, size_t, Ref);
extern Ref kCGImagePropertyPixelWidth;
size_t CGImageGetWidth(Ref), CGImageGetHeight(Ref);
Ref CGImageGetDataProvider(Ref);
Ref CGDataProviderCopyData(Ref);

typedef struct { float *realp, *imagp; } DSPSplitComplex;
typedef struct { float real, imag; } DSPComplex;
void *vDSP_create_fftsetup(unsigned long, int);
void vDSP_destroy_fftsetup(void *);
void vDSP_fft_zrip(void *, const DSPSplitComplex *, long, unsigned long, int);
void vDSP_ctoz(const DSPComplex *, long, const DSPSplitComplex *, long, unsigned long);
void vDSP_ztoc(const DSPSplitComplex *, long, DSPComplex *, long, unsigned long);
void vDSP_vsmul(const float *, long, const float *, float *, long, unsigned long);
typedef struct { void *data; unsigned long height, width; size_t rowBytes; } vImage_Buffer;
long vImageConvert_RGB888toRGBA8888(const vImage_Buffer *, const vImage_Buffer *, uint8_t, const vImage_Buffer *, _Bool, unsigned);
long vImagePremultiplyData_RGBA8888(const vImage_Buffer *, const vImage_Buffer *, unsigned);
extern Ref kSMDomainUserLaunchd;
unsigned char SMJobSubmit(Ref, Ref, Ref, Ref *);
unsigned char SMJobRemove(Ref, Ref, Ref, unsigned char, Ref *);

/* ---- building PNG files ---- */
static uint8_t png[4096];
static size_t plen;
static void be(uint32_t v) { png[plen++] = v >> 24; png[plen++] = v >> 16; png[plen++] = v >> 8; png[plen++] = v; }
static void chunk(const char *type, const uint8_t *body, uint32_t n) {
    be(n);
    size_t start = plen;
    memcpy(png + plen, type, 4); plen += 4;
    if (n) memcpy(png + plen, body, n);
    plen += n;
    be((uint32_t)crc32(0, png + start, (unsigned)(n + 4)));
}
static void begin(uint32_t w, uint32_t h, int depth, int type, int interlace) {
    static const uint8_t sig[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    memcpy(png, sig, 8);
    plen = 8;
    uint8_t ihdr[13] = {w >> 24, w >> 16, w >> 8, w, h >> 24, h >> 16, h >> 8, h, depth, type, 0, 0, interlace};
    chunk("IHDR", ihdr, 13);
}
static void finish(const uint8_t *raw, unsigned long n) {
    uint8_t z[1024];
    unsigned long zn = sizeof z;
    CHECK(compress(z, &zn, raw, n) == 0);
    chunk("IDAT", z, (uint32_t)zn);
    chunk("IEND", NULL, 0);
}
static const uint8_t *pixels(Ref *keep, size_t *w, size_t *h) {
    Ref data = CFDataCreate(NULL, png, (long)plen);
    Ref src = CGImageSourceCreateWithData(data, NULL);
    CHECK(src && CGImageSourceGetStatus(src) == 0 && CGImageSourceGetCount(src) == 1);
    Ref img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CHECK(img);
    *w = CGImageGetWidth(img);
    *h = CGImageGetHeight(img);
    *keep = CGDataProviderCopyData(CGImageGetDataProvider(img));
    return CFDataGetBytePtr(*keep);
}

int main(void) {
    Ref keep;
    size_t w, h;

    /* 2x2 RGBA: row 0 with Sub, row 1 with Up. */
    begin(2, 2, 8, 6, 0);
    /* Sub: pixel 1 = pixel 0 + (1, 255, 0, 0) mod 256 = green. Up: row 1
     * adds (0, 0, 255, 0) to red and nothing to green. */
    uint8_t raw1[] = {1, 255, 0, 0, 255, 1, 255, 0, 0,
                      2, 0, 0, 255, 0, 0, 0, 0, 0};
    finish(raw1, sizeof raw1);
    const uint8_t *p = pixels(&keep, &w, &h);
    CHECK(w == 2 && h == 2);
    CHECK(p[0] == 255 && p[1] == 0 && p[2] == 0 && p[3] == 255);
    CHECK(p[4] == 0 && p[5] == 255 && p[6] == 0 && p[7] == 255);
    CHECK(p[8] == 255 && p[9] == 0 && p[10] == 255 && p[11] == 255);   /* red + (0,0,255,0) */
    CHECK(p[15] == 255 && p[13] == 255);

    /* 3x3 interlaced 2-bit palette, index 1 transparent. */
    begin(3, 3, 2, 3, 1);
    uint8_t plte[] = {10, 20, 30, 200, 100, 50, 0, 0, 255};
    chunk("PLTE", plte, 9);
    uint8_t trns[] = {255, 0};
    chunk("tRNS", trns, 2);
    /* Adam7 passes for 3x3: pass 1 (0,0); pass 4 (2,0); pass 5 (0,2),(2,2);
     * pass 6 (1,0),(1,2); pass 7 rows 1: (0,1),(1,1),(2,1). Index = x%3. */
    uint8_t raw2[] = {0, 0x00,                         /* pass 1: (0,0)=0 */
                      0, 0x80,                         /* pass 4: (2,0)=2 */
                      0, 0x20,                         /* pass 5: (0,2)=0,(2,2)=2 -> 00 10 */
                      0, 0x40, 0, 0x40,                /* pass 6: (1,0)=1; (1,2)=1 */
                      0, 0x18};                        /* pass 7: row 1: 0,1,2 -> 00 01 10 */
    finish(raw2, sizeof raw2);
    p = pixels(&keep, &w, &h);
    CHECK(w == 3 && h == 3);
    for (int y = 0; y < 3; y++)
        for (int x = 0; x < 3; x++) {
            const uint8_t *q = p + (y * 3 + x) * 4;
            if (x == 0) CHECK(q[0] == 10 && q[1] == 20 && q[2] == 30 && q[3] == 255);
            if (x == 1) CHECK(q[3] == 0 && q[0] == 0);
            if (x == 2) CHECK(q[2] == 255 && q[3] == 255);
        }

    /* 1x1 16-bit grey. */
    begin(1, 1, 16, 0, 0);
    uint8_t raw3[] = {0, 0x80, 0x11};
    finish(raw3, sizeof raw3);
    p = pixels(&keep, &w, &h);
    CHECK(p[0] == 0x80 && p[1] == 0x80 && p[3] == 255);

    Ref data = CFDataCreate(NULL, png, (long)plen);
    Ref src = CGImageSourceCreateWithData(data, NULL);
    CHECK(CFEqual(CGImageSourceGetType(src), CFStringCreateWithCString(NULL, "public.png", 0x08000100)));
    int pw = 0;
    CHECK(CFNumberGetValue(CFDictionaryGetValue(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL), kCGImagePropertyPixelWidth), 3, &pw) && pw == 1);
    const uint8_t junk[] = {0xff, 0xd8, 0xff, 0xe0, 1, 2, 3};
    Ref jpeg = CGImageSourceCreateWithData(CFDataCreate(NULL, junk, sizeof junk), NULL);
    CHECK(CFEqual(CGImageSourceGetType(jpeg), CFStringCreateWithCString(NULL, "public.jpeg", 0x08000100)));
    CHECK(CGImageSourceGetCount(jpeg) == 0 && CGImageSourceCreateImageAtIndex(jpeg, 0, NULL) == NULL);
    png[20] ^= 0xff;                                  /* corrupt the IHDR */
    Ref bad = CGImageSourceCreateWithData(CFDataCreate(NULL, png, (long)plen), NULL);
    CHECK(CGImageSourceGetCount(bad) == 0);

    /* vDSP: x[n] = 1 + cos(2*pi*3n/16), N = 16. Forward: 2*X: DC 2*16, bin 3 2*8. */
    float x[16], re[8], im[8];
    for (int n = 0; n < 16; n++) x[n] = (float)(1 + cos(2 * 3.14159265358979 * 3 * n / 16));
    DSPSplitComplex z = {re, im};
    void *setup = vDSP_create_fftsetup(4, 0);
    CHECK(setup);
    vDSP_ctoz((const DSPComplex *)x, 2, &z, 1, 8);
    CHECK(re[1] == x[2] && im[1] == x[3]);
    vDSP_fft_zrip(setup, &z, 1, 4, 1);
    CHECK(fabs(re[0] - 32) < 1e-3 && fabs(im[0]) < 1e-3);
    CHECK(fabs(re[3] - 16) < 1e-3 && fabs(im[3]) < 1e-3);
    CHECK(fabs(re[1]) < 1e-3 && fabs(re[2]) < 1e-3 && fabs(re[5]) < 1e-3);
    vDSP_fft_zrip(setup, &z, 1, 4, -1);
    float scale = 1.0f / 32, y[16];
    vDSP_vsmul(re, 1, &scale, re, 1, 8);
    vDSP_vsmul(im, 1, &scale, im, 1, 8);
    vDSP_ztoc(&z, 1, (DSPComplex *)y, 2, 8);
    for (int n = 0; n < 16; n++) CHECK(fabs(y[n] - x[n]) < 1e-4);
    vDSP_destroy_fftsetup(setup);

    /* vImage */
    uint8_t rgb[6] = {255, 128, 0, 10, 20, 30}, rgba[8], out[8];
    vImage_Buffer s = {rgb, 1, 2, 6}, d = {rgba, 1, 2, 8}, o = {out, 1, 2, 8};
    CHECK(vImageConvert_RGB888toRGBA8888(&s, NULL, 128, &d, 0, 0) == 0);
    CHECK(rgba[0] == 255 && rgba[1] == 128 && rgba[3] == 128 && rgba[7] == 128);
    CHECK(vImagePremultiplyData_RGBA8888(&d, &o, 0) == 0 && out[0] == 128 && out[1] == 64 && out[3] == 128);
    vImage_Buffer small = {out, 1, 1, 8};
    CHECK(vImagePremultiplyData_RGBA8888(&d, &small, 0) == -21774);

    /* ServiceManagement */
    Ref err = NULL;
    CHECK(!SMJobSubmit(kSMDomainUserLaunchd, NULL, NULL, &err) && err && CFErrorGetCode(err) == 2);
    CHECK(!SMJobRemove(kSMDomainUserLaunchd, NULL, NULL, 1, &err) && CFErrorGetCode(err) == 6);

    puts("imageio/accelerate ok");
    return 0;
}
