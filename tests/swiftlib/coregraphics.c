// Driver for coregraphics.swift.
#include "darwin.h"

long swl_cg_geometry(void);
long swl_cg_paths(void);
long swl_cg_context(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("geometry", swl_cg_geometry());
    ok &= check("paths", swl_cg_paths());
    ok &= check("context", swl_cg_context());
    CHECK(ok);
    puts("coregraphics ok");
    return 0;
}
