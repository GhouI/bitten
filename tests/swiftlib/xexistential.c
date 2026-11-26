// Driver for xexistential.swift.
#include "darwin.h"

long swl_xexistential(void);

int main(void) {
    long bad = swl_xexistential();
    if (bad) printf("failed checks: %#lx\n", bad);
    CHECK(bad == 0);
    puts("swift stdlib xexistential ok");
    return 0;
}
