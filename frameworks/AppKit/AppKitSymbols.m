/* System symbol images (NSImage(systemSymbolName:), SwiftUI's
 * Image(systemName:)), drawn from their names: Apple's symbol artwork is
 * not ours to ship, so each name is read as the parts symbol names are
 * built from (a base glyph such as arrow, chevron, xmark or gearshape, a
 * direction, an enclosing circle or square, `fill`) and drawn as simple
 * strokes in the symbol's colour. Names with no known base get a small
 * outlined square. */
#import <AppKit/AppKit.h>
#include <math.h>
#include <string.h>

#define MAXTOK 12

struct sym {
    const char *tok[MAXTOK];
    int n;
    char buf[160];
};

static void parse(struct sym *s, const char *name) {
    strncpy(s->buf, name, sizeof s->buf - 1);
    s->buf[sizeof s->buf - 1] = 0;
    s->n = 0;
    for (char *save = NULL, *t = strtok_r(s->buf, ".", &save); t && s->n < MAXTOK; t = strtok_r(NULL, ".", &save))
        s->tok[s->n++] = t;
}
static int has(const struct sym *s, const char *t) {
    for (int i = 0; i < s->n; i++)
        if (!strcmp(s->tok[i], t)) return 1;
    return 0;
}
static int base_is(const struct sym *s, const char *t) { return s->n && !strcmp(s->tok[0], t); }

/* Paths are built in a unit square, y running down; `m` maps it into the
 * destination. */
struct pen {
    CGMutablePathRef stroke, fill;
    CGAffineTransform m;
};
static void mv(struct pen *p, CGFloat x, CGFloat y) { CGPathMoveToPoint(p->stroke, &p->m, x, y); }
static void ln(struct pen *p, CGFloat x, CGFloat y) { CGPathAddLineToPoint(p->stroke, &p->m, x, y); }
static void seg(struct pen *p, CGFloat x0, CGFloat y0, CGFloat x1, CGFloat y1) {
    mv(p, x0, y0);
    ln(p, x1, y1);
}
static void arc(struct pen *p, CGFloat cx, CGFloat cy, CGFloat r, CGFloat a0, CGFloat a1, bool cw) {
    CGPathMoveToPoint(p->stroke, &p->m, cx + r * cos(a0), cy + r * sin(a0));
    CGPathAddArc(p->stroke, &p->m, cx, cy, r, a0, a1, cw);
}
static void ring(struct pen *p, CGFloat cx, CGFloat cy, CGFloat r) {
    CGPathAddEllipseInRect(p->stroke, &p->m, CGRectMake(cx - r, cy - r, 2 * r, 2 * r));
}
static void dot(struct pen *p, CGFloat cx, CGFloat cy, CGFloat r) {
    CGPathAddEllipseInRect(p->fill, &p->m, CGRectMake(cx - r, cy - r, 2 * r, 2 * r));
}
static void box(struct pen *p, CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    CGPathAddRoundedRect(p->stroke, &p->m, CGRectMake(x, y, w, h), r, r);
}
static void tri(struct pen *p, CGFloat x0, CGFloat y0, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, bool filled) {
    CGMutablePathRef t = filled ? p->fill : p->stroke;
    CGPathMoveToPoint(t, &p->m, x0, y0);
    CGPathAddLineToPoint(t, &p->m, x1, y1);
    CGPathAddLineToPoint(t, &p->m, x2, y2);
    CGPathCloseSubpath(t);
}

