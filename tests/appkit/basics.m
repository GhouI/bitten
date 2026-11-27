// AppKit object model: the application and its delegate, windows, views
// and their hierarchy, hit testing, drawing passes.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static int draws;
@interface Box : NSView
@end
@implementation Box
- (void)drawRect:(NSRect)r { draws++; }
@end

/* What a view sees as the application's current event while handling one. */
static NSEvent *seen_current;
@interface Clicky : NSView
@end
@implementation Clicky
- (void)mouseDown:(NSEvent *)e { seen_current = NSApp.currentEvent; }
@end

/* Records what its tracking area reports. */
@interface Hover : NSView
@property int entered, exited, moved, updates;
@end
@implementation Hover
- (void)updateTrackingAreas {
    self.updates++;
    for (NSTrackingArea *a in self.trackingAreas) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                                                               NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                         owner:self userInfo:@{@"k" : @1}]];
}
- (void)mouseEntered:(NSEvent *)e {
    if (e.trackingArea.owner == self && [((__bridge NSDictionary *)e.userData)[@"k"] intValue] == 1) self.entered++;
}
- (void)mouseExited:(NSEvent *)e { self.exited++; }
- (void)mouseMoved:(NSEvent *)e { self.moved++; }
@end

/* The target of menu items. */
@interface Picker : NSObject
@property int picked;
- (void)pick:(id)sender;
@end
@implementation Picker
- (void)pick:(NSMenuItem *)sender { self.picked = (int)sender.tag; }
@end

/* Records its view's appearances. */
@interface Watched : NSViewController
@property (copy) NSString *log;
@end
@implementation Watched
- (void)loadView { self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]; }
- (void)viewWillAppear { self.log = [self.log ?: @"" stringByAppendingString:@"w"]; }
- (void)viewDidAppear { self.log = [self.log stringByAppendingString:@"a"]; }
- (void)viewWillDisappear { self.log = [self.log stringByAppendingString:@"x"]; }
- (void)viewDidDisappear { self.log = [self.log stringByAppendingString:@"d"]; }
@end

/* Keeps its colour in its layer, refreshed in updateLayer. */
@interface LayerKeeper : NSView
@property int updates;
@end
@implementation LayerKeeper
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { self.updates++; }
@end

/* Takes a command-key equivalent before the main menu does. */
@interface KeyTaker : NSView
@property int taken;
@end
@implementation KeyTaker
- (BOOL)performKeyEquivalent:(NSEvent *)e {
    if (![e.charactersIgnoringModifiers isEqualToString:@"k"]) return NO;
    self.taken++;
    return YES;
}
@end

/* Takes copy: when it has something to copy. */
@interface Copier : NSView
@property int copies;
@property BOOL hasSelection;
@end
@implementation Copier
- (BOOL)acceptsFirstResponder { return YES; }
- (void)copy:(id)sender { self.copies++; }
- (BOOL)validateMenuItem:(NSMenuItem *)item { return self.hasSelection; }
@end

/* Notes when it leaves its window, and when it goes. */
static int left_window, views_freed;
@interface Leaver : NSView
@end
@implementation Leaver
- (void)viewDidMoveToWindow {
    if (!self.window) left_window++;
}
- (void)dealloc { views_freed++; }
@end

/* Counts live resizes. */
@interface Resizee : NSView
@property int started, ended;
@end
@implementation Resizee
- (void)viewWillStartLiveResize { self.started++; }
- (void)viewDidEndLiveResize { self.ended++; }
@end

@interface Delegate : NSObject <NSApplicationDelegate>
@property int launched;
@end
@implementation Delegate
- (void)applicationDidFinishLaunching:(NSNotification *)n { self.launched++; }
@end

@interface Focusable : NSView
@property int resigned;
@end
@implementation Focusable
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)resignFirstResponder { self.resigned++; return NO; }   /* refuses: removal goes ahead anyway */
@end

