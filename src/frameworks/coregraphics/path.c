/* CoreGraphics: paths (CGPath and CGMutablePath), flattening into
 * polylines, and stroking (the outline of a stroke as polygons). */
#include <string.h>

#include "cg.h"

/* ---- the path object ----------------------------------------------------- */

static void path_destroy(void *o) { free(((struct cg_path *)o)->el); }

static Boolean path_equal(const void *a, const void *b) {
    const struct cg_path *x = a, *y = b;
    return x->count == y->count && !memcmp(x->el, y->el, (size_t)x->count * sizeof *x->el);
}
static const struct cf_ops path_ops = {path_destroy, path_equal, NULL, NULL};

struct cg_path *cg_path_new(void) { return cf_alloc(NULL, sizeof(struct cg_path), CF_CG_PATH, &path_ops); }

void cg_path_clear(struct cg_path *p) {
    p->count = 0;
    p->has_current = false;
}

static void push(struct cg_path *p, int type, CGPoint a, CGPoint b, CGPoint c) {
    if (p->count == p->capacity) {
        int cap = p->capacity ? p->capacity * 2 : 16;
        struct cg_el *el = realloc(p->el, (size_t)cap * sizeof *el);
        if (!el) return;
        p->el = el;
        p->capacity = cap;
    }
    struct cg_el *e = &p->el[p->count++];
    e->type = type;
    e->p[0] = a;
    e->p[1] = b;
    e->p[2] = c;
}

static CGPoint T(const CGAffineTransform *t, CGPoint p) { return t ? cg_apply(*t, p) : p; }

void cg_path_move(struct cg_path *p, CGPoint a) {
    push(p, CG_MOVE, a, a, a);
    p->current = p->start = a;
    p->has_current = true;
}

void cg_path_line(struct cg_path *p, CGPoint a) {
    if (!p->has_current) { cg_path_move(p, a); return; }
    push(p, CG_LINE, a, a, a);
    p->current = a;
}

void cg_path_quad(struct cg_path *p, CGPoint c, CGPoint a) {
    if (!p->has_current) cg_path_move(p, c);
    push(p, CG_QUAD, c, a, a);
    p->current = a;
}

void cg_path_curve(struct cg_path *p, CGPoint c1, CGPoint c2, CGPoint a) {
    if (!p->has_current) cg_path_move(p, c1);
    push(p, CG_CURVE, c1, c2, a);
    p->current = a;
}

void cg_path_close(struct cg_path *p) {
    if (!p->has_current) return;
    push(p, CG_CLOSE, p->start, p->start, p->start);
    p->current = p->start;
}

void cg_path_rect(struct cg_path *p, CGRect r, const CGAffineTransform *t) {
    CGFloat x0 = r.origin.x, y0 = r.origin.y, x1 = x0 + r.size.width, y1 = y0 + r.size.height;
    cg_path_move(p, T(t, (CGPoint){x0, y0}));
    cg_path_line(p, T(t, (CGPoint){x1, y0}));
    cg_path_line(p, T(t, (CGPoint){x1, y1}));
    cg_path_line(p, T(t, (CGPoint){x0, y1}));
    cg_path_close(p);
}

/* A quarter-ellipse as a cubic Bezier: the standard control distance. */
static const CGFloat KAPPA = 0.5522847498307936;

void cg_path_ellipse(struct cg_path *p, CGRect r, const CGAffineTransform *t) {
    CGFloat cx = r.origin.x + r.size.width / 2, cy = r.origin.y + r.size.height / 2;
    CGFloat rx = r.size.width / 2, ry = r.size.height / 2, kx = rx * KAPPA, ky = ry * KAPPA;
    /* Counter-clockwise from the right, as CGPathAddEllipseInRect. */
    cg_path_move(p, T(t, (CGPoint){cx + rx, cy}));
    cg_path_curve(p, T(t, (CGPoint){cx + rx, cy + ky}), T(t, (CGPoint){cx + kx, cy + ry}), T(t, (CGPoint){cx, cy + ry}));
    cg_path_curve(p, T(t, (CGPoint){cx - kx, cy + ry}), T(t, (CGPoint){cx - rx, cy + ky}), T(t, (CGPoint){cx - rx, cy}));
    cg_path_curve(p, T(t, (CGPoint){cx - rx, cy - ky}), T(t, (CGPoint){cx - kx, cy - ry}), T(t, (CGPoint){cx, cy - ry}));
    cg_path_curve(p, T(t, (CGPoint){cx + kx, cy - ry}), T(t, (CGPoint){cx + rx, cy - ky}), T(t, (CGPoint){cx + rx, cy}));
    cg_path_close(p);
}

