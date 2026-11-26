/* bitten SDK: the stateful core of AppKit (hand-written in frameworks/AppKit).
 * Written from the public documentation. */
#import <AppKit/AppKitBase.h>

#pragma clang assume_nonnull begin

@interface NSResponder : NSObject
@property (nullable, assign) NSResponder *nextResponder;
@property (readonly) BOOL acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
- (void)mouseDown:(NSEvent *)event NS_SWIFT_NAME(mouseDown(with:));
- (void)mouseUp:(NSEvent *)event NS_SWIFT_NAME(mouseUp(with:));
- (void)mouseDragged:(NSEvent *)event NS_SWIFT_NAME(mouseDragged(with:));
- (void)mouseMoved:(NSEvent *)event NS_SWIFT_NAME(mouseMoved(with:));
- (void)rightMouseDown:(NSEvent *)event NS_SWIFT_NAME(rightMouseDown(with:));
- (void)scrollWheel:(NSEvent *)event NS_SWIFT_NAME(scrollWheel(with:));
- (void)keyDown:(NSEvent *)event NS_SWIFT_NAME(keyDown(with:));
- (void)keyUp:(NSEvent *)event NS_SWIFT_NAME(keyUp(with:));
- (void)flagsChanged:(NSEvent *)event NS_SWIFT_NAME(flagsChanged(with:));
@end

@class CALayer;
typedef NS_ENUM(NSInteger, NSViewLayerContentsRedrawPolicy) {
    NSViewLayerContentsRedrawNever = 0, NSViewLayerContentsRedrawOnSetNeedsDisplay = 1,
    NSViewLayerContentsRedrawDuringViewResize = 2, NSViewLayerContentsRedrawBeforeViewResize = 3,
    NSViewLayerContentsRedrawCrossfade = 4
};
typedef NS_ENUM(NSInteger, NSViewLayerContentsPlacement) {
    NSViewLayerContentsPlacementScaleAxesIndependently = 0, NSViewLayerContentsPlacementScaleProportionallyToFit = 1,
    NSViewLayerContentsPlacementScaleProportionallyToFill = 2, NSViewLayerContentsPlacementCenter = 3,
    NSViewLayerContentsPlacementTop = 4, NSViewLayerContentsPlacementTopRight = 5,
    NSViewLayerContentsPlacementRight = 6, NSViewLayerContentsPlacementBottomRight = 7,
    NSViewLayerContentsPlacementBottom = 8, NSViewLayerContentsPlacementBottomLeft = 9,
    NSViewLayerContentsPlacementLeft = 10, NSViewLayerContentsPlacementTopLeft = 11
};
@interface NSView : NSResponder {
@protected
    NSRect _frame;
    NSRect _bounds;
    NSMutableArray *_subviews;
    NSView *_superview;
    NSWindow *_window;
    BOOL _needsDisplay, _hidden, _wantsLayer;
    NSAutoresizingMaskOptions _autoresizingMask;
}
- (instancetype)initWithFrame:(NSRect)frame;
@property NSRect frame;
@property NSRect bounds;
@property (readonly, copy) NSArray<NSView *> *subviews;
@property (nullable, readonly, assign) NSView *superview;
@property (nullable, readonly, assign) NSWindow *window;
@property BOOL needsDisplay;
@property (getter=isHidden) BOOL hidden;
@property BOOL wantsLayer;
@property (nullable, strong) CALayer *layer;
- (CALayer *)makeBackingLayer;
@property (readonly) BOOL wantsUpdateLayer;
- (void)updateLayer;
@property NSViewLayerContentsRedrawPolicy layerContentsRedrawPolicy;
@property NSViewLayerContentsPlacement layerContentsPlacement;
@property BOOL canDrawSubviewsIntoLayer;
@property NSAutoresizingMaskOptions autoresizingMask;
@property (readonly, getter=isFlipped) BOOL flipped;
- (void)addSubview:(NSView *)view;
- (void)removeFromSuperview;
- (void)setNeedsDisplayInRect:(NSRect)rect;
- (void)display;
- (void)drawRect:(NSRect)dirtyRect;
- (void)layout;
- (void)viewDidMoveToWindow;
- (void)viewWillMoveToWindow:(nullable NSWindow *)window;
- (NSPoint)convertPoint:(NSPoint)point fromView:(nullable NSView *)view;
- (NSPoint)convertPoint:(NSPoint)point toView:(nullable NSView *)view;
- (nullable NSView *)hitTest:(NSPoint)point;
@end

@interface NSControl : NSView
@property (nullable, weak) id target;
@property (nullable) SEL action;
@property (getter=isEnabled) BOOL enabled;
@property (copy) NSString *stringValue;
@property double doubleValue;
@property NSInteger integerValue;
@property (strong) NSFont *font;
@end

@protocol NSWindowDelegate <NSObject>
@optional
- (BOOL)windowShouldClose:(NSWindow *)sender;
- (void)windowWillClose:(NSNotification *)notification;
- (void)windowDidResize:(NSNotification *)notification;
- (void)windowDidBecomeKey:(NSNotification *)notification;
@end

@interface NSWindow : NSResponder {
@protected
    NSRect _frame;
    NSView *_contentView;
    NSString *_title;
    NSWindowStyleMask _styleMask;
    BOOL _visible, _key;
    NSUInteger _windowNumber;
    id _contentViewController;
}
- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)flag;
@property (nullable, strong) NSView *contentView;
@property (nullable, strong) NSViewController *contentViewController;
@property (copy) NSString *title;
@property NSWindowStyleMask styleMask;
@property (readonly) NSRect frame;
@property (readonly, getter=isVisible) BOOL visible;
@property (readonly, getter=isKeyWindow) BOOL keyWindow;
@property (readonly) NSInteger windowNumber;
@property (nullable, weak) id<NSWindowDelegate> delegate;
@property (strong) NSColor *backgroundColor;
- (void)setFrame:(NSRect)frame display:(BOOL)flag;
- (void)setContentSize:(NSSize)size;
- (void)makeKeyAndOrderFront:(nullable id)sender;
- (void)orderFront:(nullable id)sender;
- (void)orderOut:(nullable id)sender;
- (void)close;
- (void)center;
- (void)display;
- (NSRect)contentRectForFrameRect:(NSRect)frameRect;
- (NSRect)frameRectForContentRect:(NSRect)contentRect;
@end

@protocol NSApplicationDelegate <NSObject>
@optional
- (void)applicationWillFinishLaunching:(NSNotification *)notification;
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)notification;
- (void)applicationDidBecomeActive:(NSNotification *)notification;
- (void)applicationDidResignActive:(NSNotification *)notification;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender;
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag;
- (nullable NSMenu *)applicationDockMenu:(NSApplication *)sender;
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls;
@end

APPKIT_EXTERN NSAppearanceName const NSAppearanceNameVibrantDark, NSAppearanceNameVibrantLight,
    NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua,
    NSAppearanceNameAccessibilityHighContrastVibrantLight, NSAppearanceNameAccessibilityHighContrastVibrantDark,
    NSAppearanceNameLightContent;
@interface NSAppearance : NSObject
+ (nullable NSAppearance *)appearanceNamed:(NSAppearanceName)name;
- (nullable instancetype)initWithAppearanceNamed:(NSAppearanceName)name bundle:(nullable NSBundle *)bundle;
@property (readonly, copy) NSAppearanceName name;
@property (readonly) BOOL allowsVibrancy;
- (nullable NSAppearanceName)bestMatchFromAppearancesWithNames:(NSArray<NSAppearanceName> *)appearances;
@property (class, readonly, strong) NSAppearance *currentDrawingAppearance;
@property (class, null_resettable, strong) NSAppearance *currentAppearance;
- (void)performAsCurrentDrawingAppearance:(NS_NOESCAPE void (^)(void))block;
@end
@protocol NSAppearanceCustomization <NSObject>
@property (nullable, strong) NSAppearance *appearance;
@property (readonly, strong) NSAppearance *effectiveAppearance;
@end
@interface NSView (NSAppearanceCustomization) <NSAppearanceCustomization>
@property (nullable, strong) NSAppearance *appearance;
@property (readonly, strong) NSAppearance *effectiveAppearance;
- (void)viewDidChangeEffectiveAppearance;
@end
@interface NSWindow (NSAppearanceCustomization) <NSAppearanceCustomization>
@property (nullable, strong) NSAppearance *appearance;
@property (readonly, strong) NSAppearance *effectiveAppearance;
@end

