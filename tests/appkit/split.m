// Split views: panes and dividers, moving dividers (by hand and by mouse),
// resizing by holding priority, delegate limits and collapsing, autosave,
// and NSSplitViewController's items with Auto Layout inside the panes.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)
#define NEAR(a, b) (fabs((a) - (b)) < 0.6)
#define RECT(v, X, Y, W, H) CHECK(NEAR((v).frame.origin.x, X) && NEAR((v).frame.origin.y, Y) && \
                                  NEAR((v).frame.size.width, W) && NEAR((v).frame.size.height, H))

@interface Limits : NSObject <NSSplitViewDelegate>
@property int resized;
@end
@implementation Limits
- (CGFloat)splitView:(NSSplitView *)s constrainMinCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i { return 50; }
- (CGFloat)splitView:(NSSplitView *)s constrainMaxCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i { return 250; }
- (BOOL)splitView:(NSSplitView *)s canCollapseSubview:(NSView *)v { return v == s.arrangedSubviews[0]; }
- (void)splitViewDidResizeSubviews:(NSNotification *)n { self.resized++; }
@end

/* A toolbar with a sidebar tracking separator and one button. */
@interface Bar : NSObject <NSToolbarDelegate>
@property int pressed;
@end
@implementation Bar
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)t {
    return @[ @"NSToolbarSidebarTrackingSeparatorItemIdentifier", @"go" ];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSToolbarItemIdentifier)ident
    willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    item.view = [NSButton buttonWithTitle:@"Go" target:self action:@selector(go:)];
    return item;
}
- (void)go:(id)sender { self.pressed++; }
@end

static NSView *pane(CGFloat w, CGFloat h) { return [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)]; }

