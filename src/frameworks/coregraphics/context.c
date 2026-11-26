/* CoreGraphics: CGContext. Bitmap contexts over 8-bit RGB, gray and
 * alpha-only buffers; the graphics state stack; path construction (points
 * go through the CTM as they are added, as in Apple's implementation);
 * filling, stroking, clipping, images, gradients and transparency layers,
 * drawn by the rasterizer in raster.c.
 *
 * Not drawn: shadows (the state is kept, the shadow is not painted) and
 * blend modes other than normal, copy and clear (drawn as normal). Text
 * state is kept here for CoreText to use. */
#include <string.h>

#include "cg.h"

enum { MODE_FILL = 0, MODE_EOFILL = 1, MODE_STROKE = 2, MODE_FILL_STROKE = 3, MODE_EOFILL_STROKE = 4 };

struct gstate {
    CGAffineTransform ctm;
    CGFloat fill[4], stroke[4];                /* straight RGBA */
    struct cg_colorspace *fill_space, *stroke_space;
    CGFloat alpha, line_width, miter_limit, flatness;
    int cap, join, blend, interpolation, text_mode;
    bool antialias, allows_antialias;
    CGFloat *dashes;
    int dash_count;
    CGFloat dash_phase;
    struct cg_mask *clip;
    CGAffineTransform text_matrix;
    CGFloat character_spacing, font_size;
    const void *font;
    CGSize shadow_offset;
    CGFloat shadow_blur, shadow_color[4];
    bool smooth_fonts, subpixel_position, subpixel_quantize;
    struct gstate *next;
};

struct layer {
    struct cg_surface surface;
    struct cg_surface *under;
    CGFloat alpha;
    int blend;
    struct layer *next;
};

struct cg_context {
    struct cf_object base;
    struct cg_surface bitmap;
    struct cg_surface *target;                 /* the bitmap or the top layer */
    struct cg_colorspace *space;
    uint32_t bitmap_info;
    size_t bits_per_component, bits_per_pixel;
    bool owns_data;
    void (*release_data)(void *info, void *data);
    void *release_info;
    struct gstate *gs;
    struct cg_path *path;                      /* in device space */
    struct layer *layers;
};

typedef struct cg_context *CGContextRef;

/* ---- the object ------------------------------------------------------------------ */

static void gstate_free(struct gstate *g) {
    free(g->dashes);
    cg_mask_release(g->clip);
    cg_release(g->fill_space);
    cg_release(g->stroke_space);
    cg_release(g->font);
    free(g);
}

static void context_destroy(void *o) {
    struct cg_context *c = o;
    while (c->layers) {
        struct layer *l = c->layers;
        c->layers = l->next;
        free(l->surface.data);
        free(l);
    }
    while (c->gs) {
        struct gstate *g = c->gs;
        c->gs = g->next;
        gstate_free(g);
    }
    cg_release(c->path);
    cg_release(c->space);
    if (c->release_data) c->release_data(c->release_info, c->bitmap.data);
    if (c->owns_data) free(c->bitmap.data);
}
static const struct cf_ops context_ops = {context_destroy, NULL, NULL, NULL};

static struct gstate *gstate_new(void) {
    struct gstate *g = calloc(1, sizeof *g);
    if (!g) return NULL;
    g->ctm = CG_IDENTITY;
    g->fill[3] = g->stroke[3] = 1;             /* opaque black */
    g->fill_space = cg_retain(cg_space_gray());
    g->stroke_space = cg_retain(cg_space_gray());
    g->alpha = 1;
    g->line_width = 1;
    g->miter_limit = 10;
    g->flatness = 0.5;
    g->antialias = g->allows_antialias = true;
    g->text_matrix = CG_IDENTITY;
    g->font_size = 12;
    g->smooth_fonts = true;
    return g;
}

static struct gstate *gstate_copy(const struct gstate *s) {
    struct gstate *g = malloc(sizeof *g);
    if (!g) return NULL;
    *g = *s;
    g->next = NULL;
    if (s->dash_count) {
        g->dashes = malloc((size_t)s->dash_count * sizeof *g->dashes);
        if (g->dashes) memcpy(g->dashes, s->dashes, (size_t)s->dash_count * sizeof *g->dashes);
        else g->dash_count = 0;
    } else {
        g->dashes = NULL;
    }
    g->clip = cg_mask_retain(s->clip);
    cg_retain(g->fill_space);
    cg_retain(g->stroke_space);
    cg_retain(g->font);
    return g;
}

static struct cg_context *context_new(void) {
    struct cg_context *c = cf_alloc(NULL, sizeof *c, CF_CG_CONTEXT, &context_ops);
    if (!c) return NULL;
    c->gs = gstate_new();
    c->path = cg_path_new();
    c->target = &c->bitmap;
    if (!c->gs || !c->path) { cg_release(c); return NULL; }
    return c;
}

static CGContextRef d_CGContextRetain(CGContextRef c) { return cg_retain(c); }
DX_FN(CGContextRetain);
static void d_CGContextRelease(CGContextRef c) { cg_release(c); }
DX_FN(CGContextRelease);
static void d_CGContextFlush(CGContextRef c) {}
DX_FN(CGContextFlush);
static void d_CGContextSynchronize(CGContextRef c) {}
DX_FN(CGContextSynchronize);
CF_TYPE_ID(CGContext, CF_CG_CONTEXT);

/* ---- bitmap contexts -------------------------------------------------------------- */

static CGContextRef bitmap_context(void *data, size_t w, size_t h, size_t bpc, size_t bpr, struct cg_colorspace *space,
                                   uint32_t info, void (*release)(void *, void *), void *release_info) {
    int alpha = info & 0x1f;
    size_t bpp = alpha == 7 ? 8 : (space && space->model == CG_GRAY) ? (alpha == 0 ? 8 : 16) : 32;
    struct cg_format f;
    if (!cg_format_for(space, bpc, bpp, info, &f) || f.straight || (alpha == 0 && space && space->model == CG_RGB))
        return NULL;                           /* as Apple: no straight alpha, no 24-bit RGB */
    size_t min_row = w * (size_t)f.bytes;
    if (bpr == 0) bpr = (min_row + 15) & ~(size_t)15;
    if (bpr < min_row) return NULL;
    struct cg_context *c = context_new();
    if (!c) return NULL;
    if (!data) {
        data = calloc(h ? h : 1, bpr);
        if (!data) { cg_release(c); return NULL; }
        c->owns_data = true;
    }
    c->bitmap = (struct cg_surface){data, w, h, bpr, f};
    c->space = cg_retain(space);
    c->bitmap_info = info;
    c->bits_per_component = bpc;
    c->bits_per_pixel = bpp;
    c->release_data = release;
    c->release_info = release_info;
    if (space && space->model == CG_RGB) {
        cg_release(c->gs->fill_space);
        cg_release(c->gs->stroke_space);
        c->gs->fill_space = cg_retain(space);
        c->gs->stroke_space = cg_retain(space);
    }
    return c;
}

