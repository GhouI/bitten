/* CoreText: CTFont, CTFontDescriptor, CTFontCollection, CTFontManager and
 * the attribute keys. A CTFont is a TrueType face (ttf.c) at a size; its
 * name is the one it was asked for, so programs that ask for the system
 * font get its name back. */
#include <stdio.h>
#include <string.h>

#include "ct.h"

/* ---- strings and constants ---------------------------------------------------- */

Ref ct_cfstring(const char *s) {
    return CALL(Ref, CFStringCreateWithCString, (Ref, const char *, uint32_t))(NULL, s ? s : "", UTF8);
}

static Ref konst(const char *s) { return CALL(Ref, __CFStringMakeConstantString, (const char *))(s); }

static bool cstring(Ref s, char *out, size_t size) {
    out[0] = 0;
    return s && CALL(Boolean, CFStringGetCString, (Ref, char *, CFIndex, uint32_t))(s, out, (CFIndex)size, UTF8);
}

#define KEY(name) const void *d_##name; DX_EXPORT("_" #name, &d_##name)
KEY(kCTFontAttributeName);
KEY(kCTForegroundColorAttributeName);
KEY(kCTForegroundColorFromContextAttributeName);
KEY(kCTKernAttributeName);
KEY(kCTParagraphStyleAttributeName);
KEY(kCTUnderlineStyleAttributeName);
KEY(kCTUnderlineColorAttributeName);
KEY(kCTStrokeWidthAttributeName);
KEY(kCTStrokeColorAttributeName);
KEY(kCTLigatureAttributeName);
KEY(kCTBaselineOffsetAttributeName);
KEY(kCTFontNameAttribute);
KEY(kCTFontDisplayNameAttribute);
KEY(kCTFontFamilyNameAttribute);
KEY(kCTFontStyleNameAttribute);
KEY(kCTFontTraitsAttribute);
KEY(kCTFontSizeAttribute);
KEY(kCTFontMatrixAttribute);
KEY(kCTFontURLAttribute);
KEY(kCTFontCascadeListAttribute);
KEY(kCTFontCharacterSetAttribute);
KEY(kCTFontLanguagesAttribute);
KEY(kCTFontFeatureSettingsAttribute);
KEY(kCTFontFeaturesAttribute);
KEY(kCTFontVariationAttribute);
KEY(kCTFontOpticalSizeAttribute);
KEY(kCTFontFixedAdvanceAttribute);
KEY(kCTFontSymbolicTrait);
KEY(kCTFontWeightTrait);
KEY(kCTFontWidthTrait);
KEY(kCTFontSlantTrait);
KEY(kCTFontCopyrightNameKey);
KEY(kCTFontFamilyNameKey);
KEY(kCTFontSubFamilyNameKey);
KEY(kCTFontStyleNameKey);
KEY(kCTFontUniqueNameKey);
KEY(kCTFontFullNameKey);
KEY(kCTFontVersionNameKey);
KEY(kCTFontPostScriptNameKey);
KEY(kCTFontOpenTypeFeatureTag);
KEY(kCTFontOpenTypeFeatureValue);
KEY(kCTFontFeatureTypeIdentifierKey);
KEY(kCTFontFeatureSelectorIdentifierKey);
KEY(kCTFontVariationAxisIdentifierKey);
KEY(kCTFontVariationAxisMinimumValueKey);
KEY(kCTFontVariationAxisMaximumValueKey);
KEY(kCTFontVariationAxisDefaultValueKey);
KEY(kCTFontVariationAxisNameKey);
Ref ct_ns_color_attribute;

/* The string values of Apple's frameworks; NSFontAttributeName is the same
 * string as kCTFontAttributeName ("NSFont"). */
