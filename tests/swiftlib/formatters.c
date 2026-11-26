// Driver for formatters.swift.
#include "darwin.h"

long swl_fmt_dates(void);
long swl_fmt_regex(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("dates", swl_fmt_dates());
    ok &= check("regex", swl_fmt_regex());
    CHECK(ok);
    puts("formatters ok");
    return 0;
}
