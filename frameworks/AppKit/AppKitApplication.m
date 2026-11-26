/* The rest of NSApplication: hiding, the about panel (written to stderr:
 * there is no panel to show), modal sessions run on the main run loop,
 * presentation options and the application's menus and icon. */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

static const char app_props;
static NSMutableDictionary *props(NSApplication *a) {
    NSMutableDictionary *d = objc_getAssociatedObject(a, &app_props);
    if (!d) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(a, &app_props, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return d;
}
#define OBJ_PROP(type, getter, setter, key)                       \
    -(type)getter { return props(self)[@key]; }                   \
    -(void)setter:(type)v {                                       \
        if (v) props(self)[@key] = v;                             \
        else [props(self) removeObjectForKey:@key];               \
    }

static NSWindow *modal_window;
static NSModalResponse modal_response;
static BOOL modal_running;

@implementation NSApplication (BittenApplicationState)
- (NSApplicationActivationPolicy)activationPolicy {
    NSNumber *n = props(self)[@"policy"];
    return n ? (NSApplicationActivationPolicy)n.integerValue : NSApplicationActivationPolicyRegular;
}
- (void)setActivationPolicyAndActivate:(NSApplicationActivationPolicy)policy {
    [self setActivationPolicy:policy];
    props(self)[@"policy"] = @(policy);
    [self activate];
}
- (BOOL)isHidden { return [props(self)[@"hidden"] boolValue]; }
- (void)hide:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationWillHideNotification object:self];
    props(self)[@"hidden"] = @YES;
    for (NSWindow *w in self.windows)
        if (w.isVisible) {
            [w orderOut:nil];
            props(self)[[NSString stringWithFormat:@"hid%ld", (long)w.windowNumber]] = @YES;
        }
    [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationDidHideNotification object:self];
}
- (void)unhideWithoutActivation {
    if (!self.isHidden) return;
    props(self)[@"hidden"] = @NO;
    for (NSWindow *w in self.windows) {
        NSString *k = [NSString stringWithFormat:@"hid%ld", (long)w.windowNumber];
        if ([props(self)[k] boolValue]) [w orderFront:nil];
        [props(self) removeObjectForKey:k];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationDidUnhideNotification object:self];
}
- (void)unhide:(id)sender {
    [self unhideWithoutActivation];
    [self activate];
}
- (void)hideOtherApplications:(id)sender {}
- (void)unhideAllApplications:(id)sender { [self unhide:sender]; }
- (void)deactivate {}
- (void)yieldActivationToApplication:(id)application {}
- (void)orderFrontStandardAboutPanelWithOptions:(NSDictionary *)options {
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NSString *name = options[@"ApplicationName"] ?: info[@"CFBundleName"] ?: [NSProcessInfo processInfo].processName;
    NSString *version = options[@"ApplicationVersion"] ?: info[@"CFBundleShortVersionString"] ?: @"";
    fprintf(stderr, "bitten: about %s %s\n", name.UTF8String, version.UTF8String);
}
- (void)orderFrontStandardAboutPanel:(id)sender { [self orderFrontStandardAboutPanelWithOptions:@{}]; }
- (void)orderFrontCharacterPalette:(id)sender {}
OBJ_PROP(NSImage *, applicationIconImage, setApplicationIconImage, "icon")
OBJ_PROP(NSMenu *, windowsMenu, setWindowsMenu, "windowsMenu")
OBJ_PROP(NSMenu *, servicesMenu, setServicesMenu, "servicesMenu")
OBJ_PROP(NSMenu *, helpMenu, setHelpMenu, "helpMenu")
- (NSEvent *)currentEvent { return props(self)[@"currentEvent"]; }
- (void)postEvent:(NSEvent *)event atStart:(BOOL)flag {
    dispatch_async(dispatch_get_main_queue(), ^{ [self sendEvent:event]; });
}
- (void)discardEventsMatchingMask:(NSEventMask)mask beforeEvent:(NSEvent *)lastEvent {}
- (NSInteger)requestUserAttention:(NSRequestUserAttentionType)type { return 0; }
- (void)cancelUserAttentionRequest:(NSInteger)request {}

/* A modal session: the window shown and the main run loop run until
 * stopModal (or a stop code) ends it. */
- (NSModalResponse)runModalForWindow:(NSWindow *)window {
    NSWindow *saved = modal_window;
    BOOL wasRunning = modal_running;
    modal_window = window;
    modal_running = YES;
    modal_response = NSModalResponseContinue;
    [window makeKeyAndOrderFront:nil];
    while (modal_running) [[NSRunLoop mainRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate distantFuture]];
    NSModalResponse r = modal_response;
    modal_window = saved;
    modal_running = wasRunning;
    return r;
}
- (void)stopModalWithCode:(NSModalResponse)code {
    modal_response = code;
    modal_running = NO;
}
- (void)stopModal { [self stopModalWithCode:NSModalResponseStop]; }
- (void)abortModal { [self stopModalWithCode:NSModalResponseAbort]; }
- (NSWindow *)modalWindow { return modal_running ? modal_window : nil; }
- (NSApplicationPresentationOptions)presentationOptions { return [props(self)[@"presentation"] unsignedIntegerValue]; }
- (void)setPresentationOptions:(NSApplicationPresentationOptions)o { props(self)[@"presentation"] = @(o); }
- (NSApplicationPresentationOptions)currentSystemPresentationOptions { return self.presentationOptions; }
- (NSApplicationOcclusionState)occlusionState { return NSApplicationOcclusionStateVisible; }
- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection { return NSUserInterfaceLayoutDirectionLeftToRight; }
- (BOOL)isAutomaticCustomizeTouchBarMenuItemEnabled { return NO; }
- (void)setAutomaticCustomizeTouchBarMenuItemEnabled:(BOOL)e {}
- (void)replyToApplicationShouldTerminate:(BOOL)shouldTerminate {
    if (shouldTerminate) exit(0);
}
- (void)updateWindows {}
- (void)setWindowsNeedUpdate:(BOOL)needUpdate {}
- (void)arrangeInFront:(id)sender {
    for (NSWindow *w in self.windows) if (w.isVisible) [w orderFront:nil];
}
- (void)miniaturizeAll:(id)sender {
    for (NSWindow *w in self.windows) [w miniaturize:sender];
}
- (void)registerForRemoteNotifications {}
- (void)unregisterForRemoteNotifications {}
- (BOOL)isRegisteredForRemoteNotifications { return NO; }
- (void)registerServicesMenuSendTypes:(NSArray *)sendTypes returnTypes:(NSArray *)returnTypes {}
- (NSWindow *)windowWithWindowNumber:(NSInteger)n {
    for (NSWindow *w in self.windows) if (w.windowNumber == n) return w;
    return nil;
}
- (void)enumerateWindowsWithOptions:(NSUInteger)options usingBlock:(void (^)(NSWindow *, BOOL *))block {
    BOOL stop = NO;
    for (NSWindow *w in self.windows) {
        block(w, &stop);
        if (stop) break;
    }
}
@end