static CGContextRef d_CGBitmapContextCreate(void *data, size_t w, size_t h, size_t bpc, size_t bpr,
                                            struct cg_colorspace *space, uint32_t info) {
    return bitmap_context(data, w, h, bpc, bpr, space, info, NULL, NULL);
}
DX_FN(CGBitmapContextCreate);

static CGContextRef d_CGBitmapContextCreateWithData(void *data, size_t w, size_t h, size_t bpc, size_t bpr,
                                                    struct cg_colorspace *space, uint32_t info,
                                                    void (*release)(void *, void *), void *release_info) {
    return bitmap_context(data, w, h, bpc, bpr, space, info, release, release_info);
}
DX_FN(CGBitmapContextCreateWithData);

static void *d_CGBitmapContextGetData(CGContextRef c) { return c ? c->bitmap.data : NULL; }
DX_FN(CGBitmapContextGetData);
static size_t d_CGBitmapContextGetWidth(CGContextRef c) { return c ? c->bitmap.width : 0; }
DX_FN(CGBitmapContextGetWidth);
static size_t d_CGBitmapContextGetHeight(CGContextRef c) { return c ? c->bitmap.height : 0; }
DX_FN(CGBitmapContextGetHeight);
static size_t d_CGBitmapContextGetBytesPerRow(CGContextRef c) { return c ? c->bitmap.row_bytes : 0; }
DX_FN(CGBitmapContextGetBytesPerRow);
static size_t d_CGBitmapContextGetBitsPerComponent(CGContextRef c) { return c ? c->bits_per_component : 0; }
DX_FN(CGBitmapContextGetBitsPerComponent);
static size_t d_CGBitmapContextGetBitsPerPixel(CGContextRef c) { return c ? c->bits_per_pixel : 0; }
DX_FN(CGBitmapContextGetBitsPerPixel);
static struct cg_colorspace *d_CGBitmapContextGetColorSpace(CGContextRef c) { return c ? c->space : NULL; }
DX_FN(CGBitmapContextGetColorSpace);
static uint32_t d_CGBitmapContextGetBitmapInfo(CGContextRef c) { return c ? c->bitmap_info : 0; }
DX_FN(CGBitmapContextGetBitmapInfo);
static uint32_t d_CGBitmapContextGetAlphaInfo(CGContextRef c) { return c ? c->bitmap_info & 0x1f : 0; }
DX_FN(CGBitmapContextGetAlphaInfo);

static struct cg_image *d_CGBitmapContextCreateImage(CGContextRef c) {
    if (!c || !c->bitmap.data) return NULL;
    return cg_image_from_surface(&c->bitmap, c->space, c->bitmap_info);
}
DX_FN(CGBitmapContextCreateImage);

/* ---- graphics state ---------------------------------------------------------------- */

static void d_CGContextSaveGState(CGContextRef c) {
    if (!c) return;
    struct gstate *g = gstate_copy(c->gs);
    if (!g) return;
    g->next = c->gs;
    c->gs = g;
}
DX_FN(CGContextSaveGState);

static void d_CGContextRestoreGState(CGContextRef c) {
    if (!c || !c->gs->next) return;
    struct gstate *g = c->gs;
    c->gs = g->next;
    gstate_free(g);
}
DX_FN(CGContextRestoreGState);

static void d_CGContextTranslateCTM(CGContextRef c, CGFloat tx, CGFloat ty) {
    if (c) c->gs->ctm = cg_concat((CGAffineTransform){1, 0, 0, 1, tx, ty}, c->gs->ctm);
}
DX_FN(CGContextTranslateCTM);
static void d_CGContextScaleCTM(CGContextRef c, CGFloat sx, CGFloat sy) {
    if (c) c->gs->ctm = cg_concat((CGAffineTransform){sx, 0, 0, sy, 0, 0}, c->gs->ctm);
}
DX_FN(CGContextScaleCTM);
static void d_CGContextRotateCTM(CGContextRef c, CGFloat a) {
    if (c) c->gs->ctm = cg_concat((CGAffineTransform){cos(a), sin(a), -sin(a), cos(a), 0, 0}, c->gs->ctm);
}
DX_FN(CGContextRotateCTM);
static void d_CGContextConcatCTM(CGContextRef c, CGAffineTransform t) {
    if (c) c->gs->ctm = cg_concat(t, c->gs->ctm);
}
DX_FN(CGContextConcatCTM);
static CGAffineTransform d_CGContextGetCTM(CGContextRef c) { return c ? c->gs->ctm : CG_IDENTITY; }
DX_FN(CGContextGetCTM);
static CGAffineTransform d_CGContextGetUserSpaceToDeviceSpaceTransform(CGContextRef c) { return d_CGContextGetCTM(c); }
DX_FN(CGContextGetUserSpaceToDeviceSpaceTransform);

static void set_rgba(CGFloat *dst, CGFloat r, CGFloat g, CGFloat b, CGFloat a) { dst[0] = r; dst[1] = g; dst[2] = b; dst[3] = a; }

