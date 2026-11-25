// Driver for darwin.swift.
#include "darwin.h"

long swl_darwin_libc(void);
long swl_darwin_objc(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("libc", swl_darwin_libc());
    ok &= check("objc", swl_darwin_objc());
    CHECK(ok);
    puts("swift darwin overlays ok");
    return 0;
}
