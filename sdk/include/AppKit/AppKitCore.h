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
- (void)mouseEntered:(NSEvent *)event NS_SWIFT_NAME(mouseEntered(with:));
- (void)mouseExited:(NSEvent *)event NS_SWIFT_NAME(mouseExited(with:));
- (void)cursorUpdate:(NSEvent *)event NS_SWIFT_NAME(cursorUpdate(with:));
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
- (void)setFrameOrigin:(NSPoint)newOrigin;
- (void)setFrameSize:(NSSize)newSize;
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize;
- (void)resizeWithOldSuperviewSize:(NSSize)oldSize;
- (void)setBoundsOrigin:(NSPoint)newOrigin;
- (void)setBoundsSize:(NSSize)newSize;
@property (copy) NSArray<__kindof NSView *> *subviews;
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
@property BOOL autoresizesSubviews;
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
- (void)windowDidResignKey:(NSNotification *)notification;
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
- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames;
- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename;
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

typedef CGFloat NSFontWidth NS_TYPED_EXTENSIBLE_ENUM;
typedef NSString *NSFontDescriptorAttributeName NS_TYPED_ENUM;
typedef NSString *NSFontDescriptorSystemDesign NS_TYPED_ENUM;
typedef uint32_t NSFontDescriptorSymbolicTraits;
typedef NSUInteger NSGlyph;
typedef NS_OPTIONS(NSUInteger, NSFontTraitMask) {
    NSItalicFontMask = 0x00000001, NSBoldFontMask = 0x00000002, NSUnboldFontMask = 0x00000004,
    NSNonStandardCharacterSetFontMask = 0x00000008, NSNarrowFontMask = 0x00000010, NSExpandedFontMask = 0x00000020,
    NSCondensedFontMask = 0x00000040, NSSmallCapsFontMask = 0x00000080, NSPosterFontMask = 0x00000100,
    NSCompressedFontMask = 0x00000200, NSFixedPitchFontMask = 0x00000400, NSUnitalicFontMask = 0x01000000
};
@class NSFontDescriptor, NSAffineTransform;
/* Toll-free bridged to CTFont. */
@interface NSFont : NSObject <NSCopying>
+ (nullable NSFont *)fontWithName:(NSString *)name size:(CGFloat)size;
+ (nullable NSFont *)fontWithName:(NSString *)name matrix:(const CGFloat *)fontMatrix;
+ (nullable NSFont *)fontWithDescriptor:(NSFontDescriptor *)descriptor size:(CGFloat)size;
+ (nullable NSFont *)fontWithDescriptor:(NSFontDescriptor *)descriptor textTransform:(nullable NSAffineTransform *)t;
+ (NSFont *)systemFontOfSize:(CGFloat)size;
+ (NSFont *)systemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSFont *)systemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight width:(NSFontWidth)width;
+ (NSFont *)boldSystemFontOfSize:(CGFloat)size;
+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSFont *)monospacedDigitSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (nullable NSFont *)userFontOfSize:(CGFloat)size;
+ (nullable NSFont *)userFixedPitchFontOfSize:(CGFloat)size;
+ (NSFont *)menuFontOfSize:(CGFloat)size;
+ (NSFont *)menuBarFontOfSize:(CGFloat)size;
+ (NSFont *)labelFontOfSize:(CGFloat)size;
+ (NSFont *)messageFontOfSize:(CGFloat)size;
+ (NSFont *)titleBarFontOfSize:(CGFloat)size;
+ (NSFont *)toolTipsFontOfSize:(CGFloat)size;
+ (NSFont *)paletteFontOfSize:(CGFloat)size;
+ (NSFont *)controlContentFontOfSize:(CGFloat)size;
+ (NSFont *)preferredFontForTextStyle:(NSFontTextStyle)style options:(NSDictionary *)options;
@property (class, readonly) CGFloat systemFontSize;
@property (class, readonly) CGFloat smallSystemFontSize;
@property (class, readonly) CGFloat labelFontSize;
+ (CGFloat)systemFontSizeForControlSize:(NSControlSize)controlSize;
@property (readonly, copy) NSString *fontName;
@property (nullable, readonly, copy) NSString *familyName;
@property (nullable, readonly, copy) NSString *displayName;
@property (readonly) CGFloat pointSize;
@property (readonly) CGFloat ascender, descender, leading, capHeight, xHeight, underlinePosition,
    underlineThickness, italicAngle;
@property (readonly) NSRect boundingRectForFont;
@property (readonly) NSSize maximumAdvancement;
@property (readonly) NSUInteger numberOfGlyphs;
@property (readonly, getter=isFixedPitch) BOOL fixedPitch;
@property (readonly, getter=isVertical) BOOL vertical;
@property (readonly, copy) NSFont *verticalFont;
@property (readonly, copy) NSFont *screenFont;
@property (readonly, copy) NSFont *printerFont;
@property (readonly) const CGFloat *matrix;
@property (readonly, strong) NSFontDescriptor *fontDescriptor;
- (NSSize)advancementForGlyph:(NSGlyph)glyph;
- (NSRect)boundingRectForCGGlyph:(CGGlyph)glyph;
- (void)set;
@end
/* Toll-free bridged to CTFontDescriptor. */
@interface NSFontDescriptor : NSObject <NSCopying>
+ (NSFontDescriptor *)fontDescriptorWithFontAttributes:(nullable NSDictionary<NSFontDescriptorAttributeName, id> *)attributes;
+ (NSFontDescriptor *)fontDescriptorWithName:(NSString *)fontName size:(CGFloat)size;
+ (NSFontDescriptor *)preferredFontDescriptorForTextStyle:(NSFontTextStyle)style options:(NSDictionary *)options;
@property (readonly, copy) NSDictionary<NSFontDescriptorAttributeName, id> *fontAttributes;
- (nullable id)objectForKey:(NSFontDescriptorAttributeName)attribute;
@property (nullable, readonly, copy) NSString *postscriptName;
@property (readonly) CGFloat pointSize;
@property (readonly) NSFontDescriptorSymbolicTraits symbolicTraits;
- (NSFontDescriptor *)fontDescriptorByAddingAttributes:(NSDictionary<NSFontDescriptorAttributeName, id> *)attributes;
- (NSFontDescriptor *)fontDescriptorWithSize:(CGFloat)newPointSize;
- (NSFontDescriptor *)fontDescriptorWithFamily:(NSString *)newFamily;
- (NSFontDescriptor *)fontDescriptorWithSymbolicTraits:(NSFontDescriptorSymbolicTraits)symbolicTraits;
- (nullable NSFontDescriptor *)fontDescriptorWithDesign:(NSFontDescriptorSystemDesign)design;
@end
@interface NSFontManager : NSObject
@property (class, readonly, strong) NSFontManager *sharedFontManager;
@property (readonly, copy) NSArray<NSString *> *availableFontFamilies;
@property (readonly, copy) NSArray<NSString *> *availableFonts;
- (nullable NSArray<NSArray *> *)availableMembersOfFontFamily:(NSString *)fam;
- (NSFontTraitMask)traitsOfFont:(NSFont *)fontObj;
- (NSInteger)weightOfFont:(NSFont *)fontObj;
- (nullable NSFont *)fontWithFamily:(NSString *)family traits:(NSFontTraitMask)traits weight:(NSInteger)weight size:(CGFloat)size;
- (NSFont *)convertFont:(NSFont *)fontObj toSize:(CGFloat)size;
- (NSFont *)convertFont:(NSFont *)fontObj toHaveTrait:(NSFontTraitMask)trait;
- (NSFont *)convertFont:(NSFont *)fontObj toNotHaveTrait:(NSFontTraitMask)trait;
- (NSFont *)convertFont:(NSFont *)fontObj toFamily:(NSString *)family;
- (NSFont *)convertFont:(NSFont *)fontObj;
@property (nullable, readonly, strong) NSFont *selectedFont;
- (void)setSelectedFont:(NSFont *)fontObj isMultiple:(BOOL)flag;
@property (nullable, weak) id target;
@property (nullable) SEL action;
- (void)orderFrontFontPanel:(nullable id)sender;
@property (getter=isEnabled) BOOL enabled;
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
@property BOOL autorecalculatesKeyViewLoop;
@property BOOL allowsToolTipsWhenApplicationIsInactive;
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
+ (nullable NSButton *)standardWindowButton:(NSWindowButton)b forStyleMask:(NSWindowStyleMask)styleMask;
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
- (void)endEditingFor:(nullable id)object;
- (void)sendEvent:(NSEvent *)event;
- (void)performClose:(nullable id)sender;
@end
@interface NSResponder (BittenEvents)
- (void)rightMouseUp:(NSEvent *)event;
@end
@interface NSWindow (BittenDisplay)
- (void)_bn_scheduleDisplay;
- (void)_bn_sendStyle;
- (void)_bn_hideKeepingDisplay;
- (void)_bn_dropFirstResponder;
- (void)_post:(NSNotificationName)name;
- (void)_bn_orderFrontOnDisplay;
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

