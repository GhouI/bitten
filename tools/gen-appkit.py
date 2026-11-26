#!/usr/bin/env python3
"""Generate the AppKit skeleton: every class AppKit exports, in its place in
the class hierarchy, and every exported constant, with the values the public
documentation gives.

  gen-appkit.py header > sdk/include/AppKit/AppKitClasses.h
  gen-appkit.py source > build/.../AppKitClasses.m

The classes' behaviour is written by hand in frameworks/AppKit/*.m (as
categories or full @implementations listed in HANDWRITTEN below); this
table only guarantees that every class and symbol programs link against
exists, so that loading and subclassing work."""
import sys

# class, superclass. Order: superclasses first.
CLASSES = [
    ("NSResponder", "NSObject"),
    ("NSView", "NSResponder"),
    ("NSControl", "NSView"),
    ("NSButton", "NSControl"),
    ("NSTextField", "NSControl"),
    ("NSSecureTextField", "NSTextField"),
    ("NSImageView", "NSControl"),
    ("NSColorWell", "NSControl"),
    ("NSSegmentedControl", "NSControl"),
    ("NSScroller", "NSControl"),
    ("NSText", "NSView"),
    ("NSTextView", "NSText"),
    ("NSClipView", "NSView"),
    ("NSScrollView", "NSView"),
    ("NSVisualEffectView", "NSView"),
    ("NSProgressIndicator", "NSView"),
    ("NSWindow", "NSResponder"),
    ("NSPanel", "NSWindow"),
    ("NSSavePanel", "NSPanel"),
    ("NSOpenPanel", "NSSavePanel"),
    ("NSWindowController", "NSResponder"),
    ("NSViewController", "NSResponder"),
    ("NSSplitViewController", "NSViewController"),
    ("NSTitlebarAccessoryViewController", "NSViewController"),
    ("NSApplication", "NSResponder"),
    ("NSPopover", "NSResponder"),
    ("NSCell", "NSObject"),
    ("NSActionCell", "NSCell"),
    ("NSButtonCell", "NSActionCell"),
    ("NSTextFieldCell", "NSActionCell"),
    ("NSMenu", "NSObject"),
    ("NSMenuItem", "NSObject"),
    ("NSColor", "NSObject"),
    ("NSColorSpace", "NSObject"),
    ("NSFont", "NSObject"),
    ("NSFontManager", "NSObject"),
    ("NSImage", "NSObject"),
    ("NSImageRep", "NSObject"),
    ("NSBitmapImageRep", "NSImageRep"),
    ("NSImageSymbolConfiguration", "NSObject"),
    ("NSParagraphStyle", "NSObject"),
    ("NSMutableParagraphStyle", "NSParagraphStyle"),
    ("NSShadow", "NSObject"),
    ("NSGradient", "NSObject"),
    ("NSBezierPath", "NSObject"),
    ("NSGraphicsContext", "NSObject"),
    ("NSAppearance", "NSObject"),
    ("NSAnimationContext", "NSObject"),
    ("NSEvent", "NSObject"),
    ("NSCursor", "NSObject"),
    ("NSTrackingArea", "NSObject"),
    ("NSScreen", "NSObject"),
    ("NSWorkspace", "NSObject"),
    ("NSRunningApplication", "NSObject"),
    ("NSWorkspaceOpenConfiguration", "NSObject"),
    ("NSAlert", "NSObject"),
    ("NSSound", "NSObject"),
    ("NSStatusBar", "NSObject"),
    ("NSPasteboard", "NSObject"),
    ("NSPasteboardItem", "NSObject"),
    ("NSDraggingItem", "NSObject"),
    ("NSToolbar", "NSObject"),
    ("NSToolbarItem", "NSObject"),
    ("NSToolbarItemGroup", "NSToolbarItem"),
    ("NSMenuToolbarItem", "NSToolbarItem"),
    ("NSSplitViewItem", "NSObject"),
    ("NSGestureRecognizer", "NSObject"),
    ("NSClickGestureRecognizer", "NSGestureRecognizer"),
    ("NSPressGestureRecognizer", "NSGestureRecognizer"),
    ("NSTouchBar", "NSObject"),
    ("NSTouchBarItem", "NSObject"),
    ("NSCustomTouchBarItem", "NSTouchBarItem"),
    ("NSTextAttachment", "NSObject"),
    ("NSTextContainer", "NSObject"),
    ("NSLayoutManager", "NSObject"),
    ("NSTextContentManager", "NSObject"),
    ("NSTextContentStorage", "NSTextContentManager"),
    ("NSTextLayoutManager", "NSObject"),
    ("NSTextRange", "NSObject"),
    ("NSTextInputContext", "NSObject"),
    ("NSAccessibilityCustomAction", "NSObject"),
    ("NSHapticFeedbackManager", "NSObject"),
]