static void d_CGContextSetRGBFillColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    if (c) set_rgba(c->gs->fill, r, g, b, a);
}
DX_FN(CGContextSetRGBFillColor);
static void d_CGContextSetRGBStrokeColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    if (c) set_rgba(c->gs->stroke, r, g, b, a);
}
DX_FN(CGContextSetRGBStrokeColor);
static void d_CGContextSetGrayFillColor(CGContextRef c, CGFloat g, CGFloat a) { if (c) set_rgba(c->gs->fill, g, g, g, a); }
DX_FN(CGContextSetGrayFillColor);
static void d_CGContextSetGrayStrokeColor(CGContextRef c, CGFloat g, CGFloat a) { if (c) set_rgba(c->gs->stroke, g, g, g, a); }
DX_FN(CGContextSetGrayStrokeColor);
static void cmyk(CGFloat *dst, CGFloat cy, CGFloat m, CGFloat y, CGFloat k, CGFloat a) {
    set_rgba(dst, (1 - cy) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k), a);
}
static void d_CGContextSetCMYKFillColor(CGContextRef c, CGFloat cy, CGFloat m, CGFloat y, CGFloat k, CGFloat a) {
    if (c) cmyk(c->gs->fill, cy, m, y, k, a);
}
DX_FN(CGContextSetCMYKFillColor);
static void d_CGContextSetCMYKStrokeColor(CGContextRef c, CGFloat cy, CGFloat m, CGFloat y, CGFloat k, CGFloat a) {
    if (c) cmyk(c->gs->stroke, cy, m, y, k, a);
}
DX_FN(CGContextSetCMYKStrokeColor);
static void d_CGContextSetFillColorWithColor(CGContextRef c, const struct cg_color *k) { if (c) cg_color_rgba(k, c->gs->fill); }
DX_FN(CGContextSetFillColorWithColor);
static void d_CGContextSetStrokeColorWithColor(CGContextRef c, const struct cg_color *k) { if (c) cg_color_rgba(k, c->gs->stroke); }
DX_FN(CGContextSetStrokeColorWithColor);

static void space_color(const struct cg_colorspace *s, const CGFloat *comps, CGFloat *dst) {
    if (!comps) return;
    if (s && s->model == CG_RGB) set_rgba(dst, comps[0], comps[1], comps[2], comps[3]);
    else set_rgba(dst, comps[0], comps[0], comps[0], comps[1]);
}
static void d_CGContextSetFillColorSpace(CGContextRef c, struct cg_colorspace *s) {
    if (!c || !s) return;
    cg_retain(s);
    cg_release(c->gs->fill_space);
    c->gs->fill_space = s;
    set_rgba(c->gs->fill, 0, 0, 0, 1);
}
DX_FN(CGContextSetFillColorSpace);
static void d_CGContextSetStrokeColorSpace(CGContextRef c, struct cg_colorspace *s) {
    if (!c || !s) return;
    cg_retain(s);
    cg_release(c->gs->stroke_space);
    c->gs->stroke_space = s;
    set_rgba(c->gs->stroke, 0, 0, 0, 1);
}
DX_FN(CGContextSetStrokeColorSpace);
static void d_CGContextSetFillColor(CGContextRef c, const CGFloat *comps) { if (c) space_color(c->gs->fill_space, comps, c->gs->fill); }
DX_FN(CGContextSetFillColor);
static void d_CGContextSetStrokeColor(CGContextRef c, const CGFloat *comps) { if (c) space_color(c->gs->stroke_space, comps, c->gs->stroke); }
DX_FN(CGContextSetStrokeColor);

static void d_CGContextSetAlpha(CGContextRef c, CGFloat a) { if (c) c->gs->alpha = a < 0 ? 0 : a > 1 ? 1 : a; }
DX_FN(CGContextSetAlpha);
static void d_CGContextSetBlendMode(CGContextRef c, int mode) { if (c) c->gs->blend = mode; }
DX_FN(CGContextSetBlendMode);
static void d_CGContextSetLineWidth(CGContextRef c, CGFloat w) { if (c && w >= 0) c->gs->line_width = w; }
DX_FN(CGContextSetLineWidth);
static void d_CGContextSetLineCap(CGContextRef c, int cap) { if (c) c->gs->cap = cap; }
DX_FN(CGContextSetLineCap);
static void d_CGContextSetLineJoin(CGContextRef c, int join) { if (c) c->gs->join = join; }
DX_FN(CGContextSetLineJoin);
static void d_CGContextSetMiterLimit(CGContextRef c, CGFloat m) { if (c) c->gs->miter_limit = m; }
DX_FN(CGContextSetMiterLimit);
static void d_CGContextSetFlatness(CGContextRef c, CGFloat f) { if (c && f > 0) c->gs->flatness = f; }
DX_FN(CGContextSetFlatness);
static void d_CGContextSetShouldAntialias(CGContextRef c, bool on) { if (c) c->gs->antialias = on; }
DX_FN(CGContextSetShouldAntialias);
static void d_CGContextSetAllowsAntialiasing(CGContextRef c, bool on) { if (c) c->gs->allows_antialias = on; }
DX_FN(CGContextSetAllowsAntialiasing);
static void d_CGContextSetInterpolationQuality(CGContextRef c, int q) { if (c) c->gs->interpolation = q; }
DX_FN(CGContextSetInterpolationQuality);
static int d_CGContextGetInterpolationQuality(CGContextRef c) { return c ? c->gs->interpolation : 0; }
DX_FN(CGContextGetInterpolationQuality);
static void d_CGContextSetRenderingIntent(CGContextRef c, int intent) {}
DX_FN(CGContextSetRenderingIntent);

static void d_CGContextSetLineDash(CGContextRef c, CGFloat phase, const CGFloat *lengths, size_t count) {
    if (!c) return;
    free(c->gs->dashes);
    c->gs->dashes = NULL;
    c->gs->dash_count = 0;
    c->gs->dash_phase = phase;
    if (!lengths || !count) return;
    c->gs->dashes = malloc(count * sizeof *lengths);
    if (!c->gs->dashes) return;
    memcpy(c->gs->dashes, lengths, count * sizeof *lengths);
    c->gs->dash_count = (int)count;
}
DX_FN(CGContextSetLineDash);

static void d_CGContextSetShadowWithColor(CGContextRef c, CGSize offset, CGFloat blur, const struct cg_color *color) {
    if (!c) return;
    c->gs->shadow_offset = offset;
    c->gs->shadow_blur = blur;
    if (color) cg_color_rgba(color, c->gs->shadow_color);
    else memset(c->gs->shadow_color, 0, sizeof c->gs->shadow_color);
}
DX_FN(CGContextSetShadowWithColor);
static void d_CGContextSetShadow(CGContextRef c, CGSize offset, CGFloat blur) {
    if (!c) return;
    c->gs->shadow_offset = offset;
    c->gs->shadow_blur = blur;
    set_rgba(c->gs->shadow_color, 0, 0, 0, 1.0 / 3);
}
DX_FN(CGContextSetShadow);

