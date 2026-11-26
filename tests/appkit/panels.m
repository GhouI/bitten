// Open and save panels over a real directory: listing (folders first,
// hidden files, packages, types), choosing with the mouse and keyboard,
// going into and out of folders, multiple selection, directories, the
// delegate, the extension added when saving, New Folder, and running as a
// modal panel, a sheet, or on its own.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static NSString *tmp;
static NSString *P(NSString *name) { return [tmp stringByAppendingPathComponent:name]; }

@interface Watcher : NSObject <NSOpenSavePanelDelegate>
@property int moves, changes;
@property NSString *reject;
@end
@implementation Watcher
- (void)panel:(id)sender didChangeToDirectoryURL:(NSURL *)url { self.moves++; }
- (void)panelSelectionDidChange:(id)sender { self.changes++; }
- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)e {
    return !self.reject || ![url.lastPathComponent isEqual:self.reject];
}
@end

static NSScrollView *scroll_of(NSView *v) {
    if ([v isKindOfClass:[NSScrollView class]]) return (NSScrollView *)v;
    for (NSView *s in v.subviews) {
        NSScrollView *r = scroll_of(s);
        if (r) return r;
    }
    return nil;
}
static NSButton *button(NSView *v, NSString *title) {
    if ([v isKindOfClass:[NSButton class]] && [((NSButton *)v).title isEqual:title]) return (NSButton *)v;
    for (NSView *s in v.subviews) {
        NSButton *r = button(s, title);
        if (r) return r;
    }
    return nil;
}

static NSEvent *mouse(NSEventType t, NSWindow *w, NSPoint p, NSInteger clicks, NSEventModifierFlags m) {
    return [NSEvent mouseEventWithType:t location:p modifierFlags:m timestamp:0 windowNumber:w.windowNumber context:nil
                           eventNumber:0 clickCount:clicks pressure:1];
}
/* Clicks row r of the panel's list. */
static void click(NSSavePanel *p, int r, NSInteger clicks, NSEventModifierFlags m) {
    NSScrollView *sv = scroll_of(p.contentView);
    NSClipView *clip = sv.contentView;
    NSRect cf = clip.frame;
    CGFloat listY = r * 20 + 10 - clip.bounds.origin.y;
    NSPoint at = NSMakePoint(sv.frame.origin.x + cf.origin.x + 30, sv.frame.origin.y + cf.origin.y + cf.size.height - listY);
    [p sendEvent:mouse(NSEventTypeLeftMouseDown, p, at, clicks, m)];
    [p sendEvent:mouse(NSEventTypeLeftMouseUp, p, at, clicks, m)];
}
static void key(NSWindow *w, unsigned short code, NSString *chars) {
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                              windowNumber:w.windowNumber context:nil characters:chars charactersIgnoringModifiers:chars
                                 isARepeat:NO keyCode:code]];
}

