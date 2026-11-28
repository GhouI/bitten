/* Menus on screen: pop-up and context menus drawn in a window of their own,
 * at the pop-up menu level, as AppKit shows them. Rows highlight under the
 * pointer (tracking areas) and with the arrow keys; a click or Return picks
 * an enabled item and sends its action; a submenu opens beside its item;
 * Escape or a click elsewhere closes the menu.
 *
 * AppKit tracks a pop-up menu in a nested event loop and returns when it
 * closes. Here the menu stays up while the program's own loop runs, and
 * popUpMenuPositioningItem:atLocation:inView: returns at once: the chosen
 * item's action (and the delegate's menuDidClose:) come when the menu is
 * used, which is what programs act on. */

#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSMenu (BittenPrepare)
- (void)_bn_prepareForDisplay; /* AppKitMenuExtras.m: the delegate fills the menu */
@end

static const CGFloat kRowHeight = 22, kSeparatorHeight = 10, kInset = 5;

@class BNMenuView;

/* The menus open at once: the one the program popped up and the submenus
 * opened from it, outermost first. */
@interface BNMenuSession : NSObject
@property (strong) NSMutableArray<NSWindow *> *windows;
@property (strong) id monitor;
@property (strong) NSMenu *root;
- (void)closeChosen:(NSMenuItem *)item;
- (void)openSubmenuOf:(NSMenuItem *)item from:(BNMenuView *)view row:(NSRect)row;
- (void)closeAfter:(NSWindow *)window;
@end

static BNMenuSession *current_session;

@interface BNMenuWindow : NSWindow
@end
@implementation BNMenuWindow
- (BOOL)canBecomeKeyWindow { return YES; }
/* Menus are a material over what is behind them: the display blurs it. */
- (BOOL)_bn_hasBehindWindowMaterial { return YES; }
@end