void cg_path_rounded_rect(struct cg_path *p, CGRect r, CGFloat rw, CGFloat rh, const CGAffineTransform *t) {
    if (r.size.width < 0) { r.origin.x += r.size.width; r.size.width = -r.size.width; }
    if (r.size.height < 0) { r.origin.y += r.size.height; r.size.height = -r.size.height; }
    if (rw > r.size.width / 2) rw = r.size.width / 2;
    if (rh > r.size.height / 2) rh = r.size.height / 2;
    if (rw <= 0 || rh <= 0) { cg_path_rect(p, r, t); return; }
    CGFloat x0 = r.origin.x, y0 = r.origin.y, x1 = x0 + r.size.width, y1 = y0 + r.size.height;
    CGFloat kx = rw * KAPPA, ky = rh * KAPPA;
    cg_path_move(p, T(t, (CGPoint){x0 + rw, y0}));
    cg_path_line(p, T(t, (CGPoint){x1 - rw, y0}));
    cg_path_curve(p, T(t, (CGPoint){x1 - rw + kx, y0}), T(t, (CGPoint){x1, y0 + rh - ky}), T(t, (CGPoint){x1, y0 + rh}));
    cg_path_line(p, T(t, (CGPoint){x1, y1 - rh}));
    cg_path_curve(p, T(t, (CGPoint){x1, y1 - rh + ky}), T(t, (CGPoint){x1 - rw + kx, y1}), T(t, (CGPoint){x1 - rw, y1}));
    cg_path_line(p, T(t, (CGPoint){x0 + rw, y1}));
    cg_path_curve(p, T(t, (CGPoint){x0 + rw - kx, y1}), T(t, (CGPoint){x0, y1 - rh + ky}), T(t, (CGPoint){x0, y1 - rh}));
    cg_path_line(p, T(t, (CGPoint){x0, y0 + rh}));
    cg_path_curve(p, T(t, (CGPoint){x0, y0 + rh - ky}), T(t, (CGPoint){x0 + rw - kx, y0}), T(t, (CGPoint){x0 + rw, y0}));
    cg_path_close(p);
}

/* An arc as cubic segments of at most a quarter turn each. In CG's
 * y-up space, clockwise == true means decreasing angles. */
void cg_path_arc(struct cg_path *p, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat a1, bool clockwise,
                 const CGAffineTransform *t) {
    CGFloat sweep = a1 - a0;
    if (clockwise) {
        while (sweep > 0) sweep -= 2 * M_PI;
        if (sweep < -2 * M_PI) sweep = -2 * M_PI;
    } else {
        while (sweep < 0) sweep += 2 * M_PI;
        if (sweep > 2 * M_PI) sweep = 2 * M_PI;
    }
    CGPoint start = T(t, (CGPoint){x + r * cos(a0), y + r * sin(a0)});
    if (p->has_current) cg_path_line(p, start); else cg_path_move(p, start);
    int n = (int)ceil(fabs(sweep) / (M_PI / 2) - 1e-9);
    if (n < 1) return;
    CGFloat step = sweep / n, k = 4.0 / 3.0 * tan(step / 4);
    CGFloat a = a0;
    for (int i = 0; i < n; i++) {
        CGFloat b = a + step;
        CGPoint p0 = {x + r * cos(a), y + r * sin(a)}, p3 = {x + r * cos(b), y + r * sin(b)};
        CGPoint c1 = {p0.x - k * r * sin(a), p0.y + k * r * cos(a)};
        CGPoint c2 = {p3.x + k * r * sin(b), p3.y - k * r * cos(b)};
        cg_path_curve(p, T(t, c1), T(t, c2), T(t, p3));
        a = b;
    }
}

/* CGPathAddArcToPoint: a corner of radius r between the current point,
 * p1 and p2 (all in the path's coordinates after t). */
