/* A Cassowary constraint solver for Auto Layout (AppKitSolver.m). */
#ifndef BITTEN_APPKIT_SOLVER_H
#define BITTEN_APPKIT_SOLVER_H

typedef struct bn_solver bn_solver;
enum { BN_LE = -1, BN_EQ = 0, BN_GE = 1 };
/* Strengths: priorities below 1000 map below this. */
#define BN_STRENGTH_REQUIRED 1.0e30

bn_solver *bn_solver_new(void);
void bn_solver_free(bn_solver *s);
/* A new variable (its value is 0 until constrained). */
int bn_solver_variable(bn_solver *s);
/* sum(coefs[i] * vars[i]) + constant  relation  0, at a strength.
 * Returns 0 when a required constraint cannot be satisfied (it is
 * dropped). */
int bn_solver_add(bn_solver *s, const int *vars, const double *coefs, int n, double constant, int relation,
                  double strength);
double bn_solver_value(bn_solver *s, int var);
#endif
