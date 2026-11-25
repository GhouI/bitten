// Driver for floats.swift. Doubles and floats cross in xmm registers.
#include "darwin.h"

double swf_hypot(double, double);
float swf_hypotf(float, float);
double swf_round(double, long);
double swf_rem(double, double);
double swf_fmod(double, double);
long swf_to_int(double);
double swf_from_int(long);
double swf_from_uint(unsigned long);
unsigned long swf_bits(double);
double swf_pi(void);
double swf_big_literal(void);
float swf_big_literal_f(void);
long swf_ieee(void);
long swf_bitlevel(void);
long swf_conversions(void);
long swf_float80(void);
long swf_misc(void);

static int expect(const char *what, long got, long want) {
    if (got != want) printf("floats %s: got %#lx, want %#lx\n", what, got, want);
    return got == want;
}

int main(void) {
    CHECK(swf_hypot(3, 4) == 5);
    CHECK(swf_hypotf(5, 12) == 13);
    /* rules: nearest-away, nearest-even, up, down, toward zero, away */
    CHECK(swf_round(2.5, 0) == 3 && swf_round(-2.5, 0) == -3);
    CHECK(swf_round(2.5, 1) == 2 && swf_round(3.5, 1) == 4);
    CHECK(swf_round(2.1, 2) == 3 && swf_round(-2.1, 2) == -2);
    CHECK(swf_round(2.9, 3) == 2 && swf_round(-2.1, 3) == -3);
    CHECK(swf_round(-2.9, 4) == -2 && swf_round(2.9, 4) == 2);
    CHECK(swf_round(2.1, 5) == 3 && swf_round(-2.1, 5) == -3);
    /* IEEE remainder: ties go to the even quotient */
    CHECK(swf_rem(5, 3) == -1 && swf_rem(7, 2) == -1 && swf_rem(5, 2) == 1 && swf_rem(-5, 2) == -1);
    CHECK(swf_rem(6, 4) == -2 && swf_rem(10, 4) == 2 && swf_rem(1, 0) != swf_rem(1, 0));
    CHECK(swf_rem(0x1p60, 3) == 1);   /* 2^60 = 3 * 384307168202282325 + 1 */
    CHECK(swf_fmod(5.5, 2) == 1.5 && swf_fmod(-5.5, 2) == -1.5);
    CHECK(swf_to_int(-7.9) == -7 && swf_to_int(1e18) == 1000000000000000000L);
    CHECK(swf_from_int(-3) == -3.0 && swf_from_int(9007199254740993L) == 9007199254740992.0);
    CHECK(swf_from_uint(~0UL) == 18446744073709551616.0);
    CHECK(swf_bits(-2.0) == 0xC000000000000000UL);
    CHECK(swf_bits(swf_pi()) == 0x400921FB54442D18UL);
    CHECK(swf_big_literal() == 3 * 36893488147419103232.0);
    CHECK(swf_big_literal_f() == 1.0f / 0.0f);
    CHECK(expect("ieee", swf_ieee(), 0xff));
    CHECK(expect("bitlevel", swf_bitlevel(), 0xfff));
    CHECK(expect("conversions", swf_conversions(), 0xfff));
    CHECK(expect("float80", swf_float80(), 0x3f));
    CHECK(expect("misc", swf_misc(), 15));
    puts("swift stdlib floats ok");
    return 0;
}
