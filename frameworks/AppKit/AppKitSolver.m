/* A Cassowary linear constraint solver (after Kiwi's algorithm), in C, for
 * Auto Layout (AppKitLayout.m). The tableau is built afresh for each
 * layout pass: constraints are added one by one, each made a row in terms
 * of the non-basic symbols (slack and error symbols for inequalities and
 * non-required strengths, dummies for required equalities), solved for a
 * subject (or brought in through an artificial variable), and the
 * objective (the weighted errors) is minimised by the primal simplex. A
 * required constraint that cannot be satisfied is dropped, as AppKit
 * breaks one when constraints conflict. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "AppKitSolver.h"

enum { SYM_INVALID, SYM_EXTERNAL, SYM_SLACK, SYM_ERROR, SYM_DUMMY };

typedef struct {
    int n, cap;
    int *sym;
    double *coef;
    double constant;
} Row;

struct bn_solver {
    int nsyms, capsyms;
    unsigned char *type;     /* per symbol */
    Row **rows;              /* basic symbol -> its row, or NULL */
    Row objective;
    Row *artificial;
    int nvars;
};

#define EPS 1.0e-8
static int near_zero(double v) { return fabs(v) < EPS; }

/* ---- rows ---- */

static void row_free(Row *r) {
    free(r->sym);
    free(r->coef);
    r->sym = NULL;
    r->coef = NULL;
    r->n = r->cap = 0;
}
static Row *row_new(double constant) {
    Row *r = calloc(1, sizeof *r);
    r->constant = constant;
    return r;
}
static Row *row_copy(const Row *s) {
    Row *r = calloc(1, sizeof *r);
    r->constant = s->constant;
    r->n = r->cap = s->n;
    if (s->n) {
        r->sym = malloc(sizeof(int) * s->n);
        r->coef = malloc(sizeof(double) * s->n);
        memcpy(r->sym, s->sym, sizeof(int) * s->n);
        memcpy(r->coef, s->coef, sizeof(double) * s->n);
    }
    return r;
}
static int row_find(const Row *r, int sym) {
    for (int i = 0; i < r->n; i++) if (r->sym[i] == sym) return i;
    return -1;
}
static double row_coef(const Row *r, int sym) {
    int i = row_find(r, sym);
    return i < 0 ? 0 : r->coef[i];
}
static void row_remove_at(Row *r, int i) {
    r->n--;
    r->sym[i] = r->sym[r->n];
    r->coef[i] = r->coef[r->n];
}
static void row_remove(Row *r, int sym) {
    int i = row_find(r, sym);
    if (i >= 0) row_remove_at(r, i);
}
/* coef * sym added to the row (dropping it when it cancels). */
static void row_insert_sym(Row *r, int sym, double coef) {
    int i = row_find(r, sym);
    if (i >= 0) {
        r->coef[i] += coef;
        if (near_zero(r->coef[i])) row_remove_at(r, i);
        return;
    }
    if (near_zero(coef)) return;
    if (r->n == r->cap) {
        r->cap = r->cap ? r->cap * 2 : 8;
        r->sym = realloc(r->sym, sizeof(int) * r->cap);
        r->coef = realloc(r->coef, sizeof(double) * r->cap);
    }
    r->sym[r->n] = sym;
    r->coef[r->n] = coef;
    r->n++;
}
/* coef * other added to the row. */
static void row_insert_row(Row *r, const Row *o, double coef) {
    r->constant += o->constant * coef;
    for (int i = 0; i < o->n; i++) row_insert_sym(r, o->sym[i], o->coef[i] * coef);
}
static void row_reverse(Row *r) {
    r->constant = -r->constant;
    for (int i = 0; i < r->n; i++) r->coef[i] = -r->coef[i];
}
/* The row, an expression equal to zero, solved for sym. */
static void row_solve_for(Row *r, int sym) {
    double c = -1.0 / row_coef(r, sym);
    row_remove(r, sym);
    r->constant *= c;
    for (int i = 0; i < r->n; i++) r->coef[i] *= c;
}
static void row_solve_for_pair(Row *r, int lhs, int rhs) {
    row_insert_sym(r, lhs, -1.0);
    row_solve_for(r, rhs);
}
static void row_substitute(Row *r, int sym, const Row *by) {
    int i = row_find(r, sym);
    if (i < 0) return;
    double c = r->coef[i];
    row_remove_at(r, i);
    row_insert_row(r, by, c);
}

/* ---- the solver ---- */

static int new_symbol(bn_solver *s, unsigned char type) {
    if (s->nsyms == s->capsyms) {
        int cap = s->capsyms ? s->capsyms * 2 : 64;
        s->type = realloc(s->type, cap);
        s->rows = realloc(s->rows, sizeof(Row *) * cap);
        for (int i = s->capsyms; i < cap; i++) s->rows[i] = NULL;
        s->capsyms = cap;
    }
    s->type[s->nsyms] = type;
    return s->nsyms++;
}

bn_solver *bn_solver_new(void) {
    bn_solver *s = calloc(1, sizeof *s);
    new_symbol(s, SYM_INVALID);          /* symbol 0 stands for none */
    return s;
}

void bn_solver_free(bn_solver *s) {
    if (!s) return;
    for (int i = 0; i < s->nsyms; i++)
        if (s->rows[i]) { row_free(s->rows[i]); free(s->rows[i]); }
    row_free(&s->objective);
    free(s->type);
    free(s->rows);
    free(s);
}

int bn_solver_variable(bn_solver *s) {
    s->nvars++;
    return new_symbol(s, SYM_EXTERNAL);
}

double bn_solver_value(bn_solver *s, int var) {
    if (var <= 0 || var >= s->nsyms) return 0;
    return s->rows[var] ? s->rows[var]->constant : 0;
}

