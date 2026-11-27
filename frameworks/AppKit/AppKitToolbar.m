/* Toolbars and their items, titlebar accessories, popovers, alerts and
 * the status bar. Toolbars build their items from the delegate the way
 * AppKit does; popovers and alerts are windows shown with the existing
 * child-window, sheet and modal machinery. */

#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <objc/runtime.h>
#import <objc/message.h>
#import <objc/runtime.h>

/* ---- NSToolbarItem ---- */

@implementation NSToolbarItem {
    NSToolbarItemIdentifier _identifier;
    NSString *_label, *_paletteLabel, *_toolTip, *_title;
    NSImage *_image;
    NSView *_view;
    __weak id _target;
    SEL _action;
    BOOL _enabled, _bordered, _navigational, _visible, _autovalidates;
    NSInteger _tag, _visibilityPriority;
    NSSize _minSize, _maxSize;
    NSMenuItem *_menuFormRepresentation;
    __weak NSToolbar *_toolbar;
    NSColor *_backgroundTintColor;
    NSToolbarItemStyle _style;
}
- (instancetype)initWithItemIdentifier:(NSToolbarItemIdentifier)identifier {
    self = [super init];
    _identifier = [identifier copy];
    _label = _paletteLabel = @"";
    _enabled = _visible = _autovalidates = YES;
    return self;
}
- (NSToolbarItemIdentifier)itemIdentifier { return _identifier; }
- (NSToolbar *)toolbar { return _toolbar; }
- (void)_bn_setToolbar:(NSToolbar *)t { _toolbar = t; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { _label = [l copy] ?: @""; }
- (NSString *)paletteLabel { return _paletteLabel.length ? _paletteLabel : _label; }
- (void)setPaletteLabel:(NSString *)l { _paletteLabel = [l copy] ?: @""; }
- (NSString *)title { return _title ?: @""; }
- (void)setTitle:(NSString *)t { _title = [t copy]; }
- (NSString *)toolTip { return _toolTip; }
- (void)setToolTip:(NSString *)t { _toolTip = [t copy]; }
- (NSImage *)image { return _image ?: ([_view respondsToSelector:@selector(image)] ? [(id)_view image] : nil); }
- (void)setImage:(NSImage *)i { _image = i; }
- (NSView *)view { return _view; }
- (void)setView:(NSView *)v { _view = v; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; }
- (void)setAction:(SEL)a { _action = a; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)e { _enabled = e; }
- (BOOL)isBordered { return _bordered; }
- (void)setBordered:(BOOL)b { _bordered = b; }
- (BOOL)isNavigational { return _navigational; }
- (void)setNavigational:(BOOL)b { _navigational = b; }
- (BOOL)isVisible { return _visible; }
- (void)setVisible:(BOOL)v { _visible = v; }
- (BOOL)isHidden { return !_visible; }
- (void)setHidden:(BOOL)h { _visible = !h; }
- (BOOL)autovalidates { return _autovalidates; }
- (void)setAutovalidates:(BOOL)b { _autovalidates = b; }
- (NSInteger)tag { return _tag; }
- (void)setTag:(NSInteger)t { _tag = t; }
- (NSToolbarItemVisibilityPriority)visibilityPriority { return _visibilityPriority; }
- (void)setVisibilityPriority:(NSToolbarItemVisibilityPriority)p { _visibilityPriority = p; }
- (NSSize)minSize { return _minSize; }
- (void)setMinSize:(NSSize)s { _minSize = s; }
- (NSSize)maxSize { return _maxSize; }
- (void)setMaxSize:(NSSize)s { _maxSize = s; }
- (NSMenuItem *)menuFormRepresentation { return _menuFormRepresentation; }
- (void)setMenuFormRepresentation:(NSMenuItem *)m { _menuFormRepresentation = m; }
- (NSColor *)backgroundTintColor { return _backgroundTintColor; }
- (void)setBackgroundTintColor:(NSColor *)c { _backgroundTintColor = c; }
- (NSToolbarItemStyle)style { return _style; }
- (void)setStyle:(NSToolbarItemStyle)s { _style = s; }
- (void)validate {
    id t = _target;
    if (t && [t respondsToSelector:@selector(validateToolbarItem:)]) self.enabled = [t validateToolbarItem:self];
}
/* Sends the action as a toolbar click does. */
- (void)_bn_perform {
    if (_enabled && _action) [NSApp sendAction:_action to:_target from:self];
}
- (id)copyWithZone:(NSZone *)zone {
    NSToolbarItem *c = [[[self class] alloc] initWithItemIdentifier:_identifier];
    c.label = _label;
    c.paletteLabel = _paletteLabel;
    c.toolTip = _toolTip;
    c.image = _image;
    c.target = _target;
    c.action = _action;
    c.tag = _tag;
    return c;
}
@end

@implementation NSToolbarItemGroup {
    NSArray<NSToolbarItem *> *_subitems;
    NSToolbarItemGroupSelectionMode _selectionMode;
    NSToolbarItemGroupControlRepresentation _controlRepresentation;
    NSMutableSet<NSNumber *> *_selected;
}
+ (instancetype)groupWithItemIdentifier:(NSToolbarItemIdentifier)identifier titles:(NSArray<NSString *> *)titles
                          selectionMode:(NSToolbarItemGroupSelectionMode)mode labels:(NSArray<NSString *> *)labels
                                 target:(id)target action:(SEL)action {
    NSToolbarItemGroup *g = [[self alloc] initWithItemIdentifier:identifier];
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSToolbarItem *it = [[NSToolbarItem alloc] initWithItemIdentifier:[NSString stringWithFormat:@"%@.%lu", identifier, (unsigned long)i]];
        it.title = titles[i];
        it.label = i < labels.count ? labels[i] : titles[i];
        [items addObject:it];
    }
    g.subitems = items;
    g.selectionMode = mode;
    g.target = target;
    g.action = action;
    return g;
}
+ (instancetype)groupWithItemIdentifier:(NSToolbarItemIdentifier)identifier images:(NSArray<NSImage *> *)images
                          selectionMode:(NSToolbarItemGroupSelectionMode)mode labels:(NSArray<NSString *> *)labels
                                 target:(id)target action:(SEL)action {
    NSToolbarItemGroup *g = [[self alloc] initWithItemIdentifier:identifier];
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < images.count; i++) {
        NSToolbarItem *it = [[NSToolbarItem alloc] initWithItemIdentifier:[NSString stringWithFormat:@"%@.%lu", identifier, (unsigned long)i]];
        it.image = images[i];
        if (i < labels.count) it.label = labels[i];
        [items addObject:it];
    }
    g.subitems = items;
    g.selectionMode = mode;
    g.target = target;
    g.action = action;
    return g;
}
- (NSArray<NSToolbarItem *> *)subitems { return _subitems ?: @[]; }
- (void)setSubitems:(NSArray<NSToolbarItem *> *)s { _subitems = [s copy]; }
- (NSToolbarItemGroupSelectionMode)selectionMode { return _selectionMode; }
- (void)setSelectionMode:(NSToolbarItemGroupSelectionMode)m { _selectionMode = m; }
- (NSToolbarItemGroupControlRepresentation)controlRepresentation { return _controlRepresentation; }
- (void)setControlRepresentation:(NSToolbarItemGroupControlRepresentation)r { _controlRepresentation = r; }
- (NSInteger)selectedIndex {
    NSInteger best = -1;
    for (NSNumber *n in _selected)
        if (best < 0 || n.integerValue < best) best = n.integerValue;
    return best;
}
- (void)setSelectedIndex:(NSInteger)i {
    _selected = [NSMutableSet set];
    if (i >= 0) [_selected addObject:@(i)];
}
- (void)setSelected:(BOOL)sel atIndex:(NSInteger)i {
    if (!_selected) _selected = [NSMutableSet set];
    if (_selectionMode != NSToolbarItemGroupSelectionModeSelectAny) [_selected removeAllObjects];
    if (sel) [_selected addObject:@(i)];
    else [_selected removeObject:@(i)];
}
- (BOOL)isSelectedAtIndex:(NSInteger)i { return [_selected containsObject:@(i)]; }
@end

