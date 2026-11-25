// Driver for collections.swift.
#include "darwin.h"

long swc_run(void);

int main(void) {
    long r = swc_run();
    if (r != 4095) printf("collections: got %#lx\n", r);
    CHECK(r == 4095);
    puts("swift stdlib collections ok");
    return 0;
}
