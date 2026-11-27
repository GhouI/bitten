/* CoreGraphics: the rasterizer. Polygons in device space are scanned row
 * by row; each pixel row is sampled at four heights, and along a sample
 * line the coverage of each pixel is exact (fractional span ends), so
 * edges are antialiased in both directions. The winding rule decides which
 * spans are inside. Coverage then goes through the clip mask and blends
 * the paint into the surface, premultiplied. */
#include <string.h>

#include "cg.h"

#define SUBSAMPLES 4

/* ---- pixels -------------------------------------------------------------------- */

static uint8_t to8(CGFloat v) {
    if (v <= 0) return 0;
    if (v >= 1) return 255;
    return (uint8_t)(v * 255 + 0.5);
}

void cg_read_pixel(const struct cg_surface *s, size_t x, size_t row, CGFloat out[4]) {
    const uint8_t *p = s->data + row * s->row_bytes + x * (size_t)s->format.bytes;
    const struct cg_format *f = &s->format;
    if (f->alpha_only) {
        out[0] = out[1] = out[2] = 0;
        out[3] = p[0] / 255.0;
    } else if (f->gray) {
        out[0] = out[1] = out[2] = p[f->r] / 255.0;
        out[3] = f->a >= 0 ? p[f->a] / 255.0 : 1;
    } else {
        out[0] = p[f->r] / 255.0;
        out[1] = p[f->g] / 255.0;
        out[2] = p[f->b] / 255.0;
        out[3] = f->a >= 0 ? p[f->a] / 255.0 : 1;
    }
}

void cg_write_pixel(struct cg_surface *s, size_t x, size_t row, const CGFloat in[4]) {
    uint8_t *p = s->data + row * s->row_bytes + x * (size_t)s->format.bytes;
    const struct cg_format *f = &s->format;
    if (f->alpha_only) {
        p[0] = to8(in[3]);
    } else if (f->gray) {
        p[f->r] = to8(0.2126 * in[0] + 0.7152 * in[1] + 0.0722 * in[2]);
        if (f->a >= 0) p[f->a] = to8(in[3]);
    } else {
        p[f->r] = to8(in[0]);
        p[f->g] = to8(in[1]);
        p[f->b] = to8(in[2]);
        if (f->a >= 0) p[f->a] = to8(in[3]);
    }
}

