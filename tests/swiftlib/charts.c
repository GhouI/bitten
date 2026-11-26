// Driver for charts.swift.
#include "darwin.h"

long swl_charts_line(void);

int main(void) {
    long bad = swl_charts_line();
    if (bad) printf("charts: failed checks %#lx\n", bad);
    CHECK(bad == 0);
    puts("charts ok");
    return 0;
}
