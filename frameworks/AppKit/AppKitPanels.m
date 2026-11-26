/* NSPanel, and the open and save panels: real panels that browse the file
 * system. A panel shows the directory it is in as a list (folders first,
 * hidden files left out unless asked for, entries the panel cannot choose
 * dimmed), with back and enclosing-folder buttons, the path, a name field
 * for saving, the accessory view, New Folder, and Cancel and the prompt
 * button. Clicking selects (command and shift extend the selection when
 * several may be chosen), double-clicking a folder goes into it and
 * double-clicking a file chooses it; arrows, Return and Escape work from
 * the keyboard. runModal runs it as a modal panel; it can also be a sheet
 * or run on its own with a completion handler. */
#import <AppKit/AppKit.h>
#import <AppKit/AppKitPanels.h>
#include <objc/runtime.h>

@implementation NSPanel
@synthesize floatingPanel = _floatingPanel, becomesKeyOnlyIfNeeded = _becomesKeyOnlyIfNeeded,
            worksWhenModal = _worksWhenModal;
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

/* ---- content types ---- */

/* The file name extensions a type identifier (or an extension) stands
 * for; nil for one that takes anything. */
static NSSet<NSString *> *extensions_for(NSString *t) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *table;
    if (!table) {
        NSArray *text = @[@"txt", @"text", @"md", @"markdown", @"log", @"csv", @"json", @"xml", @"html", @"htm", @"swift",
                          @"m", @"h", @"c", @"cpp", @"py", @"js", @"ts", @"sh", @"rb", @"go", @"rs", @"yaml", @"yml"];
        NSArray *image = @[@"png", @"jpg", @"jpeg", @"gif", @"tif", @"tiff", @"heic", @"webp", @"bmp", @"ico", @"svg"];
        table = @{
            @"public.text": text, @"public.plain-text": @[@"txt", @"text", @"log"], @"public.utf8-plain-text": @[@"txt"],
            @"public.source-code": @[@"swift", @"m", @"h", @"c", @"cpp", @"py", @"js", @"ts", @"rb", @"go", @"rs"],
            @"public.json": @[@"json"], @"public.xml": @[@"xml"], @"public.html": @[@"html", @"htm"],
            @"public.comma-separated-values-text": @[@"csv"], @"public.yaml": @[@"yaml", @"yml"],
            @"net.daringfireball.markdown": @[@"md", @"markdown"], @"public.shell-script": @[@"sh", @"command", @"zsh"],
            @"public.python-script": @[@"py"], @"com.netscape.javascript-source": @[@"js"],
            @"public.swift-source": @[@"swift"],
            @"public.image": image, @"public.png": @[@"png"], @"public.jpeg": @[@"jpg", @"jpeg"],
            @"com.compuserve.gif": @[@"gif"], @"public.tiff": @[@"tif", @"tiff"], @"public.heic": @[@"heic"],
            @"org.webmproject.webp": @[@"webp"], @"public.svg-image": @[@"svg"],
            @"com.adobe.pdf": @[@"pdf"], @"public.zip-archive": @[@"zip"], @"org.gnu.gnu-zip-archive": @[@"gz"],
            @"public.tar-archive": @[@"tar"], @"com.apple.disk-image": @[@"dmg"],
            @"public.movie": @[@"mov", @"mp4", @"m4v", @"avi", @"mkv"], @"public.mpeg-4": @[@"mp4"],
            @"com.apple.quicktime-movie": @[@"mov"],
            @"public.audio": @[@"mp3", @"m4a", @"wav", @"aiff", @"aif", @"flac", @"aac"], @"public.mp3": @[@"mp3"],
            @"com.microsoft.waveform-audio": @[@"wav"],
            @"com.apple.application-bundle": @[@"app"], @"com.apple.property-list": @[@"plist"],
            @"public.rtf": @[@"rtf"], @"com.apple.rtfd": @[@"rtfd"],
        };
    }
    static NSSet *anything;
    if (!anything) anything = [NSSet setWithArray:@[@"public.data", @"public.item", @"public.content", @"public.file-url"]];
    if ([anything containsObject:t]) return nil;
    NSArray *e = table[t];
    if (e) return [NSSet setWithArray:e];
    if ([t rangeOfString:@"."].location == NSNotFound) return [NSSet setWithObject:t.lowercaseString];  /* an extension */
    return [NSSet set];
}