/* Font rendering switches: kept for CoreText. */
static void d_CGContextSetShouldSmoothFonts(CGContextRef c, bool on) { if (c) c->gs->smooth_fonts = on; }
DX_FN(CGContextSetShouldSmoothFonts);
static void d_CGContextSetAllowsFontSmoothing(CGContextRef c, bool on) {}
DX_FN(CGContextSetAllowsFontSmoothing);
static void d_CGContextSetShouldSubpixelPositionFonts(CGContextRef c, bool on) { if (c) c->gs->subpixel_position = on; }
DX_FN(CGContextSetShouldSubpixelPositionFonts);
static void d_CGContextSetAllowsFontSubpixelPositioning(CGContextRef c, bool on) {}
DX_FN(CGContextSetAllowsFontSubpixelPositioning);
static void d_CGContextSetShouldSubpixelQuantizeFonts(CGContextRef c, bool on) { if (c) c->gs->subpixel_quantize = on; }
DX_FN(CGContextSetShouldSubpixelQuantizeFonts);
static void d_CGContextSetAllowsFontSubpixelQuantization(CGContextRef c, bool on) {}
DX_FN(CGContextSetAllowsFontSubpixelQuantization);

/* Text state (drawn by CoreText). */
static void d_CGContextSetTextMatrix(CGContextRef c, CGAffineTransform t) { if (c) c->gs->text_matrix = t; }
DX_FN(CGContextSetTextMatrix);
static CGAffineTransform d_CGContextGetTextMatrix(CGContextRef c) { return c ? c->gs->text_matrix : CG_IDENTITY; }
DX_FN(CGContextGetTextMatrix);
static void d_CGContextSetTextPosition(CGContextRef c, CGFloat x, CGFloat y) {
    if (c) { c->gs->text_matrix.tx = x; c->gs->text_matrix.ty = y; }
}
DX_FN(CGContextSetTextPosition);
static CGPoint d_CGContextGetTextPosition(CGContextRef c) {
    return c ? (CGPoint){c->gs->text_matrix.tx, c->gs->text_matrix.ty} : (CGPoint){0, 0};
}
DX_FN(CGContextGetTextPosition);
static void d_CGContextSetTextDrawingMode(CGContextRef c, int mode) { if (c) c->gs->text_mode = mode; }
DX_FN(CGContextSetTextDrawingMode);
static void d_CGContextSetCharacterSpacing(CGContextRef c, CGFloat s) { if (c) c->gs->character_spacing = s; }
DX_FN(CGContextSetCharacterSpacing);
static void d_CGContextSetFont(CGContextRef c, const void *font) {
    if (!c) return;
    cg_retain(font);
    cg_release(c->gs->font);
    c->gs->font = font;
}
DX_FN(CGContextSetFont);
static void d_CGContextSetFontSize(CGContextRef c, CGFloat size) { if (c) c->gs->font_size = size; }
DX_FN(CGContextSetFontSize);

/* ---- coordinates --------------------------------------------------------------------- */

static CGRect rect_apply(CGRect r, CGAffineTransform t) {
    CGPoint p[4] = {cg_apply(t, r.origin), cg_apply(t, (CGPoint){r.origin.x + r.size.width, r.origin.y}),
                    cg_apply(t, (CGPoint){r.origin.x, r.origin.y + r.size.height}),
                    cg_apply(t, (CGPoint){r.origin.x + r.size.width, r.origin.y + r.size.height})};
    CGFloat x0 = p[0].x, x1 = p[0].x, y0 = p[0].y, y1 = p[0].y;
    for (int i = 1; i < 4; i++) {
        x0 = fmin(x0, p[i].x); x1 = fmax(x1, p[i].x);
        y0 = fmin(y0, p[i].y); y1 = fmax(y1, p[i].y);
    }
    return (CGRect){{x0, y0}, {x1 - x0, y1 - y0}};
}

static CGPoint d_CGContextConvertPointToDeviceSpace(CGContextRef c, CGPoint p) { return c ? cg_apply(c->gs->ctm, p) : p; }
DX_FN(CGContextConvertPointToDeviceSpace);
static CGPoint d_CGContextConvertPointToUserSpace(CGContextRef c, CGPoint p) { return c ? cg_apply(cg_invert(c->gs->ctm), p) : p; }
DX_FN(CGContextConvertPointToUserSpace);
static CGSize d_CGContextConvertSizeToDeviceSpace(CGContextRef c, CGSize s) {
    if (!c) return s;
    CGAffineTransform t = c->gs->ctm;
    return (CGSize){t.a * s.width + t.c * s.height, t.b * s.width + t.d * s.height};
}
DX_FN(CGContextConvertSizeToDeviceSpace);
static CGSize d_CGContextConvertSizeToUserSpace(CGContextRef c, CGSize s) {
    if (!c) return s;
    CGAffineTransform t = cg_invert(c->gs->ctm);
    return (CGSize){t.a * s.width + t.c * s.height, t.b * s.width + t.d * s.height};
}
DX_FN(CGContextConvertSizeToUserSpace);
static CGRect d_CGContextConvertRectToDeviceSpace(CGContextRef c, CGRect r) { return c ? rect_apply(r, c->gs->ctm) : r; }
DX_FN(CGContextConvertRectToDeviceSpace);
static CGRect d_CGContextConvertRectToUserSpace(CGContextRef c, CGRect r) { return c ? rect_apply(r, cg_invert(c->gs->ctm)) : r; }
DX_FN(CGContextConvertRectToUserSpace);

/* ---- the current path -------------------------------------------------------------------- */

static CGPoint dev(CGContextRef c, CGFloat x, CGFloat y) { return cg_apply(c->gs->ctm, (CGPoint){x, y}); }