__attribute__((constructor)) static void ct_keys(void) {
#define SET(n, v) d_##n = konst(v)
    SET(kCTFontAttributeName, "NSFont");
    SET(kCTForegroundColorAttributeName, "CTForegroundColor");
    SET(kCTForegroundColorFromContextAttributeName, "CTForegroundColorFromContext");
    SET(kCTKernAttributeName, "NSKern");
    SET(kCTParagraphStyleAttributeName, "NSParagraphStyle");
    SET(kCTUnderlineStyleAttributeName, "NSUnderline");
    SET(kCTUnderlineColorAttributeName, "NSUnderlineColor");
    SET(kCTStrokeWidthAttributeName, "NSStrokeWidth");
    SET(kCTStrokeColorAttributeName, "NSStrokeColor");
    SET(kCTLigatureAttributeName, "NSLigature");
    SET(kCTBaselineOffsetAttributeName, "CTBaselineOffset");
    SET(kCTFontNameAttribute, "NSFontNameAttribute");
    SET(kCTFontDisplayNameAttribute, "NSFontVisibleNameAttribute");
    SET(kCTFontFamilyNameAttribute, "NSFontFamilyAttribute");
    SET(kCTFontStyleNameAttribute, "NSFontFaceAttribute");
    SET(kCTFontTraitsAttribute, "NSCTFontTraitsAttribute");
    SET(kCTFontSizeAttribute, "NSFontSizeAttribute");
    SET(kCTFontMatrixAttribute, "NSFontMatrixAttribute");
    SET(kCTFontURLAttribute, "NSCTFontFileURLAttribute");
    SET(kCTFontCascadeListAttribute, "NSCTFontCascadeListAttribute");
    SET(kCTFontCharacterSetAttribute, "NSCTFontCharacterSetAttribute");
    SET(kCTFontLanguagesAttribute, "NSCTFontLanguagesAttribute");
    SET(kCTFontFeatureSettingsAttribute, "NSCTFontFeatureSettingsAttribute");
    SET(kCTFontFeaturesAttribute, "NSCTFontFeaturesAttribute");
    SET(kCTFontVariationAttribute, "NSCTFontVariationAttribute");
    SET(kCTFontOpticalSizeAttribute, "NSCTFontOpticalSizeAttribute");
    SET(kCTFontFixedAdvanceAttribute, "NSFontFixedAdvanceAttribute");
    SET(kCTFontSymbolicTrait, "NSCTFontSymbolicTrait");
    SET(kCTFontWeightTrait, "NSCTFontWeightTrait");
    SET(kCTFontWidthTrait, "NSCTFontProportionTrait");
    SET(kCTFontSlantTrait, "NSCTFontSlantTrait");
    SET(kCTFontCopyrightNameKey, "CTFontCopyrightName");
    SET(kCTFontFamilyNameKey, "CTFontFamilyName");
    SET(kCTFontSubFamilyNameKey, "CTFontSubFamilyName");
    SET(kCTFontStyleNameKey, "CTFontSubFamilyName");
    SET(kCTFontUniqueNameKey, "CTFontUniqueName");
    SET(kCTFontFullNameKey, "CTFontFullName");
    SET(kCTFontVersionNameKey, "CTFontVersionName");
    SET(kCTFontPostScriptNameKey, "CTFontPostScriptName");
    SET(kCTFontOpenTypeFeatureTag, "CTFeatureOpenTypeTag");
    SET(kCTFontOpenTypeFeatureValue, "CTFeatureOpenTypeValue");
    SET(kCTFontFeatureTypeIdentifierKey, "CTFeatureTypeIdentifier");
    SET(kCTFontFeatureSelectorIdentifierKey, "CTFeatureSelectorIdentifier");
    SET(kCTFontVariationAxisIdentifierKey, "NSCTVariationAxisIdentifier");
    SET(kCTFontVariationAxisMinimumValueKey, "NSCTVariationAxisMinimumValue");
    SET(kCTFontVariationAxisMaximumValueKey, "NSCTVariationAxisMaximumValue");
    SET(kCTFontVariationAxisDefaultValueKey, "NSCTVariationAxisDefaultValue");
    SET(kCTFontVariationAxisNameKey, "NSCTVariationAxisName");
#undef SET
    ct_ns_color_attribute = konst("NSColor");
}

/* ---- the font object --------------------------------------------------------------- */

static void font_destroy(void *o) { cg_release(((struct ct_font *)o)->requested_name); }

static Boolean font_equal(const void *a, const void *b) {
    const struct ct_font *x = a, *y = b;
    return x->face == y->face && x->size == y->size;
}
static CFHashCode font_hash(const void *o) {
    const struct ct_font *f = o;
    return (CFHashCode)(uintptr_t)f->face ^ (CFHashCode)(f->size * 64);
}
static const struct cf_ops font_ops = {font_destroy, font_equal, font_hash, NULL};

struct ct_font *ct_font_new(struct ttf *face, CGFloat size, const CGAffineTransform *matrix, Ref name) {
    if (!face) return NULL;
    struct ct_font *f = cf_alloc(NULL, sizeof *f, CF_CT_FONT, &font_ops);
    if (!f) return NULL;
    f->face = face;
    f->size = size > 0 ? size : 12;
    f->matrix = matrix ? *matrix : CG_IDENTITY;
    f->requested_name = name ? cg_retain(name) : ct_cfstring(face->postscript[0] ? face->postscript : face->full);
    return f;
}

struct ct_font *ct_default_font(void) {
    static struct ct_font *font;
    if (!font) {
        struct ttf *face = ct_face_for_name("Helvetica");
        if (!face) return NULL;
        font = ct_font_new(face, 12, NULL, konst("Helvetica"));
        atomic_store(&font->base.refs, LONG_MAX);
    }
    return font;
}

CGFloat ct_scale(const struct ct_font *f) { return f->size / f->face->units_per_em; }
CGFloat ct_ascent(const struct ct_font *f) { return f->face->ascent * ct_scale(f); }
CGFloat ct_descent(const struct ct_font *f) { return -f->face->descent * ct_scale(f); }
CGFloat ct_leading(const struct ct_font *f) { return f->face->line_gap * ct_scale(f); }

