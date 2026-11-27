// Driver for swiftui.swift.
#include "darwin.h"

long swl_swiftui_layout(void);
long swl_swiftui_state(void);
long swl_swiftui_lazy(void);
long swl_swiftui_timelines(void);
long swl_swiftui_order(void);
long swl_swiftui_styles(void);
long swl_swiftui_hits(void);
long swl_swiftui_scrollstack(void);
long swl_swiftui_aspect(void);
long swl_swiftui_inset(void);
long swl_swiftui_labels(void);
long swl_swiftui_hover(void);
long swl_swiftui_togglemarks(void);
long swl_swiftui_flexrows(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("layout", swl_swiftui_layout());
    ok &= check("state", swl_swiftui_state());
    ok &= check("lazy", swl_swiftui_lazy());
    ok &= check("timelines", swl_swiftui_timelines());
    ok &= check("order", swl_swiftui_order());
    ok &= check("styles", swl_swiftui_styles());
    ok &= check("hits", swl_swiftui_hits());
    ok &= check("scrollstack", swl_swiftui_scrollstack());
    ok &= check("aspect", swl_swiftui_aspect());
    ok &= check("inset", swl_swiftui_inset());
    ok &= check("labels", swl_swiftui_labels());
    ok &= check("hover", swl_swiftui_hover());
    ok &= check("togglemarks", swl_swiftui_togglemarks());
    ok &= check("flexrows", swl_swiftui_flexrows());
    CHECK(ok);
    puts("swift swiftui ok");
    return 0;
}
