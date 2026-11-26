/* NSWorkspace and NSRunningApplication: this application as the one running
 * app, its own notification centre, and opening URLs and files. Inside the
 * container there is no Finder or browser: opening is reported on stderr
 * and handed to $BITTEN_OPEN (a command given the URL) when that is set. */
#import <AppKit/AppKit.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

extern char **environ;

@implementation NSRunningApplication {
  @public
    pid_t _pid;
}
+ (instancetype)currentApplication {
    static NSRunningApplication *current;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        current = [NSRunningApplication new];
        current->_pid = getpid();
    });
    return current;
}
+ (nullable instancetype)runningApplicationWithProcessIdentifier:(pid_t)pid {
    return pid == getpid() ? [self currentApplication] : nil;
}
+ (NSArray<NSRunningApplication *> *)runningApplicationsWithBundleIdentifier:(NSString *)bundleIdentifier {
    NSRunningApplication *me = [self currentApplication];
    return [me.bundleIdentifier isEqualToString:bundleIdentifier] ? @[ me ] : @[];
}
- (pid_t)processIdentifier { return _pid; }
- (NSString *)bundleIdentifier { return [NSBundle mainBundle].bundleIdentifier; }
- (NSURL *)bundleURL { return [NSBundle mainBundle].bundleURL; }
- (NSURL *)executableURL { return [NSBundle mainBundle].executableURL; }
- (NSString *)localizedName {
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    return info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: [NSProcessInfo processInfo].processName;
}
- (NSImage *)icon { return nil; }
- (BOOL)isActive { return [NSApp isActive]; }
- (BOOL)isHidden { return NO; }
- (BOOL)isTerminated { return NO; }
- (BOOL)isFinishedLaunching { return YES; }
- (NSApplicationActivationPolicy)activationPolicy { return NSApplicationActivationPolicyRegular; }
- (NSDate *)launchDate { return nil; }
- (BOOL)activateWithOptions:(NSUInteger)options {
    [NSApp activate];
    return YES;
}
- (BOOL)activateFromApplication:(NSRunningApplication *)app options:(NSUInteger)options {
    return [self activateWithOptions:options];
}
- (BOOL)hide { return NO; }
- (BOOL)unhide { return YES; }
- (BOOL)terminate {
    [NSApp terminate:nil];
    return YES;
}
- (BOOL)forceTerminate { exit(0); }
@end

@implementation NSWorkspaceOpenConfiguration
+ (instancetype)configuration { return [self new]; }
@end

@implementation NSWorkspace {
    NSNotificationCenter *_center;
}
+ (NSWorkspace *)sharedWorkspace {
    static NSWorkspace *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [NSWorkspace new];
        shared->_center = [NSNotificationCenter new];
    });
    return shared;
}
- (NSNotificationCenter *)notificationCenter { return _center; }

