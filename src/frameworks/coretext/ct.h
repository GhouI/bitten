/* CoreText inside mrun: TrueType fonts (ttf.c), finding them (fonts.c),
 * CTFont and its descriptors (font.c), lines and runs (line.c). */
#ifndef DX_CT_H
#define DX_CT_H

#include <stdbool.h>
#include <stdint.h>

#include "../coregraphics/cg.h"

typedef const void *Ref;
#define CALL(ret, name, args) ((ret(*) args)dx_registry_lookup("_" #name))
#define UTF8 0x08000100u
#define UTF16LE 0x14000100u

/* ---- TrueType (ttf.c) ------------------------------------------------- */

struct ttf {
    char *path;
    uint8_t *data;
    size_t size;
    uint32_t offset;                /* of this face (TrueType collections) */
    /* tables: offsets into data, 0 when absent */
    uint32_t cmap, glyf, loca, hmtx, head, hhea, maxp, os2, post, name, kern;
    uint32_t cmap_sub;              /* the subtable used */
    int cmap_format;
    int units_per_em, num_glyphs, num_hmetrics, loca_long;
    int ascent, descent, line_gap, cap_height, x_height, underline_pos, underline_thickness;
    int x_min, y_min, x_max, y_max;
    int weight;                     /* usWeightClass, 100..900 */
    bool italic, monospace;
    char family[96], style[64], full[160], postscript[96];
};

struct ttf *ttf_open(const char *path, int index);   /* NULL when not a TrueType font */
void ttf_close(struct ttf *f);
uint16_t ttf_glyph(const struct ttf *f, uint32_t codepoint);
int ttf_advance(const struct ttf *f, uint16_t glyph);
/* The outline in font units, transformed by t (may be NULL), appended to p. */
void ttf_outline(const struct ttf *f, uint16_t glyph, const CGAffineTransform *t, struct cg_path *p);
bool ttf_glyph_box(const struct ttf *f, uint16_t glyph, int box[4]);   /* xmin ymin xmax ymax */
const uint8_t *ttf_table(const struct ttf *f, uint32_t tag, uint32_t *length);

/* ---- the fonts on the system (fonts.c) -------------------------------- */

/* The face for a font name (PostScript, full or family name, or an Apple
 * name mapped to an open equivalent: the system UI font, Helvetica, Menlo,
 * Times...), never NULL while any font is installed. */
struct ttf *ct_face_for_name(const char *name);
/* The same family in another weight and slant. */
struct ttf *ct_face_variant(const struct ttf *f, int weight, bool italic);
/* A face that has a glyph for the code point, preferring f. */
struct ttf *ct_face_covering(const struct ttf *f, uint32_t codepoint);
/* Register the faces in a font file (CTFontManager); the first, or NULL. */
struct ttf *ct_register_file(const char *path);
int ct_face_count(void);

/* ---- CTFont (font.c) ----------------------------------------------------- */

struct ct_font {
    struct cf_object base;
    struct ttf *face;
    CGFloat size;
    CGAffineTransform matrix;
    Ref requested_name;             /* CFString the font was asked for by */
};

struct ct_font *ct_font_new(struct ttf *face, CGFloat size, const CGAffineTransform *matrix, Ref name);
struct ct_font *ct_default_font(void);
CGFloat ct_scale(const struct ct_font *f);           /* points per font unit */
CGFloat ct_ascent(const struct ct_font *f);
CGFloat ct_descent(const struct ct_font *f);
CGFloat ct_leading(const struct ct_font *f);
Ref ct_cfstring(const char *utf8);
/* A CTFont for an attribute value: a CTFont, or an NSFont (by -fontName and
 * -pointSize), or NULL. Returned retained. */
struct ct_font *ct_font_from_value(Ref value);
/* A CGColor for a color attribute: a CGColor or an NSColor (-CGColor). */
Ref ct_color_from_value(Ref value);

/* Attribute names, shared with Foundation and AppKit. */
extern const void *d_kCTFontAttributeName, *d_kCTForegroundColorAttributeName,
    *d_kCTForegroundColorFromContextAttributeName, *d_kCTKernAttributeName;
extern Ref ct_ns_color_attribute;                    /* @"NSColor" */

#endif