static BOOL menu_dark(NSView *v) {
    return [[v.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
        isEqualToString:NSAppearanceNameDarkAqua];
}

/* A menu's key equivalent as macOS writes it: ⌃⌥⇧⌘ then the key. */
static NSString *key_label(NSMenuItem *item) {
    NSString *key = item.keyEquivalent;
    if (!key.length) return @"";
    NSEventModifierFlags m = item.keyEquivalentModifierMask;
    if (![key.lowercaseString isEqualToString:key]) m |= NSEventModifierFlagShift;
    NSMutableString *s = [NSMutableString string];
    if (m & NSEventModifierFlagControl) [s appendString:@"⌃"];
    if (m & NSEventModifierFlagOption) [s appendString:@"⌥"];
    if (m & NSEventModifierFlagShift) [s appendString:@"⇧"];
    if (m & NSEventModifierFlagCommand) [s appendString:@"⌘"];
    unichar c = [key characterAtIndex:0];
    switch (c) {
    case '\r': [s appendString:@"↩"]; break;
    case '\t': [s appendString:@"⇥"]; break;
    case 0x1b: [s appendString:@"⎋"]; break;
    case 0x7f: case 8: [s appendString:@"⌫"]; break;
    case ' ': [s appendString:@"Space"]; break;
    case 0xF700: [s appendString:@"↑"]; break;
    case 0xF701: [s appendString:@"↓"]; break;
    case 0xF702: [s appendString:@"←"]; break;
    case 0xF703: [s appendString:@"→"]; break;
    case 0xF728: [s appendString:@"⌦"]; break;
    case 0xF729: [s appendString:@"↖"]; break;   /* Home */
    case 0xF72B: [s appendString:@"↘"]; break;   /* End */
    case 0xF72C: [s appendString:@"⇞"]; break;   /* Page Up */
    case 0xF72D: [s appendString:@"⇟"]; break;   /* Page Down */
    case 0xF739: [s appendString:@"⌧"]; break;   /* Clear */
    case 0x03: [s appendString:@"⌤"]; break;     /* Enter */
    case 0x19: [s appendString:@"⇤"]; break;     /* Back Tab */
    default:
        if (c >= 0xF704 && c <= 0xF726) [s appendFormat:@"F%d", c - 0xF704 + 1];   /* F1-F35 */
        else [s appendString:key.uppercaseString];
        break;
    }
    return s;
}

/* (For tests: the label drawn for an item's key equivalent.) */
@implementation NSMenuItem (BittenKeyLabel)
- (NSString *)_bn_keyEquivalentLabel { return key_label(self); }
@end

/* Enables each item whose action has someone to send it to (and who
 * agrees, through validateMenuItem:), as AppKit's menu update does. */
static void validate(NSMenu *menu) {
    if (!menu.autoenablesItems) return;
    for (NSMenuItem *item in menu.itemArray) {
        if (!item.action || item.submenu) continue;
        id target = [NSApp targetForAction:item.action to:item.target from:item];
        BOOL enabled = target != nil;
        if (enabled && [target respondsToSelector:@selector(validateMenuItem:)])
            enabled = ((BOOL(*)(id, SEL, id))objc_msgSend)(target, @selector(validateMenuItem:), item);
        item.enabled = enabled;
    }
}

@interface BNMenuView : NSView
@property (strong) NSMenu *menu;
@property NSInteger highlighted;
@end

/* The items a menu shows: not hidden ones, and no separator at either end
 * or next to another (a menu that ends in one for items the system would
 * add shows no line with nothing under it). */
static NSArray<NSMenuItem *> *bn_shown_items(NSMenu *menu) {
    NSMutableArray<NSMenuItem *> *a = [NSMutableArray array];
    for (NSMenuItem *i in menu.itemArray) {
        if (i.isHidden) continue;
        if (i.isSeparatorItem && (a.count == 0 || a.lastObject.isSeparatorItem)) continue;
        [a addObject:i];
    }
    while (a.count && a.lastObject.isSeparatorItem) [a removeLastObject];
    return a;
}
@implementation BNMenuView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (NSArray<NSMenuItem *> *)visibleItems { return bn_shown_items(self.menu); }
static NSDictionary *text_attrs(NSFont *font, NSColor *color) {
    return @{NSFontAttributeName : font, NSForegroundColorAttributeName : color};
}
/* The menu's size for its items. */
+ (NSSize)sizeForMenu:(NSMenu *)menu {
    /* BITTEN_MENU_DEBUG: the items of each menu shown */
    if (getenv("BITTEN_MENU_DEBUG"))
        for (NSMenuItem *i in menu.itemArray)
            fprintf(stderr, "bitten: menu item '%s'%s%s%s key %s (U+%04X) mask 0x%lx\n", i.title.UTF8String ?: "",
                    i.isSeparatorItem ? " separator" : "", i.isHidden ? " hidden" : "", i.isEnabled ? "" : " disabled",
                    key_label(i).UTF8String, i.keyEquivalent.length ? [i.keyEquivalent characterAtIndex:0] : 0,
                    (unsigned long)i.keyEquivalentModifierMask);
    NSFont *font = menu.font ?: [NSFont menuFontOfSize:0];
    CGFloat w = menu.minimumWidth, h = 2 * kInset;
    for (NSMenuItem *i in bn_shown_items(menu)) {
        if (i.isSeparatorItem) { h += kSeparatorHeight; continue; }
        h += kRowHeight;
        CGFloat tw = [i.title sizeWithAttributes:text_attrs(font, NSColor.labelColor)].width;
        CGFloat kw = [key_label(i) sizeWithAttributes:text_attrs(font, NSColor.labelColor)].width;
        w = MAX(w, 24 + (i.image ? 22 : 0) + tw + (kw > 0 ? kw + 28 : 0) + (i.submenu ? 28 : 0) + 16);
    }
    return NSMakeSize(ceil(MAX(w, 120)), ceil(h));
}
/* The rows of the visible items, top down (separators included). */
- (NSArray<NSValue *> *)rows {
    NSMutableArray *rows = [NSMutableArray array];
    CGFloat y = kInset;
    for (NSMenuItem *i in self.visibleItems) {
        CGFloat h = i.isSeparatorItem ? kSeparatorHeight : kRowHeight;
        [rows addObject:[NSValue valueWithRect:NSMakeRect(kInset, y, self.bounds.size.width - 2 * kInset, h)]];
        y += h;
    }
    return rows;
}
- (NSInteger)rowAt:(NSPoint)p {
    NSArray *rows = self.rows;
    for (NSUInteger k = 0; k < rows.count; k++)
        if (NSPointInRect(p, [rows[k] rectValue])) return (NSInteger)k;
    return -1;
}
- (BOOL)selectable:(NSInteger)row {
    NSArray *items = self.visibleItems;
    if (row < 0 || row >= (NSInteger)items.count) return NO;
    NSMenuItem *i = items[(NSUInteger)row];
    return !i.isSeparatorItem && i.isEnabled;
}
- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:7 yRadius:7];
    /* Light or dark as the menu's appearance; translucent over the blur
     * the display draws behind it. */
    BOOL dark = menu_dark(self);
    [[NSColor colorWithWhite:dark ? 0.17 : 0.97 alpha:0.86] setFill];
    [bg fill];
    [[NSColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.16 : 0.18] setStroke];
    bg.lineWidth = 1;
    [bg stroke];
    NSFont *font = self.menu.font ?: [NSFont menuFontOfSize:0];
    NSArray *items = self.visibleItems, *rows = self.rows;
    BOOL images = NO;
    for (NSMenuItem *i in items) images |= i.image != nil;
    for (NSUInteger k = 0; k < items.count; k++) {
        NSMenuItem *i = items[k];
        NSRect r = [rows[k] rectValue];
        if (i.isSeparatorItem) {
            [[NSColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.14 : 0.12] setFill];
            NSRectFill(NSMakeRect(r.origin.x + 6, NSMidY(r) - 0.5, r.size.width - 12, 1));
            continue;
        }
        BOOL lit = (NSInteger)k == self.highlighted && i.isEnabled;
        if (lit) {
            [NSColor.controlAccentColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] fill];
        }
        NSColor *color = !i.isEnabled ? NSColor.disabledControlTextColor : lit ? NSColor.whiteColor : NSColor.labelColor;
        NSDictionary *attrs = text_attrs(font, color);
        CGFloat textY = r.origin.y + (r.size.height - font.ascender + font.descender) / 2;
        if (i.state != NSControlStateValueOff)
            [(i.state == NSControlStateValueOn ? @"✓" : @"–") drawAtPoint:NSMakePoint(r.origin.x + 6, textY) withAttributes:attrs];
        CGFloat x = r.origin.x + 19;
        if (images) {
            if (i.image) [i.image drawInRect:NSMakeRect(x, r.origin.y + 3, 16, 16)];
            x += 22;
        }
        [i.title drawAtPoint:NSMakePoint(x, textY) withAttributes:attrs];
        NSString *right = i.submenu ? @"›" : key_label(i);
        if (right.length) {
            NSSize s = [right sizeWithAttributes:attrs];
            NSDictionary *dim = text_attrs(font, lit ? NSColor.whiteColor : NSColor.secondaryLabelColor);
            [right drawAtPoint:NSMakePoint(NSMaxX(r) - 10 - s.width, textY) withAttributes:dim];
        }
    }
}
- (void)highlight:(NSInteger)row {
    if (row == self.highlighted) return;
    self.highlighted = row;
    self.needsDisplay = YES;
    [current_session closeAfter:self.window];
    NSArray *items = self.visibleItems;
    if (row >= 0 && row < (NSInteger)items.count && [items[(NSUInteger)row] submenu] && [self selectable:row])
        [current_session openSubmenuOf:items[(NSUInteger)row] from:self row:[self.rows[(NSUInteger)row] rectValue]];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in self.trackingAreas) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                                               NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                         owner:self userInfo:nil]];
}
- (void)mouseMoved:(NSEvent *)e {
    NSInteger row = [self rowAt:[self convertPoint:e.locationInWindow fromView:nil]];
    [self highlight:[self selectable:row] ? row : -1];
}
- (void)mouseEntered:(NSEvent *)e { [self mouseMoved:e]; }
- (void)mouseExited:(NSEvent *)e {
    NSArray *items = self.visibleItems;
    /* a row whose submenu is open stays lit */
    if (self.highlighted >= 0 && self.highlighted < (NSInteger)items.count && [items[(NSUInteger)self.highlighted] submenu]) return;
    [self highlight:-1];
}
- (void)choose:(NSInteger)row {
    if (![self selectable:row]) return;
    NSMenuItem *item = self.visibleItems[(NSUInteger)row];
    if (item.submenu) return;
    [current_session closeChosen:item];
}
- (void)mouseDown:(NSEvent *)e {}
- (void)mouseUp:(NSEvent *)e { [self choose:[self rowAt:[self convertPoint:e.locationInWindow fromView:nil]]]; }
- (void)rightMouseUp:(NSEvent *)e { [self mouseUp:e]; }
- (void)keyDown:(NSEvent *)e {
    NSString *c = e.charactersIgnoringModifiers;
    unichar k = c.length ? [c characterAtIndex:0] : 0;
    NSInteger n = (NSInteger)self.visibleItems.count;
    if (k == NSUpArrowFunctionKey || k == NSDownArrowFunctionKey) {
        NSInteger step = k == NSUpArrowFunctionKey ? -1 : 1, row = self.highlighted;
        for (NSInteger tries = 0; tries < n; tries++) {
            row = row < 0 ? (step > 0 ? 0 : n - 1) : (row + step + n) % n;
            if ([self selectable:row]) break;
        }
        [self highlight:[self selectable:row] ? row : -1];
    } else if (k == '\r' || k == 3 || k == ' ') {
        [self choose:self.highlighted];
    } else if (k == 0x1b) {
        [current_session closeChosen:nil];
    } else if (k == NSLeftArrowFunctionKey) {
        NSWindow *w = self.window;
        if (current_session.windows.count > 1 && current_session.windows.lastObject == w) {
            [current_session.windows removeLastObject];
            [w orderOut:nil];
            [current_session.windows.lastObject makeKeyAndOrderFront:nil];
        }
    } else if (k == NSRightArrowFunctionKey) {
        NSArray *windows = current_session.windows;
        NSUInteger i = [windows indexOfObjectIdenticalTo:self.window];
        if (i != NSNotFound && i + 1 < windows.count) {
            BNMenuView *sub = (BNMenuView *)[windows[i + 1] contentView];
            [windows[i + 1] makeKeyAndOrderFront:nil];
            for (NSInteger r = 0; r < (NSInteger)sub.visibleItems.count; r++)
                if ([sub selectable:r]) { [sub highlight:r]; break; }
        }
    }
}
@end