typedef NS_ENUM(NSUInteger, NSImageInterpolation) {
    NSImageInterpolationDefault = 0,
    NSImageInterpolationNone = 1,
    NSImageInterpolationLow = 2,
    NSImageInterpolationMedium = 4,
    NSImageInterpolationHigh = 3,
};
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
@property NSCompositingOperation compositingOperation;
@property NSImageInterpolation imageInterpolation;
@property BOOL shouldAntialias;
@property NSPoint patternPhase;
@property NSInteger colorRenderingIntent;
@property (readonly) NSDictionary *attributes;
@property (readonly) void *graphicsPort;
@end

APPKIT_EXTERN void NSRectFill(NSRect rect);
APPKIT_EXTERN void NSRectFillUsingOperation(NSRect rect, NSCompositingOperation op);
APPKIT_EXTERN void NSFrameRect(NSRect rect);
APPKIT_EXTERN void NSFrameRectWithWidth(NSRect rect, CGFloat frameWidth);
APPKIT_EXTERN void NSRectClip(NSRect rect);
APPKIT_EXTERN void NSRectClipList(const NSRect *rects, NSInteger count);
APPKIT_EXTERN void NSBeep(void);
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
- (BOOL)containsPoint:(NSPoint)point;
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
@property BOOL shouldCascadeWindows;
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
+ (instancetype)configurationPreferringMonochrome;
+ (instancetype)configurationPreferringHierarchical;
+ (instancetype)configurationWithTextStyle:(NSString *)style scale:(NSImageSymbolScale)scale;
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
- (void)drawInRect:(NSRect)dstSpacePortionRect fromRect:(NSRect)srcSpacePortionRect
         operation:(NSCompositingOperation)op fraction:(CGFloat)requestedAlpha
    respectFlipped:(BOOL)respectContextIsFlipped hints:(nullable NSDictionary *)hints;
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

@interface NSEvent (NSTrackingAreaEvents)
/* For mouse-entered, mouse-exited and cursor-update events. */
@property (nullable, readonly) NSTrackingArea *trackingArea;
@property (nullable, readonly) void *userData;
@property (readonly) NSInteger trackingNumber;
@end

@class NSScrollView, NSCursor, NSMenu;
/* Characters of keys that type none of their own (NSEvent.h). */
enum {
    NSUpArrowFunctionKey = 0xF700, NSDownArrowFunctionKey = 0xF701, NSLeftArrowFunctionKey = 0xF702,
    NSRightArrowFunctionKey = 0xF703, NSF1FunctionKey = 0xF704, NSF2FunctionKey = 0xF705, NSF3FunctionKey = 0xF706,
    NSF4FunctionKey = 0xF707, NSF5FunctionKey = 0xF708, NSF6FunctionKey = 0xF709, NSF7FunctionKey = 0xF70A,
    NSF8FunctionKey = 0xF70B, NSF9FunctionKey = 0xF70C, NSF10FunctionKey = 0xF70D, NSF11FunctionKey = 0xF70E,
    NSF12FunctionKey = 0xF70F, NSInsertFunctionKey = 0xF727, NSDeleteFunctionKey = 0xF728, NSHomeFunctionKey = 0xF729,
    NSBeginFunctionKey = 0xF72A, NSEndFunctionKey = 0xF72B, NSPageUpFunctionKey = 0xF72C, NSPageDownFunctionKey = 0xF72D
};

@interface NSView (NSContextMenu)
- (nullable NSMenu *)menuForEvent:(NSEvent *)event;
@end

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
/* bitten: runs -layout in this subtree where needed, without solving the
 * window's constraints (for hosts that size their subviews while drawing). */
- (void)_bn_layoutSubtree;
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

typedef NS_ENUM(NSInteger, NSScrollerStyle) { NSScrollerStyleLegacy = 0, NSScrollerStyleOverlay = 1 };
typedef NS_ENUM(NSInteger, NSScrollerKnobStyle) {
    NSScrollerKnobStyleDefault = 0, NSScrollerKnobStyleDark = 1, NSScrollerKnobStyleLight = 2
};
typedef NS_ENUM(NSUInteger, NSBorderType) { NSNoBorder = 0, NSLineBorder = 1, NSBezelBorder = 2, NSGrooveBorder = 3 };
typedef NS_ENUM(NSInteger, NSScrollElasticity) {
    NSScrollElasticityAutomatic = 0, NSScrollElasticityNone = 1, NSScrollElasticityAllowed = 2
};

@interface NSScroller : NSControl
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)controlSize scrollerStyle:(NSScrollerStyle)scrollerStyle;
@property (class, readonly) NSScrollerStyle preferredScrollerStyle;
@property (class, readonly, getter=isCompatibleWithOverlayScrollers) BOOL compatibleWithOverlayScrollers;
@property double doubleValue;
@property CGFloat knobProportion;
@property NSScrollerStyle scrollerStyle;
@property NSScrollerKnobStyle knobStyle;
@end

@interface NSClipView : NSView
@property (nullable, strong) __kindof NSView *documentView;
@property BOOL drawsBackground;
@property (copy) NSColor *backgroundColor;
@property NSEdgeInsets contentInsets;
@property BOOL automaticallyAdjustsContentInsets;
@property (readonly) NSRect documentRect;
@property (readonly) NSRect documentVisibleRect;
- (NSRect)constrainBoundsRect:(NSRect)proposedBounds;
- (void)scrollToPoint:(NSPoint)newOrigin;
@end

@interface NSScrollView : NSView
@property (strong) NSClipView *contentView;
@property (nullable, strong) __kindof NSView *documentView;
@property (readonly) NSSize contentSize;
@property (readonly) NSRect documentVisibleRect;
@property NSEdgeInsets contentInsets;
@property BOOL automaticallyAdjustsContentInsets;
@property NSEdgeInsets scrollerInsets;
@property BOOL drawsBackground;
@property (copy) NSColor *backgroundColor;
@property NSBorderType borderType;
@property BOOL hasVerticalScroller;
@property BOOL hasHorizontalScroller;
@property (nullable, strong) NSScroller *verticalScroller;
@property (nullable, strong) NSScroller *horizontalScroller;
@property BOOL autohidesScrollers;
@property NSScrollerStyle scrollerStyle;
@property NSScrollElasticity verticalScrollElasticity;
@property NSScrollElasticity horizontalScrollElasticity;
@property BOOL usesPredominantAxisScrolling;
@property BOOL allowsMagnification;
@property CGFloat magnification;
@property CGFloat lineScroll;
@property CGFloat verticalLineScroll;
@property CGFloat horizontalLineScroll;
- (void)tile;
- (void)flashScrollers;
- (void)reflectScrolledClipView:(NSClipView *)clipView;
@end

@interface NSView (BittenSubviews)
- (void)addSubview:(NSView *)view positioned:(NSWindowOrderingMode)place relativeTo:(nullable NSView *)otherView;
- (void)replaceSubview:(NSView *)oldView with:(NSView *)newView;
- (void)sortSubviewsUsingFunction:(NSComparisonResult (*)(__kindof NSView *, __kindof NSView *, void *_Nullable))compare
                          context:(nullable void *)context;
- (nullable NSView *)ancestorSharedWithView:(NSView *)view;
@end
@interface NSView (BittenScrolling)
- (void)scrollPoint:(NSPoint)point;
- (BOOL)scrollRectToVisible:(NSRect)rect;
@end

