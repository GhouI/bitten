/* ImageIO's image sources over the decoders here: PNG (png.c). A source
 * holds the file's bytes; images are decoded when asked for. Other formats
 * are recognised by their signature (so the type is right) but decode to
 * nothing: their status is kCGImageStatusUnknownType. Thumbnails are the
 * full image. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cg.h"

enum { STATUS_UNKNOWN_TYPE = -3, STATUS_INVALID_DATA = -4, STATUS_COMPLETE = 0 };

#define IMAGEIO_CONSTANTS(X) \
    X(kCGImagePropertyPixelWidth, "PixelWidth") \
    X(kCGImagePropertyPixelHeight, "PixelHeight") \
    X(kCGImagePropertyHasAlpha, "HasAlpha") \
    X(kCGImagePropertyColorModel, "ColorModel") \
    X(kCGImagePropertyColorModelRGB, "RGB") \
    X(kCGImagePropertyDepth, "Depth") \
    X(kCGImagePropertyOrientation, "Orientation") \
    X(kCGImagePropertyDPIWidth, "DPIWidth") \
    X(kCGImagePropertyDPIHeight, "DPIHeight") \
    X(kCGImageSourceShouldCache, "kCGImageSourceShouldCache") \
    X(kCGImageSourceShouldCacheImmediately, "kCGImageSourceShouldCacheImmediately") \
    X(kCGImageSourceShouldAllowFloat, "kCGImageSourceShouldAllowFloat") \
    X(kCGImageSourceTypeIdentifierHint, "kCGImageSourceTypeIdentifierHint") \
    X(kCGImageSourceCreateThumbnailFromImageIfAbsent, "kCGImageSourceCreateThumbnailFromImageIfAbsent") \
    X(kCGImageSourceCreateThumbnailFromImageAlways, "kCGImageSourceCreateThumbnailFromImageAlways") \
    X(kCGImageSourceCreateThumbnailWithTransform, "kCGImageSourceCreateThumbnailWithTransform") \
    X(kCGImageSourceThumbnailMaxPixelSize, "kCGImageSourceThumbnailMaxPixelSize")

#define IO_DECLARE(name, value) static const struct cf_string *d_##name; DX_EXPORT("_" #name, &d_##name);
IMAGEIO_CONSTANTS(IO_DECLARE)
#undef IO_DECLARE
__attribute__((constructor)) static void imageio_constants_init(void) {
#define IO_INIT(name, value) d_##name = d___CFStringMakeConstantString(value);
    IMAGEIO_CONSTANTS(IO_INIT)
#undef IO_INIT
}

struct cg_image_source {
    struct cf_object base;
    uint8_t *bytes;
    size_t length;
    struct cg_image *image;                /* decoded on first use */
    bool tried;
};
static void source_destroy(void *object) {
    struct cg_image_source *s = object;
    free(s->bytes);
    if (s->image) cg_release(s->image);
}
static const struct cf_ops source_ops = {.destroy = source_destroy};
CF_TYPE_ID(CGImageSource, CF_CG_IMAGE_SOURCE);

static struct cg_image_source *source_with(const uint8_t *bytes, size_t n) {
    struct cg_image_source *s = cf_alloc(NULL, sizeof *s, CF_CG_IMAGE_SOURCE, &source_ops);
    if (!s) return NULL;
    s->bytes = malloc(n ? n : 1);
    if (!s->bytes) { cg_release(s); return NULL; }
    if (n) memcpy(s->bytes, bytes, n);
    s->length = n;
    return s;
}

static const char *type_of(const struct cg_image_source *s) {
    const uint8_t *b = s->bytes;
    size_t n = s->length;
    if (n >= 8 && !memcmp(b, "\x89PNG\r\n\x1a\n", 8)) return "public.png";
    if (n >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) return "public.jpeg";
    if (n >= 6 && (!memcmp(b, "GIF87a", 6) || !memcmp(b, "GIF89a", 6))) return "com.compuserve.gif";
    if (n >= 4 && (!memcmp(b, "II*\0", 4) || !memcmp(b, "MM\0*", 4))) return "public.tiff";
    if (n >= 2 && !memcmp(b, "BM", 2)) return "com.microsoft.bmp";
    if (n >= 4 && !memcmp(b, "\0\0\1\0", 4)) return "com.microsoft.ico";
    if (n >= 4 && !memcmp(b, "icns", 4)) return "com.apple.icns";
    if (n >= 12 && !memcmp(b, "RIFF", 4) && !memcmp(b + 8, "WEBP", 4)) return "org.webmproject.webp";
    if (n >= 12 && !memcmp(b + 4, "ftypheic", 8)) return "public.heic";
    return NULL;
}

static struct cg_image *decoded(struct cg_image_source *s) {
    if (!s->tried) {
        s->tried = true;
        size_t w = 0, h = 0;
        uint8_t *rgba = cg_png_decode(s->bytes, s->length, &w, &h);
        if (rgba) {
            s->image = cg_image_from_rgba(rgba, w, h);
            free(rgba);
        }
    }
    return s->image;
}

static struct cg_image_source *d_CGImageSourceCreateWithData(const struct cf_data *data, const void *options) {
    if (!data || d_CFGetTypeID(data) != CF_DATA) return NULL;
    return source_with(d_CFDataGetBytePtr(data), (size_t)d_CFDataGetLength(data));
}
DX_FN(CGImageSourceCreateWithData);

