/* CoreGraphics: pixel formats, data providers and images. An image keeps
 * its pixels converted to premultiplied RGBA (rows top to bottom) for
 * drawing, and the provider it was made from for programs that read the
 * bytes back. */
#include <string.h>

#include "cg.h"

typedef const void *CFDataRef;

enum {
    ALPHA_NONE = 0, ALPHA_PREMULTIPLIED_LAST = 1, ALPHA_PREMULTIPLIED_FIRST = 2, ALPHA_LAST = 3,
    ALPHA_FIRST = 4, ALPHA_NONE_SKIP_LAST = 5, ALPHA_NONE_SKIP_FIRST = 6, ALPHA_ONLY = 7,
    ALPHA_INFO_MASK = 0x1f, FLOAT_COMPONENTS = 0x100, BYTE_ORDER_MASK = 0x7000,
    BYTE_ORDER_16_LITTLE = 0x1000, BYTE_ORDER_32_LITTLE = 0x2000,
};

bool cg_format_for(const struct cg_colorspace *space, size_t bpc, size_t bpp, uint32_t info, struct cg_format *f) {
    int alpha = info & ALPHA_INFO_MASK;
    bool little = (info & BYTE_ORDER_MASK) == BYTE_ORDER_32_LITTLE || (info & BYTE_ORDER_MASK) == BYTE_ORDER_16_LITTLE;
    memset(f, 0, sizeof *f);
    f->a = -1;
    if (bpc != 8 || (info & FLOAT_COMPONENTS)) return false;
    if (alpha == ALPHA_ONLY) {
        if (bpp != 8) return false;
        f->bytes = 1;
        f->alpha_only = true;
        return true;
    }
    if (!space) return false;
    f->straight = alpha == ALPHA_LAST || alpha == ALPHA_FIRST;
    if (space->model == CG_GRAY) {
        f->gray = true;
        if (bpp == 8 && alpha == ALPHA_NONE) { f->bytes = 1; return true; }
        if (bpp == 16) {
            f->bytes = 2;
            bool first = alpha == ALPHA_PREMULTIPLIED_FIRST || alpha == ALPHA_FIRST || alpha == ALPHA_NONE_SKIP_FIRST;
            if (little) first = !first;
            if (alpha == ALPHA_NONE_SKIP_LAST || alpha == ALPHA_NONE_SKIP_FIRST) { f->r = first ? 1 : 0; return true; }
            f->r = first ? 1 : 0;
            f->a = first ? 0 : 1;
            return true;
        }
        return false;
    }
    if (bpp == 24 && alpha == ALPHA_NONE) {
        f->bytes = 3;
        f->r = 0; f->g = 1; f->b = 2;
        return true;
    }
    if (bpp != 32) return false;
    f->bytes = 4;
    bool first = alpha == ALPHA_PREMULTIPLIED_FIRST || alpha == ALPHA_FIRST || alpha == ALPHA_NONE_SKIP_FIRST;
    int o[4];                          /* memory order of A,R,G,B or R,G,B,A */
    if (first) { o[0] = 0; o[1] = 1; o[2] = 2; o[3] = 3; }   /* A R G B */
    else { o[0] = 3; o[1] = 0; o[2] = 1; o[3] = 2; }         /* R G B A: a at 3 */
    if (little) for (int i = 0; i < 4; i++) o[i] = 3 - o[i];
    f->a = o[0]; f->r = o[1]; f->g = o[2]; f->b = o[3];
    if (alpha == ALPHA_NONE || alpha == ALPHA_NONE_SKIP_LAST || alpha == ALPHA_NONE_SKIP_FIRST) f->a = -1;
    return true;
}

/* ---- data providers --------------------------------------------------------- */

static void provider_destroy(void *o) {
    struct cg_provider *p = o;
    if (p->release) p->release(p->info, p->bytes, p->length);
    cg_release(p->data);
    if (p->owns) free(p->bytes);
}
static const struct cf_ops provider_ops = {provider_destroy, NULL, NULL, NULL};

