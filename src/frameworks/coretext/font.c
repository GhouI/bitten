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

static int ct_debug = -1;
#define CT_TRACE(...) do { if (ct_debug < 0) ct_debug = getenv("BITTEN_CT_DEBUG") != NULL; \
                           if (ct_debug) fprintf(stderr, "coretext: " __VA_ARGS__); } while (0)
static struct ct_font *d_CTFontCreateWithName(Ref name, CGFloat size, const CGAffineTransform *matrix) {
    char n[256];
    cstring(name, n, sizeof n);
    CT_TRACE("CTFontCreateWithName %s -> %s\n", n, ct_face_for_name(n) ? ct_face_for_name(n)->postscript : "(none)");
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

/* Apple's own fonts are served by stand-ins (fonts.c); a font asked for by
 * one of their names reports that font's names, as on a Mac. */
static const struct { const char *prefix, *family, *ps; } apple_fonts[] = {
    {".AppleSystemUIFontMonospaced", ".AppleSystemUIFontMonospaced", ".SFNSMono"},
    {".AppleSystemUIFont", ".AppleSystemUIFont", ".SFNS"},
    {".SFNSMono", ".AppleSystemUIFontMonospaced", ".SFNSMono"},
    {".SFNS", ".AppleSystemUIFont", ".SFNS"},
    {"SFMono", "SF Mono", "SFMono"}, {"SF Mono", "SF Mono", "SFMono"},
    {"SFPro", "SF Pro", "SFPro"}, {"SF Pro", "SF Pro", "SFPro"},
    {"Menlo", "Menlo", "Menlo"}, {"Monaco", "Monaco", "Monaco"},
    {"HelveticaNeue", "Helvetica Neue", "HelveticaNeue"}, {"Helvetica Neue", "Helvetica Neue", "HelveticaNeue"},
    {"Helvetica", "Helvetica", "Helvetica"}, {"Courier New", "Courier New", "CourierNewPSMT"},
    {"Courier", "Courier", "Courier"}, {"Times New Roman", "Times New Roman", "TimesNewRomanPSMT"},
    {"Times", "Times", "Times"}, {"Lucida Grande", "Lucida Grande", "LucidaGrande"},
    {"LucidaGrande", "Lucida Grande", "LucidaGrande"}, {"Geneva", "Geneva", "Geneva"},
    {"Andale Mono", "Andale Mono", "AndaleMono"},
};
static int apple_index(const char *name) {
    for (size_t i = 0; i < sizeof apple_fonts / sizeof *apple_fonts; i++)
        if (!strncasecmp(name, apple_fonts[i].prefix, strlen(apple_fonts[i].prefix))) return (int)i;
    return -1;
}
/* The names a font reports: its face's, or the Apple font's it stands in
 * for. Returns 1 when standing in. */
/* A style in Apple's words: Book, Roman and Normal are Regular, Oblique is
 * Italic ("Bold Oblique" -> "Bold Italic"). */
static void apple_style_words(const char *style, char *words, size_t n) {
    if (!style || !style[0] || !strcasecmp(style, "Book") || !strcasecmp(style, "Roman") || !strcasecmp(style, "Normal"))
        style = "Regular";
    size_t w = 0;
    for (const char *c = style; *c && w + 7 < n;) {
        if (!strncasecmp(c, "Oblique", 7)) { memcpy(words + w, "Italic", 6); w += 6; c += 7; }
        else words[w++] = *c++;
    }
    words[w] = 0;
}
static int reported_names(const struct ct_font *f, char *family, char *ps, char *full, size_t n);
/* The style a font reports: its face's, or in Apple's words when it stands
 * in for an Apple font (as its descriptors say). */
static Ref reported_style(const struct ct_font *f) {
    char fam[256], ps[256], full[256], words[64];
    if (!reported_names(f, fam, ps, full, sizeof fam)) return ct_cfstring(f->face->style);
    apple_style_words(f->face->style, words, sizeof words);
    return ct_cfstring(words);
}
static int reported_names(const struct ct_font *f, char *family, char *ps, char *full, size_t n) {
    char req[256] = "";
    if (f->requested_name) cstring(f->requested_name, req, sizeof req);
    int a = req[0] ? apple_index(req) : -1;
    if (a < 0 || !strcasecmp(f->face->family, apple_fonts[a].family)) {
        snprintf(family, n, "%s", f->face->family);
        snprintf(ps, n, "%s", f->face->postscript[0] ? f->face->postscript : f->face->full);
        snprintf(full, n, "%s", f->face->full);
        return 0;
    }
    /* Apple's style words; the PostScript name drops the spaces (Menlo-BoldItalic) */
    char words[64], st[64];
    apple_style_words(f->face->style, words, sizeof words);
    size_t k = 0;
    for (const char *c = words; *c && k + 1 < sizeof st; c++)
        if (*c != ' ') st[k++] = *c;
    st[k] = 0;
    snprintf(family, n, "%s", apple_fonts[a].family);
    snprintf(ps, n, "%s-%s", apple_fonts[a].ps, st);
    snprintf(full, n, "%s %s", apple_fonts[a].family, words);
    return 1;
}
static Ref d_CTFontCopyPostScriptName(const struct ct_font *f) {
    if (!f) return NULL;
    char fam[256], ps[256], full[256];
    reported_names(f, fam, ps, full, sizeof fam);
    return ct_cfstring(ps);
}
DX_FN(CTFontCopyPostScriptName);
static Ref d_CTFontCopyFamilyName(const struct ct_font *f) {
    if (!f) return NULL;
    char fam[256], ps[256], full[256];
    reported_names(f, fam, ps, full, sizeof fam);
    return ct_cfstring(fam);
}
DX_FN(CTFontCopyFamilyName);
static Ref d_CTFontCopyFullName(const struct ct_font *f) {
    if (!f) return NULL;
    char fam[256], ps[256], full[256];
    reported_names(f, fam, ps, full, sizeof fam);
    return ct_cfstring(full);
}
DX_FN(CTFontCopyFullName);
static Ref d_CTFontCopyDisplayName(const struct ct_font *f) { return d_CTFontCopyFullName(f); }
DX_FN(CTFontCopyDisplayName);

static Ref d_CTFontCopyName(const struct ct_font *f, Ref key) {
    if (!f || !key) return NULL;
    if (d_CFEqual(key, d_kCTFontFamilyNameKey)) return d_CTFontCopyFamilyName(f);
    if (d_CFEqual(key, d_kCTFontSubFamilyNameKey) || d_CFEqual(key, d_kCTFontStyleNameKey)) return reported_style(f);
    if (d_CFEqual(key, d_kCTFontFullNameKey) || d_CFEqual(key, d_kCTFontUniqueNameKey)) return d_CTFontCopyFullName(f);
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
    Ref slant = number(f->face->italic ? 0.07 : 0), width = number(0);  /* clockwise is positive */
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
    if (d_CFEqual(key, d_kCTFontStyleNameAttribute)) return reported_style(f);
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

/* ---- matching against the installed faces ---- */

static double number_value(Ref n, double fallback) {
    double v = fallback;
    if (n) CALL(Boolean, CFNumberGetValue, (Ref, CFIndex, void *))(n, 13, &v);
    return v;
}

static struct ct_font *d_CTFontCreateWithFontDescriptor(const struct ct_desc *d, CGFloat size, const CGAffineTransform *m);
static Ref d_CTFontCopyTraits(const struct ct_font *f);

/* A descriptor for an installed face: its names, style, traits and file. */
static struct ct_desc *face_desc(struct ttf *face, Ref url) {
    Ref own = NULL;
    if (!url && face->path)
    {
        Ref path = ct_cfstring(face->path);
        url = own = CALL(Ref, CFURLCreateWithFileSystemPath, (Ref, Ref, CFIndex, Boolean))(NULL, path, 0, 0);
        cg_release(path);
    }
    Ref name = ct_cfstring(face->postscript[0] ? face->postscript : face->full), family = ct_cfstring(face->family);
    Ref style = ct_cfstring(face->style[0] ? face->style : "Regular"), full = ct_cfstring(face->full[0] ? face->full : face->family);
    /* the face's traits, as a font made from it reports them */
    struct ct_font *f = ct_font_new(face, 12, NULL, NULL);
    Ref traits = f ? d_CTFontCopyTraits(f) : NULL;
    const void *keys[6] = {d_kCTFontNameAttribute, d_kCTFontFamilyNameAttribute, d_kCTFontStyleNameAttribute,
                           d_kCTFontDisplayNameAttribute};
    const void *vals[6] = {name, family, style, full};
    CFIndex n = 4;
    if (url) { keys[n] = d_kCTFontURLAttribute; vals[n++] = url; }
    if (traits) { keys[n] = d_kCTFontTraitsAttribute; vals[n++] = traits; }
    Ref dict = make_dict(keys, vals, n);
    struct ct_desc *d = desc_new(dict);
    cg_release(dict); cg_release(name); cg_release(family); cg_release(style); cg_release(full);
    if (f) cg_release(f);
    if (traits) cg_release(traits);
    if (own) cg_release(own);
    return d;
}

static bool same(Ref s, const char *v) {
    char a[256] = "";
    cstring(s, a, sizeof a);
    return !strcasecmp(a, v);
}
/* Whether an installed face has every attribute the descriptor gives that
 * fonts can be told apart by: name (PostScript or full), family, style,
 * symbolic traits (bold, italic, monospace) and file. Other attributes
 * (size, matrix, features...) do not choose faces. */
static bool face_matches(const struct ttf *face, const struct ct_desc *d) {
    Ref v;
    if ((v = d_CFDictionaryGetValue(d->attributes, d_kCTFontNameAttribute)) &&
        !same(v, face->postscript) && !same(v, face->full))
        return false;
    if ((v = d_CFDictionaryGetValue(d->attributes, d_kCTFontFamilyNameAttribute)) && !same(v, face->family)) return false;
    if ((v = d_CFDictionaryGetValue(d->attributes, d_kCTFontStyleNameAttribute)) &&
        !same(v, face->style[0] ? face->style : "Regular"))
        return false;
    if ((v = d_CFDictionaryGetValue(d->attributes, d_kCTFontTraitsAttribute))) {
        uint32_t sym = (uint32_t)number_value(d_CFDictionaryGetValue(v, d_kCTFontSymbolicTrait), 0);
        if ((sym & TRAIT_MONO) && !face->monospace) return false;
        if ((sym & TRAIT_BOLD) && face->weight < 600) return false;
        if ((sym & TRAIT_ITALIC) && !face->italic) return false;
    }
    if ((v = d_CFDictionaryGetValue(d->attributes, d_kCTFontURLAttribute))) {
        char path[1024];
        if (!CALL(Boolean, CFURLGetFileSystemRepresentation, (Ref, Boolean, uint8_t *, CFIndex))(v, 1, (uint8_t *)path, sizeof path) ||
            !face->path || strcmp(path, face->path))
            return false;
    }
    return true;
}
/* families alphabetically, then lighter before bolder, upright before italic */
static int face_order(const void *pa, const void *pb) {
    const struct ttf *a = *(struct ttf *const *)pa, *b = *(struct ttf *const *)pb;
    int c = strcasecmp(a->family, b->family);
    if (c) return c;
    if (a->weight != b->weight) return a->weight - b->weight;
    if (a->italic != b->italic) return a->italic - b->italic;
    return strcmp(a->postscript, b->postscript);
}
/* Descriptors for the installed faces matching any of `descs` (all faces
 * when there are none), sorted; each face once. */
static Ref matching_faces(const struct ct_desc *const *descs, CFIndex n) {
    int count = ct_face_count();
    struct ttf **hits = calloc((size_t)(count ? count : 1), sizeof *hits);
    int nhits = 0;
    for (int i = 0; i < count; i++) {
        struct ttf *face = ct_face_at(i);
        if (!face) continue;
        bool ok = n == 0;
        for (CFIndex k = 0; k < n && !ok; k++) ok = descs[k] && face_matches(face, descs[k]);
        if (ok) hits[nhits++] = face;
    }
    qsort(hits, (size_t)nhits, sizeof *hits, face_order);
    /* one face per PostScript name, as on a Mac (a font installed in two
     * font directories counts once) */
    int kept = 0;
    for (int i = 0; i < nhits; i++) {
        bool dup = false;
        for (int j = 0; j < kept && !dup; j++)
            dup = hits[i]->postscript[0] && !strcmp(hits[j]->postscript, hits[i]->postscript);
        if (!dup) hits[kept++] = hits[i];
    }
    nhits = kept;
    const void **out = calloc((size_t)(nhits ? nhits : 1), sizeof *out);
    for (int i = 0; i < nhits; i++) out[i] = face_desc(hits[i], NULL);
    Ref arr = make_array(out, nhits);
    for (int i = 0; i < nhits; i++) cg_release(out[i]);
    free(out);
    free(hits);
    return arr;
}

/* A stand-in face described as the Apple font it stands for: the Apple
 * names (Menlo-Bold, "Menlo Bold"), the face's style and traits. */
static struct ct_desc *stand_in_desc(struct ttf *face, Ref apple_name) {
    struct ct_font *f = ct_font_new(face, 12, NULL, apple_name);
    if (!f) return NULL;
    Ref ps = d_CTFontCopyPostScriptName(f), fam = d_CTFontCopyFamilyName(f), full = d_CTFontCopyFullName(f);
    Ref style = reported_style(f), traits = d_CTFontCopyTraits(f);
    const void *keys[] = {d_kCTFontNameAttribute, d_kCTFontFamilyNameAttribute, d_kCTFontStyleNameAttribute,
                          d_kCTFontDisplayNameAttribute, d_kCTFontTraitsAttribute};
    const void *vals[] = {ps, fam, style, full, traits};
    Ref dict = make_dict(keys, vals, traits ? 5 : 4);
    struct ct_desc *r = desc_new(dict);
    cg_release(dict); cg_release(ps); cg_release(fam); cg_release(full); cg_release(style);
    if (traits) cg_release(traits);
    cg_release(f);
    return r;
}

/* An Apple font asked for (fonts.c maps it to an open family): by name,
 * its stand-in face; by family, every face of the stand-in family, as a
 * Mac lists Menlo's Regular, Bold, Italic and Bold Italic. All under the
 * Apple font's names. */
static Ref apple_stand_in(const struct ct_desc *d) {
    char a[256] = "", b[256] = "";
    cstring(d_CFDictionaryGetValue(d->attributes, d_kCTFontNameAttribute), a, sizeof a);
    cstring(d_CFDictionaryGetValue(d->attributes, d_kCTFontFamilyNameAttribute), b, sizeof b);
    const char *want = a[0] ? a : b;
    if (!want[0] || apple_index(want) < 0) return NULL;
    struct ttf *base = ct_face_for_name(want);
    if (!base) return NULL;
    Ref apple = ct_cfstring(want);
    struct ttf **faces = NULL;
    int n = 0;
    if (a[0]) {
        /* a name: the face it picks (Menlo-Bold: the bold face) */
        struct ct_font *f = d_CTFontCreateWithFontDescriptor(d, 12, NULL);
        if (f) {
            faces = malloc(sizeof *faces);
            faces[n++] = f->face;
            cg_release(f);
        }
    } else {
        int count = ct_face_count();
        faces = calloc((size_t)(count ? count : 1), sizeof *faces);
        for (int i = 0; i < count; i++) {
            struct ttf *face = ct_face_at(i);
            if (!face || strcasecmp(face->family, base->family)) continue;
            bool dup = false;
            for (int j = 0; j < n && !dup; j++) dup = !strcmp(faces[j]->postscript, face->postscript);
            if (!dup) faces[n++] = face;
        }
        qsort(faces, (size_t)n, sizeof *faces, face_order);
    }
    const void **out = calloc((size_t)(n ? n : 1), sizeof *out);
    int k = 0;
    for (int i = 0; i < n; i++)
        if ((out[k] = stand_in_desc(faces[i], apple))) k++;
    Ref arr = k ? make_array(out, k) : NULL;
    for (int i = 0; i < k; i++) cg_release(out[i]);
    free(out);
    free(faces);
    cg_release(apple);
    return arr;
}

/* The installed faces a descriptor matches (a family gives all its faces;
 * an Apple font its stand-in, under the Apple names), or NULL when none. */
static Ref d_CTFontDescriptorCreateMatchingFontDescriptors(const struct ct_desc *d, Ref mandatory) {
    if (!d) return NULL;
    const struct ct_desc *one[] = {d};
    Ref arr = matching_faces(one, 1);
    CT_TRACE("matching -> %ld faces\n", (long)d_CFArrayGetCount(arr));
    if (d_CFArrayGetCount(arr) > 0) return arr;
    cg_release(arr);
    if (d_CFDictionaryGetValue(d->attributes, d_kCTFontURLAttribute)) {
        /* a file not registered yet: itself */
        const void *self[] = {d};
        return make_array(self, 1);
    }
    return apple_stand_in(d);
}
DX_FN(CTFontDescriptorCreateMatchingFontDescriptors);

static struct ct_desc *d_CTFontDescriptorCreateMatchingFontDescriptor(const struct ct_desc *d, Ref mandatory) {
    return d ? cg_retain(d) : NULL;
}
DX_FN(CTFontDescriptorCreateMatchingFontDescriptor);
CF_TYPE_ID(CTFontDescriptor, CF_CT_DESCRIPTOR);


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
    Ref name = d_CTFontCopyPostScriptName(f), family = d_CTFontCopyFamilyName(f), size = number(f->size);
    Ref style = reported_style(f);
    const void *keys[] = {d_kCTFontNameAttribute, d_kCTFontFamilyNameAttribute, d_kCTFontSizeAttribute,
                          d_kCTFontStyleNameAttribute};
    const void *vals[] = {name, family, size, style};
    Ref dict = make_dict(keys, vals, 4);
    struct ct_desc *d = desc_new(dict);
    cg_release(dict); cg_release(name); cg_release(family); cg_release(size); cg_release(style);
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

/* The installed faces matching any of the collection's descriptors (all
 * of them for an empty collection), plus the stand-ins for Apple fonts the
 * descriptors name; NULL when nothing matches. */
static Ref d_CTFontCollectionCreateMatchingFontDescriptors(const struct ct_collection *c) {
    if (!c) return NULL;
    CFIndex n = d_CFArrayGetCount(c->descriptors);
    const struct ct_desc **descs = calloc((size_t)(n ? n : 1), sizeof *descs);
    for (CFIndex i = 0; i < n; i++) descs[i] = d_CFArrayGetValueAtIndex(c->descriptors, i);
    Ref arr = matching_faces(descs, n);
    for (CFIndex i = 0; i < n; i++) {
        bool hit = false;
        for (int k = 0; k < ct_face_count() && !hit; k++) {
            struct ttf *face = ct_face_at(k);
            hit = face && face_matches(face, descs[i]);
        }
        Ref extra = hit ? NULL : apple_stand_in(descs[i]);
        if (extra) {
            Ref merged = CALL(Ref, CFArrayCreateMutableCopy, (Ref, CFIndex, Ref))(NULL, 0, arr);
            for (CFIndex k = 0; k < d_CFArrayGetCount(extra); k++)
                CALL(void, CFArrayAppendValue, (Ref, const void *))(merged, d_CFArrayGetValueAtIndex(extra, k));
            cg_release(arr);
            cg_release(extra);
            arr = merged;
        }
    }
    free(descs);
    if (!d_CFArrayGetCount(arr)) {
        cg_release(arr);
        return NULL;
    }
    return arr;
}
DX_FN(CTFontCollectionCreateMatchingFontDescriptors);

static struct ct_collection *d_CTFontCollectionCreateFromAvailableFonts(Ref options) {
    return d_CTFontCollectionCreateWithFontDescriptors(NULL, options);
}
DX_FN(CTFontCollectionCreateFromAvailableFonts);

/* Every installed family, or PostScript name, sorted, each once. */
static Ref available_names(bool families) {
    int count = ct_face_count();
    struct ttf **all = calloc((size_t)(count ? count : 1), sizeof *all);
    int n = 0;
    for (int i = 0; i < count; i++)
        if ((all[n] = ct_face_at(i))) n++;
    qsort(all, (size_t)n, sizeof *all, face_order);
    const void **names = calloc((size_t)(n ? n : 1), sizeof *names);
    int k = 0;
    for (int i = 0; i < n; i++) {
        const char *v = families ? all[i]->family : (all[i]->postscript[0] ? all[i]->postscript : all[i]->full);
        if (!v[0]) continue;
        bool dup = false;
        for (int j = 0; j < i && !dup; j++)
            dup = !strcmp(v, families ? all[j]->family : (all[j]->postscript[0] ? all[j]->postscript : all[j]->full));
        if (!dup) names[k++] = ct_cfstring(v);
    }
    Ref arr = make_array(names, k);
    for (int i = 0; i < k; i++) cg_release(names[i]);
    free(names);
    free(all);
    return arr;
}
static Ref d_CTFontManagerCopyAvailableFontFamilyNames(void) { return available_names(true); }
DX_FN(CTFontManagerCopyAvailableFontFamilyNames);
static Ref d_CTFontManagerCopyAvailablePostScriptNames(void) { return available_names(false); }
DX_FN(CTFontManagerCopyAvailablePostScriptNames);
CF_TYPE_ID(CTFontCollection, CF_CT_COLLECTION);

static struct ct_font *d_CTFontCreateWithFontDescriptor(const struct ct_desc *d, CGFloat size, const CGAffineTransform *m);

/* The faces in a font file (the target app ships one in its bundle). */
static Ref d_CTFontManagerCreateFontDescriptorsFromURL(Ref url) {
    char path[1024];
    if (!url || !CALL(Boolean, CFURLGetFileSystemRepresentation, (Ref, Boolean, uint8_t *, CFIndex))(url, 1, (uint8_t *)path, sizeof path))
        return NULL;
    struct ttf *face = ct_register_file(path);
    CT_TRACE("descriptors from %s -> %s", path, face ? face->family : "(none)");
    if (!face) return NULL;
    struct ct_desc *d = face_desc(face, url);
    const void *one[] = {d};
    Ref a = make_array(one, 1);
    cg_release(d);
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
