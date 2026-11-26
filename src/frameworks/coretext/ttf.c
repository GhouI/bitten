/* TrueType fonts: the tables CoreText needs (head, hhea, maxp, hmtx, cmap
 * formats 4 and 12, loca, glyf with composite glyphs, OS/2, post, name),
 * read from the font file as the OpenType specification lays them out.
 * Outlines become CG paths (quadratic curves), drawn by CoreGraphics.
 * CFF-flavoured OpenType fonts are not read. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ct.h"

static uint16_t u16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static int16_t s16(const uint8_t *p) { return (int16_t)u16(p); }
static uint32_t u32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
#define TAG(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

static bool in(const struct ttf *f, uint32_t off, uint32_t len) { return off <= f->size && len <= f->size - off; }

const uint8_t *ttf_table(const struct ttf *f, uint32_t tag, uint32_t *length) {
    const uint8_t *d = f->data + f->offset;
    uint16_t n = u16(d + 4);
    for (uint16_t i = 0; i < n; i++) {
        const uint8_t *rec = d + 12 + 16 * i;
        if (!in(f, f->offset + 12 + 16u * i, 16)) return NULL;
        if (u32(rec) == tag) {
            uint32_t off = u32(rec + 8), len = u32(rec + 12);
            if (!in(f, off, len)) return NULL;
            if (length) *length = len;
            return f->data + off;
        }
    }
    return NULL;
}

static uint32_t table_off(const struct ttf *f, uint32_t tag, uint32_t min) {
    uint32_t len = 0;
    const uint8_t *t = ttf_table(f, tag, &len);
    return t && len >= min ? (uint32_t)(t - f->data) : 0;
}

/* A name-table string (platform 3 UTF-16BE or platform 1 Roman) as UTF-8. */
static void read_name(const struct ttf *f, int id, char *out, size_t size) {
    out[0] = 0;
    if (!f->name) return;
    const uint8_t *t = f->data + f->name;
    uint16_t count = u16(t + 2), strings = u16(t + 4);
    int best = -1;
    for (uint16_t i = 0; i < count; i++) {
        const uint8_t *r = t + 6 + 12 * i;
        if (!in(f, f->name + 6 + 12u * i, 12) || u16(r + 6) != id) continue;
        int platform = u16(r), language = u16(r + 4);
        int score = platform == 3 ? (language == 0x409 ? 3 : 2) : platform == 1 ? 1 : 0;
        if (score <= 0 || score <= best) continue;
        uint32_t off = f->name + strings + u16(r + 10), len = u16(r + 8);
        if (!in(f, off, len)) continue;
        best = score;
        size_t o = 0;
        const uint8_t *s = f->data + off;
        if (platform == 3) {
            for (uint32_t k = 0; k + 1 < len && o + 4 < size; k += 2) {
                uint32_t c = u16(s + k);
                if (c < 0x80) out[o++] = (char)c;
                else if (c < 0x800) { out[o++] = (char)(0xc0 | c >> 6); out[o++] = (char)(0x80 | (c & 63)); }
                else { out[o++] = (char)(0xe0 | c >> 12); out[o++] = (char)(0x80 | (c >> 6 & 63)); out[o++] = (char)(0x80 | (c & 63)); }
            }
        } else {
            for (uint32_t k = 0; k < len && o + 1 < size; k++) out[o++] = (char)(s[k] < 0x80 ? s[k] : '?');
        }
        out[o] = 0;
    }
}

static void pick_cmap(struct ttf *f) {
    const uint8_t *t = f->data + f->cmap;
    uint16_t n = u16(t + 2);
    int best = 0;
    for (uint16_t i = 0; i < n; i++) {
        if (!in(f, f->cmap + 4 + 8u * i, 8)) break;
        const uint8_t *r = t + 4 + 8 * i;
        int platform = u16(r), encoding = u16(r + 2);
        uint32_t off = f->cmap + u32(r + 4);
        if (!in(f, off, 4)) continue;
        int format = u16(f->data + off);
        int score = 0;
        if (format == 12 && (platform == 3 || platform == 0)) score = 4;
        else if (format == 4 && platform == 3 && encoding == 1) score = 3;
        else if (format == 4 && platform == 0) score = 2;
        else if (format == 4 && platform == 3 && encoding == 0) score = 1;   /* symbol fonts */
        if (score > best) { best = score; f->cmap_sub = off; f->cmap_format = format; }
    }
}