@interface NSApplication : NSResponder
@property (class, readonly, strong) NSApplication *sharedApplication;
@property (nullable, weak) id<NSApplicationDelegate> delegate;
@property (readonly, copy) NSArray<NSWindow *> *windows;
@property (nullable, readonly, assign) NSWindow *keyWindow;
@property (nullable, readonly, assign) NSWindow *mainWindow;
@property (nullable, strong) NSMenu *mainMenu;
- (BOOL)sendAction:(SEL)action to:(nullable id)target from:(nullable id)sender;
- (nullable id)targetForAction:(SEL)action;
- (nullable id)targetForAction:(SEL)action to:(nullable id)target from:(nullable id)sender;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly, getter=isActive) BOOL active;
@property (nullable, strong) NSAppearance *appearance;
@property (readonly, strong) NSAppearance *effectiveAppearance;
- (void)run;
- (void)finishLaunching;
- (void)stop:(nullable id)sender;
- (void)terminate:(nullable id)sender;
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)policy;
- (void)activateIgnoringOtherApps:(BOOL)flag;
- (void)activate;
- (nullable NSEvent *)nextEventMatchingMask:(NSEventMask)mask untilDate:(nullable NSDate *)expiration
                            inMode:(NSRunLoopMode)mode dequeue:(BOOL)deqFlag;
- (void)sendEvent:(NSEvent *)event;
@end

typedef NS_OPTIONS(NSUInteger, NSApplicationPresentationOptions) {
    NSApplicationPresentationDefault = 0, NSApplicationPresentationAutoHideDock = 1 << 0,
    NSApplicationPresentationHideDock = 1 << 1, NSApplicationPresentationAutoHideMenuBar = 1 << 2,
    NSApplicationPresentationHideMenuBar = 1 << 3, NSApplicationPresentationFullScreen = 1 << 10,
    NSApplicationPresentationAutoHideToolbar = 1 << 11
} NS_SWIFT_NAME(NSApplication.PresentationOptions);
typedef NS_ENUM(NSUInteger, NSRequestUserAttentionType) { NSCriticalRequest = 0, NSInformationalRequest = 10 } NS_SWIFT_NAME(NSApplication.RequestUserAttentionType);
typedef NS_OPTIONS(NSUInteger, NSApplicationOcclusionState) { NSApplicationOcclusionStateVisible = 1UL << 1 } NS_SWIFT_NAME(NSApplication.OcclusionState);
typedef NSString *NSAboutPanelOptionKey NS_TYPED_ENUM NS_SWIFT_NAME(NSApplication.AboutPanelOptionKey);
@class NSDockTile;

@interface NSApplication (BittenApplicationState)
@property (readonly) NSApplicationActivationPolicy activationPolicy;
@property (readonly, getter=isHidden) BOOL hidden;
- (void)hide:(nullable id)sender;
- (void)unhide:(nullable id)sender;
- (void)unhideWithoutActivation;
- (void)hideOtherApplications:(nullable id)sender;
- (void)unhideAllApplications:(nullable id)sender;
- (void)deactivate;
- (void)yieldActivationToApplication:(id)application;
- (void)orderFrontStandardAboutPanel:(nullable id)sender;
- (void)orderFrontStandardAboutPanelWithOptions:(NSDictionary<NSAboutPanelOptionKey, id> *)optionsDictionary;
- (void)orderFrontCharacterPalette:(nullable id)sender;
@property (nullable, strong) NSImage *applicationIconImage;
@property (nullable, strong) NSMenu *windowsMenu;
@property (nullable, strong) NSMenu *servicesMenu;
@property (nullable, strong) NSMenu *helpMenu;
@property (nullable, readonly, strong) NSEvent *currentEvent;
- (void)postEvent:(NSEvent *)event atStart:(BOOL)flag;
- (void)discardEventsMatchingMask:(NSEventMask)mask beforeEvent:(nullable NSEvent *)lastEvent;
- (NSInteger)requestUserAttention:(NSRequestUserAttentionType)requestType;
- (void)cancelUserAttentionRequest:(NSInteger)request;
- (NSModalResponse)runModalForWindow:(NSWindow *)window;
- (void)stopModal;
- (void)stopModalWithCode:(NSModalResponse)returnCode;
- (void)abortModal;
@property (nullable, readonly, strong) NSWindow *modalWindow;
@property NSApplicationPresentationOptions presentationOptions;
@property (readonly) NSApplicationPresentationOptions currentSystemPresentationOptions;
@property (readonly) NSApplicationOcclusionState occlusionState;
@property (readonly) NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;
@property (getter=isAutomaticCustomizeTouchBarMenuItemEnabled) BOOL automaticCustomizeTouchBarMenuItemEnabled;
- (void)replyToApplicationShouldTerminate:(BOOL)shouldTerminate;
- (void)updateWindows;
- (void)setWindowsNeedUpdate:(BOOL)needUpdate;
- (void)arrangeInFront:(nullable id)sender;
- (void)miniaturizeAll:(nullable id)sender;
- (void)registerForRemoteNotifications;
- (void)unregisterForRemoteNotifications;
@property (readonly, getter=isRegisteredForRemoteNotifications) BOOL registeredForRemoteNotifications;
- (void)registerServicesMenuSendTypes:(NSArray<NSString *> *)sendTypes returnTypes:(NSArray<NSString *> *)returnTypes;
- (nullable NSWindow *)windowWithWindowNumber:(NSInteger)windowNum;
- (void)enumerateWindowsWithOptions:(NSUInteger)options usingBlock:(void (^)(NSWindow *window, BOOL *stop))block;
- (void)setActivationPolicyAndActivate:(NSApplicationActivationPolicy)policy;
@end
APPKIT_EXTERN NSApplication *NSApp;
APPKIT_EXTERN int NSApplicationMain(int argc, const char *argv[]);

@interface NSEvent : NSObject
@property (readonly) NSEventType type;
@property (readonly) NSEventModifierFlags modifierFlags;
@property (readonly) NSTimeInterval timestamp;
@property (nullable, readonly, weak) NSWindow *window;
@property (readonly) NSPoint locationInWindow;
@property (readonly) NSInteger clickCount;
@property (nullable, readonly, copy) NSString *characters;
@property (nullable, readonly, copy) NSString *charactersIgnoringModifiers;
@property (readonly) unsigned short keyCode;
@property (readonly) CGFloat scrollingDeltaX;
@property (readonly) CGFloat scrollingDeltaY;
+ (NSPoint)mouseLocation;
+ (NSEventModifierFlags)modifierFlags;
+ (nullable NSEvent *)mouseEventWithType:(NSEventType)type location:(NSPoint)location
                           modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                            windowNumber:(NSInteger)wNum context:(nullable id)unusedPassNil
                             eventNumber:(NSInteger)eNum clickCount:(NSInteger)cNum pressure:(float)pressure;
+ (nullable NSEvent *)keyEventWithType:(NSEventType)type location:(NSPoint)location
                         modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                          windowNumber:(NSInteger)wNum context:(nullable id)unusedPassNil
                            characters:(NSString *)keys charactersIgnoringModifiers:(NSString *)ukeys
                             isARepeat:(BOOL)flag keyCode:(unsigned short)code;
@property (readonly) NSInteger windowNumber;
@property (readonly, getter=isARepeat) BOOL ARepeat;
@property (readonly) NSInteger buttonNumber;
@property (readonly) CGFloat deltaX;
@property (readonly) CGFloat deltaY;
@property (readonly) BOOL hasPreciseScrollingDeltas;
- (nullable NSString *)charactersByApplyingModifiers:(NSEventModifierFlags)modifiers;
@end

