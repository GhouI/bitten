// Driver for numerics.swift.
#include "darwin.h"

long swn_generic(void);

int main(void) {
    long r = swn_generic();
    if (r != 4095) printf("numerics: got %#lx\n", r);
    CHECK(r == 4095);
    puts("swift stdlib numerics ok");
    return 0;
}
