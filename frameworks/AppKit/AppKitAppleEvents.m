/* The core Apple events every Cocoa application handles, installed as it
 * finishes launching (before applicationWillFinishLaunching:, so apps can
 * replace them there): open, reopen, open documents, open URLs, quit and
 * show preferences, forwarded to the delegate as AppKit does. Also
 * NSWindow's occlusion state. */

#import <AppKit/AppKit.h>
#import <Foundation/NSAppleEvent.h>

@implementation NSApplication (BittenAppleEvents)
- (void)_bn_installCoreEventHandlers {
    NSAppleEventManager *m = [NSAppleEventManager sharedAppleEventManager];
    [m setEventHandler:self andSelector:@selector(_bn_handleOpenApplication:withReply:)
         forEventClass:kCoreEventClass andEventID:kAEOpenApplication];
    [m setEventHandler:self andSelector:@selector(_bn_handleReopenApplication:withReply:)
         forEventClass:kCoreEventClass andEventID:kAEReopenApplication];
    [m setEventHandler:self andSelector:@selector(_bn_handleOpenDocuments:withReply:)
         forEventClass:kCoreEventClass andEventID:kAEOpenDocuments];
    [m setEventHandler:self andSelector:@selector(_bn_handleQuit:withReply:)
         forEventClass:kCoreEventClass andEventID:kAEQuitApplication];
    [m setEventHandler:self andSelector:@selector(_bn_handleShowPreferences:withReply:)
         forEventClass:kCoreEventClass andEventID:kAEShowPreferences];
    [m setEventHandler:self andSelector:@selector(_bn_handleGetURL:withReply:)
         forEventClass:kInternetEventClass andEventID:kAEGetURL];
}
- (void)_bn_handleOpenApplication:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {}
- (void)_bn_handleReopenApplication:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    id d = self.delegate;
    BOOL visible = NO;
    for (NSWindow *w in self.windows)
        if (w.isVisible) visible = YES;
    if ([d respondsToSelector:@selector(applicationShouldHandleReopen:hasVisibleWindows:)] &&
        ![d applicationShouldHandleReopen:self hasVisibleWindows:visible])
        return;
    if (!visible)
        for (NSWindow *w in self.windows)
            if (w.isMiniaturized) {
                [w deminiaturize:nil];
                break;
            }
}
/* The URLs in an event's direct object: one descriptor or a list. */
static NSArray<NSURL *> *urls_in(NSAppleEventDescriptor *event, BOOL files) {
    NSAppleEventDescriptor *direct = [event paramDescriptorForKeyword:keyDirectObject];
    if (!direct) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSInteger n = direct.numberOfItems;
    NSArray *items = n > 0 ? nil : @[ direct ];
    if (!items) {
        NSMutableArray *a = [NSMutableArray array];
        for (NSInteger i = 1; i <= n; i++) {
            NSAppleEventDescriptor *d = [direct descriptorAtIndex:i];
            if (d) [a addObject:d];
        }
        items = a;
    }
    for (NSAppleEventDescriptor *d in items) {
        NSURL *u = files ? d.fileURLValue : nil;
        if (!u && d.stringValue) u = files ? [NSURL fileURLWithPath:d.stringValue] : [NSURL URLWithString:d.stringValue];
        if (u) [out addObject:u];
    }
    return out;
}
- (void)_bn_openURLs:(NSArray<NSURL *> *)urls {
    if (!urls.count) return;
    id d = self.delegate;
    if ([d respondsToSelector:@selector(application:openURLs:)]) {
        [d application:self openURLs:urls];
        return;
    }
    NSMutableArray *paths = [NSMutableArray array];
    for (NSURL *u in urls)
        if (u.isFileURL) [paths addObject:u.path];
    if (paths.count && [d respondsToSelector:@selector(application:openFiles:)]) [d application:self openFiles:paths];
    else if (paths.count && [d respondsToSelector:@selector(application:openFile:)])
        for (NSString *p in paths) [d application:self openFile:p];
}
- (void)_bn_handleOpenDocuments:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    [self _bn_openURLs:urls_in(event, YES)];
}
- (void)_bn_handleGetURL:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    [self _bn_openURLs:urls_in(event, NO)];
}
- (void)_bn_handleQuit:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    [self terminate:nil];
}
- (void)_bn_handleShowPreferences:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    [self sendAction:NSSelectorFromString(@"showSettingsWindow:") to:nil from:self] ||
        [self sendAction:NSSelectorFromString(@"showPreferencesWindow:") to:nil from:self];
}
@end

@implementation NSWindow (BittenOcclusion)
- (NSWindowOcclusionState)occlusionState { return self.isVisible ? NSWindowOcclusionStateVisible : 0; }
@end