void cg_path_arc_to(struct cg_path *p, CGPoint p1, CGPoint p2, CGFloat r, const CGAffineTransform *t) {
    if (!p->has_current) { cg_path_move(p, T(t, p1)); return; }
    /* Work in untransformed coordinates: invert the current point. */
    CGPoint p0 = t ? cg_apply(cg_invert(*t), p->current) : p->current;
    CGFloat d0x = p0.x - p1.x, d0y = p0.y - p1.y, d2x = p2.x - p1.x, d2y = p2.y - p1.y;
    CGFloat l0 = hypot(d0x, d0y), l2 = hypot(d2x, d2y);
    if (l0 == 0 || l2 == 0 || r == 0) { cg_path_line(p, T(t, p1)); return; }
    d0x /= l0; d0y /= l0; d2x /= l2; d2y /= l2;
    CGFloat cosang = d0x * d2x + d0y * d2y;
    if (fabs(cosang) > 1 - 1e-9) { cg_path_line(p, T(t, p1)); return; }
    CGFloat ang = acos(cosang), dist = r / tan(ang / 2);
    CGPoint t0 = {p1.x + d0x * dist, p1.y + d0y * dist}, t2 = {p1.x + d2x * dist, p1.y + d2y * dist};
    CGFloat bx = d0x + d2x, by = d0y + d2y, bl = hypot(bx, by);
    CGFloat cd = r / sin(ang / 2);
    CGPoint c = {p1.x + bx / bl * cd, p1.y + by / bl * cd};
    CGFloat a0 = atan2(t0.y - c.y, t0.x - c.x), a1 = atan2(t2.y - c.y, t2.x - c.x);
    /* A corner arc is always the short way round between the tangents. */
    CGFloat sweep = a1 - a0;
    while (sweep > M_PI) sweep -= 2 * M_PI;
    while (sweep <= -M_PI) sweep += 2 * M_PI;
    cg_path_line(p, T(t, t0));
    cg_path_arc(p, c.x, c.y, r, a0, a0 + sweep, sweep < 0, t);
}

void cg_path_append(struct cg_path *p, const struct cg_path *src, const CGAffineTransform *t) {
    for (int i = 0; src && i < src->count; i++) {
        const struct cg_el *e = &src->el[i];
        switch (e->type) {
        case CG_MOVE: cg_path_move(p, T(t, e->p[0])); break;
        case CG_LINE: cg_path_line(p, T(t, e->p[0])); break;
        case CG_QUAD: cg_path_quad(p, T(t, e->p[0]), T(t, e->p[1])); break;
        case CG_CURVE: cg_path_curve(p, T(t, e->p[0]), T(t, e->p[1]), T(t, e->p[2])); break;
        case CG_CLOSE: cg_path_close(p); break;
        }
    }
}

static int el_points(int type) { return type == CG_QUAD ? 2 : type == CG_CURVE ? 3 : type == CG_CLOSE ? 0 : 1; }

CGRect cg_path_bounds(const struct cg_path *p, bool control_points) {
    CGFloat x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
    struct cg_polys polys = {0};
    if (!control_points) {
        cg_flatten(p, 0.05, &polys);
        for (int i = 0; i < polys.count; i++)
            for (int k = 0; k < polys.poly[i].count; k++) {
                CGPoint q = polys.poly[i].pt[k];
                if (q.x < x0) x0 = q.x;
                if (q.y < y0) y0 = q.y;
                if (q.x > x1) x1 = q.x;
                if (q.y > y1) y1 = q.y;
            }
        cg_polys_free(&polys);
    } else {
        for (int i = 0; i < p->count; i++)
            for (int k = 0; k < el_points(p->el[i].type); k++) {
                CGPoint q = p->el[i].p[k];
                if (q.x < x0) x0 = q.x;
                if (q.y < y0) y0 = q.y;
                if (q.x > x1) x1 = q.x;
                if (q.y > y1) y1 = q.y;
            }
    }
    if (x0 > x1) return (CGRect){{INFINITY, INFINITY}, {0, 0}};      /* CGRectNull */
    return (CGRect){{x0, y0}, {x1 - x0, y1 - y0}};
}

/* ---- polylines ------------------------------------------------------------- */

void cg_poly_add(struct cg_poly *p, CGPoint a) {
    if (p->count && p->pt[p->count - 1].x == a.x && p->pt[p->count - 1].y == a.y) return;
    if (p->count == p->capacity) {
        int cap = p->capacity ? p->capacity * 2 : 16;
        CGPoint *pt = realloc(p->pt, (size_t)cap * sizeof *pt);
        if (!pt) return;
        p->pt = pt;
        p->capacity = cap;
    }
    p->pt[p->count++] = a;
}

struct cg_poly *cg_polys_new_poly(struct cg_polys *s) {
    if (s->count == s->capacity) {
        int cap = s->capacity ? s->capacity * 2 : 8;
        struct cg_poly *poly = realloc(s->poly, (size_t)cap * sizeof *poly);
        if (!poly) return NULL;
        s->poly = poly;
        s->capacity = cap;
    }
    struct cg_poly *p = &s->poly[s->count++];
    memset(p, 0, sizeof *p);
    return p;
}

void cg_polys_free(struct cg_polys *s) {
    for (int i = 0; i < s->count; i++) free(s->poly[i].pt);
    free(s->poly);
    memset(s, 0, sizeof *s);
}