static void d_CGContextBeginPath(CGContextRef c) { if (c) cg_path_clear(c->path); }
DX_FN(CGContextBeginPath);
static void d_CGContextMoveToPoint(CGContextRef c, CGFloat x, CGFloat y) { if (c) cg_path_move(c->path, dev(c, x, y)); }
DX_FN(CGContextMoveToPoint);
static void d_CGContextAddLineToPoint(CGContextRef c, CGFloat x, CGFloat y) { if (c) cg_path_line(c->path, dev(c, x, y)); }
DX_FN(CGContextAddLineToPoint);
static void d_CGContextAddCurveToPoint(CGContextRef c, CGFloat c1x, CGFloat c1y, CGFloat c2x, CGFloat c2y, CGFloat x, CGFloat y) {
    if (c) cg_path_curve(c->path, dev(c, c1x, c1y), dev(c, c2x, c2y), dev(c, x, y));
}
DX_FN(CGContextAddCurveToPoint);
static void d_CGContextAddQuadCurveToPoint(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat x, CGFloat y) {
    if (c) cg_path_quad(c->path, dev(c, cx, cy), dev(c, x, y));
}
DX_FN(CGContextAddQuadCurveToPoint);
static void d_CGContextClosePath(CGContextRef c) { if (c) cg_path_close(c->path); }
DX_FN(CGContextClosePath);
static void d_CGContextAddRect(CGContextRef c, CGRect r) { if (c) cg_path_rect(c->path, r, &c->gs->ctm); }
DX_FN(CGContextAddRect);
static void d_CGContextAddRects(CGContextRef c, const CGRect *r, size_t n) {
    for (size_t i = 0; c && r && i < n; i++) cg_path_rect(c->path, r[i], &c->gs->ctm);
}
DX_FN(CGContextAddRects);
static void d_CGContextAddLines(CGContextRef c, const CGPoint *p, size_t n) {
    for (size_t i = 0; c && p && i < n; i++) {
        if (i == 0) cg_path_move(c->path, cg_apply(c->gs->ctm, p[0]));
        else cg_path_line(c->path, cg_apply(c->gs->ctm, p[i]));
    }
}
DX_FN(CGContextAddLines);
static void d_CGContextAddEllipseInRect(CGContextRef c, CGRect r) { if (c) cg_path_ellipse(c->path, r, &c->gs->ctm); }
DX_FN(CGContextAddEllipseInRect);
static void d_CGContextAddArc(CGContextRef c, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat a1, int clockwise) {
    if (c) cg_path_arc(c->path, x, y, r, a0, a1, clockwise != 0, &c->gs->ctm);
}
DX_FN(CGContextAddArc);
static void d_CGContextAddArcToPoint(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r) {
    if (c) cg_path_arc_to(c->path, (CGPoint){x1, y1}, (CGPoint){x2, y2}, r, &c->gs->ctm);
}
DX_FN(CGContextAddArcToPoint);
static void d_CGContextAddPath(CGContextRef c, const struct cg_path *p) { if (c) cg_path_append(c->path, p, &c->gs->ctm); }
DX_FN(CGContextAddPath);
static bool d_CGContextIsPathEmpty(CGContextRef c) { return !c || c->path->count == 0; }
DX_FN(CGContextIsPathEmpty);
static CGPoint d_CGContextGetPathCurrentPoint(CGContextRef c) {
    if (!c || !c->path->has_current) return (CGPoint){0, 0};
    return cg_apply(cg_invert(c->gs->ctm), c->path->current);
}
DX_FN(CGContextGetPathCurrentPoint);
static struct cg_path *d_CGContextCopyPath(CGContextRef c) {
    if (!c) return NULL;
    struct cg_path *p = cg_path_new();
    CGAffineTransform inv = cg_invert(c->gs->ctm);
    if (p) cg_path_append(p, c->path, &inv);
    return p;
}
DX_FN(CGContextCopyPath);
static CGRect d_CGContextGetPathBoundingBox(CGContextRef c) {
    if (!c || !c->path->count) return (CGRect){{INFINITY, INFINITY}, {0, 0}};
    return rect_apply(cg_path_bounds(c->path, true), cg_invert(c->gs->ctm));
}
DX_FN(CGContextGetPathBoundingBox);

/* ---- drawing ---------------------------------------------------------------------------------- */

static struct cg_target target(CGContextRef c) {
    return (struct cg_target){c->target, c->gs->clip, c->gs->alpha, c->gs->blend,
                              c->gs->antialias && c->gs->allows_antialias};
}

static CGFloat ctm_scale(CGContextRef c) {
    CGFloat det = fabs(c->gs->ctm.a * c->gs->ctm.d - c->gs->ctm.b * c->gs->ctm.c);
    return det > 0 ? sqrt(det) : 1;
}

/* Fill a device-space path. */
static void fill_path(CGContextRef c, const struct cg_path *p, bool eo, const struct cg_paint *paint) {
    struct cg_polys polys = {0};
    cg_flatten(p, 0.2, &polys);
    struct cg_target t = target(c);
    cg_fill_polys(&t, &polys, eo, paint);
    cg_polys_free(&polys);
}

/* The stroke of a device-space path, computed in user space. */
static void stroke_outline(CGContextRef c, const struct cg_path *p, struct cg_polys *out) {
    CGAffineTransform inv = cg_invert(c->gs->ctm);
    struct cg_path *user = cg_path_new();
    if (!user) return;
    cg_path_append(user, p, &inv);
    CGFloat tol = 0.2 / ctm_scale(c);
    struct cg_polys flat = {0};
    cg_flatten(user, tol, &flat);
    struct cg_stroke_style st = {c->gs->line_width, c->gs->miter_limit, c->gs->cap, c->gs->join,
                                 c->gs->dashes, c->gs->dash_count, c->gs->dash_phase};
    /* A zero width draws a hairline: one device pixel. */
    if (st.width == 0) st.width = 1 / ctm_scale(c);
    cg_stroke(&flat, &st, tol, out);
    cg_polys_transform(out, c->gs->ctm);
    cg_polys_free(&flat);
    cg_release(user);
}

static void stroke_path(CGContextRef c, const struct cg_path *p) {
    struct cg_polys outline = {0};
    stroke_outline(c, p, &outline);
    struct cg_paint paint = {{c->gs->stroke[0], c->gs->stroke[1], c->gs->stroke[2], c->gs->stroke[3]}, NULL, NULL, false};
    struct cg_target t = target(c);
    cg_fill_polys(&t, &outline, false, &paint);
    cg_polys_free(&outline);
}

static struct cg_paint fill_paint(CGContextRef c) {
    return (struct cg_paint){{c->gs->fill[0], c->gs->fill[1], c->gs->fill[2], c->gs->fill[3]}, NULL, NULL, false};
}

static void d_CGContextDrawPath(CGContextRef c, int mode) {
    if (!c) return;
    struct cg_paint paint = fill_paint(c);
    if (mode == MODE_FILL || mode == MODE_FILL_STROKE) fill_path(c, c->path, false, &paint);
    if (mode == MODE_EOFILL || mode == MODE_EOFILL_STROKE) fill_path(c, c->path, true, &paint);
    if (mode == MODE_STROKE || mode == MODE_FILL_STROKE || mode == MODE_EOFILL_STROKE) stroke_path(c, c->path);
    cg_path_clear(c->path);
}
DX_FN(CGContextDrawPath);
static void d_CGContextFillPath(CGContextRef c) { d_CGContextDrawPath(c, MODE_FILL); }
DX_FN(CGContextFillPath);
static void d_CGContextEOFillPath(CGContextRef c) { d_CGContextDrawPath(c, MODE_EOFILL); }
DX_FN(CGContextEOFillPath);
static void d_CGContextStrokePath(CGContextRef c) { d_CGContextDrawPath(c, MODE_STROKE); }
DX_FN(CGContextStrokePath);