@class NSColorSpace, NSAppearance;
@interface NSColor : NSObject <NSCopying>
+ (NSColor *)colorWithSRGBRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithWhite:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
@property (class, strong, readonly) NSColor *blackColor, *whiteColor, *clearColor, *redColor,
    *greenColor, *blueColor, *grayColor, *labelColor, *secondaryLabelColor, *textColor,
    *textBackgroundColor, *windowBackgroundColor, *controlBackgroundColor, *controlAccentColor,
    *separatorColor, *selectedContentBackgroundColor;
@property (readonly) CGFloat redComponent, greenComponent, blueComponent, alphaComponent;
@property (readonly) CGColorRef CGColor NS_SWIFT_NAME(cgColor);
+ (NSColor *)colorWithCGColor:(CGColorRef)cgColor;
- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha;
- (void)set;
- (void)setFill;
- (void)setStroke;
+ (NSColor *)colorWithDisplayP3Red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithColorSpace:(NSColorSpace *)space components:(const CGFloat *)components count:(NSInteger)n;
+ (NSColor *)colorWithDeviceRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithDeviceWhite:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithCalibratedWhite:(CGFloat)w alpha:(CGFloat)a;
@property (readonly, strong) NSColorSpace *colorSpace;
- (nullable NSColor *)colorUsingColorSpace:(NSColorSpace *)space;
@property (readonly) NSInteger numberOfComponents;
- (void)getComponents:(CGFloat *)components;
- (void)getRed:(nullable CGFloat *)r green:(nullable CGFloat *)g blue:(nullable CGFloat *)b alpha:(nullable CGFloat *)a;
@property (readonly) CGFloat whiteComponent;
+ (NSColor *)colorWithName:(nullable NSColorName)name dynamicProvider:(NSColor * (^)(NSAppearance *appearance))provider;
- (nullable NSColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(NSColor *)color;
- (nullable NSColor *)highlightWithLevel:(CGFloat)level;
- (nullable NSColor *)shadowWithLevel:(CGFloat)level;
@property (class, strong, readonly) NSColor *systemRedColor, *systemOrangeColor, *systemYellowColor, *systemGreenColor,
    *systemMintColor, *systemTealColor, *systemCyanColor, *systemBlueColor, *systemIndigoColor, *systemPurpleColor,
    *systemPinkColor, *systemBrownColor, *systemGrayColor, *tertiaryLabelColor, *quaternaryLabelColor,
    *placeholderTextColor, *controlColor, *controlTextColor, *disabledControlTextColor, *selectedControlColor,
    *selectedControlTextColor, *alternateSelectedControlTextColor, *selectedMenuItemTextColor,
    *selectedTextBackgroundColor, *selectedTextColor, *unemphasizedSelectedContentBackgroundColor,
    *unemphasizedSelectedTextBackgroundColor, *underPageBackgroundColor, *tertiarySystemFillColor,
    *quaternarySystemFillColor, *secondarySystemFillColor, *systemFillColor, *linkColor,
    *keyboardFocusIndicatorColor, *gridColor, *headerTextColor, *findHighlightColor, *shadowColor, *highlightColor,
    *windowFrameTextColor, *scrubberTexturedBackgroundColor;
@end

typedef NS_ENUM(NSInteger, NSColorSpaceModel) {
    NSColorSpaceModelUnknown = -1, NSColorSpaceModelGray, NSColorSpaceModelRGB, NSColorSpaceModelCMYK,
    NSColorSpaceModelLAB, NSColorSpaceModelDeviceN, NSColorSpaceModelIndexed, NSColorSpaceModelPatterned
};

@interface NSColorSpace : NSObject <NSCopying>
@property (class, strong, readonly) NSColorSpace *sRGBColorSpace, *extendedSRGBColorSpace, *displayP3ColorSpace,
    *genericRGBColorSpace, *deviceRGBColorSpace, *genericGamma22GrayColorSpace,
    *extendedGenericGamma22GrayColorSpace, *deviceGrayColorSpace;
- (nullable instancetype)initWithCGColorSpace:(CGColorSpaceRef)cgColorSpace;
@property (nullable, readonly) CGColorSpaceRef CGColorSpace NS_SWIFT_NAME(cgColorSpace);
@property (readonly) NSColorSpaceModel colorSpaceModel;
@property (readonly) NSInteger numberOfColorComponents;
@property (nullable, readonly, copy) NSString *localizedName;
- (BOOL)isP3;
@end

@interface NSFont : NSObject <NSCopying>
+ (NSFont *)fontWithName:(NSString *)name size:(CGFloat)size;
+ (NSFont *)systemFontOfSize:(CGFloat)size;
+ (NSFont *)systemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSFont *)boldSystemFontOfSize:(CGFloat)size;
+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSFont *)userFixedPitchFontOfSize:(CGFloat)size;
+ (CGFloat)systemFontSize;
@property (readonly, copy) NSString *fontName;
@property (readonly) CGFloat pointSize;
@property (readonly) CGFloat ascender, descender, leading;
@end

@interface NSScreen : NSObject
@property (class, readonly, nullable, strong) NSScreen *mainScreen;
@property (class, readonly, copy) NSArray<NSScreen *> *screens;
@property (readonly) NSRect frame;
@property (readonly) NSRect visibleFrame;
@property (readonly) CGFloat backingScaleFactor;
@end


typedef NS_ENUM(NSInteger, NSWindowTitleVisibility) { NSWindowTitleVisible = 0, NSWindowTitleHidden = 1 } NS_SWIFT_NAME(NSWindow.TitleVisibility);
typedef NS_ENUM(NSInteger, NSWindowTabbingMode) {
    NSWindowTabbingModeAutomatic, NSWindowTabbingModePreferred, NSWindowTabbingModeDisallowed
} NS_SWIFT_NAME(NSWindow.TabbingMode);
typedef NS_ENUM(NSInteger, NSWindowUserTabbingPreference) {
    NSWindowUserTabbingPreferenceManual, NSWindowUserTabbingPreferenceAlways, NSWindowUserTabbingPreferenceInFullScreen
} NS_SWIFT_NAME(NSWindow.UserTabbingPreference);
typedef NS_OPTIONS(NSUInteger, NSWindowCollectionBehavior) {
    NSWindowCollectionBehaviorDefault = 0, NSWindowCollectionBehaviorCanJoinAllSpaces = 1 << 0,
    NSWindowCollectionBehaviorMoveToActiveSpace = 1 << 1, NSWindowCollectionBehaviorManaged = 1 << 2,
    NSWindowCollectionBehaviorTransient = 1 << 3, NSWindowCollectionBehaviorStationary = 1 << 4,
    NSWindowCollectionBehaviorParticipatesInCycle = 1 << 5, NSWindowCollectionBehaviorIgnoresCycle = 1 << 6,
    NSWindowCollectionBehaviorFullScreenPrimary = 1 << 7, NSWindowCollectionBehaviorFullScreenAuxiliary = 1 << 8,
    NSWindowCollectionBehaviorFullScreenNone = 1 << 9, NSWindowCollectionBehaviorFullScreenAllowsTiling = 1 << 11,
    NSWindowCollectionBehaviorFullScreenDisallowsTiling = 1 << 12, NSWindowCollectionBehaviorPrimary = 1 << 16,
    NSWindowCollectionBehaviorAuxiliary = 1 << 17, NSWindowCollectionBehaviorCanJoinAllApplications = 1 << 18
} NS_SWIFT_NAME(NSWindow.CollectionBehavior);
typedef NSInteger NSWindowLevel NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSWindow.Level);
static const NSWindowLevel NSNormalWindowLevel = 0;
static const NSWindowLevel NSFloatingWindowLevel = 3;
static const NSWindowLevel NSSubmenuWindowLevel = 3;
static const NSWindowLevel NSTornOffMenuWindowLevel = 3;
static const NSWindowLevel NSModalPanelWindowLevel = 8;
static const NSWindowLevel NSMainMenuWindowLevel = 24;
static const NSWindowLevel NSStatusWindowLevel = 25;
static const NSWindowLevel NSPopUpMenuWindowLevel = 101;
static const NSWindowLevel NSScreenSaverWindowLevel = 1000;
typedef NS_ENUM(NSUInteger, NSWindowButton) {
    NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton, NSWindowToolbarButton,
    NSWindowDocumentIconButton, NSWindowDocumentVersionsButton = 6
} NS_SWIFT_NAME(NSWindow.ButtonType);
typedef NS_ENUM(NSInteger, NSWindowToolbarStyle) {
    NSWindowToolbarStyleAutomatic, NSWindowToolbarStyleExpanded, NSWindowToolbarStylePreference,
    NSWindowToolbarStyleUnified, NSWindowToolbarStyleUnifiedCompact
} NS_SWIFT_NAME(NSWindow.ToolbarStyle);
typedef NS_ENUM(NSInteger, NSTitlebarSeparatorStyle) {
    NSTitlebarSeparatorStyleAutomatic, NSTitlebarSeparatorStyleNone, NSTitlebarSeparatorStyleLine,
    NSTitlebarSeparatorStyleShadow
};
typedef NS_ENUM(NSInteger, NSWindowAnimationBehavior) {
    NSWindowAnimationBehaviorDefault = 0, NSWindowAnimationBehaviorNone = 2, NSWindowAnimationBehaviorDocumentWindow,
    NSWindowAnimationBehaviorUtilityWindow, NSWindowAnimationBehaviorAlertPanel
} NS_SWIFT_NAME(NSWindow.AnimationBehavior);
typedef NS_ENUM(NSUInteger, NSWindowSharingType) {
    NSWindowSharingNone, NSWindowSharingReadOnly, NSWindowSharingReadWrite
} NS_SWIFT_NAME(NSWindow.SharingType);
typedef NS_ENUM(NSInteger, NSWindowOrderingMode) { NSWindowAbove = 1, NSWindowBelow = -1, NSWindowOut = 0 } NS_SWIFT_NAME(NSWindow.OrderingMode);
typedef NSString *NSWindowFrameAutosaveName NS_SWIFT_NAME(NSWindow.FrameAutosaveName);
typedef NSString *NSWindowTabbingIdentifier NS_SWIFT_NAME(NSWindow.TabbingIdentifier);
typedef NSString *NSUserInterfaceItemIdentifier NS_TYPED_EXTENSIBLE_ENUM;
@class NSButton, NSToolbar, NSWindowTab, NSWindowTabGroup, NSTitlebarAccessoryViewController;