@implementation NSMenuToolbarItem {
    NSMenu *_menu;
    BOOL _showsIndicator;
}
- (instancetype)initWithItemIdentifier:(NSToolbarItemIdentifier)identifier {
    self = [super initWithItemIdentifier:identifier];
    _showsIndicator = YES;
    _menu = [[NSMenu alloc] initWithTitle:@""];
    return self;
}
- (NSMenu *)menu { return _menu; }
- (void)setMenu:(NSMenu *)m { _menu = m; }
- (BOOL)showsIndicator { return _showsIndicator; }
- (void)setShowsIndicator:(BOOL)b { _showsIndicator = b; }
@end

/* ---- NSToolbar ---- */

@implementation NSToolbar {
    NSToolbarIdentifier _identifier;
    __weak id<NSToolbarDelegate> _delegate;
    NSMutableArray<NSToolbarItem *> *_items;
    BOOL _visible, _allowsCustomization, _autosaves, _showsBaselineSeparator, _built, _allowsExtensionItems;
    NSToolbarDisplayMode _displayMode;
    NSToolbarItemIdentifier _selected;
    NSSet<NSToolbarItemIdentifier> *_centered;
}
- (instancetype)initWithIdentifier:(NSToolbarIdentifier)identifier {
    self = [super init];
    _identifier = [identifier copy];
    _items = [NSMutableArray array];
    _visible = YES;
    _showsBaselineSeparator = YES;
    return self;
}
- (instancetype)init { return [self initWithIdentifier:@""]; }
- (NSToolbarIdentifier)identifier { return _identifier; }
- (id<NSToolbarDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSToolbarDelegate>)d {
    _delegate = d;
    _built = NO;
    [self _bn_build];
}
static BOOL standard_identifier(NSString *i) {
    return [i isEqualToString:NSToolbarFlexibleSpaceItemIdentifier] || [i isEqualToString:NSToolbarSpaceItemIdentifier] ||
           [i hasPrefix:@"NSToolbar"];
}
- (NSToolbarItem *)_bn_make:(NSToolbarItemIdentifier)ident inserting:(BOOL)inserting {
    id<NSToolbarDelegate> d = _delegate;
    NSToolbarItem *item = nil;
    if (!standard_identifier(ident) &&
        [d respondsToSelector:@selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:)])
        item = [d toolbar:self itemForItemIdentifier:ident willBeInsertedIntoToolbar:inserting];
    if (!item) item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    [item _bn_setToolbar:self];
    return item;
}
/* The default items, made once the delegate is set. */
- (void)_bn_build {
    if (_built) return;
    id<NSToolbarDelegate> d = _delegate;
    if (![d respondsToSelector:@selector(toolbarDefaultItemIdentifiers:)]) return;
    _built = YES;
    [_items removeAllObjects];
    for (NSToolbarItemIdentifier ident in [d toolbarDefaultItemIdentifiers:self]) {
        NSToolbarItem *item = [self _bn_make:ident inserting:YES];
        if (getenv("BITTEN_TOOLBAR_DEBUG"))
            fprintf(stderr, "bitten: toolbar '%s' item '%s' label '%s' view %s\n", _identifier.UTF8String ?: "",
                    ident.UTF8String ?: "", item.label.UTF8String ?: "",
                    item.view ? object_getClassName(item.view) : "-");
        [_items addObject:item];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSToolbarWillAddItemNotification
                                                            object:self
                                                          userInfo:@{@"item" : item}];
    }
}
- (NSArray<NSToolbarItem *> *)items {
    [self _bn_build];
    return [_items copy];
}
- (NSArray<NSToolbarItem *> *)visibleItems {
    NSMutableArray *v = [NSMutableArray array];
    for (NSToolbarItem *i in self.items)
        if (i.isVisible) [v addObject:i];
    return v;
}
- (void)insertItemWithItemIdentifier:(NSToolbarItemIdentifier)ident atIndex:(NSInteger)index {
    [self _bn_build];
    NSToolbarItem *item = [self _bn_make:ident inserting:YES];
    [_items insertObject:item atIndex:MIN((NSUInteger)MAX(index, 0), _items.count)];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSToolbarWillAddItemNotification object:self
                                                      userInfo:@{@"item" : item}];
}
- (void)removeItemAtIndex:(NSInteger)index {
    [self _bn_build];
    if (index < 0 || index >= (NSInteger)_items.count) return;
    NSToolbarItem *item = _items[index];
    [_items removeObjectAtIndex:index];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSToolbarDidRemoveItemNotification object:self
                                                      userInfo:@{@"item" : item}];
}
- (void)removeItemWithItemIdentifier:(NSToolbarItemIdentifier)ident {
    for (NSInteger i = (NSInteger)_items.count - 1; i >= 0; i--)
        if ([_items[i].itemIdentifier isEqualToString:ident]) [self removeItemAtIndex:i];
}
- (BOOL)isVisible { return _visible; }
- (void)setVisible:(BOOL)v { _visible = v; }
- (NSToolbarDisplayMode)displayMode { return _displayMode; }
- (void)setDisplayMode:(NSToolbarDisplayMode)m { _displayMode = m; }
- (BOOL)allowsUserCustomization { return _allowsCustomization; }
- (void)setAllowsUserCustomization:(BOOL)b { _allowsCustomization = b; }
- (BOOL)allowsExtensionItems { return _allowsExtensionItems; }
- (void)setAllowsExtensionItems:(BOOL)b { _allowsExtensionItems = b; }
- (BOOL)autosavesConfiguration { return _autosaves; }
- (void)setAutosavesConfiguration:(BOOL)b { _autosaves = b; }
- (BOOL)showsBaselineSeparator { return _showsBaselineSeparator; }
- (void)setShowsBaselineSeparator:(BOOL)b { _showsBaselineSeparator = b; }
- (NSToolbarItemIdentifier)selectedItemIdentifier { return _selected; }
- (void)setSelectedItemIdentifier:(NSToolbarItemIdentifier)i { _selected = [i copy]; }
- (NSSet<NSToolbarItemIdentifier> *)centeredItemIdentifiers { return _centered ?: [NSSet set]; }
- (void)setCenteredItemIdentifiers:(NSSet<NSToolbarItemIdentifier> *)s { _centered = [s copy]; }
- (NSToolbarItemIdentifier)centeredItemIdentifier { return _centered.anyObject; }
- (void)setCenteredItemIdentifier:(NSToolbarItemIdentifier)i { _centered = i ? [NSSet setWithObject:i] : nil; }
- (void)validateVisibleItems {
    for (NSToolbarItem *i in self.visibleItems)
        if (i.autovalidates) [i validate];
}
- (void)runCustomizationPalette:(id)sender {}
- (BOOL)customizationPaletteIsRunning { return NO; }
@end

