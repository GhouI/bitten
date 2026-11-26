/* CoreGraphics: color spaces, colors and gradients.
 *
 * Two color models, gray and RGB. Named spaces (sRGB, Display P3, the
 * linear and extended ones) are RGB or gray spaces that keep their name;
 * colors are not converted between them, which is right for sRGB and close
 * for the rest. */
#include <stdio.h>
#include <string.h>

#include "cg.h"

const void *d_CFRetain(const void *object);
void d_CFRelease(const void *object);
struct cf_string *d___CFStringMakeConstantString(const char *bytes);

void *cg_retain(const void *o) { return o ? (void *)d_CFRetain(o) : NULL; }
void cg_release(const void *o) { if (o) d_CFRelease(o); }

/* ---- color spaces ------------------------------------------------------ */

static void space_destroy(void *o) {
    struct cg_colorspace *s = o;
    cg_release(s->name);
}
static const struct cf_ops space_ops = {space_destroy, NULL, NULL, NULL};

static struct cg_colorspace *space_new(enum cg_model model, const void *name) {
    struct cg_colorspace *s = cf_alloc(NULL, sizeof *s, CF_CG_COLORSPACE, &space_ops);
    if (!s) return NULL;
    s->model = model;
    s->components = model == CG_RGB ? 3 : 1;
    s->name = cg_retain(name);
    return s;
}

static struct cg_colorspace *shared_rgb, *shared_gray;

struct cg_colorspace *cg_space_rgb(void) {
    if (!shared_rgb) {
        shared_rgb = space_new(CG_RGB, NULL);
        atomic_store(&shared_rgb->base.refs, LONG_MAX);
    }
    return shared_rgb;
}

struct cg_colorspace *cg_space_gray(void) {
    if (!shared_gray) {
        shared_gray = space_new(CG_GRAY, NULL);
        atomic_store(&shared_gray->base.refs, LONG_MAX);
    }
    return shared_gray;
}