@interface NSWindow (BittenWindowState)
@property (class) BOOL allowsAutomaticWindowTabbing;
@property (class, readonly) NSWindowUserTabbingPreference userTabbingPreference;
@property NSWindowTabbingMode tabbingMode;
@property (copy) NSWindowTabbingIdentifier tabbingIdentifier;
@property NSWindowTitleVisibility titleVisibility;
@property BOOL titlebarAppearsTransparent;
@property NSTitlebarSeparatorStyle titlebarSeparatorStyle;
@property NSWindowToolbarStyle toolbarStyle;
@property (nullable, strong) NSToolbar *toolbar;
@property (copy) NSString *subtitle;
@property NSWindowCollectionBehavior collectionBehavior;
@property NSWindowLevel level;
@property (getter=isOpaque) BOOL opaque;
@property BOOL hasShadow;
@property CGFloat alphaValue;
@property (getter=isMovable) BOOL movable;
@property (getter=isMovableByWindowBackground) BOOL movableByWindowBackground;
@property (getter=isReleasedWhenClosed) BOOL releasedWhenClosed;
@property BOOL hidesOnDeactivate;
@property BOOL canHide;
@property BOOL ignoresMouseEvents;
@property BOOL acceptsMouseMovedEvents;
@property (getter=isExcludedFromWindowsMenu) BOOL excludedFromWindowsMenu;
@property (getter=isRestorable) BOOL restorable;
@property (getter=isDocumentEdited) BOOL documentEdited;
@property (nullable, copy) NSURL *representedURL;
@property (nullable, copy) NSUserInterfaceItemIdentifier identifier;
@property NSWindowAnimationBehavior animationBehavior;
@property NSWindowSharingType sharingType;
@property BOOL preventsApplicationTerminationWhenModal;
@property NSSize minSize, maxSize, contentMinSize, contentMaxSize, aspectRatio, contentAspectRatio, resizeIncrements;
@property (readonly) NSRect contentLayoutRect;
@property (nullable, weak) NSView *initialFirstResponder;
@property (nullable, weak) NSWindowController *windowController;
@property (readonly, copy) NSWindowFrameAutosaveName frameAutosaveName;
- (BOOL)setFrameAutosaveName:(NSWindowFrameAutosaveName)name;
- (BOOL)setFrameUsingName:(NSWindowFrameAutosaveName)name;
- (BOOL)setFrameUsingName:(NSWindowFrameAutosaveName)name force:(BOOL)force;
- (void)saveFrameUsingName:(NSWindowFrameAutosaveName)name;
@property (readonly, getter=isMainWindow) BOOL mainWindow;
@property (readonly) BOOL canBecomeKeyWindow;
@property (readonly) BOOL canBecomeMainWindow;
- (void)makeKeyWindow;
- (void)makeMainWindow;
- (void)becomeKeyWindow;
- (void)resignKeyWindow;
- (void)orderFrontRegardless;
- (void)orderBack:(nullable id)sender;
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin;
@property (readonly, getter=isMiniaturized) BOOL miniaturized;
@property (readonly, getter=isZoomed) BOOL zoomed;
- (void)miniaturize:(nullable id)sender;
- (void)deminiaturize:(nullable id)sender;
- (void)performMiniaturize:(nullable id)sender;
- (void)zoom:(nullable id)sender;
- (void)performZoom:(nullable id)sender;
- (void)toggleFullScreen:(nullable id)sender;
- (void)toggleToolbarShown:(nullable id)sender;
- (nullable NSButton *)standardWindowButton:(NSWindowButton)b;
- (void)setFrameOrigin:(NSPoint)point;
- (void)setFrameTopLeftPoint:(NSPoint)point;
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)topLeftPoint;
- (void)setFrame:(NSRect)frameRect display:(BOOL)displayFlag animate:(BOOL)animateFlag;
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(nullable NSScreen *)screen;
@property (nullable, readonly, assign) NSScreen *screen;
@property (readonly) CGFloat backingScaleFactor;
- (NSRect)convertRectToScreen:(NSRect)rect;
- (NSRect)convertRectFromScreen:(NSRect)rect;
- (NSPoint)convertPointToScreen:(NSPoint)point;
- (NSPoint)convertPointFromScreen:(NSPoint)point;
- (NSRect)convertRectToBacking:(NSRect)rect;
- (NSRect)convertRectFromBacking:(NSRect)rect;
@property (readonly) NSPoint mouseLocationOutsideOfEventStream;
- (void)beginSheet:(NSWindow *)sheetWindow completionHandler:(void (^_Nullable)(NSModalResponse returnCode))handler;
- (void)beginCriticalSheet:(NSWindow *)sheetWindow completionHandler:(void (^_Nullable)(NSModalResponse returnCode))handler;
- (void)endSheet:(NSWindow *)sheetWindow;
- (void)endSheet:(NSWindow *)sheetWindow returnCode:(NSModalResponse)returnCode;
@property (nullable, readonly, strong) NSWindow *attachedSheet;
@property (readonly, copy) NSArray<NSWindow *> *sheets;
@property (nullable, readonly, strong) NSWindow *sheetParent;
@property (readonly, getter=isSheet) BOOL sheet;
@property (nullable, weak) NSWindow *parentWindow;
@property (nullable, readonly, copy) NSArray<NSWindow *> *childWindows;
- (void)addChildWindow:(NSWindow *)childWin ordered:(NSWindowOrderingMode)place;
- (void)removeChildWindow:(NSWindow *)childWin;
@property (copy) NSArray<NSTitlebarAccessoryViewController *> *titlebarAccessoryViewControllers;
- (void)addTitlebarAccessoryViewController:(NSTitlebarAccessoryViewController *)childViewController;
- (void)removeTitlebarAccessoryViewControllerAtIndex:(NSInteger)index;
@property (readonly, copy, nullable) NSArray<NSWindow *> *tabbedWindows;
- (void)addTabbedWindow:(NSWindow *)window ordered:(NSWindowOrderingMode)ordered;
- (void)selectNextTab:(nullable id)sender;
- (void)selectPreviousTab:(nullable id)sender;
- (void)mergeAllWindows:(nullable id)sender;
- (void)invalidateShadow;
- (void)update;
@property BOOL viewsNeedDisplay;
@property (readonly) NSInteger orderedIndex;
@end

