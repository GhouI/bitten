/* CoreText: CTLine and CTRun. A line lays an attributed string out on one
 * baseline: runs of equal font and color, each character mapped to a
 * glyph of the run's font (or of a fallback face that has it), advanced by
 * the glyph widths and any kern. No shaping beyond that: no ligatures, no
 * kerning tables, no bidirectional reordering. Drawing fills the glyph
 * outlines through CoreGraphics at the context's text position, through its
 * text matrix. */
#include <string.h>

#include "ct.h"

struct ct_run {
    struct cf_object base;
    struct ct_font *font;
    Ref attributes;                 /* the string's attributes (+ the font used) */
    Ref color;                      /* CGColor, or NULL for black */
    bool context_color;             /* kCTForegroundColorFromContextAttributeName */
    CFRange range;                  /* in the string */
    CFIndex count;
    uint16_t *glyphs;
    CGPoint *positions;             /* relative to the line origin */
    CGSize *advances;
    CFIndex *indices;               /* string index of each glyph */
    CGFloat width;
};

struct ct_line {
    struct cf_object base;
    Ref runs;                       /* CFArray of ct_run */
    CFRange range;
    CGFloat width, ascent, descent, leading;
};

static void run_destroy(void *o) {
    struct ct_run *r = o;
    cg_release(r->font);
    cg_release(r->attributes);
    cg_release(r->color);
    free(r->glyphs);
    free(r->positions);
    free(r->advances);
    free(r->indices);
}
static const struct cf_ops run_ops = {run_destroy, NULL, NULL, NULL};

static void line_destroy(void *o) { cg_release(((struct ct_line *)o)->runs); }
static const struct cf_ops line_ops = {line_destroy, NULL, NULL, NULL};

/* ---- reading attributed strings (CF or Objective-C) ------------------------------- */

struct source {
    Ref string;
    CFIndex length;
    Ref cf;                         /* a CFAttributedString, or NULL */
    void *objc;                     /* an NSAttributedString-like object */
};

static Ref attrs_at(const struct source *s, CFIndex i, CFRange *effective) {
    if (s->cf) return CALL(Ref, CFAttributedStringGetAttributes, (Ref, CFIndex, CFRange *))(s->cf, i, effective);
    void *(*send)(void *, void *, CFIndex, CFRange *) = CT_LOOKUP("_objc_msgSend");
    void *(*reg)(const char *) = CT_LOOKUP("_sel_registerName");
    return send(s->objc, reg("attributesAtIndex:effectiveRange:"), i, effective);
}

static bool open_source(Ref attributed, struct source *s) {
    memset(s, 0, sizeof *s);
    if (!attributed) return false;
    if (cf_is_cf(attributed) && ((const struct cf_object *)attributed)->type == CF_ATTRIBUTED_STRING) {
        s->cf = attributed;
        s->string = CALL(Ref, CFAttributedStringGetString, (Ref))(attributed);
    } else {
        void *(*send)(void *, void *) = CT_LOOKUP("_objc_msgSend");
        void *(*reg)(const char *) = CT_LOOKUP("_sel_registerName");
        s->objc = (void *)attributed;
        s->string = send(s->objc, reg("string"));
    }
    s->length = s->string ? CALL(CFIndex, CFStringGetLength, (Ref))(s->string) : 0;
    return s->string != NULL;
}

static Ref attr(Ref dict, Ref key) { return dict && key ? d_CFDictionaryGetValue(dict, key) : NULL; }

/* ---- layout ------------------------------------------------------------------------ */

static void grow(struct ct_run *r, CFIndex cap) {
    r->glyphs = realloc(r->glyphs, (size_t)cap * sizeof *r->glyphs);
    r->positions = realloc(r->positions, (size_t)cap * sizeof *r->positions);
    r->advances = realloc(r->advances, (size_t)cap * sizeof *r->advances);
    r->indices = realloc(r->indices, (size_t)cap * sizeof *r->indices);
}

