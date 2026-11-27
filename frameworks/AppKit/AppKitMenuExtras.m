/* NSMenu and NSMenuItem state beyond the core: menu delegates (asked to
 * update a menu before it is shown), fonts and widths, item views, represented objects and subtitles. */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static id get(id o, const void *k) { return objc_getAssociatedObject(o, k); }
static void set(id o, const void *k, id v) { objc_setAssociatedObject(o, k, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void set_weak(id o, const void *k, id v) { objc_setAssociatedObject(o, k, v, OBJC_ASSOCIATION_ASSIGN); }

static const char k_delegate, k_min_width, k_font, k_selection_mode, k_view, k_represented, k_subtitle, k_highlighted;

@implementation NSMenu (BittenExtras)
- (id<NSMenuDelegate>)delegate { return get(self, &k_delegate); }
- (void)setDelegate:(id<NSMenuDelegate>)d { set_weak(self, &k_delegate, d); }
- (CGFloat)minimumWidth { return [get(self, &k_min_width) doubleValue]; }
- (void)setMinimumWidth:(CGFloat)w { set(self, &k_min_width, @(w)); }
- (NSFont *)font { return get(self, &k_font) ?: [NSFont menuFontOfSize:0]; }
- (void)setFont:(NSFont *)f { set(self, &k_font, f); }
- (NSMenuSelectionMode)selectionMode { return [get(self, &k_selection_mode) integerValue]; }
- (void)setSelectionMode:(NSMenuSelectionMode)m { set(self, &k_selection_mode, @(m)); }
- (CGFloat)menuBarHeight { return self == [NSApp mainMenu] ? 24 : 0; }
- (NSSize)size {
    CGFloat w = self.minimumWidth, h = 8;
    NSDictionary *attrs = @{NSFontAttributeName : self.font};
    for (NSMenuItem *i in self.itemArray) {
        if (i.isHidden) continue;
        h += i.isSeparatorItem ? 10 : 22;
        w = MAX(w, [i.title sizeWithAttributes:attrs].width + 60);
    }
    return NSMakeSize(w, h);
}
- (NSInteger)indexOfItemWithTitle:(NSString *)title {
    NSArray *items = self.itemArray;
    for (NSUInteger i = 0; i < items.count; i++)
        if ([[items[i] title] isEqualToString:title]) return (NSInteger)i;
    return -1;
}
/* Lets the delegate fill the menu, as AppKit does before showing it. */
- (void)_bn_prepareForDisplay {
    id<NSMenuDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(numberOfItemsInMenu:)] &&
        [d respondsToSelector:@selector(menu:updateItem:atIndex:shouldCancel:)]) {
        NSInteger n = [d numberOfItemsInMenu:self];
        while (self.numberOfItems < n) [self addItem:[[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""]];
        while (self.numberOfItems > n && n >= 0) [self removeItemAtIndex:self.numberOfItems - 1];
        for (NSInteger i = 0; i < n; i++)
            if (![d menu:self updateItem:[self itemAtIndex:i] atIndex:i shouldCancel:NO]) break;
    }
    if ([d respondsToSelector:@selector(menuNeedsUpdate:)]) [d menuNeedsUpdate:self];
    [self update];
}
/* Showing menus: AppKitMenuWindow.m. */
@end

@implementation NSMenuItem (BittenExtras)
- (NSView *)view { return get(self, &k_view); }
- (void)setView:(NSView *)v { set(self, &k_view, v); }
- (id)representedObject { return get(self, &k_represented); }
- (void)setRepresentedObject:(id)o { set(self, &k_represented, o); }
- (NSString *)subtitle { return get(self, &k_subtitle); }
- (void)setSubtitle:(NSString *)s { set(self, &k_subtitle, [s copy]); }
- (BOOL)isHighlighted { return [get(self, &k_highlighted) boolValue]; }
/* The item whose submenu holds this item. */
- (NSMenuItem *)parentItem {
    NSMenu *m = self.menu, *sup = m.supermenu;
    for (NSMenuItem *i in sup.itemArray)
        if (i.submenu == m) return i;
    return nil;
}
- (BOOL)isHiddenOrHasHiddenAncestor {
    if (self.isHidden) return YES;
    for (NSMenuItem *p = self.parentItem; p; p = p.parentItem)
        if (p.isHidden) return YES;
    return NO;
}
@end