@interface NSWindow (NSEvents)
@property (readonly, weak) NSResponder *firstResponder;
- (BOOL)makeFirstResponder:(nullable NSResponder *)responder;
- (void)sendEvent:(NSEvent *)event;
- (void)performClose:(nullable id)sender;
@end
@interface NSResponder (BittenEvents)
- (void)rightMouseUp:(NSEvent *)event;
@end
@interface NSWindow (BittenDisplay)
- (void)_bn_scheduleDisplay;
- (void)_bn_closeDisplay;
- (void)displayIfNeeded;
- (nullable CGContextRef)_bn_backingContext;
@end
@interface NSRunningApplication : NSObject
@property (class, readonly, strong) NSRunningApplication *currentApplication;
+ (nullable instancetype)runningApplicationWithProcessIdentifier:(pid_t)pid;
+ (NSArray<NSRunningApplication *> *)runningApplicationsWithBundleIdentifier:(NSString *)bundleIdentifier;
@property (readonly) pid_t processIdentifier;
@property (nullable, readonly, copy) NSString *bundleIdentifier;
@property (nullable, readonly, copy) NSURL *bundleURL;
@property (nullable, readonly, copy) NSURL *executableURL;
@property (nullable, readonly, copy) NSString *localizedName;
@property (nullable, readonly, strong) NSImage *icon;
@property (readonly, getter=isActive) BOOL active;
@property (readonly, getter=isHidden) BOOL hidden;
@property (readonly, getter=isTerminated) BOOL terminated;
@property (readonly, getter=isFinishedLaunching) BOOL finishedLaunching;
@property (readonly) NSApplicationActivationPolicy activationPolicy;
@property (nullable, readonly, copy) NSDate *launchDate;
- (BOOL)activateWithOptions:(NSUInteger)options;
- (BOOL)activateFromApplication:(NSRunningApplication *)application options:(NSUInteger)options;
- (BOOL)hide;
- (BOOL)unhide;
- (BOOL)terminate;
- (BOOL)forceTerminate;
@end
@interface NSWorkspaceOpenConfiguration : NSObject <NSCopying>
+ (instancetype)configuration;
@end
@interface NSWorkspace : NSObject
@property (class, readonly, strong) NSWorkspace *sharedWorkspace;
@property (readonly, strong) NSNotificationCenter *notificationCenter;
- (BOOL)openURL:(NSURL *)url;
- (void)openURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)configuration
    completionHandler:(void (^_Nullable)(NSRunningApplication *_Nullable app, NSError *_Nullable error))completionHandler;
- (void)openURLs:(NSArray<NSURL *> *)urls withApplicationAtURL:(NSURL *)applicationURL
    configuration:(NSWorkspaceOpenConfiguration *)configuration
    completionHandler:(void (^_Nullable)(NSRunningApplication *_Nullable app, NSError *_Nullable error))completionHandler;
- (void)openApplicationAtURL:(NSURL *)applicationURL configuration:(NSWorkspaceOpenConfiguration *)configuration
           completionHandler:(void (^_Nullable)(NSRunningApplication *_Nullable app, NSError *_Nullable error))completionHandler;
- (BOOL)openFile:(NSString *)fullPath;
- (BOOL)selectFile:(nullable NSString *)fullPath inFileViewerRootedAtPath:(NSString *)rootFullPath;
- (void)activateFileViewerSelectingURLs:(NSArray<NSURL *> *)fileURLs;
- (nullable NSURL *)URLForApplicationWithBundleIdentifier:(NSString *)bundleIdentifier;
- (nullable NSURL *)URLForApplicationToOpenURL:(NSURL *)url;
- (NSArray<NSURL *> *)URLsForApplicationsToOpenURL:(NSURL *)url;
- (nullable NSString *)fullPathForApplication:(NSString *)appName;
@property (nullable, readonly, strong) NSRunningApplication *frontmostApplication;
@property (nullable, readonly, strong) NSRunningApplication *menuBarOwningApplication;
@property (readonly, copy) NSArray<NSRunningApplication *> *runningApplications;
- (NSImage *)iconForFile:(NSString *)fullPath;
- (nullable NSImage *)iconForFiles:(NSArray<NSString *> *)fullPaths;
- (NSImage *)iconForContentType:(id)contentType;
- (BOOL)setIcon:(nullable NSImage *)image forFile:(NSString *)fullPath options:(NSUInteger)options;
- (BOOL)isFilePackageAtPath:(NSString *)fullPath;
- (void)recycleURLs:(NSArray<NSURL *> *)URLs
  completionHandler:(void (^_Nullable)(NSDictionary<NSURL *, NSURL *> *newURLs, NSError *_Nullable error))handler;
@property (readonly) BOOL accessibilityDisplayShouldReduceMotion;
@property (readonly) BOOL accessibilityDisplayShouldIncreaseContrast;
@property (readonly) BOOL accessibilityDisplayShouldReduceTransparency;
@property (readonly) BOOL accessibilityDisplayShouldDifferentiateWithoutColor;
@property (readonly) BOOL accessibilityDisplayShouldInvertColors;
@property (readonly, getter=isVoiceOverEnabled) BOOL voiceOverEnabled;
@property (readonly, getter=isSwitchControlEnabled) BOOL switchControlEnabled;
- (void)noteFileSystemChanged:(NSString *)path;
@end

@interface NSGraphicsContext : NSObject
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)graphicsPort flipped:(BOOL)initialFlippedState;
@property (class, nullable, strong) NSGraphicsContext *currentContext;
+ (BOOL)currentContextDrawingToScreen;
+ (void)saveGraphicsState;
+ (void)restoreGraphicsState;
- (void)saveGraphicsState;
- (void)restoreGraphicsState;
- (void)flushGraphics;
@property (readonly) CGContextRef CGContext;
@property (readonly, getter=isFlipped) BOOL flipped;
@property (readonly, getter=isDrawingToScreen) BOOL drawingToScreen;
@end

APPKIT_EXTERN void NSRectFill(NSRect rect);
APPKIT_EXTERN void NSRectFillUsingOperation(NSRect rect, NSCompositingOperation op);
APPKIT_EXTERN void NSFrameRect(NSRect rect);
APPKIT_EXTERN void NSFrameRectWithWidth(NSRect rect, CGFloat frameWidth);
APPKIT_EXTERN void NSEraseRect(NSRect rect);

typedef NS_ENUM(NSUInteger, NSLineCapStyle) { NSLineCapStyleButt = 0, NSLineCapStyleRound = 1, NSLineCapStyleSquare = 2 };
typedef NS_ENUM(NSUInteger, NSLineJoinStyle) { NSLineJoinStyleMiter = 0, NSLineJoinStyleRound = 1, NSLineJoinStyleBevel = 2 };
@interface NSBezierPath : NSObject <NSCopying>
+ (NSBezierPath *)bezierPath;
+ (NSBezierPath *)bezierPathWithRect:(NSRect)rect;
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)rect;
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xRadius yRadius:(CGFloat)yRadius;
+ (void)fillRect:(NSRect)rect;
+ (void)strokeRect:(NSRect)rect;
+ (void)strokeLineFromPoint:(NSPoint)point1 toPoint:(NSPoint)point2;
- (void)moveToPoint:(NSPoint)point;
- (void)lineToPoint:(NSPoint)point;
- (void)curveToPoint:(NSPoint)endPoint controlPoint1:(NSPoint)controlPoint1 controlPoint2:(NSPoint)controlPoint2;
- (void)closePath;
- (void)removeAllPoints;
- (void)appendBezierPath:(NSBezierPath *)path;
- (void)appendBezierPathWithRect:(NSRect)rect;
- (void)appendBezierPathWithOvalInRect:(NSRect)rect;
- (void)appendBezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xRadius yRadius:(CGFloat)yRadius;
- (void)appendBezierPathWithArcWithCenter:(NSPoint)center radius:(CGFloat)radius startAngle:(CGFloat)startAngle
                                 endAngle:(CGFloat)endAngle clockwise:(BOOL)clockwise;