static struct ct_font *d_CTFontCreateWithName(Ref name, CGFloat size, const CGAffineTransform *matrix) {
    char n[256];
    cstring(name, n, sizeof n);
    return ct_font_new(ct_face_for_name(n), size, matrix, name);
}
DX_FN(CTFontCreateWithName);

/* kCTFontUIFontUser... : all the UI fonts are the system font. */
static struct ct_font *d_CTFontCreateUIFontForLanguage(uint32_t type, CGFloat size, Ref language) {
    bool mono = type == 1 || type == 2;                 /* user fixed pitch */
    struct ttf *face = ct_face_for_name(mono ? "Menlo" : ".AppleSystemUIFont");
    return ct_font_new(face, size > 0 ? size : 13, NULL, konst(mono ? "Menlo-Regular" : ".AppleSystemUIFont"));
}
DX_FN(CTFontCreateUIFontForLanguage);

static struct ct_font *d_CTFontCreateCopyWithAttributes(const struct ct_font *f, CGFloat size,
                                                        const CGAffineTransform *matrix, Ref descriptor) {
    if (!f) return NULL;
    return ct_font_new(f->face, size > 0 ? size : f->size, matrix ? matrix : &f->matrix, f->requested_name);
}
DX_FN(CTFontCreateCopyWithAttributes);

enum { TRAIT_ITALIC = 1 << 0, TRAIT_BOLD = 1 << 1, TRAIT_MONO = 1 << 10 };

static struct ct_font *d_CTFontCreateCopyWithSymbolicTraits(const struct ct_font *f, CGFloat size,
                                                            const CGAffineTransform *matrix, uint32_t value,
                                                            uint32_t mask) {
    if (!f) return NULL;
    int weight = f->face->weight;
    bool italic = f->face->italic;
    if (mask & TRAIT_BOLD) weight = (value & TRAIT_BOLD) ? 700 : 400;
    if (mask & TRAIT_ITALIC) italic = (value & TRAIT_ITALIC) != 0;
    struct ttf *face = ct_face_variant(f->face, weight, italic);
    return ct_font_new(face, size > 0 ? size : f->size, matrix ? matrix : &f->matrix, NULL);
}
DX_FN(CTFontCreateCopyWithSymbolicTraits);

static uint32_t d_CTFontGetSymbolicTraits(const struct ct_font *f) {
    if (!f) return 0;
    return (f->face->italic ? TRAIT_ITALIC : 0) | (f->face->weight >= 600 ? TRAIT_BOLD : 0) |
           (f->face->monospace ? TRAIT_MONO : 0);
}
DX_FN(CTFontGetSymbolicTraits);

/* A font for the characters in range: the font itself, or a fallback that
 * covers the first character it lacks. */
static struct ct_font *d_CTFontCreateForString(const struct ct_font *f, Ref string, CFRange range) {
    if (!f) return NULL;
    CFIndex len = string ? CALL(CFIndex, CFStringGetLength, (Ref))(string) : 0;
    for (CFIndex i = range.location; i < range.location + range.length && i < len; i++) {
        uint16_t c;
        CALL(void, CFStringGetCharacters, (Ref, CFRange, uint16_t *))(string, (CFRange){i, 1}, &c);
        uint32_t cp = c;
        if (c >= 0xd800 && c < 0xdc00 && i + 1 < len) {
            uint16_t lo;
            CALL(void, CFStringGetCharacters, (Ref, CFRange, uint16_t *))(string, (CFRange){i + 1, 1}, &lo);
            cp = 0x10000 + ((uint32_t)(c - 0xd800) << 10) + (lo - 0xdc00);
        }
        struct ttf *face = ct_face_covering(f->face, cp);
        if (face != f->face) return ct_font_new(face, f->size, &f->matrix, NULL);
    }
    return cg_retain(f);
}
DX_FN(CTFontCreateForString);

