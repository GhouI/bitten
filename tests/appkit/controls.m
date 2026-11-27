// AppKit controls and the window furniture around them: buttons,
// segmented controls, text fields, scroll views, toolbars built from their
// delegate, alerts, popovers, the status bar, colours and attributed text.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

@interface Target : NSObject <NSToolbarDelegate>
@property int clicks;
@end
@implementation Target
- (void)click:(id)sender { self.clicks++; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)t {
    return @[ @"one", NSToolbarFlexibleSpaceItemIdentifier, @"two" ];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)f {
    NSToolbarItem *i = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    i.label = [ident uppercaseString];
    i.target = self;
    i.action = @selector(click:);
    return i;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Target *t = [Target new];

        NSButton *b = [NSButton buttonWithTitle:@"Go" target:t action:@selector(click:)];
        CHECK([b.title isEqualToString:@"Go"] && b.frame.size.width > 20);
        [b performClick:nil];
        CHECK(t.clicks == 1);
        NSButton *check = [NSButton checkboxWithTitle:@"On" target:t action:@selector(click:)];
        [check performClick:nil];
        CHECK(check.state == NSControlStateValueOn && t.clicks == 2);
        [check performClick:nil];
        CHECK(check.state == NSControlStateValueOff);

        NSSegmentedControl *seg = [NSSegmentedControl segmentedControlWithLabels:@[ @"A", @"B", @"C" ]
                                                                    trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                          target:t action:@selector(click:)];
        CHECK(seg.segmentCount == 3 && seg.selectedSegment == -1);
        seg.selectedSegment = 2;
        CHECK([seg isSelectedForSegment:2] && ![seg isSelectedForSegment:0]);

        NSTextField *label = [NSTextField labelWithString:@"Hello"];
        CHECK(!label.isEditable && label.intrinsicContentSize.width > 10);
        NSTextField *wrap = [NSTextField wrappingLabelWithString:@"one two three four five six seven"];
        wrap.preferredMaxLayoutWidth = 60;
        CHECK(wrap.intrinsicContentSize.height > label.intrinsicContentSize.height);

        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 400)];
        sv.documentView = doc;
        [sv.contentView scrollToPoint:NSMakePoint(0, 1000)];
        CHECK(sv.contentView.bounds.origin.y == 300);
        CHECK(NSEqualRects(sv.documentVisibleRect, NSMakeRect(0, 300, 100, 100)));

        NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"main"];
        tb.delegate = t;
        CHECK(tb.items.count == 3 && [tb.items[0].label isEqualToString:@"ONE"]);
        [tb removeItemAtIndex:1];
        CHECK(tb.items.count == 2 && [tb.items[1].itemIdentifier isEqualToString:@"two"]);

        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Delete?";
        alert.informativeText = @"This cannot be undone.";
        [alert addButtonWithTitle:@"Delete"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert layout];
        CHECK(alert.buttons.count == 2 && alert.buttons[0].tag == NSAlertFirstButtonReturn);
        CHECK(alert.window.contentView.subviews.count >= 4);

        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200)
                                                  styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        NSViewController *vc = [NSViewController new];
        vc.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
        NSPopover *pop = [NSPopover new];
        pop.contentViewController = vc;
        [pop showRelativeToRect:NSZeroRect ofView:w.contentView preferredEdge:NSRectEdgeMaxY];
        CHECK(pop.isShown && w.childWindows.count == 1);
        [pop close];
        CHECK(!pop.isShown && w.childWindows.count == 0);

        NSStatusItem *si = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        CHECK(si.button != nil && [NSStatusBar systemStatusBar].thickness > 0);

        NSColor *p3 = [NSColor colorWithDisplayP3Red:1 green:0 blue:0 alpha:1];
        CHECK(p3.colorSpace == [NSColorSpace displayP3ColorSpace] && p3.redComponent > 1.0);
        NSColor *dyn = [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *a) {
            return [a.name containsString:@"Dark"] ? NSColor.whiteColor : NSColor.blackColor;
        }];
        __block CGFloat light = -1, dark = -1;
        [[NSAppearance appearanceNamed:NSAppearanceNameAqua] performAsCurrentDrawingAppearance:^{ light = dyn.redComponent; }];
        [[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] performAsCurrentDrawingAppearance:^{ dark = dyn.redComponent; }];
        CHECK(light == 0 && dark == 1);

        NSSize s = [@"text" sizeWithAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:13]}];
        CHECK(s.width > 10 && s.height > 10);
        /* A colour well keeps its colour and style, and activates on a click. */
        NSColorWell *well = [NSColorWell colorWellWithStyle:NSColorWellStyleMinimal];
        CHECK(well.colorWellStyle == NSColorWellStyleMinimal && !well.isActive);
        well.color = [NSColor redColor];
        well.supportsAlpha = YES;
        CHECK(well.supportsAlpha && well.color.redComponent > 0.99 && well.color.greenComponent < 0.01);
        [well activate:YES];
        CHECK(well.isActive);
        [well deactivate];
        CHECK(!well.isActive);

        puts("appkit controls ok");
    }
    return 0;
}