static Ref with_font(Ref attributes, struct ct_font *font) {
    Ref m = attributes ? CALL(Ref, CFDictionaryCreateMutableCopy, (Ref, CFIndex, Ref))(NULL, 0, attributes)
                       : CALL(Ref, CFDictionaryCreateMutable, (Ref, CFIndex, const void *, const void *))(
                             NULL, 0, CT_LOOKUP("_kCFTypeDictionaryKeyCallBacks"),
                             CT_LOOKUP("_kCFTypeDictionaryValueCallBacks"));
    CALL(void, CFDictionarySetValue, (Ref, Ref, Ref))(m, d_kCTFontAttributeName, font);
    return m;
}

static struct ct_line *layout(Ref attributed) {
    struct source src;
    if (!open_source(attributed, &src)) return NULL;
    struct ct_line *line = cf_alloc(NULL, sizeof *line, CF_CT_LINE, &line_ops);
    if (!line) return NULL;
    line->range = (CFRange){0, src.length};
    uint16_t *chars = malloc((size_t)(src.length ? src.length : 1) * 2);
    if (!chars) { cg_release(line); return NULL; }
    if (src.length) CALL(void, CFStringGetCharacters, (Ref, CFRange, uint16_t *))(src.string, (CFRange){0, src.length}, chars);
    const void **runs = NULL;
    CFIndex nruns = 0, runcap = 0;
    CGFloat x = 0;
    struct ct_font *deflt = ct_default_font();
    for (CFIndex i = 0; i < src.length;) {
        CFRange eff = {i, 1};
        Ref attrs = attrs_at(&src, i, &eff);
        if (eff.length <= 0 || eff.location + eff.length <= i) eff = (CFRange){i, 1};
        CFIndex end = eff.location + eff.length;
        if (end > src.length) end = src.length;
        struct ct_font *font = ct_font_from_value(attr(attrs, d_kCTFontAttributeName));
        if (!font) font = cg_retain(deflt);
        if (!font) break;
        Ref color = ct_color_from_value(attr(attrs, d_kCTForegroundColorAttributeName));
        if (!color) color = ct_color_from_value(attr(attrs, ct_ns_color_attribute));
        bool from_context = attr(attrs, d_kCTForegroundColorFromContextAttributeName) != NULL;
        double kern = 0;
        Ref k = attr(attrs, d_kCTKernAttributeName);
        if (k && cf_is_cf(k)) CALL(Boolean, CFNumberGetValue, (Ref, CFIndex, void *))(k, 13, &kern);
        /* Within the attribute run, split where the face changes (fallbacks). */
        while (i < end) {
            struct ct_run *r = cf_alloc(NULL, sizeof *r, CF_CT_RUN, &run_ops);
            if (!r) break;
            r->color = color ? cg_retain(color) : NULL;
            r->context_color = from_context;
            r->range.location = i;
            CFIndex cap = 16;
            grow(r, cap);
            struct ttf *face = NULL;
            CFIndex start = i;
            while (i < end) {
                uint32_t cp = chars[i];
                int units = 1;
                if (cp >= 0xd800 && cp < 0xdc00 && i + 1 < end && chars[i + 1] >= 0xdc00 && chars[i + 1] < 0xe000) {
                    cp = 0x10000 + ((cp - 0xd800) << 10) + (chars[i + 1] - 0xdc00u);
                    units = 2;
                }
                struct ttf *want = (cp == '\n' || cp == '\r' || cp == '\t') ? font->face : ct_face_covering(font->face, cp);
                if (!face) face = want;
                else if (want != face) break;
                if (r->count == cap) { cap *= 2; grow(r, cap); }
                uint16_t g = ttf_glyph(face, cp);
                CGFloat adv = (cp == '\n' || cp == '\r') ? 0 : ttf_advance(face, g) * font->size / face->units_per_em + kern;
                r->glyphs[r->count] = g;
                r->positions[r->count] = (CGPoint){x, 0};
                r->advances[r->count] = (CGSize){adv, 0};
                r->indices[r->count] = i;
                r->count++;
                r->width += adv;
                x += adv;
                i += units;
            }
            r->range.length = i - start;
            r->font = face == font->face ? cg_retain(font) : ct_font_new(face, font->size, &font->matrix, NULL);
            r->attributes = with_font(attrs, r->font);
            if (ct_ascent(r->font) > line->ascent) line->ascent = ct_ascent(r->font);
            if (ct_descent(r->font) > line->descent) line->descent = ct_descent(r->font);
            if (ct_leading(r->font) > line->leading) line->leading = ct_leading(r->font);
            if (nruns == runcap) { runcap = runcap ? runcap * 2 : 4; runs = realloc(runs, (size_t)runcap * sizeof *runs); }
            runs[nruns++] = r;
        }
        cg_release(font);
    }
    if (!nruns && deflt) {                          /* empty line: metrics of the default font */
        line->ascent = ct_ascent(deflt);
        line->descent = ct_descent(deflt);
        line->leading = ct_leading(deflt);
    }
    line->width = x;
    line->runs = CALL(Ref, CFArrayCreate, (Ref, const void **, CFIndex, const void *))(
        NULL, runs, nruns, CT_LOOKUP("_kCFTypeArrayCallBacks"));
    for (CFIndex k = 0; k < nruns; k++) cg_release(runs[k]);
    free(runs);
    free(chars);
    return line;
}