static struct cg_provider *provider_copy(const uint8_t *bytes, size_t length) {
    struct cg_provider *p = cf_alloc(NULL, sizeof *p, CF_CG_PROVIDER, &provider_ops);
    if (!p) return NULL;
    p->bytes = malloc(length ? length : 1);
    if (!p->bytes) { cg_release(p); return NULL; }
    if (length) memcpy(p->bytes, bytes, length);
    p->length = length;
    p->owns = true;
    return p;
}

static struct cg_provider *d_CGDataProviderCreateWithCFData(CFDataRef data) {
    if (!data) return NULL;
    struct cg_provider *p = cf_alloc(NULL, sizeof *p, CF_CG_PROVIDER, &provider_ops);
    if (!p) return NULL;
    p->data = cg_retain(data);
    p->bytes = (uint8_t *)d_CFDataGetBytePtr((const struct cf_data *)data);
    p->length = (size_t)d_CFDataGetLength((const struct cf_data *)data);
    return p;
}
DX_FN(CGDataProviderCreateWithCFData);

static struct cg_provider *d_CGDataProviderCreateWithData(void *info, const void *data, size_t size,
                                                          void (*release)(void *, const void *, size_t)) {
    struct cg_provider *p = cf_alloc(NULL, sizeof *p, CF_CG_PROVIDER, &provider_ops);
    if (!p) return NULL;
    p->bytes = (uint8_t *)data;
    p->length = size;
    p->info = info;
    p->release = release;
    return p;
}
DX_FN(CGDataProviderCreateWithData);

static CFDataRef d_CGDataProviderCopyData(const struct cg_provider *p) {
    return p ? d_CFDataCreate(NULL, p->bytes, (CFIndex)p->length) : NULL;
}
DX_FN(CGDataProviderCopyData);
static struct cg_provider *d_CGDataProviderRetain(struct cg_provider *p) { return cg_retain(p); }
DX_FN(CGDataProviderRetain);
static void d_CGDataProviderRelease(struct cg_provider *p) { cg_release(p); }
DX_FN(CGDataProviderRelease);
CF_TYPE_ID(CGDataProvider, CF_CG_PROVIDER);

/* ---- images ---------------------------------------------------------------------- */

static void image_destroy(void *o) {
    struct cg_image *i = o;
    free(i->rgba);
    cg_release(i->space);
    cg_release(i->provider);
}
static const struct cf_ops image_ops = {image_destroy, NULL, NULL, NULL};

static struct cg_image *image_alloc(size_t w, size_t h) {
    struct cg_image *img = cf_alloc(NULL, sizeof *img, CF_CG_IMAGE, &image_ops);
    if (!img) return NULL;
    img->width = w;
    img->height = h;
    img->rgba = calloc((w && h) ? w * h : 1, 4);
    if (!img->rgba) { cg_release(img); return NULL; }
    img->interpolate = true;
    return img;
}

/* Convert pixels of a known format into the image's premultiplied RGBA. */
static void convert_in(struct cg_image *img, const uint8_t *src, size_t row_bytes, const struct cg_format *f) {
    struct cg_surface s = {(uint8_t *)src, img->width, img->height, row_bytes, *f};
    for (size_t y = 0; y < img->height; y++)
        for (size_t x = 0; x < img->width; x++) {
            CGFloat px[4];
            cg_read_pixel(&s, x, y, px);
            if (f->straight) for (int k = 0; k < 3; k++) px[k] *= px[3];
            uint8_t *d = img->rgba + (y * img->width + x) * 4;
            for (int k = 0; k < 4; k++) d[k] = (uint8_t)(px[k] * 255 + 0.5);
        }
}

/* Describe the RGBA pixels as the image's own data (premultiplied last). */
static void set_rgba_provider(struct cg_image *img) {
    img->bits_per_component = 8;
    img->bits_per_pixel = 32;
    img->bytes_per_row = img->width * 4;
    img->bitmap_info = ALPHA_PREMULTIPLIED_LAST;
    img->provider = provider_copy(img->rgba, img->width * img->height * 4);
}

/* An image of premultiplied RGBA pixels, rows top to bottom (decoders). */
struct cg_image *cg_image_from_rgba(const uint8_t *rgba, size_t w, size_t h) {
    struct cg_image *img = image_alloc(w, h);
    if (!img) return NULL;
    memcpy(img->rgba, rgba, w * h * 4);
    img->space = cg_retain(cg_space_rgb());
    set_rgba_provider(img);
    return img;
}