void cg_polys_transform(struct cg_polys *s, CGAffineTransform t) {
    for (int i = 0; i < s->count; i++)
        for (int k = 0; k < s->poly[i].count; k++) s->poly[i].pt[k] = cg_apply(t, s->poly[i].pt[k]);
}

static int segments(CGFloat length, CGFloat tolerance) {
    int n = (int)ceil(sqrt(length / (tolerance * 8)));
    return n < 1 ? 1 : n > 200 ? 200 : n;
}

void cg_flatten(const struct cg_path *p, CGFloat tolerance, struct cg_polys *out) {
    struct cg_poly *cur = NULL;
    CGPoint last = {0, 0};
    for (int i = 0; p && i < p->count; i++) {
        const struct cg_el *e = &p->el[i];
        if (e->type == CG_MOVE || !cur) {
            cur = cg_polys_new_poly(out);
            if (!cur) return;
            if (e->type != CG_MOVE) cg_poly_add(cur, last);
        }
        switch (e->type) {
        case CG_MOVE:
            cg_poly_add(cur, e->p[0]);
            last = e->p[0];
            break;
        case CG_LINE:
            cg_poly_add(cur, e->p[0]);
            last = e->p[0];
            break;
        case CG_QUAD: {
            CGFloat len = hypot(e->p[0].x - last.x, e->p[0].y - last.y) + hypot(e->p[1].x - e->p[0].x, e->p[1].y - e->p[0].y);
            int n = segments(len, tolerance);
            for (int k = 1; k <= n; k++) {
                CGFloat t = (CGFloat)k / n, u = 1 - t;
                cg_poly_add(cur, (CGPoint){u * u * last.x + 2 * u * t * e->p[0].x + t * t * e->p[1].x,
                                           u * u * last.y + 2 * u * t * e->p[0].y + t * t * e->p[1].y});
            }
            last = e->p[1];
            break;
        }
        case CG_CURVE: {
            CGFloat len = hypot(e->p[0].x - last.x, e->p[0].y - last.y) + hypot(e->p[1].x - e->p[0].x, e->p[1].y - e->p[0].y) +
                          hypot(e->p[2].x - e->p[1].x, e->p[2].y - e->p[1].y);
            int n = segments(len, tolerance);
            for (int k = 1; k <= n; k++) {
                CGFloat t = (CGFloat)k / n, u = 1 - t;
                CGFloat a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
                cg_poly_add(cur, (CGPoint){a * last.x + b * e->p[0].x + c * e->p[1].x + d * e->p[2].x,
                                           a * last.y + b * e->p[0].y + c * e->p[1].y + d * e->p[2].y});
            }
            last = e->p[2];
            break;
        }
        case CG_CLOSE:
            cur->closed = true;
            last = e->p[0];
            cur = NULL;            /* a following segment starts a new subpath at the start point */
            break;
        }
    }
}

/* ---- stroking ------------------------------------------------------------------ */

static CGFloat signed_area(const struct cg_poly *p) {
    CGFloat a = 0;
    for (int i = 0; i < p->count; i++) {
        CGPoint u = p->pt[i], v = p->pt[(i + 1) % p->count];
        a += u.x * v.y - v.x * u.y;
    }
    return a / 2;
}

/* Add a polygon, counter-clockwise. */
static void emit(struct cg_polys *out, const CGPoint *pts, int n) {
    struct cg_poly *p = cg_polys_new_poly(out);
    if (!p) return;
    for (int i = 0; i < n; i++) cg_poly_add(p, pts[i]);
    p->closed = true;
    if (signed_area(p) < 0)
        for (int i = 0; i < p->count / 2; i++) {
            CGPoint t = p->pt[i];
            p->pt[i] = p->pt[p->count - 1 - i];
            p->pt[p->count - 1 - i] = t;
        }
}

static void emit_circle(struct cg_polys *out, CGPoint c, CGFloat r, CGFloat tolerance) {
    int n = (int)ceil(M_PI / acos(fmax(-1, 1 - tolerance / fmax(r, 1e-9))));
    if (n < 8) n = 8;
    if (n > 256) n = 256;
    CGPoint pts[256];
    for (int i = 0; i < n; i++) pts[i] = (CGPoint){c.x + r * cos(2 * M_PI * i / n), c.y + r * sin(2 * M_PI * i / n)};
    emit(out, pts, n);
}

enum { CAP_BUTT = 0, CAP_ROUND = 1, CAP_SQUARE = 2, JOIN_MITER = 0, JOIN_ROUND = 1, JOIN_BEVEL = 2 };