void cg_blend_pixel(const struct cg_target *t, size_t x, size_t row, const CGFloat src[4], CGFloat coverage) {
    if (t->surface->bounded && !cg_surface_holds(t->surface, x, row)) return;
    if (t->clip) coverage *= t->clip->data[row * t->clip->width + x] / 255.0;
    if (coverage <= 0) return;
    CGFloat d[4], s[4], k = coverage * t->alpha;
    const struct cg_format *f = &t->surface->format;
    if (t->blend == CG_BLEND_NORMAL && f->bytes == 4 && !f->gray && !f->alpha_only) {
        /* Source over an 8-bit colour pixel, the common case, without the
         * round trip through cg_read_pixel/cg_write_pixel: the same sums. */
        uint8_t *p = t->surface->data + row * t->surface->row_bytes + x * 4;
        CGFloat sa = src[3] * k;
        if (sa >= 1) {
            p[f->r] = to8(src[0] * k);
            p[f->g] = to8(src[1] * k);
            p[f->b] = to8(src[2] * k);
            if (f->a >= 0) p[f->a] = 255;
            return;
        }
        CGFloat inv = (1 - sa) * (1.0 / 255);
        p[f->r] = to8(src[0] * k + p[f->r] * inv);
        p[f->g] = to8(src[1] * k + p[f->g] * inv);
        p[f->b] = to8(src[2] * k + p[f->b] * inv);
        if (f->a >= 0) p[f->a] = to8(sa + p[f->a] * inv);
        return;
    }
    cg_read_pixel(t->surface, x, row, d);
    switch (t->blend) {
    case CG_BLEND_CLEAR:
        for (int i = 0; i < 4; i++) d[i] *= 1 - coverage;
        break;
    case CG_BLEND_COPY:
        for (int i = 0; i < 4; i++) d[i] = src[i] * t->alpha * coverage + d[i] * (1 - coverage);
        break;
    case CG_BLEND_NORMAL:
        for (int i = 0; i < 4; i++) s[i] = src[i] * k;
        for (int i = 0; i < 4; i++) d[i] = s[i] + d[i] * (1 - s[3]);
        break;
    default: {
        /* Porter-Duff and separable modes on premultiplied colour: the
         * result r replaces the destination where the shape covers it. */
        CGFloat r[4], sa, da = d[3];
        for (int i = 0; i < 4; i++) s[i] = src[i] * t->alpha;
        sa = s[3];
        for (int i = 0; i < 4; i++) {
            CGFloat sc = s[i], dc = d[i];
            switch (t->blend) {
            case 18: r[i] = sc * da; break;                              /* source in */
            case 19: r[i] = sc * (1 - da); break;                        /* source out */
            case 20: r[i] = sc * da + dc * (1 - sa); break;              /* source atop */
            case 21: r[i] = sc * (1 - da) + dc; break;                   /* destination over */
            case 22: r[i] = dc * sa; break;                              /* destination in */
            case 23: r[i] = dc * (1 - sa); break;                        /* destination out */
            case 24: r[i] = sc * (1 - da) + dc * sa; break;              /* destination atop */
            case 25: r[i] = sc * (1 - da) + dc * (1 - sa); break;        /* xor */
            case 27: r[i] = sc + dc > 1 ? 1 : sc + dc; break;            /* plus lighter */
            case 1:                                                      /* multiply */
                r[i] = i == 3 ? sa + da - sa * da : sc * dc + sc * (1 - da) + dc * (1 - sa);
                break;
            case 2: r[i] = sc + dc - sc * dc; break;                     /* screen */
            case 4: case 5: {                                            /* darken, lighten */
                if (i == 3) { r[i] = sa + da - sa * da; break; }
                CGFloat a = sc * da, b = dc * sa;
                r[i] = (t->blend == 4 ? (a < b ? a : b) : (a > b ? a : b)) + sc * (1 - da) + dc * (1 - sa);
                break;
            }
            default: r[i] = sc + dc * (1 - sa); break;                   /* others: normal */
            }
        }
        for (int i = 0; i < 4; i++) d[i] += (r[i] - d[i]) * coverage;
        break;
    }
    }
    cg_write_pixel(t->surface, x, row, d);
}

/* ---- masks -------------------------------------------------------------------- */

struct cg_mask *cg_mask_new(size_t w, size_t h, uint8_t fill) {
    struct cg_mask *m = calloc(1, sizeof *m);
    if (!m) return NULL;
    m->refs = 1;
    m->width = w;
    m->height = h;
    m->data = malloc((w && h) ? w * h : 1);
    if (!m->data) { free(m); return NULL; }
    memset(m->data, fill, w * h);
    if (fill) m->x1 = w, m->y1 = h;
    return m;
}

struct cg_mask *cg_mask_retain(struct cg_mask *m) {
    if (m) m->refs++;
    return m;
}

void cg_mask_release(struct cg_mask *m) {
    if (m && --m->refs == 0) {
        free(m->data);
        free(m);
    }
}

/* ---- scan conversion ------------------------------------------------------------- */

struct edge { CGFloat x0, y0, x1, y1; int dir; };
struct crossing { CGFloat x; int dir; };

static int by_x(const void *a, const void *b) {
    CGFloat d = ((const struct crossing *)a)->x - ((const struct crossing *)b)->x;
    return d < 0 ? -1 : d > 0;
}

typedef void (*row_fn)(void *ctx, size_t row, size_t x0, size_t x1, const float *coverage);

