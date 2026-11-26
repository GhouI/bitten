/* Accelerate: the vDSP and vImage functions programs use, in plain C.
 * vDSP's real FFT follows Apple's packing and scaling: a real signal of
 * 2^n samples goes in as a split complex of 2^(n-1) (even samples in the
 * real part, odd in the imaginary, see vDSP_ctoz); out of the forward
 * transform come twice the DFT's values, with X[0] in realp[0] and X[N/2]
 * in imagp[0]. The inverse leaves 2N times the signal. */
#include <math.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "dx.h"

typedef long vDSP_Stride;
typedef unsigned long vDSP_Length;
typedef struct { float *realp, *imagp; } DSPSplitComplex;
typedef struct { float real, imag; } DSPComplex;
enum { FFT_FORWARD = 1, FFT_INVERSE = -1 };

struct fft_setup {
    unsigned log2n;
    double *cosv, *sinv;                    /* the twiddles of a 2^log2n transform */
};

static struct fft_setup *d_vDSP_create_fftsetup(vDSP_Length log2n, int radix) {
    if (log2n > 24) return NULL;
    struct fft_setup *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    size_t n = (size_t)1 << log2n;
    s->log2n = (unsigned)log2n;
    s->cosv = malloc(n * sizeof(double));
    s->sinv = malloc(n * sizeof(double));
    if (!s->cosv || !s->sinv) { free(s->cosv); free(s->sinv); free(s); return NULL; }
    for (size_t k = 0; k < n; k++) {
        s->cosv[k] = cos(2 * M_PI * (double)k / (double)n);
        s->sinv[k] = sin(2 * M_PI * (double)k / (double)n);
    }
    return s;
}
DX_FN(vDSP_create_fftsetup);

static void d_vDSP_destroy_fftsetup(struct fft_setup *s) {
    if (!s) return;
    free(s->cosv);
    free(s->sinv);
    free(s);
}
DX_FN(vDSP_destroy_fftsetup);

/* In-place complex FFT of n = 2^log2n points (sign -1 forward, +1 inverse),
 * with twiddles from a setup for a transform at least this long. */
static void fft(const struct fft_setup *s, double *re, double *im, unsigned log2n, int sign) {
    size_t n = (size_t)1 << log2n, step = (size_t)1 << (s->log2n - log2n);
    for (size_t i = 1, j = 0; i < n; i++) {
        size_t bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            double t = re[i]; re[i] = re[j]; re[j] = t;
            t = im[i]; im[i] = im[j]; im[j] = t;
        }
    }
    for (size_t len = 2; len <= n; len <<= 1) {
        size_t half = len / 2, stride = (n / len) * step;
        for (size_t i = 0; i < n; i += len)
            for (size_t k = 0; k < half; k++) {
                double c = s->cosv[k * stride], sn = sign * s->sinv[k * stride];
                double xr = re[i + k + half] * c - im[i + k + half] * sn;
                double xi = re[i + k + half] * sn + im[i + k + half] * c;
                re[i + k + half] = re[i + k] - xr;
                im[i + k + half] = im[i + k] - xi;
                re[i + k] += xr;
                im[i + k] += xi;
            }
    }
}

static void d_vDSP_fft_zrip(struct fft_setup *s, const DSPSplitComplex *c, vDSP_Stride stride, vDSP_Length log2n,
                            int direction) {
    if (!s || !c || log2n < 1 || log2n > s->log2n) return;
    size_t n = (size_t)1 << log2n, h = n / 2;
    double *re = calloc(n, sizeof(double)), *im = calloc(n, sizeof(double));
    if (!re || !im) { free(re); free(im); return; }
    if (direction == FFT_FORWARD) {
        for (size_t k = 0; k < h; k++) {
            re[2 * k] = c->realp[k * (size_t)stride];
            re[2 * k + 1] = c->imagp[k * (size_t)stride];
        }
        fft(s, re, im, (unsigned)log2n, -1);
        c->realp[0] = (float)(2 * re[0]);
        c->imagp[0] = (float)(2 * re[h]);
        for (size_t k = 1; k < h; k++) {
            c->realp[k * (size_t)stride] = (float)(2 * re[k]);
            c->imagp[k * (size_t)stride] = (float)(2 * im[k]);
        }
    } else {
        re[0] = c->realp[0];
        re[h] = c->imagp[0];
        for (size_t k = 1; k < h; k++) {
            re[k] = c->realp[k * (size_t)stride];
            im[k] = c->imagp[k * (size_t)stride];
            re[n - k] = re[k];
            im[n - k] = -im[k];
        }
        fft(s, re, im, (unsigned)log2n, +1);
        for (size_t k = 0; k < h; k++) {
            c->realp[k * (size_t)stride] = (float)re[2 * k];
            c->imagp[k * (size_t)stride] = (float)re[2 * k + 1];
        }
    }
    free(re);
    free(im);
}
DX_FN(vDSP_fft_zrip);