/* ---- titlebar accessories ---- */

@implementation NSTitlebarAccessoryViewController {
    NSLayoutAttribute _layoutAttribute;
    CGFloat _fullScreenMinHeight;
    BOOL _hidden, _automaticallyAdjustsSize;
}
- (instancetype)initWithNibName:(NSString *)nib bundle:(NSBundle *)bundle {
    self = [super initWithNibName:nib bundle:bundle];
    _layoutAttribute = NSLayoutAttributeBottom;
    _automaticallyAdjustsSize = YES;
    return self;
}
- (NSLayoutAttribute)layoutAttribute { return _layoutAttribute; }
- (void)setLayoutAttribute:(NSLayoutAttribute)a { _layoutAttribute = a; }
- (CGFloat)fullScreenMinHeight { return _fullScreenMinHeight; }
- (void)setFullScreenMinHeight:(CGFloat)h { _fullScreenMinHeight = h; }
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)h { _hidden = h; }
- (BOOL)automaticallyAdjustsSize { return _automaticallyAdjustsSize; }
- (void)setAutomaticallyAdjustsSize:(BOOL)b { _automaticallyAdjustsSize = b; }
@end

/* ---- NSPopover: a borderless child window beside its anchor ---- */

@implementation NSPopover {
    NSViewController *_contentViewController;
    NSSize _contentSize;
    NSPopoverBehavior _behavior;
    BOOL _animates, _shown, _hidesDetachedWindowOnDeactivate;
    NSAppearance *_appearance;
    NSWindow *_window;
    __weak id<NSPopoverDelegate> _delegate;
    NSRect _positioningRect;
    __weak NSView *_anchorView;
    NSRectEdge _edge;
    BOOL _placing;
}
- (instancetype)init {
    self = [super init];
    _animates = YES;
    return self;
}
- (NSViewController *)contentViewController { return _contentViewController; }
- (void)setContentViewController:(NSViewController *)vc { _contentViewController = vc; }
- (NSSize)contentSize {
    if (_contentSize.width > 0 || _contentSize.height > 0) return _contentSize;
    NSSize p = _contentViewController.preferredContentSize;
    return p.width > 0 ? p : _contentViewController.view.frame.size;
}
- (void)setContentSize:(NSSize)s {
    _contentSize = s;
    if (_window) {
        NSRect f = _window.frame;
        f.size = s;
        [_window setFrame:[self _bn_frameForSize:s] display:YES];
    }
}
/* Where the popover goes for a size: beside its anchor on the chosen edge,
 * centred along it, kept on the screen. */
