// Driver for packs.swift.
#include "darwin.h"

long swl_packs(void);

int main(void) {
    long bad = swl_packs();
    if (bad) printf("packs: failed checks %#lx\n", bad);
    CHECK(bad == 0);
    puts("packs ok");
    return 0;
}