struct cg_image *cg_image_from_surface(const struct cg_surface *s, struct cg_colorspace *space, uint32_t info) {
    struct cg_image *img = image_alloc(s->width, s->height);
    if (!img) return NULL;
    convert_in(img, s->data, s->row_bytes, &s->format);
    img->space = cg_retain(space ? space : cg_space_rgb());
    img->bits_per_component = 8;
    img->bits_per_pixel = (size_t)s->format.bytes * 8;
    img->bytes_per_row = s->row_bytes;
    img->bitmap_info = info;
    img->provider = provider_copy(s->data, s->row_bytes * s->height);
    return img;
}

static struct cg_image *d_CGImageCreate(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr,
                                        struct cg_colorspace *space, uint32_t info, struct cg_provider *provider,
                                        const CGFloat *decode, bool interpolate, int intent) {
    struct cg_format f;
    if (!provider || !cg_format_for(space, bpc, bpp, info, &f)) return NULL;
    if (h && provider->length < bpr * (h - 1) + w * (bpp / 8)) return NULL;
    struct cg_image *img = image_alloc(w, h);
    if (!img) return NULL;
    convert_in(img, provider->bytes, bpr, &f);
    img->space = cg_retain(space);
    img->bits_per_component = bpc;
    img->bits_per_pixel = bpp;
    img->bytes_per_row = bpr;
    img->bitmap_info = info;
    img->interpolate = interpolate;
    img->provider = cg_retain(provider);
    return img;
}
DX_FN(CGImageCreate);

/* An image mask: 8-bit samples, 0 paints and 255 masks out (decode not
 * supported). Kept as alpha = 1 - sample. */
static struct cg_image *d_CGImageMaskCreate(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr,
                                            struct cg_provider *provider, const CGFloat *decode, bool interpolate) {
    if (!provider || bpc != 8 || bpp != 8 || (h && provider->length < bpr * (h - 1) + w)) return NULL;
    struct cg_image *img = image_alloc(w, h);
    if (!img) return NULL;
    for (size_t y = 0; y < h; y++)
        for (size_t x = 0; x < w; x++) img->rgba[(y * w + x) * 4 + 3] = (uint8_t)(255 - provider->bytes[y * bpr + x]);
    img->is_mask = true;
    img->bits_per_component = img->bits_per_pixel = 8;
    img->bytes_per_row = bpr;
    img->provider = cg_retain(provider);
    return img;
}
DX_FN(CGImageMaskCreate);

static struct cg_image *d_CGImageCreateWithImageInRect(const struct cg_image *src, CGRect r) {
    if (!src) return NULL;
    CGFloat x0 = floor(fmax(r.origin.x, 0)), y0 = floor(fmax(r.origin.y, 0));
    CGFloat x1 = ceil(fmin(r.origin.x + r.size.width, (CGFloat)src->width));
    CGFloat y1 = ceil(fmin(r.origin.y + r.size.height, (CGFloat)src->height));
    if (x1 <= x0 || y1 <= y0) return NULL;
    size_t w = (size_t)(x1 - x0), h = (size_t)(y1 - y0);
    struct cg_image *img = image_alloc(w, h);
    if (!img) return NULL;
    for (size_t y = 0; y < h; y++)
        memcpy(img->rgba + y * w * 4, src->rgba + ((y + (size_t)y0) * src->width + (size_t)x0) * 4, w * 4);
    img->space = cg_retain(src->space);
    img->is_mask = src->is_mask;
    img->interpolate = src->interpolate;
    set_rgba_provider(img);
    return img;
}
DX_FN(CGImageCreateWithImageInRect);

static struct cg_image *d_CGImageCreateCopy(struct cg_image *img) { return cg_retain(img); }
DX_FN(CGImageCreateCopy);
static struct cg_image *d_CGImageCreateCopyWithColorSpace(const struct cg_image *src, struct cg_colorspace *space) {
    if (!src || !space) return NULL;
    struct cg_image *img = image_alloc(src->width, src->height);
    if (!img) return NULL;
    memcpy(img->rgba, src->rgba, src->width * src->height * 4);
    img->space = cg_retain(space);
    set_rgba_provider(img);
    return img;
}
DX_FN(CGImageCreateCopyWithColorSpace);