static CGFloat d_CTFontGetSize(const struct ct_font *f) { return f ? f->size : 0; }
DX_FN(CTFontGetSize);
static CGAffineTransform d_CTFontGetMatrix(const struct ct_font *f) { return f ? f->matrix : CG_IDENTITY; }
DX_FN(CTFontGetMatrix);
static CGFloat d_CTFontGetAscent(const struct ct_font *f) { return f ? ct_ascent(f) : 0; }
DX_FN(CTFontGetAscent);
static CGFloat d_CTFontGetDescent(const struct ct_font *f) { return f ? ct_descent(f) : 0; }
DX_FN(CTFontGetDescent);
static CGFloat d_CTFontGetLeading(const struct ct_font *f) { return f ? ct_leading(f) : 0; }
DX_FN(CTFontGetLeading);
static unsigned d_CTFontGetUnitsPerEm(const struct ct_font *f) { return f ? (unsigned)f->face->units_per_em : 0; }
DX_FN(CTFontGetUnitsPerEm);
static CFIndex d_CTFontGetGlyphCount(const struct ct_font *f) { return f ? f->face->num_glyphs : 0; }
DX_FN(CTFontGetGlyphCount);
static CGFloat d_CTFontGetCapHeight(const struct ct_font *f) { return f ? f->face->cap_height * ct_scale(f) : 0; }
DX_FN(CTFontGetCapHeight);
static CGFloat d_CTFontGetXHeight(const struct ct_font *f) { return f ? f->face->x_height * ct_scale(f) : 0; }
DX_FN(CTFontGetXHeight);
static CGFloat d_CTFontGetUnderlinePosition(const struct ct_font *f) { return f ? f->face->underline_pos * ct_scale(f) : 0; }
DX_FN(CTFontGetUnderlinePosition);
static CGFloat d_CTFontGetUnderlineThickness(const struct ct_font *f) { return f ? f->face->underline_thickness * ct_scale(f) : 0; }
DX_FN(CTFontGetUnderlineThickness);
static CGFloat d_CTFontGetSlantAngle(const struct ct_font *f) { return f && f->face->italic ? -12 : 0; }
DX_FN(CTFontGetSlantAngle);
static CGRect d_CTFontGetBoundingBox(const struct ct_font *f) {
    if (!f) return (CGRect){{0, 0}, {0, 0}};
    CGFloat s = ct_scale(f);
    return (CGRect){{f->face->x_min * s, f->face->y_min * s},
                    {(f->face->x_max - f->face->x_min) * s, (f->face->y_max - f->face->y_min) * s}};
}
DX_FN(CTFontGetBoundingBox);

/* UTF-16 to glyphs; a surrogate pair maps to one glyph and a zero after it,
 * as CTFontGetGlyphsForCharacters does. */
static bool d_CTFontGetGlyphsForCharacters(const struct ct_font *f, const uint16_t *chars, uint16_t *glyphs, CFIndex n) {
    bool all = true;
    for (CFIndex i = 0; f && i < n; i++) {
        uint32_t c = chars[i];
        if (c >= 0xd800 && c < 0xdc00 && i + 1 < n && chars[i + 1] >= 0xdc00 && chars[i + 1] < 0xe000) {
            c = 0x10000 + ((c - 0xd800) << 10) + (chars[i + 1] - 0xdc00u);
            glyphs[i] = ttf_glyph(f->face, c);
            glyphs[i + 1] = 0;
            if (!glyphs[i]) all = false;
            i++;
            continue;
        }
        glyphs[i] = ttf_glyph(f->face, c);
        if (!glyphs[i]) all = false;
    }
    return f && all;
}
DX_FN(CTFontGetGlyphsForCharacters);

static double d_CTFontGetAdvancesForGlyphs(const struct ct_font *f, int orientation, const uint16_t *glyphs,
                                           CGSize *advances, CFIndex n) {
    double total = 0;
    for (CFIndex i = 0; f && i < n; i++) {
        CGFloat a = orientation == 2 ? f->size : ttf_advance(f->face, glyphs[i]) * ct_scale(f);  /* vertical: 1 em */
        if (advances) advances[i] = orientation == 2 ? (CGSize){0, a} : (CGSize){a, 0};
        total += a;
    }
    return total;
}
DX_FN(CTFontGetAdvancesForGlyphs);

static CGRect d_CTFontGetBoundingRectsForGlyphs(const struct ct_font *f, int orientation, const uint16_t *glyphs,
                                                CGRect *rects, CFIndex n) {
    CGFloat x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
    for (CFIndex i = 0; f && i < n; i++) {
        int b[4];
        CGRect r = {{0, 0}, {0, 0}};
        if (ttf_glyph_box(f->face, glyphs[i], b)) {
            CGFloat s = ct_scale(f);
            r = (CGRect){{b[0] * s, b[1] * s}, {(b[2] - b[0]) * s, (b[3] - b[1]) * s}};
            x0 = fmin(x0, r.origin.x); y0 = fmin(y0, r.origin.y);
            x1 = fmax(x1, r.origin.x + r.size.width); y1 = fmax(y1, r.origin.y + r.size.height);
        }
        if (rects) rects[i] = r;
    }
    if (x0 > x1) return (CGRect){{0, 0}, {0, 0}};
    return (CGRect){{x0, y0}, {x1 - x0, y1 - y0}};
}
DX_FN(CTFontGetBoundingRectsForGlyphs);

/* A glyph's outline in points (y up), through matrix when given. */
static struct cg_path *d_CTFontCreatePathForGlyph(const struct ct_font *f, uint16_t glyph, const CGAffineTransform *matrix) {
    if (!f) return NULL;
    CGFloat s = ct_scale(f);
    CGAffineTransform t = cg_concat((CGAffineTransform){s, 0, 0, s, 0, 0}, f->matrix);
    if (matrix) t = cg_concat(t, *matrix);
    struct cg_path *p = cg_path_new();
    if (p) ttf_outline(f->face, glyph, &t, p);
    return p;
}
DX_FN(CTFontCreatePathForGlyph);