# Classes whose @interface and @implementation are hand-written
# (sdk/include/AppKit/*.h, frameworks/AppKit/*.m) because they carry state.
HANDWRITTEN = {"NSResponder", "NSView", "NSWindow", "NSApplication", "NSEvent",
               "NSColor", "NSFont", "NSScreen", "NSGraphicsContext", "NSMenu",
               "NSMenuItem", "NSControl", "NSAppearance", "NSBezierPath", "NSWorkspace", "NSRunningApplication", "NSWorkspaceOpenConfiguration",
               "NSViewController", "NSWindowController", "NSImage", "NSImageRep", "NSBitmapImageRep",
               "NSImageSymbolConfiguration", "NSPasteboard", "NSPasteboardItem", "NSColorSpace", "NSVisualEffectView", "NSAnimationContext", "NSShadow", "NSTrackingArea", "NSScroller", "NSClipView", "NSScrollView", "NSTextField", "NSImageView", "NSButton", "NSProgressIndicator", "NSSegmentedControl", "NSCursor", "NSParagraphStyle", "NSMutableParagraphStyle", "NSGradient", "NSSound", "NSHapticFeedbackManager", "NSAccessibilityCustomAction", "NSGestureRecognizer", "NSClickGestureRecognizer", "NSPressGestureRecognizer", "NSToolbar", "NSToolbarItem", "NSToolbarItemGroup", "NSMenuToolbarItem", "NSTitlebarAccessoryViewController", "NSPopover", "NSAlert", "NSStatusBar", "NSSplitViewController", "NSSplitViewItem"}

NOTIFICATIONS = """
NSToolbarWillAddItemNotification NSToolbarDidRemoveItemNotification NSPopoverWillShowNotification
NSPopoverDidCloseNotification
NSApplicationDidBecomeActiveNotification NSApplicationDidChangeScreenParametersNotification
NSApplicationDidHideNotification NSApplicationDidResignActiveNotification NSApplicationWillHideNotification
NSApplicationWillUnhideNotification
NSApplicationDidUnhideNotification NSApplicationWillBecomeActiveNotification
NSApplicationWillResignActiveNotification NSApplicationWillTerminateNotification
NSApplicationDidFinishLaunchingNotification NSApplicationWillFinishLaunchingNotification
NSWindowDidBecomeKeyNotification NSWindowDidBecomeMainNotification
NSWindowDidChangeOcclusionStateNotification NSWindowDidChangeScreenNotification
NSWindowDidDeminiaturizeNotification NSWindowDidEndLiveResizeNotification
NSWindowDidEndSheetNotification NSWindowDidEnterFullScreenNotification
NSWindowDidExitFullScreenNotification NSWindowDidMiniaturizeNotification
NSWindowDidMoveNotification NSWindowDidResignKeyNotification NSWindowDidResignMainNotification
NSWindowDidResizeNotification NSWindowDidUpdateNotification NSWindowWillBeginSheetNotification
NSWindowWillCloseNotification NSWindowWillEnterFullScreenNotification
NSWindowWillExitFullScreenNotification NSWindowWillStartLiveResizeNotification
NSViewFrameDidChangeNotification NSViewBoundsDidChangeNotification
NSWorkspaceSessionDidBecomeActiveNotification NSWorkspaceScreensDidWakeNotification
NSWorkspaceDidWakeNotification NSWorkspaceDidUnhideApplicationNotification
NSWorkspaceDidTerminateApplicationNotification NSWorkspaceDidLaunchApplicationNotification
NSWorkspaceDidHideApplicationNotification NSWorkspaceDidActivateApplicationNotification
NSWorkspaceActiveSpaceDidChangeNotification
NSTextViewDidChangeSelectionNotification NSTextInputContextKeyboardSelectionDidChangeNotification
NSSystemColorsDidChangeNotification NSScrollViewWillStartLiveScrollNotification
NSScrollViewDidLiveScrollNotification NSScrollViewDidEndLiveScrollNotification
NSPreferredScrollerStyleDidChangeNotification NSPopoverWillCloseNotification
NSPopoverDidShowNotification NSMenuWillSendActionNotification NSMenuDidRemoveItemNotification
NSMenuDidEndTrackingNotification NSMenuDidChangeItemNotification NSMenuDidBeginTrackingNotification
NSMenuDidAddItemNotification NSFontSetChangedNotification
NSAccessibilityValueChangedNotification NSAccessibilityTitleChangedNotification
NSAccessibilitySelectedTextChangedNotification NSAccessibilityAnnouncementRequestedNotification
""".split()

