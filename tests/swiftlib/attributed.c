// Driver for attributed.swift.
#include "darwin.h"

long swl_attributed(void);

int main(void) {
    long bad = swl_attributed();
    if (bad) printf("attributed: failed checks %#lx\n", bad);
    CHECK(bad == 0);
    puts("attributed ok");
    return 0;
}
