/* bitten SDK: Auto Layout (frameworks/AppKit/AppKitLayout.m): constraints,
 * anchors, layout guides, NSStackView. A Cassowary solver sets the frames
 * of views that do not translate their autoresizing masks. */
#ifndef BITTEN_APPKIT_LAYOUT_H
#define BITTEN_APPKIT_LAYOUT_H
#import <AppKit/AppKitCore.h>

#pragma clang assume_nonnull begin

/* NSLayoutAttribute is in AppKitCore.h. */
typedef NS_ENUM(NSInteger, NSLayoutRelation) {
    NSLayoutRelationLessThanOrEqual = -1, NSLayoutRelationEqual = 0, NSLayoutRelationGreaterThanOrEqual = 1
};
typedef NS_OPTIONS(NSUInteger, NSLayoutFormatOptions) { NSLayoutFormatDirectionLeadingToTrailing = 0 };
typedef NS_ENUM(NSInteger, NSUserInterfaceLayoutOrientation) {
    NSUserInterfaceLayoutOrientationHorizontal = 0, NSUserInterfaceLayoutOrientationVertical = 1
};
typedef NS_ENUM(NSInteger, NSStackViewDistribution) {
    NSStackViewDistributionGravityAreas = -1, NSStackViewDistributionFill = 0, NSStackViewDistributionFillEqually,
    NSStackViewDistributionFillProportionally, NSStackViewDistributionEqualSpacing,
    NSStackViewDistributionEqualCentering
};
typedef NS_ENUM(NSInteger, NSStackViewGravity) {
    NSStackViewGravityTop = 1, NSStackViewGravityLeading = 1, NSStackViewGravityCenter = 2,
    NSStackViewGravityBottom = 3, NSStackViewGravityTrailing = 3
};

static const NSLayoutPriority NSLayoutPriorityRequired NS_SWIFT_NAME(required) = 1000;
static const NSLayoutPriority NSLayoutPriorityDefaultHigh NS_SWIFT_NAME(defaultHigh) = 750;
static const NSLayoutPriority NSLayoutPriorityDragThatCanResizeWindow NS_SWIFT_NAME(dragThatCanResizeWindow) = 510;
static const NSLayoutPriority NSLayoutPriorityWindowSizeStayPut NS_SWIFT_NAME(windowSizeStayPut) = 500;
static const NSLayoutPriority NSLayoutPriorityDragThatCannotResizeWindow NS_SWIFT_NAME(dragThatCannotResizeWindow) = 490;
static const NSLayoutPriority NSLayoutPriorityDefaultLow NS_SWIFT_NAME(defaultLow) = 250;
static const NSLayoutPriority NSLayoutPriorityFittingSizeCompression NS_SWIFT_NAME(fittingSizeCompression) = 50;
static const NSLayoutPriority NSStackViewVisibilityPriorityMustHold = 1000;
static const NSLayoutPriority NSStackViewVisibilityPriorityNotVisible = 0;

@class NSLayoutAnchor, NSLayoutGuide, NSLayoutXAxisAnchor, NSLayoutYAxisAnchor, NSLayoutDimension;

@interface NSLayoutConstraint : NSObject
+ (instancetype)constraintWithItem:(id)view1 attribute:(NSLayoutAttribute)attr1 relatedBy:(NSLayoutRelation)relation
                            toItem:(nullable id)view2 attribute:(NSLayoutAttribute)attr2 multiplier:(CGFloat)multiplier
                          constant:(CGFloat)c;
+ (NSArray<NSLayoutConstraint *> *)constraintsWithVisualFormat:(NSString *)format options:(NSLayoutFormatOptions)opts
                                                       metrics:(nullable NSDictionary<NSString *, NSNumber *> *)metrics
                                                         views:(NSDictionary<NSString *, id> *)views;
+ (void)activateConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
+ (void)deactivateConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
@property NSLayoutPriority priority;
@property BOOL shouldBeArchived;
@property (nullable, readonly, weak) id firstItem;
@property (nullable, readonly, weak) id secondItem;
@property (readonly) NSLayoutAttribute firstAttribute;
@property (readonly) NSLayoutAttribute secondAttribute;
@property (readonly, copy) NSLayoutAnchor *firstAnchor;
@property (nullable, readonly, copy) NSLayoutAnchor *secondAnchor;
@property (readonly) NSLayoutRelation relation;
@property (readonly) CGFloat multiplier;
@property CGFloat constant;
@property (getter=isActive) BOOL active;
@property (nullable, copy) NSString *identifier;
@end

@interface NSLayoutAnchor<AnchorType> : NSObject <NSCopying>
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor constant:(CGFloat)c;
@property (readonly, copy) NSString *name;
@property (nullable, readonly, weak) id item;
@property (readonly) NSLayoutAttribute _bn_attribute;
@end