/* Draw glyphs at positions (in text space) with the context's text matrix
 * and fill color. */
static void d_CTFontDrawGlyphs(const struct ct_font *f, const uint16_t *glyphs, const CGPoint *positions, size_t n,
                               void *ctx) {
    if (!f || !ctx || !glyphs) return;
    CGAffineTransform tm = CALL(CGAffineTransform, CGContextGetTextMatrix, (void *))(ctx);
    struct cg_path *p = cg_path_new();
    if (!p) return;
    CGFloat s = ct_scale(f);
    for (size_t i = 0; i < n; i++) {
        CGPoint at = positions ? positions[i] : (CGPoint){0, 0};
        CGAffineTransform g = cg_concat(cg_concat((CGAffineTransform){s, 0, 0, s, 0, 0}, f->matrix),
                                        (CGAffineTransform){1, 0, 0, 1, at.x, at.y});
        g = cg_concat(g, tm);
        ttf_outline(f->face, glyphs[i], &g, p);
    }
    CALL(void, CGContextAddPath, (void *, Ref))(ctx, p);
    CALL(void, CGContextFillPath, (void *))(ctx);
    cg_release(p);
}
DX_FN(CTFontDrawGlyphs);

/* ---- names and attributes ------------------------------------------------------------- */

static Ref d_CTFontCopyPostScriptName(const struct ct_font *f) {
    return f ? ct_cfstring(f->face->postscript[0] ? f->face->postscript : f->face->full) : NULL;
}
DX_FN(CTFontCopyPostScriptName);
static Ref d_CTFontCopyFamilyName(const struct ct_font *f) { return f ? ct_cfstring(f->face->family) : NULL; }
DX_FN(CTFontCopyFamilyName);
static Ref d_CTFontCopyFullName(const struct ct_font *f) { return f ? ct_cfstring(f->face->full) : NULL; }
DX_FN(CTFontCopyFullName);
static Ref d_CTFontCopyDisplayName(const struct ct_font *f) { return f ? ct_cfstring(f->face->full) : NULL; }
DX_FN(CTFontCopyDisplayName);

static Ref d_CTFontCopyName(const struct ct_font *f, Ref key) {
    if (!f || !key) return NULL;
    if (d_CFEqual(key, d_kCTFontFamilyNameKey)) return ct_cfstring(f->face->family);
    if (d_CFEqual(key, d_kCTFontSubFamilyNameKey) || d_CFEqual(key, d_kCTFontStyleNameKey)) return ct_cfstring(f->face->style);
    if (d_CFEqual(key, d_kCTFontFullNameKey) || d_CFEqual(key, d_kCTFontUniqueNameKey)) return ct_cfstring(f->face->full);
    if (d_CFEqual(key, d_kCTFontPostScriptNameKey)) return d_CTFontCopyPostScriptName(f);
    return NULL;
}
DX_FN(CTFontCopyName);

static Ref number(double v) {
    return CALL(Ref, CFNumberCreate, (Ref, CFIndex, const void *))(NULL, 13 /* kCFNumberDoubleType */, &v);
}

static Ref make_dict(const void **keys, const void **values, CFIndex n) {
    return CALL(Ref, CFDictionaryCreate, (Ref, const void **, const void **, CFIndex, const void *, const void *))(
        NULL, keys, values, n, dx_registry_lookup("_kCFTypeDictionaryKeyCallBacks"),
        dx_registry_lookup("_kCFTypeDictionaryValueCallBacks"));
}

static Ref make_array(const void **values, CFIndex n) {
    return CALL(Ref, CFArrayCreate, (Ref, const void **, CFIndex, const void *))(
        NULL, values, n, dx_registry_lookup("_kCFTypeArrayCallBacks"));
}

/* kCTFontWeightTrait is -1..1, 0 regular: usWeightClass mapped piecewise. */
static double weight_trait(int w) {
    static const struct { int w; double t; } k[] = {{100, -0.8}, {200, -0.6}, {300, -0.4}, {400, 0},
                                                     {500, 0.23}, {600, 0.3}, {700, 0.4}, {800, 0.56}, {900, 0.62}};
    if (w <= 100) return -0.8;
    for (int i = 1; i < 9; i++)
        if (w <= k[i].w) return k[i - 1].t + (k[i].t - k[i - 1].t) * (w - k[i - 1].w) / (k[i].w - k[i - 1].w);
    return 0.62;
}