/* Polygons in device space (y up) over a width x height pixel grid. */
/* Only rows [lr0, lr1) and columns [lc0, lc1) are scanned (a clip's box). */
static void scan(const struct cg_polys *polys, size_t width, size_t height, bool even_odd, bool aa,
                 size_t lr0, size_t lr1, size_t lc0, size_t lc1, row_fn fn, void *ctx) {
    size_t ne = 0, cap = 64;
    struct edge *edges = malloc(cap * sizeof *edges);
    if (!edges) return;
    CGFloat miny = INFINITY, maxy = -INFINITY, minx = INFINITY, maxx = -INFINITY;
    for (int i = 0; i < polys->count; i++) {
        const struct cg_poly *p = &polys->poly[i];
        for (int k = 0; k < p->count; k++) {
            CGPoint a = p->pt[k], b = p->pt[(k + 1) % p->count];
            CGFloat ay = (CGFloat)height - a.y, by = (CGFloat)height - b.y;   /* to pixel rows */
            if (!isfinite(a.x) || !isfinite(ay) || !isfinite(b.x) || !isfinite(by)) continue;
            if (a.x < minx) minx = a.x;
            if (a.x > maxx) maxx = a.x;
            if (ay == by) continue;
            if (ne == cap) {
                cap *= 2;
                struct edge *e = realloc(edges, cap * sizeof *edges);
                if (!e) { free(edges); return; }
                edges = e;
            }
            struct edge *e = &edges[ne++];
            if (ay < by) { *e = (struct edge){a.x, ay, b.x, by, 1}; }
            else { *e = (struct edge){b.x, by, a.x, ay, -1}; }
            if (e->y0 < miny) miny = e->y0;
            if (e->y1 > maxy) maxy = e->y1;
        }
    }
    if (!ne) { free(edges); return; }
    long r0 = (long)floor(miny), r1 = (long)ceil(maxy);
    if (r0 < (long)lr0) r0 = (long)lr0;
    if (r1 > (long)lr1) r1 = (long)lr1;
    if (r1 > (long)height) r1 = (long)height;
    long c0 = (long)floor(minx) - 1, c1 = (long)ceil(maxx) + 1;
    if (c0 < (long)lc0) c0 = (long)lc0;
    if (c1 > (long)lc1) c1 = (long)lc1;
    if (c1 > (long)width) c1 = (long)width;
    if (r0 >= r1 || c0 >= c1) { free(edges); return; }
    size_t span = (size_t)(c1 - c0);
    float *cov = calloc(span + 1, sizeof *cov);
    struct crossing *xs = malloc(ne * sizeof *xs);
    int samples = aa ? SUBSAMPLES : 1;
    float weight = 1.0f / samples;
    for (long row = r0; cov && xs && row < r1; row++) {
        bool any = false;
        for (int s = 0; s < samples; s++) {
            CGFloat sy = row + (s + 0.5) / samples;
            size_t n = 0;
            for (size_t i = 0; i < ne; i++) {
                const struct edge *e = &edges[i];
                if (sy < e->y0 || sy >= e->y1) continue;
                xs[n].x = e->x0 + (sy - e->y0) * (e->x1 - e->x0) / (e->y1 - e->y0);
                xs[n].dir = e->dir;
                n++;
            }
            if (n < 2) continue;
            qsort(xs, n, sizeof *xs, by_x);
            int wind = 0;
            for (size_t i = 0; i + 1 < n; i++) {
                wind += xs[i].dir;
                bool inside = even_odd ? (wind & 1) : wind != 0;
                if (!inside) continue;
                CGFloat xa = xs[i].x - c0, xb = xs[i + 1].x - c0;
                if (xa < 0) xa = 0;
                if (xb > (CGFloat)span) xb = (CGFloat)span;
                if (xb <= xa) continue;
                any = true;
                if (!aa) {
                    long ia = (long)ceil(xa - 0.5), ib = (long)ceil(xb - 0.5);
                    for (long k = ia; k < ib; k++) cov[k] += weight;
                    continue;
                }
                long ia = (long)floor(xa), ib = (long)floor(xb);
                if (ia == ib) { cov[ia] += (float)(xb - xa) * weight; continue; }
                cov[ia] += (float)(ia + 1 - xa) * weight;
                for (long k = ia + 1; k < ib; k++) cov[k] += weight;
                if (ib < (long)span) cov[ib] += (float)(xb - ib) * weight;
            }
        }
        if (any) fn(ctx, (size_t)row, (size_t)c0, (size_t)c1, cov);
        memset(cov, 0, (span + 1) * sizeof *cov);
    }
    free(xs);
    free(cov);
    free(edges);
}

/* ---- filling --------------------------------------------------------------------- */

struct fill_ctx { const struct cg_target *t; const struct cg_paint *paint; };