/* Hands a URL to $BITTEN_OPEN, or just reports it. */
- (BOOL)_bn_open:(NSString *)what {
    fprintf(stderr, "bitten: open %s\n", what.UTF8String);
    const char *cmd = getenv("BITTEN_OPEN");
    if (!cmd || !*cmd) return YES;
    pid_t pid;
    char *argv[] = {(char *)cmd, (char *)what.UTF8String, NULL};
    return posix_spawnp(&pid, cmd, NULL, NULL, argv, environ) == 0;
}
- (BOOL)openURL:(NSURL *)url { return url ? [self _bn_open:url.absoluteString] : NO; }
- (void)openURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)configuration
    completionHandler:(void (^)(NSRunningApplication *app, NSError *error))handler {
    BOOL ok = [self openURL:url];
    if (handler)
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(ok ? [NSRunningApplication currentApplication] : nil,
                    ok ? nil : [NSError errorWithDomain:NSCocoaErrorDomain code:4 userInfo:nil]);
        });
}
- (void)openURLs:(NSArray<NSURL *> *)urls withApplicationAtURL:(NSURL *)appURL
    configuration:(NSWorkspaceOpenConfiguration *)configuration
    completionHandler:(void (^)(NSRunningApplication *app, NSError *error))handler {
    for (NSURL *u in urls) [self openURL:u];
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(nil, nil); });
}
- (void)openApplicationAtURL:(NSURL *)appURL configuration:(NSWorkspaceOpenConfiguration *)configuration
           completionHandler:(void (^)(NSRunningApplication *app, NSError *error))handler {
    [self _bn_open:appURL.path ?: @""];
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(nil, nil); });
}
- (BOOL)openFile:(NSString *)path { return [self _bn_open:path]; }
- (BOOL)selectFile:(NSString *)path inFileViewerRootedAtPath:(NSString *)root {
    return [self _bn_open:path ?: root];
}
- (void)activateFileViewerSelectingURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) [self _bn_open:u.path];
}
- (NSURL *)URLForApplicationWithBundleIdentifier:(NSString *)bundleIdentifier {
    if ([bundleIdentifier isEqualToString:[NSBundle mainBundle].bundleIdentifier]) return [NSBundle mainBundle].bundleURL;
    return nil;
}
- (NSURL *)URLForApplicationToOpenURL:(NSURL *)url { return nil; }
- (NSArray<NSURL *> *)URLsForApplicationsToOpenURL:(NSURL *)url { return @[]; }
- (NSString *)fullPathForApplication:(NSString *)appName { return nil; }
- (NSRunningApplication *)frontmostApplication { return [NSRunningApplication currentApplication]; }
- (NSRunningApplication *)menuBarOwningApplication { return [NSRunningApplication currentApplication]; }
- (NSArray<NSRunningApplication *> *)runningApplications { return @[ [NSRunningApplication currentApplication] ]; }
- (NSImage *)iconForFile:(NSString *)fullPath { return [NSImage new]; }
- (NSImage *)iconForFiles:(NSArray<NSString *> *)fullPaths { return [NSImage new]; }
- (NSImage *)iconForContentType:(id)contentType { return [NSImage new]; }
- (BOOL)setIcon:(NSImage *)image forFile:(NSString *)fullPath options:(NSUInteger)options { return NO; }
- (BOOL)isFilePackageAtPath:(NSString *)fullPath {
    struct stat st;
    if (stat(fullPath.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) return NO;
    NSString *ext = fullPath.pathExtension.lowercaseString;
    return [@[ @"app", @"bundle", @"framework", @"plugin", @"kext", @"rtfd" ] containsObject:ext];
}
- (void)recycleURLs:(NSArray<NSURL *> *)URLs completionHandler:(void (^)(NSDictionary<NSURL *, NSURL *> *, NSError *))handler {
    /* No Trash in the container: move them to ~/.Trash. */
    NSString *trash = [NSHomeDirectory() stringByAppendingPathComponent:@".Trash"];
    [[NSFileManager defaultManager] createDirectoryAtPath:trash withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableDictionary *moved = [NSMutableDictionary dictionary];
    NSError *error = nil;
    for (NSURL *u in URLs) {
        NSString *dest = [trash stringByAppendingPathComponent:u.lastPathComponent];
        if ([[NSFileManager defaultManager] moveItemAtPath:u.path toPath:dest error:&error])
            moved[u] = [NSURL fileURLWithPath:dest];
    }
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(moved, error); });
}
- (BOOL)accessibilityDisplayShouldReduceMotion { return NO; }
- (BOOL)accessibilityDisplayShouldIncreaseContrast { return NO; }
- (BOOL)accessibilityDisplayShouldReduceTransparency { return NO; }
- (BOOL)accessibilityDisplayShouldDifferentiateWithoutColor { return NO; }
- (BOOL)accessibilityDisplayShouldInvertColors { return NO; }
- (BOOL)isVoiceOverEnabled { return NO; }
- (BOOL)isSwitchControlEnabled { return NO; }
- (void)noteFileSystemChanged:(NSString *)path {}
@end