/* Complex (interleaved) to split complex, and back. Strides count floats
 * on the interleaved side in pairs, as Apple's do (2 = contiguous). */
static void d_vDSP_ctoz(const DSPComplex *c, vDSP_Stride ic, const DSPSplitComplex *z, vDSP_Stride iz, vDSP_Length n) {
    for (vDSP_Length i = 0; i < n; i++) {
        z->realp[i * (size_t)iz] = c[i * (size_t)ic / 2].real;
        z->imagp[i * (size_t)iz] = c[i * (size_t)ic / 2].imag;
    }
}
DX_FN(vDSP_ctoz);
static void d_vDSP_ztoc(const DSPSplitComplex *z, vDSP_Stride iz, DSPComplex *c, vDSP_Stride ic, vDSP_Length n) {
    for (vDSP_Length i = 0; i < n; i++) {
        c[i * (size_t)ic / 2].real = z->realp[i * (size_t)iz];
        c[i * (size_t)ic / 2].imag = z->imagp[i * (size_t)iz];
    }
}
DX_FN(vDSP_ztoc);

static void d_vDSP_vsmul(const float *a, vDSP_Stride ia, const float *b, float *c, vDSP_Stride ic, vDSP_Length n) {
    for (vDSP_Length i = 0; i < n; i++) c[i * (size_t)ic] = a[i * (size_t)ia] * *b;
}
DX_FN(vDSP_vsmul);
static void d_vDSP_vadd(const float *a, vDSP_Stride ia, const float *b, vDSP_Stride ib, float *c, vDSP_Stride ic,
                        vDSP_Length n) {
    for (vDSP_Length i = 0; i < n; i++) c[i * (size_t)ic] = a[i * (size_t)ia] + b[i * (size_t)ib];
}
DX_FN(vDSP_vadd);
static void d_vDSP_vmul(const float *a, vDSP_Stride ia, const float *b, vDSP_Stride ib, float *c, vDSP_Stride ic,
                        vDSP_Length n) {
    for (vDSP_Length i = 0; i < n; i++) c[i * (size_t)ic] = a[i * (size_t)ia] * b[i * (size_t)ib];
}
DX_FN(vDSP_vmul);
static void d_vDSP_zvabs(const DSPSplitComplex *a, vDSP_Stride ia, float *c, vDSP_Stride ic, vDSP_Length n) {
    for (vDSP_Length i = 0; i < n; i++)
        c[i * (size_t)ic] = hypotf(a->realp[i * (size_t)ia], a->imagp[i * (size_t)ia]);
}
DX_FN(vDSP_zvabs);
static void d_vDSP_zvmags(const DSPSplitComplex *a, vDSP_Stride ia, float *c, vDSP_Stride ic, vDSP_Length n) {
    for (vDSP_Length i = 0; i < n; i++) {
        float r = a->realp[i * (size_t)ia], m = a->imagp[i * (size_t)ia];
        c[i * (size_t)ic] = r * r + m * m;
    }
}
DX_FN(vDSP_zvmags);
static void d_vDSP_maxv(const float *a, vDSP_Stride ia, float *c, vDSP_Length n) {
    float m = -INFINITY;
    for (vDSP_Length i = 0; i < n; i++) if (a[i * (size_t)ia] > m) m = a[i * (size_t)ia];
    *c = m;
}
DX_FN(vDSP_maxv);
static void d_vDSP_meanv(const float *a, vDSP_Stride ia, float *c, vDSP_Length n) {
    double s = 0;
    for (vDSP_Length i = 0; i < n; i++) s += a[i * (size_t)ia];
    *c = n ? (float)(s / (double)n) : 0;
}
DX_FN(vDSP_meanv);
static void d_vDSP_rmsqv(const float *a, vDSP_Stride ia, float *c, vDSP_Length n) {
    double s = 0;
    for (vDSP_Length i = 0; i < n; i++) s += (double)a[i * (size_t)ia] * a[i * (size_t)ia];
    *c = n ? (float)sqrt(s / (double)n) : 0;
}
DX_FN(vDSP_rmsqv);

