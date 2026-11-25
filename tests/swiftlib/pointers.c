// Driver for pointers.swift.
#include "darwin.h"

long swp_layout(void);
long swp_objects(long step);
long swp_buffers(void);

static int died[16];
void swp_note_deinit(long v) { if (v >= 0 && v < 16) died[v]++; }

int main(void) {
    CHECK(swp_layout() == 3);
    CHECK(swp_objects(1) == 1);
    /* After step 1 the only references were in q, which was never
     * released: nothing died. */
    CHECK(died[7] == 0 && died[8] == 0 && died[9] == 0);
    CHECK(swp_objects(2) == 3);
    /* Step 2's own objects: 8 and 9 deinitialized, and 7 released when
     * `first` went out of scope. Step 1 leaked its four (on purpose). */
    CHECK(died[7] == 1 && died[8] == 1 && died[9] == 1);
    long b = swp_buffers();
    if (b != 63) printf("buffers: %#lx\n", b);
    CHECK(b == 63);
    puts("swift stdlib pointers ok");
    return 0;
}