- (NSRect)_bn_frameForSize:(NSSize)size {
    NSView *view = _anchorView;
    NSWindow *parent = view.window;
    if (!parent) return _window ? (NSRect){_window.frame.origin, size} : (NSRect){NSZeroPoint, size};
    NSRect rect = _positioningRect;
    NSRect anchor = [parent convertRectToScreen:[view convertRect:NSIsEmptyRect(rect) ? view.bounds : rect toView:nil]];
    NSPoint o;
    switch (_edge) {
    case NSRectEdgeMinX: o = NSMakePoint(NSMinX(anchor) - size.width, NSMidY(anchor) - size.height / 2); break;
    case NSRectEdgeMaxX: o = NSMakePoint(NSMaxX(anchor), NSMidY(anchor) - size.height / 2); break;
    case NSRectEdgeMaxY: o = NSMakePoint(NSMidX(anchor) - size.width / 2, NSMaxY(anchor)); break;
    default: o = NSMakePoint(NSMidX(anchor) - size.width / 2, NSMinY(anchor) - size.height); break;
    }
    NSRect screen = [NSScreen mainScreen].visibleFrame;
    o.x = MAX(NSMinX(screen), MIN(o.x, NSMaxX(screen) - size.width));
    o.y = MAX(NSMinY(screen), MIN(o.y, NSMaxY(screen) - size.height));
    return (NSRect){o, size};
}
/* The content changed the popover window's size: back beside the anchor. */
- (void)_bn_windowResized:(NSNotification *)n {
    if (_placing || !_shown) return;
    _placing = YES;
    NSRect f = [self _bn_frameForSize:_window.frame.size];
    if (!NSEqualPoints(f.origin, _window.frame.origin)) [_window setFrameOrigin:f.origin];
    _placing = NO;
}
- (NSPopoverBehavior)behavior { return _behavior; }
- (void)setBehavior:(NSPopoverBehavior)b { _behavior = b; }
- (BOOL)animates { return _animates; }
- (void)setAnimates:(BOOL)b { _animates = b; }
- (NSAppearance *)appearance { return _appearance; }
- (void)setAppearance:(NSAppearance *)a { _appearance = a; }
- (NSAppearance *)effectiveAppearance { return _appearance ?: [NSApp effectiveAppearance]; }
- (id<NSPopoverDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSPopoverDelegate>)d { _delegate = d; }
- (BOOL)isShown { return _shown; }
- (BOOL)isDetached { return NO; }
- (NSRect)positioningRect { return _positioningRect; }
- (void)setPositioningRect:(NSRect)r { _positioningRect = r; }
- (BOOL)hidesDetachedWindowOnDeactivate { return _hidesDetachedWindowOnDeactivate; }
- (void)setHidesDetachedWindowOnDeactivate:(BOOL)b { _hidesDetachedWindowOnDeactivate = b; }
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    NSWindow *parent = view.window;
    if (!parent || !_contentViewController) return;
    id<NSPopoverDelegate> d = _delegate;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSPopoverWillShowNotification object:self];
    _positioningRect = rect;
    _anchorView = view;
    _edge = edge;
    NSSize size = self.contentSize;
    NSPoint o = [self _bn_frameForSize:size].origin;
    if (!_window) {
        _window = [[NSPanel alloc] initWithContentRect:NSMakeRect(o.x, o.y, size.width, size.height)
                                             styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
        _window.releasedWhenClosed = NO;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_bn_windowResized:)
                                                     name:NSWindowDidResizeNotification object:_window];
    } else {
        [_window setFrame:NSMakeRect(o.x, o.y, size.width, size.height) display:NO];
    }
    _window.appearance = self.effectiveAppearance;
    _window.contentViewController = _contentViewController;
    [parent addChildWindow:_window ordered:NSWindowAbove];
    [_window makeKeyAndOrderFront:nil];
    _shown = YES;
    if ([d respondsToSelector:@selector(popoverDidShow:)])
        [d popoverDidShow:[NSNotification notificationWithName:NSPopoverDidShowNotification object:self]];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSPopoverDidShowNotification object:self];
}
- (void)close {
    if (!_shown) return;
    id<NSPopoverDelegate> d = _delegate;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSPopoverWillCloseNotification object:self];
    [_window.parentWindow removeChildWindow:_window];
    [_window orderOut:nil];
    _shown = NO;
    if ([d respondsToSelector:@selector(popoverDidClose:)])
        [d popoverDidClose:[NSNotification notificationWithName:NSPopoverDidCloseNotification object:self]];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSPopoverDidCloseNotification object:self];
}
- (void)performClose:(id)sender {
    id<NSPopoverDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(popoverShouldClose:)] && ![d popoverShouldClose:self]) return;
    [self close];
}
@end