- (void)fill;
- (void)stroke;
- (void)addClip;
- (void)setClip;
@property CGFloat lineWidth;
@property NSLineCapStyle lineCapStyle;
@property NSLineJoinStyle lineJoinStyle;
@property (readonly, getter=isEmpty) BOOL empty;
@property (readonly) NSRect bounds;
@property (readonly) CGPathRef CGPath;
@end

@interface NSMenu : NSObject
- (instancetype)initWithTitle:(NSString *)title;
@property (copy) NSString *title;
@property (readonly, copy) NSArray<NSMenuItem *> *itemArray;
@property (readonly) NSInteger numberOfItems;
- (void)addItem:(NSMenuItem *)item;
- (NSMenuItem *)addItemWithTitle:(NSString *)title action:(nullable SEL)action keyEquivalent:(NSString *)key;
- (void)removeAllItems;
- (void)insertItem:(NSMenuItem *)newItem atIndex:(NSInteger)index;
- (void)removeItem:(NSMenuItem *)item;
- (void)removeItemAtIndex:(NSInteger)index;
- (nullable NSMenuItem *)itemAtIndex:(NSInteger)index;
- (nullable NSMenuItem *)itemWithTitle:(NSString *)title;
- (nullable NSMenuItem *)itemWithTag:(NSInteger)tag;
- (NSInteger)indexOfItem:(NSMenuItem *)item;
@property (copy) NSArray<NSMenuItem *> *items;
@property (nullable, assign) NSMenu *supermenu;
@property BOOL autoenablesItems;
/* Finds an enabled item whose key equivalent matches a key event, and sends
 * its action. */
- (BOOL)performKeyEquivalent:(NSEvent *)event;
- (void)performActionForItemAtIndex:(NSInteger)index;
- (void)update;
@end

@interface NSMenuItem : NSObject
+ (NSMenuItem *)separatorItem;
- (instancetype)initWithTitle:(NSString *)title action:(nullable SEL)action keyEquivalent:(NSString *)key;
@property (copy) NSString *title;
@property (nullable) SEL action;
@property (nullable, weak) id target;
@property (copy) NSString *keyEquivalent;
@property (nullable, strong) NSMenu *submenu;
@property (nullable, readonly, assign) NSMenu *menu;
@property NSEventModifierFlags keyEquivalentModifierMask;
@property (readonly) BOOL hasSubmenu;
@property (readonly, getter=isSeparatorItem) BOOL separatorItem;
@property NSInteger state;
@property (getter=isHidden) BOOL hidden;
@property (nullable, strong) NSImage *image;
@property (nullable, copy) NSString *toolTip;
@property (getter=isEnabled) BOOL enabled;
@property NSInteger tag;
@property (nullable, strong) id representedObject;
@end

@interface NSViewController : NSResponder
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil;
- (instancetype)init;
@property (strong) NSView *view;
@property (nullable, readonly, strong) NSView *viewIfLoaded;
@property (readonly, getter=isViewLoaded) BOOL viewLoaded;
@property (nullable, copy) NSString *title;
@property (nullable, strong) id representedObject;
@property (nullable, readonly, copy) NSString *nibName;
@property (nullable, readonly, strong) NSBundle *nibBundle;
@property NSSize preferredContentSize;
@property (readonly, copy) NSArray<NSViewController *> *childViewControllers;
@property (nullable, readonly, assign) NSViewController *parentViewController;
- (void)loadView;
- (void)loadViewIfNeeded;
- (void)viewDidLoad;
- (void)viewWillAppear;
- (void)viewDidAppear;
- (void)viewWillDisappear;
- (void)viewDidDisappear;
- (void)viewWillLayout;
- (void)viewDidLayout;
- (void)updateViewConstraints;
- (void)addChildViewController:(NSViewController *)childViewController;
- (void)removeFromParentViewController;
@end

@interface NSWindowController : NSResponder
- (instancetype)initWithWindow:(nullable NSWindow *)window;
- (instancetype)initWithWindowNibName:(NSString *)windowNibName;
@property (nullable, strong) NSWindow *window;
@property (nullable, strong) NSViewController *contentViewController;
@property (readonly, getter=isWindowLoaded) BOOL windowLoaded;
@property (nullable, assign) id owner;
- (void)loadWindow;
- (void)windowWillLoad;
- (void)windowDidLoad;
- (void)showWindow:(nullable id)sender;
- (void)close;
@end


typedef NSString *NSImageName NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSImage.Name);
typedef NS_ENUM(NSInteger, NSImageScaling) {
    NSImageScaleProportionallyDown = 0, NSImageScaleAxesIndependently, NSImageScaleNone, NSImageScaleProportionallyUpOrDown
};
typedef NS_ENUM(NSInteger, NSImageSymbolScale) {
    NSImageSymbolScaleSmall = 1, NSImageSymbolScaleMedium = 2, NSImageSymbolScaleLarge = 3
} NS_SWIFT_NAME(NSImage.SymbolScale);

@interface NSImageRep : NSObject <NSCopying>
@property NSSize size;
@property NSInteger pixelsWide, pixelsHigh;
@property (getter=hasAlpha) BOOL alpha;
- (BOOL)draw;
- (BOOL)drawInRect:(NSRect)rect;
- (nullable CGImageRef)CGImageForProposedRect:(nullable NSRect *)proposedDestRect context:(nullable NSGraphicsContext *)context
                                         hints:(nullable NSDictionary *)hints;
@end

@interface NSBitmapImageRep : NSImageRep
- (instancetype)initWithCGImage:(CGImageRef)cgImage;
- (nullable instancetype)initWithData:(NSData *)data;
+ (nullable instancetype)imageRepWithData:(NSData *)data;
@property (nullable, readonly) CGImageRef CGImage;
@end

@interface NSImageSymbolConfiguration : NSObject <NSCopying>
+ (instancetype)configurationWithPointSize:(CGFloat)pointSize weight:(NSFontWeight)weight;
+ (instancetype)configurationWithPointSize:(CGFloat)pointSize weight:(NSFontWeight)weight scale:(NSImageSymbolScale)scale;
+ (instancetype)configurationWithScale:(NSImageSymbolScale)scale;
+ (instancetype)configurationWithTextStyle:(NSString *)style;
+ (instancetype)configurationWithHierarchicalColor:(NSColor *)hierarchicalColor;
+ (instancetype)configurationWithPaletteColors:(NSArray<NSColor *> *)paletteColors;
+ (instancetype)configurationPreferringMulticolor;
- (instancetype)configurationByApplyingConfiguration:(NSImageSymbolConfiguration *)configuration;
@end

@interface NSImage : NSObject <NSCopying>
+ (nullable NSImage *)imageNamed:(NSImageName)name;
+ (nullable instancetype)imageWithSystemSymbolName:(NSString *)name accessibilityDescription:(nullable NSString *)description;
+ (nullable instancetype)imageWithSystemSymbolName:(NSString *)name variableValue:(double)value
                          accessibilityDescription:(nullable NSString *)description;
+ (nullable instancetype)imageWithSymbolName:(NSString *)name variableValue:(double)value;
+ (instancetype)imageWithSize:(NSSize)size flipped:(BOOL)drawingHandlerShouldBeCalledWithFlippedContext
               drawingHandler:(BOOL (^)(NSRect dstRect))drawingHandler;