struct ttf *ttf_open(const char *path, int index) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return NULL;
    struct stat st;
    if (fstat(fd, &st) || st.st_size < 12) { close(fd); return NULL; }
    void *map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map == MAP_FAILED) return NULL;
    struct ttf *f = calloc(1, sizeof *f);
    if (!f) { munmap(map, (size_t)st.st_size); return NULL; }
    f->data = map;
    f->size = (size_t)st.st_size;
    uint32_t tag = u32(f->data);
    if (tag == TAG('t', 't', 'c', 'f')) {
        if (!in(f, 12, 4) || (uint32_t)index >= u32(f->data + 8) || !in(f, 12 + 4u * (uint32_t)index, 4)) goto fail;
        f->offset = u32(f->data + 12 + 4 * index);
        if (!in(f, f->offset, 12)) goto fail;
        tag = u32(f->data + f->offset);
    } else if (index) goto fail;
    if (tag != 0x00010000 && tag != TAG('t', 'r', 'u', 'e')) goto fail;   /* CFF ('OTTO') is not read */
    f->head = table_off(f, TAG('h', 'e', 'a', 'd'), 54);
    f->hhea = table_off(f, TAG('h', 'h', 'e', 'a'), 36);
    f->maxp = table_off(f, TAG('m', 'a', 'x', 'p'), 6);
    f->hmtx = table_off(f, TAG('h', 'm', 't', 'x'), 4);
    f->cmap = table_off(f, TAG('c', 'm', 'a', 'p'), 4);
    f->loca = table_off(f, TAG('l', 'o', 'c', 'a'), 4);
    f->glyf = table_off(f, TAG('g', 'l', 'y', 'f'), 0);
    f->os2 = table_off(f, TAG('O', 'S', '/', '2'), 68);
    f->post = table_off(f, TAG('p', 'o', 's', 't'), 16);
    f->name = table_off(f, TAG('n', 'a', 'm', 'e'), 6);
    if (!f->head || !f->hhea || !f->maxp || !f->hmtx || !f->cmap || !f->loca || !f->glyf) goto fail;
    const uint8_t *h = f->data + f->head, *hh = f->data + f->hhea;
    f->units_per_em = u16(h + 18);
    if (f->units_per_em < 16) goto fail;
    f->x_min = s16(h + 36); f->y_min = s16(h + 38); f->x_max = s16(h + 40); f->y_max = s16(h + 42);
    f->loca_long = s16(h + 50) != 0;
    f->ascent = s16(hh + 4);
    f->descent = s16(hh + 6);
    f->line_gap = s16(hh + 8);
    f->num_hmetrics = u16(hh + 34);
    f->num_glyphs = u16(f->data + f->maxp + 4);
    f->weight = 400;
    f->cap_height = f->ascent * 7 / 10;
    f->x_height = f->ascent / 2;
    if (f->os2) {
        const uint8_t *o = f->data + f->os2;
        f->weight = u16(o + 4);
        uint16_t selection = u16(o + 62);
        f->italic = selection & 1;
        if (u16(o) >= 2 && in(f, f->os2, 90)) {
            if (s16(o + 86)) f->x_height = s16(o + 86);
            if (s16(o + 88)) f->cap_height = s16(o + 88);
        }
    }
    if (f->post) {
        const uint8_t *p = f->data + f->post;
        f->underline_pos = s16(p + 8);
        f->underline_thickness = s16(p + 10);
        f->monospace = u32(p + 12) != 0;
        if (u32(p + 4) != 0) f->italic = true;               /* italicAngle */
    }
    if (!f->underline_thickness) f->underline_thickness = f->units_per_em / 20;
    pick_cmap(f);
    if (!f->cmap_sub) goto fail;
    read_name(f, 1, f->family, sizeof f->family);
    read_name(f, 2, f->style, sizeof f->style);
    read_name(f, 4, f->full, sizeof f->full);
    read_name(f, 6, f->postscript, sizeof f->postscript);
    /* Typographic family and subfamily (ids 16, 17) when present. */
    char typo[96];
    read_name(f, 16, typo, sizeof typo);
    if (typo[0]) snprintf(f->family, sizeof f->family, "%s", typo);
    read_name(f, 17, typo, sizeof typo);
    if (typo[0]) snprintf(f->style, sizeof f->style, "%.63s", typo);
    if (!f->family[0]) goto fail;
    f->path = strdup(path);
    return f;
fail:
    munmap(f->data, f->size);
    free(f);
    return NULL;
}

void ttf_close(struct ttf *f) {
    if (!f) return;
    munmap(f->data, f->size);
    free(f->path);
    free(f);
}

