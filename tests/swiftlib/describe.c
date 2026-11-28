// Driver for describe.swift.
#include "darwin.h"

long swl_describe_all(void);

int main(void) {
    long bad = swl_describe_all();
    if (bad) printf("describe: %ld mismatches\n", bad);
    CHECK(bad == 0);
    puts("swift describe ok");
    return 0;
}
