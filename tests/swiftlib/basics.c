// Driver for basics.swift.
#include "darwin.h"

long swl_arith(long, long);
long swl_compare(long, long);
unsigned char swl_unsigned(unsigned char);
long swl_optional(long);

int main(void) {
    CHECK(swl_arith(5, 7) == (25 / 2 + 25 % 5));
    CHECK(swl_compare(1, 2) == (1 | 2 | 32));
    CHECK(swl_compare(3, 3) == (2 | 8 | 16));
    CHECK(swl_compare(9, -9) == (4 | 8 | 32));
    CHECK(swl_unsigned(100) == (unsigned char)(300 - 256) >> 1);
    CHECK(swl_optional(42) == 42);
    CHECK(swl_optional(3) == 999);
    puts("swift stdlib basics ok");
    return 0;
}
