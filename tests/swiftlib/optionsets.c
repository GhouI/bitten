// Driver for optionsets.swift.
#include "darwin.h"

long swl_optionsets_run(void);

int main(void) {
    long bad = swl_optionsets_run();
    if (bad) printf("optionsets: failed checks %#lx\n", bad);
    CHECK(bad == 0);
    puts("swift stdlib option sets ok");
    return 0;
}
