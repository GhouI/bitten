// Driver for calendar.swift.
#include "darwin.h"

long swl_calendar(void);

int main(void) {
    long bad = swl_calendar();
    if (bad) printf("failed checks: %#lx\n", bad);
    CHECK(bad == 0);
    puts("swift foundation calendar ok");
    return 0;
}