static struct ct_line *d_CTLineCreateWithAttributedString(Ref attributed) { return layout(attributed); }
DX_FN(CTLineCreateWithAttributedString);
CF_TYPE_ID(CTLine, CF_CT_LINE);
CF_TYPE_ID(CTRun, CF_CT_RUN);

static CFIndex run_count(const struct ct_line *l) { return CALL(CFIndex, CFArrayGetCount, (Ref))(l->runs); }
static struct ct_run *run_at(const struct ct_line *l, CFIndex i) {
    return (struct ct_run *)CALL(Ref, CFArrayGetValueAtIndex, (Ref, CFIndex))(l->runs, i);
}

static Ref d_CTLineGetGlyphRuns(const struct ct_line *l) { return l ? l->runs : NULL; }
DX_FN(CTLineGetGlyphRuns);
static CFRange d_CTLineGetStringRange(const struct ct_line *l) { return l ? l->range : (CFRange){0, 0}; }
DX_FN(CTLineGetStringRange);
static CFIndex d_CTLineGetGlyphCount(const struct ct_line *l) {
    CFIndex n = 0;
    for (CFIndex i = 0; l && i < run_count(l); i++) n += run_at(l, i)->count;
    return n;
}
DX_FN(CTLineGetGlyphCount);

static double d_CTLineGetTypographicBounds(const struct ct_line *l, CGFloat *ascent, CGFloat *descent, CGFloat *leading) {
    if (ascent) *ascent = l ? l->ascent : 0;
    if (descent) *descent = l ? l->descent : 0;
    if (leading) *leading = l ? l->leading : 0;
    return l ? l->width : 0;
}
DX_FN(CTLineGetTypographicBounds);

static double d_CTLineGetTrailingWhitespaceWidth(const struct ct_line *l) { return 0; }
DX_FN(CTLineGetTrailingWhitespaceWidth);

/* The union of the glyph boxes, relative to the line origin. */
static CGRect glyph_bounds(const struct ct_line *l) {
    CGFloat x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
    for (CFIndex i = 0; i < run_count(l); i++) {
        struct ct_run *r = run_at(l, i);
        CGFloat s = ct_scale(r->font);
        for (CFIndex k = 0; k < r->count; k++) {
            int b[4];
            if (!ttf_glyph_box(r->font->face, r->glyphs[k], b)) continue;
            x0 = fmin(x0, r->positions[k].x + b[0] * s);
            x1 = fmax(x1, r->positions[k].x + b[2] * s);
            y0 = fmin(y0, b[1] * s);
            y1 = fmax(y1, b[3] * s);
        }
    }
    if (x0 > x1) return (CGRect){{0, 0}, {0, 0}};
    return (CGRect){{x0, y0}, {x1 - x0, y1 - y0}};
}

