/* bitten SDK: AppKit's basic types. Written from the public documentation. */
#ifndef BITTEN_APPKITBASE_H
#define BITTEN_APPKITBASE_H
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <sys/types.h>

#define APPKIT_EXTERN extern
typedef NSString *NSNotificationName;
typedef NSString *NSAppearanceName;
typedef NSString *NSAttributedStringKey;
typedef NSString *NSPasteboardType NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSPasteboard.PasteboardType);
typedef NSString *NSPasteboardName NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSPasteboard.Name);
typedef NSString *NSImageName;
typedef NSString *NSToolbarItemIdentifier;
typedef NSString *NSAccessibilityRole;
typedef NSString *NSAccessibilityNotificationName;
typedef NSString *NSBindingName;
typedef NSString *NSBindingOption;
typedef NSString *NSFontTextStyle;
typedef NSString *NSFontDescriptorAttributeName;
typedef NSString *NSImageHintKey;
typedef NSString *NSColorSpaceName;
typedef NSString *NSColorName NS_SWIFT_NAME(NSColor.Name);
typedef NSString *NSWorkspaceNotificationKey_;
typedef CGFloat NSFontWeight;

typedef NS_OPTIONS(NSUInteger, NSWindowStyleMask) {
    NSWindowStyleMaskBorderless = 0,
    NSWindowStyleMaskTitled = 1 << 0,
    NSWindowStyleMaskClosable = 1 << 1,
    NSWindowStyleMaskMiniaturizable = 1 << 2,
    NSWindowStyleMaskResizable = 1 << 3,
    NSWindowStyleMaskFullSizeContentView = 1 << 15,
} NS_SWIFT_NAME(NSWindow.StyleMask);
typedef NS_ENUM(NSInteger, NSModalResponse) {
    NSModalResponseStop = -1000, NSModalResponseAbort = -1001, NSModalResponseContinue = -1002,
    NSModalResponseOK = 1, NSModalResponseCancel = 0
} NS_SWIFT_NAME(NSApplication.ModalResponse);
typedef NS_ENUM(NSUInteger, NSBackingStoreType) {
    NSBackingStoreRetained = 0, NSBackingStoreNonretained = 1, NSBackingStoreBuffered = 2,
} NS_SWIFT_NAME(NSWindow.BackingStoreType);
typedef NS_ENUM(NSInteger, NSApplicationActivationPolicy) {
    NSApplicationActivationPolicyRegular = 0,
    NSApplicationActivationPolicyAccessory = 1,
    NSApplicationActivationPolicyProhibited = 2,
} NS_SWIFT_NAME(NSApplication.ActivationPolicy);
typedef NS_ENUM(NSUInteger, NSApplicationTerminateReply) {
    NSTerminateCancel = 0, NSTerminateNow = 1, NSTerminateLater = 2,
} NS_SWIFT_NAME(NSApplication.TerminateReply);
typedef NS_ENUM(NSUInteger, NSEventType) {
    NSEventTypeLeftMouseDown = 1, NSEventTypeLeftMouseUp = 2,
    NSEventTypeRightMouseDown = 3, NSEventTypeRightMouseUp = 4,
    NSEventTypeMouseMoved = 5, NSEventTypeLeftMouseDragged = 6, NSEventTypeRightMouseDragged = 7,
    NSEventTypeMouseEntered = 8, NSEventTypeMouseExited = 9,
    NSEventTypeKeyDown = 10, NSEventTypeKeyUp = 11, NSEventTypeFlagsChanged = 12,
    NSEventTypeAppKitDefined = 13, NSEventTypeSystemDefined = 14, NSEventTypeApplicationDefined = 15,
    NSEventTypePeriodic = 16, NSEventTypeCursorUpdate = 17, NSEventTypeScrollWheel = 22,
} NS_SWIFT_NAME(NSEvent.EventType);
typedef NS_OPTIONS(NSUInteger, NSEventModifierFlags) {
    NSEventModifierFlagCapsLock = 1 << 16, NSEventModifierFlagShift = 1 << 17,
    NSEventModifierFlagControl = 1 << 18, NSEventModifierFlagOption = 1 << 19,
    NSEventModifierFlagCommand = 1 << 20, NSEventModifierFlagNumericPad = 1 << 21,
    NSEventModifierFlagHelp = 1 << 22, NSEventModifierFlagFunction = 1 << 23,
} NS_SWIFT_NAME(NSEvent.ModifierFlags);
typedef NS_OPTIONS(unsigned long long, NSEventMask) {
    NSEventMaskLeftMouseDown = 1ULL << 1, NSEventMaskLeftMouseUp = 1ULL << 2, NSEventMaskRightMouseDown = 1ULL << 3,
    NSEventMaskRightMouseUp = 1ULL << 4, NSEventMaskMouseMoved = 1ULL << 5, NSEventMaskLeftMouseDragged = 1ULL << 6,
    NSEventMaskRightMouseDragged = 1ULL << 7, NSEventMaskMouseEntered = 1ULL << 8, NSEventMaskMouseExited = 1ULL << 9,
    NSEventMaskKeyDown = 1ULL << 10, NSEventMaskKeyUp = 1ULL << 11, NSEventMaskFlagsChanged = 1ULL << 12,
    NSEventMaskAppKitDefined = 1ULL << 13, NSEventMaskSystemDefined = 1ULL << 14,
    NSEventMaskApplicationDefined = 1ULL << 15, NSEventMaskPeriodic = 1ULL << 16, NSEventMaskCursorUpdate = 1ULL << 17,
    NSEventMaskScrollWheel = 1ULL << 22, NSEventMaskTabletPoint = 1ULL << 23, NSEventMaskTabletProximity = 1ULL << 24,
    NSEventMaskOtherMouseDown = 1ULL << 25, NSEventMaskOtherMouseUp = 1ULL << 26,
    NSEventMaskOtherMouseDragged = 1ULL << 27, NSEventMaskGesture = 1ULL << 29, NSEventMaskMagnify = 1ULL << 30,
    NSEventMaskSwipe = 1ULL << 31, NSEventMaskRotate = 1ULL << 18, NSEventMaskBeginGesture = 1ULL << 19,
    NSEventMaskEndGesture = 1ULL << 20, NSEventMaskSmartMagnify = 1ULL << 32, NSEventMaskPressure = 1ULL << 34,
    NSEventMaskDirectTouch = 1ULL << 37, NSEventMaskChangeMode = 1ULL << 38,
    NSEventMaskAny = ~0ULL
} NS_SWIFT_NAME(NSEvent.EventTypeMask);
static inline NSEventMask NSEventMaskFromType(NSUInteger type) { return 1ULL << type; }
typedef NS_ENUM(NSUInteger, NSCompositingOperation) {
    NSCompositingOperationClear = 0, NSCompositingOperationCopy = 1,
    NSCompositingOperationSourceOver = 2, NSCompositingOperationSourceIn = 3, NSCompositingOperationSourceOut = 4,
    NSCompositingOperationSourceAtop = 5, NSCompositingOperationDestinationOver = 6,
    NSCompositingOperationDestinationIn = 7, NSCompositingOperationDestinationOut = 8,
    NSCompositingOperationDestinationAtop = 9, NSCompositingOperationXOR = 10, NSCompositingOperationPlusDarker = 11,
    NSCompositingOperationPlusLighter = 13, NSCompositingOperationMultiply = 14, NSCompositingOperationScreen = 15,
    NSCompositingOperationOverlay = 16, NSCompositingOperationDarken = 17, NSCompositingOperationLighten = 18,
    NSCompositingOperationColorDodge = 19, NSCompositingOperationColorBurn = 20, NSCompositingOperationSoftLight = 21,
    NSCompositingOperationHardLight = 22, NSCompositingOperationDifference = 23, NSCompositingOperationExclusion = 24,
    NSCompositingOperationHue = 25, NSCompositingOperationSaturation = 26, NSCompositingOperationColor = 27,
    NSCompositingOperationLuminosity = 28,
};
typedef NS_ENUM(NSInteger, NSUserInterfaceLayoutDirection) {
    NSUserInterfaceLayoutDirectionLeftToRight = 0, NSUserInterfaceLayoutDirectionRightToLeft = 1,
};
typedef NS_OPTIONS(NSUInteger, NSAutoresizingMaskOptions) {
    NSViewNotSizable = 0, NSViewMinXMargin = 1, NSViewWidthSizable = 2, NSViewMaxXMargin = 4,
    NSViewMinYMargin = 8, NSViewHeightSizable = 16, NSViewMaxYMargin = 32,
};
typedef NS_ENUM(NSUInteger, NSControlSize) {
    NSControlSizeRegular = 0, NSControlSizeSmall = 1, NSControlSizeMini = 2, NSControlSizeLarge = 3
};
typedef NS_OPTIONS(NSUInteger, NSCursorFrameResizePosition) {
    NSCursorFrameResizePositionTop = 1 << 0, NSCursorFrameResizePositionLeft = 1 << 1,
    NSCursorFrameResizePositionBottom = 1 << 2, NSCursorFrameResizePositionRight = 1 << 3,
    NSCursorFrameResizePositionTopLeft = NSCursorFrameResizePositionTop | NSCursorFrameResizePositionLeft,
    NSCursorFrameResizePositionTopRight = NSCursorFrameResizePositionTop | NSCursorFrameResizePositionRight,
    NSCursorFrameResizePositionBottomLeft = NSCursorFrameResizePositionBottom | NSCursorFrameResizePositionLeft,
    NSCursorFrameResizePositionBottomRight = NSCursorFrameResizePositionBottom | NSCursorFrameResizePositionRight,
};

@class NSApplication, NSWindow, NSView, NSEvent, NSColor, NSFont, NSScreen, NSMenu, NSMenuItem,
    NSGraphicsContext, NSImage, NSResponder, NSAppearance, NSCursor, NSPasteboard, NSNotification, NSViewController,
    NSWindowController;

APPKIT_EXTERN void NSAccessibilityPostNotification(id element, NSAccessibilityNotificationName notification);
APPKIT_EXTERN void NSAccessibilityPostNotificationWithUserInfo(id element, NSAccessibilityNotificationName notification,
                                                               NSDictionary *userInfo);
#endif