static void fill_row(void *arg, size_t row, size_t x0, size_t x1, const float *cov) {
    struct fill_ctx *c = arg;
    const struct cg_target *t = c->t;
    CGFloat color[4], premul[4];
    if (!c->paint->shade) {
        CGFloat a = c->paint->rgba[3];
        for (int i = 0; i < 3; i++) premul[i] = c->paint->rgba[i] * a;
        premul[3] = a;
    }
    /* An opaque colour over 8-bit colour pixels: where the shape and the
     * clip cover a pixel fully, the pixel is the colour. */
    const struct cg_format *f = &t->surface->format;
    bool solid = !c->paint->shade && premul[3] >= 1 && t->alpha >= 1 && t->blend == CG_BLEND_NORMAL &&
                 f->bytes == 4 && !f->gray && !f->alpha_only;
    uint8_t px[4] = {0};
    if (solid) {
        px[f->r] = to8(premul[0]);
        px[f->g] = to8(premul[1]);
        px[f->b] = to8(premul[2]);
        if (f->a >= 0) px[f->a] = 255;
    }
    const struct cg_surface *sf = t->surface;
    if (sf->bounded) { /* only the pixels a bounded layer holds */
        if (row < sf->by0 || row >= sf->by1) return;
        size_t lo = x0 > sf->bx0 ? x0 : sf->bx0, hi = x1 < sf->bx1 ? x1 : sf->bx1;
        if (lo >= hi) return;
        cov += lo - x0;
        x0 = lo;
        x1 = hi;
    }
    uint8_t *line = t->surface->data + row * t->surface->row_bytes;
    const uint8_t *clip = t->clip ? t->clip->data + row * t->clip->width : NULL;
    for (size_t x = x0; x < x1; x++) {
        float k = cov[x - x0];
        if (k <= 0) continue;
        if (k > 1) k = 1;
        if (solid && k >= 1 && (!clip || clip[x] == 255)) {
            memcpy(line + x * 4, px, 4);
            continue;
        }
        if (c->paint->shade) {
            c->paint->shade(c->paint, x + 0.5, (CGFloat)t->surface->height - (row + 0.5), color);
            if (c->paint->premultiplied) {
                for (int i = 0; i < 4; i++) premul[i] = color[i];
            } else {
                for (int i = 0; i < 3; i++) premul[i] = color[i] * color[3];
                premul[3] = color[3];
            }
        }
        cg_blend_pixel(t, x, row, premul, k);
    }
}

void cg_fill_polys(const struct cg_target *t, const struct cg_polys *polys, bool even_odd, const struct cg_paint *paint) {
    if (!t->surface || !t->surface->data) return;
    struct fill_ctx c = {t, paint};
    size_t w = t->surface->width, h = t->surface->height;
    if (t->clip) {
        if (t->clip->x0 >= t->clip->x1 || t->clip->y0 >= t->clip->y1) return;
        scan(polys, w, h, even_odd, t->antialias, t->clip->y0, t->clip->y1, t->clip->x0, t->clip->x1, fill_row, &c);
    } else {
        scan(polys, w, h, even_odd, t->antialias, 0, h, 0, w, fill_row, &c);
    }
}

struct mask_ctx { struct cg_mask *m; };

static void mask_row(void *arg, size_t row, size_t x0, size_t x1, const float *cov) {
    struct cg_mask *m = ((struct mask_ctx *)arg)->m;
    for (size_t x = x0; x < x1; x++) {
        float k = cov[x - x0];
        if (k > 1) k = 1;
        uint8_t v = (uint8_t)(k * 255 + 0.5f);
        if (k <= 0 || !v) continue;
        m->data[row * m->width + x] = v;
        if (m->x0 >= m->x1) m->x0 = x, m->x1 = x + 1, m->y0 = row, m->y1 = row + 1;
        if (x < m->x0) m->x0 = x;
        if (x + 1 > m->x1) m->x1 = x + 1;
        if (row < m->y0) m->y0 = row;
        if (row + 1 > m->y1) m->y1 = row + 1;
    }
}

void cg_mask_polys(struct cg_mask *m, const struct cg_polys *polys, bool even_odd, bool antialias) {
    cg_mask_polys_within(m, polys, even_odd, antialias, NULL);
}
void cg_mask_polys_within(struct cg_mask *m, const struct cg_polys *polys, bool even_odd, bool antialias,
                          const struct cg_mask *within) {
    struct mask_ctx c = {m};
    if (within) scan(polys, m->width, m->height, even_odd, antialias, within->y0, within->y1, within->x0, within->x1, mask_row, &c);
    else scan(polys, m->width, m->height, even_odd, antialias, 0, m->height, 0, m->width, mask_row, &c);
}
