// Driver for swiftui.swift.
#include "darwin.h"

long swl_swiftui_layout(void);
long swl_swiftui_state(void);
long swl_swiftui_lazy(void);
long swl_swiftui_timelines(void);
long swl_swiftui_order(void);
long swl_swiftui_styles(void);
long swl_swiftui_pressrebuild(void);
long swl_swiftui_hits(void);
long swl_swiftui_scrollstack(void);
long swl_swiftui_aspect(void);
long swl_swiftui_inset(void);
long swl_swiftui_labels(void);
long swl_swiftui_hover(void);
long swl_swiftui_togglemarks(void);
long swl_swiftui_flexrows(void);
long swl_swiftui_minframe(void);
long swl_swiftui_statescope(void);
long swl_swiftui_sheetwindow(void);
long swl_swiftui_gridrowfields(void);
long swl_swiftui_gridspan(void);
long swl_swiftui_nohitrep(void);
long swl_swiftui_truncate(void);
long swl_swiftui_blendout(void);
long swl_swiftui_canvashole(void);
long swl_swiftui_spacershort(void);
long swl_swiftui_leakfree(void);
long swl_swiftui_bglayers(void);
long swl_swiftui_viewlists(void);
long swl_swiftui_hiddenhost(void);
long swl_swiftui_stalechange(void);
long swl_swiftui_linelimit(void);
long swl_swiftui_shortcuts(void);
long swl_swiftui_toggleclick(void);
long swl_swiftui_rebuildwrites(void);

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
    ok &= check("pressrebuild", swl_swiftui_pressrebuild());
    ok &= check("hits", swl_swiftui_hits());
    ok &= check("scrollstack", swl_swiftui_scrollstack());
    ok &= check("aspect", swl_swiftui_aspect());
    ok &= check("inset", swl_swiftui_inset());
    ok &= check("labels", swl_swiftui_labels());
    ok &= check("hover", swl_swiftui_hover());
    ok &= check("togglemarks", swl_swiftui_togglemarks());
    ok &= check("flexrows", swl_swiftui_flexrows());
    ok &= check("minframe", swl_swiftui_minframe());
    ok &= check("statescope", swl_swiftui_statescope());
    ok &= check("sheetwindow", swl_swiftui_sheetwindow());
    ok &= check("gridrowfields", swl_swiftui_gridrowfields());
    ok &= check("gridspan", swl_swiftui_gridspan());
    ok &= check("nohitrep", swl_swiftui_nohitrep());
    ok &= check("truncate", swl_swiftui_truncate());
    ok &= check("blendout", swl_swiftui_blendout());
    ok &= check("canvashole", swl_swiftui_canvashole());
    ok &= check("spacershort", swl_swiftui_spacershort());
    ok &= check("leakfree", swl_swiftui_leakfree());
    ok &= check("bglayers", swl_swiftui_bglayers());
    ok &= check("viewlists", swl_swiftui_viewlists());
    ok &= check("hiddenhost", swl_swiftui_hiddenhost());
    ok &= check("stalechange", swl_swiftui_stalechange());
    ok &= check("linelimit", swl_swiftui_linelimit());
    ok &= check("shortcuts", swl_swiftui_shortcuts());
    ok &= check("toggleclick", swl_swiftui_toggleclick());
    ok &= check("rebuildwrites", swl_swiftui_rebuildwrites());
    CHECK(ok);
    puts("swift swiftui ok");
    return 0;
}
