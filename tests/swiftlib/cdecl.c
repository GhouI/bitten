// Driver for cdecl.swift.
#include "darwin.h"

double swd_scale(int, double);
long swd_sum(const long *, long);
unsigned char swd_flag(_Bool);

int main(void) {
    long v[4] = {1, 2, 3, 40};
    CHECK(swd_scale(3, 1.5) == 4.5);
    CHECK(swd_sum(v, 4) == 46);
    CHECK(swd_flag(1) == 0xAB && swd_flag(0) == 0);
    puts("swift stdlib cdecl ok");
    return 0;
}