#define SPACE_NAME(name)                                                         \
    static const void *d_##name;                                                 \
    DX_EXPORT("_" #name, &d_##name)
SPACE_NAME(kCGColorSpaceGenericGray);
SPACE_NAME(kCGColorSpaceGenericRGB);
SPACE_NAME(kCGColorSpaceGenericCMYK);
SPACE_NAME(kCGColorSpaceSRGB);
SPACE_NAME(kCGColorSpaceExtendedSRGB);
SPACE_NAME(kCGColorSpaceLinearSRGB);
SPACE_NAME(kCGColorSpaceExtendedLinearSRGB);
SPACE_NAME(kCGColorSpaceDisplayP3);
SPACE_NAME(kCGColorSpaceExtendedDisplayP3);
SPACE_NAME(kCGColorSpaceGenericGrayGamma2_2);
SPACE_NAME(kCGColorSpaceLinearGray);
SPACE_NAME(kCGColorSpaceExtendedGray);
SPACE_NAME(kCGColorSpaceExtendedLinearGray);
SPACE_NAME(kCGColorSpaceGenericRGBLinear);
SPACE_NAME(kCGColorWhite);
SPACE_NAME(kCGColorBlack);
SPACE_NAME(kCGColorClear);

__attribute__((constructor)) static void color_names(void) {
#define NAME(n) d_##n = d___CFStringMakeConstantString(#n)
    NAME(kCGColorSpaceGenericGray);
    NAME(kCGColorSpaceGenericRGB);
    NAME(kCGColorSpaceGenericCMYK);
    NAME(kCGColorSpaceSRGB);
    NAME(kCGColorSpaceExtendedSRGB);
    NAME(kCGColorSpaceLinearSRGB);
    NAME(kCGColorSpaceExtendedLinearSRGB);
    NAME(kCGColorSpaceDisplayP3);
    NAME(kCGColorSpaceExtendedDisplayP3);
    NAME(kCGColorSpaceGenericGrayGamma2_2);
    NAME(kCGColorSpaceLinearGray);
    NAME(kCGColorSpaceExtendedGray);
    NAME(kCGColorSpaceExtendedLinearGray);
    NAME(kCGColorSpaceGenericRGBLinear);
    NAME(kCGColorWhite);
    NAME(kCGColorBlack);
    NAME(kCGColorClear);
#undef NAME
}

static struct cg_colorspace *d_CGColorSpaceCreateDeviceRGB(void) { return cg_retain(cg_space_rgb()); }
DX_FN(CGColorSpaceCreateDeviceRGB);
static struct cg_colorspace *d_CGColorSpaceCreateDeviceGray(void) { return cg_retain(cg_space_gray()); }
DX_FN(CGColorSpaceCreateDeviceGray);

static struct cg_colorspace *d_CGColorSpaceCreateWithName(const void *name) {
    if (!name) return NULL;
    const void *gray[] = {d_kCGColorSpaceGenericGray, d_kCGColorSpaceGenericGrayGamma2_2,
                          d_kCGColorSpaceLinearGray, d_kCGColorSpaceExtendedGray,
                          d_kCGColorSpaceExtendedLinearGray};
    for (size_t i = 0; i < sizeof gray / sizeof *gray; i++)
        if (d_CFEqual(name, gray[i])) return space_new(CG_GRAY, name);
    if (d_CFEqual(name, d_kCGColorSpaceGenericCMYK)) return NULL;     /* no CMYK here */
    return space_new(CG_RGB, name);
}
DX_FN(CGColorSpaceCreateWithName);

static struct cg_colorspace *d_CGColorSpaceRetain(struct cg_colorspace *s) { return cg_retain(s); }
DX_FN(CGColorSpaceRetain);
static void d_CGColorSpaceRelease(struct cg_colorspace *s) { cg_release(s); }
DX_FN(CGColorSpaceRelease);
static size_t d_CGColorSpaceGetNumberOfComponents(const struct cg_colorspace *s) { return s ? (size_t)s->components : 0; }
DX_FN(CGColorSpaceGetNumberOfComponents);
/* CGColorSpaceModel: monochrome 0, RGB 1. */
static int d_CGColorSpaceGetModel(const struct cg_colorspace *s) { return s ? (int)s->model : -1; }
DX_FN(CGColorSpaceGetModel);
static const void *d_CGColorSpaceGetName(const struct cg_colorspace *s) { return s ? s->name : NULL; }
DX_FN(CGColorSpaceGetName);
static const void *d_CGColorSpaceCopyName(const struct cg_colorspace *s) { return s ? cg_retain(s->name) : NULL; }
DX_FN(CGColorSpaceCopyName);
static bool d_CGColorSpaceSupportsOutput(const struct cg_colorspace *s) { return s != NULL; }
DX_FN(CGColorSpaceSupportsOutput);
static bool d_CGColorSpaceIsWideGamutRGB(const struct cg_colorspace *s) {
    return s && s->name && (d_CFEqual(s->name, d_kCGColorSpaceDisplayP3) || d_CFEqual(s->name, d_kCGColorSpaceExtendedDisplayP3));
}
DX_FN(CGColorSpaceIsWideGamutRGB);
CF_TYPE_ID(CGColorSpace, CF_CG_COLORSPACE);

/* ---- colors -------------------------------------------------------------- */

static void color_destroy(void *o) { cg_release(((struct cg_color *)o)->space); }

static Boolean color_equal(const void *a, const void *b) {
    const struct cg_color *x = a, *y = b;
    if (x->count != y->count || x->space->model != y->space->model) return 0;
    for (int i = 0; i < x->count; i++)
        if (x->c[i] != y->c[i]) return 0;
    return 1;
}
static const struct cf_ops color_ops = {color_destroy, color_equal, NULL, NULL};

static struct cg_color *color_new(struct cg_colorspace *space, const CGFloat *c) {
    if (!space || !c) return NULL;
    struct cg_color *k = cf_alloc(NULL, sizeof *k, CF_CG_COLOR, &color_ops);
    if (!k) return NULL;
    k->space = cg_retain(space);
    k->count = space->components + 1;
    for (int i = 0; i < k->count; i++) k->c[i] = c[i];
    return k;
}

void cg_color_rgba(const struct cg_color *color, CGFloat out[4]) {
    if (!color) { out[0] = out[1] = out[2] = 0; out[3] = 1; return; }
    if (color->space->model == CG_GRAY) {
        out[0] = out[1] = out[2] = color->c[0];
        out[3] = color->c[1];
    } else {
        for (int i = 0; i < 4; i++) out[i] = color->c[i];
    }
}

static struct cg_color *d_CGColorCreate(struct cg_colorspace *space, const CGFloat *components) {
    return color_new(space, components);
}
DX_FN(CGColorCreate);

static struct cg_color *d_CGColorCreateGenericRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    CGFloat c[] = {r, g, b, a};
    return color_new(cg_space_rgb(), c);
}
DX_FN(CGColorCreateGenericRGB);