@protocol NSAccessibility <NSObject>
@end
@interface NSResponder (BittenAccessibility) <NSAccessibility>
@property (nullable, copy) NSString * accessibilityLabel;
@property (nullable, copy) NSString * accessibilityTitle;
@property (nullable, copy) NSString * accessibilityHelp;
@property (nullable, strong) id accessibilityValue;
@property (nullable, copy) NSAccessibilityRole accessibilityRole;
@property (nullable, copy) NSString * accessibilitySubrole;
@property (nullable, copy) NSString * accessibilityRoleDescription;
@property (nullable, copy) NSString * accessibilityIdentifier;
@property (nullable, copy) NSString * accessibilityPlaceholderValue;
@property (nullable, copy) NSString * accessibilityValueDescription;
@property (nullable, copy) NSArray * accessibilityChildren;
@property (nullable, copy) NSArray * accessibilityCustomActions;
@property (nullable, copy) NSArray * accessibilitySelectedChildren;
@property (nullable, weak) id accessibilityParent;
@property (nullable, strong) id accessibilityMinValue;
@property (nullable, strong) id accessibilityMaxValue;
@property (nullable, copy) NSArray * accessibilityRows;
@property (nullable, copy) NSArray * accessibilitySelectedRows;
@property (nullable, copy) NSArray * accessibilityVisibleRows;
@property (nullable, copy) NSString * accessibilitySelectedText;
@property (nullable, strong) NSNumber * accessibilityOrientation;
@property (nullable, strong) NSNumber * accessibilityIndex;
@property (getter=isAccessibilityElement) BOOL accessibilityElement;
@property (getter=isAccessibilityEnabled) BOOL accessibilityEnabled;
@property (getter=isAccessibilityHidden) BOOL accessibilityHidden;
@property (getter=isAccessibilitySelected) BOOL accessibilitySelected;
@property (getter=isAccessibilityFocused) BOOL accessibilityFocused;
@property (getter=isAccessibilityExpanded) BOOL accessibilityExpanded;
@property (readonly) NSRect accessibilityFrame;
- (BOOL)accessibilityPerformPress;
- (BOOL)accessibilityPerformIncrement;
- (BOOL)accessibilityPerformDecrement;
- (nullable id)accessibilityHitTest:(NSPoint)point;
@property (nullable, readonly) id accessibilityFocusedUIElement;
@end
@interface NSMenuItem (BittenAccessibility) <NSAccessibility>
@property (nullable, copy) NSString * accessibilityLabel;
@property (nullable, copy) NSString * accessibilityTitle;
@property (nullable, copy) NSString * accessibilityHelp;
@property (nullable, strong) id accessibilityValue;
@property (nullable, copy) NSAccessibilityRole accessibilityRole;
@property (nullable, copy) NSString * accessibilitySubrole;
@property (nullable, copy) NSString * accessibilityRoleDescription;
@property (nullable, copy) NSString * accessibilityIdentifier;
@property (nullable, copy) NSString * accessibilityPlaceholderValue;
@property (nullable, copy) NSString * accessibilityValueDescription;
@property (nullable, copy) NSArray * accessibilityChildren;
@property (nullable, copy) NSArray * accessibilityCustomActions;
@property (nullable, copy) NSArray * accessibilitySelectedChildren;
@property (nullable, weak) id accessibilityParent;
@property (nullable, strong) id accessibilityMinValue;
@property (nullable, strong) id accessibilityMaxValue;
@property (nullable, copy) NSArray * accessibilityRows;
@property (nullable, copy) NSArray * accessibilitySelectedRows;
@property (nullable, copy) NSArray * accessibilityVisibleRows;
@property (nullable, copy) NSString * accessibilitySelectedText;
@property (nullable, strong) NSNumber * accessibilityOrientation;
@property (nullable, strong) NSNumber * accessibilityIndex;
@property (getter=isAccessibilityElement) BOOL accessibilityElement;
@property (getter=isAccessibilityEnabled) BOOL accessibilityEnabled;
@property (getter=isAccessibilityHidden) BOOL accessibilityHidden;
@property (getter=isAccessibilitySelected) BOOL accessibilitySelected;
@property (getter=isAccessibilityFocused) BOOL accessibilityFocused;
@property (getter=isAccessibilityExpanded) BOOL accessibilityExpanded;
@property (readonly) NSRect accessibilityFrame;
- (BOOL)accessibilityPerformPress;
- (BOOL)accessibilityPerformIncrement;
- (BOOL)accessibilityPerformDecrement;
- (nullable id)accessibilityHitTest:(NSPoint)point;
@property (nullable, readonly) id accessibilityFocusedUIElement;
@end
@interface NSMenu (BittenAccessibility) <NSAccessibility>
@property (nullable, copy) NSString * accessibilityLabel;
@property (nullable, copy) NSString * accessibilityTitle;
@property (nullable, copy) NSString * accessibilityHelp;
@property (nullable, strong) id accessibilityValue;
@property (nullable, copy) NSAccessibilityRole accessibilityRole;
@property (nullable, copy) NSString * accessibilitySubrole;
@property (nullable, copy) NSString * accessibilityRoleDescription;
@property (nullable, copy) NSString * accessibilityIdentifier;
@property (nullable, copy) NSString * accessibilityPlaceholderValue;
@property (nullable, copy) NSString * accessibilityValueDescription;
@property (nullable, copy) NSArray * accessibilityChildren;
@property (nullable, copy) NSArray * accessibilityCustomActions;
@property (nullable, copy) NSArray * accessibilitySelectedChildren;
@property (nullable, weak) id accessibilityParent;
@property (nullable, strong) id accessibilityMinValue;
@property (nullable, strong) id accessibilityMaxValue;
@property (nullable, copy) NSArray * accessibilityRows;
@property (nullable, copy) NSArray * accessibilitySelectedRows;
@property (nullable, copy) NSArray * accessibilityVisibleRows;
@property (nullable, copy) NSString * accessibilitySelectedText;
@property (nullable, strong) NSNumber * accessibilityOrientation;
@property (nullable, strong) NSNumber * accessibilityIndex;
@property (getter=isAccessibilityElement) BOOL accessibilityElement;
@property (getter=isAccessibilityEnabled) BOOL accessibilityEnabled;
@property (getter=isAccessibilityHidden) BOOL accessibilityHidden;
@property (getter=isAccessibilitySelected) BOOL accessibilitySelected;
@property (getter=isAccessibilityFocused) BOOL accessibilityFocused;
@property (getter=isAccessibilityExpanded) BOOL accessibilityExpanded;
@property (readonly) NSRect accessibilityFrame;
- (BOOL)accessibilityPerformPress;
- (BOOL)accessibilityPerformIncrement;
- (BOOL)accessibilityPerformDecrement;
- (nullable id)accessibilityHitTest:(NSPoint)point;
@property (nullable, readonly) id accessibilityFocusedUIElement;
@end

/* macOS on x86-64 keeps AppKit's original values (right before center);
 * the iOS order is only for arm64. */
typedef NS_ENUM(NSInteger, NSTextAlignment) {
    NSTextAlignmentLeft = 0, NSTextAlignmentRight = 1, NSTextAlignmentCenter = 2, NSTextAlignmentJustified = 3,
    NSTextAlignmentNatural = 4
};
typedef NS_ENUM(NSInteger, NSLineBreakMode) {
    NSLineBreakByWordWrapping = 0, NSLineBreakByCharWrapping, NSLineBreakByClipping, NSLineBreakByTruncatingHead,
    NSLineBreakByTruncatingTail, NSLineBreakByTruncatingMiddle
};
typedef NS_OPTIONS(NSInteger, NSStringDrawingOptions) {
    NSStringDrawingUsesLineFragmentOrigin = 1 << 0, NSStringDrawingUsesFontLeading = 1 << 1,
    NSStringDrawingUsesDeviceMetrics = 1 << 3, NSStringDrawingTruncatesLastVisibleLine = 1 << 5
};
typedef float NSLayoutPriority NS_SWIFT_NAME(NSLayoutConstraint.Priority);
typedef NS_ENUM(NSInteger, NSLayoutConstraintOrientation) {
    NSLayoutConstraintOrientationHorizontal = 0, NSLayoutConstraintOrientationVertical = 1
};
typedef NS_ENUM(NSUInteger, NSTextFieldBezelStyle) { NSTextFieldSquareBezel = 0, NSTextFieldRoundedBezel = 1 };

@interface NSAttributedString (NSStringDrawing)
@property (readonly) NSSize size;
- (void)drawAtPoint:(NSPoint)point;
- (void)drawInRect:(NSRect)rect;
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options context:(nullable id)context;
@end
@interface NSString (NSStringDrawing)
- (NSSize)sizeWithAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs;
- (void)drawAtPoint:(NSPoint)point withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs;
- (void)drawInRect:(NSRect)rect withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs;
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options
                    attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attributes context:(nullable id)context;
@end

@class NSText;
@interface NSControl (BittenText)
@property NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property NSControlSize controlSize;
@property (getter=isHighlighted) BOOL highlighted;
@property NSInteger tag;
@property (nullable, copy) id objectValue;
@property (copy) NSAttributedString *attributedStringValue;
@property BOOL refusesFirstResponder;
- (BOOL)sendAction:(nullable SEL)action to:(nullable id)target;
- (void)sizeToFit;
@property (nullable, readonly) id cell;
@property (nullable, readonly) NSText *currentEditor;
@end
@interface NSView (BittenLayoutPriority)
- (NSLayoutPriority)contentHuggingPriorityForOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setContentHuggingPriority:(NSLayoutPriority)priority forOrientation:(NSLayoutConstraintOrientation)orientation;
- (NSLayoutPriority)contentCompressionResistancePriorityForOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)priority
                                 forOrientation:(NSLayoutConstraintOrientation)orientation;
@end

@class NSTextField;
@protocol NSTextFieldDelegate <NSObject>
@optional
- (void)controlTextDidChange:(NSNotification *)obj;
- (void)controlTextDidBeginEditing:(NSNotification *)obj;
- (void)controlTextDidEndEditing:(NSNotification *)obj;
@end
@interface NSTextField : NSControl
+ (instancetype)labelWithString:(NSString *)stringValue;
+ (instancetype)wrappingLabelWithString:(NSString *)stringValue;
+ (instancetype)labelWithAttributedString:(NSAttributedString *)attributedStringValue;
+ (instancetype)textFieldWithString:(NSString *)stringValue;
@property (null_resettable, copy) NSColor *textColor;
@property (nullable, copy) NSColor *backgroundColor;
@property (getter=isEditable) BOOL editable;
@property (getter=isSelectable) BOOL selectable;
@property (getter=isBordered) BOOL bordered;
@property (getter=isBezeled) BOOL bezeled;
@property NSTextFieldBezelStyle bezelStyle;
@property BOOL drawsBackground;
@property NSInteger maximumNumberOfLines;
@property BOOL usesSingleLineMode;
@property BOOL truncatesLastVisibleLine;
@property BOOL wraps;
- (void)setScrollable:(BOOL)flag;
- (void)setAllowsDefaultTighteningForTruncation:(BOOL)flag;
- (void)setImportsGraphics:(BOOL)flag;
- (void)setAllowsEditingTextAttributes:(BOOL)flag;
@property (nullable, copy) NSString *placeholderString;
@property (nullable, copy) NSAttributedString *placeholderAttributedString;
@property CGFloat preferredMaxLayoutWidth;
@property (nullable, weak) id<NSTextFieldDelegate> delegate;
@end