static void stroke_poly(const CGPoint *pt, int n, bool closed, const struct cg_stroke_style *st, CGFloat tol,
                        struct cg_polys *out) {
    CGFloat hw = st->width / 2;
    if (hw <= 0) return;
    if (n == 1) {
        if (st->cap == CAP_ROUND) emit_circle(out, pt[0], hw, tol);
        else if (st->cap == CAP_SQUARE) {
            CGPoint q[] = {{pt[0].x - hw, pt[0].y - hw}, {pt[0].x + hw, pt[0].y - hw},
                           {pt[0].x + hw, pt[0].y + hw}, {pt[0].x - hw, pt[0].y + hw}};
            emit(out, q, 4);
        }
        return;
    }
    int segs = closed ? n : n - 1;
    for (int i = 0; i < segs; i++) {
        CGPoint a = pt[i], b = pt[(i + 1) % n];
        CGFloat dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy);
        if (len == 0) continue;
        CGFloat nx = -dy / len * hw, ny = dx / len * hw;
        CGFloat ex = 0, ey = 0, sx = 0, sy = 0;          /* square caps extend the ends */
        if (!closed && st->cap == CAP_SQUARE) {
            if (i == 0) { sx = dx / len * hw; sy = dy / len * hw; }
            if (i == segs - 1) { ex = dx / len * hw; ey = dy / len * hw; }
        }
        CGPoint q[] = {{a.x - sx + nx, a.y - sy + ny}, {b.x + ex + nx, b.y + ey + ny},
                       {b.x + ex - nx, b.y + ey - ny}, {a.x - sx - nx, a.y - sy - ny}};
        emit(out, q, 4);
    }
    /* Joins at interior vertices (every vertex of a closed polyline). */
    for (int i = closed ? 0 : 1; i < (closed ? n : n - 1); i++) {
        CGPoint v = pt[i], a = pt[(i - 1 + n) % n], b = pt[(i + 1) % n];
        CGFloat d1x = v.x - a.x, d1y = v.y - a.y, d2x = b.x - v.x, d2y = b.y - v.y;
        CGFloat l1 = hypot(d1x, d1y), l2 = hypot(d2x, d2y);
        if (l1 == 0 || l2 == 0) continue;
        d1x /= l1; d1y /= l1; d2x /= l2; d2y /= l2;
        CGFloat cross = d1x * d2y - d1y * d2x;
        if (fabs(cross) < 1e-12 && d1x * d2x + d1y * d2y > 0) continue;   /* straight on */
        if (st->join == JOIN_ROUND) { emit_circle(out, v, hw, tol); continue; }
        /* The outer side is opposite the turn. */
        CGFloat s = cross > 0 ? -1 : 1;
        CGPoint o1 = {v.x - d1y * hw * s, v.y + d1x * hw * s}, o2 = {v.x - d2y * hw * s, v.y + d2x * hw * s};
        if (st->join == JOIN_MITER) {
            CGFloat cos_half = sqrt((1 + d1x * d2x + d1y * d2y) / 2);
            if (cos_half > 1e-9 && 1 / cos_half <= st->miter_limit) {
                CGFloat mx = (o1.x + o2.x) / 2 - v.x, my = (o1.y + o2.y) / 2 - v.y, ml = hypot(mx, my);
                if (ml > 0) {
                    CGFloat k = hw / cos_half / ml;
                    CGPoint m = {v.x + mx * k, v.y + my * k};
                    CGPoint q[] = {v, o1, m, o2};
                    emit(out, q, 4);
                    continue;
                }
            }
        }
        CGPoint q[] = {v, o1, o2};
        emit(out, q, 3);
    }
    if (!closed && st->cap == CAP_ROUND) {
        emit_circle(out, pt[0], hw, tol);
        emit_circle(out, pt[n - 1], hw, tol);
    }
}