@class NSLayoutDimension;
@interface NSLayoutXAxisAnchor : NSLayoutAnchor<NSLayoutXAxisAnchor *>
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutXAxisAnchor *)otherAnchor;
- (NSLayoutConstraint *)constraintEqualToSystemSpacingAfterAnchor:(NSLayoutXAxisAnchor *)anchor multiplier:(CGFloat)multiplier;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToSystemSpacingAfterAnchor:(NSLayoutXAxisAnchor *)anchor
                                                                    multiplier:(CGFloat)multiplier;
@end
@interface NSLayoutYAxisAnchor : NSLayoutAnchor<NSLayoutYAxisAnchor *>
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutYAxisAnchor *)otherAnchor;
- (NSLayoutConstraint *)constraintEqualToSystemSpacingBelowAnchor:(NSLayoutYAxisAnchor *)anchor multiplier:(CGFloat)multiplier;
@end
@interface NSLayoutDimension : NSLayoutAnchor<NSLayoutDimension *>
- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m
                                                     constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m
                                                  constant:(CGFloat)c;
@end

/* The anchors of views and layout guides. */
@protocol NSLayoutAnchorProviding
@property (readonly, strong) NSLayoutXAxisAnchor *leadingAnchor;
@property (readonly, strong) NSLayoutXAxisAnchor *trailingAnchor;
@property (readonly, strong) NSLayoutXAxisAnchor *leftAnchor;
@property (readonly, strong) NSLayoutXAxisAnchor *rightAnchor;
@property (readonly, strong) NSLayoutYAxisAnchor *topAnchor;
@property (readonly, strong) NSLayoutYAxisAnchor *bottomAnchor;
@property (readonly, strong) NSLayoutDimension *widthAnchor;
@property (readonly, strong) NSLayoutDimension *heightAnchor;
@property (readonly, strong) NSLayoutXAxisAnchor *centerXAnchor;
@property (readonly, strong) NSLayoutYAxisAnchor *centerYAnchor;
@end

@interface NSLayoutGuide : NSObject <NSLayoutAnchorProviding>
@property (nullable, weak) NSView *owningView;
@property (copy) NSUserInterfaceItemIdentifier identifier;
@property (readonly) NSRect frame;
@property (readonly) BOOL hasAmbiguousLayout;
@end

@interface NSView (NSConstraintBasedLayout) <NSLayoutAnchorProviding>
@property (readonly, strong) NSLayoutYAxisAnchor *firstBaselineAnchor;
@property (readonly, strong) NSLayoutYAxisAnchor *lastBaselineAnchor;
@property (readonly, copy) NSArray<NSLayoutConstraint *> *constraints;
- (void)addConstraint:(NSLayoutConstraint *)constraint;
- (void)addConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
- (void)removeConstraint:(NSLayoutConstraint *)constraint;
- (void)removeConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
@property (readonly, copy) NSArray<NSLayoutGuide *> *layoutGuides;
- (void)addLayoutGuide:(NSLayoutGuide *)guide;
- (void)removeLayoutGuide:(NSLayoutGuide *)guide;
@property (readonly, strong) NSLayoutGuide *safeAreaLayoutGuide;
@property (readonly, strong) NSLayoutGuide *layoutMarginsGuide;
@property (readonly) CGFloat firstBaselineOffsetFromTop;
@property (readonly) CGFloat lastBaselineOffsetFromBottom;
@property BOOL needsUpdateConstraints;
- (void)updateConstraints;
- (void)updateConstraintsForSubtreeIfNeeded;
- (NSArray<NSLayoutConstraint *> *)constraintsAffectingLayoutForOrientation:(NSLayoutConstraintOrientation)orientation;
@property (readonly) BOOL hasAmbiguousLayout;
@end

@interface NSStackView : NSView
+ (instancetype)stackViewWithViews:(NSArray<NSView *> *)views;
@property NSUserInterfaceLayoutOrientation orientation;
@property NSLayoutAttribute alignment;
@property NSEdgeInsets edgeInsets;
@property NSStackViewDistribution distribution;
@property CGFloat spacing;
@property BOOL detachesHiddenViews;
@property (readonly, copy) NSArray<__kindof NSView *> *arrangedSubviews;
- (void)addArrangedSubview:(NSView *)view;
- (void)insertArrangedSubview:(NSView *)view atIndex:(NSInteger)index;
- (void)removeArrangedSubview:(NSView *)view;
- (void)setCustomSpacing:(CGFloat)spacing afterView:(NSView *)view;
- (CGFloat)customSpacingAfterView:(NSView *)view;
@property (copy) NSArray<__kindof NSView *> *views;
- (void)setViews:(NSArray<NSView *> *)views inGravity:(NSStackViewGravity)gravity;
- (void)addView:(NSView *)view inGravity:(NSStackViewGravity)gravity;
- (NSLayoutPriority)huggingPriorityForOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setHuggingPriority:(NSLayoutPriority)priority forOrientation:(NSLayoutConstraintOrientation)orientation;
- (NSLayoutPriority)clippingResistancePriorityForOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setClippingResistancePriority:(NSLayoutPriority)priority forOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setVisibilityPriority:(NSLayoutPriority)priority forView:(NSView *)view;
@end

#pragma clang assume_nonnull end
#endif