@implementation BNMenuSession
/* A window for `menu` with its top-left corner at `topLeft` (screen),
 * kept on the screen. */
- (NSWindow *)windowFor:(NSMenu *)menu topLeft:(NSPoint)topLeft {
    [menu _bn_prepareForDisplay];
    validate(menu);
    NSSize size = [BNMenuView sizeForMenu:menu];
    NSRect screen = [NSScreen mainScreen].visibleFrame;
    NSRect f = NSMakeRect(topLeft.x, topLeft.y - size.height, size.width, size.height);
    if (NSMaxX(f) > NSMaxX(screen)) f.origin.x = NSMaxX(screen) - f.size.width;
    if (f.origin.x < screen.origin.x) f.origin.x = screen.origin.x;
    if (f.origin.y < screen.origin.y) f.origin.y = screen.origin.y;
    if (NSMaxY(f) > NSMaxY(screen)) f.origin.y = NSMaxY(screen) - f.size.height;
    BNMenuWindow *w = [[BNMenuWindow alloc] initWithContentRect:f styleMask:NSWindowStyleMaskBorderless
                                                        backing:NSBackingStoreBuffered defer:NO];
    w.level = NSPopUpMenuWindowLevel;
    w.opaque = NO;
    w.backgroundColor = NSColor.clearColor;
    w.releasedWhenClosed = NO;
    BNMenuView *v = [[BNMenuView alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, f.size.height)];
    v.menu = menu;
    v.highlighted = -1;
    w.contentView = v;
    [w makeFirstResponder:v];
    id<NSMenuDelegate> d = menu.delegate;
    if ([d respondsToSelector:@selector(menuWillOpen:)]) [d menuWillOpen:menu];
    return w;
}
- (void)openSubmenuOf:(NSMenuItem *)item from:(BNMenuView *)view row:(NSRect)row {
    NSRect inWindow = [view convertRect:row toView:nil];
    NSRect onScreen = [view.window convertRectToScreen:inWindow];
    NSWindow *w = [self windowFor:item.submenu topLeft:NSMakePoint(NSMaxX(onScreen) + 2, NSMaxY(onScreen) + kInset)];
    [self.windows addObject:w];
    [w orderFront:nil];
}
/* Closes the submenus opened from `window`'s menu. */
- (void)closeAfter:(NSWindow *)window {
    NSUInteger i = [self.windows indexOfObjectIdenticalTo:window];
    if (i == NSNotFound) return;
    while (self.windows.count > i + 1) {
        NSWindow *w = self.windows.lastObject;
        [self.windows removeLastObject];
        [self tellClosed:w];
        [w orderOut:nil];
    }
}
- (void)tellClosed:(NSWindow *)w {
    NSMenu *menu = [(BNMenuView *)w.contentView menu];
    id<NSMenuDelegate> d = menu.delegate;
    if ([d respondsToSelector:@selector(menuDidClose:)]) [d menuDidClose:menu];
}
/* Ends the session; with an item, sends its action (after the menus are
 * gone, as AppKit does). */
