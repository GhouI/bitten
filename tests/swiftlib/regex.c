// Driver for regex.swift.
#include "darwin.h"

long swl_rx_literals(void);
long swl_rx_collections(void);
long swl_rx_builder(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("literals", swl_rx_literals());
    ok &= check("collections", swl_rx_collections());
    ok &= check("builder", swl_rx_builder());
    CHECK(ok);
    puts("regex ok");
    return 0;
}