/* A UTType object's identifier, or a string as it is. */
static NSString *type_identifier(id t) {
    if ([t isKindOfClass:[NSString class]]) return t;
    if ([t respondsToSelector:@selector(identifier)]) return [t performSelector:@selector(identifier)];
    return nil;
}

/* ---- the list of a directory's entries ---- */

@interface BNFileEntry : NSObject
@property NSURL *url;
@property NSString *name;
@property BOOL directory, package, enabled;
@end
@implementation BNFileEntry
@end

@class BNFileList;
@interface NSSavePanel (BNPanelPrivate)
- (void)_bn_listClicked:(BNFileList *)list row:(NSInteger)row event:(NSEvent *)e;
- (void)_bn_listKey:(NSEvent *)e;
@end

static const CGFloat kRow = 20;

/* The rows selected, in order. */
@interface BNIndexSet : NSObject
@property (readonly) NSUInteger count, firstIndex, lastIndex;
- (BOOL)containsIndex:(NSUInteger)i;
- (void)addIndex:(NSUInteger)i;
- (void)removeIndex:(NSUInteger)i;
- (void)removeAllIndexes;
- (NSArray *)objectsIn:(NSArray *)a;
@end
@implementation BNIndexSet {
    NSMutableArray<NSNumber *> *_rows;
}
- (instancetype)init {
    if ((self = [super init])) _rows = [NSMutableArray array];
    return self;
}
- (NSUInteger)count { return _rows.count; }
- (NSUInteger)firstIndex { return _rows.count ? _rows[0].unsignedIntegerValue : NSNotFound; }
- (NSUInteger)lastIndex { return _rows.count ? _rows.lastObject.unsignedIntegerValue : NSNotFound; }
- (BOOL)containsIndex:(NSUInteger)i { return [_rows containsObject:@(i)]; }
- (void)addIndex:(NSUInteger)i {
    if ([self containsIndex:i]) return;
    [_rows addObject:@(i)];
    [_rows sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [a compare:b]; }];
}
- (void)removeIndex:(NSUInteger)i { [_rows removeObject:@(i)]; }
- (void)removeAllIndexes { [_rows removeAllObjects]; }
- (NSArray *)objectsIn:(NSArray *)a {
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *n in _rows)
        if (n.unsignedIntegerValue < a.count) [out addObject:a[n.unsignedIntegerValue]];
    return out;
}
@end

/* A window point in a view's coordinates, minding flipped views. */
static NSPoint local_point(NSView *v, NSPoint p) {
    NSRect f = v.frame, b = v.bounds;
    if (!v.superview) {
        CGFloat y = p.y - f.origin.y;
        return NSMakePoint(p.x - f.origin.x + b.origin.x, (v.isFlipped ? f.size.height - y : y) + b.origin.y);
    }
    NSPoint s = local_point(v.superview, p);
    CGFloat dy = s.y - f.origin.y;
    BOOL sf = v.superview.isFlipped;
    CGFloat y = v.isFlipped ? (sf ? dy : f.size.height - dy) : (sf ? f.size.height - dy : dy);
    return NSMakePoint(s.x - f.origin.x + b.origin.x, y + b.origin.y);
}

