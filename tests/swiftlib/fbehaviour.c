// Driver for fbehaviour.swift.
#include "darwin.h"

long swl_fbehaviour_all(void);

int main(void) {
    long bad = swl_fbehaviour_all();
    if (bad) printf("fbehaviour: %ld mismatches\n", bad);
    CHECK(bad == 0);
    puts("swift foundation behaviour ok");
    return 0;
}
