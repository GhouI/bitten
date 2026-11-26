// Driver for dispatch.swift.
#include "darwin.h"

long swl_dispatch_queues(void);
long swl_dispatch_times(void);
long swl_dispatch_sources(void);
long swl_dispatch_misc(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("queues", swl_dispatch_queues());
    ok &= check("times", swl_dispatch_times());
    ok &= check("sources", swl_dispatch_sources());
    ok &= check("misc", swl_dispatch_misc());
    CHECK(ok);
    puts("swift dispatch ok");
    return 0;
}
