// Driver for codable.swift.
#include "darwin.h"

long swcod_run(void);

int main(void) {
    long r = swcod_run();
    if (r != 15) printf("codable: got %ld\n", r);
    CHECK(r == 15);
    puts("swift stdlib codable ok");
    return 0;
}
