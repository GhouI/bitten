// Driver for mfbehaviour.swift.
#include "darwin.h"

long swl_mfbehaviour_all(void);

int main(void) {
    long bad = swl_mfbehaviour_all();
    if (bad) printf("mfbehaviour: %ld mismatches\n", bad);
    CHECK(bad == 0);
    puts("swift more foundation ok");
    return 0;
}