typedef NS_OPTIONS(NSUInteger, NSCursorFrameResizeDirections) {
    NSCursorFrameResizeDirectionsInward = 1 << 0, NSCursorFrameResizeDirectionsOutward = 1 << 1,
    NSCursorFrameResizeDirectionsAll = NSCursorFrameResizeDirectionsInward | NSCursorFrameResizeDirectionsOutward
};
typedef NS_ENUM(NSUInteger, NSImageAlignment) {
    NSImageAlignCenter = 0, NSImageAlignTop, NSImageAlignTopLeft, NSImageAlignTopRight, NSImageAlignLeft,
    NSImageAlignBottom, NSImageAlignBottomLeft, NSImageAlignBottomRight, NSImageAlignRight
};
typedef NS_ENUM(NSUInteger, NSImageFrameStyle) {
    NSImageFrameNone = 0, NSImageFramePhoto, NSImageFrameGrayBezel, NSImageFrameGroove, NSImageFrameButton
};
typedef NS_ENUM(NSUInteger, NSCellImagePosition) {
    NSNoImage = 0, NSImageOnly = 1, NSImageLeft = 2, NSImageRight = 3, NSImageBelow = 4, NSImageAbove = 5,
    NSImageOverlaps = 6, NSImageLeading = 7, NSImageTrailing = 8
};
typedef NS_ENUM(NSUInteger, NSBezelStyle) {
    NSBezelStyleAutomatic = 0, NSBezelStylePush = 1, NSBezelStyleFlexiblePush = 2, NSBezelStyleDisclosure = 5,
    NSBezelStyleCircular = 7, NSBezelStyleHelpButton = 9, NSBezelStyleSmallSquare = 10, NSBezelStyleToolbar = 11,
    NSBezelStyleAccessoryBarAction = 12, NSBezelStyleAccessoryBar = 13, NSBezelStylePushDisclosure = 14,
    NSBezelStyleBadge = 15, NSBezelStyleRounded = 1, NSBezelStyleRegularSquare = 2, NSBezelStyleTexturedSquare = 8,
    NSBezelStyleTexturedRounded = 11, NSBezelStyleRoundRect = 12, NSBezelStyleRecessed = 13,
    NSBezelStyleRoundedDisclosure = 14, NSBezelStyleInline = 15, NSBezelStyleShadowlessSquare = 6
};
typedef NS_ENUM(NSUInteger, NSButtonType) {
    NSButtonTypeMomentaryLight = 0, NSButtonTypePushOnPushOff = 1, NSButtonTypeToggle = 2, NSButtonTypeSwitch = 3,
    NSButtonTypeRadio = 4, NSButtonTypeMomentaryChange = 5, NSButtonTypeOnOff = 6, NSButtonTypeMomentaryPushIn = 7,
    NSButtonTypeAccelerator = 8, NSButtonTypeMultiLevelAccelerator = 9
};
typedef NSInteger NSControlStateValue NS_TYPED_EXTENSIBLE_ENUM;
static const NSControlStateValue NSControlStateValueMixed = -1;
static const NSControlStateValue NSControlStateValueOff = 0;
static const NSControlStateValue NSControlStateValueOn = 1;
typedef NS_ENUM(NSUInteger, NSProgressIndicatorStyle) {
    NSProgressIndicatorStyleBar = 0, NSProgressIndicatorStyleSpinning = 1
};
typedef NS_ENUM(NSUInteger, NSSegmentSwitchTracking) {
    NSSegmentSwitchTrackingSelectOne = 0, NSSegmentSwitchTrackingSelectAny = 1, NSSegmentSwitchTrackingMomentary = 2,
    NSSegmentSwitchTrackingMomentaryAccelerator = 3
};
typedef NS_ENUM(NSInteger, NSSegmentStyle) {
    NSSegmentStyleAutomatic = 0, NSSegmentStyleRounded = 1, NSSegmentStyleRoundRect = 3,
    NSSegmentStyleTexturedSquare = 4, NSSegmentStyleSmallSquare = 6, NSSegmentStyleSeparated = 8,
    NSSegmentStyleTexturedRounded = 2, NSSegmentStyleCapsule = 5
};
typedef NS_ENUM(NSInteger, NSWritingDirection) {
    NSWritingDirectionNatural = -1, NSWritingDirectionLeftToRight = 0, NSWritingDirectionRightToLeft = 1
};
typedef NS_OPTIONS(NSUInteger, NSGradientDrawingOptions) {
    NSGradientDrawsBeforeStartingLocation = 1 << 0, NSGradientDrawsAfterEndingLocation = 1 << 1
};
typedef NSString *NSSoundName NS_SWIFT_NAME(NSSound.Name);
typedef NS_ENUM(NSInteger, NSHapticFeedbackPattern) {
    NSHapticFeedbackPatternGeneric = 0, NSHapticFeedbackPatternAlignment, NSHapticFeedbackPatternLevelChange
};
typedef NS_ENUM(NSUInteger, NSHapticFeedbackPerformanceTime) {
    NSHapticFeedbackPerformanceTimeDefault = 0, NSHapticFeedbackPerformanceTimeNow, NSHapticFeedbackPerformanceTimeDrawCompleted
};
typedef NS_ENUM(NSInteger, NSGestureRecognizerState) {
    NSGestureRecognizerStatePossible, NSGestureRecognizerStateBegan, NSGestureRecognizerStateChanged,
    NSGestureRecognizerStateEnded, NSGestureRecognizerStateCancelled, NSGestureRecognizerStateFailed,
    NSGestureRecognizerStateRecognized = NSGestureRecognizerStateEnded
};

@interface NSImageView : NSControl
+ (instancetype)imageViewWithImage:(NSImage *)image;
@property (nullable, strong) NSImage *image;
@property NSImageScaling imageScaling;
@property NSImageAlignment imageAlignment;
@property NSImageFrameStyle imageFrameStyle;
@property (nullable, copy) NSColor *contentTintColor;
@property (nullable, copy) NSImageSymbolConfiguration *symbolConfiguration;
@property (getter=isEditable) BOOL editable;
@property BOOL animates;
@end

@interface NSButton : NSControl
+ (instancetype)buttonWithTitle:(NSString *)title target:(nullable id)target action:(nullable SEL)action;
+ (instancetype)buttonWithImage:(NSImage *)image target:(nullable id)target action:(nullable SEL)action;
+ (instancetype)buttonWithTitle:(NSString *)title image:(NSImage *)image target:(nullable id)target
                         action:(nullable SEL)action;
+ (instancetype)checkboxWithTitle:(NSString *)title target:(nullable id)target action:(nullable SEL)action;
+ (instancetype)radioButtonWithTitle:(NSString *)title target:(nullable id)target action:(nullable SEL)action;
@property (copy) NSString *title;
@property (copy) NSAttributedString *attributedTitle;
@property (copy) NSString *alternateTitle;
@property (nullable, strong) NSImage *image;
@property (nullable, strong) NSImage *alternateImage;
@property NSCellImagePosition imagePosition;
@property NSImageScaling imageScaling;
@property BOOL imageHugsTitle;
@property NSBezelStyle bezelStyle;
- (void)setButtonType:(NSButtonType)type;
@property NSControlStateValue state;
@property BOOL allowsMixedState;
@property (getter=isBordered) BOOL bordered;
@property (getter=isTransparent) BOOL transparent;
@property BOOL showsBorderOnlyWhileMouseInside;
@property (getter=isSpringLoaded) BOOL springLoaded;
@property (nullable, copy) NSColor *contentTintColor;
@property (nullable, copy) NSColor *bezelColor;
@property (copy) NSString *keyEquivalent;
@property NSEventModifierFlags keyEquivalentModifierMask;
@property (nullable, copy) NSImageSymbolConfiguration *symbolConfiguration;
@property BOOL hasDestructiveAction;
- (void)setPeriodicDelay:(float)delay interval:(float)interval;
- (void)performClick:(nullable id)sender;
- (BOOL)performKeyEquivalent:(NSEvent *)key;
@end

@interface NSProgressIndicator : NSView
@property double doubleValue;
- (void)incrementBy:(double)delta;
@property double minValue;
@property double maxValue;
@property (getter=isIndeterminate) BOOL indeterminate;
@property NSProgressIndicatorStyle style;
@property NSControlSize controlSize;
@property (getter=isDisplayedWhenStopped) BOOL displayedWhenStopped;
@property BOOL usesThreadedAnimation;
@property (getter=isBezeled) BOOL bezeled;
@property (nullable, strong) NSProgress *observedProgress;
- (void)startAnimation:(nullable id)sender;
- (void)stopAnimation:(nullable id)sender;
- (void)sizeToFit;
@end

typedef NS_ENUM(NSInteger, NSSegmentDistribution) {
    NSSegmentDistributionFit = 0,
    NSSegmentDistributionFill,
    NSSegmentDistributionFillEqually,
    NSSegmentDistributionFillProportionally,
};
@interface NSSegmentedControl : NSControl
+ (instancetype)segmentedControlWithLabels:(NSArray<NSString *> *)labels trackingMode:(NSSegmentSwitchTracking)trackingMode
                                    target:(nullable id)target action:(nullable SEL)action;