- (void)closeChosen:(NSMenuItem *)item {
    if (current_session != self) return;
    BNMenuSession *keep = self; /* current_session held the last reference */
    current_session = nil;
    if (self.monitor) [NSEvent removeMonitor:self.monitor];
    self.monitor = nil;
    for (NSWindow *w in [self.windows reverseObjectEnumerator]) {
        [self tellClosed:w];
        [w orderOut:nil];
    }
    [self.windows removeAllObjects];
    if (!item) return;
    NSMenu *menu = item.menu;
    NSInteger index = [menu indexOfItem:item];
    if (getenv("BITTEN_EVENT_DEBUG"))
        fprintf(stderr, "bitten: menu item '%s' chosen: action %s target %s, index %ld in %s\n", item.title.UTF8String ?: "",
                item.action ? sel_getName(item.action) : "none", item.target ? object_getClassName(item.target) : "nil",
                (long)index, menu ? "its menu" : "no menu");
    if (index >= 0) [menu performActionForItemAtIndex:index];
    (void)keep;
}
@end

@implementation NSMenu (BittenMenuWindow)
/* Shows the menu with `item` (or its top) at `location` in `view` (or on
 * the screen when there is no view). */
- (BOOL)popUpMenuPositioningItem:(NSMenuItem *)item atLocation:(NSPoint)location inView:(NSView *)view {
    [current_session closeChosen:nil];
    NSPoint p = location;
    if (view.window) p = [view.window convertPointToScreen:[view convertPoint:location toView:nil]];
    BNMenuSession *s = [BNMenuSession new];
    s.windows = [NSMutableArray array];
    s.root = self;
    current_session = s;
    if (item) {
        /* the item's row goes where the menu was asked to put it */
        CGFloat above = kInset;
        for (NSMenuItem *i in bn_shown_items(self)) {
            if (i == item) break;
            above += i.isSeparatorItem ? kSeparatorHeight : kRowHeight;
        }
        p.y += above + (view && !view.isFlipped ? kRowHeight : 0);
    }
    NSWindow *w = [s windowFor:self topLeft:p];
    [s.windows addObject:w];
    [w makeKeyAndOrderFront:nil];
    if (item) {
        BNMenuView *v = (BNMenuView *)w.contentView;
        NSInteger row = (NSInteger)[v.visibleItems indexOfObjectIdenticalTo:item];
        if ([v selectable:row]) v.highlighted = row;
    }
    /* A click outside the menus closes them (and goes no further). */
    __weak BNMenuSession *weak = s;
    s.monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
                                                      handler:^NSEvent *(NSEvent *e) {
        BNMenuSession *session = weak;
        if (!session || [session.windows indexOfObjectIdenticalTo:e.window] != NSNotFound) return e;
        [session closeChosen:nil];
        return nil;
    }];
    return NO;
}
+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view {
    NSPoint p = [view convertPoint:event.locationInWindow fromView:nil];
    [menu popUpMenuPositioningItem:nil atLocation:p inView:view];
}
+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view withFont:(NSFont *)font {
    [self popUpContextMenu:menu withEvent:event forView:view];
}
- (void)cancelTracking { [current_session closeChosen:nil]; }
- (void)cancelTrackingWithoutAnimation { [current_session closeChosen:nil]; }
@end

/* A right click shows the view's context menu (menuForEvent:), as NSView
 * does; without one it goes up the responder chain. */
@implementation NSView (BittenContextMenu)
- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [self menuForEvent:event];
    if (menu.numberOfItems || menu.delegate) {
        [NSMenu popUpContextMenu:menu withEvent:event forView:self];
        return;
    }
    [self.nextResponder rightMouseDown:event];
}
@end
