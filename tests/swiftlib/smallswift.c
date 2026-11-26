// Driver for smallswift.swift.
#include "darwin.h"

long swl_small_coreaudio(void);
long swl_small_other(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("coreaudio", swl_small_coreaudio());
    ok &= check("accessibility/enclave", swl_small_other());
    CHECK(ok);
    puts("smallswift ok");
    return 0;
}