static struct cg_image_source *d_CGImageSourceCreateWithDataProvider(const struct cg_provider *p, const void *options) {
    return p ? source_with(p->bytes, p->length) : NULL;
}
DX_FN(CGImageSourceCreateWithDataProvider);

typedef Boolean (*url_path_fn)(const void *, Boolean, uint8_t *, CFIndex);
static struct cg_image_source *d_CGImageSourceCreateWithURL(const void *url, const void *options) {
    url_path_fn path_of = (url_path_fn)dx_registry_lookup("_CFURLGetFileSystemRepresentation");
    char path[4096];
    if (!url || !path_of || !path_of(url, 1, (uint8_t *)path, sizeof path)) return NULL;
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    uint8_t *bytes = NULL;
    size_t n = 0, cap = 0;
    for (;;) {
        if (n == cap) {
            cap = cap ? cap * 2 : 65536;
            uint8_t *q = realloc(bytes, cap);
            if (!q) { free(bytes); fclose(f); return NULL; }
            bytes = q;
        }
        size_t got = fread(bytes + n, 1, cap - n, f);
        if (!got) break;
        n += got;
    }
    fclose(f);
    struct cg_image_source *s = source_with(bytes, n);
    free(bytes);
    return s;
}
DX_FN(CGImageSourceCreateWithURL);

static int d_CGImageSourceGetStatus(struct cg_image_source *s) {
    if (!s) return STATUS_INVALID_DATA;
    if (!type_of(s)) return STATUS_UNKNOWN_TYPE;
    return decoded(s) ? STATUS_COMPLETE : STATUS_UNKNOWN_TYPE;
}
DX_FN(CGImageSourceGetStatus);
static int d_CGImageSourceGetStatusAtIndex(struct cg_image_source *s, size_t i) {
    return i == 0 ? d_CGImageSourceGetStatus(s) : STATUS_INVALID_DATA;
}
DX_FN(CGImageSourceGetStatusAtIndex);

static size_t d_CGImageSourceGetCount(struct cg_image_source *s) { return s && decoded(s) ? 1 : 0; }
DX_FN(CGImageSourceGetCount);

static const struct cf_string *d_CGImageSourceGetType(struct cg_image_source *s) {
    const char *t = s ? type_of(s) : NULL;
    return t ? d___CFStringMakeConstantString(t) : NULL;
}
DX_FN(CGImageSourceGetType);

static struct cg_image *d_CGImageSourceCreateImageAtIndex(struct cg_image_source *s, size_t i, const void *options) {
    struct cg_image *img = s && i == 0 ? decoded(s) : NULL;
    return img ? cg_retain(img) : NULL;
}
DX_FN(CGImageSourceCreateImageAtIndex);
static struct cg_image *d_CGImageSourceCreateThumbnailAtIndex(struct cg_image_source *s, size_t i, const void *options) {
    return d_CGImageSourceCreateImageAtIndex(s, i, options);
}
DX_FN(CGImageSourceCreateThumbnailAtIndex);

static struct cf_dict *properties(struct cg_image_source *s) {
    struct cg_image *img = decoded(s);
    if (!img) return NULL;
    int w = (int)img->width, h = (int)img->height, depth = 8;
    const void *keys[] = {d_kCGImagePropertyPixelWidth, d_kCGImagePropertyPixelHeight, d_kCGImagePropertyDepth,
                          d_kCGImagePropertyColorModel};
    const void *vals[] = {d_CFNumberCreate(NULL, 3, &w), d_CFNumberCreate(NULL, 3, &h), d_CFNumberCreate(NULL, 3, &depth),
                          d_kCGImagePropertyColorModelRGB};
    struct cf_dict *d = d_CFDictionaryCreate(NULL, keys, vals, 4, &d_kCFTypeDictionaryKeyCallBacks,
                                             &d_kCFTypeDictionaryValueCallBacks);
    for (int i = 0; i < 3; i++) d_CFRelease(vals[i]);
    return d;
}
static struct cf_dict *d_CGImageSourceCopyPropertiesAtIndex(struct cg_image_source *s, size_t i, const void *options) {
    return s && i == 0 ? properties(s) : NULL;
}
DX_FN(CGImageSourceCopyPropertiesAtIndex);
static struct cf_dict *d_CGImageSourceCopyProperties(struct cg_image_source *s, const void *options) {
    return d_CFDictionaryCreate(NULL, NULL, NULL, 0, &d_kCFTypeDictionaryKeyCallBacks, &d_kCFTypeDictionaryValueCallBacks);
}
DX_FN(CGImageSourceCopyProperties);

/* CoreGraphics' own PNG entry point. */
static struct cg_image *d_CGImageCreateWithPNGDataProvider(const struct cg_provider *p, const CGFloat *decode,
                                                           bool interpolate, int intent) {
    if (!p) return NULL;
    size_t w = 0, h = 0;
    uint8_t *rgba = cg_png_decode(p->bytes, p->length, &w, &h);
    if (!rgba) return NULL;
    struct cg_image *img = cg_image_from_rgba(rgba, w, h);
    free(rgba);
    return img;
}
DX_FN(CGImageCreateWithPNGDataProvider);