enum { BOUNDS_EXCLUDE_LEADING = 1, BOUNDS_EXCLUDE_SHIFTS = 2, BOUNDS_HANGING = 4, BOUNDS_GLYPH_PATH = 8,
       BOUNDS_OPTICAL = 16, BOUNDS_LANGUAGE_EXTENTS = 32 };

static CGRect d_CTLineGetBoundsWithOptions(const struct ct_line *l, unsigned long options) {
    if (!l) return (CGRect){{0, 0}, {0, 0}};
    if (options & (BOUNDS_GLYPH_PATH | BOUNDS_OPTICAL)) return glyph_bounds(l);
    CGFloat leading = (options & BOUNDS_EXCLUDE_LEADING) ? 0 : l->leading;
    return (CGRect){{0, -l->descent}, {l->width, l->ascent + l->descent + leading}};
}
DX_FN(CTLineGetBoundsWithOptions);

static CGRect d_CTLineGetImageBounds(const struct ct_line *l, void *ctx) {
    CGRect r = l ? glyph_bounds(l) : (CGRect){{0, 0}, {0, 0}};
    if (ctx) {
        CGPoint p = CALL(CGPoint, CGContextGetTextPosition, (void *))(ctx);
        r.origin.x += p.x;
        r.origin.y += p.y;
    }
    return r;
}
DX_FN(CTLineGetImageBounds);

static CGFloat d_CTLineGetOffsetForStringIndex(const struct ct_line *l, CFIndex index, CGFloat *secondary) {
    CGFloat x = l ? l->width : 0;
    for (CFIndex i = 0; l && i < run_count(l); i++) {
        struct ct_run *r = run_at(l, i);
        for (CFIndex k = 0; k < r->count; k++)
            if (r->indices[k] >= index) { x = r->positions[k].x; goto done; }
    }
done:
    if (secondary) *secondary = x;
    return x;
}
DX_FN(CTLineGetOffsetForStringIndex);

/* The string index nearest a point: the glyph whose middle is past it. */
static CFIndex d_CTLineGetStringIndexForPosition(const struct ct_line *l, CGPoint p) {
    if (!l) return -1;
    for (CFIndex i = 0; i < run_count(l); i++) {
        struct ct_run *r = run_at(l, i);
        for (CFIndex k = 0; k < r->count; k++)
            if (p.x < r->positions[k].x + r->advances[k].width / 2) return r->indices[k];
    }
    return l->range.location + l->range.length;
}
DX_FN(CTLineGetStringIndexForPosition);

/* ---- runs ---------------------------------------------------------------------------- */

static CFIndex d_CTRunGetGlyphCount(const struct ct_run *r) { return r ? r->count : 0; }
DX_FN(CTRunGetGlyphCount);
static Ref d_CTRunGetAttributes(const struct ct_run *r) { return r ? r->attributes : NULL; }
DX_FN(CTRunGetAttributes);
static CFRange d_CTRunGetStringRange(const struct ct_run *r) { return r ? r->range : (CFRange){0, 0}; }
DX_FN(CTRunGetStringRange);
static uint32_t d_CTRunGetStatus(const struct ct_run *r) { return 0; }
DX_FN(CTRunGetStatus);
static const uint16_t *d_CTRunGetGlyphsPtr(const struct ct_run *r) { return r ? r->glyphs : NULL; }
DX_FN(CTRunGetGlyphsPtr);
static const CGPoint *d_CTRunGetPositionsPtr(const struct ct_run *r) { return r ? r->positions : NULL; }
DX_FN(CTRunGetPositionsPtr);
static const CGSize *d_CTRunGetAdvancesPtr(const struct ct_run *r) { return r ? r->advances : NULL; }
DX_FN(CTRunGetAdvancesPtr);
static const CFIndex *d_CTRunGetStringIndicesPtr(const struct ct_run *r) { return r ? r->indices : NULL; }
DX_FN(CTRunGetStringIndicesPtr);

/* CFRange {0, 0} means "to the end", as in CoreText. */
static CFRange span(const struct ct_run *r, CFRange range) {
    if (range.length == 0) range.length = r->count - range.location;
    if (range.location < 0) range.location = 0;
    if (range.location + range.length > r->count) range.length = r->count - range.location;
    if (range.length < 0) range.length = 0;
    return range;
}