static struct cg_color *d_CGColorCreateSRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    CGFloat c[] = {r, g, b, a};
    struct cg_colorspace *s = d_CGColorSpaceCreateWithName(d_kCGColorSpaceSRGB);
    struct cg_color *k = color_new(s, c);
    cg_release(s);
    return k;
}
DX_FN(CGColorCreateSRGB);

static struct cg_color *d_CGColorCreateGenericGray(CGFloat g, CGFloat a) {
    CGFloat c[] = {g, a};
    return color_new(cg_space_gray(), c);
}
DX_FN(CGColorCreateGenericGray);

static struct cg_color *d_CGColorCreateGenericGrayGamma2_2(CGFloat g, CGFloat a) {
    return d_CGColorCreateGenericGray(g, a);
}
DX_FN(CGColorCreateGenericGrayGamma2_2);

static struct cg_color *d_CGColorCreateCopy(const struct cg_color *k) { return k ? color_new(k->space, k->c) : NULL; }
DX_FN(CGColorCreateCopy);

static struct cg_color *d_CGColorCreateCopyWithAlpha(const struct cg_color *k, CGFloat alpha) {
    if (!k) return NULL;
    CGFloat c[5];
    memcpy(c, k->c, sizeof c);
    c[k->count - 1] = alpha;
    return color_new(k->space, c);
}
DX_FN(CGColorCreateCopyWithAlpha);

static struct cg_color *d_CGColorCreateCopyByMatchingToColorSpace(struct cg_colorspace *space, int intent,
                                                                   const struct cg_color *k, const void *options) {
    if (!space || !k) return NULL;
    CGFloat rgba[4];
    cg_color_rgba(k, rgba);
    if (space->model == CG_GRAY) {
        CGFloat c[] = {0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2], rgba[3]};
        return color_new(space, c);
    }
    return color_new(space, rgba);
}
DX_FN(CGColorCreateCopyByMatchingToColorSpace);

static const struct cg_color *d_CGColorGetConstantColor(const void *name) {
    static struct cg_color *white, *black, *clear;
    if (!name) return NULL;
    if (d_CFEqual(name, d_kCGColorWhite)) {
        if (!white) { white = d_CGColorCreateGenericGray(1, 1); atomic_store(&white->base.refs, LONG_MAX); }
        return white;
    }
    if (d_CFEqual(name, d_kCGColorBlack)) {
        if (!black) { black = d_CGColorCreateGenericGray(0, 1); atomic_store(&black->base.refs, LONG_MAX); }
        return black;
    }
    if (d_CFEqual(name, d_kCGColorClear)) {
        if (!clear) { clear = d_CGColorCreateGenericGray(0, 0); atomic_store(&clear->base.refs, LONG_MAX); }
        return clear;
    }
    return NULL;
}
DX_FN(CGColorGetConstantColor);

static struct cg_color *d_CGColorRetain(struct cg_color *k) { return cg_retain(k); }
DX_FN(CGColorRetain);
static void d_CGColorRelease(struct cg_color *k) { cg_release(k); }
DX_FN(CGColorRelease);
static bool d_CGColorEqualToColor(const struct cg_color *a, const struct cg_color *b) {
    return a == b || (a && b && color_equal(a, b));
}
DX_FN(CGColorEqualToColor);
static size_t d_CGColorGetNumberOfComponents(const struct cg_color *k) { return k ? (size_t)k->count : 0; }
DX_FN(CGColorGetNumberOfComponents);
static const CGFloat *d_CGColorGetComponents(const struct cg_color *k) { return k ? k->c : NULL; }
DX_FN(CGColorGetComponents);
static CGFloat d_CGColorGetAlpha(const struct cg_color *k) { return k ? k->c[k->count - 1] : 0; }
DX_FN(CGColorGetAlpha);
static struct cg_colorspace *d_CGColorGetColorSpace(const struct cg_color *k) { return k ? k->space : NULL; }
DX_FN(CGColorGetColorSpace);
static const void *d_CGColorGetPattern(const struct cg_color *k) { return NULL; }
DX_FN(CGColorGetPattern);
CF_TYPE_ID(CGColor, CF_CG_COLOR);