int main(void) {
    [NSApplication sharedApplication];
    NSFileManager *fm = [NSFileManager defaultManager];
    tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"bitten-panels-%d", getpid()]];
    [fm createDirectoryAtPath:P(@"Folder") withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createDirectoryAtPath:P(@"Pkg.app") withIntermediateDirectories:YES attributes:nil error:NULL];
    for (NSString *f in @[@"b.txt", @"a.png", @".hidden", @"Folder/inner.txt"])
        [@"x" writeToFile:P(f) atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    NSURL *dir = [NSURL fileURLWithPath:tmp isDirectory:YES];

    /* Rows: Folder, a.png (not text: dimmed), b.txt, Pkg.app (a package: dimmed). */
    NSOpenPanel *open = [NSOpenPanel openPanel];
    CHECK([open isKindOfClass:[NSOpenPanel class]] && open.canChooseFiles && !open.canChooseDirectories);
    CHECK([open.prompt isEqual:@"Open"]);
    Watcher *watch = [Watcher new];
    open.delegate = watch;
    open.directoryURL = dir;
    open.allowedContentTypes = @[@"public.text"];
    __block NSModalResponse got = -1;
    [open beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    CHECK(open.isVisible);
    click(open, 2, 1, 0);
    CHECK(watch.changes == 1);
    [open ok:nil];
    CHECK(got == NSModalResponseOK && !open.isVisible);
    CHECK(open.URLs.count == 1 && [open.URL.path isEqual:P(@"b.txt")]);

    /* A dimmed row does not select; double-clicking a folder goes in; left goes up. */
    got = -1;
    [open beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    click(open, 1, 1, 0);
    [open ok:nil];
    CHECK(got == -1);
    int moves = watch.moves;
    click(open, 0, 2, 0);
    CHECK(watch.moves == moves + 1 && [open.directoryURL.path isEqual:P(@"Folder")]);
    click(open, 0, 2, 0);                         /* inner.txt: chosen */
    CHECK(got == NSModalResponseOK && [open.URL.path isEqual:P(@"Folder/inner.txt")]);

    /* The keyboard: down to b.txt, Return. Left goes up a level. */
    got = -1;
    open.directoryURL = [NSURL fileURLWithPath:P(@"Folder") isDirectory:YES];
    [open beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    key(open, 123, @"");
    CHECK([open.directoryURL.path isEqual:tmp]);
    key(open, 125, @"");
    key(open, 125, @"");
    key(open, 125, @"");
    key(open, 36, @"\r");
    CHECK(got == NSModalResponseOK && [open.URL.path isEqual:P(@"b.txt")]);

    /* Validation can refuse; Escape cancels. */
    got = -1;
    watch.reject = @"b.txt";
    [open beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    click(open, 2, 1, 0);
    [open ok:nil];
    CHECK(got == -1 && open.isVisible);
    key(open, 53, @"\033");
    CHECK(got == NSModalResponseCancel && !open.isVisible);
    watch.reject = nil;

    /* Several at once, with command-click. */
    open.allowedContentTypes = @[];
    open.allowsMultipleSelection = YES;
    [open beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    click(open, 1, 1, 0);
    click(open, 2, 1, NSEventModifierFlagCommand);
    [open ok:nil];
    CHECK(open.URLs.count == 2 && [open.URLs[0].path isEqual:P(@"a.png")] && [open.URLs[1].path isEqual:P(@"b.txt")]);

    /* Directories: nothing selected chooses the one shown. Packages are files. */
    NSOpenPanel *dirs = [NSOpenPanel openPanel];
    dirs.canChooseDirectories = YES;
    dirs.canChooseFiles = NO;
    dirs.directoryURL = dir;
    [dirs beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    [dirs ok:nil];
    CHECK([dirs.URL.path isEqual:tmp]);
    [dirs beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    click(dirs, 0, 1, 0);
    [dirs ok:nil];
    CHECK([dirs.URL.path isEqual:P(@"Folder")]);
    dirs.canChooseFiles = YES;
    [dirs beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    click(dirs, 3, 1, 0);
    [dirs ok:nil];
    CHECK([dirs.URL.path isEqual:P(@"Pkg.app")]);
    dirs.treatsFilePackagesAsDirectories = YES;   /* now Pkg.app is a folder, second row */
    [dirs beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    click(dirs, 1, 1, 0);
    [dirs ok:nil];
    CHECK([dirs.URL.path isEqual:P(@"Pkg.app")]);

    /* Hidden files. */
    dirs.treatsFilePackagesAsDirectories = NO;
    dirs.showsHiddenFiles = YES;
    [dirs beginWithCompletionHandler:^(NSModalResponse r) { got = r; }];
    click(dirs, 1, 1, 0);
    [dirs ok:nil];
    CHECK([dirs.URL.path isEqual:P(@".hidden")]);

    /* Saving, as a modal panel: the type's extension is added. */
    NSSavePanel *save = [NSSavePanel savePanel];
    CHECK(![save isKindOfClass:[NSOpenPanel class]] && [save.prompt isEqual:@"Save"] && save.canCreateDirectories);
    save.directoryURL = dir;
    save.allowedContentTypes = @[@"public.plain-text"];
    save.nameFieldStringValue = @"report";
    save.message = @"Where to?";
    dispatch_async(dispatch_get_main_queue(), ^{
        CHECK([NSApp modalWindow] == save);
        [save ok:nil];
    });
    CHECK([save runModal] == NSModalResponseOK);
    CHECK([save.URL.path isEqual:P(@"report.txt")]);
    save.nameFieldStringValue = @"notes.txt";
    dispatch_async(dispatch_get_main_queue(), ^{ [save ok:nil]; });
    [save runModal];
    CHECK([save.URL.path isEqual:P(@"notes.txt")]);

    /* Clicking an existing file takes its name; New Folder makes one. */
    dispatch_async(dispatch_get_main_queue(), ^{
        click(save, 2, 1, 0);
        CHECK([save.nameFieldStringValue isEqual:@"b.txt"]);
        [button(save.contentView, @"New Folder") performClick:nil];
        [save cancel:nil];
    });
    CHECK([save runModal] == NSModalResponseCancel);
    BOOL isDir = NO;
    CHECK([fm fileExistsAtPath:P(@"untitled folder") isDirectory:&isDir] && isDir);

    /* As a sheet on a window. */
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 500) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:NO];
    [w makeKeyAndOrderFront:nil];
    __block NSModalResponse sheet = -1;
    [save beginSheetModalForWindow:w completionHandler:^(NSModalResponse r) { sheet = r; }];
    CHECK(save.sheetParent == w);
    save.nameFieldStringValue = @"sheet";
    [save ok:nil];
    CHECK(sheet == NSModalResponseOK && [save.URL.path isEqual:P(@"sheet.txt")]);

    [fm removeItemAtPath:tmp error:NULL];
    printf("panels ok\n");
    return 0;
}
