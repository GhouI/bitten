/* Extended libm imports used by the Intel macOS build of jq. */
#include "darwin.h"

double erf(double), erfc(double), fdim(double, double);
double asinh(double), acosh(double), atanh(double);
double j0(double), j1(double), jn(int, double), y0(double), y1(double), yn(int, double);
double lgamma(double), lgamma_r(double, int *), tgamma(double), logb(double);
double nextafter(double, double), nexttoward(double, long double);
double scalb(double, double), scalbln(double, long);

int main(void) {
    int sign = 0;
    CHECK(erf(0) == 0 && erfc(0) == 1 && fdim(5, 2) == 3);
    CHECK(asinh(0) == 0 && acosh(1) == 0 && atanh(0) == 0);
    CHECK(j0(0) == 1 && j1(0) == 0 && jn(2, 0) == 0);
    CHECK(yn(0, 1) == y0(1) && yn(1, 1) == y1(1));
    CHECK(lgamma(1) == 0 && lgamma_r(1, &sign) == 0 && sign == 1);
    CHECK(tgamma(5) == 24 && logb(8) == 3);
    CHECK(nextafter(1, 2) == 0x1.0000000000001p0);
    CHECK(nexttoward(1, 2.0L) == 0x1.0000000000001p0);
    CHECK(scalb(1.5, 2) == 6 && scalbln(1.5, -2L) == 0.375);
    puts("libm extensions ok");
    return 0;
}