@interface BNFileList : NSView
@property (copy) NSArray<BNFileEntry *> *entries;
@property BNIndexSet *selection;
@property (weak) NSSavePanel *panel;
@end
@implementation BNFileList
- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) _selection = [BNIndexSet new];
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)dirty {
    [[NSColor textBackgroundColor] setFill];
    NSRectFill(self.bounds);
    NSFont *font = [NSFont systemFontOfSize:13];
    for (NSUInteger i = 0; i < _entries.count; i++) {
        BNFileEntry *e = _entries[i];
        NSRect row = NSMakeRect(0, i * kRow, self.bounds.size.width, kRow);
        BOOL sel = [_selection containsIndex:i];
        if (sel) {
            [[NSColor selectedContentBackgroundColor] setFill];
            NSRectFill(row);
        }
        NSColor *c = sel ? [NSColor alternateSelectedControlTextColor]
                         : e.enabled ? [NSColor textColor] : [NSColor disabledControlTextColor];
        NSDictionary *attrs = @{NSFontAttributeName : font, NSForegroundColorAttributeName : c};
        NSString *mark = e.directory && !e.package ? @"▸" : @" ";
        [mark drawAtPoint:NSMakePoint(6, row.origin.y + 2) withAttributes:attrs];
        [e.name drawAtPoint:NSMakePoint(22, row.origin.y + 2) withAttributes:attrs];
    }
}
- (void)mouseDown:(NSEvent *)e {
    [self.window makeFirstResponder:self];
    NSPoint p = local_point(self, e.locationInWindow);
    NSInteger row = p.y < 0 ? -1 : (NSInteger)(p.y / kRow);
    if (row >= (NSInteger)_entries.count) row = -1;
    [_panel _bn_listClicked:self row:row event:e];
}
- (void)keyDown:(NSEvent *)e { [_panel _bn_listKey:e]; }
@end

/* The panel's content: unflipped, with clicks in the list sent to it. */
@interface BNPanelContent : NSView
@property (weak) NSScrollView *scroll;
@property (weak) BNFileList *list;
@end
@implementation BNPanelContent
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if (!hit || !_scroll) return hit;
    NSPoint local = NSMakePoint(point.x - self.frame.origin.x, point.y - self.frame.origin.y);
    if (NSPointInRect(local, _scroll.frame)) return _list;
    return hit;
}
@end

/* ---- the save panel ---- */

@interface NSSavePanel () {
@public
    NSURL *_directoryURL, *_url;
    NSArray *_allowedContentTypes;
    NSArray<NSString *> *_allowedFileTypes;
    NSString *_prompt, *_nameFieldLabel, *_nameFieldStringValue, *_message;
    NSView *_accessoryView;
    __weak id<NSOpenSavePanelDelegate> _delegate;
    NSMutableArray<NSURL *> *_back;
    BNFileList *_list;
    NSTextField *_nameField, *_pathLabel;
    NSButton *_okButton;
    void (^_handler)(NSModalResponse);
    BOOL _built;
}
- (BOOL)_bn_isOpen;
- (BOOL)_bn_multiple;
- (void)_bn_reload;
- (void)_bn_prepare;
- (BOOL)_bn_typeAllowed:(NSURL *)u;
- (BOOL)_bn_validate:(NSURL *)u;
- (void)_bn_finish:(NSModalResponse)r;
@end

@implementation NSSavePanel
@synthesize allowsOtherFileTypes = _allowsOtherFileTypes, canCreateDirectories = _canCreateDirectories,
            canSelectHiddenExtension = _canSelectHiddenExtension, extensionHidden = _extensionHidden,
            treatsFilePackagesAsDirectories = _treatsFilePackagesAsDirectories, showsHiddenFiles = _showsHiddenFiles,
            showsTagField = _showsTagField, tagNames = _tagNames, showsContentTypes = _showsContentTypes,
            identifier = _identifier;

+ (NSSavePanel *)savePanel {
    NSSavePanel *p = [[self alloc] initWithContentRect:NSMakeRect(0, 0, 640, 420)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    p.releasedWhenClosed = NO;
    return p;
}
- (instancetype)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)m backing:(NSBackingStoreType)b defer:(BOOL)d {
    if ((self = [super initWithContentRect:r styleMask:m backing:b defer:d])) {
        _back = [NSMutableArray array];
        _allowedContentTypes = @[];
        _nameFieldStringValue = @"";
        _canCreateDirectories = YES;
        _showsTagField = YES;
        NSString *docs = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        BOOL dir = NO;
        _directoryURL = [NSURL fileURLWithPath:[[NSFileManager defaultManager] fileExistsAtPath:docs isDirectory:&dir] && dir
                                                   ? docs
                                                   : NSHomeDirectory()
                                   isDirectory:YES];
        self.title = [self _bn_isOpen] ? @"Open" : @"Save";
    }
    return self;
}
- (BOOL)_bn_isOpen { return NO; }