static Ref d_CTFontCopyTraits(const struct ct_font *f) {
    if (!f) return NULL;
    Ref sym = number(d_CTFontGetSymbolicTraits(f)), weight = number(weight_trait(f->face->weight));
    Ref slant = number(f->face->italic ? -0.07 : 0), width = number(0);
    const void *keys[] = {d_kCTFontSymbolicTrait, d_kCTFontWeightTrait, d_kCTFontSlantTrait, d_kCTFontWidthTrait};
    const void *vals[] = {sym, weight, slant, width};
    Ref d = make_dict(keys, vals, 4);
    cg_release(sym); cg_release(weight); cg_release(slant); cg_release(width);
    return d;
}
DX_FN(CTFontCopyTraits);

static Ref url_for(const char *path) {
    Ref s = ct_cfstring(path);
    Ref url = CALL(Ref, CFURLCreateWithFileSystemPath, (Ref, Ref, CFIndex, Boolean))(NULL, s, 0, 0);
    cg_release(s);
    return url;
}

static Ref d_CTFontCopyAttribute(const struct ct_font *f, Ref key) {
    if (!f || !key) return NULL;
    if (d_CFEqual(key, d_kCTFontNameAttribute)) return d_CTFontCopyPostScriptName(f);
    if (d_CFEqual(key, d_kCTFontFamilyNameAttribute)) return ct_cfstring(f->face->family);
    if (d_CFEqual(key, d_kCTFontStyleNameAttribute)) return ct_cfstring(f->face->style);
    if (d_CFEqual(key, d_kCTFontDisplayNameAttribute)) return ct_cfstring(f->face->full);
    if (d_CFEqual(key, d_kCTFontSizeAttribute)) return number(f->size);
    if (d_CFEqual(key, d_kCTFontTraitsAttribute)) return d_CTFontCopyTraits(f);
    if (d_CFEqual(key, d_kCTFontURLAttribute)) return f->face->path ? url_for(f->face->path) : NULL;
    return NULL;
}
DX_FN(CTFontCopyAttribute);

static Ref d_CTFontCopyTable(const struct ct_font *f, uint32_t tag, uint32_t options) {
    uint32_t len = 0;
    const uint8_t *t = f ? ttf_table(f->face, tag, &len) : NULL;
    return t ? CALL(Ref, CFDataCreate, (Ref, const uint8_t *, CFIndex))(NULL, t, len) : NULL;
}
DX_FN(CTFontCopyTable);

/* No variable fonts here. */
static Ref d_CTFontCopyVariation(const struct ct_font *f) { return NULL; }
DX_FN(CTFontCopyVariation);
static Ref d_CTFontCopyVariationAxes(const struct ct_font *f) { return NULL; }
DX_FN(CTFontCopyVariationAxes);
CF_TYPE_ID(CTFont, CF_CT_FONT);

/* ---- descriptors -------------------------------------------------------------------- */

struct ct_desc {
    struct cf_object base;
    Ref attributes;                 /* CFDictionary */
};

static void desc_destroy(void *o) { cg_release(((struct ct_desc *)o)->attributes); }
static Boolean desc_equal(const void *a, const void *b) {
    return d_CFEqual(((const struct ct_desc *)a)->attributes, ((const struct ct_desc *)b)->attributes);
}
static const struct cf_ops desc_ops = {desc_destroy, desc_equal, NULL, NULL};

static struct ct_desc *desc_new(Ref attributes) {
    struct ct_desc *d = cf_alloc(NULL, sizeof *d, CF_CT_DESCRIPTOR, &desc_ops);
    if (!d) return NULL;
    d->attributes = attributes ? CALL(Ref, CFDictionaryCreateCopy, (Ref, Ref))(NULL, attributes) : make_dict(NULL, NULL, 0);
    return d;
}

static struct ct_desc *d_CTFontDescriptorCreateWithAttributes(Ref attributes) { return desc_new(attributes); }
DX_FN(CTFontDescriptorCreateWithAttributes);

static struct ct_desc *d_CTFontDescriptorCreateWithNameAndSize(Ref name, CGFloat size) {
    Ref sz = number(size);
    const void *keys[] = {d_kCTFontNameAttribute, d_kCTFontSizeAttribute}, *vals[] = {name, sz};
    Ref dict = make_dict(keys, vals, name ? 2 : 0);
    struct ct_desc *d = desc_new(dict);
    cg_release(dict);
    cg_release(sz);
    return d;
}
DX_FN(CTFontDescriptorCreateWithNameAndSize);

static Ref d_CTFontDescriptorCopyAttribute(const struct ct_desc *d, Ref key) {
    Ref v = d ? d_CFDictionaryGetValue(d->attributes, key) : NULL;
    return v ? cg_retain(v) : NULL;
}
DX_FN(CTFontDescriptorCopyAttribute);

static Ref d_CTFontDescriptorCopyAttributes(const struct ct_desc *d) { return d ? cg_retain(d->attributes) : NULL; }
DX_FN(CTFontDescriptorCopyAttributes);