uint16_t ttf_glyph(const struct ttf *f, uint32_t c) {
    const uint8_t *t = f->data + f->cmap_sub;
    if (f->cmap_format == 4) {
        if (c > 0xffff || !in(f, f->cmap_sub, 14)) return 0;
        uint16_t segx2 = u16(t + 6);
        uint32_t ends = f->cmap_sub + 14, starts = ends + segx2 + 2, deltas = starts + segx2, ranges = deltas + segx2;
        if (!in(f, ends, (uint32_t)segx2 * 4 + 2)) return 0;
        uint16_t lo = 0, hi = segx2 / 2;
        while (lo < hi) {                       /* first segment whose end >= c */
            uint16_t mid = (uint16_t)((lo + hi) / 2);
            if (u16(f->data + ends + 2 * mid) < c) lo = (uint16_t)(mid + 1); else hi = mid;
        }
        if (lo >= segx2 / 2) return 0;
        uint16_t start = u16(f->data + starts + 2 * lo);
        if (c < start) return 0;
        uint16_t delta = u16(f->data + deltas + 2 * lo), range = u16(f->data + ranges + 2 * lo);
        if (!range) return (uint16_t)(c + delta);
        uint32_t at = ranges + 2 * lo + range + 2 * (c - start);
        if (!in(f, at, 2)) return 0;
        uint16_t g = u16(f->data + at);
        return g ? (uint16_t)(g + delta) : 0;
    }
    if (f->cmap_format == 12) {
        if (!in(f, f->cmap_sub, 16)) return 0;
        uint32_t n = u32(t + 12), lo = 0, hi = n;
        if (!in(f, f->cmap_sub + 16, n * 12)) return 0;
        while (lo < hi) {
            uint32_t mid = (lo + hi) / 2;
            const uint8_t *g = t + 16 + 12 * mid;
            if (c < u32(g)) hi = mid;
            else if (c > u32(g + 4)) lo = mid + 1;
            else return (uint16_t)(u32(g + 8) + (c - u32(g)));
        }
    }
    return 0;
}

int ttf_advance(const struct ttf *f, uint16_t g) {
    int i = g < f->num_hmetrics ? g : f->num_hmetrics - 1;
    if (i < 0 || !in(f, f->hmtx + 4u * (uint32_t)i, 2)) return 0;
    return u16(f->data + f->hmtx + 4 * i);
}

/* Where glyph g's data lies in glyf; false for an empty glyph. */
static bool glyph_range(const struct ttf *f, uint16_t g, uint32_t *off, uint32_t *len) {
    if (g >= f->num_glyphs) return false;
    uint32_t a, b;
    if (f->loca_long) {
        if (!in(f, f->loca + 4u * g, 8)) return false;
        a = u32(f->data + f->loca + 4 * g);
        b = u32(f->data + f->loca + 4 * g + 4);
    } else {
        if (!in(f, f->loca + 2u * g, 4)) return false;
        a = 2u * u16(f->data + f->loca + 2 * g);
        b = 2u * u16(f->data + f->loca + 2 * g + 2);
    }
    if (b <= a || !in(f, f->glyf + a, b - a) || b - a < 10) return false;
    *off = f->glyf + a;
    *len = b - a;
    return true;
}

bool ttf_glyph_box(const struct ttf *f, uint16_t g, int box[4]) {
    uint32_t off, len;
    if (!glyph_range(f, g, &off, &len)) return false;
    const uint8_t *p = f->data + off;
    box[0] = s16(p + 2); box[1] = s16(p + 4); box[2] = s16(p + 6); box[3] = s16(p + 8);
    return true;
}

static CGPoint tp(const CGAffineTransform *t, CGFloat x, CGFloat y) {
    CGPoint p = {x, y};
    return t ? cg_apply(*t, p) : p;
}

