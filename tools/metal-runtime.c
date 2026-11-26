/* Textures for shaders compiled by metal-compile.py: reading and sampling
 * the textures bitten's software Metal device hands them. Compiled into
 * each shaders.so. The layouts below are shared with frameworks/Metal. */
#include <math.h>
#include <stddef.h>
#include <stdint.h>

struct bn_mtl_texture {
    uint8_t *data;
    int32_t width, height, bytes_per_row;
    int32_t format;           /* 0 R8, 1 RGBA8, 2 BGRA8, 3 RGBA32F, 4 RG8, 5 RGBA16F, 6 RGBA8 sRGB, 7 BGRA8 sRGB */
};

/* AIR's constexpr sampler state (first word): the filters and whether
 * coordinates are in pixels. */
#define SMP_LINEAR(v) ((((v) >> 9) & 1) || (((v) >> 11) & 1))
#define SMP_PIXEL(v) (((v) >> 15) & 1)

static float half_to_float(uint16_t h) {
    uint32_t s = (uint32_t)(h & 0x8000) << 16, e = (h >> 10) & 0x1f, m = h & 0x3ff, f;
    if (e == 0) {
        if (!m) f = s;
        else {
            e = 127 - 15 + 1;
            while (!(m & 0x400)) { m <<= 1; e--; }
            f = s | e << 23 | (m & 0x3ff) << 13;
        }
    } else if (e == 31) {
        f = s | 0x7f800000 | m << 13;
    } else {
        f = s | (e + 127 - 15) << 23 | m << 13;
    }
    float r;
    __builtin_memcpy(&r, &f, 4);
    return r;
}

static void texel(const struct bn_mtl_texture *t, int x, int y, float *o) {
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x >= t->width) x = t->width - 1;
    if (y >= t->height) y = t->height - 1;
    if (!t->data || t->width <= 0 || t->height <= 0) {
        o[0] = o[1] = o[2] = 0;
        o[3] = 1;
        return;
    }
    const uint8_t *p = t->data + (size_t)y * (size_t)t->bytes_per_row;
    switch (t->format) {
    case 0: o[0] = p[x] / 255.0f; o[1] = 0; o[2] = 0; o[3] = 1; break;
    case 4: o[0] = p[2 * x] / 255.0f; o[1] = p[2 * x + 1] / 255.0f; o[2] = 0; o[3] = 1; break;
    case 1: case 6: o[0] = p[4 * x] / 255.0f; o[1] = p[4 * x + 1] / 255.0f; o[2] = p[4 * x + 2] / 255.0f; o[3] = p[4 * x + 3] / 255.0f; break;
    case 2: case 7: o[2] = p[4 * x] / 255.0f; o[1] = p[4 * x + 1] / 255.0f; o[0] = p[4 * x + 2] / 255.0f; o[3] = p[4 * x + 3] / 255.0f; break;
    case 3: __builtin_memcpy(o, p + 16 * x, 16); break;
    case 5: for (int i = 0; i < 4; i++) o[i] = half_to_float(((const uint16_t *)p)[4 * x + i]); break;
    default: o[0] = o[1] = o[2] = 0; o[3] = 1;
    }
    if (t->format == 6 || t->format == 7)
        for (int i = 0; i < 3; i++) o[i] = o[i] <= 0.04045f ? o[i] / 12.92f : powf((o[i] + 0.055f) / 1.055f, 2.4f);
}

int32_t bn_tex_width(const struct bn_mtl_texture *t) { return t ? t->width : 0; }
int32_t bn_tex_height(const struct bn_mtl_texture *t) { return t ? t->height : 0; }

void bn_tex_read(const struct bn_mtl_texture *t, int32_t x, int32_t y, float *out) {
    if (!t) {
        out[0] = out[1] = out[2] = out[3] = 0;
        return;
    }
    texel(t, x, y, out);
}

void bn_tex_sample(const struct bn_mtl_texture *t, const uint64_t *state, float u, float v, float *out) {
    if (!t || t->width <= 0) {
        out[0] = out[1] = out[2] = out[3] = 0;
        return;
    }
    uint64_t s = state ? state[0] : 0;
    float x = SMP_PIXEL(s) ? u : u * (float)t->width, y = SMP_PIXEL(s) ? v : v * (float)t->height;
    if (!SMP_LINEAR(s)) {
        texel(t, (int)floorf(x), (int)floorf(y), out);
        return;
    }
    x -= 0.5f;
    y -= 0.5f;
    int x0 = (int)floorf(x), y0 = (int)floorf(y);
    float fx = x - (float)x0, fy = y - (float)y0;
    float a[4], b[4], c[4], d[4];
    texel(t, x0, y0, a);
    texel(t, x0 + 1, y0, b);
    texel(t, x0, y0 + 1, c);
    texel(t, x0 + 1, y0 + 1, d);
    for (int i = 0; i < 4; i++) {
        float top = a[i] + (b[i] - a[i]) * fx, bot = c[i] + (d[i] - c[i]) * fx;
        out[i] = top + (bot - top) * fy;
    }
}
