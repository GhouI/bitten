// Driver for photosui.swift.
#include "darwin.h"

long swl_photosui(void);

int main(void) {
    long bad = swl_photosui();
    if (bad) printf("photosui: failed checks %#lx\n", bad);
    CHECK(bad == 0);
    puts("photosui ok");
    return 0;
}