- (instancetype)initWithSize:(NSSize)size;
- (nullable instancetype)initWithData:(NSData *)data;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url;
- (nullable instancetype)initWithContentsOfFile:(NSString *)fileName;
- (nullable instancetype)initByReferencingURL:(NSURL *)url;
- (nullable instancetype)initByReferencingFile:(NSString *)fileName;
- (instancetype)initWithCGImage:(CGImageRef)cgImage size:(NSSize)size;
@property NSSize size;
@property (getter=isTemplate) BOOL template;
@property (nullable, copy) NSString *accessibilityDescription;
@property (readonly, copy) NSArray<NSImageRep *> *representations;
@property (readonly, getter=isValid) BOOL valid;
- (nullable NSImageName)name;
- (BOOL)setName:(nullable NSImageName)string;
- (void)addRepresentation:(NSImageRep *)imageRep;
- (void)removeRepresentation:(NSImageRep *)imageRep;
- (nullable CGImageRef)CGImageForProposedRect:(nullable NSRect *)proposedDestRect context:(nullable NSGraphicsContext *)context
                                         hints:(nullable NSDictionary *)hints;
- (nullable NSData *)TIFFRepresentation;
- (void)drawInRect:(NSRect)rect;
- (void)drawInRect:(NSRect)dstSpacePortionRect fromRect:(NSRect)srcSpacePortionRect
         operation:(NSCompositingOperation)op fraction:(CGFloat)requestedAlpha;
- (void)drawAtPoint:(NSPoint)point fromRect:(NSRect)fromRect operation:(NSCompositingOperation)op fraction:(CGFloat)delta;
- (void)lockFocus;
- (void)unlockFocus;
- (nullable NSImage *)imageWithSymbolConfiguration:(NSImageSymbolConfiguration *)configuration;
@property (readonly, copy) NSImageSymbolConfiguration *symbolConfiguration;
@property NSRect alignmentRect;
@property NSEdgeInsets capInsets;
@property NSInteger resizingMode;
@property BOOL matchesOnlyOnBestFittingAxis;
@property NSUInteger cacheMode;
@property (copy) NSColor *backgroundColor;
@property BOOL usesEPSOnResolutionMismatch, prefersColorMatch, matchesOnMultipleResolution;
@property (getter=isFlipped) BOOL flipped;
- (void)recache;
- (nullable NSImageRep *)bestRepresentationForRect:(NSRect)rect context:(nullable NSGraphicsContext *)referenceContext
                                             hints:(nullable NSDictionary *)hints;
- (NSImage *)imageWithLocale:(nullable id)locale;
@end


APPKIT_EXTERN NSPasteboardType const NSPasteboardTypeString, NSPasteboardTypePNG, NSPasteboardTypeTIFF,
    NSPasteboardTypeFileURL, NSPasteboardTypeURL, NSPasteboardTypeRTF, NSPasteboardTypeRTFD, NSPasteboardTypeHTML,
    NSPasteboardTypePDF, NSPasteboardTypeColor, NSPasteboardTypeFont, NSPasteboardTypeRuler, NSPasteboardTypeSound,
    NSPasteboardTypeTabularText, NSPasteboardTypeMultipleTextSelection, NSPasteboardTypeFindPanelSearchOptions;
APPKIT_EXTERN NSPasteboardName const NSPasteboardNameGeneral, NSPasteboardNameFind, NSPasteboardNameFont,
    NSPasteboardNameRuler, NSPasteboardNameDrag;
typedef NSString *NSPasteboardReadingOptionKey NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSPasteboard.ReadingOptionKey);

@protocol NSPasteboardWriting <NSObject>
- (NSArray<NSPasteboardType> *)writableTypesForPasteboard:(NSPasteboard *)pasteboard;
- (nullable id)pasteboardPropertyListForType:(NSPasteboardType)type;
@end
@protocol NSPasteboardReading <NSObject>
+ (NSArray<NSPasteboardType> *)readableTypesForPasteboard:(NSPasteboard *)pasteboard;
@optional
- (nullable id)initWithPasteboardPropertyList:(id)propertyList ofType:(NSPasteboardType)type;
@end

@interface NSPasteboardItem : NSObject <NSPasteboardWriting, NSPasteboardReading>
@property (readonly, copy) NSArray<NSPasteboardType> *types;
- (nullable NSPasteboardType)availableTypeFromArray:(NSArray<NSPasteboardType> *)types;
- (BOOL)setData:(NSData *)data forType:(NSPasteboardType)type;
- (BOOL)setString:(NSString *)string forType:(NSPasteboardType)type;
- (BOOL)setPropertyList:(id)propertyList forType:(NSPasteboardType)type;
- (nullable NSData *)dataForType:(NSPasteboardType)type;
- (nullable NSString *)stringForType:(NSPasteboardType)type;
- (nullable id)propertyListForType:(NSPasteboardType)type;
@end

@interface NSPasteboard : NSObject
@property (class, readonly, strong) NSPasteboard *generalPasteboard;
+ (NSPasteboard *)pasteboardWithName:(NSPasteboardName)name;
+ (NSPasteboard *)pasteboardWithUniqueName;
@property (readonly, copy) NSPasteboardName name;
@property (readonly) NSInteger changeCount;
- (void)releaseGlobally;
- (NSInteger)clearContents;
- (BOOL)writeObjects:(NSArray<id<NSPasteboardWriting>> *)objects;
- (nullable NSArray *)readObjectsForClasses:(NSArray<Class> *)classArray
                                    options:(nullable NSDictionary<NSPasteboardReadingOptionKey, id> *)options;
@property (nullable, readonly, copy) NSArray<NSPasteboardItem *> *pasteboardItems;
- (BOOL)canReadItemWithDataConformingToTypes:(NSArray<NSString *> *)types;
- (BOOL)canReadObjectForClasses:(NSArray<Class> *)classArray options:(nullable NSDictionary<NSPasteboardReadingOptionKey, id> *)options;
- (NSInteger)declareTypes:(NSArray<NSPasteboardType> *)newTypes owner:(nullable id)newOwner;
- (NSInteger)addTypes:(NSArray<NSPasteboardType> *)newTypes owner:(nullable id)newOwner;
@property (nullable, readonly, copy) NSArray<NSPasteboardType> *types;
- (nullable NSPasteboardType)availableTypeFromArray:(NSArray<NSPasteboardType> *)types;
- (BOOL)setData:(nullable NSData *)data forType:(NSPasteboardType)dataType;
- (BOOL)setPropertyList:(id)plist forType:(NSPasteboardType)dataType;
- (BOOL)setString:(NSString *)string forType:(NSPasteboardType)dataType;
- (nullable NSData *)dataForType:(NSPasteboardType)dataType;
- (nullable id)propertyListForType:(NSPasteboardType)dataType;
- (nullable NSString *)stringForType:(NSPasteboardType)dataType;
@end

#pragma clang assume_nonnull end

typedef NS_ENUM(NSInteger, NSBackgroundStyle) {
    NSBackgroundStyleNormal = 0, NSBackgroundStyleEmphasized = 1, NSBackgroundStyleRaised = 2,
    NSBackgroundStyleLowered = 3
};
typedef NS_ENUM(NSInteger, NSVisualEffectMaterial) {
    NSVisualEffectMaterialAppearanceBased = 0, NSVisualEffectMaterialLight = 1, NSVisualEffectMaterialDark = 2,
    NSVisualEffectMaterialTitlebar = 3, NSVisualEffectMaterialSelection = 4, NSVisualEffectMaterialMenu = 5,
    NSVisualEffectMaterialPopover = 6, NSVisualEffectMaterialSidebar = 7, NSVisualEffectMaterialMediumLight = 8,
    NSVisualEffectMaterialUltraDark = 9, NSVisualEffectMaterialHeaderView = 10, NSVisualEffectMaterialSheet = 11,
    NSVisualEffectMaterialWindowBackground = 12, NSVisualEffectMaterialHUDWindow = 13,
    NSVisualEffectMaterialFullScreenUI = 15, NSVisualEffectMaterialToolTip = 17,
    NSVisualEffectMaterialContentBackground = 18, NSVisualEffectMaterialUnderWindowBackground = 21,
    NSVisualEffectMaterialUnderPageBackground = 22
};
typedef NS_ENUM(NSInteger, NSVisualEffectBlendingMode) {
    NSVisualEffectBlendingModeBehindWindow = 0, NSVisualEffectBlendingModeWithinWindow = 1
};
typedef NS_ENUM(NSInteger, NSVisualEffectState) {
    NSVisualEffectStateFollowsWindowActiveState = 0, NSVisualEffectStateActive = 1, NSVisualEffectStateInactive = 2
};
@interface NSVisualEffectView : NSView
@property NSVisualEffectMaterial material;
@property NSVisualEffectBlendingMode blendingMode;
@property NSVisualEffectState state;
@property (getter=isEmphasized) BOOL emphasized;
@property (nullable, strong) NSImage *maskImage;
@property (readonly) NSBackgroundStyle interiorBackgroundStyle;
@end