static struct ct_desc *d_CTFontDescriptorCreateCopyWithAttributes(const struct ct_desc *d, Ref attributes) {
    if (!d) return NULL;
    Ref m = CALL(Ref, CFDictionaryCreateMutableCopy, (Ref, CFIndex, Ref))(NULL, 0, d->attributes);
    CFIndex n = attributes ? CALL(CFIndex, CFDictionaryGetCount, (Ref))(attributes) : 0;
    const void **k = malloc((size_t)(n ? n : 1) * sizeof *k), **v = malloc((size_t)(n ? n : 1) * sizeof *v);
    if (k && v && n) {
        CALL(void, CFDictionaryGetKeysAndValues, (Ref, const void **, const void **))(attributes, k, v);
        for (CFIndex i = 0; i < n; i++) CALL(void, CFDictionarySetValue, (Ref, Ref, Ref))(m, k[i], v[i]);
    }
    free(k);
    free(v);
    struct ct_desc *r = desc_new(m);
    cg_release(m);
    return r;
}
DX_FN(CTFontDescriptorCreateCopyWithAttributes);

/* The descriptors that match: here, the descriptor itself (every name
 * resolves to some installed face). */
static Ref d_CTFontDescriptorCreateMatchingFontDescriptors(const struct ct_desc *d, Ref mandatory) {
    if (!d) return NULL;
    const void *one[] = {d};
    return make_array(one, 1);
}
DX_FN(CTFontDescriptorCreateMatchingFontDescriptors);

static struct ct_desc *d_CTFontDescriptorCreateMatchingFontDescriptor(const struct ct_desc *d, Ref mandatory) {
    return d ? cg_retain(d) : NULL;
}
DX_FN(CTFontDescriptorCreateMatchingFontDescriptor);
CF_TYPE_ID(CTFontDescriptor, CF_CT_DESCRIPTOR);

static double number_value(Ref n, double fallback) {
    double v = fallback;
    if (n) CALL(Boolean, CFNumberGetValue, (Ref, CFIndex, void *))(n, 13, &v);
    return v;
}

static struct ct_font *d_CTFontCreateWithFontDescriptor(const struct ct_desc *d, CGFloat size, const CGAffineTransform *m) {
    char name[256] = "";
    Ref nm = d ? d_CFDictionaryGetValue(d->attributes, d_kCTFontNameAttribute) : NULL;
    if (!nm && d) nm = d_CFDictionaryGetValue(d->attributes, d_kCTFontFamilyNameAttribute);
    cstring(nm, name, sizeof name);
    struct ttf *face = NULL;
    Ref url = d ? d_CFDictionaryGetValue(d->attributes, d_kCTFontURLAttribute) : NULL;
    if (url) {
        char path[1024];
        if (CALL(Boolean, CFURLGetFileSystemRepresentation, (Ref, Boolean, uint8_t *, CFIndex))(url, 1, (uint8_t *)path, sizeof path))
            face = ct_register_file(path);
    }
    if (!face) face = ct_face_for_name(name);
    /* Traits in the descriptor pick a weight or slant of the family. */
    Ref traits = d ? d_CFDictionaryGetValue(d->attributes, d_kCTFontTraitsAttribute) : NULL;
    if (traits && face) {
        uint32_t sym = (uint32_t)number_value(d_CFDictionaryGetValue(traits, d_kCTFontSymbolicTrait), 0);
        Ref wt = d_CFDictionaryGetValue(traits, d_kCTFontWeightTrait);
        int weight = face->weight;
        if (wt) {
            double t = number_value(wt, 0);
            weight = t >= 0.56 ? 800 : t >= 0.4 ? 700 : t >= 0.3 ? 600 : t >= 0.2 ? 500 : t > -0.3 ? 400 : t > -0.5 ? 300 : 200;
        } else if (sym & TRAIT_BOLD) weight = 700;
        face = ct_face_variant(face, weight, (sym & TRAIT_ITALIC) != 0 || face->italic);
    }
    if (size <= 0 && d) size = number_value(d_CFDictionaryGetValue(d->attributes, d_kCTFontSizeAttribute), 12);
    return ct_font_new(face, size, m, nm);
}
DX_FN(CTFontCreateWithFontDescriptor);

static struct ct_desc *d_CTFontCopyFontDescriptor(const struct ct_font *f) {
    if (!f) return NULL;
    Ref name = d_CTFontCopyPostScriptName(f), family = ct_cfstring(f->face->family), size = number(f->size);
    const void *keys[] = {d_kCTFontNameAttribute, d_kCTFontFamilyNameAttribute, d_kCTFontSizeAttribute};
    const void *vals[] = {name, family, size};
    Ref dict = make_dict(keys, vals, 3);
    struct ct_desc *d = desc_new(dict);
    cg_release(dict); cg_release(name); cg_release(family); cg_release(size);
    return d;
}
DX_FN(CTFontCopyFontDescriptor);