/* Split polylines by the dash pattern. */
static void dash(const struct cg_polys *in, const struct cg_stroke_style *st, struct cg_polys *out) {
    CGFloat total = 0;
    for (int i = 0; i < st->dash_count; i++) total += fabs(st->dashes[i]);
    for (int i = 0; i < in->count; i++) {
        const struct cg_poly *p = &in->poly[i];
        int n = p->count, segs = p->closed ? n : n - 1;
        /* Where the phase puts us in the pattern. */
        CGFloat phase = fmod(st->dash_phase, total);
        if (phase < 0) phase += total;
        int di = 0;
        while (phase >= fabs(st->dashes[di])) { phase -= fabs(st->dashes[di]); di = (di + 1) % st->dash_count; }
        CGFloat left = fabs(st->dashes[di]) - phase;
        bool on = (di % 2) == 0;
        struct cg_poly *cur = NULL;
        if (on && n) { cur = cg_polys_new_poly(out); if (cur) cg_poly_add(cur, p->pt[0]); }
        for (int s = 0; s < segs; s++) {
            CGPoint a = p->pt[s], b = p->pt[(s + 1) % n];
            CGFloat len = hypot(b.x - a.x, b.y - a.y), pos = 0;
            while (len - pos > left) {
                pos += left;
                CGPoint m = {a.x + (b.x - a.x) * pos / len, a.y + (b.y - a.y) * pos / len};
                if (on && cur) cg_poly_add(cur, m);
                on = !on;
                di = (di + 1) % st->dash_count;
                left = fabs(st->dashes[di]);
                if (on) { cur = cg_polys_new_poly(out); if (cur) cg_poly_add(cur, m); }
                else cur = NULL;
            }
            left -= len - pos;
            if (on && cur) cg_poly_add(cur, b);
        }
    }
}

void cg_stroke(const struct cg_polys *in, const struct cg_stroke_style *st, CGFloat tol, struct cg_polys *out) {
    struct cg_polys dashed = {0};
    bool use_dash = false;
    if (st->dash_count > 0) {
        CGFloat total = 0;
        for (int i = 0; i < st->dash_count; i++) total += fabs(st->dashes[i]);
        if (total > 0) { dash(in, st, &dashed); use_dash = true; }
    }
    const struct cg_polys *src = use_dash ? &dashed : in;
    for (int i = 0; i < src->count; i++) {
        const struct cg_poly *p = &src->poly[i];
        int n = p->count;
        bool closed = p->closed && !use_dash;
        if (closed && n > 1 && p->pt[0].x == p->pt[n - 1].x && p->pt[0].y == p->pt[n - 1].y) n--;
        if (n > 0) stroke_poly(p->pt, n, closed && n > 2, st, tol, out);
    }
    if (use_dash) cg_polys_free(&dashed);
}

/* ---- the CGPath API -------------------------------------------------------------- */

static struct cg_path *d_CGPathCreateMutable(void) { return cg_path_new(); }
DX_FN(CGPathCreateMutable);

static struct cg_path *copy_path(const struct cg_path *src, const CGAffineTransform *t) {
    if (!src) return NULL;
    struct cg_path *p = cg_path_new();
    if (p) cg_path_append(p, src, t);
    return p;
}

static struct cg_path *d_CGPathCreateCopy(const struct cg_path *p) { return copy_path(p, NULL); }
DX_FN(CGPathCreateCopy);
static struct cg_path *d_CGPathCreateMutableCopy(const struct cg_path *p) { return copy_path(p, NULL); }
DX_FN(CGPathCreateMutableCopy);
static struct cg_path *d_CGPathCreateCopyByTransformingPath(const struct cg_path *p, const CGAffineTransform *t) {
    return copy_path(p, t);
}
DX_FN(CGPathCreateCopyByTransformingPath);
static struct cg_path *d_CGPathCreateMutableCopyByTransformingPath(const struct cg_path *p, const CGAffineTransform *t) {
    return copy_path(p, t);
}
DX_FN(CGPathCreateMutableCopyByTransformingPath);

static struct cg_path *d_CGPathCreateWithRect(CGRect r, const CGAffineTransform *t) {
    struct cg_path *p = cg_path_new();
    if (p) cg_path_rect(p, r, t);
    return p;
}
DX_FN(CGPathCreateWithRect);

static struct cg_path *d_CGPathCreateWithEllipseInRect(CGRect r, const CGAffineTransform *t) {
    struct cg_path *p = cg_path_new();
    if (p) cg_path_ellipse(p, r, t);
    return p;
}
DX_FN(CGPathCreateWithEllipseInRect);

static struct cg_path *d_CGPathCreateWithRoundedRect(CGRect r, CGFloat w, CGFloat h, const CGAffineTransform *t) {
    struct cg_path *p = cg_path_new();
    if (p) cg_path_rounded_rect(p, r, w, h, t);
    return p;
}
DX_FN(CGPathCreateWithRoundedRect);

static struct cg_path *d_CGPathRetain(struct cg_path *p) { return cg_retain(p); }
DX_FN(CGPathRetain);
static void d_CGPathRelease(struct cg_path *p) { cg_release(p); }
DX_FN(CGPathRelease);
static bool d_CGPathEqualToPath(const struct cg_path *a, const struct cg_path *b) {
    return a == b || (a && b && path_equal(a, b));
}
DX_FN(CGPathEqualToPath);

