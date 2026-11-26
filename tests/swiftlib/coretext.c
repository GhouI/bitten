// Driver for coretext.swift.
#include "darwin.h"

long swl_ct_files(void);

int main(void) {
    long bad = swl_ct_files();
    if (bad) printf("files: failed checks %#lx\n", bad);
    CHECK(bad == 0);
    puts("coretext ok");
    return 0;
}