/* ---- NSAlert: a panel with a message, details and buttons ---- */

@interface BNAlertContent : NSView
@end
@implementation BNAlertContent
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(self.bounds);
}
@end

@implementation NSAlert {
    NSString *_messageText, *_informativeText;
    NSAlertStyle _style;
    NSImage *_icon;
    NSMutableArray<NSButton *> *_buttons;
    NSView *_accessoryView;
    BOOL _showsSuppressionButton, _showsHelp;
    NSButton *_suppressionButton;
    NSPanel *_window;
    __weak id<NSAlertDelegate> _delegate;
    NSString *_helpAnchor;
}
+ (NSAlert *)alertWithError:(NSError *)error {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = error.localizedDescription ?: @"";
    a.informativeText = error.userInfo[NSLocalizedRecoverySuggestionErrorKey] ?: (error.userInfo[NSLocalizedFailureReasonErrorKey] ?: @"");
    a.alertStyle = NSAlertStyleWarning;
    return a;
}
- (instancetype)init {
    self = [super init];
    _messageText = @"Alert";
    _informativeText = @"";
    _buttons = [NSMutableArray array];
    return self;
}
- (NSString *)messageText { return _messageText; }
- (void)setMessageText:(NSString *)t { _messageText = [t copy] ?: @""; }
- (NSString *)informativeText { return _informativeText; }
- (void)setInformativeText:(NSString *)t { _informativeText = [t copy] ?: @""; }
- (NSAlertStyle)alertStyle { return _style; }
- (void)setAlertStyle:(NSAlertStyle)s { _style = s; }
- (NSImage *)icon { return _icon; }
- (void)setIcon:(NSImage *)i { _icon = i; }
- (NSArray<NSButton *> *)buttons { return [_buttons copy]; }
- (NSView *)accessoryView { return _accessoryView; }
- (void)setAccessoryView:(NSView *)v { _accessoryView = v; }
- (BOOL)showsSuppressionButton { return _showsSuppressionButton; }
- (void)setShowsSuppressionButton:(BOOL)b { _showsSuppressionButton = b; }
- (NSButton *)suppressionButton {
    if (!_suppressionButton) _suppressionButton = [NSButton checkboxWithTitle:@"Do not show this message again" target:nil action:nil];
    return _suppressionButton;
}
- (BOOL)showsHelp { return _showsHelp; }
- (void)setShowsHelp:(BOOL)b { _showsHelp = b; }
- (NSString *)helpAnchor { return _helpAnchor; }
- (void)setHelpAnchor:(NSString *)h { _helpAnchor = [h copy]; }
- (id<NSAlertDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSAlertDelegate>)d { _delegate = d; }
- (NSWindow *)window {
    [self layout];
    return _window;
}
- (NSButton *)addButtonWithTitle:(NSString *)title {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:@selector(_bn_buttonPressed:)];
    b.tag = NSAlertFirstButtonReturn + (NSInteger)_buttons.count;
    if (_buttons.count == 0) b.keyEquivalent = @"\r";
    else if ([title isEqualToString:@"Cancel"]) b.keyEquivalent = @"\033";
    [_buttons addObject:b];
    return b;
}
- (void)_bn_buttonPressed:(NSButton *)sender {
    NSWindow *parent = _window.sheetParent;
    if (parent) [parent endSheet:_window returnCode:sender.tag];
    else if ([NSApp modalWindow] == _window) [NSApp stopModalWithCode:sender.tag];
    [_window orderOut:nil];
}
/* Lays out icon, texts, accessory and buttons (right to left) in a panel. */
- (void)layout {
    if (!_buttons.count) [self addButtonWithTitle:@"OK"];
    CGFloat w = 420, pad = 20, y = pad;
    if (!_window) {
        _window = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, w, 160)
                                             styleMask:NSWindowStyleMaskTitled
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
        _window.releasedWhenClosed = NO;
    }
    BNAlertContent *content = [[BNAlertContent alloc] initWithFrame:NSMakeRect(0, 0, w, 160)];
    NSTextField *msg = [NSTextField wrappingLabelWithString:_messageText];
    msg.font = [NSFont boldSystemFontOfSize:13];
    msg.preferredMaxLayoutWidth = w - 2 * pad;
    NSSize ms = msg.intrinsicContentSize;
    msg.frame = NSMakeRect(pad, y, w - 2 * pad, ms.height);
    [content addSubview:msg];
    y += ms.height + 8;
    if (_informativeText.length) {
        NSTextField *info = [NSTextField wrappingLabelWithString:_informativeText];
        info.font = [NSFont systemFontOfSize:11];
        info.preferredMaxLayoutWidth = w - 2 * pad;
        NSSize is = info.intrinsicContentSize;
        info.frame = NSMakeRect(pad, y, w - 2 * pad, is.height);
        [content addSubview:info];
        y += is.height + 8;
    }
    if (_accessoryView) {
        NSRect f = _accessoryView.frame;
        f.origin = NSMakePoint(pad, y);
        _accessoryView.frame = f;
        [content addSubview:_accessoryView];
        y += f.size.height + 8;
    }
    if (_showsSuppressionButton) {
        NSButton *s = self.suppressionButton;
        NSSize ss = s.intrinsicContentSize;
        s.frame = NSMakeRect(pad, y, ss.width, ss.height);
        [content addSubview:s];
        y += ss.height + 8;
    }
    y += 4;
    CGFloat x = w - pad, bh = 22;
    for (NSButton *b in _buttons) {
        NSSize bs = b.intrinsicContentSize;
        CGFloat bw = MAX(bs.width, 72);
        x -= bw;
        b.frame = NSMakeRect(x, y, bw, bh);
        [content addSubview:b];
        x -= 8;
    }
    y += bh + pad;
    content.frame = NSMakeRect(0, 0, w, y);
    NSRect f = _window.frame;
    f.size = NSMakeSize(w, y + 28);
    [_window setFrame:f display:NO];
    _window.contentView = content;
}
- (NSModalResponse)runModal {
    [self layout];
    [_window center];
    return [NSApp runModalForWindow:_window];
}
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler {
    [self layout];
    if (!window) {
        NSModalResponse r = [self runModal];
        if (handler) handler(r);
        return;
    }
    [window beginSheet:_window completionHandler:handler];
}
@end

