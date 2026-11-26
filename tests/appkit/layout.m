// Auto Layout: anchors and constraints solved into frames, priorities,
// multipliers, intrinsic sizes, autoresizing masks, layout guides and stack
// views.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)
#define RECT(v, X, Y, W, H) CHECK(fabs((v).frame.origin.x - (X)) < 0.6 && fabs((v).frame.origin.y - (Y)) < 0.6 && \
                                  fabs((v).frame.size.width - (W)) < 0.6 && fabs((v).frame.size.height - (H)) < 0.6)

@interface Flipped : NSView
@end
@implementation Flipped
- (BOOL)isFlipped { return YES; }
@end

@interface Sized : NSView
@property NSSize size;
@end
@implementation Sized
- (NSSize)intrinsicContentSize { return self.size; }
@end

static NSView *auto_view(void) {
    NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    return v;
}

int main(void) {
    [NSApplication sharedApplication];

    /* Edges with insets, in an unflipped root: y counts up from the bottom. */
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSView *a = auto_view();
    [root addSubview:a];
    NSLayoutConstraint *lead = [a.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:10];
    [NSLayoutConstraint activateConstraints:@[
        lead,
        [a.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],
        [a.widthAnchor constraintEqualToConstant:100],
        [a.heightAnchor constraintEqualToAnchor:root.heightAnchor multiplier:0.5],
    ]];
    CHECK(lead.isActive && [root.constraints containsObject:lead] && lead.firstItem == a && lead.secondItem == root);
    CHECK(lead.firstAttribute == NSLayoutAttributeLeading && lead.priority == NSLayoutPriorityRequired);
    [root layoutSubtreeIfNeeded];
    RECT(a, 10, 130, 100, 150);

    /* Changing a constant lays out again. */
    lead.constant = 30;
    [root layoutSubtreeIfNeeded];
    RECT(a, 30, 130, 100, 150);

    /* A sibling placed after the first, centred, and the old-style API. */
    NSView *b = auto_view();
    [root addSubview:b];
    NSLayoutConstraint *trail = [NSLayoutConstraint constraintWithItem:b attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:root attribute:NSLayoutAttributeTrailing multiplier:1 constant:-2];
    [root addConstraints:@[
        [NSLayoutConstraint constraintWithItem:b attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual
                                        toItem:a attribute:NSLayoutAttributeRight multiplier:1 constant:8],
        trail,
        [NSLayoutConstraint constraintWithItem:b attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual
                                        toItem:a attribute:NSLayoutAttributeCenterY multiplier:1 constant:0],
        [NSLayoutConstraint constraintWithItem:b attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual
                                        toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:50],
    ]];
    [root layoutSubtreeIfNeeded];
    RECT(b, 138, 180, 260, 50);

    /* Priorities: an optional width loses to a required maximum. */
    NSLayoutConstraint *wide = [b.widthAnchor constraintEqualToConstant:1000];
    wide.priority = NSLayoutPriorityDefaultHigh;
    trail.active = NO;
    CHECK(!trail.isActive && ![root.constraints containsObject:trail]);
    wide.active = YES;
    [[b.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor] setActive:YES];
    [root layoutSubtreeIfNeeded];
    RECT(b, 138, 180, 262, 50);

    /* Deactivating leaves the frame as it was. */
    wide.active = NO;
    [NSLayoutConstraint deactivateConstraints:root.constraints];
    CHECK(root.constraints.count == 0);
    [root layoutSubtreeIfNeeded];
    RECT(b, 138, 180, 262, 50);

    /* Flipped superviews, nested views, intrinsic sizes and hugging. */
    Flipped *top = [[Flipped alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    NSView *box = auto_view();
    Sized *label = [[Sized alloc] initWithFrame:NSZeroRect];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.size = NSMakeSize(60, 20);
    [top addSubview:box];
    [box addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [box.leadingAnchor constraintEqualToAnchor:top.leadingAnchor constant:5],
        [box.trailingAnchor constraintEqualToAnchor:top.trailingAnchor constant:-5],
        [box.topAnchor constraintEqualToAnchor:top.topAnchor constant:10],
        [box.bottomAnchor constraintEqualToAnchor:top.bottomAnchor constant:-10],
        [label.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:box.topAnchor constant:4],
    ]];
    [top layoutSubtreeIfNeeded];
    RECT(box, 5, 10, 290, 180);
    RECT(label, 115, 156, 60, 20);   /* box is not flipped: y up from its bottom */

    /* Compression resistance holds the intrinsic size against a weak squeeze. */
    NSLayoutConstraint *squeeze = [label.widthAnchor constraintEqualToConstant:10];
    squeeze.priority = NSLayoutPriorityDefaultLow;
    squeeze.active = YES;
    [top layoutSubtreeIfNeeded];
    CHECK(fabs(label.frame.size.width - 60) < 0.6);
    squeeze.priority = 800;
    [top layoutSubtreeIfNeeded];
    CHECK(fabs(label.frame.size.width - 10) < 0.6);
    squeeze.active = NO;

    /* A view with an autoresizing mask keeps its frame and stretches. */
    NSView *masked = [[NSView alloc] initWithFrame:NSMakeRect(20, 20, 100, 40)];
    masked.autoresizingMask = NSViewWidthSizable;
    [top addSubview:masked];
    NSView *under = auto_view();
    [top addSubview:under];
    [NSLayoutConstraint activateConstraints:@[
        [under.topAnchor constraintEqualToAnchor:masked.bottomAnchor constant:6],
        [under.leadingAnchor constraintEqualToAnchor:masked.leadingAnchor],
        [under.widthAnchor constraintEqualToAnchor:masked.widthAnchor multiplier:0.5 constant:10],
        [under.heightAnchor constraintEqualToConstant:12],
    ]];
    [top layoutSubtreeIfNeeded];
    RECT(masked, 20, 20, 100, 40);
    RECT(under, 20, 66, 60, 12);

    /* Layout guides: the safe area, and one of the view's own. */
    NSLayoutGuide *g = [NSLayoutGuide new];
    [top addLayoutGuide:g];
    CHECK(g.owningView == top && top.layoutGuides.count == 1);
    NSView *inGuide = auto_view();
    [top addSubview:inGuide];
    [NSLayoutConstraint activateConstraints:@[
        [g.leadingAnchor constraintEqualToAnchor:top.safeAreaLayoutGuide.leadingAnchor constant:100],
        [g.widthAnchor constraintEqualToConstant:50],
        [g.topAnchor constraintEqualToAnchor:top.topAnchor],
        [g.heightAnchor constraintEqualToConstant:30],
        [inGuide.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [inGuide.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [inGuide.topAnchor constraintEqualToAnchor:g.bottomAnchor],
        [inGuide.heightAnchor constraintEqualToConstant:5],
    ]];
    [top layoutSubtreeIfNeeded];
    RECT(inGuide, 100, 30, 50, 5);
    CHECK(fabs(g.frame.origin.x - 100) < 0.6 && fabs(g.frame.size.width - 50) < 0.6);

    /* Stack views: horizontal with spacing, custom spacing and insets. */
    Flipped *host = [[Flipped alloc] initWithFrame:NSMakeRect(0, 0, 500, 100)];
    Sized *s1 = [Sized new], *s2 = [Sized new], *s3 = [Sized new];
    s1.size = NSMakeSize(40, 20);
    s2.size = NSMakeSize(60, 30);
    s3.size = NSMakeSize(20, 10);
    NSStackView *stack = [NSStackView stackViewWithViews:@[s1, s2, s3]];
    CHECK(stack.arrangedSubviews.count == 3 && s1.superview == stack && !s2.translatesAutoresizingMaskIntoConstraints);
    CHECK(stack.orientation == NSUserInterfaceLayoutOrientationHorizontal && stack.spacing == 8);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.edgeInsets = NSEdgeInsetsMake(5, 10, 5, 10);
    [stack setCustomSpacing:20 afterView:s1];
    [host addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [stack.topAnchor constraintEqualToAnchor:host.topAnchor],
    ]];
    [host layoutSubtreeIfNeeded];
    /* 10 + 40 + 20 + 60 + 8 + 20 + 10 wide, 5 + 30 + 5 tall */
    RECT(stack, 0, 0, 168, 40);
    RECT(s1, 10, 10, 40, 20);   /* centred: stack not flipped, y up */
    RECT(s2, 70, 5, 60, 30);
    RECT(s3, 138, 15, 20, 10);

    /* Hidden views drop out; vertical stacks fill equally. */
    s2.hidden = YES;
    stack.needsLayout = YES;
    [host layoutSubtreeIfNeeded];
    RECT(stack, 0, 0, 100, 30);
    RECT(s3, 70, 10, 20, 10);
    s2.hidden = NO;

    NSStackView *col = [NSStackView new];
    col.orientation = NSUserInterfaceLayoutOrientationVertical;
    col.distribution = NSStackViewDistributionFillEqually;
    col.alignment = NSLayoutAttributeLeading;
    col.spacing = 0;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *r1 = auto_view(), *r2 = auto_view();
    [col addArrangedSubview:r1];
    [col addArrangedSubview:r2];
    [host addSubview:col];
    [NSLayoutConstraint activateConstraints:@[
        [col.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:200],
        [col.topAnchor constraintEqualToAnchor:host.topAnchor],
        [col.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        [col.widthAnchor constraintEqualToConstant:80],
        [r1.widthAnchor constraintEqualToConstant:30],
        [r2.widthAnchor constraintEqualToConstant:50],
    ]];
    [host layoutSubtreeIfNeeded];
    RECT(col, 200, 0, 80, 100);
    RECT(r1, 0, 50, 30, 50);
    RECT(r2, 0, 0, 50, 50);

    /* Windows lay out before they draw. */
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 200) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:NO];
    NSView *fill = auto_view();
    [w.contentView addSubview:fill];
    [NSLayoutConstraint activateConstraints:@[
        [fill.leadingAnchor constraintEqualToAnchor:w.contentView.leadingAnchor constant:16],
        [fill.trailingAnchor constraintEqualToAnchor:w.contentView.trailingAnchor constant:-16],
        [fill.topAnchor constraintEqualToAnchor:w.contentView.topAnchor constant:16],
        [fill.bottomAnchor constraintEqualToAnchor:w.contentView.bottomAnchor constant:-16],
    ]];
    [w makeKeyAndOrderFront:nil];
    [w display];
    RECT(fill, 16, 16, 288, 168);

    printf("layout ok\n");
    return 0;
}
