// Driver for uttype.swift.
#include "darwin.h"

long swl_ut_types(void);
long swl_ut_foundation(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("types", swl_ut_types());
    ok &= check("foundation", swl_ut_foundation());
    CHECK(ok);
    puts("uttype ok");
    return 0;
}