/* ---- vImage ---- */

typedef struct { void *data; unsigned long height, width; size_t rowBytes; } vImage_Buffer;
#define kvImageNoError 0
#define kvImageBufferSizeMismatch (-21774)
#define kvImageNullPointerArgument (-21772)

static long d_vImageConvert_RGB888toRGBA8888(const vImage_Buffer *src, const vImage_Buffer *alpha, uint8_t a,
                                             const vImage_Buffer *dst, bool premultiply, uint32_t flags) {
    if (!src || !dst || !src->data || !dst->data) return kvImageNullPointerArgument;
    if (src->width != dst->width || src->height != dst->height) return kvImageBufferSizeMismatch;
    for (unsigned long y = 0; y < src->height; y++) {
        const uint8_t *s = (const uint8_t *)src->data + y * src->rowBytes;
        const uint8_t *al = alpha && alpha->data ? (const uint8_t *)alpha->data + y * alpha->rowBytes : NULL;
        uint8_t *d = (uint8_t *)dst->data + y * dst->rowBytes;
        for (unsigned long x = 0; x < src->width; x++) {
            uint8_t av = al ? al[x] : a;
            for (int c = 0; c < 3; c++) d[x * 4 + c] = premultiply ? (uint8_t)((s[x * 3 + c] * av + 127) / 255) : s[x * 3 + c];
            d[x * 4 + 3] = av;
        }
    }
    return kvImageNoError;
}
DX_FN(vImageConvert_RGB888toRGBA8888);

static long d_vImagePremultiplyData_RGBA8888(const vImage_Buffer *src, const vImage_Buffer *dst, uint32_t flags) {
    if (!src || !dst || !src->data || !dst->data) return kvImageNullPointerArgument;
    if (src->width != dst->width || src->height != dst->height) return kvImageBufferSizeMismatch;
    for (unsigned long y = 0; y < src->height; y++) {
        const uint8_t *s = (const uint8_t *)src->data + y * src->rowBytes;
        uint8_t *d = (uint8_t *)dst->data + y * dst->rowBytes;
        for (unsigned long x = 0; x < src->width; x++) {
            uint8_t a = s[x * 4 + 3];
            for (int c = 0; c < 3; c++) d[x * 4 + c] = (uint8_t)((s[x * 4 + c] * a + 127) / 255);
            d[x * 4 + 3] = a;
        }
    }
    return kvImageNoError;
}
DX_FN(vImagePremultiplyData_RGBA8888);

static long d_vImageUnpremultiplyData_RGBA8888(const vImage_Buffer *src, const vImage_Buffer *dst, uint32_t flags) {
    if (!src || !dst || !src->data || !dst->data) return kvImageNullPointerArgument;
    if (src->width != dst->width || src->height != dst->height) return kvImageBufferSizeMismatch;
    for (unsigned long y = 0; y < src->height; y++) {
        const uint8_t *s = (const uint8_t *)src->data + y * src->rowBytes;
        uint8_t *d = (uint8_t *)dst->data + y * dst->rowBytes;
        for (unsigned long x = 0; x < src->width; x++) {
            uint8_t a = s[x * 4 + 3];
            for (int c = 0; c < 3; c++) {
                unsigned v = a ? (s[x * 4 + c] * 255u + a / 2) / a : 0;
                d[x * 4 + c] = (uint8_t)(v > 255 ? 255 : v);
            }
            d[x * 4 + 3] = a;
        }
    }
    return kvImageNoError;
}
DX_FN(vImageUnpremultiplyData_RGBA8888);
