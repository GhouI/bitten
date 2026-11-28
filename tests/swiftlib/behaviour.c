// Driver for behaviour.swift.
#include "darwin.h"

long swl_behaviour_all(void);

int main(void) {
    long bad = swl_behaviour_all();
    if (bad) printf("behaviour: %ld mismatches\n", bad);
    CHECK(bad == 0);
    puts("swift behaviour ok");
    return 0;
}