static struct cg_image *d_CGImageRetain(struct cg_image *i) { return cg_retain(i); }
DX_FN(CGImageRetain);
static void d_CGImageRelease(struct cg_image *i) { cg_release(i); }
DX_FN(CGImageRelease);
static size_t d_CGImageGetWidth(const struct cg_image *i) { return i ? i->width : 0; }
DX_FN(CGImageGetWidth);
static size_t d_CGImageGetHeight(const struct cg_image *i) { return i ? i->height : 0; }
DX_FN(CGImageGetHeight);
static size_t d_CGImageGetBitsPerComponent(const struct cg_image *i) { return i ? i->bits_per_component : 0; }
DX_FN(CGImageGetBitsPerComponent);
static size_t d_CGImageGetBitsPerPixel(const struct cg_image *i) { return i ? i->bits_per_pixel : 0; }
DX_FN(CGImageGetBitsPerPixel);
static size_t d_CGImageGetBytesPerRow(const struct cg_image *i) { return i ? i->bytes_per_row : 0; }
DX_FN(CGImageGetBytesPerRow);
static struct cg_colorspace *d_CGImageGetColorSpace(const struct cg_image *i) { return i ? i->space : NULL; }
DX_FN(CGImageGetColorSpace);
static uint32_t d_CGImageGetBitmapInfo(const struct cg_image *i) { return i ? i->bitmap_info : 0; }
DX_FN(CGImageGetBitmapInfo);
static uint32_t d_CGImageGetAlphaInfo(const struct cg_image *i) { return i ? i->bitmap_info & ALPHA_INFO_MASK : 0; }
DX_FN(CGImageGetAlphaInfo);
static struct cg_provider *d_CGImageGetDataProvider(const struct cg_image *i) { return i ? i->provider : NULL; }
DX_FN(CGImageGetDataProvider);
static bool d_CGImageGetShouldInterpolate(const struct cg_image *i) { return i && i->interpolate; }
DX_FN(CGImageGetShouldInterpolate);
static bool d_CGImageIsMask(const struct cg_image *i) { return i && i->is_mask; }
DX_FN(CGImageIsMask);
CF_TYPE_ID(CGImage, CF_CG_IMAGE);

/* ---- sampling ------------------------------------------------------------------------ */

static void texel(const struct cg_image *img, long x, long y, bool tile, CGFloat out[4]) {
    long w = (long)img->width, h = (long)img->height;
    if (tile) {
        x %= w; if (x < 0) x += w;
        y %= h; if (y < 0) y += h;
    } else {
        if (x < 0) x = 0;
        if (x >= w) x = w - 1;
        if (y < 0) y = 0;
        if (y >= h) y = h - 1;
    }
    const uint8_t *p = img->rgba + ((size_t)y * img->width + (size_t)x) * 4;
    for (int k = 0; k < 4; k++) out[k] = p[k] / 255.0;
}

void cg_image_sample(const struct cg_image *img, CGFloat u, CGFloat v, bool smooth, bool tile, CGFloat out[4]) {
    if (!img->width || !img->height) { out[0] = out[1] = out[2] = out[3] = 0; return; }
    if (!smooth) { texel(img, (long)floor(u), (long)floor(v), tile, out); return; }
    CGFloat fx = u - 0.5, fy = v - 0.5;
    long x0 = (long)floor(fx), y0 = (long)floor(fy);
    CGFloat ax = fx - x0, ay = fy - y0, a[4], b[4], c[4], d[4];
    texel(img, x0, y0, tile, a);
    texel(img, x0 + 1, y0, tile, b);
    texel(img, x0, y0 + 1, tile, c);
    texel(img, x0 + 1, y0 + 1, tile, d);
    for (int k = 0; k < 4; k++)
        out[k] = (a[k] * (1 - ax) + b[k] * ax) * (1 - ay) + (c[k] * (1 - ax) + d[k] * ax) * ay;
}
