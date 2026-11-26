/* bitten SDK: AppKit cells. Controls here draw themselves; their cells
 * hold the state programs configure through them and can draw on their
 * own (drawWithFrame:inView:). */
#import <AppKit/AppKitCore.h>

#pragma clang assume_nonnull begin
typedef NS_ENUM(NSUInteger, NSCellType) { NSNullCellType = 0, NSTextCellType = 1, NSImageCellType = 2 };

@interface NSCell : NSObject <NSCopying>
- (instancetype)init;
- (instancetype)initTextCell:(NSString *)string;
- (instancetype)initImageCell:(nullable NSImage *)image;
@property NSCellType type;
@property (nullable, copy) id objectValue;
@property (copy) NSString *stringValue;
@property (copy) NSAttributedString *attributedStringValue;
@property (copy) NSString *title;
@property (nullable, strong) NSImage *image;
@property (nullable, strong) NSFont *font;
@property NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property BOOL wraps, scrollable, usesSingleLineMode, truncatesLastVisibleLine;
@property (getter=isEnabled) BOOL enabled;
@property (getter=isEditable) BOOL editable;
@property (getter=isSelectable) BOOL selectable;
@property (getter=isBordered) BOOL bordered;
@property (getter=isBezeled) BOOL bezeled;
@property (getter=isHighlighted) BOOL highlighted;
@property NSControlStateValue state;
@property NSInteger tag;
@property (nullable, weak) id target;
@property (nullable) SEL action;
@property (nullable, strong) id representedObject;
@property NSControlSize controlSize;
@property NSFocusRingType focusRingType;
@property (nullable, weak) NSView *controlView;
@property double doubleValue;
@property NSInteger integerValue;
@property int intValue;
@property float floatValue;
@property (readonly) NSSize cellSize;
- (NSSize)cellSizeForBounds:(NSRect)bounds;
- (NSRect)drawingRectForBounds:(NSRect)rect;
- (NSRect)titleRectForBounds:(NSRect)rect;
- (NSRect)imageRectForBounds:(NSRect)rect;
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
@end

@interface NSActionCell : NSCell
@end

@interface NSButtonCell : NSActionCell
@property NSBezelStyle bezelStyle;
@property NSCellImagePosition imagePosition;
@property (nullable, copy) NSString *alternateTitle;
@property (nullable, strong) NSImage *alternateImage;
@property (nullable, copy) NSColor *backgroundColor;
@property BOOL imageDimsWhenDisabled, showsBorderOnlyWhileMouseInside;
- (void)drawImage:(NSImage *)image withFrame:(NSRect)frame inView:(NSView *)controlView;
- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)controlView;
- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView;
@end

@interface NSTextFieldCell : NSActionCell
@property (nullable, copy) NSColor *textColor, *backgroundColor;
@property BOOL drawsBackground;
@property (nullable, copy) NSString *placeholderString;
@property (nullable, copy) NSAttributedString *placeholderAttributedString;
@end
#pragma clang assume_nonnull end