# String constants whose value is their own name (Apple's convention for
# keys and identifiers); some documented values differ and are listed in
# STRING_VALUES.
STRINGS = """
NSWorkspaceApplicationKey NSValueTransformerNameBindingOption NSValueBinding NSTitleBinding
NSMaxValueBinding NSHiddenBinding
NSParagraphStyleAttributeName NSForegroundColorAttributeName NSFontAttributeName
NSUnderlineStyleAttributeName NSBaselineOffsetAttributeName NSBackgroundColorAttributeName
NSToolbarSidebarTrackingSeparatorItemIdentifier NSToolbarFlexibleSpaceItemIdentifier
NSToolbarSpaceItemIdentifier NSToolbarToggleSidebarItemIdentifier NSToolbarShowColorsItemIdentifier
NSToolbarShowFontsItemIdentifier NSToolbarPrintItemIdentifier NSToolbarCloudSharingItemIdentifier
NSToolbarInspectorTrackingSeparatorItemIdentifier NSToolbarToggleInspectorItemIdentifier
NSPasteboardURLReadingFileURLsOnlyKey
NSImageHintInterpolation NSImageHintCTM NSImageNameApplicationIcon
NSFontTextStyleTitle3 NSFontTextStyleTitle2 NSFontTextStyleSubheadline NSFontTextStyleFootnote
NSFontTextStyleCaption1 NSFontTextStyleBody NSFontTextStyleHeadline NSFontTextStyleTitle1
NSFontTextStyleLargeTitle NSFontTextStyleCallout NSFontTextStyleCaption2
NSFontCascadeListAttribute
NSEventTrackingRunLoopMode NSDeviceRGBColorSpace
NSAppearanceNameDarkAqua NSAppearanceNameAqua
NSAccessibilityTextAreaRole NSAccessibilityStaticTextRole NSAccessibilitySplitterRole
NSAccessibilitySplitGroupRole NSAccessibilityRowRole NSAccessibilityRadioButtonRole
NSAccessibilityListRole NSAccessibilityImageRole NSAccessibilityHandleRole NSAccessibilityGroupRole
NSAccessibilityButtonRole NSAccessibilityAnnouncementKey
""".split()

# Documented values that are not simply the constant's name.
STRING_VALUES = {
    "NSAppearanceNameAqua": "NSAppearanceNameAqua",
    "NSAppearanceNameDarkAqua": "NSAppearanceNameDarkAqua",
    "NSValueBinding": "value",
    "NSTitleBinding": "title",
    "NSHiddenBinding": "hidden",
    "NSMaxValueBinding": "maxValue",
    "NSImageNameApplicationIcon": "NSApplicationIcon",
    "NSFontAttributeName": "NSFont",
    "NSForegroundColorAttributeName": "NSColor",
    "NSBackgroundColorAttributeName": "NSBackgroundColor",
    "NSParagraphStyleAttributeName": "NSParagraphStyle",
    "NSUnderlineStyleAttributeName": "NSUnderline",
    "NSBaselineOffsetAttributeName": "NSBaselineOffset",
    "NSAccessibilityButtonRole": "AXButton",
    "NSAccessibilityGroupRole": "AXGroup",
    "NSAccessibilityImageRole": "AXImage",
    "NSAccessibilityListRole": "AXList",
    "NSAccessibilityRowRole": "AXRow",
    "NSAccessibilityRadioButtonRole": "AXRadioButton",
    "NSAccessibilitySplitGroupRole": "AXSplitGroup",
    "NSAccessibilitySplitterRole": "AXSplitter",
    "NSAccessibilityStaticTextRole": "AXStaticText",
    "NSAccessibilityTextAreaRole": "AXTextArea",
    "NSAccessibilityHandleRole": "AXHandle",
}

# CGFloat constants (NSFontWeight values are the documented weights).
FLOATS = {
    "NSFontWeightUltraLight": -0.8, "NSFontWeightThin": -0.6, "NSFontWeightLight": -0.4,
    "NSFontWeightRegular": 0.0, "NSFontWeightMedium": 0.23, "NSFontWeightSemibold": 0.3,
    "NSFontWeightBold": 0.4, "NSFontWeightHeavy": 0.56, "NSFontWeightBlack": 0.62,
    "NSViewNoIntrinsicMetric": -1.0,
}


def header():
    out = ["/* Generated by tools/gen-appkit.py: the AppKit classes that have no",
           " * hand-written interface yet, and the exported constants. */",
           "#import <AppKit/AppKitBase.h>", "", "#pragma clang assume_nonnull begin"]
    for c, s in CLASSES:
        if c not in HANDWRITTEN:
            out.append(f"@interface {c} : {s}\n@end")
    out.append("")
    for n in NOTIFICATIONS:
        out.append(f"APPKIT_EXTERN NSNotificationName const {n};")
    for n in STRINGS:
        out.append(f"APPKIT_EXTERN NSString *const {n};")
    for n in FLOATS:
        out.append(f"APPKIT_EXTERN const CGFloat {n};")
    out.append("#pragma clang assume_nonnull end")
    return "\n".join(out) + "\n"


def source():
    out = ["/* Generated by tools/gen-appkit.py. */",
           "#import <AppKit/AppKit.h>", ""]
    for c, s in CLASSES:
        if c not in HANDWRITTEN:
            out.append(f"@implementation {c}\n@end")
    out.append("")
    for n in NOTIFICATIONS + STRINGS:
        v = STRING_VALUES.get(n, n)
        out.append(f'NSString *const {n} = @"{v}";')
    for n, v in FLOATS.items():
        out.append(f"const CGFloat {n} = {v};")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    sys.stdout.write(header() if sys.argv[1] == "header" else source())