static void simple_outline(const struct ttf *f, uint32_t off, uint32_t len, int contours,
                           const CGAffineTransform *t, struct cg_path *path) {
    const uint8_t *p = f->data + off, *end = p + len;
    const uint8_t *ends = p + 10;
    if (ends + 2 * contours + 2 > end) return;
    int npoints = u16(ends + 2 * (contours - 1)) + 1;
    uint16_t ilen = u16(ends + 2 * contours);
    const uint8_t *q = ends + 2 * contours + 2 + ilen;
    if (q > end || npoints <= 0 || npoints > 65535) return;
    uint8_t *flags = malloc((size_t)npoints);
    CGFloat *xs = malloc((size_t)npoints * sizeof *xs), *ys = malloc((size_t)npoints * sizeof *ys);
    if (!flags || !xs || !ys) goto done;
    for (int i = 0; i < npoints;) {             /* flags, with repeats */
        if (q >= end) goto done;
        uint8_t fl = *q++;
        flags[i++] = fl;
        if (fl & 8) {
            if (q >= end) goto done;
            for (int r = *q++; r > 0 && i < npoints; r--) flags[i++] = fl;
        }
    }
    int v = 0;
    for (int i = 0; i < npoints; i++) {          /* x */
        uint8_t fl = flags[i];
        if (fl & 2) { if (q >= end) goto done; v += (fl & 16) ? *q : -*q; q++; }
        else if (!(fl & 16)) { if (q + 2 > end) goto done; v += s16(q); q += 2; }
        xs[i] = v;
    }
    v = 0;
    for (int i = 0; i < npoints; i++) {          /* y */
        uint8_t fl = flags[i];
        if (fl & 4) { if (q >= end) goto done; v += (fl & 32) ? *q : -*q; q++; }
        else if (!(fl & 32)) { if (q + 2 > end) goto done; v += s16(q); q += 2; }
        ys[i] = v;
    }
    int first = 0;
    for (int c = 0; c < contours; c++) {
        int last = u16(ends + 2 * c);
        if (last < first || last >= npoints) break;
        int n = last - first + 1;
        /* Start at an on-curve point, or between two off-curve ones. */
        int s = -1;
        for (int k = 0; k < n; k++) if (flags[first + k] & 1) { s = k; break; }
        CGFloat sx, sy;
        if (s >= 0) { sx = xs[first + s]; sy = ys[first + s]; }
        else { s = 0; sx = (xs[first] + xs[last]) / 2; sy = (ys[first] + ys[last]) / 2; }
        cg_path_move(path, tp(t, sx, sy));
        bool have_ctrl = false;
        CGFloat cx = 0, cy = 0;
        for (int k = 1; k <= n; k++) {
            int i = first + (s + k) % n;
            CGFloat x = xs[i], y = ys[i];
            if (flags[i] & 1) {
                if (have_ctrl) cg_path_quad(path, tp(t, cx, cy), tp(t, x, y));
                else cg_path_line(path, tp(t, x, y));
                have_ctrl = false;
            } else {
                if (have_ctrl) {
                    CGFloat mx = (cx + x) / 2, my = (cy + y) / 2;
                    cg_path_quad(path, tp(t, cx, cy), tp(t, mx, my));
                }
                cx = x; cy = y;
                have_ctrl = true;
            }
        }
        if (have_ctrl) cg_path_quad(path, tp(t, cx, cy), tp(t, sx, sy));
        cg_path_close(path);
        first = last + 1;
    }
done:
    free(flags);
    free(xs);
    free(ys);
}

static void outline(const struct ttf *f, uint16_t g, const CGAffineTransform *t, struct cg_path *path, int depth) {
    uint32_t off, len;
    if (depth > 8 || !glyph_range(f, g, &off, &len)) return;
    int contours = s16(f->data + off);
    if (contours > 0) { simple_outline(f, off, len, contours, t, path); return; }
    if (contours == 0) return;
    /* Composite: components, each a glyph with an offset and maybe a scale. */
    const uint8_t *p = f->data + off + 10, *end = f->data + off + len;
    for (;;) {
        if (p + 4 > end) return;
        uint16_t flags = u16(p), child = u16(p + 2);
        p += 4;
        CGFloat dx, dy;
        if (flags & 1) {                         /* ARG_1_AND_2_ARE_WORDS */
            if (p + 4 > end) return;
            dx = s16(p); dy = s16(p + 2); p += 4;
        } else {
            if (p + 2 > end) return;
            dx = (int8_t)p[0]; dy = (int8_t)p[1]; p += 2;
        }
        if (!(flags & 2)) dx = dy = 0;           /* point matching: not supported */
        CGAffineTransform m = {1, 0, 0, 1, dx, dy};
        if (flags & 8) {                         /* WE_HAVE_A_SCALE */
            if (p + 2 > end) return;
            m.a = m.d = s16(p) / 16384.0; p += 2;
        } else if (flags & 0x40) {               /* X_AND_Y_SCALE */
            if (p + 4 > end) return;
            m.a = s16(p) / 16384.0; m.d = s16(p + 2) / 16384.0; p += 4;
        } else if (flags & 0x80) {               /* TWO_BY_TWO */
            if (p + 8 > end) return;
            m.a = s16(p) / 16384.0; m.b = s16(p + 2) / 16384.0;
            m.c = s16(p + 4) / 16384.0; m.d = s16(p + 6) / 16384.0; p += 8;
        }
        CGAffineTransform full = t ? cg_concat(m, *t) : m;
        outline(f, child, &full, path, depth + 1);
        if (!(flags & 0x20)) return;             /* MORE_COMPONENTS */
    }
}

void ttf_outline(const struct ttf *f, uint16_t g, const CGAffineTransform *t, struct cg_path *p) {
    outline(f, g, t, p, 0);
}
