/* bitten SDK: <math.h>. */
#ifndef BITTEN_MATH_H
#define BITTEN_MATH_H
#include <sys/cdefs.h>

#define HUGE_VAL __builtin_huge_val()
#define HUGE_VALF __builtin_huge_valf()
#define INFINITY __builtin_inff()
#define NAN __builtin_nanf("")
#define FP_NAN 1
#define FP_INFINITE 2
#define FP_ZERO 3
#define FP_NORMAL 4
#define FP_SUBNORMAL 5
#define fpclassify(x) __builtin_fpclassify(FP_NAN, FP_INFINITE, FP_NORMAL, FP_SUBNORMAL, FP_ZERO, (x))
#define isnan(x) __builtin_isnan(x)
#define isinf(x) __builtin_isinf(x)
#define isfinite(x) __builtin_isfinite(x)
#define isnormal(x) __builtin_isnormal(x)
#define signbit(x) __builtin_signbit(x)

#define M_E 2.71828182845904523536028747135266250
#define M_LOG2E 1.44269504088896340735992468100189214
#define M_LOG10E 0.434294481903251827651128918916605082
#define M_LN2 0.693147180559945309417232121458176568
#define M_LN10 2.30258509299404568401799145468436421
#define M_PI 3.14159265358979323846264338327950288
#define M_PI_2 1.57079632679489661923132169163975144
#define M_PI_4 0.785398163397448309615660845819875721
#define M_1_PI 0.318309886183790671537767526745028724
#define M_2_PI 0.636619772367581343075535053490057448
#define M_2_SQRTPI 1.12837916709551257389615890312154517
#define M_SQRT2 1.41421356237309504880168872420969808
#define M_SQRT1_2 0.707106781186547524400844362104849039

__BEGIN_DECLS
double acos(double);
double asin(double);
double atan(double);
double atan2(double, double);
float atan2f(float, float);
double cos(double);
float cosf(float);
double sin(double);
float sinf(float);
double tan(double);
float tanf(float);
double cosh(double);
double sinh(double);
double tanh(double);
double exp(double);
float expf(float);
double exp2(double);
double expm1(double);
double log(double);
float logf(float);
double log10(double);
float log10f(float);
double log2(double);
float log2f(float);
double log1p(double);
double pow(double, double);
float powf(float, float);
double sqrt(double);
float sqrtf(float);
long double sqrtl(long double);
double cbrt(double);
double hypot(double, double);
float hypotf(float, float);
double fabs(double);
float fabsf(float);
long double fabsl(long double);
double ceil(double);
float ceilf(float);
long double ceill(long double);
double floor(double);
float floorf(float);
long double floorl(long double);
double round(double);
float roundf(float);
long double roundl(long double);
double trunc(double);
float truncf(float);
long double truncl(long double);
double rint(double);
float rintf(float);
long double rintl(long double);
double nearbyint(double);
float nearbyintf(float);
long lrint(double);
long lround(double);
long lroundf(float);
long long llround(double);
double fmod(double, double);
float fmodf(float, float);
long double fmodl(long double, long double);
double remainder(double, double);
float remainderf(float, float);
long double remainderl(long double, long double);
double fma(double, double, double);
float fmaf(float, float, float);
long double fmal(long double, long double, long double);
double fmax(double, double);
float fmaxf(float, float);
double fmin(double, double);
float fminf(float, float);
double copysign(double, double);
double frexp(double, int *);
double ldexp(double, int);
double modf(double, double *);
double nan(const char *);
__END_DECLS
#endif
