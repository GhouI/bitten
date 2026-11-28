// Driver for stdbehaviour.swift.
#include "darwin.h"

long swl_stdbehaviour_all(void);

int main(void) {
    long bad = swl_stdbehaviour_all();
    if (bad) printf("stdbehaviour: %ld mismatches\n", bad);
    CHECK(bad == 0);
    puts("swift stdlib behaviour ok");
    return 0;
}