+ (instancetype)segmentedControlWithImages:(NSArray<NSImage *> *)images trackingMode:(NSSegmentSwitchTracking)trackingMode
                                    target:(nullable id)target action:(nullable SEL)action;
@property NSInteger segmentCount;
@property NSInteger selectedSegment;
@property (readonly) NSInteger indexOfSelectedItem;
@property NSSegmentSwitchTracking trackingMode;
@property NSSegmentStyle segmentStyle;
@property (nullable, copy) NSColor *selectedSegmentBezelColor;
- (BOOL)selectSegmentWithTag:(NSInteger)tag;
@property NSSegmentDistribution segmentDistribution;
@property (getter=isSpringLoaded) BOOL springLoaded;
- (void)setShowsMenuIndicator:(BOOL)show forSegment:(NSInteger)segment;
- (BOOL)showsMenuIndicatorForSegment:(NSInteger)segment;
- (void)setAlignment:(NSTextAlignment)alignment forSegment:(NSInteger)segment;
- (NSTextAlignment)alignmentForSegment:(NSInteger)segment;
- (NSImageScaling)imageScalingForSegment:(NSInteger)segment;
- (void)setLabel:(NSString *)label forSegment:(NSInteger)segment;
- (nullable NSString *)labelForSegment:(NSInteger)segment;
- (void)setImage:(nullable NSImage *)image forSegment:(NSInteger)segment;
- (nullable NSImage *)imageForSegment:(NSInteger)segment;
- (void)setImageScaling:(NSImageScaling)scaling forSegment:(NSInteger)segment;
- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment;
- (CGFloat)widthForSegment:(NSInteger)segment;
- (void)setToolTip:(nullable NSString *)toolTip forSegment:(NSInteger)segment;
- (nullable NSString *)toolTipForSegment:(NSInteger)segment;
- (void)setTag:(NSInteger)tag forSegment:(NSInteger)segment;
- (NSInteger)tagForSegment:(NSInteger)segment;
- (void)setMenu:(nullable NSMenu *)menu forSegment:(NSInteger)segment;
- (nullable NSMenu *)menuForSegment:(NSInteger)segment;
- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment;
- (BOOL)isEnabledForSegment:(NSInteger)segment;
- (void)setSelected:(BOOL)selected forSegment:(NSInteger)segment;
- (BOOL)isSelectedForSegment:(NSInteger)segment;
@end

@interface NSCursor : NSObject
@property (class, readonly, strong) NSCursor *arrowCursor, *IBeamCursor, *IBeamCursorForVerticalLayout,
    *pointingHandCursor, *closedHandCursor, *openHandCursor, *resizeLeftCursor, *resizeRightCursor,
    *resizeLeftRightCursor, *resizeUpCursor, *resizeDownCursor, *resizeUpDownCursor, *crosshairCursor,
    *disappearingItemCursor, *operationNotAllowedCursor, *dragLinkCursor, *dragCopyCursor, *contextualMenuCursor,
    *columnResizeCursor, *rowResizeCursor, *zoomInCursor, *zoomOutCursor, *currentCursor, *currentSystemCursor;
+ (NSCursor *)columnResizeCursorInDirections:(NSCursorFrameResizeDirections)directions;
+ (NSCursor *)rowResizeCursorInDirections:(NSCursorFrameResizeDirections)directions;
+ (NSCursor *)frameResizeCursorFromPosition:(NSCursorFrameResizePosition)position
                               inDirections:(NSCursorFrameResizeDirections)directions;
+ (void)hide;
+ (void)unhide;
+ (void)setHiddenUntilMouseMoves:(BOOL)flag;
+ (void)pop;
- (instancetype)initWithImage:(nullable NSImage *)newImage hotSpot:(NSPoint)point;
@property (nullable, readonly, strong) NSImage *image;
@property (readonly) NSPoint hotSpot;
- (void)set;
- (void)push;
- (void)pop;
@end

@interface NSParagraphStyle : NSObject <NSCopying, NSMutableCopying>
@property (class, readonly, copy) NSParagraphStyle *defaultParagraphStyle;
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(nullable NSString *)languageName;
@property (readonly) NSTextAlignment alignment;
@property (readonly) NSLineBreakMode lineBreakMode;
@property (readonly) CGFloat lineSpacing, paragraphSpacing, paragraphSpacingBefore, headIndent, tailIndent,
    firstLineHeadIndent, minimumLineHeight, maximumLineHeight, lineHeightMultiple, defaultTabInterval;
@property (readonly) float hyphenationFactor;
@property (readonly) NSWritingDirection baseWritingDirection;
@property (readonly, copy) NSArray *tabStops;
@property (readonly) BOOL allowsDefaultTighteningForTruncation;
@end
@interface NSMutableParagraphStyle : NSParagraphStyle
@property NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property CGFloat lineSpacing, paragraphSpacing, paragraphSpacingBefore, headIndent, tailIndent, firstLineHeadIndent,
    minimumLineHeight, maximumLineHeight, lineHeightMultiple, defaultTabInterval;
@property float hyphenationFactor;
@property NSWritingDirection baseWritingDirection;
@property (copy) NSArray *tabStops;
@property BOOL allowsDefaultTighteningForTruncation;
- (void)setParagraphStyle:(NSParagraphStyle *)obj;
@end

@class NSBezierPath;
@interface NSGradient : NSObject <NSCopying>
- (nullable instancetype)initWithStartingColor:(NSColor *)startingColor endingColor:(NSColor *)endingColor;
- (nullable instancetype)initWithColors:(NSArray<NSColor *> *)colorArray;
- (nullable instancetype)initWithColors:(NSArray<NSColor *> *)colorArray
                              locations:(nullable NSArray<NSNumber *> *)locations;
- (nullable instancetype)initWithColorsAndLocations:(NSColor *)firstColor, ... NS_REQUIRES_NIL_TERMINATION;
@property (readonly) NSInteger numberOfColorStops;
- (void)getColor:(NSColor *_Nullable *_Nullable)color location:(nullable CGFloat *)location atIndex:(NSInteger)index;
- (NSColor *)interpolatedColorAtLocation:(CGFloat)location;
- (void)drawFromPoint:(NSPoint)startingPoint toPoint:(NSPoint)endingPoint options:(NSGradientDrawingOptions)options;
- (void)drawInRect:(NSRect)rect angle:(CGFloat)angle;
- (void)drawInBezierPath:(NSBezierPath *)path angle:(CGFloat)angle;
- (void)drawInRect:(NSRect)rect relativeCenterPosition:(NSPoint)relativeCenterPosition;
@end

@class NSSound;
@protocol NSSoundDelegate <NSObject>
@optional
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)flag;
@end
@interface NSSound : NSObject <NSCopying>
+ (nullable instancetype)soundNamed:(NSSoundName)name;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url byReference:(BOOL)byRef;
- (nullable instancetype)initWithContentsOfFile:(NSString *)path byReference:(BOOL)byRef;
@property (nullable, readonly, copy) NSSoundName name;
- (BOOL)setName:(nullable NSSoundName)string;
- (BOOL)play;
- (BOOL)stop;
- (BOOL)pause;
- (BOOL)resume;
@property (readonly, getter=isPlaying) BOOL playing;
@property float volume;
@property BOOL loops;
@property (readonly) NSTimeInterval duration;
@property NSTimeInterval currentTime;
@property (nullable, weak) id<NSSoundDelegate> delegate;
@end

@protocol NSHapticFeedbackPerformer <NSObject>
- (void)performFeedbackPattern:(NSHapticFeedbackPattern)pattern performanceTime:(NSHapticFeedbackPerformanceTime)performanceTime;
@end
@interface NSHapticFeedbackManager : NSObject
@property (class, readonly, strong) id<NSHapticFeedbackPerformer> defaultPerformer;
@end

@interface NSAccessibilityCustomAction : NSObject
- (instancetype)initWithName:(NSString *)name handler:(BOOL (^_Nullable)(void))handler;
- (instancetype)initWithName:(NSString *)name target:(id)target selector:(SEL)selector;
@property (copy) NSString *name;
@property (nullable, copy) BOOL (^handler)(void);
@property (nullable, weak) id target;
@property (nullable) SEL selector;
@end

@class NSGestureRecognizer;
@protocol NSGestureRecognizerDelegate <NSObject>
@optional
- (BOOL)gestureRecognizerShouldBegin:(NSGestureRecognizer *)gestureRecognizer;
@end
@interface NSGestureRecognizer : NSObject
- (instancetype)initWithTarget:(nullable id)target action:(nullable SEL)action;
@property (nullable, weak) id target;
@property (nullable) SEL action;
@property (nullable, readonly) NSView *view;
- (void)_bn_setView:(nullable NSView *)view;
@property NSGestureRecognizerState state;
@property (getter=isEnabled) BOOL enabled;
@property (nullable, weak) id<NSGestureRecognizerDelegate> delegate;
@property BOOL delaysPrimaryMouseButtonEvents;
- (NSPoint)locationInView:(nullable NSView *)view;
@end
@interface NSClickGestureRecognizer : NSGestureRecognizer
@property NSInteger numberOfClicksRequired;
@property NSInteger numberOfTouchesRequired;
@property NSUInteger buttonMask;
@end
@interface NSPressGestureRecognizer : NSGestureRecognizer
@property NSTimeInterval minimumPressDuration;
@property CGFloat allowableMovement;
@property NSUInteger buttonMask;
@end
@interface NSView (BittenGestures)
@property (copy) NSArray<NSGestureRecognizer *> *gestureRecognizers;
- (void)addGestureRecognizer:(NSGestureRecognizer *)gestureRecognizer;
- (void)removeGestureRecognizer:(NSGestureRecognizer *)gestureRecognizer;
@end

