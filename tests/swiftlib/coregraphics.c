// Driver for coregraphics.swift.
#include "darwin.h"

long swl_cg_geometry(void);
long swl_cg_paths(void);
long swl_cg_context(void);
long swl_cg_members(void);
long swl_cg_describe(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("geometry", swl_cg_geometry());
    ok &= check("paths", swl_cg_paths());
    ok &= check("context", swl_cg_context());
    ok &= check("members", swl_cg_members());
    ok &= check("describe", swl_cg_describe());
    CHECK(ok);
    puts("coregraphics ok");
    return 0;
}