/* Fallback fonts for any language: the families fonts.c falls back on. */
static Ref d_CTFontCopyDefaultCascadeListForLanguages(const struct ct_font *f, Ref languages) {
    static const char *const names[] = {"DejaVu Sans", "Noto Sans", "FreeSans", "Droid Sans Fallback"};
    const void *descs[4];
    CFIndex n = 0;
    for (int i = 0; i < 4; i++) {
        Ref s = ct_cfstring(names[i]);
        const void *k[] = {d_kCTFontFamilyNameAttribute}, *v[] = {s};
        Ref dict = make_dict(k, v, 1);
        descs[n++] = desc_new(dict);
        cg_release(dict);
        cg_release(s);
    }
    Ref a = make_array(descs, n);
    for (CFIndex i = 0; i < n; i++) cg_release(descs[i]);
    return a;
}
DX_FN(CTFontCopyDefaultCascadeListForLanguages);

/* ---- collections and the font manager ----------------------------------------------- */

struct ct_collection {
    struct cf_object base;
    Ref descriptors;                /* CFArray */
};
static void collection_destroy(void *o) { cg_release(((struct ct_collection *)o)->descriptors); }
static const struct cf_ops collection_ops = {collection_destroy, NULL, NULL, NULL};

static struct ct_collection *d_CTFontCollectionCreateWithFontDescriptors(Ref descriptors, Ref options) {
    struct ct_collection *c = cf_alloc(NULL, sizeof *c, CF_CT_COLLECTION, &collection_ops);
    if (!c) return NULL;
    c->descriptors = descriptors ? cg_retain(descriptors) : make_array(NULL, 0);
    return c;
}
DX_FN(CTFontCollectionCreateWithFontDescriptors);

static Ref d_CTFontCollectionCreateMatchingFontDescriptors(const struct ct_collection *c) {
    return c ? cg_retain(c->descriptors) : NULL;
}
DX_FN(CTFontCollectionCreateMatchingFontDescriptors);
CF_TYPE_ID(CTFontCollection, CF_CT_COLLECTION);

/* The faces in a font file (the target app ships one in its bundle). */
static Ref d_CTFontManagerCreateFontDescriptorsFromURL(Ref url) {
    char path[1024];
    if (!url || !CALL(Boolean, CFURLGetFileSystemRepresentation, (Ref, Boolean, uint8_t *, CFIndex))(url, 1, (uint8_t *)path, sizeof path))
        return NULL;
    struct ttf *face = ct_register_file(path);
    if (!face) return NULL;
    Ref name = ct_cfstring(face->postscript[0] ? face->postscript : face->full), family = ct_cfstring(face->family);
    const void *keys[] = {d_kCTFontNameAttribute, d_kCTFontFamilyNameAttribute, d_kCTFontURLAttribute};
    const void *vals[] = {name, family, url};
    Ref dict = make_dict(keys, vals, 3);
    struct ct_desc *d = desc_new(dict);
    const void *one[] = {d};
    Ref a = make_array(one, 1);
    cg_release(d); cg_release(dict); cg_release(name); cg_release(family);
    return a;
}
DX_FN(CTFontManagerCreateFontDescriptorsFromURL);

static bool d_CTFontManagerRegisterFontsForURL(Ref url, uint32_t scope, Ref *error) {
    Ref a = d_CTFontManagerCreateFontDescriptorsFromURL(url);
    if (a) cg_release(a);
    return a != NULL;
}
DX_FN(CTFontManagerRegisterFontsForURL);

/* ---- values from attributed strings ------------------------------------------------- */

static void *msg(void *obj, const char *sel) {
    void *(*send)(void *, void *) = dx_registry_lookup("_objc_msgSend");
    void *(*reg)(const char *) = dx_registry_lookup("_sel_registerName");
    return send(obj, reg(sel));
}

static bool responds(void *obj, const char *sel) {
    bool (*send)(void *, void *, void *) = dx_registry_lookup("_objc_msgSend");
    void *(*reg)(const char *) = dx_registry_lookup("_sel_registerName");
    return send(obj, reg("respondsToSelector:"), reg(sel));
}

struct ct_font *ct_font_from_value(Ref v) {
    if (!v) return NULL;
    if (cf_is_cf(v)) return ((const struct cf_object *)v)->type == CF_CT_FONT ? cg_retain(v) : NULL;
    /* An NSFont: by name and size. */
    if (!responds((void *)v, "fontName") || !responds((void *)v, "pointSize")) return NULL;
    Ref name = msg((void *)v, "fontName");
    double (*size_of)(void *, void *) = dx_registry_lookup("_objc_msgSend");
    void *(*reg)(const char *) = dx_registry_lookup("_sel_registerName");
    CGFloat size = size_of((void *)v, reg("pointSize"));
    return d_CTFontCreateWithName(name, size, NULL);
}

Ref ct_color_from_value(Ref v) {
    if (!v) return NULL;
    if (cf_is_cf(v)) return ((const struct cf_object *)v)->type == CF_CG_COLOR ? v : NULL;
    return responds((void *)v, "CGColor") ? msg((void *)v, "CGColor") : NULL;
}