static void d_CGPathMoveToPoint(struct cg_path *p, const CGAffineTransform *t, CGFloat x, CGFloat y) {
    if (p) cg_path_move(p, T(t, (CGPoint){x, y}));
}
DX_FN(CGPathMoveToPoint);
static void d_CGPathAddLineToPoint(struct cg_path *p, const CGAffineTransform *t, CGFloat x, CGFloat y) {
    if (p) cg_path_line(p, T(t, (CGPoint){x, y}));
}
DX_FN(CGPathAddLineToPoint);
static void d_CGPathAddQuadCurveToPoint(struct cg_path *p, const CGAffineTransform *t, CGFloat cx, CGFloat cy,
                                        CGFloat x, CGFloat y) {
    if (p) cg_path_quad(p, T(t, (CGPoint){cx, cy}), T(t, (CGPoint){x, y}));
}
DX_FN(CGPathAddQuadCurveToPoint);
static void d_CGPathAddCurveToPoint(struct cg_path *p, const CGAffineTransform *t, CGFloat c1x, CGFloat c1y,
                                    CGFloat c2x, CGFloat c2y, CGFloat x, CGFloat y) {
    if (p) cg_path_curve(p, T(t, (CGPoint){c1x, c1y}), T(t, (CGPoint){c2x, c2y}), T(t, (CGPoint){x, y}));
}
DX_FN(CGPathAddCurveToPoint);
static void d_CGPathCloseSubpath(struct cg_path *p) { if (p) cg_path_close(p); }
DX_FN(CGPathCloseSubpath);
static void d_CGPathAddRect(struct cg_path *p, const CGAffineTransform *t, CGRect r) { if (p) cg_path_rect(p, r, t); }
DX_FN(CGPathAddRect);
static void d_CGPathAddRects(struct cg_path *p, const CGAffineTransform *t, const CGRect *r, size_t n) {
    for (size_t i = 0; p && r && i < n; i++) cg_path_rect(p, r[i], t);
}
DX_FN(CGPathAddRects);
static void d_CGPathAddLines(struct cg_path *p, const CGAffineTransform *t, const CGPoint *pts, size_t n) {
    for (size_t i = 0; p && pts && i < n; i++) {
        if (i == 0) cg_path_move(p, T(t, pts[0]));
        else cg_path_line(p, T(t, pts[i]));
    }
}
DX_FN(CGPathAddLines);
static void d_CGPathAddEllipseInRect(struct cg_path *p, const CGAffineTransform *t, CGRect r) {
    if (p) cg_path_ellipse(p, r, t);
}
DX_FN(CGPathAddEllipseInRect);
static void d_CGPathAddRoundedRect(struct cg_path *p, const CGAffineTransform *t, CGRect r, CGFloat w, CGFloat h) {
    if (p) cg_path_rounded_rect(p, r, w, h, t);
}
DX_FN(CGPathAddRoundedRect);
static void d_CGPathAddArc(struct cg_path *p, const CGAffineTransform *t, CGFloat x, CGFloat y, CGFloat r,
                           CGFloat a0, CGFloat a1, bool clockwise) {
    if (p) cg_path_arc(p, x, y, r, a0, a1, clockwise, t);
}
DX_FN(CGPathAddArc);
static void d_CGPathAddRelativeArc(struct cg_path *p, const CGAffineTransform *t, CGFloat x, CGFloat y, CGFloat r,
                                   CGFloat a0, CGFloat delta) {
    if (p) cg_path_arc(p, x, y, r, a0, a0 + delta, delta < 0, t);
}
DX_FN(CGPathAddRelativeArc);
static void d_CGPathAddArcToPoint(struct cg_path *p, const CGAffineTransform *t, CGFloat x1, CGFloat y1,
                                  CGFloat x2, CGFloat y2, CGFloat r) {
    if (p) cg_path_arc_to(p, (CGPoint){x1, y1}, (CGPoint){x2, y2}, r, t);
}
DX_FN(CGPathAddArcToPoint);
static void d_CGPathAddPath(struct cg_path *p, const CGAffineTransform *t, const struct cg_path *src) {
    if (p) cg_path_append(p, src, t);
}
DX_FN(CGPathAddPath);