typedef NS_ENUM(NSInteger, NSLayoutAttribute) {
    NSLayoutAttributeLeft = 1, NSLayoutAttributeRight, NSLayoutAttributeTop, NSLayoutAttributeBottom,
    NSLayoutAttributeLeading, NSLayoutAttributeTrailing, NSLayoutAttributeWidth, NSLayoutAttributeHeight,
    NSLayoutAttributeCenterX, NSLayoutAttributeCenterY, NSLayoutAttributeLastBaseline,
    NSLayoutAttributeBaseline = NSLayoutAttributeLastBaseline, NSLayoutAttributeFirstBaseline,
    NSLayoutAttributeNotAnAttribute = 0
};
typedef NSString *NSToolbarIdentifier NS_SWIFT_NAME(NSToolbar.Identifier);
typedef NS_ENUM(NSUInteger, NSToolbarDisplayMode) {
    NSToolbarDisplayModeDefault, NSToolbarDisplayModeIconAndLabel, NSToolbarDisplayModeIconOnly,
    NSToolbarDisplayModeLabelOnly
};
typedef NSInteger NSToolbarItemVisibilityPriority NS_TYPED_EXTENSIBLE_ENUM;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityStandard = 0;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityLow = -1000;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityHigh = 1000;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityUser = 2000;
typedef NS_ENUM(NSInteger, NSToolbarItemStyle) {
    NSToolbarItemStylePlain = 0, NSToolbarItemStyleProminent = 1
};
typedef NS_ENUM(NSInteger, NSToolbarItemGroupSelectionMode) {
    NSToolbarItemGroupSelectionModeSelectOne = 0, NSToolbarItemGroupSelectionModeSelectAny = 1,
    NSToolbarItemGroupSelectionModeMomentary = 2
};
typedef NS_ENUM(NSInteger, NSToolbarItemGroupControlRepresentation) {
    NSToolbarItemGroupControlRepresentationAutomatic, NSToolbarItemGroupControlRepresentationExpanded,
    NSToolbarItemGroupControlRepresentationCollapsed
};

