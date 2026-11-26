// Driver for network.swift.
#include "darwin.h"

long swl_network_values(void);
long swl_network_echo(void);
long swl_network_failures(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("values", swl_network_values());
    ok &= check("echo", swl_network_echo());
    ok &= check("failures", swl_network_failures());
    CHECK(ok);
    puts("swift network ok");
    return 0;
}
