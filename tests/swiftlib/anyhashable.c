// Driver for anyhashable.swift.
#include "darwin.h"

long swl_anyhashable(void);

int main(void) {
    long bad = swl_anyhashable();
    if (bad) printf("failed checks: %#lx\n", bad);
    CHECK(bad == 0);
    puts("swift stdlib anyhashable ok");
    return 0;
}