@interface NSAnimationContext : NSObject
+ (NSAnimationContext *)currentContext;
+ (void)beginGrouping;
+ (void)endGrouping;
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *context))changes
        completionHandler:(nullable void (^)(void))completionHandler;
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *context))changes;
@property NSTimeInterval duration;
@property (nullable, strong) id timingFunction;
@property BOOL allowsImplicitAnimation;
@property (nullable, copy) void (^completionHandler)(void);
@end

@protocol NSAnimatablePropertyContainer
- (instancetype)animator;
@property (copy) NSDictionary<NSString *, id> *animations;
- (nullable id)animationForKey:(NSString *)key;
+ (nullable id)defaultAnimationForKey:(NSString *)key;
@end
@interface NSView (NSAnimatablePropertyContainer) <NSAnimatablePropertyContainer>
@end
@interface NSWindow (NSAnimatablePropertyContainer) <NSAnimatablePropertyContainer>
@end

typedef NS_ENUM(NSUInteger, NSFocusRingType) {
    NSFocusRingTypeDefault = 0, NSFocusRingTypeNone = 1, NSFocusRingTypeExterior = 2
};
typedef NS_OPTIONS(NSUInteger, NSTrackingAreaOptions) {
    NSTrackingMouseEnteredAndExited = 0x01, NSTrackingMouseMoved = 0x02, NSTrackingCursorUpdate = 0x04,
    NSTrackingActiveWhenFirstResponder = 0x10, NSTrackingActiveInKeyWindow = 0x20,
    NSTrackingActiveInActiveApp = 0x40, NSTrackingActiveAlways = 0x80, NSTrackingAssumeInside = 0x100,
    NSTrackingInVisibleRect = 0x200, NSTrackingEnabledDuringMouseDrag = 0x400
};
typedef NS_OPTIONS(unsigned long long, NSAlignmentOptions) {
    NSAlignMinXInward = 1ULL << 0, NSAlignMinYInward = 1ULL << 1, NSAlignMaxXInward = 1ULL << 2,
    NSAlignMaxYInward = 1ULL << 3, NSAlignWidthInward = 1ULL << 4, NSAlignHeightInward = 1ULL << 5,
    NSAlignMinXOutward = 1ULL << 8, NSAlignMinYOutward = 1ULL << 9, NSAlignMaxXOutward = 1ULL << 10,
    NSAlignMaxYOutward = 1ULL << 11, NSAlignWidthOutward = 1ULL << 12, NSAlignHeightOutward = 1ULL << 13,
    NSAlignMinXNearest = 1ULL << 16, NSAlignMinYNearest = 1ULL << 17, NSAlignMaxXNearest = 1ULL << 18,
    NSAlignMaxYNearest = 1ULL << 19, NSAlignWidthNearest = 1ULL << 20, NSAlignHeightNearest = 1ULL << 21,
    NSAlignRectFlipped = 1ULL << 63,
    NSAlignAllEdgesInward = NSAlignMinXInward | NSAlignMaxXInward | NSAlignMinYInward | NSAlignMaxYInward,
    NSAlignAllEdgesOutward = NSAlignMinXOutward | NSAlignMaxXOutward | NSAlignMinYOutward | NSAlignMaxYOutward,
    NSAlignAllEdgesNearest = NSAlignMinXNearest | NSAlignMaxXNearest | NSAlignMinYNearest | NSAlignMaxYNearest
};

@interface NSShadow : NSObject <NSCopying>
@property NSSize shadowOffset;
@property CGFloat shadowBlurRadius;
@property (nullable, copy) NSColor *shadowColor;
- (void)set;
@end

@interface NSTrackingArea : NSObject <NSCopying>
- (instancetype)initWithRect:(NSRect)rect options:(NSTrackingAreaOptions)options owner:(nullable id)owner
                    userInfo:(nullable NSDictionary *)userInfo;
@property (readonly) NSRect rect;
@property (readonly) NSTrackingAreaOptions options;
@property (nullable, readonly, weak) id owner;
@property (nullable, readonly) NSDictionary *userInfo;
@end

@class NSScrollView, NSCursor, NSMenu;
@interface NSView (BittenExtras)
@property CGFloat alphaValue;
@property (nullable, copy) NSString *toolTip;
@property (nullable, copy) NSUserInterfaceItemIdentifier identifier;
@property (nullable, copy) NSShadow *shadow;
@property NSFocusRingType focusRingType;
@property BOOL translatesAutoresizingMaskIntoConstraints;
@property (readonly) NSSize intrinsicContentSize;
- (void)invalidateIntrinsicContentSize;
@property (readonly) NSSize fittingSize;
@property NSEdgeInsets additionalSafeAreaInsets;
@property (readonly) NSEdgeInsets safeAreaInsets;
@property (readonly) NSRect safeAreaRect;
@property BOOL postsFrameChangedNotifications;
@property BOOL postsBoundsChangedNotifications;
@property BOOL clipsToBounds;
@property (nullable, strong) id compositingFilter;
@property (copy) NSArray *contentFilters;
@property (copy) NSArray *backgroundFilters;
@property BOOL needsLayout;
- (void)layoutSubtreeIfNeeded;
- (void)updateTrackingAreas;
@property (readonly, copy) NSArray<NSTrackingArea *> *trackingAreas;
- (void)addTrackingArea:(NSTrackingArea *)trackingArea;
- (void)removeTrackingArea:(NSTrackingArea *)trackingArea;
- (void)addCursorRect:(NSRect)rect cursor:(NSCursor *)object;
- (void)removeCursorRect:(NSRect)rect cursor:(NSCursor *)object;
- (void)resetCursorRects;
- (void)discardCursorRects;
- (void)registerForDraggedTypes:(NSArray<NSPasteboardType> *)newTypes;
- (void)unregisterDraggedTypes;
@property (readonly, copy) NSArray<NSPasteboardType> *registeredDraggedTypes;
@property (nullable, readonly) NSScrollView *enclosingScrollView;
@property (readonly) NSRect visibleRect;
- (BOOL)isDescendantOf:(NSView *)view;
@property (readonly, getter=isHiddenOrHasHiddenAncestor) BOOL hiddenOrHasHiddenAncestor;
@property (readonly) NSInteger tag;
- (nullable __kindof NSView *)viewWithTag:(NSInteger)tag;
- (BOOL)acceptsFirstMouse:(nullable NSEvent *)event;
@property (readonly) BOOL wantsDefaultClipping;
@property (readonly) BOOL inLiveResize;
- (void)viewDidChangeBackingProperties;
@property (nullable, strong) NSMenu *menu;
- (NSRect)convertRect:(NSRect)rect fromView:(nullable NSView *)view;
- (NSRect)convertRect:(NSRect)rect toView:(nullable NSView *)view;
- (NSPoint)convertPointToBacking:(NSPoint)point;
- (NSPoint)convertPointFromBacking:(NSPoint)point;
- (NSSize)convertSizeToBacking:(NSSize)size;
- (NSSize)convertSizeFromBacking:(NSSize)size;
- (NSRect)convertRectToBacking:(NSRect)rect;
- (NSRect)convertRectFromBacking:(NSRect)rect;
- (NSRect)backingAlignedRect:(NSRect)rect options:(NSAlignmentOptions)options;
@end