/* Direction: angle of travel in the y-down square (0 = right). */
static int direction(const struct sym *s, CGFloat *angle) {
    int up = has(s, "up"), down = has(s, "down");
    int left = has(s, "left") || has(s, "backward"), right = has(s, "right") || has(s, "forward");
    if (up && right) *angle = -M_PI / 4;
    else if (up && left) *angle = -3 * M_PI / 4;
    else if (down && right) *angle = M_PI / 4;
    else if (down && left) *angle = 3 * M_PI / 4;
    else if (up) *angle = -M_PI / 2;
    else if (down) *angle = M_PI / 2;
    else if (left) *angle = M_PI;
    else if (right) *angle = 0;
    else return 0;
    return 1;
}
/* A segment through the centre along `a`, with an arrowhead at its end. */
static void arrow(struct pen *p, CGFloat a, CGFloat len) {
    CGFloat dx = cos(a), dy = sin(a);
    CGFloat x0 = 0.5 - dx * len / 2, y0 = 0.5 - dy * len / 2, x1 = 0.5 + dx * len / 2, y1 = 0.5 + dy * len / 2;
    seg(p, x0, y0, x1, y1);
    CGFloat h = len * 0.4;
    mv(p, x1 - h * cos(a - M_PI / 4), y1 - h * sin(a - M_PI / 4));
    ln(p, x1, y1);
    ln(p, x1 - h * cos(a + M_PI / 4), y1 - h * sin(a + M_PI / 4));
}
static void chevron(struct pen *p, CGFloat a, CGFloat cx, CGFloat cy, CGFloat size) {
    CGFloat tipx = cx + cos(a) * size * 0.25, tipy = cy + sin(a) * size * 0.25;
    mv(p, tipx - size * 0.5 * cos(a - M_PI / 4), tipy - size * 0.5 * sin(a - M_PI / 4));
    ln(p, tipx, tipy);
    ln(p, tipx - size * 0.5 * cos(a + M_PI / 4), tipy - size * 0.5 * sin(a + M_PI / 4));
}
/* A circular arrow: most of a circle, with a head at its end. */
static void circular(struct pen *p, bool clockwise, CGFloat r) {
    CGFloat a0 = clockwise ? -M_PI / 2 + 0.5 : -M_PI / 2 - 0.5, a1 = clockwise ? a0 + 5.2 : a0 - 5.2;
    arc(p, 0.5, 0.5, r, a0, a1, !clockwise);
    CGFloat ex = 0.5 + r * cos(a1), ey = 0.5 + r * sin(a1);
    CGFloat t = a1 + (clockwise ? M_PI / 2 : -M_PI / 2); /* direction of travel */
    CGFloat h = r * 0.55;
    mv(p, ex - h * cos(t - M_PI / 4), ey - h * sin(t - M_PI / 4));
    ln(p, ex, ey);
    ln(p, ex - h * cos(t + M_PI / 4), ey - h * sin(t + M_PI / 4));
}

