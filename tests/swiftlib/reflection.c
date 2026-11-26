// Driver for reflection.swift.
#include "darwin.h"

long swl_reflection_lazy(void);
long swl_reflection_random(void);
long swl_reflection_casts(void);
long swl_reflection_mirror(void);
long swl_reflection_buffers(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("lazy", swl_reflection_lazy());
    ok &= check("random", swl_reflection_random());
    ok &= check("casts", swl_reflection_casts());
    ok &= check("mirror", swl_reflection_mirror());
    ok &= check("buffers", swl_reflection_buffers());
    CHECK(ok);
    puts("swift stdlib reflection ok");
    return 0;
}