- (NSURL *)URL { return _url; }
- (NSURL *)directoryURL { return _directoryURL; }
- (void)setDirectoryURL:(NSURL *)u {
    if (!u) return;
    if (_directoryURL && ![_directoryURL isEqual:u]) [_back addObject:_directoryURL];
    [self _bn_go:u];
}
- (void)_bn_go:(NSURL *)u {
    _directoryURL = [NSURL fileURLWithPath:u.path.stringByStandardizingPath isDirectory:YES];
    id<NSOpenSavePanelDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(panel:didChangeToDirectoryURL:)]) [d panel:self didChangeToDirectoryURL:_directoryURL];
    [self _bn_reload];
}
- (NSArray *)allowedContentTypes { return _allowedContentTypes; }
- (void)setAllowedContentTypes:(NSArray *)t {
    _allowedContentTypes = [t copy] ?: @[];
    [self _bn_reload];
}
- (NSArray<NSString *> *)allowedFileTypes { return _allowedFileTypes; }
- (void)setAllowedFileTypes:(NSArray<NSString *> *)t {
    _allowedFileTypes = [t copy];
    [self _bn_reload];
}
- (NSView *)accessoryView { return _accessoryView; }
- (void)setAccessoryView:(NSView *)v {
    _accessoryView = v;
    if (_built) [self _bn_build];
}
- (id<NSOpenSavePanelDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSOpenSavePanelDelegate>)d { _delegate = d; }
- (BOOL)isExpanded { return YES; }
- (NSString *)prompt { return _prompt ?: ([self _bn_isOpen] ? @"Open" : @"Save"); }
- (void)setPrompt:(NSString *)p {
    _prompt = [p copy];
    _okButton.title = self.prompt;
}
- (NSString *)nameFieldLabel { return _nameFieldLabel ?: @"Save As:"; }
- (void)setNameFieldLabel:(NSString *)l { _nameFieldLabel = [l copy]; }
- (NSString *)nameFieldStringValue { return _nameField ? _nameField.stringValue : _nameFieldStringValue; }
- (void)setNameFieldStringValue:(NSString *)s {
    _nameFieldStringValue = [s copy] ?: @"";
    _nameField.stringValue = _nameFieldStringValue;
}
- (NSString *)message { return _message ?: @""; }
- (void)setMessage:(NSString *)m { _message = [m copy]; }
- (BOOL)showsHiddenFiles { return _showsHiddenFiles; }
- (BOOL)treatsFilePackagesAsDirectories { return _treatsFilePackagesAsDirectories; }
- (void)setShowsHiddenFiles:(BOOL)b {
    _showsHiddenFiles = b;
    [self _bn_reload];
}
- (void)setTreatsFilePackagesAsDirectories:(BOOL)b {
    _treatsFilePackagesAsDirectories = b;
    [self _bn_reload];
}
- (void)validateVisibleColumns { [self _bn_reload]; }

/* ---- what may be chosen ---- */

- (NSArray *)_bn_types { return _allowedContentTypes.count ? _allowedContentTypes : _allowedFileTypes; }
- (BOOL)_bn_typeAllowed:(NSURL *)u {
    NSArray *types = [self _bn_types];
    if (!types.count) return YES;
    NSString *ext = u.pathExtension.lowercaseString;
    for (id t in types) {
        NSString *ident = type_identifier(t);
        if (!ident) continue;
        NSSet *exts = extensions_for(ident);
        if (!exts || [exts containsObject:ext]) return YES;
    }
    return NO;
}
/* Whether an entry is shown enabled: folders always (to go into). */
- (BOOL)_bn_enabled:(BNFileEntry *)e {
    BOOL ok = (e.directory && !e.package) || [self _bn_typeAllowed:e.url];
    if (![self _bn_isOpen] && !(e.directory && !e.package)) ok = NO;    /* existing files are dimmed when saving */
    id<NSOpenSavePanelDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(panel:shouldEnableURL:)]) ok = [d panel:self shouldEnableURL:e.url];
    return ok;
}
- (BOOL)_bn_choosable:(BNFileEntry *)e { return NO; }

/* ---- the directory ---- */

