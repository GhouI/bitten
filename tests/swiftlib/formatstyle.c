// Driver for formatstyle.swift (dates in UTC).
#include "darwin.h"

int setenv(const char *, const char *, int);
long swl_fmt_numbers(void);
long swl_fmt_lists_dates(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    setenv("TZ", "UTC", 1);
    int ok = check("numbers", swl_fmt_numbers());
    ok &= check("lists/dates", swl_fmt_lists_dates());
    CHECK(ok);
    puts("formatstyle ok");
    return 0;
}