/* ---- the status bar ---- */

@implementation NSStatusBarButton
@end

@implementation NSStatusItem {
    __weak NSStatusBar *_statusBar;
    CGFloat _length;
    NSStatusBarButton *_button;
    NSMenu *_menu;
    BOOL _visible;
    NSStatusItemBehavior _behavior;
    NSString *_autosaveName;
}
- (instancetype)initWithBNStatusBar:(NSStatusBar *)bar length:(CGFloat)length {
    self = [super init];
    _statusBar = bar;
    _length = length;
    _visible = YES;
    _button = [[NSStatusBarButton alloc] initWithFrame:NSMakeRect(0, 0, length > 0 ? length : 24, 22)];
    _button.bordered = NO;
    _button.title = @"";
    return self;
}
- (NSStatusBar *)statusBar { return _statusBar; }
- (CGFloat)length { return _length; }
- (void)setLength:(CGFloat)l { _length = l; }
- (NSStatusBarButton *)button { return _button; }
- (NSMenu *)menu { return _menu; }
- (void)setMenu:(NSMenu *)m { _menu = m; }
- (BOOL)isVisible { return _visible; }
- (void)setVisible:(BOOL)v { _visible = v; }
- (NSStatusItemBehavior)behavior { return _behavior; }
- (void)setBehavior:(NSStatusItemBehavior)b { _behavior = b; }
- (NSStatusItemAutosaveName)autosaveName { return _autosaveName; }
- (void)setAutosaveName:(NSStatusItemAutosaveName)n { _autosaveName = [n copy]; }
@end

