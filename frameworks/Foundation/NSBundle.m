/* NSBundle: a directory with an Info.plist and resources. macOS bundles keep
 * those under Contents/ (Contents/Info.plist, Contents/Resources,
 * Contents/MacOS/<executable>); flat bundles keep them at the top. The main
 * bundle is the .app around the running executable. */
#import "FoundationInternal.h"
#include <sys/stat.h>

int _NSGetExecutablePath(char *buf, uint32_t *size);

static NSMutableDictionary<NSString *, NSBundle *> *bundles_by_path;

static BOOL is_dir(NSString *path) {
    struct stat st;
    return stat(path.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode);
}
static BOOL exists(NSString *path) {
    struct stat st;
    return stat(path.fileSystemRepresentation, &st) == 0;
}

/* Parses an old-style .strings file: "key" = "value"; with comments. */
static NSDictionary *parse_strings_text(NSString *text) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSUInteger n = text.length, i = 0;
    unichar *c = malloc((n + 1) * sizeof(unichar));
    [text getCharacters:c range:NSMakeRange(0, n)];
    NSString *pending_key = nil;
    while (i < n) {
        unichar ch = c[i];
        if (ch == '/' && i + 1 < n && c[i + 1] == '*') {
            i += 2;
            while (i + 1 < n && !(c[i] == '*' && c[i + 1] == '/')) i++;
            i += 2;
        } else if (ch == '/' && i + 1 < n && c[i + 1] == '/') {
            while (i < n && c[i] != '\n') i++;
        } else if (ch == '"') {
            NSMutableString *s = [NSMutableString string];
            i++;
            while (i < n && c[i] != '"') {
                unichar u = c[i++];
                if (u == '\\' && i < n) {
                    u = c[i++];
                    if (u == 'n') u = '\n';
                    else if (u == 't') u = '\t';
                    else if (u == 'r') u = '\r';
                    else if (u == 'U' || u == 'u') {
                        unsigned v = 0;
                        for (int k = 0; k < 4 && i < n; k++, i++) {
                            unichar h = c[i];
                            v = v * 16 + (h <= '9' ? h - '0' : (h | 0x20) - 'a' + 10);
                        }
                        u = (unichar)v;
                    }
                }
                [s appendString:[NSString stringWithCharacters:&u length:1]];
            }
            i++;
            if (pending_key) {
                d[pending_key] = s;
                pending_key = nil;
            } else {
                pending_key = s;
            }
        } else if (ch == ';') {
            if (pending_key) d[pending_key] = pending_key; /* "key"; */
            pending_key = nil;
            i++;
        } else {
            i++;
        }
    }
    free(c);
    return d;
}

static NSDictionary *read_table(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    if ([plist isKindOfClass:[NSDictionary class]]) return plist;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
    return text ? parse_strings_text(text) : nil;
}

@implementation NSBundle {
    NSString *_path, *_contents, *_executablePath;
    NSDictionary *_info;
    NSMutableDictionary *_tables;
    BOOL _main;
}

+ (NSBundle *)mainBundle {
    static NSBundle *main;
    @synchronized(self) {
        if (!main) {
            char buf[4096];
            uint32_t size = sizeof buf;
            NSString *exe = _NSGetExecutablePath(buf, &size) == 0 ? [NSString stringWithUTF8String:buf] : @"/";
            NSString *dir = exe.stringByDeletingLastPathComponent;
            NSString *path = dir;
            if ([dir.lastPathComponent isEqualToString:@"MacOS"] &&
                [dir.stringByDeletingLastPathComponent.lastPathComponent isEqualToString:@"Contents"])
                path = dir.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
            main = [[NSBundle alloc] initWithPath:path];
            main->_executablePath = exe;
            main->_main = YES;
        }
    }
    return main;
}

+ (NSBundle *)bundleWithPath:(NSString *)path { return [[self alloc] initWithPath:path]; }
+ (NSBundle *)bundleWithURL:(NSURL *)url { return url.isFileURL ? [self bundleWithPath:url.path] : nil; }
+ (NSBundle *)bundleForClass:(Class)cls { return [self mainBundle]; }
+ (NSBundle *)bundleWithIdentifier:(NSString *)identifier {
    if ([[self mainBundle].bundleIdentifier isEqualToString:identifier]) return [self mainBundle];
    @synchronized([NSBundle class]) {
        for (NSBundle *b in bundles_by_path.allValues)
            if ([b.bundleIdentifier isEqualToString:identifier]) return b;
    }
    return nil;
}
+ (NSArray<NSBundle *> *)allBundles { return @[ [self mainBundle] ]; }
+ (NSArray<NSBundle *> *)allFrameworks { return @[]; }

- (instancetype)initWithPath:(NSString *)path {
    if (!path || !is_dir(path)) return nil;
    path = path.stringByStandardizingPath;
    @synchronized([NSBundle class]) {
        if (!bundles_by_path) bundles_by_path = [NSMutableDictionary dictionary];
        NSBundle *existing = bundles_by_path[path];
        if (existing) return existing;
        if (!(self = [super init])) return nil;
        _path = [path copy];
        NSString *contents = [path stringByAppendingPathComponent:@"Contents"];
        _contents = is_dir(contents) ? contents : _path;
        _tables = [NSMutableDictionary dictionary];
        bundles_by_path[path] = self;
    }
    return self;
}
- (instancetype)initWithURL:(NSURL *)url { return url.isFileURL ? [self initWithPath:url.path] : nil; }

