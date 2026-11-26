// Driver for urlrequest.swift.
#include "darwin.h"

long swl_ur_request(void);
long swl_ur_websocket(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("request", swl_ur_request());
    ok &= check("websocket", swl_ur_websocket());
    CHECK(ok);
    puts("urlrequest ok");
    return 0;
}