/* The base glyph, in the unit square. Returns 0 for an unknown base. */
static int glyph(struct pen *p, const struct sym *s) {
    CGFloat a;
    const char *b = s->n ? s->tok[0] : "";
    if (!strcmp(b, "chevron")) {
        if (has(s, "up") && has(s, "down")) {
            chevron(p, -M_PI / 2, 0.5, 0.3, 0.5);
            chevron(p, M_PI / 2, 0.5, 0.7, 0.5);
        } else if (has(s, "forwardslash")) {
            chevron(p, M_PI, 0.22, 0.5, 0.5);
            chevron(p, 0, 0.78, 0.5, 0.5);
            seg(p, 0.58, 0.25, 0.42, 0.75);
        } else {
            if (!direction(s, &a)) a = 0;
            chevron(p, a, 0.5, 0.5, 0.75);
        }
        return 1;
    }
    if (!strcmp(b, "arrow") || !strcmp(b, "arrowshape")) {
        if (has(s, "clockwise") || has(s, "counterclockwise")) {
            circular(p, has(s, "clockwise"), 0.3);
        } else if (has(s, "2") || has(s, "circlepath")) {
            arc(p, 0.5, 0.5, 0.3, M_PI + 0.3, 2 * M_PI - 0.3, false);
            arc(p, 0.5, 0.5, 0.3, 0.3, M_PI - 0.3, false);
            chevron(p, M_PI / 2 + 0.2, 0.5 + 0.3 * cos(-0.3), 0.5 + 0.3 * sin(-0.3), 0.3);
            chevron(p, -M_PI / 2 + 0.2, 0.5 + 0.3 * cos(M_PI - 0.3), 0.5 + 0.3 * sin(M_PI - 0.3), 0.3);
        } else if (has(s, "uturn")) {
            /* Out along the top, round the far side, back along the bottom. */
            bool back = has(s, "backward") || has(s, "left");
            CGFloat d = back ? 1 : -1; /* the turn's side: right when heading back */
            mv(p, 0.5 - d * 0.28, 0.35);
            ln(p, 0.5 + d * 0.1, 0.35);
            CGPathAddArc(p->stroke, &p->m, 0.5 + d * 0.1, 0.52, 0.17, -M_PI / 2, M_PI / 2, !back);
            ln(p, 0.5 - d * 0.1, 0.69);
            chevron(p, back ? M_PI : 0, 0.5 - d * 0.28, 0.35, 0.3);
        } else if (has(s, "and")) {
            /* arrow.up.and.down, arrow.left.and.right and the like: both ways. */
            if (has(s, "up") || has(s, "down")) {
                arrow(p, -M_PI / 2, 0.75);
                chevron(p, M_PI / 2, 0.5, 0.82, 0.32);
            }
            if (has(s, "left") || has(s, "right")) {
                arrow(p, 0, 0.75);
                chevron(p, M_PI, 0.18, 0.5, 0.32);
            }
        } else if (has(s, "branch")) {
            seg(p, 0.35, 0.85, 0.35, 0.15);
            arc(p, 0.65, 0.3, 0.12, 0, M_PI * 2, false);
            mv(p, 0.65, 0.42);
            CGPathAddQuadCurveToPoint(p->stroke, &p->m, 0.65, 0.6, 0.35, 0.65);
        } else {
            if (!direction(s, &a)) a = 0;
            arrow(p, a, 0.7);
            if (has(s, "line")) {
                CGFloat x = 0.5 + cos(a) * 0.4, y = 0.5 + sin(a) * 0.4;
                seg(p, x - sin(a) * 0.3, y + cos(a) * 0.3, x + sin(a) * 0.3, y - cos(a) * 0.3);
            }
        }
        return 1;
    }
    if (!strcmp(b, "xmark")) {
        seg(p, 0.25, 0.25, 0.75, 0.75);
        seg(p, 0.75, 0.25, 0.25, 0.75);
        return 1;
    }
    if (!strcmp(b, "plus")) {
        seg(p, 0.5, 0.18, 0.5, 0.82);
        seg(p, 0.18, 0.5, 0.82, 0.5);
        return 1;
    }
    if (!strcmp(b, "minus")) {
        seg(p, 0.18, 0.5, 0.82, 0.5);
        return 1;
    }
    if (!strcmp(b, "checkmark")) {
        mv(p, 0.2, 0.52);
        ln(p, 0.42, 0.74);
        ln(p, 0.8, 0.28);
        return 1;
    }
    if (!strcmp(b, "ellipsis")) {
        for (int i = 0; i < 3; i++) dot(p, 0.2 + 0.3 * i, 0.5, 0.075);
        return 1;
    }
    if (!strcmp(b, "magnifyingglass")) {
        ring(p, 0.43, 0.43, 0.25);
        seg(p, 0.61, 0.61, 0.82, 0.82);
        return 1;
    }
    if (!strcmp(b, "gear") || !strcmp(b, "gearshape")) {
        ring(p, 0.5, 0.5, 0.26);
        ring(p, 0.5, 0.5, 0.1);
        for (int i = 0; i < 8; i++) {
            CGFloat t = i * M_PI / 4;
            seg(p, 0.5 + 0.26 * cos(t), 0.5 + 0.26 * sin(t), 0.5 + 0.38 * cos(t), 0.5 + 0.38 * sin(t));
        }
        return 1;
    }
    if (!strcmp(b, "trash")) {
        seg(p, 0.2, 0.25, 0.8, 0.25);
        seg(p, 0.4, 0.25, 0.42, 0.15);
        seg(p, 0.6, 0.25, 0.58, 0.15);
        seg(p, 0.42, 0.15, 0.58, 0.15);
        mv(p, 0.27, 0.25);
        ln(p, 0.32, 0.85);
        ln(p, 0.68, 0.85);
        ln(p, 0.73, 0.25);
        return 1;
    }
    if (!strcmp(b, "doc") || !strcmp(b, "document")) {
        mv(p, 0.25, 0.12);
        ln(p, 0.58, 0.12);
        ln(p, 0.75, 0.3);
        ln(p, 0.75, 0.88);
        ln(p, 0.25, 0.88);
        CGPathCloseSubpath(p->stroke);
        if (has(s, "text") || has(s, "plaintext"))
            for (int i = 0; i < 3; i++) seg(p, 0.35, 0.45 + 0.13 * i, 0.65, 0.45 + 0.13 * i);
        if (has(s, "on")) box(p, 0.15, 0.22, 0.5, 0.7, 0.05);
        return 1;
    }
    if (!strcmp(b, "folder")) {
        mv(p, 0.12, 0.28);
        ln(p, 0.4, 0.28);
        ln(p, 0.47, 0.36);
        ln(p, 0.88, 0.36);
        ln(p, 0.88, 0.8);
        ln(p, 0.12, 0.8);
        CGPathCloseSubpath(p->stroke);
        return 1;
    }
    if (!strcmp(b, "terminal") || !strcmp(b, "apple") && has(s, "terminal")) {
        box(p, 0.1, 0.18, 0.8, 0.64, 0.1);
        chevron(p, 0, 0.3, 0.45, 0.25);
        seg(p, 0.45, 0.62, 0.65, 0.62);
        return 1;
    }
    if (!strcmp(b, "sidebar")) {
        box(p, 0.1, 0.2, 0.8, 0.6, 0.08);
        CGFloat x = has(s, "right") || has(s, "trailing") ? 0.65 : 0.35;
        seg(p, x, 0.2, x, 0.8);
        return 1;
    }
    if (!strcmp(b, "rectangle") || !strcmp(b, "macwindow") || !strcmp(b, "uiwindow") || !strcmp(b, "menubar")) {
        box(p, 0.1, 0.22, 0.8, 0.56, 0.08);
        if (has(s, "split")) seg(p, 0.5, 0.22, 0.5, 0.78);
        if (!strcmp(b, "macwindow") || !strcmp(b, "menubar")) seg(p, 0.1, 0.36, 0.9, 0.36);
        if (has(s, "stack") || has(s, "on")) box(p, 0.18, 0.12, 0.8, 0.56, 0.08);
        return 1;
    }
    if (!strcmp(b, "square") && (has(s, "and") && has(s, "arrow"))) {
        /* square.and.arrow.up (share) and .down (save) */
        mv(p, 0.35, 0.4);
        ln(p, 0.25, 0.4);
        ln(p, 0.25, 0.88);
        ln(p, 0.75, 0.88);
        ln(p, 0.75, 0.4);
        ln(p, 0.65, 0.4);
        bool upw = has(s, "up");
        seg(p, 0.5, 0.1, 0.5, 0.62);
        chevron(p, upw ? -M_PI / 2 : M_PI / 2, 0.5, upw ? 0.18 : 0.55, 0.32);
        return 1;
    }
    if (!strcmp(b, "exclamationmark")) {
        if (has(s, "triangle")) {
            tri(p, 0.5, 0.12, 0.9, 0.85, 0.1, 0.85, false);
            seg(p, 0.5, 0.38, 0.5, 0.6);
            dot(p, 0.5, 0.72, 0.045);
        } else {
            seg(p, 0.5, 0.2, 0.5, 0.6);
            dot(p, 0.5, 0.78, 0.06);
        }
        return 1;
    }
    if (!strcmp(b, "questionmark")) {
        arc(p, 0.5, 0.36, 0.17, M_PI, M_PI * 2.35, false);
        ln(p, 0.5, 0.6);
        dot(p, 0.5, 0.8, 0.06);
        return 1;
    }
    if (!strcmp(b, "info")) {
        dot(p, 0.5, 0.25, 0.06);
        seg(p, 0.5, 0.42, 0.5, 0.8);
        return 1;
    }
    if (!strcmp(b, "line") && has(s, "horizontal")) {
        int k = has(s, "3") ? 3 : 2;
        for (int i = 0; i < k; i++) seg(p, 0.2, 0.3 + 0.4 * i / (k - 1), 0.8, 0.3 + 0.4 * i / (k - 1));
        return 1;
    }
    if (!strcmp(b, "list")) {
        for (int i = 0; i < 3; i++) {
            dot(p, 0.2, 0.3 + 0.2 * i, 0.05);
            seg(p, 0.35, 0.3 + 0.2 * i, 0.82, 0.3 + 0.2 * i);
        }
        return 1;
    }
    if (!strcmp(b, "play")) {
        tri(p, 0.3, 0.2, 0.8, 0.5, 0.3, 0.8, has(s, "fill"));
        return 1;
    }
    if (!strcmp(b, "pause")) {
        seg(p, 0.38, 0.22, 0.38, 0.78);
        seg(p, 0.62, 0.22, 0.62, 0.78);
        return 1;
    }
    if (!strcmp(b, "stop")) {
        box(p, 0.25, 0.25, 0.5, 0.5, 0.05);
        return 1;
    }
    if (!strcmp(b, "bolt")) {
        mv(p, 0.58, 0.1);
        ln(p, 0.28, 0.55);
        ln(p, 0.5, 0.55);
        ln(p, 0.42, 0.9);
        ln(p, 0.72, 0.45);
        ln(p, 0.5, 0.45);
        CGPathCloseSubpath(p->stroke);
        return 1;
    }
    if (!strcmp(b, "clock")) {
        ring(p, 0.5, 0.5, 0.36);
        mv(p, 0.5, 0.28);
        ln(p, 0.5, 0.5);
        ln(p, 0.66, 0.6);
        return 1;
    }
    if (!strcmp(b, "globe") || !strcmp(b, "network")) {
        ring(p, 0.5, 0.5, 0.36);
        CGPathAddEllipseInRect(p->stroke, &p->m, CGRectMake(0.34, 0.14, 0.32, 0.72));
        seg(p, 0.14, 0.5, 0.86, 0.5);
        return 1;
    }
    if (!strcmp(b, "lock")) {
        box(p, 0.25, 0.45, 0.5, 0.4, 0.06);
        mv(p, 0.35, 0.45);
        ln(p, 0.35, 0.32);
        CGPathAddArc(p->stroke, &p->m, 0.5, 0.32, 0.15, M_PI, 2 * M_PI, false);
        if (!has(s, "open")) ln(p, 0.65, 0.45);
        return 1;
    }
    if (!strcmp(b, "link")) {
        box(p, 0.12, 0.38, 0.42, 0.24, 0.12);
        box(p, 0.46, 0.38, 0.42, 0.24, 0.12);
        return 1;
    }
    if (!strcmp(b, "bell")) {
        mv(p, 0.2, 0.72);
        ln(p, 0.8, 0.72);
        mv(p, 0.27, 0.72);
        CGPathAddCurveToPoint(p->stroke, &p->m, 0.3, 0.2, 0.7, 0.2, 0.73, 0.72);
        dot(p, 0.5, 0.82, 0.06);
        return 1;
    }
    if (!strcmp(b, "person")) {
        ring(p, 0.5, 0.33, 0.15);
        arc(p, 0.5, 0.85, 0.3, M_PI, 2 * M_PI, false);
        return 1;
    }
    if (!strcmp(b, "house")) {
        mv(p, 0.15, 0.5);
        ln(p, 0.5, 0.18);
        ln(p, 0.85, 0.5);
        mv(p, 0.25, 0.42);
        ln(p, 0.25, 0.85);
        ln(p, 0.75, 0.85);
        ln(p, 0.75, 0.42);
        return 1;
    }
    if (!strcmp(b, "pencil") || !strcmp(b, "square") && has(s, "pencil")) {
        mv(p, 0.25, 0.75);
        ln(p, 0.3, 0.58);
        ln(p, 0.66, 0.22);
        ln(p, 0.78, 0.34);
        ln(p, 0.42, 0.7);
        CGPathCloseSubpath(p->stroke);
        return 1;
    }
    if (!strcmp(b, "star")) {
        mv(p, 0.5, 0.12);
        for (int i = 1; i <= 10; i++) {
            CGFloat t = -M_PI / 2 + i * M_PI / 5, r = i % 2 ? 0.17 : 0.38;
            ln(p, 0.5 + r * cos(t), 0.53 + r * sin(t));
        }
        return 1;
    }
    if (!strcmp(b, "power")) {
        arc(p, 0.5, 0.52, 0.3, -M_PI / 2 + 0.6, 3 * M_PI / 2 - 0.6, false);
        seg(p, 0.5, 0.12, 0.5, 0.48);
        return 1;
    }
    if (!strcmp(b, "character") || !strcmp(b, "textformat") || !strcmp(b, "text")) {
        seg(p, 0.5, 0.2, 0.5, 0.8);
        seg(p, 0.38, 0.2, 0.62, 0.2);
        seg(p, 0.38, 0.8, 0.62, 0.8);
        return 1;
    }
    if (!strcmp(b, "keyboard") || !strcmp(b, "command")) {
        box(p, 0.1, 0.28, 0.8, 0.44, 0.06);
        for (int i = 0; i < 4; i++) dot(p, 0.25 + 0.17 * i, 0.42, 0.035);
        seg(p, 0.3, 0.58, 0.7, 0.58);
        return 1;
    }
    if (!strcmp(b, "circle") && has(s, "lefthalf")) {
        ring(p, 0.5, 0.5, 0.36);
        CGPathAddArc(p->fill, &p->m, 0.5, 0.5, 0.36, M_PI / 2, 3 * M_PI / 2, false);
        CGPathCloseSubpath(p->fill);
        return 1;
    }
    if (!strcmp(b, "circle") || !strcmp(b, "square") || !strcmp(b, "app")) {
        /* The bare shape; its fill comes from draw_symbol. */
        return 2;
    }
    return 0;
}