- (NSString *)bundlePath { return _path; }
- (NSURL *)bundleURL { return [NSURL fileURLWithPath:_path isDirectory:YES]; }
- (NSString *)resourcePath {
    if (_contents == _path) return _path;
    return [_contents stringByAppendingPathComponent:@"Resources"];
}
- (NSURL *)resourceURL { return [NSURL fileURLWithPath:self.resourcePath isDirectory:YES]; }
- (NSString *)executablePath {
    if (_executablePath) return _executablePath;
    NSString *name = self.infoDictionary[@"CFBundleExecutable"];
    if (!name) return nil;
    NSString *p = _contents == _path ? [_path stringByAppendingPathComponent:name]
                                     : [[_contents stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:name];
    return exists(p) ? p : nil;
}
- (NSURL *)executableURL {
    NSString *p = self.executablePath;
    return p ? [NSURL fileURLWithPath:p] : nil;
}
- (NSString *)privateFrameworksPath { return [_contents stringByAppendingPathComponent:@"Frameworks"]; }
- (NSURL *)privateFrameworksURL { return [NSURL fileURLWithPath:self.privateFrameworksPath isDirectory:YES]; }
- (NSString *)sharedFrameworksPath { return [_contents stringByAppendingPathComponent:@"SharedFrameworks"]; }
- (NSString *)builtInPlugInsPath { return [_contents stringByAppendingPathComponent:@"PlugIns"]; }
- (NSURL *)builtInPlugInsURL { return [NSURL fileURLWithPath:self.builtInPlugInsPath isDirectory:YES]; }
- (NSURL *)appStoreReceiptURL {
    return [NSURL fileURLWithPath:[_contents stringByAppendingPathComponent:@"_MASReceipt/receipt"]];
}

- (NSDictionary<NSString *, id> *)infoDictionary {
    @synchronized(self) {
        if (!_info) {
            NSData *data = [NSData dataWithContentsOfFile:[_contents stringByAppendingPathComponent:@"Info.plist"]];
            id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
            _info = [plist isKindOfClass:[NSDictionary class]] ? plist : @{};
        }
        return _info;
    }
}
- (NSDictionary<NSString *, id> *)localizedInfoDictionary {
    NSMutableDictionary *d = [self.infoDictionary mutableCopy];
    NSDictionary *loc = [self _table:@"InfoPlist"];
    if (loc) [d addEntriesFromDictionary:loc];
    return d;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    id v = [self _table:@"InfoPlist"][key];
    return v ?: self.infoDictionary[key];
}
- (NSString *)bundleIdentifier { return self.infoDictionary[@"CFBundleIdentifier"]; }
- (NSString *)developmentLocalization { return self.infoDictionary[@"CFBundleDevelopmentRegion"] ?: @"en"; }
- (NSArray<NSString *> *)localizations {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.resourcePath error:NULL])
        if ([f.pathExtension isEqualToString:@"lproj"]) [out addObject:f.stringByDeletingPathExtension];
    return out;
}
- (NSArray<NSString *> *)preferredLocalizations { return @[ self.developmentLocalization ]; }
- (Class)principalClass {
    NSString *name = self.infoDictionary[@"NSPrincipalClass"];
    return name ? NSClassFromString(name) : nil;
}
- (BOOL)load { return YES; }
- (BOOL)isLoaded { return YES; }
- (BOOL)loadAndReturnError:(NSError **)error { return YES; }
- (BOOL)unload { return NO; }

/* ---- resources ---- */

- (NSArray<NSString *> *)_searchDirectories:(NSString *)subpath {
    NSString *base = self.resourcePath;
    if (subpath.length) base = [base stringByAppendingPathComponent:subpath];
    NSString *dev = [self.developmentLocalization stringByAppendingPathExtension:@"lproj"];
    return @[ base, [base stringByAppendingPathComponent:dev], [base stringByAppendingPathComponent:@"Base.lproj"] ];
}
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext inDirectory:(NSString *)subpath {
    NSString *file = name ?: @"";
    if (ext.length) file = [file stringByAppendingPathExtension:ext];
    if (!file.length) return nil;
    for (NSString *dir in [self _searchDirectories:subpath]) {
        NSString *p = [dir stringByAppendingPathComponent:file];
        if (exists(p)) return p;
    }
    return nil;
}
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext {
    return [self pathForResource:name ofType:ext inDirectory:nil];
}
- (NSArray<NSString *> *)pathsForResourcesOfType:(NSString *)ext inDirectory:(NSString *)subpath {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *dir in [self _searchDirectories:subpath])
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL])
            if (!ext.length || [f.pathExtension isEqualToString:ext]) [out addObject:[dir stringByAppendingPathComponent:f]];
    return out;
}
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)ext subdirectory:(NSString *)subpath {
    NSString *p = [self pathForResource:name ofType:ext inDirectory:subpath];
    return p ? [NSURL fileURLWithPath:p] : nil;
}
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)ext {
    return [self URLForResource:name withExtension:ext subdirectory:nil];
}
- (NSArray<NSURL *> *)URLsForResourcesWithExtension:(NSString *)ext subdirectory:(NSString *)subpath {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *p in [self pathsForResourcesOfType:ext inDirectory:subpath]) [out addObject:[NSURL fileURLWithPath:p]];
    return out;
}

- (NSDictionary *)_table:(NSString *)table {
    @synchronized(self) {
        id cached = _tables[table];
        if (cached) return cached == [NSNull null] ? nil : cached;
        NSString *p = [self pathForResource:table ofType:@"strings"];
        NSDictionary *d = p ? read_table(p) : nil;
        _tables[table] = d ?: (id)[NSNull null];
        return d;
    }
}
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
    if (!key) return value ?: @"";
    NSString *s = [self _table:table.length ? table : @"Localizable"][key];
    if ([s isKindOfClass:[NSString class]]) return s;
    return value.length ? value : key;
}
- (NSString *)description { return [NSString stringWithFormat:@"NSBundle <%@>%@", _path, _main ? @" (loaded)" : @""]; }
@end