static NSEvent *mouse(NSEventType t, NSWindow *w, CGFloat x, CGFloat y) {
    return [NSEvent mouseEventWithType:t location:NSMakePoint(x, y) modifierFlags:0 timestamp:0
                          windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

int main(void) {
    [NSApplication sharedApplication];

    /* Side by side, thick dividers. */
    NSSplitView *s = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 309, 200)];
    s.vertical = YES;
    CHECK(s.isFlipped && s.dividerThickness == 9 && s.arrangesAllSubviews);
    NSView *a = pane(100, 10), *b = pane(200, 10);
    [s addSubview:a];
    [s addSubview:b];
    CHECK(s.arrangedSubviews.count == 2);
    [s adjustSubviews];
    RECT(a, 0, 0, 100, 200);
    RECT(b, 109, 0, 200, 200);
    CHECK([s minPossiblePositionOfDividerAtIndex:0] == 0 && [s maxPossiblePositionOfDividerAtIndex:0] == 300);

    [s setPosition:150 ofDividerAtIndex:0];
    RECT(a, 0, 0, 150, 200);
    RECT(b, 159, 0, 150, 200);

    /* Growing: equal holding priorities share; a higher one holds. */
    s.frame = NSMakeRect(0, 0, 409, 200);
    RECT(a, 0, 0, 200, 200);
    RECT(b, 209, 0, 200, 200);
    [s setHoldingPriority:500 forSubviewAtIndex:0];
    CHECK([s holdingPriorityForSubviewAtIndex:0] == 500 && [s holdingPriorityForSubviewAtIndex:1] == 250);
    s.frame = NSMakeRect(0, 0, 509, 300);
    RECT(a, 0, 0, 200, 300);
    RECT(b, 209, 0, 300, 300);

    /* adjustSubviews scales proportionally. */
    s.frame = NSMakeRect(0, 0, 509, 300);
    [s adjustSubviews];
    RECT(b, 209, 0, 300, 300);

    /* Stacked, thin dividers: the first pane at the top. */
    NSSplitView *h = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 100, 201)];
    h.dividerStyle = NSSplitViewDividerStyleThin;
    NSView *top = pane(10, 50), *bottom = pane(10, 150);
    [h addArrangedSubview:top];
    [h addArrangedSubview:bottom];
    [h adjustSubviews];
    RECT(top, 0, 0, 100, 50);
    RECT(bottom, 0, 51, 100, 150);

    /* A delegate's limits, and collapsing past them. */
    Limits *lim = [Limits new];
    s.delegate = lim;
    [s setPosition:30 ofDividerAtIndex:0];      /* within half the minimum: holds at it */
    CHECK(NEAR(a.frame.size.width, 50) && !a.isHidden);
    [s setPosition:400 ofDividerAtIndex:0];
    CHECK(NEAR(a.frame.size.width, 250));
    CHECK(lim.resized >= 2);
    [s setPosition:20 ofDividerAtIndex:0];      /* below half: collapses */
    CHECK([s isSubviewCollapsed:a] && a.isHidden);
    RECT(b, 9, 0, 500, 300);
    [s setPosition:120 ofDividerAtIndex:0];
    CHECK(![s isSubviewCollapsed:a] && !a.isHidden && NEAR(a.frame.size.width, 120));
    RECT(b, 129, 0, 380, 300);

    /* Dragging a divider with the mouse in a window. */
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 509, 300) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:NO];
    w.contentView = s;
    [w makeKeyAndOrderFront:nil];
    CHECK([w.contentView hitTest:NSMakePoint(124, 100)] == s);       /* on the divider */
    CHECK([w.contentView hitTest:NSMakePoint(60, 100)] == a);
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, 124, 100)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 204, 100)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, 204, 100)];
    CHECK(NEAR(a.frame.size.width, 200));
    RECT(b, 209, 0, 300, 300);

    /* Autosave: another split view with the name picks the sizes up. */
    s.autosaveName = @"Test Split";
    [s setPosition:180 ofDividerAtIndex:0];
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"NSSplitView Subview Frames Test Split"];
    CHECK(saved.count == 2 && [saved[0] hasPrefix:@"0.000000, 0.000000, 180.000000"]);
    NSSplitView *s2 = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 509, 300)];
    s2.vertical = YES;
    NSView *a2 = pane(254, 10), *b2 = pane(254, 10);
    [s2 addSubview:a2];
    [s2 addSubview:b2];
    s2.autosaveName = @"Test Split";
    CHECK(NEAR(a2.frame.size.width, 180) && NEAR(b2.frame.size.width, 320));

    /* A split view controller: a sidebar and the content. */
    NSSplitViewController *svc = [NSSplitViewController new];
    NSViewController *side = [NSViewController new], *main = [NSViewController new];
    side.view = pane(200, 100);
    main.view = pane(100, 100);
    NSSplitViewItem *sideItem = [NSSplitViewItem sidebarWithViewController:side];
    NSSplitViewItem *mainItem = [NSSplitViewItem splitViewItemWithViewController:main];
    CHECK(sideItem.behavior == NSSplitViewItemBehaviorSidebar && sideItem.canCollapse && !mainItem.canCollapse);
    CHECK(sideItem.holdingPriority > mainItem.holdingPriority);
    sideItem.minimumThickness = 150;
    sideItem.maximumThickness = 300;
    svc.view.frame = NSMakeRect(0, 0, 800, 500);
    svc.splitViewItems = @[sideItem, mainItem];
    CHECK(svc.splitView.isVertical && svc.splitView.dividerThickness == 1 && svc.splitView.delegate == (id)svc);
    CHECK([svc splitViewItemForViewController:main] == mainItem && side.parentViewController == svc);
    [svc.view layoutSubtreeIfNeeded];
    RECT(side.view, 0, 0, 200, 500);
    RECT(main.view, 201, 0, 599, 500);

    /* A label pinned inside the content pane follows it. */
    NSView *label = [[NSView alloc] initWithFrame:NSZeroRect];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [main.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.trailingAnchor constraintEqualToAnchor:main.view.trailingAnchor constant:-10],
        [label.topAnchor constraintEqualToAnchor:main.view.topAnchor constant:10],
        [label.widthAnchor constraintEqualToConstant:50],
        [label.heightAnchor constraintEqualToConstant:20],
    ]];
    [svc.view layoutSubtreeIfNeeded];
    RECT(label, 539, 470, 50, 20);

    /* The window grows: the content takes it, the sidebar holds. */
    svc.view.frame = NSMakeRect(0, 0, 1000, 500);
    [svc.view layoutSubtreeIfNeeded];
    RECT(side.view, 0, 0, 200, 500);
    RECT(main.view, 201, 0, 799, 500);
    RECT(label, 739, 470, 50, 20);

    /* The sidebar's limits bound the divider. */
    [svc.splitView setPosition:100 ofDividerAtIndex:0];
    CHECK(NEAR(side.view.frame.size.width, 150));
    [svc.splitView setPosition:900 ofDividerAtIndex:0];
    CHECK(NEAR(side.view.frame.size.width, 300));
    [svc.splitView setPosition:200 ofDividerAtIndex:0];

    /* Toggling the sidebar collapses it (and its divider) and brings it back. */
    [svc toggleSidebar:nil];
    CHECK(sideItem.isCollapsed && [svc.splitView isSubviewCollapsed:side.view] && side.view.isHidden);
    RECT(main.view, 0, 0, 1000, 500);
    [svc.view layoutSubtreeIfNeeded];
    RECT(label, 940, 470, 50, 20);
    sideItem.animator.collapsed = NO;
    CHECK(!sideItem.isCollapsed && !side.view.isHidden);
    RECT(side.view, 0, 0, 200, 500);
    RECT(main.view, 201, 0, 799, 500);

    /* A collapsed item added later starts collapsed. */
    NSViewController *insp = [NSViewController new];
    insp.view = pane(250, 100);
    NSSplitViewItem *inspItem = [NSSplitViewItem inspectorWithViewController:insp];
    inspItem.collapsed = YES;
    [svc addSplitViewItem:inspItem];
    CHECK(svc.splitViewItems.count == 3 && insp.view.isHidden);
    RECT(main.view, 201, 0, 799, 500);
    [svc toggleInspector:nil];
    CHECK(!inspItem.isCollapsed);
    RECT(insp.view, 750, 0, 250, 500);
    RECT(main.view, 201, 0, 548, 500);

    /* A full-size-content window's toolbar items sit in its title bar's
     * strip, those after the sidebar tracking separator from the split
     * view's divider, and take clicks there. */
    NSWindow *tw = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200)
                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                 backing:NSBackingStoreBuffered defer:NO];
    NSSplitView *ts = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    ts.vertical = YES;
    [ts addSubview:pane(120, 200)];
    [ts addSubview:pane(279, 200)];
    tw.contentView = ts;
    [ts adjustSubviews];
    Bar *bar = [Bar new];
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"test"];
    toolbar.delegate = bar;
    tw.toolbar = toolbar;
    NSView *strip = [tw _bn_toolbarView];
    CHECK(strip && strip.subviews.count == 1);
    NSRect go = [strip.subviews[0] convertRect:strip.subviews[0].bounds toView:nil];
    CHECK(NSMinX(go) >= 120 && NSMinY(go) >= 200 - 28 && NSMaxY(go) <= 200);
    [tw makeKeyAndOrderFront:nil];
    [tw sendEvent:mouse(NSEventTypeLeftMouseDown, tw, NSMidX(go), NSMidY(go))];
    [tw sendEvent:mouse(NSEventTypeLeftMouseUp, tw, NSMidX(go), NSMidY(go))];
    CHECK(bar.pressed == 1);
    [tw close];

    printf("split ok\n");
    return 0;
}
