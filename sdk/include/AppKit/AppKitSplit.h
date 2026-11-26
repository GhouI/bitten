/* bitten SDK: AppKit split views (NSSplitView, NSSplitViewController,
 * NSSplitViewItem). */
#ifndef BITTEN_APPKIT_SPLIT_H
#define BITTEN_APPKIT_SPLIT_H
#import <AppKit/AppKitCore.h>
#import <AppKit/AppKitLayout.h>

#pragma clang assume_nonnull begin

@class NSSplitView;

typedef NS_ENUM(NSInteger, NSSplitViewDividerStyle) {
    NSSplitViewDividerStyleThick = 1,
    NSSplitViewDividerStyleThin = 2,
    NSSplitViewDividerStylePaneSplitter = 3,
};

APPKIT_EXTERN NSNotificationName const NSSplitViewWillResizeSubviewsNotification;
APPKIT_EXTERN NSNotificationName const NSSplitViewDidResizeSubviewsNotification;

@protocol NSSplitViewDelegate <NSObject>
@optional
- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview;
- (BOOL)splitView:(NSSplitView *)splitView shouldCollapseSubview:(NSView *)subview
    forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex;
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition
         ofSubviewAt:(NSInteger)dividerIndex;
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition
         ofSubviewAt:(NSInteger)dividerIndex;
- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition
         ofSubviewAt:(NSInteger)dividerIndex;
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize;
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view;
- (BOOL)splitView:(NSSplitView *)splitView shouldHideDividerAtIndex:(NSInteger)dividerIndex;
- (NSRect)splitView:(NSSplitView *)splitView effectiveRect:(NSRect)proposedEffectiveRect
       forDrawnRect:(NSRect)drawnRect ofDividerAtIndex:(NSInteger)dividerIndex;
- (NSRect)splitView:(NSSplitView *)splitView additionalEffectiveRectOfDividerAtIndex:(NSInteger)dividerIndex;
- (void)splitViewWillResizeSubviews:(NSNotification *)notification;
- (void)splitViewDidResizeSubviews:(NSNotification *)notification;
@end

/* Subviews side by side (vertical dividers) or stacked (horizontal ones),
 * divided by dividers the user drags. The view is flipped: the first
 * subview is at the left or the top. */
@interface NSSplitView : NSView
@property (getter=isVertical) BOOL vertical;
@property NSSplitViewDividerStyle dividerStyle;
@property (nullable, copy) NSString *autosaveName;
@property (nullable, weak) id<NSSplitViewDelegate> delegate;
@property BOOL arrangesAllSubviews;
@property (readonly, copy) NSArray<__kindof NSView *> *arrangedSubviews;
- (void)addArrangedSubview:(NSView *)view;
- (void)insertArrangedSubview:(NSView *)view atIndex:(NSInteger)index;
- (void)removeArrangedSubview:(NSView *)view;
- (void)drawDividerInRect:(NSRect)rect;
@property (readonly, copy) NSColor *dividerColor;
@property (readonly) CGFloat dividerThickness;
- (void)adjustSubviews;
- (BOOL)isSubviewCollapsed:(NSView *)subview;
- (CGFloat)minPossiblePositionOfDividerAtIndex:(NSInteger)dividerIndex;
- (CGFloat)maxPossiblePositionOfDividerAtIndex:(NSInteger)dividerIndex;
- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)dividerIndex;
- (NSLayoutPriority)holdingPriorityForSubviewAtIndex:(NSInteger)subviewIndex;
- (void)setHoldingPriority:(NSLayoutPriority)priority forSubviewAtIndex:(NSInteger)subviewIndex;
@end

typedef NS_ENUM(NSInteger, NSSplitViewItemBehavior) {
    NSSplitViewItemBehaviorDefault,
    NSSplitViewItemBehaviorSidebar,
    NSSplitViewItemBehaviorContentList,
    NSSplitViewItemBehaviorInspector,
} NS_SWIFT_NAME(NSSplitViewItem.Behavior);

typedef NS_ENUM(NSInteger, NSSplitViewItemCollapseBehavior) {
    NSSplitViewItemCollapseBehaviorDefault,
    NSSplitViewItemCollapseBehaviorPreferResizingSplitViewWithFixedSiblings,
    NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView,
    NSSplitViewItemCollapseBehaviorUseConstraints,
} NS_SWIFT_NAME(NSSplitViewItem.CollapseBehavior);

APPKIT_EXTERN const CGFloat NSSplitViewItemUnspecifiedDimension;
APPKIT_EXTERN const CGFloat NSSplitViewControllerAutomaticDimension;

@interface NSSplitViewItem : NSObject
+ (instancetype)splitViewItemWithViewController:(NSViewController *)viewController;
+ (instancetype)sidebarWithViewController:(NSViewController *)viewController;
+ (instancetype)contentListWithViewController:(NSViewController *)viewController;
+ (instancetype)inspectorWithViewController:(NSViewController *)viewController;
@property (readonly) NSSplitViewItemBehavior behavior;
@property (strong) NSViewController *viewController;
@property (getter=isCollapsed) BOOL collapsed;
@property BOOL canCollapse;
@property BOOL canCollapseFromWindowResize;
@property NSSplitViewItemCollapseBehavior collapseBehavior;
@property CGFloat minimumThickness;
@property CGFloat maximumThickness;
@property CGFloat preferredThicknessFraction;
@property NSLayoutPriority holdingPriority;
@property CGFloat automaticMaximumThickness;
@property (getter=isSpringLoaded) BOOL springLoaded;
@property BOOL allowsFullHeightLayout;
@property NSInteger titlebarSeparatorStyle;
- (instancetype)animator;
@end

@interface NSSplitViewController : NSViewController <NSSplitViewDelegate>
@property (strong) NSSplitView *splitView;
@property (copy) NSArray<NSSplitViewItem *> *splitViewItems;
- (void)addSplitViewItem:(NSSplitViewItem *)splitViewItem;
- (void)insertSplitViewItem:(NSSplitViewItem *)splitViewItem atIndex:(NSInteger)index;
- (void)removeSplitViewItem:(NSSplitViewItem *)splitViewItem;
- (nullable NSSplitViewItem *)splitViewItemForViewController:(NSViewController *)viewController;
@property CGFloat minimumThicknessForInlineSidebars;
- (void)toggleSidebar:(nullable id)sender;
- (void)toggleInspector:(nullable id)sender;
- (NSRect)splitView:(NSSplitView *)splitView effectiveRect:(NSRect)proposedEffectiveRect
       forDrawnRect:(NSRect)drawnRect ofDividerAtIndex:(NSInteger)dividerIndex;
- (NSRect)splitView:(NSSplitView *)splitView additionalEffectiveRectOfDividerAtIndex:(NSInteger)dividerIndex;
- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview;
- (BOOL)splitView:(NSSplitView *)splitView shouldHideDividerAtIndex:(NSInteger)dividerIndex;
@end

#pragma clang assume_nonnull end
#endif
