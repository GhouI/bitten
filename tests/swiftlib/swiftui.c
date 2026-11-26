// Driver for swiftui.swift.
#include "darwin.h"

long swl_swiftui_layout(void);
long swl_swiftui_state(void);
long swl_swiftui_lazy(void);
long swl_swiftui_order(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("layout", swl_swiftui_layout());
    ok &= check("state", swl_swiftui_state());
    ok &= check("lazy", swl_swiftui_lazy());
    ok &= check("order", swl_swiftui_order());
    CHECK(ok);
    puts("swift swiftui ok");
    return 0;
}