static BOOL is_package(NSString *name) {
    static NSSet *exts;
    if (!exts) exts = [NSSet setWithArray:@[@"app", @"bundle", @"framework", @"plugin", @"pkg", @"rtfd", @"xcodeproj",
                                            @"playground", @"photoslibrary", @"kext", @"appex"]];
    return [exts containsObject:name.pathExtension.lowercaseString];
}

- (NSArray<BNFileEntry *> *)_bn_entries {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dirPath = _directoryURL.path;
    NSMutableArray<BNFileEntry *> *out = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dirPath error:NULL] ?: @[]) {
        if (!_showsHiddenFiles && [name hasPrefix:@"."]) continue;
        BNFileEntry *e = [BNFileEntry new];
        NSString *path = [dirPath stringByAppendingPathComponent:name];
        BOOL dir = NO;
        [fm fileExistsAtPath:path isDirectory:&dir];
        e.name = name;
        e.directory = dir;
        e.package = dir && is_package(name) && !_treatsFilePackagesAsDirectories;
        e.url = [NSURL fileURLWithPath:path isDirectory:dir];
        [out addObject:e];
    }
    [out sortUsingComparator:^NSComparisonResult(BNFileEntry *a, BNFileEntry *b) {
        BOOL fa = a.directory && !a.package, fb = b.directory && !b.package;
        if (fa != fb) return fa ? NSOrderedAscending : NSOrderedDescending;
        return [a.name caseInsensitiveCompare:b.name];
    }];
    for (BNFileEntry *e in out) e.enabled = [self _bn_enabled:e];
    return out;
}

- (void)_bn_reload {
    if (!_list) return;
    NSArray *old = [_list.selection objectsIn:_list.entries];
    _list.entries = [self _bn_entries];
    [_list.selection removeAllIndexes];
    for (NSUInteger i = 0; i < _list.entries.count; i++)
        for (BNFileEntry *o in old)
            if ([o.url isEqual:_list.entries[i].url]) [_list.selection addIndex:i];
    NSScrollView *sv = _list.enclosingScrollView;
    CGFloat h = MAX(_list.entries.count * kRow, sv ? sv.contentSize.height : 0);
    _list.frame = NSMakeRect(0, 0, sv ? sv.contentSize.width : _list.frame.size.width, h);
    _list.needsDisplay = YES;
    _pathLabel.stringValue = _directoryURL.path ?: @"";
}

/* ---- the panel's views ---- */