/* ---- gradients ------------------------------------------------------------ */

static void gradient_destroy(void *o) {
    struct cg_gradient *g = o;
    free(g->rgba);
    free(g->locations);
}
static const struct cf_ops gradient_ops = {gradient_destroy, NULL, NULL, NULL};

static struct cg_gradient *gradient_new(int count) {
    if (count < 1) return NULL;
    struct cg_gradient *g = cf_alloc(NULL, sizeof *g, CF_CG_GRADIENT, &gradient_ops);
    if (!g) return NULL;
    g->count = count;
    g->rgba = calloc((size_t)count, sizeof *g->rgba);
    g->locations = calloc((size_t)count, sizeof *g->locations);
    return g;
}

static void gradient_default_locations(struct cg_gradient *g, const CGFloat *locations) {
    for (int i = 0; i < g->count; i++)
        g->locations[i] = locations ? locations[i] : (g->count == 1 ? 0 : (CGFloat)i / (g->count - 1));
}

typedef const void *CFArrayRef;

static struct cg_gradient *d_CGGradientCreateWithColors(struct cg_colorspace *space, CFArrayRef colors,
                                                        const CGFloat *locations) {
    if (!colors) return NULL;
    struct cg_gradient *g = gradient_new((int)d_CFArrayGetCount((const struct cf_array *)colors));
    if (!g) return NULL;
    for (int i = 0; i < g->count; i++) cg_color_rgba(d_CFArrayGetValueAtIndex((const struct cf_array *)colors, i), g->rgba[i]);
    gradient_default_locations(g, locations);
    return g;
}
DX_FN(CGGradientCreateWithColors);

static struct cg_gradient *d_CGGradientCreateWithColorComponents(struct cg_colorspace *space,
                                                                 const CGFloat *components,
                                                                 const CGFloat *locations, size_t count) {
    if (!space || !components) return NULL;
    struct cg_gradient *g = gradient_new((int)count);
    if (!g) return NULL;
    int n = space->components + 1;
    for (int i = 0; i < g->count; i++) {
        const CGFloat *c = components + i * n;
        if (space->model == CG_GRAY) {
            g->rgba[i][0] = g->rgba[i][1] = g->rgba[i][2] = c[0];
            g->rgba[i][3] = c[1];
        } else {
            memcpy(g->rgba[i], c, 4 * sizeof *c);
        }
    }
    gradient_default_locations(g, locations);
    return g;
}
DX_FN(CGGradientCreateWithColorComponents);

static struct cg_gradient *d_CGGradientRetain(struct cg_gradient *g) { return cg_retain(g); }
DX_FN(CGGradientRetain);
static void d_CGGradientRelease(struct cg_gradient *g) { cg_release(g); }
DX_FN(CGGradientRelease);
CF_TYPE_ID(CGGradient, CF_CG_GRADIENT);

/* The color at t, interpolated between stops (straight alpha in, out). */
void cg_gradient_at(const struct cg_gradient *g, CGFloat t, CGFloat out[4]) {
    if (t <= g->locations[0] || g->count == 1) { memcpy(out, g->rgba[0], 4 * sizeof *out); return; }
    if (t >= g->locations[g->count - 1]) { memcpy(out, g->rgba[g->count - 1], 4 * sizeof *out); return; }
    int i = 1;
    while (i < g->count - 1 && g->locations[i] < t) i++;
    CGFloat span = g->locations[i] - g->locations[i - 1];
    CGFloat f = span > 0 ? (t - g->locations[i - 1]) / span : 1;
    /* Interpolate premultiplied, as Apple does, then give back straight. */
    CGFloat a0 = g->rgba[i - 1][3], a1 = g->rgba[i][3];
    CGFloat a = a0 + (a1 - a0) * f;
    for (int k = 0; k < 3; k++) {
        CGFloat p = g->rgba[i - 1][k] * a0 + (g->rgba[i][k] * a1 - g->rgba[i - 1][k] * a0) * f;
        out[k] = a > 0 ? p / a : g->rgba[i - 1][k] + (g->rgba[i][k] - g->rgba[i - 1][k]) * f;
    }
    out[3] = a;
}
