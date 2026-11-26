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
typedef NS_OPTIONS(unsigned long long, NSEventMask) { NSEventMaskAny = ~0ULL } NS_SWIFT_NAME(NSEvent.EventTypeMask);
typedef NS_ENUM(NSUInteger, NSCompositingOperation) {
    NSCompositingOperationClear = 0, NSCompositingOperationCopy = 1,
    NSCompositingOperationSourceOver = 2,
};
typedef NS_ENUM(NSInteger, NSUserInterfaceLayoutDirection) {
    NSUserInterfaceLayoutDirectionLeftToRight = 0, NSUserInterfaceLayoutDirectionRightToLeft = 1,
};
typedef NS_OPTIONS(NSUInteger, NSAutoresizingMaskOptions) {
    NSViewNotSizable = 0, NSViewMinXMargin = 1, NSViewWidthSizable = 2, NSViewMaxXMargin = 4,
    NSViewMinYMargin = 8, NSViewHeightSizable = 16, NSViewMaxYMargin = 32,
};
typedef NS_ENUM(NSInteger, NSCursorFrameResizePosition) {
    NSCursorFrameResizePositionTop = 1 << 0, NSCursorFrameResizePositionLeft = 1 << 1,
    NSCursorFrameResizePositionBottom = 1 << 2, NSCursorFrameResizePositionRight = 1 << 3,
};

@class NSApplication, NSWindow, NSView, NSEvent, NSColor, NSFont, NSScreen, NSMenu, NSMenuItem,
    NSGraphicsContext, NSImage, NSResponder, NSAppearance, NSCursor, NSPasteboard, NSNotification, NSViewController,
    NSWindowController;

APPKIT_EXTERN void NSAccessibilityPostNotification(id element, NSAccessibilityNotificationName notification);
APPKIT_EXTERN void NSAccessibilityPostNotificationWithUserInfo(id element, NSAccessibilityNotificationName notification,
                                                               NSDictionary *userInfo);
#endif