- (void)_bn_build {
    NSRect cr = [self contentRectForFrameRect:self.frame];
    CGFloat W = cr.size.width, H = cr.size.height, pad = 12;
    BNPanelContent *content = [[BNPanelContent alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    __block CGFloat top = pad;
    void (^put)(NSView *, CGFloat, CGFloat, CGFloat, CGFloat) = ^(NSView *v, CGFloat x, CGFloat t, CGFloat w, CGFloat h) {
        v.frame = NSMakeRect(x, H - t - h, w, h);
        [content addSubview:v];
    };
    if (self.message.length) {
        NSTextField *m = [NSTextField labelWithString:self.message];
        put(m, pad, top, W - 2 * pad, 17);
        top += 17 + 8;
    }
    NSButton *back = [NSButton buttonWithTitle:@"<" target:self action:@selector(_bn_goBack:)];
    put(back, pad, top, 28, 22);
    NSButton *up = [NSButton buttonWithTitle:@"Up" target:self action:@selector(_bn_goUp:)];
    put(up, pad + 32, top, 40, 22);
    _pathLabel = [NSTextField labelWithString:_directoryURL.path ?: @""];
    put(_pathLabel, pad + 80, top + 3, W - 2 * pad - 80, 17);
    top += 22 + 8;
    if (![self _bn_isOpen]) {
        NSTextField *label = [NSTextField labelWithString:self.nameFieldLabel];
        put(label, pad, top + 3, 70, 17);
        _nameField = [NSTextField textFieldWithString:_nameFieldStringValue ?: @""];
        put(_nameField, pad + 74, top, W - 2 * pad - 74, 22);
        top += 22 + 8;
    } else {
        _nameField = nil;
    }
    CGFloat bottom = pad + 22 + 8;
    if (_accessoryView) bottom += _accessoryView.frame.size.height + 8;
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(pad, bottom, W - 2 * pad, H - top - bottom)];
    sv.hasVerticalScroller = YES;
    sv.borderType = NSBezelBorder;
    _list = [[BNFileList alloc] initWithFrame:NSMakeRect(0, 0, sv.contentSize.width, sv.contentSize.height)];
    _list.panel = self;
    sv.documentView = _list;
    [content addSubview:sv];
    content.scroll = sv;
    content.list = _list;
    if (_accessoryView) {
        NSRect f = _accessoryView.frame;
        _accessoryView.frame = NSMakeRect((W - f.size.width) / 2, pad + 22 + 8, f.size.width, f.size.height);
        [content addSubview:_accessoryView];
    }
    _okButton = [NSButton buttonWithTitle:self.prompt target:self action:@selector(ok:)];
    _okButton.keyEquivalent = @"\r";
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";
    _okButton.frame = NSMakeRect(W - pad - 80, pad, 80, 22);
    cancel.frame = NSMakeRect(W - pad - 168, pad, 80, 22);
    [content addSubview:_okButton];
    [content addSubview:cancel];
    if (_canCreateDirectories) {
        NSButton *nf = [NSButton buttonWithTitle:@"New Folder" target:self action:@selector(_bn_newFolder:)];
        nf.frame = NSMakeRect(pad, pad, 96, 22);
        [content addSubview:nf];
    }
    self.contentView = content;
    [self makeFirstResponder:_list];
    _built = YES;
    [self _bn_reload];
}

- (void)_bn_goBack:(id)sender {
    NSURL *u = _back.lastObject;
    if (!u) return;
    [_back removeLastObject];
    [self _bn_go:u];
}
- (void)_bn_goUp:(id)sender {
    NSURL *parent = _directoryURL.URLByDeletingLastPathComponent;
    if (!parent || [parent.path isEqual:_directoryURL.path]) return;
    self.directoryURL = parent;
}
- (void)_bn_newFolder:(id)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *name = @"untitled folder";
    for (int i = 2; [fm fileExistsAtPath:[_directoryURL.path stringByAppendingPathComponent:name]]; i++)
        name = [NSString stringWithFormat:@"untitled folder %d", i];
    NSString *path = [_directoryURL.path stringByAppendingPathComponent:name];
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:NULL]) return;
    [self _bn_reload];
    for (NSUInteger i = 0; i < _list.entries.count; i++)
        if ([_list.entries[i].name isEqual:name]) {
            [_list.selection removeAllIndexes];
            [_list.selection addIndex:i];
        }
    [self _bn_selectionChanged];
}

- (void)_bn_selectionChanged {
    _list.needsDisplay = YES;
    id<NSOpenSavePanelDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(panelSelectionDidChange:)]) [d panelSelectionDidChange:self];
}

- (BOOL)_bn_multiple { return NO; }

- (void)_bn_listClicked:(BNFileList *)list row:(NSInteger)row event:(NSEvent *)e {
    if (row < 0) {
        [list.selection removeAllIndexes];
        [self _bn_selectionChanged];
        return;
    }
    BNFileEntry *entry = list.entries[(NSUInteger)row];
    if (e.clickCount >= 2) {
        if (entry.directory && !entry.package) self.directoryURL = entry.url;
        else if (entry.enabled || ![self _bn_isOpen]) {
            [list.selection removeAllIndexes];
            [list.selection addIndex:(NSUInteger)row];
            [self ok:nil];
        }
        return;
    }
    if (!entry.enabled && [self _bn_isOpen]) return;
    NSEventModifierFlags m = e.modifierFlags;
    if ([self _bn_multiple] && (m & NSEventModifierFlagCommand)) {
        if ([list.selection containsIndex:(NSUInteger)row]) [list.selection removeIndex:(NSUInteger)row];
        else [list.selection addIndex:(NSUInteger)row];
    } else if ([self _bn_multiple] && (m & NSEventModifierFlagShift) && list.selection.count) {
        NSUInteger a = MIN(list.selection.firstIndex, (NSUInteger)row), b = MAX(list.selection.lastIndex, (NSUInteger)row);
        for (NSUInteger i = a; i <= b; i++)
            if (list.entries[i].enabled) [list.selection addIndex:i];
    } else {
        [list.selection removeAllIndexes];
        [list.selection addIndex:(NSUInteger)row];
    }
    if (![self _bn_isOpen] && !(entry.directory && !entry.package)) self.nameFieldStringValue = entry.name;
    [self _bn_selectionChanged];
}

