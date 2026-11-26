/* CoreGraphics inside mrun: shared types for the CG objects (all of them
 * CF objects, see corefoundation/cf.h) and the software rasterizer.
 *
 * Coordinates: user space is mapped to device space by the CTM; device
 * space has its origin at the bottom left with y up, as Apple's bitmap
 * contexts do. Rows of a surface run top to bottom, so the rasterizer flips
 * y when it turns device coordinates into pixels. Pixels are 8-bit and
 * premultiplied, in the byte order the bitmap context was created with. */
#ifndef DX_CG_H
#define DX_CG_H

#include <math.h>
#include <stdbool.h>
#include <stdint.h>

#include "../corefoundation/cf.h"

typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;

static inline CGPoint cg_apply(CGAffineTransform t, CGPoint p) {
    CGPoint r = {t.a * p.x + t.c * p.y + t.tx, t.b * p.x + t.d * p.y + t.ty};
    return r;
}

/* t1 then t2 (CGAffineTransformConcat's order). */
static inline CGAffineTransform cg_concat(CGAffineTransform t1, CGAffineTransform t2) {
    CGAffineTransform r = {
        t1.a * t2.a + t1.b * t2.c, t1.a * t2.b + t1.b * t2.d,
        t1.c * t2.a + t1.d * t2.c, t1.c * t2.b + t1.d * t2.d,
        t1.tx * t2.a + t1.ty * t2.c + t2.tx, t1.tx * t2.b + t1.ty * t2.d + t2.ty,
    };
    return r;
}

static inline CGAffineTransform cg_invert(CGAffineTransform t) {
    CGFloat det = t.a * t.d - t.b * t.c;
    if (det == 0) return t;
    CGAffineTransform r = {t.d / det, -t.b / det, -t.c / det, t.a / det, 0, 0};
    r.tx = -(r.a * t.tx + r.c * t.ty);
    r.ty = -(r.b * t.tx + r.d * t.ty);
    return r;
}

static const CGAffineTransform CG_IDENTITY = {1, 0, 0, 1, 0, 0};

/* ---- color spaces, colors, gradients (color.c) ------------------------- */

enum cg_model { CG_GRAY = 0, CG_RGB = 1 };

struct cg_colorspace {
    struct cf_object base;
    enum cg_model model;
    int components;                   /* without alpha */
    const void *name;                 /* CFString, or NULL for device spaces */
};

struct cg_color {
    struct cf_object base;
    struct cg_colorspace *space;
    CGFloat c[5];                     /* components then alpha */
    int count;                        /* components + 1 */
};

struct cg_gradient {
    struct cf_object base;
    int count;
    CGFloat (*rgba)[4];               /* straight (not premultiplied) */
    CGFloat *locations;
};

struct cg_colorspace *cg_space_rgb(void);
struct cg_colorspace *cg_space_gray(void);
/* RGBA of a color, straight alpha. */
void cg_color_rgba(const struct cg_color *color, CGFloat out[4]);
void cg_gradient_at(const struct cg_gradient *g, CGFloat t, CGFloat out[4]);

/* ---- paths (path.c) ---------------------------------------------------- */

enum cg_el_type { CG_MOVE = 0, CG_LINE = 1, CG_QUAD = 2, CG_CURVE = 3, CG_CLOSE = 4 };

struct cg_el {
    int type;
    CGPoint p[3];
};

struct cg_path {
    struct cf_object base;
    struct cg_el *el;
    int count, capacity;
    CGPoint current, start;           /* current point, start of subpath */
    bool has_current;
};

struct cg_path *cg_path_new(void);
void cg_path_clear(struct cg_path *p);
void cg_path_move(struct cg_path *p, CGPoint a);
void cg_path_line(struct cg_path *p, CGPoint a);
void cg_path_quad(struct cg_path *p, CGPoint c, CGPoint a);
void cg_path_curve(struct cg_path *p, CGPoint c1, CGPoint c2, CGPoint a);
void cg_path_close(struct cg_path *p);
void cg_path_rect(struct cg_path *p, CGRect r, const CGAffineTransform *t);
void cg_path_ellipse(struct cg_path *p, CGRect r, const CGAffineTransform *t);
void cg_path_rounded_rect(struct cg_path *p, CGRect r, CGFloat rw, CGFloat rh, const CGAffineTransform *t);
void cg_path_arc(struct cg_path *p, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat a1, bool clockwise,
                 const CGAffineTransform *t);
void cg_path_arc_to(struct cg_path *p, CGPoint p1, CGPoint p2, CGFloat r, const CGAffineTransform *t);
void cg_path_append(struct cg_path *p, const struct cg_path *src, const CGAffineTransform *t);
CGRect cg_path_bounds(const struct cg_path *p, bool control_points);

/* Polylines: a path flattened into straight segments. */
struct cg_poly {
    CGPoint *pt;
    int count, capacity;
    bool closed;
};

struct cg_polys {
    struct cg_poly *poly;
    int count, capacity;
};