@implementation NSStatusBar {
    NSMutableArray<NSStatusItem *> *_items;
}
+ (NSStatusBar *)systemStatusBar {
    static NSStatusBar *bar;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bar = [[NSStatusBar alloc] init];
        bar->_items = [NSMutableArray array];
    });
    return bar;
}
- (NSStatusItem *)statusItemWithLength:(CGFloat)length {
    NSStatusItem *i = [[NSStatusItem alloc] initWithBNStatusBar:self length:length];
    [_items addObject:i];
    return i;
}
- (void)removeStatusItem:(NSStatusItem *)item { [_items removeObjectIdenticalTo:item]; }
- (BOOL)isVertical { return NO; }
- (CGFloat)thickness { return 22; }
@end

/* ---- the toolbar band: a toolbar's items drawn above a window's content ---- */

/* Lays a window's toolbar items out in a row: those before the sidebar
 * tracking separator after the title bar's buttons, those after it from the
 * window's split view divider; flexible spaces share what is left. Items
 * without a view get buttons (a group, one per subitem). */
@interface BNToolbarView : NSView
@property (weak) NSWindow *owner;
@end
@implementation BNToolbarView {
    NSArray<NSToolbarItem *> *_shown;
    NSMutableArray<NSView *> *_views;   /* per item: its view, or NSNull for spaces */
}
- (BOOL)isFlipped { return YES; }
static NSString *const kSidebarTracking = @"NSToolbarSidebarTrackingSeparatorItemIdentifier";
static BOOL is_space(NSToolbarItem *i) {
    NSString *s = i.itemIdentifier;
    return [s isEqualToString:NSToolbarFlexibleSpaceItemIdentifier] || [s isEqualToString:NSToolbarSpaceItemIdentifier] ||
           [s isEqualToString:kSidebarTracking] || [s hasPrefix:@"NSToolbar"];
}
- (NSButton *)_bn_buttonFor:(NSToolbarItem *)item tag:(NSInteger)tag {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 28, 24)];
    b.bordered = NO;
    if (item.image) {
        b.image = item.image;
        b.title = @"";
    } else {
        b.title = item.title.length ? item.title : item.label;
    }
    b.target = self;
    b.action = @selector(_bn_clicked:);
    b.tag = tag;
    b.toolTip = item.toolTip ?: item.label;
    [b sizeToFit];
    NSRect f = b.frame;
    f.size = NSMakeSize(MAX(f.size.width, 28), 24);
    b.frame = f;
    return b;
}
- (void)_bn_rebuild {
    NSArray<NSToolbarItem *> *items = self.owner.toolbar.visibleItems ?: @[];
    if ([items isEqualToArray:_shown ?: @[]] && _views) return;
    for (NSView *v in [self.subviews copy]) [v removeFromSuperview];
    _shown = items;
    _views = [NSMutableArray array];
    for (NSToolbarItem *item in items) {
        if (is_space(item)) {
            [_views addObject:(id)[NSNull null]];
            continue;
        }
        NSView *v = item.view;
        if (!v && [item isKindOfClass:[NSToolbarItemGroup class]]) {
            NSArray<NSToolbarItem *> *subs = ((NSToolbarItemGroup *)item).subitems;
            NSView *box = [[NSView alloc] initWithFrame:NSZeroRect];
            CGFloat x = 0;
            for (NSUInteger i = 0; i < subs.count; i++) {
                NSButton *b = [self _bn_buttonFor:subs[i] tag:(NSInteger)([_views count] << 8 | i)];
                b.frame = NSMakeRect(x, 0, b.frame.size.width, 24);
                [box addSubview:b];
                x += b.frame.size.width;
            }
            box.frame = NSMakeRect(0, 0, x, 24);
            v = box;
        } else if (!v) {
            v = [self _bn_buttonFor:item tag:(NSInteger)([_views count] << 8 | 0xFF)];
        }
        [self addSubview:v];
        [_views addObject:v];
    }
}
- (void)_bn_clicked:(NSButton *)sender {
    NSUInteger index = (NSUInteger)sender.tag >> 8, sub = (NSUInteger)sender.tag & 0xFF;
    if (index >= _shown.count) return;
    NSToolbarItem *item = _shown[index];
    if ([item isKindOfClass:[NSToolbarItemGroup class]] && sub != 0xFF) {
        NSToolbarItemGroup *g = (NSToolbarItemGroup *)item;
        NSToolbarItem *s = sub < g.subitems.count ? g.subitems[sub] : nil;
        g.selectedIndex = (NSInteger)sub;
        /* A subitem with its own action sends that; else the group's does. */
        if (s.action) [NSApp sendAction:s.action to:s.target from:s];
        else if (g.action) [NSApp sendAction:g.action to:g.target from:g];
        return;
    }
    [item _bn_perform];
}
/* Where the window's (first) split view divides its first pane from the
 * rest, in this view's coordinates; 0 without one. */