- (void)_bn_listKey:(NSEvent *)e {
    NSString *k = e.charactersIgnoringModifiers;
    unsigned short code = e.keyCode;
    NSUInteger n = _list.entries.count;
    NSInteger cur = _list.selection.count ? (NSInteger)_list.selection.lastIndex : -1;
    if (code == 125 || code == 126) {                      /* down, up */
        NSInteger next = cur + (code == 125 ? 1 : -1);
        if (cur < 0) next = code == 125 ? 0 : (NSInteger)n - 1;
        if (next < 0 || (NSUInteger)next >= n) return;
        [_list.selection removeAllIndexes];
        [_list.selection addIndex:(NSUInteger)next];
        [self _bn_selectionChanged];
    } else if ([k isEqual:@"\r"] || code == 36) {
        [self ok:nil];
    } else if ([k isEqual:@"\033"] || code == 53) {
        [self cancel:nil];
    } else if (code == 124 && cur >= 0) {                  /* right: into a folder */
        BNFileEntry *entry = _list.entries[(NSUInteger)cur];
        if (entry.directory && !entry.package) self.directoryURL = entry.url;
    } else if (code == 123) {                              /* left: up */
        [self _bn_goUp:nil];
    }
}

/* ---- finishing ---- */

- (BOOL)_bn_validate:(NSURL *)u {
    id<NSOpenSavePanelDelegate> d = _delegate;
    if (![d respondsToSelector:@selector(panel:validateURL:error:)]) return YES;
    NSError *err = nil;
    return [d panel:self validateURL:u error:&err];
}

/* The name typed, with the allowed type's extension added if it has none. */
- (NSString *)_bn_finalName {
    NSString *name = self.nameFieldStringValue;
    id<NSOpenSavePanelDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(panel:userEnteredFilename:confirmed:)])
        name = [d panel:self userEnteredFilename:name confirmed:YES] ?: name;
    NSArray *types = [self _bn_types];
    if (!types.count || !name.length) return name;
    NSURL *probe = [NSURL fileURLWithPath:name];
    if ([self _bn_typeAllowed:probe] && probe.pathExtension.length) return name;
    if (_allowsOtherFileTypes && probe.pathExtension.length) return name;
    NSSet *exts = extensions_for(type_identifier(types[0]));
    NSString *ext = exts.count == 1 ? exts.anyObject : nil;
    if (!ext) {
        /* the type's usual extension: the first in its list */
        NSString *ident = type_identifier(types[0]);
        if ([ident isEqual:@"public.jpeg"]) ext = @"jpeg";
        else if ([ident isEqual:@"public.plain-text"] || [ident isEqual:@"public.text"]) ext = @"txt";
        else if ([ident isEqual:@"public.tiff"]) ext = @"tiff";
        else ext = exts.anyObject;
    }
    return ext ? [name stringByAppendingPathExtension:ext] : name;
}

- (BOOL)_bn_accept {
    NSString *name = [self _bn_finalName];
    if (!name.length) return NO;
    NSURL *u = [NSURL fileURLWithPath:[_directoryURL.path stringByAppendingPathComponent:name] isDirectory:NO];
    if (![self _bn_validate:u]) return NO;
    _url = u;
    return YES;
}

- (void)ok:(id)sender {
    if (![self _bn_accept]) {
        NSBeep();
        return;
    }
    [self _bn_finish:NSModalResponseOK];
}
- (void)cancel:(id)sender { [self _bn_finish:NSModalResponseCancel]; }

- (void)_bn_finish:(NSModalResponse)r {
    NSWindow *parent = self.sheetParent;
    void (^h)(NSModalResponse) = _handler;
    _handler = nil;
    if (parent) [parent endSheet:self returnCode:r];
    else if ([NSApp modalWindow] == self) [NSApp stopModalWithCode:r];
    [self orderOut:nil];
    if (h) h(r);
}