void cg_polys_free(struct cg_polys *s);
void cg_poly_add(struct cg_poly *p, CGPoint a);
struct cg_poly *cg_polys_new_poly(struct cg_polys *s);
/* Flatten with the given tolerance, in the path's own coordinates. */
void cg_flatten(const struct cg_path *p, CGFloat tolerance, struct cg_polys *out);
void cg_polys_transform(struct cg_polys *s, CGAffineTransform t);

struct cg_stroke_style {
    CGFloat width, miter_limit;
    int cap, join;                    /* CGLineCap, CGLineJoin */
    const CGFloat *dashes;
    int dash_count;
    CGFloat dash_phase;
};

/* The outline of a stroke as closed polygons, all counter-clockwise, to be
 * filled with the nonzero rule. */
void cg_stroke(const struct cg_polys *in, const struct cg_stroke_style *style, CGFloat tolerance,
               struct cg_polys *out);

/* ---- surfaces and rasterizing (raster.c) ------------------------------ */

struct cg_format {
    int bytes;                        /* per pixel: 1 to 4 */
    int r, g, b, a;                   /* byte offsets; a = -1 without alpha */
    bool gray;                        /* one gray byte (+ alpha when a >= 0) */
    bool alpha_only;
    bool straight;                    /* alpha not premultiplied (images only) */
};

/* The pixel layout for a color space, depth and CGBitmapInfo; false when
 * bitten cannot handle it (16- and 32-bit components, CMYK, floats). */
bool cg_format_for(const struct cg_colorspace *space, size_t bpc, size_t bpp, uint32_t info,
                   struct cg_format *out);

struct cg_surface {
    uint8_t *data;
    size_t width, height, row_bytes;
    struct cg_format format;
};

/* A coverage mask over a surface, shared by saved graphics states. */
struct cg_mask {
    int refs;
    size_t width, height;
    uint8_t *data;
};

struct cg_mask *cg_mask_new(size_t w, size_t h, uint8_t fill);
struct cg_mask *cg_mask_retain(struct cg_mask *m);
void cg_mask_release(struct cg_mask *m);

/* What to paint: a solid color, or a function of the device point. */
struct cg_paint {
    CGFloat rgba[4];                  /* straight; used when shade is NULL */
    void (*shade)(const struct cg_paint *, CGFloat x, CGFloat y, CGFloat out[4]);
    const void *info;
    bool premultiplied;               /* shade gives premultiplied colors */
};

enum cg_blend { CG_BLEND_NORMAL = 0, CG_BLEND_CLEAR = 16, CG_BLEND_COPY = 17 };

struct cg_target {
    struct cg_surface *surface;
    const struct cg_mask *clip;       /* NULL: no clip */
    CGFloat alpha;
    int blend;
    bool antialias;
};

/* Fill device-space polygons (y up) with a paint. even_odd picks the rule. */
void cg_fill_polys(const struct cg_target *t, const struct cg_polys *polys, bool even_odd,
                   const struct cg_paint *paint);
/* Rasterize polygons into a coverage mask (for clipping). */
void cg_mask_polys(struct cg_mask *m, const struct cg_polys *polys, bool even_odd, bool antialias);
void cg_read_pixel(const struct cg_surface *s, size_t x, size_t row, CGFloat out[4]);   /* premultiplied */
void cg_write_pixel(struct cg_surface *s, size_t x, size_t row, const CGFloat in[4]);   /* premultiplied */
void cg_blend_pixel(const struct cg_target *t, size_t x, size_t row, const CGFloat premul[4], CGFloat coverage);

/* ---- images and data providers (image.c) ------------------------------ */

struct cg_provider {
    struct cf_object base;
    uint8_t *bytes;
    size_t length;
    const void *data;                 /* a retained CFData, or NULL */
    void *info;
    void (*release)(void *info, const void *data, size_t size);
    bool owns;
};

struct cg_image {
    struct cf_object base;
    struct cg_provider *provider;     /* the pixels as the image describes them */
    size_t width, height, bits_per_component, bits_per_pixel, bytes_per_row;
    uint32_t bitmap_info;
    struct cg_colorspace *space;
    uint8_t *rgba;                    /* premultiplied RGBA, rows top to bottom */
    bool is_mask;
    bool interpolate;
};

struct cg_image *cg_image_from_surface(const struct cg_surface *s, struct cg_colorspace *space, uint32_t info);
struct cg_image *cg_image_from_rgba(const uint8_t *rgba, size_t w, size_t h);
/* PNG files to premultiplied RGBA, rows top to bottom (png.c); malloc'd. */
uint8_t *cg_png_decode(const uint8_t *data, size_t n, size_t *w, size_t *h);
/* A premultiplied RGBA sample at image coordinates (u, v), v down. */
void cg_image_sample(const struct cg_image *img, CGFloat u, CGFloat v, bool smooth, bool tile, CGFloat out[4]);

/* ---- CF type ids --------------------------------------------------------- */

void *cg_retain(const void *o);
void cg_release(const void *o);

#endif
