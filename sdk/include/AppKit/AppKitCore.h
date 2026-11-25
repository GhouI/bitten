/* bitten SDK: the stateful core of AppKit (hand-written in frameworks/AppKit).
 * Written from the public documentation. */
#import <AppKit/AppKitBase.h>

@interface NSResponder : NSObject
@property (nullable, assign) NSResponder *nextResponder;
- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
- (void)mouseDown:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (void)rightMouseDown:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;
- (void)keyDown:(NSEvent *)event;
- (void)keyUp:(NSEvent *)event;
- (void)flagsChanged:(NSEvent *)event;
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
@property (readonly, assign) NSView *superview;
@property (readonly, assign) NSWindow *window;
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
- (void)viewWillMoveToWindow:(NSWindow *)window;
- (NSPoint)convertPoint:(NSPoint)point fromView:(NSView *)view;
- (NSPoint)convertPoint:(NSPoint)point toView:(NSView *)view;
- (NSView *)hitTest:(NSPoint)point;
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
}
- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)flag;
@property (strong) NSView *contentView;
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
- (void)makeKeyAndOrderFront:(id)sender;
- (void)orderFront:(id)sender;
- (void)orderOut:(id)sender;
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
- (NSMenu *)applicationDockMenu:(NSApplication *)sender;
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls;
@end

@interface NSApplication : NSResponder
+ (NSApplication *)sharedApplication;
@property (nullable, weak) id<NSApplicationDelegate> delegate;
@property (readonly, copy) NSArray<NSWindow *> *windows;
@property (nullable, readonly, assign) NSWindow *keyWindow;
@property (nullable, readonly, assign) NSWindow *mainWindow;
@property (nullable, strong) NSMenu *mainMenu;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly, getter=isActive) BOOL active;
@property (nullable, strong) NSAppearance *appearance;
- (void)run;
- (void)finishLaunching;
- (void)stop:(id)sender;
- (void)terminate:(id)sender;
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)policy;
- (void)activateIgnoringOtherApps:(BOOL)flag;
- (void)activate;
- (NSEvent *)nextEventMatchingMask:(NSEventMask)mask untilDate:(NSDate *)expiration
                            inMode:(NSRunLoopMode)mode dequeue:(BOOL)deqFlag;
- (void)sendEvent:(NSEvent *)event;
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
@property (class, readonly, strong) NSScreen *mainScreen;
@property (class, readonly, copy) NSArray<NSScreen *> *screens;
@property (readonly) NSRect frame;
@property (readonly) NSRect visibleFrame;
@property (readonly) CGFloat backingScaleFactor;
@end

@interface NSGraphicsContext : NSObject
@property (class, strong) NSGraphicsContext *currentContext;
+ (void)saveGraphicsState;
+ (void)restoreGraphicsState;
@end

@interface NSMenu : NSObject
- (instancetype)initWithTitle:(NSString *)title;
@property (copy) NSString *title;
@property (readonly, copy) NSArray<NSMenuItem *> *itemArray;
@property (readonly) NSInteger numberOfItems;
- (void)addItem:(NSMenuItem *)item;
- (NSMenuItem *)addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key;
- (void)removeAllItems;
@end

@interface NSMenuItem : NSObject
+ (NSMenuItem *)separatorItem;
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key;
@property (copy) NSString *title;
@property (nullable) SEL action;
@property (nullable, weak) id target;
@property (copy) NSString *keyEquivalent;
@property (nullable, strong) NSMenu *submenu;
@property (getter=isEnabled) BOOL enabled;
@property NSInteger tag;
@property (nullable, strong) id representedObject;
@end
