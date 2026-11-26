// Driver for simd.swift.
#include "darwin.h"

long swl_simd(void);

int main(void) {
    long bad = swl_simd();
    if (bad) printf("simd: failed checks %#lx\n", bad);
    CHECK(bad == 0);
    puts("simd ok");
    return 0;
}
