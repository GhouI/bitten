// Driver for keypaths.swift: each function returns the bits of the checks
// that failed.
#include "darwin.h"

long swl_kp_stored(void);
long swl_kp_classes(void);
long swl_kp_computed(void);
long swl_kp_generic(void);
long swl_kp_equality(void);
long swl_kp_kinds(void);
long swl_kp_append(void);

static int check(const char *name, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", name, bad);
    return bad != 0;
}

int main(void) {
    int fails = 0;
    fails += check("stored", swl_kp_stored());
    fails += check("classes", swl_kp_classes());
    fails += check("computed", swl_kp_computed());
    fails += check("generic", swl_kp_generic());
    fails += check("equality", swl_kp_equality());
    fails += check("kinds", swl_kp_kinds());
    fails += check("append", swl_kp_append());
    CHECK(fails == 0);
    puts("swift stdlib key paths ok");
    return 0;
}