@class NSToolbar, NSToolbarItem;
@protocol NSToolbarItemValidation <NSObject>
- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
@end
@protocol NSToolbarDelegate <NSObject>
@optional
- (nullable NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
          willBeInsertedIntoToolbar:(BOOL)flag;
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray<NSToolbarItemIdentifier> *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar;
- (void)toolbarWillAddItem:(NSNotification *)notification;
- (void)toolbarDidRemoveItem:(NSNotification *)notification;
@end

@interface NSToolbarItem : NSObject <NSCopying>
- (instancetype)initWithItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier;
@property (readonly, copy) NSToolbarItemIdentifier itemIdentifier;
@property (nullable, readonly, weak) NSToolbar *toolbar;
- (void)_bn_setToolbar:(nullable NSToolbar *)toolbar;
@property (copy) NSString *label;
@property (copy) NSString *paletteLabel;
@property (copy) NSString *title;
@property (nullable, copy) NSString *toolTip;
@property (nullable, strong) NSImage *image;
@property (nullable, strong) NSView *view;
@property (nullable, weak) id target;
@property (nullable) SEL action;
@property (getter=isEnabled) BOOL enabled;
@property (getter=isBordered) BOOL bordered;
@property (getter=isNavigational) BOOL navigational;
@property (getter=isVisible) BOOL visible;
@property (getter=isHidden) BOOL hidden;
@property BOOL autovalidates;
@property NSInteger tag;
@property NSToolbarItemVisibilityPriority visibilityPriority;
@property NSSize minSize;
@property NSSize maxSize;
@property (nullable, strong) NSMenuItem *menuFormRepresentation;
@property (nullable, copy) NSColor *backgroundTintColor;
@property NSToolbarItemStyle style;
- (void)validate;
@end
@interface NSToolbarItemGroup : NSToolbarItem
+ (instancetype)groupWithItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier titles:(NSArray<NSString *> *)titles
                          selectionMode:(NSToolbarItemGroupSelectionMode)selectionMode
                                 labels:(nullable NSArray<NSString *> *)labels target:(nullable id)target
                                 action:(nullable SEL)action;
+ (instancetype)groupWithItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier images:(NSArray<NSImage *> *)images
                          selectionMode:(NSToolbarItemGroupSelectionMode)selectionMode
                                 labels:(nullable NSArray<NSString *> *)labels target:(nullable id)target
                                 action:(nullable SEL)action;
@property (copy) NSArray<NSToolbarItem *> *subitems;
@property NSToolbarItemGroupSelectionMode selectionMode;
@property NSToolbarItemGroupControlRepresentation controlRepresentation;
@property NSInteger selectedIndex;
- (void)setSelected:(BOOL)selected atIndex:(NSInteger)index;
- (BOOL)isSelectedAtIndex:(NSInteger)index;
@end
@interface NSMenuToolbarItem : NSToolbarItem
@property (strong) NSMenu *menu;
@property BOOL showsIndicator;
@end
@interface NSToolbar : NSObject
- (instancetype)initWithIdentifier:(NSToolbarIdentifier)identifier;
@property (readonly, copy) NSToolbarIdentifier identifier;
@property (nullable, weak) id<NSToolbarDelegate> delegate;
@property (readonly, copy) NSArray<NSToolbarItem *> *items;
@property (nullable, readonly, copy) NSArray<NSToolbarItem *> *visibleItems;
- (void)insertItemWithItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier atIndex:(NSInteger)index;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeItemWithItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier;
@property (getter=isVisible) BOOL visible;
@property NSToolbarDisplayMode displayMode;
@property BOOL allowsUserCustomization;
@property BOOL allowsExtensionItems;
@property BOOL autosavesConfiguration;
@property BOOL showsBaselineSeparator;
@property (nullable, copy) NSToolbarItemIdentifier selectedItemIdentifier;
@property (copy) NSSet<NSToolbarItemIdentifier> *centeredItemIdentifiers;
@property (nullable, copy) NSToolbarItemIdentifier centeredItemIdentifier;
- (void)validateVisibleItems;
- (void)runCustomizationPalette:(nullable id)sender;
@property (readonly) BOOL customizationPaletteIsRunning;
@end

@interface NSTitlebarAccessoryViewController : NSViewController
@property NSLayoutAttribute layoutAttribute;
@property CGFloat fullScreenMinHeight;
@property (getter=isHidden) BOOL hidden;
@property BOOL automaticallyAdjustsSize;
@end

typedef NS_ENUM(NSInteger, NSPopoverBehavior) {
    NSPopoverBehaviorApplicationDefined = 0, NSPopoverBehaviorTransient = 1, NSPopoverBehaviorSemitransient = 2
};
@class NSPopover;
@protocol NSPopoverDelegate <NSObject>
@optional
- (BOOL)popoverShouldClose:(NSPopover *)popover;
- (void)popoverDidShow:(NSNotification *)notification;
- (void)popoverDidClose:(NSNotification *)notification;
@end
@interface NSPopover : NSResponder
@property (nullable, strong) NSViewController *contentViewController;
@property NSSize contentSize;
@property NSPopoverBehavior behavior;
@property BOOL animates;
@property (nullable, strong) NSAppearance *appearance;
@property (readonly, strong) NSAppearance *effectiveAppearance;
@property (nullable, weak) id<NSPopoverDelegate> delegate;
@property (readonly, getter=isShown) BOOL shown;
@property (readonly, getter=isDetached) BOOL detached;
@property NSRect positioningRect;
@property BOOL hidesDetachedWindowOnDeactivate;
- (void)showRelativeToRect:(NSRect)positioningRect ofView:(NSView *)positioningView preferredEdge:(NSRectEdge)preferredEdge;
- (void)performClose:(nullable id)sender;
- (void)close;
@end

typedef NS_ENUM(NSUInteger, NSAlertStyle) {
    NSAlertStyleWarning = 0, NSAlertStyleInformational = 1, NSAlertStyleCritical = 2
};
static const NSModalResponse NSAlertFirstButtonReturn = 1000;
static const NSModalResponse NSAlertSecondButtonReturn = 1001;
static const NSModalResponse NSAlertThirdButtonReturn = 1002;
@class NSAlert;
@protocol NSAlertDelegate <NSObject>
@optional
- (BOOL)alertShowHelp:(NSAlert *)alert;
@end
@interface NSAlert : NSObject
+ (NSAlert *)alertWithError:(NSError *)error;
@property (copy) NSString *messageText;
@property (copy) NSString *informativeText;
@property NSAlertStyle alertStyle;
@property (null_resettable, strong) NSImage *icon;
@property (readonly, copy) NSArray<NSButton *> *buttons;
- (NSButton *)addButtonWithTitle:(NSString *)title;
@property (nullable, strong) NSView *accessoryView;
@property BOOL showsSuppressionButton;
@property (nullable, readonly, strong) NSButton *suppressionButton;
@property BOOL showsHelp;
@property (nullable, copy) NSString *helpAnchor;
@property (nullable, weak) id<NSAlertDelegate> delegate;
@property (readonly, strong) NSWindow *window;
- (void)layout;
- (NSModalResponse)runModal;
- (void)beginSheetModalForWindow:(NSWindow *)sheetWindow
               completionHandler:(void (^_Nullable)(NSModalResponse returnCode))handler;
@end

typedef NSString *NSStatusItemAutosaveName NS_SWIFT_NAME(NSStatusItem.AutosaveName);
typedef NS_OPTIONS(NSUInteger, NSStatusItemBehavior) {
    NSStatusItemBehaviorRemovalAllowed = 1 << 1, NSStatusItemBehaviorTerminationOnRemoval = 1 << 2
};
static const CGFloat NSVariableStatusItemLength = -1;
static const CGFloat NSSquareStatusItemLength = -2;
@class NSStatusBar;
@interface NSStatusBarButton : NSButton
@end
@interface NSStatusItem : NSObject
@property (readonly, weak) NSStatusBar *statusBar;
@property CGFloat length;
@property (nullable, readonly, strong) NSStatusBarButton *button;
@property (nullable, strong) NSMenu *menu;
@property (getter=isVisible) BOOL visible;
@property NSStatusItemBehavior behavior;
@property (null_resettable, copy) NSStatusItemAutosaveName autosaveName;
@end
@interface NSStatusBar : NSObject
@property (class, readonly, strong) NSStatusBar *systemStatusBar;
- (NSStatusItem *)statusItemWithLength:(CGFloat)length;
- (void)removeStatusItem:(NSStatusItem *)item;
@property (readonly, getter=isVertical) BOOL vertical;
@property (readonly) CGFloat thickness;
@end

@protocol NSTextInputClient
@required
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange;
- (void)doCommandBySelector:(SEL)selector;
- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange;
- (void)unmarkText;
- (NSRange)selectedRange;
- (NSRange)markedRange;
- (BOOL)hasMarkedText;
- (nullable NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange;
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText;
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange;
- (NSUInteger)characterIndexForPoint:(NSPoint)point;
@end
typedef NSString *NSTextInputSourceIdentifier NS_SWIFT_NAME(NSTextInputSourceIdentifier);
@interface NSTextInputContext : NSObject
@property (class, readonly, nullable, strong) NSTextInputContext *currentInputContext;
- (instancetype)initWithClient:(id<NSTextInputClient>)client;
@property (readonly, weak) id<NSTextInputClient> client;
@property BOOL acceptsGlyphInfo;
@property (nullable, copy) NSArray<NSString *> *allowedInputSourceLocales;
@property (nullable, readonly) NSArray<NSTextInputSourceIdentifier> *keyboardInputSources;
@property (nullable, copy) NSTextInputSourceIdentifier selectedKeyboardInputSource;
+ (nullable NSString *)localizedNameForInputSource:(NSTextInputSourceIdentifier)inputSourceIdentifier;
- (void)activate;
- (void)deactivate;
- (BOOL)handleEvent:(NSEvent *)event;
- (void)discardMarkedText;
- (void)invalidateCharacterCoordinates;
@end
@interface NSResponder (BittenTextInput)
- (void)interpretKeyEvents:(NSArray<NSEvent *> *)eventArray;
- (void)doCommandBySelector:(SEL)selector;
- (void)insertText:(id)insertString;
- (void)flushBufferedKeyEvents;
@end
@interface NSView (BittenInputContext)
@property (nullable, readonly, strong) NSTextInputContext *inputContext;
@end

@class NSTextView, NSLayoutManager;
@interface NSTextContainer : NSObject
- (instancetype)initWithSize:(NSSize)size;
- (instancetype)initWithContainerSize:(NSSize)size;
@property NSSize size;
@property NSSize containerSize;
@property CGFloat lineFragmentPadding;
@property BOOL widthTracksTextView;
@property BOOL heightTracksTextView;
@property (nullable, weak) NSTextView *textView;
@property (nullable, weak) NSLayoutManager *layoutManager;
@property NSLineBreakMode lineBreakMode;
@property NSUInteger maximumNumberOfLines;
@end
@interface NSLayoutManager : NSObject
@property (nullable, assign) NSMutableAttributedString *textStorage;
@property (readonly, copy) NSArray<NSTextContainer *> *textContainers;
- (void)addTextContainer:(NSTextContainer *)container;
- (void)removeTextContainerAtIndex:(NSUInteger)index;
@property BOOL allowsNonContiguousLayout;
- (void)ensureLayoutForTextContainer:(NSTextContainer *)container;
- (void)ensureLayoutForCharacterRange:(NSRange)charRange;
@property (readonly) NSUInteger numberOfGlyphs;
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)container;
- (NSRange)glyphRangeForCharacterRange:(NSRange)charRange actualCharacterRange:(nullable NSRangePointer)actualCharRange;
- (NSRange)characterRangeForGlyphRange:(NSRange)glyphRange actualGlyphRange:(nullable NSRangePointer)actualGlyphRange;
- (NSRect)usedRectForTextContainer:(NSTextContainer *)container;
- (NSRect)boundingRectForGlyphRange:(NSRange)glyphRange inTextContainer:(NSTextContainer *)container;
- (CGFloat)defaultLineHeightForFont:(NSFont *)theFont;
- (void)invalidateLayoutForCharacterRange:(NSRange)charRange actualCharacterRange:(nullable NSRangePointer)actualCharRange;
- (void)invalidateDisplayForCharacterRange:(NSRange)charRange;
@end
@interface NSTextAttachment : NSObject
- (instancetype)initWithData:(nullable NSData *)contentData ofType:(nullable NSString *)uti;
- (instancetype)initWithFileWrapper:(nullable id)fileWrapper;
@property (nullable, copy) NSData *contents;
@property (nullable, copy) NSString *fileType;
@property (nullable, strong) NSImage *image;
@property NSRect bounds;
@property (nullable, strong) id fileWrapper;
@property (nullable, strong) id attachmentCell;
@end
@protocol NSTextLocation <NSObject>
- (NSComparisonResult)compare:(id<NSTextLocation>)location;
@end
@interface NSTextRange : NSObject
- (nullable instancetype)initWithLocation:(id<NSTextLocation>)location endLocation:(nullable id<NSTextLocation>)endLocation;
- (instancetype)initWithLocation:(id<NSTextLocation>)location;
@property (readonly, strong) id<NSTextLocation> location;
@property (readonly, strong) id<NSTextLocation> endLocation;
@property (readonly, getter=isEmpty) BOOL empty;
- (BOOL)isEqualToTextRange:(NSTextRange *)textRange;
- (BOOL)containsLocation:(id<NSTextLocation>)location;
- (BOOL)containsRange:(NSTextRange *)textRange;
- (BOOL)intersectsWithTextRange:(NSTextRange *)textRange;
@end

@interface NSText : NSView
@end
@protocol NSTextViewDelegate <NSObject>
@optional
- (void)textDidChange:(NSNotification *)notification;
- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange
    replacementString:(nullable NSString *)replacementString;
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
@end
@interface NSTextView : NSText <NSTextInputClient>
- (instancetype)initWithFrame:(NSRect)frameRect textContainer:(nullable NSTextContainer *)container;
+ (NSScrollView *)scrollableTextView;
- (NSUInteger)characterIndexForInsertionAtPoint:(NSPoint)point;
@property (nullable, readonly, strong) NSMutableAttributedString *textStorage;
@property (nullable, strong) NSTextContainer *textContainer;
@property (nullable, readonly, strong) NSLayoutManager *layoutManager;
@property (copy) NSString *string;
@property (nullable, strong) NSFont *font;
@property (nullable, copy) NSColor *textColor;
@property (copy) NSDictionary<NSAttributedStringKey, id> *typingAttributes;
@property (getter=isEditable) BOOL editable;
@property (getter=isSelectable) BOOL selectable;
@property (getter=isRichText) BOOL richText;
@property BOOL importsGraphics;
@property (getter=isFieldEditor) BOOL fieldEditor;
@property BOOL drawsBackground;
@property (copy) NSColor *backgroundColor;
@property (copy) NSColor *insertionPointColor;
@property BOOL allowsUndo;
@property BOOL usesFindBar;
@property (getter=isContinuousSpellCheckingEnabled) BOOL continuousSpellCheckingEnabled;
- (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)flag;
- (void)setAutomaticDashSubstitutionEnabled:(BOOL)flag;
- (void)setAutomaticTextReplacementEnabled:(BOOL)flag;
- (void)setAutomaticSpellingCorrectionEnabled:(BOOL)flag;
- (void)setAutomaticLinkDetectionEnabled:(BOOL)flag;
- (void)setAutomaticDataDetectionEnabled:(BOOL)flag;
- (void)setAutomaticTextCompletionEnabled:(BOOL)flag;
- (void)setGrammarCheckingEnabled:(BOOL)flag;
- (void)setSmartInsertDeleteEnabled:(BOOL)flag;
- (void)setDisplaysLinkToolTips:(BOOL)flag;
- (void)setUsesFontPanel:(BOOL)flag;
@property NSTextAlignment alignment;
@property NSWritingDirection baseWritingDirection;
@property (nullable, copy) NSParagraphStyle *defaultParagraphStyle;
@property (copy) NSDictionary<NSAttributedStringKey, id> *markedTextAttributes;
@property (copy) NSDictionary<NSAttributedStringKey, id> *selectedTextAttributes;
@property (nullable, copy) NSDictionary<NSAttributedStringKey, id> *linkTextAttributes;
@property BOOL usesRuler;
@property (getter=isRulerVisible) BOOL rulerVisible;
@property BOOL usesInspectorBar;
@property (getter=isAutomaticQuoteSubstitutionEnabled) BOOL automaticQuoteSubstitutionEnabled;
@property (getter=isAutomaticDashSubstitutionEnabled) BOOL automaticDashSubstitutionEnabled;
@property (getter=isAutomaticTextReplacementEnabled) BOOL automaticTextReplacementEnabled;
@property (getter=isAutomaticSpellingCorrectionEnabled) BOOL automaticSpellingCorrectionEnabled;
@property (getter=isAutomaticLinkDetectionEnabled) BOOL automaticLinkDetectionEnabled;
@property (getter=isAutomaticDataDetectionEnabled) BOOL automaticDataDetectionEnabled;
@property (getter=isAutomaticTextCompletionEnabled) BOOL automaticTextCompletionEnabled;
@property (getter=isGrammarCheckingEnabled) BOOL grammarCheckingEnabled;
@property BOOL smartInsertDeleteEnabled;
@property BOOL allowsDocumentBackgroundColorChange;
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string;
- (void)setFont:(NSFont *)font range:(NSRange)range;
- (void)setTextColor:(nullable NSColor *)color range:(NSRange)range;
- (void)delete:(nullable id)sender;
- (void)setAlignment:(NSTextAlignment)alignment range:(NSRange)range;
- (NSAttributedString *)attributedString;
- (BOOL)performValidatedReplacementInRange:(NSRange)range withAttributedString:(NSAttributedString *)string;
- (void)setBaseWritingDirection:(NSWritingDirection)direction range:(NSRange)range;
- (void)setUsesRuler:(BOOL)flag;
- (void)setAllowsImageEditing:(BOOL)flag;
@property (getter=isHorizontallyResizable) BOOL horizontallyResizable;
@property (getter=isVerticallyResizable) BOOL verticallyResizable;
@property NSSize minSize;
@property NSSize maxSize;
@property NSSize textContainerInset;
@property (readonly) NSPoint textContainerOrigin;
@property (nullable, weak) id<NSTextViewDelegate> delegate;
@property (copy) NSArray<NSValue *> *selectedRanges;
- (void)setSelectedRange:(NSRange)charRange;
- (void)selectAll:(nullable id)sender;
- (void)scrollRangeToVisible:(NSRange)range;
- (void)sizeToFit;
- (BOOL)shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(nullable NSString *)replacementString;
- (void)didChangeText;
- (void)insertText:(id)insertString;
- (void)copy:(nullable id)sender;
- (void)cut:(nullable id)sender;
- (void)paste:(nullable id)sender;
- (void)insertNewline:(nullable id)sender;
- (void)insertTab:(nullable id)sender;
- (void)deleteBackward:(nullable id)sender;
- (void)deleteForward:(nullable id)sender;
- (void)moveLeft:(nullable id)sender;
- (void)moveRight:(nullable id)sender;
- (void)moveUp:(nullable id)sender;
- (void)moveDown:(nullable id)sender;
- (void)moveToBeginningOfLine:(nullable id)sender;
- (void)moveToEndOfLine:(nullable id)sender;
- (void)moveToBeginningOfDocument:(nullable id)sender;
- (void)moveToEndOfDocument:(nullable id)sender;
@end

typedef NS_ENUM(NSInteger, NSWritingToolsBehavior) {
    NSWritingToolsBehaviorNone = -1, NSWritingToolsBehaviorDefault = 0, NSWritingToolsBehaviorComplete,
    NSWritingToolsBehaviorLimited
};
typedef NS_OPTIONS(NSUInteger, NSWritingToolsResultOptions) {
    NSWritingToolsResultDefault = 0, NSWritingToolsResultPlainText = 1 << 0, NSWritingToolsResultRichText = 1 << 1,
    NSWritingToolsResultList = 1 << 2, NSWritingToolsResultTable = 1 << 3
};
@interface NSTextField (BittenWritingTools)
@property BOOL allowsWritingTools;
@property NSWritingToolsBehavior writingToolsBehavior;
@property NSWritingToolsResultOptions allowedWritingToolsResultOptions;
@property (getter=isAutomaticTextCompletionEnabled) BOOL automaticTextCompletionEnabled;
@end
@interface NSTextView (BittenWritingTools)
@property BOOL allowsWritingTools;
@property NSWritingToolsBehavior writingToolsBehavior;
@property NSWritingToolsResultOptions allowedWritingToolsResultOptions;
@property BOOL usesAdaptiveColorMappingForDarkAppearance;
@end
@interface NSControl (BittenCellClass)
@property (class, nullable) Class cellClass;
- (void)setCell:(nullable id)cell;
@property (getter=isContinuous) BOOL continuous;
@end

@interface NSEvent (BittenMonitors)
+ (nullable id)addLocalMonitorForEventsMatchingMask:(NSEventMask)mask
                                            handler:(NSEvent *_Nullable (^)(NSEvent *event))block;
+ (nullable id)addGlobalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(void (^)(NSEvent *event))block;
+ (void)removeMonitor:(id)eventMonitor;
@end

@interface NSDockTile : NSObject
@property (readonly) NSSize size;
@property (nullable, copy) NSString *badgeLabel;
@property (nullable, strong) NSView *contentView;
@property BOOL showsApplicationBadge;
@property (nullable, readonly, weak) id owner;
- (void)display;
@end
@interface NSApplication (BittenServices)
@property (nullable, strong) id servicesProvider;
- (void)registerServicesMenuSendTypes:(NSArray<NSPasteboardType> *)sendTypes returnTypes:(NSArray<NSPasteboardType> *)returnTypes;
@property (readonly, strong) NSDockTile *dockTile;
@property (readonly, copy) NSArray<NSWindow *> *orderedWindows;
@property (readonly, getter=isFullKeyboardAccessEnabled) BOOL fullKeyboardAccessEnabled;
@end

typedef NS_OPTIONS(NSUInteger, NSWindowOcclusionState) { NSWindowOcclusionStateVisible = 1UL << 1 } NS_SWIFT_NAME(NSWindow.OcclusionState);
@interface NSWindow (BittenOcclusion)
@property (readonly) NSWindowOcclusionState occlusionState;
@end
@interface NSApplication (BittenAppleEvents)
- (void)_bn_installCoreEventHandlers;
@end

typedef NS_ENUM(NSInteger, NSMenuSelectionMode) {
    NSMenuSelectionModeAutomatic = 0, NSMenuSelectionModeSelectOne = 1, NSMenuSelectionModeSelectAny = 2
};
@protocol NSMenuDelegate <NSObject>
@optional
- (void)menuNeedsUpdate:(NSMenu *)menu;
- (NSInteger)numberOfItemsInMenu:(NSMenu *)menu;
- (BOOL)menu:(NSMenu *)menu updateItem:(NSMenuItem *)item atIndex:(NSInteger)index shouldCancel:(BOOL)shouldCancel;
- (void)menuWillOpen:(NSMenu *)menu;
- (void)menuDidClose:(NSMenu *)menu;
- (void)menu:(NSMenu *)menu willHighlightItem:(nullable NSMenuItem *)item;
@end
@interface NSMenu (BittenExtras)
@property (nullable, weak) id<NSMenuDelegate> delegate;
@property CGFloat minimumWidth;
@property (null_resettable, strong) NSFont *font;
@property NSMenuSelectionMode selectionMode;
@property (readonly) CGFloat menuBarHeight;
@property (readonly) NSSize size;
- (NSInteger)indexOfItemWithTitle:(NSString *)title;
- (BOOL)popUpMenuPositioningItem:(nullable NSMenuItem *)item atLocation:(NSPoint)location inView:(nullable NSView *)view
    NS_SWIFT_NAME(popUp(positioning:at:in:));
+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view;
+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view withFont:(nullable NSFont *)font;
- (void)cancelTracking;
- (void)cancelTrackingWithoutAnimation;
@end
@interface NSMenuItem (BittenExtras)
@property (nullable, strong) NSView *view;
@property (nullable, strong) id representedObject;
@property (nullable, copy) NSString *subtitle;
@property (readonly, getter=isHighlighted) BOOL highlighted;
@property (readonly, getter=isHiddenOrHasHiddenAncestor) BOOL hiddenOrHasHiddenAncestor;
@property (nullable, readonly, weak) NSMenuItem *parentItem;
@end