static bool d_CGPathIsEmpty(const struct cg_path *p) { return !p || p->count == 0; }
DX_FN(CGPathIsEmpty);
static bool d_CGPathIsRect(const struct cg_path *p, CGRect *rect) {
    if (!p || p->count < 4 || p->count > 6 || p->el[0].type != CG_MOVE) return false;
    for (int i = 1; i < 4; i++) if (p->el[i].type != CG_LINE) return false;
    CGPoint a = p->el[0].p[0], c = p->el[2].p[0];
    if (!(p->el[1].p[0].y == a.y && p->el[3].p[0].x == a.x && p->el[1].p[0].x == c.x && p->el[3].p[0].y == c.y))
        return false;
    if (rect) *rect = (CGRect){{fmin(a.x, c.x), fmin(a.y, c.y)}, {fabs(c.x - a.x), fabs(c.y - a.y)}};
    return true;
}
DX_FN(CGPathIsRect);
static CGPoint d_CGPathGetCurrentPoint(const struct cg_path *p) { return p && p->has_current ? p->current : (CGPoint){0, 0}; }
DX_FN(CGPathGetCurrentPoint);
static CGRect d_CGPathGetBoundingBox(const struct cg_path *p) {
    return p ? cg_path_bounds(p, true) : (CGRect){{INFINITY, INFINITY}, {0, 0}};
}
DX_FN(CGPathGetBoundingBox);
static CGRect d_CGPathGetPathBoundingBox(const struct cg_path *p) {
    return p ? cg_path_bounds(p, false) : (CGRect){{INFINITY, INFINITY}, {0, 0}};
}
DX_FN(CGPathGetPathBoundingBox);

/* Winding numbers over the flattened path. */
static bool d_CGPathContainsPoint(const struct cg_path *p, const CGAffineTransform *t, CGPoint pt, bool eo) {
    if (!p) return false;
    if (t) pt = cg_apply(cg_invert(*t), pt);
    struct cg_polys polys = {0};
    cg_flatten(p, 0.05, &polys);
    int wind = 0;
    for (int i = 0; i < polys.count; i++) {
        const struct cg_poly *q = &polys.poly[i];
        for (int k = 0; k < q->count; k++) {
            CGPoint a = q->pt[k], b = q->pt[(k + 1) % q->count];
            if ((a.y <= pt.y) != (b.y <= pt.y)) {
                CGFloat x = a.x + (pt.y - a.y) * (b.x - a.x) / (b.y - a.y);
                if (x > pt.x) wind += b.y > a.y ? 1 : -1;
            }
        }
    }
    cg_polys_free(&polys);
    return eo ? (wind & 1) : wind != 0;
}
DX_FN(CGPathContainsPoint);

/* CGPathElement: { type, points } where points has room for the element. */
struct cg_path_element { int type; CGPoint *points; };

static void d_CGPathApply(const struct cg_path *p, void *info, void (*fn)(void *, const struct cg_path_element *)) {
    for (int i = 0; p && fn && i < p->count; i++) {
        CGPoint pts[3];
        memcpy(pts, p->el[i].p, sizeof pts);
        struct cg_path_element e = {p->el[i].type, pts};
        fn(info, &e);
    }
}
DX_FN(CGPathApply);

/* The block form: a Blocks-runtime block taking the element. */
struct block { void *isa; int flags, reserved; void (*invoke)(struct block *, const struct cg_path_element *); };

static void d_CGPathApplyWithBlock(const struct cg_path *p, struct block *b) {
    for (int i = 0; p && b && i < p->count; i++) {
        CGPoint pts[3];
        memcpy(pts, p->el[i].p, sizeof pts);
        struct cg_path_element e = {p->el[i].type, pts};
        b->invoke(b, &e);
    }
}
DX_FN(CGPathApplyWithBlock);

/* The stroke's outline as a path (CGPathCreateCopyByStrokingPath). */
static struct cg_path *d_CGPathCreateCopyByStrokingPath(const struct cg_path *p, const CGAffineTransform *t,
                                                        CGFloat width, int cap, int join, CGFloat miter) {
    if (!p) return NULL;
    struct cg_polys flat = {0}, outline = {0};
    cg_flatten(p, 0.05, &flat);
    struct cg_stroke_style st = {width, miter, cap, join, NULL, 0, 0};
    cg_stroke(&flat, &st, 0.05, &outline);
    struct cg_path *r = cg_path_new();
    for (int i = 0; r && i < outline.count; i++) {
        for (int k = 0; k < outline.poly[i].count; k++) {
            CGPoint q = T(t, outline.poly[i].pt[k]);
            if (k == 0) cg_path_move(r, q); else cg_path_line(r, q);
        }
        cg_path_close(r);
    }
    cg_polys_free(&flat);
    cg_polys_free(&outline);
    return r;
}
DX_FN(CGPathCreateCopyByStrokingPath);

CF_TYPE_ID(CGPath, CF_CG_PATH);