@interface NSEvent (BittenMouse)
+ (void)_bn_setMouseLocation:(NSPoint)p flags:(NSEventModifierFlags)f;
@end
@interface NSWindow (BittenBacking)
- (CGContextRef)_bn_backingContext;
@end

int main(void) {
    NSApplication *app = [NSApplication sharedApplication];
    CHECK(app == NSApp);
    Delegate *d = [Delegate new];
    app.delegate = d;
    [app finishLaunching];
    CHECK(d.launched == 1 && app.active);

    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing:NSBackingStoreBuffered defer:NO];
    CHECK(w.frame.size.height == 328 && w.contentView.frame.size.height == 300);
    /* The title bar's buttons sit where the display draws them, left to
     * right: a program lays its own title bar items out after them. */
    NSButton *close = [w standardWindowButton:NSWindowCloseButton], *zoom = [w standardWindowButton:NSWindowZoomButton];
    CHECK(close && zoom && NSMinX(close.frame) < NSMinX(zoom.frame) && NSMaxX(zoom.frame) > 60);
    Box *outer = [[Box alloc] initWithFrame:NSMakeRect(10, 10, 200, 100)];
    Box *inner = [[Box alloc] initWithFrame:NSMakeRect(5, 5, 50, 50)];
    [outer addSubview:inner];
    [w.contentView addSubview:outer];
    CHECK(inner.window == w && outer.superview == w.contentView && inner.nextResponder == outer);
    [w makeKeyAndOrderFront:nil];
    CHECK(w.visible && w.keyWindow && app.keyWindow == w && draws == 2);
    CHECK([w.contentView hitTest:NSMakePoint(20, 20)] == inner);
    CHECK([w.contentView hitTest:NSMakePoint(100, 80)] == outer);
    NSPoint p = [inner convertPoint:NSMakePoint(1, 1) toView:nil];
    CHECK(p.x == 16 && p.y == 16);
    [inner removeFromSuperview];
    CHECK(inner.window == nil && outer.subviews.count == 0);
    CHECK([NSColor redColor].redComponent == 1 && [NSFont systemFontOfSize:12].pointSize == 12);
    CHECK([NSScreen mainScreen].frame.size.width == 1440);
    CHECK(NSFontWeightBold == 0.4 && [NSWindowDidResizeNotification isEqual:@"NSWindowDidResizeNotification"]);
    [w setContentSize:NSMakeSize(500, 400)];
    CHECK(w.contentView.frame.size.width == 500);

    /* The event being dispatched is the application's current event. */
    Clicky *clicky = [[Clicky alloc] initWithFrame:NSMakeRect(300, 300, 50, 50)];
    [w.contentView addSubview:clicky];
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(310, 310)
                                  modifierFlags:0 timestamp:0 windowNumber:w.windowNumber context:nil
                                    eventNumber:0 clickCount:1 pressure:1];
    [app sendEvent:down];
    CHECK(seen_current == down && app.currentEvent == down);

    /* Tracking areas: set up when the view joins the window, then told as
     * the mouse enters, moves inside and leaves. */
    Hover *hover = [[Hover alloc] initWithFrame:NSMakeRect(100, 100, 50, 50)];
    [w.contentView addSubview:hover];
    NSEvent * (^move)(CGFloat, CGFloat) = ^(CGFloat x, CGFloat y) {
        return [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:NSMakePoint(x, y) modifierFlags:0
                                 timestamp:0 windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:0
                                  pressure:0];
    };
    [w sendEvent:move(10, 10)];
    CHECK(hover.updates == 1 && hover.entered == 0);
    [w sendEvent:move(120, 120)];
    [w sendEvent:move(125, 125)];
    CHECK(hover.entered == 1 && hover.moved == 2 && hover.exited == 0);
    [w sendEvent:move(300, 10)];
    CHECK(hover.entered == 1 && hover.exited == 1);

    /* Key status moves with notifications; a key window ordered out
     * passes it back to the titled window behind it. */
    __block int resigned = 0, became = 0;
    NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered defer:NO];
    id o1 = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidResignKeyNotification object:w queue:nil
                                                          usingBlock:^(NSNotification *n) { resigned++; }];
    id o2 = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification object:w queue:nil
                                                          usingBlock:^(NSNotification *n) { became++; }];
    [w makeKeyAndOrderFront:nil];
    CHECK(became == 0 && resigned == 0);  // already key
    [panel makeKeyAndOrderFront:nil];
    CHECK(panel.keyWindow && !w.keyWindow && resigned == 1);
    [panel orderOut:nil];
    CHECK(!panel.keyWindow && w.keyWindow && became == 1);
    [[NSNotificationCenter defaultCenter] removeObserver:o1];
    [[NSNotificationCenter defaultCenter] removeObserver:o2];

    /* Menus: items know their menu; separators are made as such; a pop-up
     * menu shows in a window of its own, and the keyboard picks an item. */
    Picker *picker = [Picker new];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"m"];
    NSMenuItem *first = [menu addItemWithTitle:@"First" action:@selector(pick:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *second = [menu addItemWithTitle:@"Second" action:@selector(pick:) keyEquivalent:@"s"];
    NSMenuItem *blank = [menu addItemWithTitle:@"" action:NULL keyEquivalent:@""];
    first.target = second.target = picker;
    first.tag = 1, second.tag = 2;
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@"sub"];
    blank.submenu = sub;
    CHECK(first.menu == menu && sub.supermenu == menu && [menu itemAtIndex:1].isSeparatorItem && !blank.isSeparatorItem);
    NSUInteger before = app.windows.count;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(10, 10) inView:w.contentView];
    NSWindow *menuWindow = app.windows.lastObject;
    CHECK(app.windows.count == before + 1 && menuWindow.level == NSPopUpMenuWindowLevel && menuWindow.visible &&
          menuWindow.keyWindow);
    NSEvent * (^key)(unichar) = ^(unichar c) {
        NSString *s = [NSString stringWithCharacters:&c length:1];
        return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                            windowNumber:menuWindow.windowNumber context:nil characters:s charactersIgnoringModifiers:s
                               isARepeat:NO keyCode:0];
    };
    [menuWindow sendEvent:key(NSDownArrowFunctionKey)];  /* First */
    [menuWindow sendEvent:key(NSDownArrowFunctionKey)];  /* over the separator: Second */
    [menuWindow sendEvent:key('\r')];
    CHECK(picker.picked == 2 && !menuWindow.visible && w.keyWindow);

    /* A controller's view appears with a visible window and disappears
     * when it leaves or the window goes. */
    Watched *watched = [Watched new];
    NSWindow *hiddenWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50)
                                                         styleMask:NSWindowStyleMaskTitled
                                                           backing:NSBackingStoreBuffered defer:NO];
    [hiddenWindow.contentView addSubview:watched.view];
    CHECK(watched.log == nil);                         /* not visible yet */
    [hiddenWindow orderFront:nil];
    CHECK([watched.log isEqualToString:@"wa"]);
    [watched.view removeFromSuperview];
    CHECK([watched.log isEqualToString:@"waxd"]);
    [hiddenWindow.contentView addSubview:watched.view];
    [hiddenWindow orderOut:nil];
    CHECK([watched.log isEqualToString:@"waxdwaxd"]);

    /* System colours follow the drawing appearance. */
    NSAppearance *darkAqua = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSAppearance *aqua = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    __block CGFloat darkBg = 0, lightBg = 0, darkLabel = 0;
    [darkAqua performAsCurrentDrawingAppearance:^{
        darkBg = NSColor.windowBackgroundColor.redComponent;
        darkLabel = NSColor.labelColor.redComponent;
    }];
    [aqua performAsCurrentDrawingAppearance:^{ lightBg = NSColor.windowBackgroundColor.redComponent; }];
    CHECK(darkBg < 0.3 && lightBg > 0.9 && darkLabel > 0.9);

    /* An appearance change has update-layer views refresh their layers. */
    CHECK(dlopen("/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore", RTLD_NOW) != NULL);
    LayerKeeper *keeper = [[LayerKeeper alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
    keeper.wantsLayer = YES;
    [w.contentView addSubview:keeper];
    [w display];
    int updatesBefore = keeper.updates;
    w.appearance = darkAqua;
    [w display];
    CHECK(keeper.updates > updatesBefore);

    /* A template image draws in the label colour of the appearance. */
    NSImage *glyph = [NSImage imageWithSize:NSMakeSize(4, 4) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [[NSColor blackColor] setFill];
        NSRectFill(r);
        return YES;
    }];
    glyph.template = YES;
    NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(40, 40, 4, 4)];
    iv.image = glyph;
    [w.contentView addSubview:iv];
    [w display];
    CGContextRef backing = [w _bn_backingContext];
    const unsigned char *bp = CGBitmapContextGetData(backing);
    size_t bpr = CGBitmapContextGetBytesPerRow(backing), bh = CGBitmapContextGetHeight(backing);
    const unsigned char *pix = bp + (bh - 42) * bpr + 42 * 4;   /* BGRA, rows top down */
    CHECK(pix[0] > 200 && pix[1] > 200 && pix[2] > 200);      /* white-ish in dark */

    /* Command keys go to the key window's views before the main menu. */
    KeyTaker *taker = [[KeyTaker alloc] initWithFrame:NSMakeRect(0, 0, 5, 5)];
    [w.contentView addSubview:taker];
    [w makeKeyAndOrderFront:nil];
    NSEvent *cmdK = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                                    timestamp:0 windowNumber:w.windowNumber context:nil characters:@"k"
                  charactersIgnoringModifiers:@"k" isARepeat:NO keyCode:40];
    [app sendEvent:cmdK];
    CHECK(taker.taken == 1);

    /* The first responder leaving its window leaves the window first
     * responder (after being asked to resign), even inside a removed parent. */
    NSView *holder = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
    Focusable *focus = [[Focusable alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    [holder addSubview:focus];
    [w.contentView addSubview:holder];
    CHECK([w makeFirstResponder:focus] && w.firstResponder == focus);
    [holder removeFromSuperview];
    CHECK(w.firstResponder == w && focus.resigned == 1);

    /* A menu item's key equivalent counts only when something along the
     * responder chain takes its action and validates the item. */
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    NSEvent *cmdC = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                                    timestamp:0 windowNumber:w.windowNumber context:nil characters:@"c"
                  charactersIgnoringModifiers:@"c" isARepeat:NO keyCode:8];
    CHECK(![edit performKeyEquivalent:cmdC]);                /* nobody copies */
    Copier *copier = [[Copier alloc] initWithFrame:NSMakeRect(0, 0, 5, 5)];
    [w.contentView addSubview:copier];
    [w makeFirstResponder:copier];
    CHECK(![edit performKeyEquivalent:cmdC] && copier.copies == 0);   /* nothing selected */
    copier.hasSelection = YES;
    CHECK([edit performKeyEquivalent:cmdC] && copier.copies == 1);

    /* A key nothing along the responder chain takes ends at the window,
     * which offers it as a key equivalent: Escape presses a Cancel button. */
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:copier action:@selector(copy:)];
    cancel.keyEquivalent = @"\e";
    [w.contentView addSubview:cancel];
    NSEvent *esc = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                windowNumber:w.windowNumber context:nil characters:@"\e" charactersIgnoringModifiers:@"\e"
                                   isARepeat:NO keyCode:53];
    [w sendEvent:esc];
    CHECK(copier.copies == 2);

    /* Views don't own their window or superview: a window let go is freed
     * with its views, which are told they left it; a view kept after its
     * superview goes has no superview. */
    Leaver *kept = nil;
    @autoreleasepool {
        NSWindow *gone = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50) styleMask:NSWindowStyleMaskTitled
                                                       backing:NSBackingStoreBuffered defer:NO];
        Leaver *a = [[Leaver alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [gone.contentView addSubview:a];
        [gone makeFirstResponder:a];
        [gone close];
        gone = nil;
    }
    /* (a display it had asked for holds it until the main queue runs) */
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    CHECK(left_window == 1 && views_freed == 1);
    @autoreleasepool {
        NSView *parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
        kept = [[Leaver alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [parent addSubview:kept];
        CHECK(kept.superview == parent);
        parent = nil;
    }
    CHECK(kept.superview == nil);

    /* A window knows where the mouse is now, in its own coordinates. */
    [NSEvent _bn_setMouseLocation:NSMakePoint(w.frame.origin.x + 30, w.frame.origin.y + 40) flags:0];
    NSPoint at = w.mouseLocationOutsideOfEventStream;
    CHECK(at.x == 30 && at.y == 40);

    /* Sizes from the display's grip make a live resize, which ends once
     * they stop: views hear the start once and the end once. */
    Resizee *rz = [[Resizee alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    [w.contentView addSubview:rz];
    [w _bn_liveResizeStep];
    [w _bn_liveResizeStep];
    CHECK(w.inLiveResize && rz.inLiveResize && rz.started == 1 && rz.ended == 0);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
    CHECK(!w.inLiveResize && rz.started == 1 && rz.ended == 1);

    /* Tracking loops take queued events by mask; others stay, in order. */
    NSEvent *(^mouse)(NSEventType) = ^(NSEventType t) {
        return [NSEvent mouseEventWithType:t location:NSMakePoint(5, 5) modifierFlags:0 timestamp:0
                              windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    };
    [NSApp postEvent:mouse(NSEventTypeLeftMouseDragged) atStart:NO];
    [NSApp postEvent:mouse(NSEventTypeRightMouseDown) atStart:NO];
    [NSApp postEvent:mouse(NSEventTypeLeftMouseUp) atStart:NO];
    NSEvent *got = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:[NSDate distantPast]
                                         inMode:NSEventTrackingRunLoopMode dequeue:YES];
    CHECK(got.type == NSEventTypeLeftMouseUp);
    CHECK(![NSApp nextEventMatchingMask:NSEventMaskKeyDown untilDate:nil inMode:NSDefaultRunLoopMode dequeue:YES]);
    __block int seen = 0;
    [NSEvent trackEventsMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDown timeout:1
                                mode:NSEventTrackingRunLoopMode handler:^(NSEvent *e, BOOL *stop) {
        seen++;
        if (e.type == NSEventTypeRightMouseDown) *stop = YES;
    }];
    CHECK(seen == 2);

    /* Main follows key for windows that can be main; moving a window posts
     * that it moved. */
    NSWindow *w2 = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50) styleMask:NSWindowStyleMaskTitled
                                                 backing:NSBackingStoreBuffered defer:NO];
    [w makeKeyAndOrderFront:nil];
    CHECK(w.isMainWindow && NSApp.mainWindow == w);
    [w2 makeKeyAndOrderFront:nil];
    CHECK(w2.isMainWindow && !w.isMainWindow && NSApp.mainWindow == w2);
    __block int moves = 0;
    id obs = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidMoveNotification object:w2 queue:nil
                                                           usingBlock:^(NSNotification *n) { moves++; }];
    [w2 setFrameOrigin:NSMakePoint(100, 100)];
    [w2 setFrameOrigin:NSMakePoint(100, 100)];
    CHECK(moves == 1);
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    [w2 orderOut:nil];
    CHECK(!w2.isMainWindow && w.isMainWindow);
    puts("AppKit basics ok");
    return 0;
}