static void substitute(bn_solver *s, int sym, const Row *row) {
    for (int i = 0; i < s->nsyms; i++)
        if (s->rows[i] && s->rows[i] != row) row_substitute(s->rows[i], sym, row);
    row_substitute(&s->objective, sym, row);
    if (s->artificial) row_substitute(s->artificial, sym, row);
}

/* The entering symbol: one with a negative cost in the objective. */
static int entering_symbol(bn_solver *s, const Row *objective) {
    for (int i = 0; i < objective->n; i++)
        if (s->type[objective->sym[i]] != SYM_DUMMY && objective->coef[i] < 0) return objective->sym[i];
    return 0;
}

/* The basic symbol to leave: the minimum ratio among restricted rows. */
static int leaving_symbol(bn_solver *s, int entering) {
    double best = INFINITY;
    int found = 0;
    for (int i = 1; i < s->nsyms; i++) {
        Row *r = s->rows[i];
        if (!r || s->type[i] == SYM_EXTERNAL) continue;
        double c = row_coef(r, entering);
        if (c < 0) {
            double ratio = -r->constant / c;
            if (ratio < best) { best = ratio; found = i; }
        }
    }
    return found;
}

static void optimize(bn_solver *s, Row *objective) {
    for (int guard = 0; guard < 100000; guard++) {
        int entering = entering_symbol(s, objective);
        if (!entering) return;
        int leaving = leaving_symbol(s, entering);
        if (!leaving) return;                 /* unbounded: leave as is */
        Row *row = s->rows[leaving];
        s->rows[leaving] = NULL;
        row_solve_for_pair(row, leaving, entering);
        substitute(s, entering, row);
        s->rows[entering] = row;
    }
}

static int any_pivotable(bn_solver *s, const Row *r) {
    for (int i = 0; i < r->n; i++) {
        unsigned char t = s->type[r->sym[i]];
        if (t == SYM_SLACK || t == SYM_ERROR) return r->sym[i];
    }
    return 0;
}

static int add_with_artificial(bn_solver *s, Row *row) {
    int art = new_symbol(s, SYM_SLACK);
    s->rows[art] = row_copy(row);
    s->artificial = row_copy(row);
    optimize(s, s->artificial);
    int ok = near_zero(s->artificial->constant);
    row_free(s->artificial);
    free(s->artificial);
    s->artificial = NULL;
    if (s->rows[art]) {
        Row *r = s->rows[art];
        s->rows[art] = NULL;
        if (r->n == 0) {
            row_free(r);
            free(r);
            row_free(row);
            free(row);
            return ok;
        }
        int entering = any_pivotable(s, r);
        if (!entering) {
            row_free(r);
            free(r);
            row_free(row);
            free(row);
            return 0;
        }
        row_solve_for_pair(r, art, entering);
        substitute(s, entering, r);
        s->rows[entering] = r;
    }
    for (int i = 0; i < s->nsyms; i++) if (s->rows[i]) row_remove(s->rows[i], art);
    row_remove(&s->objective, art);
    row_free(row);
    free(row);
    return ok;
}

int bn_solver_add(bn_solver *s, const int *vars, const double *coefs, int n, double constant, int relation,
                  double strength) {
    int required = strength >= BN_STRENGTH_REQUIRED;
    Row *row = row_new(constant);
    for (int i = 0; i < n; i++) {
        if (near_zero(coefs[i])) continue;
        Row *basic = s->rows[vars[i]];
        if (basic) row_insert_row(row, basic, coefs[i]);
        else row_insert_sym(row, vars[i], coefs[i]);
    }
    int marker = 0, other = 0;
    if (relation != BN_EQ) {
        /* expr <= 0: expr + slack = 0; expr >= 0: expr - slack = 0. */
        double c = relation == BN_LE ? 1.0 : -1.0;
        marker = new_symbol(s, SYM_SLACK);
        row_insert_sym(row, marker, c);
        if (!required) {
            other = new_symbol(s, SYM_ERROR);
            row_insert_sym(row, other, -c);
            row_insert_sym(&s->objective, other, strength);
        }
    } else if (!required) {
        marker = new_symbol(s, SYM_ERROR);
        other = new_symbol(s, SYM_ERROR);
        row_insert_sym(row, marker, -1.0);
        row_insert_sym(row, other, 1.0);
        row_insert_sym(&s->objective, marker, strength);
        row_insert_sym(&s->objective, other, strength);
    } else {
        marker = new_symbol(s, SYM_DUMMY);
        row_insert_sym(row, marker, 1.0);
    }
    if (row->constant < 0) row_reverse(row);

    /* The subject: an external symbol, else a negative marker or other. */
    int subject = 0;
    for (int i = 0; i < row->n && !subject; i++)
        if (s->type[row->sym[i]] == SYM_EXTERNAL) subject = row->sym[i];
    if (!subject && marker && (s->type[marker] == SYM_SLACK || s->type[marker] == SYM_ERROR) &&
        row_coef(row, marker) < 0)
        subject = marker;
    if (!subject && other && (s->type[other] == SYM_SLACK || s->type[other] == SYM_ERROR) &&
        row_coef(row, other) < 0)
        subject = other;

    if (!subject) {
        int all_dummies = 1;
        for (int i = 0; i < row->n; i++) if (s->type[row->sym[i]] != SYM_DUMMY) all_dummies = 0;
        if (all_dummies) {
            int ok = near_zero(row->constant);
            row_free(row);
            free(row);
            return ok;                       /* satisfied already, or unsatisfiable */
        }
        if (!add_with_artificial(s, row)) return 0;
    } else {
        row_solve_for(row, subject);
        substitute(s, subject, row);
        s->rows[subject] = row;
    }
    optimize(s, &s->objective);
    return 1;
}