static void d_CTRunGetGlyphs(const struct ct_run *r, CFRange range, uint16_t *out) {
    if (!r || !out) return;
    range = span(r, range);
    memcpy(out, r->glyphs + range.location, (size_t)range.length * sizeof *out);
}
DX_FN(CTRunGetGlyphs);
static void d_CTRunGetPositions(const struct ct_run *r, CFRange range, CGPoint *out) {
    if (!r || !out) return;
    range = span(r, range);
    memcpy(out, r->positions + range.location, (size_t)range.length * sizeof *out);
}
DX_FN(CTRunGetPositions);
static void d_CTRunGetAdvances(const struct ct_run *r, CFRange range, CGSize *out) {
    if (!r || !out) return;
    range = span(r, range);
    memcpy(out, r->advances + range.location, (size_t)range.length * sizeof *out);
}
DX_FN(CTRunGetAdvances);
static void d_CTRunGetStringIndices(const struct ct_run *r, CFRange range, CFIndex *out) {
    if (!r || !out) return;
    range = span(r, range);
    memcpy(out, r->indices + range.location, (size_t)range.length * sizeof *out);
}
DX_FN(CTRunGetStringIndices);

static double d_CTRunGetTypographicBounds(const struct ct_run *r, CFRange range, CGFloat *ascent, CGFloat *descent,
                                          CGFloat *leading) {
    if (!r) return 0;
    if (ascent) *ascent = ct_ascent(r->font);
    if (descent) *descent = ct_descent(r->font);
    if (leading) *leading = ct_leading(r->font);
    range = span(r, range);
    double w = 0;
    for (CFIndex k = range.location; k < range.location + range.length; k++) w += r->advances[k].width;
    return w;
}
DX_FN(CTRunGetTypographicBounds);

/* ---- drawing ------------------------------------------------------------------------- */

static void draw_run(const struct ct_run *r, CFRange range, void *ctx, CGAffineTransform tm) {
    if (!r->count) return;
    range = span(r, range);
    struct cg_path *p = cg_path_new();
    if (!p) return;
    CGFloat s = ct_scale(r->font);
    for (CFIndex k = range.location; k < range.location + range.length; k++) {
        CGAffineTransform g = cg_concat((CGAffineTransform){s, 0, 0, s, 0, 0}, r->font->matrix);
        g = cg_concat(g, (CGAffineTransform){1, 0, 0, 1, r->positions[k].x, r->positions[k].y});
        g = cg_concat(g, tm);
        ttf_outline(r->font->face, r->glyphs[k], &g, p);
    }
    CALL(void, CGContextSaveGState, (void *))(ctx);
    if (!r->context_color) {
        if (r->color) CALL(void, CGContextSetFillColorWithColor, (void *, Ref))(ctx, r->color);
        else CALL(void, CGContextSetRGBFillColor, (void *, CGFloat, CGFloat, CGFloat, CGFloat))(ctx, 0, 0, 0, 1);
    }
    CALL(void, CGContextAddPath, (void *, Ref))(ctx, p);
    CALL(void, CGContextFillPath, (void *))(ctx);
    CALL(void, CGContextRestoreGState, (void *))(ctx);
    cg_release(p);
}

static void d_CTRunDraw(const struct ct_run *r, void *ctx, CFRange range) {
    if (!r || !ctx) return;
    CGAffineTransform tm = CALL(CGAffineTransform, CGContextGetTextMatrix, (void *))(ctx);
    draw_run(r, range, ctx, tm);
}
DX_FN(CTRunDraw);

/* Draw at the text position (the text matrix's translation). */
static void d_CTLineDraw(const struct ct_line *l, void *ctx) {
    if (!l || !ctx) return;
    CGAffineTransform tm = CALL(CGAffineTransform, CGContextGetTextMatrix, (void *))(ctx);
    for (CFIndex i = 0; i < run_count(l); i++) draw_run(run_at(l, i), (CFRange){0, 0}, ctx, tm);
}
DX_FN(CTLineDraw);