static void with_temp_path(CGContextRef c, void (*build)(struct cg_path *, const void *, const CGAffineTransform *),
                           const void *arg, int mode) {
    struct cg_path *saved = c->path, *tmp = cg_path_new();
    if (!tmp) return;
    build(tmp, arg, &c->gs->ctm);
    c->path = tmp;
    d_CGContextDrawPath(c, mode);
    c->path = saved;
    cg_release(tmp);
}

static void build_rect(struct cg_path *p, const void *r, const CGAffineTransform *t) { cg_path_rect(p, *(const CGRect *)r, t); }
static void build_ellipse(struct cg_path *p, const void *r, const CGAffineTransform *t) { cg_path_ellipse(p, *(const CGRect *)r, t); }

static void d_CGContextFillRect(CGContextRef c, CGRect r) { if (c) with_temp_path(c, build_rect, &r, MODE_FILL); }
DX_FN(CGContextFillRect);
static void d_CGContextFillRects(CGContextRef c, const CGRect *r, size_t n) {
    for (size_t i = 0; c && r && i < n; i++) with_temp_path(c, build_rect, &r[i], MODE_FILL);
}
DX_FN(CGContextFillRects);
static void d_CGContextStrokeRect(CGContextRef c, CGRect r) { if (c) with_temp_path(c, build_rect, &r, MODE_STROKE); }
DX_FN(CGContextStrokeRect);
static void d_CGContextStrokeRectWithWidth(CGContextRef c, CGRect r, CGFloat w) {
    if (!c) return;
    CGFloat old = c->gs->line_width;
    c->gs->line_width = w;
    with_temp_path(c, build_rect, &r, MODE_STROKE);
    c->gs->line_width = old;
}
DX_FN(CGContextStrokeRectWithWidth);
static void d_CGContextFillEllipseInRect(CGContextRef c, CGRect r) { if (c) with_temp_path(c, build_ellipse, &r, MODE_FILL); }
DX_FN(CGContextFillEllipseInRect);
static void d_CGContextStrokeEllipseInRect(CGContextRef c, CGRect r) { if (c) with_temp_path(c, build_ellipse, &r, MODE_STROKE); }
DX_FN(CGContextStrokeEllipseInRect);

static void d_CGContextStrokeLineSegments(CGContextRef c, const CGPoint *p, size_t n) {
    if (!c || !p) return;
    struct cg_path *saved = c->path, *tmp = cg_path_new();
    if (!tmp) return;
    for (size_t i = 0; i + 1 < n; i += 2) {
        cg_path_move(tmp, cg_apply(c->gs->ctm, p[i]));
        cg_path_line(tmp, cg_apply(c->gs->ctm, p[i + 1]));
    }
    c->path = tmp;
    d_CGContextDrawPath(c, MODE_STROKE);
    c->path = saved;
    cg_release(tmp);
}
DX_FN(CGContextStrokeLineSegments);

/* Clear: paint transparent with the copy rule (clip still applies). */
static void d_CGContextClearRect(CGContextRef c, CGRect r) {
    if (!c) return;
    int blend = c->gs->blend;
    CGFloat alpha = c->gs->alpha;
    c->gs->blend = CG_BLEND_CLEAR;
    c->gs->alpha = 1;
    with_temp_path(c, build_rect, &r, MODE_FILL);
    c->gs->blend = blend;
    c->gs->alpha = alpha;
}
DX_FN(CGContextClearRect);

static void d_CGContextReplacePathWithStrokedPath(CGContextRef c) {
    if (!c) return;
    struct cg_polys outline = {0};
    stroke_outline(c, c->path, &outline);
    cg_path_clear(c->path);
    for (int i = 0; i < outline.count; i++) {
        for (int k = 0; k < outline.poly[i].count; k++) {
            if (k == 0) cg_path_move(c->path, outline.poly[i].pt[0]);
            else cg_path_line(c->path, outline.poly[i].pt[k]);
        }
        cg_path_close(c->path);
    }
    cg_polys_free(&outline);
}
DX_FN(CGContextReplacePathWithStrokedPath);

static bool d_CGContextPathContainsPoint(CGContextRef c, CGPoint p, int mode) {
    if (!c) return false;
    CGPoint d = cg_apply(c->gs->ctm, p);
    if (mode == MODE_STROKE) {
        struct cg_polys outline = {0};
        stroke_outline(c, c->path, &outline);
        int wind = 0;
        for (int i = 0; i < outline.count; i++)
            for (int k = 0; k < outline.poly[i].count; k++) {
                CGPoint a = outline.poly[i].pt[k], b = outline.poly[i].pt[(k + 1) % outline.poly[i].count];
                if ((a.y <= d.y) != (b.y <= d.y) && a.x + (d.y - a.y) * (b.x - a.x) / (b.y - a.y) > d.x)
                    wind += b.y > a.y ? 1 : -1;
            }
        cg_polys_free(&outline);
        return wind != 0;
    }
    struct cg_polys polys = {0};
    cg_flatten(c->path, 0.2, &polys);
    int wind = 0;
    for (int i = 0; i < polys.count; i++)
        for (int k = 0; k < polys.poly[i].count; k++) {
            CGPoint a = polys.poly[i].pt[k], b = polys.poly[i].pt[(k + 1) % polys.poly[i].count];
            if ((a.y <= d.y) != (b.y <= d.y) && a.x + (d.y - a.y) * (b.x - a.x) / (b.y - a.y) > d.x)
                wind += b.y > a.y ? 1 : -1;
        }
    cg_polys_free(&polys);
    bool eo = mode == MODE_EOFILL || mode == MODE_EOFILL_STROKE;
    return eo ? (wind & 1) : wind != 0;
}
DX_FN(CGContextPathContainsPoint);

/* ---- clipping ------------------------------------------------------------------------------- */

