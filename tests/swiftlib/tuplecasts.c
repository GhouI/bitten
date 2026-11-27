// Driver for tuplecasts.swift.
#include "darwin.h"

long swl_tuplecasts_labels(void);
long swl_tuplecasts_elements(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("labels", swl_tuplecasts_labels());
    ok &= check("elements", swl_tuplecasts_elements());
    CHECK(ok);
    puts("swift tuple casts ok");
    return 0;
}