static NSSplitView *find_split(NSView *v, int depth) {
    if ([v isKindOfClass:[NSSplitView class]]) return (NSSplitView *)v;
    if (depth > 6) return nil;
    for (NSView *s in v.subviews) {
        NSSplitView *f = find_split(s, depth + 1);
        if (f) return f;
    }
    return nil;
}
- (CGFloat)_bn_dividerX {
    NSSplitView *split = find_split(self.owner.contentView, 0);
    NSView *first = split.arrangedSubviews.firstObject ?: split.subviews.firstObject;
    if (!first || first.isHidden) return 0;
    return NSMaxX([first convertRect:first.bounds toView:nil]);
}
- (void)layout {
    [self _bn_rebuild];
    CGFloat h = self.bounds.size.height, gap = 8;
    /* Widths first, then flexible spaces share the rest. */
    NSUInteger n = _shown.count, flex = 0;
    CGFloat x = 78, fixed = 0;
    CGFloat *widths = calloc(n ? n : 1, sizeof(CGFloat));
    for (NSUInteger i = 0; i < n; i++) {
        NSToolbarItem *item = _shown[i];
        id v = _views[i];
        if ([item.itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) flex++;
        else if ([item.itemIdentifier isEqualToString:NSToolbarSpaceItemIdentifier]) widths[i] = gap;
        else if (v != [NSNull null]) {
            NSView *view = v;
            NSSize s = view.fittingSize;
            if (s.width <= 0) s = view.frame.size;
            if (item.minSize.width > s.width) s.width = item.minSize.width;
            widths[i] = s.width;
            fixed += s.width + gap;
        }
    }
    CGFloat divider = [self _bn_dividerX];
    /* Room left for flexible spaces (measured from where the row starts). */
    CGFloat start = x;
    for (NSUInteger i = 0; i < n; i++)
        if ([_shown[i].itemIdentifier isEqualToString:kSidebarTracking] && divider > start) start = divider + gap;
    CGFloat share = flex ? MAX(0, (self.bounds.size.width - gap - start - fixed) / flex) : 0;
    for (NSUInteger i = 0; i < n; i++) {
        NSToolbarItem *item = _shown[i];
        NSString *ident = item.itemIdentifier;
        if ([ident isEqualToString:kSidebarTracking]) {
            if (divider > 0) x = MAX(x, divider + gap);
            continue;
        }
        if ([ident isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) {
            x += share;
            continue;
        }
        id v = _views[i];
        if (v == [NSNull null]) {
            x += widths[i];
            continue;
        }
        NSView *view = v;
        NSSize s = view.fittingSize;
        if (s.height <= 0) s.height = view.frame.size.height;
        s.height = MIN(MAX(s.height, 16), h - 4);
        view.frame = NSMakeRect(x, floor((h - s.height) / 2), widths[i], s.height);
        /* Items validate as AppKit's toolbar does before showing them. */
        if (item.autovalidates || item.target) [item validate];
        if ([view isKindOfClass:[NSButton class]]) ((NSButton *)view).enabled = item.isEnabled;
        if ([item isKindOfClass:[NSToolbarItemGroup class]] && !item.view) {
            NSArray<NSToolbarItem *> *subs = ((NSToolbarItemGroup *)item).subitems;
            for (NSButton *b in view.subviews)
                if ((NSUInteger)(b.tag & 0xFF) < subs.count) b.enabled = subs[(NSUInteger)(b.tag & 0xFF)].isEnabled;
        }
        x += widths[i] + gap;
    }
    free(widths);
    [super layout];
}
- (void)drawRect:(NSRect)dirty {
    /* (the window draws what is behind the strip) */
}
@end

@interface NSView (BittenToolbarWindow)
- (void)_setWindow:(NSWindow *)window;
@end

@implementation NSWindow (BittenToolbarStrip)
static const char kToolbarViewKey;
/* A full-size-content window's toolbar items, drawn in its title bar's
 * strip over the content (as macOS's unified title bar shows them beside
 * the window's buttons); nil when there are none to show. */
- (NSView *)_bn_toolbarView {
    NSWindowStyleMask m = self.styleMask;
    NSToolbar *t = self.toolbar;
    if (!(m & NSWindowStyleMaskTitled) || !(m & NSWindowStyleMaskFullSizeContentView) || !t.isVisible ||
        !t.visibleItems.count)
        return nil;
    BNToolbarView *v = objc_getAssociatedObject(self, &kToolbarViewKey);
    if (!v) {
        v = [[BNToolbarView alloc] initWithFrame:NSZeroRect];
        v.owner = self;
        objc_setAssociatedObject(self, &kToolbarViewKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [v _setWindow:self];
    }
    NSRect content = [self contentRectForFrameRect:self.frame];
    NSRect f = NSMakeRect(0, content.size.height - 28, content.size.width, 28);
    if (!NSEqualRects(v.frame, f)) v.frame = f;
    [v layout];
    return v;
}
@end