- (void)_bn_prepare {
    _url = nil;
    [_back removeAllObjects];
    [self _bn_build];
}
- (NSModalResponse)runModal {
    [self _bn_prepare];
    [self center];
    return [NSApp runModalForWindow:self];
}
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler {
    if (!window) {
        [self beginWithCompletionHandler:handler];
        return;
    }
    [self _bn_prepare];
    [window beginSheet:self completionHandler:handler];
}
- (void)beginWithCompletionHandler:(void (^)(NSModalResponse))handler {
    [self _bn_prepare];
    _handler = [handler copy];
    [self center];
    [self makeKeyAndOrderFront:nil];
}
@end

/* ---- the open panel ---- */

@implementation NSOpenPanel {
    NSArray<NSURL *> *_urls;
}
@synthesize resolvesAliases = _resolvesAliases, canChooseDirectories = _canChooseDirectories,
            allowsMultipleSelection = _allowsMultipleSelection, canChooseFiles = _canChooseFiles,
            canResolveUbiquitousConflicts = _canResolveUbiquitousConflicts,
            canDownloadUbiquitousContents = _canDownloadUbiquitousContents,
            accessoryViewDisclosed = _accessoryViewDisclosed;

+ (NSOpenPanel *)openPanel { return (NSOpenPanel *)[self savePanel]; }
- (instancetype)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)m backing:(NSBackingStoreType)b defer:(BOOL)d {
    if ((self = [super initWithContentRect:r styleMask:m backing:b defer:d])) {
        _canChooseFiles = YES;
        _resolvesAliases = YES;
        self.canCreateDirectories = NO;
        _urls = @[];
    }
    return self;
}
- (BOOL)_bn_isOpen { return YES; }
- (BOOL)_bn_multiple { return _allowsMultipleSelection; }
- (NSArray<NSURL *> *)URLs { return _urls; }
- (NSURL *)URL { return _urls.firstObject; }
- (BOOL)canChooseFiles { return _canChooseFiles; }
- (BOOL)canChooseDirectories { return _canChooseDirectories; }
- (void)setCanChooseFiles:(BOOL)b {
    _canChooseFiles = b;
    [self _bn_reload];
}
- (void)setCanChooseDirectories:(BOOL)b {
    _canChooseDirectories = b;
    [self _bn_reload];
}

- (BOOL)_bn_enabled:(BNFileEntry *)e {
    BOOL folder = e.directory && !e.package;
    BOOL ok = folder || (_canChooseFiles && [self _bn_typeAllowed:e.url]);
    id<NSOpenSavePanelDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(panel:shouldEnableURL:)]) ok = [d panel:self shouldEnableURL:e.url];
    return ok;
}
- (BOOL)_bn_choosable:(BNFileEntry *)e {
    if (!e.enabled) return NO;
    BOOL folder = e.directory && !e.package;
    return folder ? _canChooseDirectories : _canChooseFiles;
}

- (BOOL)_bn_accept {
    NSMutableArray<NSURL *> *chosen = [NSMutableArray array];
    NSArray<BNFileEntry *> *sel = [_list.selection objectsIn:_list.entries];
    /* One folder selected that cannot be chosen: go into it. */
    if (sel.count == 1 && sel[0].directory && !sel[0].package && !_canChooseDirectories) {
        self.directoryURL = sel[0].url;
        return NO;
    }
    for (BNFileEntry *e in sel)
        if ([self _bn_choosable:e]) [chosen addObject:e.url];
    if (!sel.count && _canChooseDirectories) [chosen addObject:self.directoryURL];
    if (!chosen.count) return NO;
    for (NSURL *u in chosen)
        if (![self _bn_validate:u]) return NO;
    _urls = [chosen copy];
    return YES;
}
- (void)ok:(id)sender {
    if (![self _bn_accept]) {
        if (!_list.selection.count || !((BNFileEntry *)[_list.selection objectsIn:_list.entries].firstObject).directory) NSBeep();
        return;
    }
    [self _bn_finish:NSModalResponseOK];
}
- (void)_bn_prepare {
    _urls = @[];
    [super _bn_prepare];
}
@end
