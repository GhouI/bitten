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

#pragma clang assume_nonnull end
