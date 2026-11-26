// Driver for localized.swift.
#include "darwin.h"

long swl_loc_defaults(void);
long swl_loc_table(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("defaults", swl_loc_defaults());
    ok &= check("table", swl_loc_table());
    CHECK(ok);
    puts("localized ok");
    return 0;
}