static void intersect_clip(CGContextRef c, struct cg_mask *m) {
    struct gstate *g = c->gs;
    if (g->clip) {
        for (size_t i = 0; i < m->width * m->height; i++)
            m->data[i] = (uint8_t)((m->data[i] * g->clip->data[i] + 127) / 255);
        cg_mask_release(g->clip);
    }
    g->clip = m;
}

static void clip_to_path(CGContextRef c, const struct cg_path *p, bool eo) {
    struct cg_mask *m = cg_mask_new(c->target->width, c->target->height, 0);
    if (!m) return;
    struct cg_polys polys = {0};
    cg_flatten(p, 0.2, &polys);
    cg_mask_polys(m, &polys, eo, c->gs->antialias && c->gs->allows_antialias);
    cg_polys_free(&polys);
    intersect_clip(c, m);
}

static void d_CGContextClip(CGContextRef c) {
    if (!c) return;
    clip_to_path(c, c->path, false);
    cg_path_clear(c->path);
}
DX_FN(CGContextClip);
static void d_CGContextEOClip(CGContextRef c) {
    if (!c) return;
    clip_to_path(c, c->path, true);
    cg_path_clear(c->path);
}
DX_FN(CGContextEOClip);
static void d_CGContextClipToRect(CGContextRef c, CGRect r) {
    if (!c) return;
    struct cg_path *p = cg_path_new();
    if (!p) return;
    cg_path_rect(p, r, &c->gs->ctm);
    clip_to_path(c, p, false);
    cg_release(p);
}
DX_FN(CGContextClipToRect);
static void d_CGContextClipToRects(CGContextRef c, const CGRect *r, size_t n) {
    if (!c || !r) return;
    struct cg_path *p = cg_path_new();
    if (!p) return;
    for (size_t i = 0; i < n; i++) cg_path_rect(p, r[i], &c->gs->ctm);
    clip_to_path(c, p, false);
    cg_release(p);
}
DX_FN(CGContextClipToRects);

/* The image's luminance (or a mask's coverage) over rect becomes the clip. */
static void d_CGContextClipToMask(CGContextRef c, CGRect r, const struct cg_image *img) {
    if (!c || !img) return;
    size_t w = c->target->width, h = c->target->height;
    struct cg_mask *m = cg_mask_new(w, h, 0);
    if (!m) return;
    CGAffineTransform inv = cg_invert(c->gs->ctm);
    for (size_t row = 0; row < h; row++)
        for (size_t x = 0; x < w; x++) {
            CGPoint u = cg_apply(inv, (CGPoint){x + 0.5, h - (row + 0.5)});
            CGFloat fx = (u.x - r.origin.x) / r.size.width, fy = (u.y - r.origin.y) / r.size.height;
            if (fx < 0 || fx >= 1 || fy < 0 || fy >= 1) continue;
            CGFloat s[4];
            cg_image_sample(img, fx * img->width, (1 - fy) * img->height, true, false, s);
            CGFloat v = img->is_mask ? s[3] : 0.2126 * s[0] + 0.7152 * s[1] + 0.0722 * s[2];
            m->data[row * w + x] = (uint8_t)(fmin(fmax(v, 0), 1) * 255 + 0.5);
        }
    intersect_clip(c, m);
}
DX_FN(CGContextClipToMask);

static CGRect d_CGContextGetClipBoundingBox(CGContextRef c) {
    if (!c) return (CGRect){{INFINITY, INFINITY}, {0, 0}};
    size_t w = c->target->width, h = c->target->height;
    CGRect dev = {{0, 0}, {(CGFloat)w, (CGFloat)h}};
    if (c->gs->clip) {
        long x0 = (long)w, x1 = -1, r0 = (long)h, r1 = -1;
        for (size_t row = 0; row < h; row++)
            for (size_t x = 0; x < w; x++)
                if (c->gs->clip->data[row * w + x]) {
                    if ((long)x < x0) x0 = (long)x;
                    if ((long)x > x1) x1 = (long)x;
                    if ((long)row < r0) r0 = (long)row;
                    if ((long)row > r1) r1 = (long)row;
                }
        if (x1 < 0) return (CGRect){{INFINITY, INFINITY}, {0, 0}};
        dev = (CGRect){{(CGFloat)x0, (CGFloat)h - (r1 + 1)}, {(CGFloat)(x1 - x0 + 1), (CGFloat)(r1 - r0 + 1)}};
    }
    return rect_apply(dev, cg_invert(c->gs->ctm));
}
DX_FN(CGContextGetClipBoundingBox);

/* ---- images ------------------------------------------------------------------------------------- */

struct image_paint {
    const struct cg_image *img;
    CGAffineTransform inv;          /* device -> user */
    CGRect rect;
    bool smooth, tile;
    CGFloat fill[4];                /* for masks */
};

static void shade_image(const struct cg_paint *paint, CGFloat x, CGFloat y, CGFloat out[4]) {
    const struct image_paint *ip = paint->info;
    CGPoint u = cg_apply(ip->inv, (CGPoint){x, y});
    CGFloat fx = (u.x - ip->rect.origin.x) / ip->rect.size.width;
    CGFloat fy = (u.y - ip->rect.origin.y) / ip->rect.size.height;
    if (!ip->tile && (fx < 0 || fx > 1 || fy < 0 || fy > 1)) { out[0] = out[1] = out[2] = out[3] = 0; return; }
    cg_image_sample(ip->img, fx * ip->img->width, (1 - fy) * ip->img->height, ip->smooth, ip->tile, out);
    if (ip->img->is_mask) {
        CGFloat a = out[3] * ip->fill[3];
        for (int k = 0; k < 3; k++) out[k] = ip->fill[k] * a;
        out[3] = a;
    }
}

static void draw_image(CGContextRef c, CGRect r, const struct cg_image *img, bool tile) {
    if (!c || !img || r.size.width == 0 || r.size.height == 0) return;
    struct image_paint ip = {img, cg_invert(c->gs->ctm), r, c->gs->interpolation != 1 && img->interpolate, tile, {0}};
    memcpy(ip.fill, c->gs->fill, sizeof ip.fill);
    struct cg_paint paint = {{0, 0, 0, 0}, shade_image, &ip, true};
    struct cg_path *p = cg_path_new();
    if (!p) return;
    if (tile) cg_path_rect(p, (CGRect){{0, 0}, {(CGFloat)c->target->width, (CGFloat)c->target->height}}, NULL);
    else cg_path_rect(p, r, &c->gs->ctm);
    fill_path(c, p, false, &paint);
    cg_release(p);
}