static void stroke_and_fill(CGContextRef c, struct pen *p, CGFloat width) {
    CGContextSetLineWidth(c, width);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetLineJoin(c, kCGLineJoinRound);
    CGContextAddPath(c, p->stroke);
    CGContextStrokePath(c);
    CGContextAddPath(c, p->fill);
    CGContextFillPath(c);
}

/* Draws the symbol `name` into (x, y, w, h) of `c` in the given colour;
 * `flipped` says whether the context's y runs down. Exported for SwiftUI. */
__attribute__((visibility("default"))) void bn_draw_symbol(CGContextRef c, const char *name, double x, double y,
                                                         double w, double h, double r, double g, double b, double a,
                                                         int flipped) {
    if (!c || !name || w <= 0 || h <= 0) return;
    struct sym s;
    parse(&s, name);
    CGFloat side = fmin(w, h), ox = x + (w - side) / 2, oy = y + (h - side) / 2;
    CGAffineTransform unit = flipped ? CGAffineTransformMake(side, 0, 0, side, ox, oy)
                                     : CGAffineTransformMake(side, 0, 0, -side, ox, oy + side);
    bool filled = has(&s, "fill");
    int circled = !base_is(&s, "circle") && has(&s, "circle");
    int squared = !base_is(&s, "square") && !base_is(&s, "rectangle") && has(&s, "square");
    /* square.and.arrow.* and square.and.pencil draw their own square */
    bool own_square = base_is(&s, "square") && (has(&s, "arrow") || has(&s, "pencil"));
    if (base_is(&s, "arrow") && has(&s, "and") && has(&s, "square")) squared = 0;

    CGContextSaveGState(c);
    CGContextSetRGBStrokeColor(c, r, g, b, a);
    CGContextSetRGBFillColor(c, r, g, b, a);
    CGFloat lw = fmax(1, side * 0.085);

    struct pen container = {CGPathCreateMutable(), CGPathCreateMutable(), unit};
    if (circled || base_is(&s, "circle")) {
        CGRect e = CGRectMake(0.08, 0.08, 0.84, 0.84);
        CGPathAddEllipseInRect(filled ? container.fill : container.stroke, &unit, e);
    } else if (squared || (base_is(&s, "square") && !own_square) || base_is(&s, "app")) {
        CGPathAddRoundedRect(filled ? container.fill : container.stroke, &unit, CGRectMake(0.1, 0.1, 0.8, 0.8), 0.18,
                             0.18);
    }
    bool boxed = !CGPathIsEmpty(container.stroke) || !CGPathIsEmpty(container.fill);

    /* The glyph, smaller inside a container. */
    CGAffineTransform inner = unit;
    if (boxed && !(base_is(&s, "circle") || (base_is(&s, "square") && !own_square) || base_is(&s, "app")))
        inner = CGAffineTransformConcat(CGAffineTransformMake(0.56, 0, 0, 0.56, 0.22, 0.22), unit);
    struct pen glyphpen = {CGPathCreateMutable(), CGPathCreateMutable(), inner};
    int known = glyph(&glyphpen, &s);
    if (!known && !boxed) {
        /* Unknown: a small outlined square, quieter than a filled block. */
        CGPathAddRoundedRect(glyphpen.stroke, &unit, CGRectMake(0.22, 0.22, 0.56, 0.56), 0.1, 0.1);
    }

    if (boxed && filled) {
        /* A filled container with the glyph knocked out of it. */
        CGContextBeginTransparencyLayer(c, NULL);
        stroke_and_fill(c, &container, lw);
        CGContextSetBlendMode(c, kCGBlendModeClear);
        stroke_and_fill(c, &glyphpen, lw * 0.9);
        CGContextEndTransparencyLayer(c);
    } else {
        stroke_and_fill(c, &container, lw);
        stroke_and_fill(c, &glyphpen, boxed ? lw * 0.9 : lw);
    }
    CGPathRelease(container.stroke);
    CGPathRelease(container.fill);
    CGPathRelease(glyphpen.stroke);
    CGPathRelease(glyphpen.fill);
    CGContextRestoreGState(c);
}