static void d_CGContextDrawImage(CGContextRef c, CGRect r, const struct cg_image *img) { draw_image(c, r, img, false); }
DX_FN(CGContextDrawImage);
static void d_CGContextDrawTiledImage(CGContextRef c, CGRect r, const struct cg_image *img) { draw_image(c, r, img, true); }
DX_FN(CGContextDrawTiledImage);

/* ---- gradients ---------------------------------------------------------------------------------- */

enum { EXTEND_BEFORE = 1, EXTEND_AFTER = 2 };

struct gradient_paint {
    const struct cg_gradient *g;
    CGAffineTransform inv;
    CGPoint p0, p1;
    CGFloat r0, r1;
    int options;
    bool radial;
};

static void shade_gradient(const struct cg_paint *paint, CGFloat x, CGFloat y, CGFloat out[4]) {
    const struct gradient_paint *gp = paint->info;
    CGPoint u = cg_apply(gp->inv, (CGPoint){x, y});
    CGFloat t;
    if (!gp->radial) {
        CGFloat dx = gp->p1.x - gp->p0.x, dy = gp->p1.y - gp->p0.y, len2 = dx * dx + dy * dy;
        t = len2 > 0 ? ((u.x - gp->p0.x) * dx + (u.y - gp->p0.y) * dy) / len2 : 0;
    } else {
        /* The largest t with |u - c(t)| = r(t) and r(t) >= 0, where
         * c(t) = p0 + t (p1 - p0) and r(t) = r0 + t (r1 - r0). */
        CGFloat cdx = gp->p1.x - gp->p0.x, cdy = gp->p1.y - gp->p0.y, dr = gp->r1 - gp->r0;
        CGFloat pdx = u.x - gp->p0.x, pdy = u.y - gp->p0.y;
        CGFloat a = cdx * cdx + cdy * cdy - dr * dr;
        CGFloat b = pdx * cdx + pdy * cdy + gp->r0 * dr;
        CGFloat cc = pdx * pdx + pdy * pdy - gp->r0 * gp->r0;
        if (fabs(a) < 1e-12) {
            if (fabs(b) < 1e-12) { out[3] = 0; out[0] = out[1] = out[2] = 0; return; }
            t = cc / (2 * b);
        } else {
            CGFloat disc = b * b - a * cc;
            if (disc < 0) { out[0] = out[1] = out[2] = out[3] = 0; return; }
            CGFloat s = sqrt(disc), t1 = (b + s) / a, t2 = (b - s) / a;
            t = fmax(t1, t2);
            if (gp->r0 + t * dr < 0) t = fmin(t1, t2);
            if (gp->r0 + t * dr < 0) { out[0] = out[1] = out[2] = out[3] = 0; return; }
        }
    }
    if ((t < 0 && !(gp->options & EXTEND_BEFORE)) || (t > 1 && !(gp->options & EXTEND_AFTER))) {
        out[0] = out[1] = out[2] = out[3] = 0;
        return;
    }
    cg_gradient_at(gp->g, t < 0 ? 0 : t > 1 ? 1 : t, out);
}

static void draw_gradient(CGContextRef c, struct gradient_paint *gp) {
    struct cg_paint paint = {{0, 0, 0, 0}, shade_gradient, gp, false};
    struct cg_path *p = cg_path_new();
    if (!p) return;
    cg_path_rect(p, (CGRect){{0, 0}, {(CGFloat)c->target->width, (CGFloat)c->target->height}}, NULL);
    fill_path(c, p, false, &paint);
    cg_release(p);
}

static void d_CGContextDrawLinearGradient(CGContextRef c, const struct cg_gradient *g, CGPoint p0, CGPoint p1, uint32_t options) {
    if (!c || !g) return;
    struct gradient_paint gp = {g, cg_invert(c->gs->ctm), p0, p1, 0, 0, (int)options, false};
    draw_gradient(c, &gp);
}
DX_FN(CGContextDrawLinearGradient);

static void d_CGContextDrawRadialGradient(CGContextRef c, const struct cg_gradient *g, CGPoint p0, CGFloat r0,
                                          CGPoint p1, CGFloat r1, uint32_t options) {
    if (!c || !g) return;
    struct gradient_paint gp = {g, cg_invert(c->gs->ctm), p0, p1, r0, r1, (int)options, true};
    draw_gradient(c, &gp);
}
DX_FN(CGContextDrawRadialGradient);

/* ---- transparency layers ------------------------------------------------------------------------- */

static void d_CGContextBeginTransparencyLayer(CGContextRef c, const void *aux) {
    if (!c) return;
    struct layer *l = calloc(1, sizeof *l);
    if (!l) return;
    size_t w = c->target->width, h = c->target->height;
    struct cg_format f = {4, 0, 1, 2, 3, false, false, false};
    l->surface = (struct cg_surface){calloc(h ? h : 1, w ? w * 4 : 1), w, h, w * 4, f};
    if (!l->surface.data) { free(l); return; }
    l->under = c->target;
    l->alpha = c->gs->alpha;
    l->blend = c->gs->blend;
    l->next = c->layers;
    c->layers = l;
    c->target = &l->surface;
    d_CGContextSaveGState(c);
    c->gs->alpha = 1;
    c->gs->blend = CG_BLEND_NORMAL;
}
DX_FN(CGContextBeginTransparencyLayer);

static void d_CGContextBeginTransparencyLayerWithRect(CGContextRef c, CGRect r, const void *aux) {
    d_CGContextBeginTransparencyLayer(c, aux);
}
DX_FN(CGContextBeginTransparencyLayerWithRect);

static void d_CGContextEndTransparencyLayer(CGContextRef c) {
    if (!c || !c->layers) return;
    struct layer *l = c->layers;
    d_CGContextRestoreGState(c);
    c->layers = l->next;
    c->target = l->under;
    struct cg_target t = {c->target, c->gs->clip, l->alpha, l->blend, true};
    for (size_t row = 0; row < l->surface.height; row++)
        for (size_t x = 0; x < l->surface.width; x++) {
            CGFloat px[4];
            cg_read_pixel(&l->surface, x, row, px);
            if (px[3] > 0 || l->blend == CG_BLEND_COPY) cg_blend_pixel(&t, x, row, px, 1);
        }
    free(l->surface.data);
    free(l);
}
DX_FN(CGContextEndTransparencyLayer);
