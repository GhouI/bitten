#import "FoundationInternal.h"
#include <dirent.h>
#include <pwd.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

NSFileAttributeKey const NSFileSize = @"NSFileSize";
NSFileAttributeKey const NSFileType = @"NSFileType";
NSFileAttributeKey const NSFileModificationDate = @"NSFileModificationDate";
NSFileAttributeKey const NSFileCreationDate = @"NSFileCreationDate";
NSFileAttributeKey const NSFilePosixPermissions = @"NSFilePosixPermissions";
NSFileAttributeKey const NSFileOwnerAccountID = @"NSFileOwnerAccountID";
NSFileAttributeKey const NSFileGroupOwnerAccountID = @"NSFileGroupOwnerAccountID";
NSString *const NSFileTypeRegular = @"NSFileTypeRegular";
NSString *const NSFileTypeDirectory = @"NSFileTypeDirectory";
NSString *const NSFileTypeSymbolicLink = @"NSFileTypeSymbolicLink";
NSString *const NSFileTypeUnknown = @"NSFileTypeUnknown";
NSString *const NSFileTypeSocket = @"NSFileTypeSocket";
NSString *const NSFileTypeCharacterSpecial = @"NSFileTypeCharacterSpecial";
NSString *const NSFileTypeBlockSpecial = @"NSFileTypeBlockSpecial";

void BNSetPOSIXError(NSError **error, NSString *path, BOOL reading) {
    if (!error) return;
    int e = errno;
    NSInteger code = reading ? (e == ENOENT ? NSFileReadNoSuchFileError : e == EACCES ? NSFileReadNoPermissionError : NSFileReadUnknownError)
                             : (e == ENOENT ? NSFileNoSuchFileError : e == EACCES ? NSFileWriteNoPermissionError
                                : e == EEXIST ? NSFileWriteFileExistsError : NSFileWriteUnknownError);
    NSError *underlying = [NSError errorWithDomain:NSPOSIXErrorDomain code:e userInfo:nil];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSUnderlyingErrorKey] = underlying;
    if (path) info[NSFilePathErrorKey] = path;
    info[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"The file “%@” couldn’t be %s: %s.",
                                       path.lastPathComponent ?: @"", reading ? "opened" : "saved", strerror(e)];
    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:info];
}

static const char *FS(NSString *path) { return path.fileSystemRepresentation; }

@implementation NSFileManager
+ (NSFileManager *)defaultManager {
    static NSFileManager *shared;
    @synchronized(self) {
        if (!shared) shared = [NSFileManager new];
    }
    return shared;
}
- (NSString *)currentDirectoryPath {
    char buf[4096];
    return getcwd(buf, sizeof buf) ? [NSString stringWithUTF8String:buf] : nil;
}
- (BOOL)changeCurrentDirectoryPath:(NSString *)path { return path && chdir(FS(path)) == 0; }
- (BOOL)fileExistsAtPath:(NSString *)path { return [self fileExistsAtPath:path isDirectory:NULL]; }
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    struct stat st;
    if (!path.length || stat(FS(path), &st) != 0) return NO;
    if (isDirectory) *isDirectory = S_ISDIR(st.st_mode);
    return YES;
}
- (BOOL)isReadableFileAtPath:(NSString *)path { return path && access(FS(path), R_OK) == 0; }
- (BOOL)isWritableFileAtPath:(NSString *)path { return path && access(FS(path), W_OK) == 0; }
- (BOOL)isExecutableFileAtPath:(NSString *)path { return path && access(FS(path), X_OK) == 0; }

- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    DIR *dir = path ? opendir(FS(path)) : NULL;
    if (!dir) {
        BNSetPOSIXError(error, path, YES);
        return nil;
    }
    NSMutableArray *names = [NSMutableArray array];
    for (struct dirent *e; (e = readdir(dir));) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        NSString *name = [NSString stringWithUTF8String:e->d_name];
        if (name) [names addObject:name];
    }
    closedir(dir);
    return names;
}
- (NSArray<NSString *> *)subpathsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    NSArray *top = [self contentsOfDirectoryAtPath:path error:error];
    if (!top) return nil;
    NSMutableArray *all = [NSMutableArray array];
    for (NSString *name in [top sortedArrayUsingSelector:@selector(compare:)]) {
        [all addObject:name];
        NSString *full = [path stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(FS(full), &st) == 0 && S_ISDIR(st.st_mode)) {
            for (NSString *sub in [self subpathsOfDirectoryAtPath:full error:NULL])
                [all addObject:[name stringByAppendingPathComponent:sub]];
        }
    }
    return all;
}
- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)intermediates attributes:(NSDictionary *)attributes error:(NSError **)error {
    uint16_t mode = attributes[NSFilePosixPermissions] ? (uint16_t)[attributes[NSFilePosixPermissions] intValue] : 0755;
    if (!path.length) { errno = ENOENT; BNSetPOSIXError(error, path, NO); return NO; }
    if (intermediates) {
        NSString *parent = path.stringByDeletingLastPathComponent;
        BOOL isDir = NO;
        if (parent.length && ![parent isEqualToString:path] && ![self fileExistsAtPath:parent isDirectory:&isDir]) {
            if (![self createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:attributes error:error]) return NO;
        }
        if ([self fileExistsAtPath:path isDirectory:&isDir] && isDir) return YES;
    }
    if (mkdir(FS(path), mode) != 0) {
        BNSetPOSIXError(error, path, NO);
        return NO;
    }
    return YES;
}
- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attributes {
    if (!path || !BNWriteFile(FS(path), data.bytes, data.length, YES)) return NO;
    if (attributes[NSFilePosixPermissions]) chmod(FS(path), (uint16_t)[attributes[NSFilePosixPermissions] intValue]);
    return YES;
}
- (NSData *)contentsAtPath:(NSString *)path { return [NSData dataWithContentsOfFile:path]; }
/* Files compare by their bytes, symbolic links by where they point and
 * directories by their entries, recursively. */
- (BOOL)contentsEqualAtPath:(NSString *)path1 andPath:(NSString *)path2 {
    struct stat a, b;
    if (lstat(path1.fileSystemRepresentation, &a) || lstat(path2.fileSystemRepresentation, &b)) return NO;
    if ((a.st_mode & S_IFMT) != (b.st_mode & S_IFMT)) return NO;
    if (a.st_dev == b.st_dev && a.st_ino == b.st_ino) return YES;
    switch (a.st_mode & S_IFMT) {
    case S_IFREG: {
        if (a.st_size != b.st_size) return NO;
        NSData *x = [NSData dataWithContentsOfFile:path1], *y = [NSData dataWithContentsOfFile:path2];
        return x && y && [x isEqualToData:y];
    }
    case S_IFLNK: {
        NSString *x = [self destinationOfSymbolicLinkAtPath:path1 error:NULL];
        NSString *y = [self destinationOfSymbolicLinkAtPath:path2 error:NULL];
        return x && y && [x isEqualToString:y];
    }
    case S_IFDIR: {
        NSArray *x = [[self contentsOfDirectoryAtPath:path1 error:NULL] sortedArrayUsingSelector:@selector(compare:)];
        NSArray *y = [[self contentsOfDirectoryAtPath:path2 error:NULL] sortedArrayUsingSelector:@selector(compare:)];
        if (!x || !y || ![x isEqualToArray:y]) return NO;
        for (NSString *name in x)
            if (![self contentsEqualAtPath:[path1 stringByAppendingPathComponent:name]
                                   andPath:[path2 stringByAppendingPathComponent:name]])
                return NO;
        return YES;
    }
    default: return a.st_rdev == b.st_rdev;
    }
}
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
    struct stat st;
    if (!path || lstat(FS(path), &st) != 0) {
        if (!path) errno = ENOENT;
        BNSetPOSIXError(error, path, NO);
        return NO;
    }
    if (S_ISDIR(st.st_mode)) {
        for (NSString *name in [self contentsOfDirectoryAtPath:path error:NULL])
            if (![self removeItemAtPath:[path stringByAppendingPathComponent:name] error:error]) return NO;
        if (rmdir(FS(path)) != 0) { BNSetPOSIXError(error, path, NO); return NO; }
        return YES;
    }
    if (unlink(FS(path)) != 0) { BNSetPOSIXError(error, path, NO); return NO; }
    return YES;
}
- (BOOL)copyItemAtPath:(NSString *)source toPath:(NSString *)destination error:(NSError **)error {
    struct stat st;
    if (!source || !destination || lstat(FS(source), &st) != 0) {
        if (!source || !destination) errno = ENOENT;
        BNSetPOSIXError(error, source, YES);
        return NO;
    }
    if (lstat(FS(destination), &(struct stat){0}) == 0) {
        errno = EEXIST;
        BNSetPOSIXError(error, destination, NO);
        return NO;
    }
    if (S_ISDIR(st.st_mode)) {
        if (mkdir(FS(destination), st.st_mode & 07777) != 0) { BNSetPOSIXError(error, destination, NO); return NO; }
        for (NSString *name in [self contentsOfDirectoryAtPath:source error:NULL])
            if (![self copyItemAtPath:[source stringByAppendingPathComponent:name]
                               toPath:[destination stringByAppendingPathComponent:name] error:error]) return NO;
        return YES;
    }
    if (S_ISLNK(st.st_mode)) {
        char target[4096];
        ssize_t n = readlink(FS(source), target, sizeof target - 1);
        if (n < 0) { BNSetPOSIXError(error, source, YES); return NO; }
        target[n] = 0;
        if (symlink(target, FS(destination)) != 0) { BNSetPOSIXError(error, destination, NO); return NO; }
        return YES;
    }
    size_t length = 0;
    void *bytes = BNReadFile(FS(source), &length);
    if (!bytes) { BNSetPOSIXError(error, source, YES); return NO; }
    BOOL ok = BNWriteFile(FS(destination), bytes, length, NO);
    free(bytes);
    if (!ok) { BNSetPOSIXError(error, destination, NO); return NO; }
    chmod(FS(destination), st.st_mode & 07777);
    return YES;
}
- (BOOL)moveItemAtPath:(NSString *)source toPath:(NSString *)destination error:(NSError **)error {
    if (!source || !destination) { errno = ENOENT; BNSetPOSIXError(error, source, NO); return NO; }
    if (lstat(FS(destination), &(struct stat){0}) == 0) {
        errno = EEXIST;
        BNSetPOSIXError(error, destination, NO);
        return NO;
    }
    if (rename(FS(source), FS(destination)) == 0) return YES;
    /* across file systems: copy, then remove */
    if (![self copyItemAtPath:source toPath:destination error:error]) return NO;
    return [self removeItemAtPath:source error:error];
}
- (BOOL)createSymbolicLinkAtPath:(NSString *)path withDestinationPath:(NSString *)destination error:(NSError **)error {
    if (path && destination && symlink(FS(destination), FS(path)) == 0) return YES;
    BNSetPOSIXError(error, path, NO);
    return NO;
}
- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error {
    char target[4096];
    ssize_t n = path ? readlink(FS(path), target, sizeof target - 1) : -1;
    if (n < 0) { BNSetPOSIXError(error, path, YES); return nil; }
    target[n] = 0;
    return [NSString stringWithUTF8String:target];
}
- (NSDictionary<NSFileAttributeKey, id> *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error {
    struct stat st;
    if (!path || lstat(FS(path), &st) != 0) {
        if (!path) errno = ENOENT;
        BNSetPOSIXError(error, path, YES);
        return nil;
    }
    NSString *type = S_ISDIR(st.st_mode) ? NSFileTypeDirectory : S_ISREG(st.st_mode) ? NSFileTypeRegular
                   : S_ISLNK(st.st_mode) ? NSFileTypeSymbolicLink : S_ISSOCK(st.st_mode) ? NSFileTypeSocket
                   : S_ISCHR(st.st_mode) ? NSFileTypeCharacterSpecial : S_ISBLK(st.st_mode) ? NSFileTypeBlockSpecial
                   : NSFileTypeUnknown;
    NSTimeInterval m = (NSTimeInterval)st.st_mtimespec.tv_sec + (NSTimeInterval)st.st_mtimespec.tv_nsec / 1e9;
    NSTimeInterval b = (NSTimeInterval)st.st_birthtimespec.tv_sec + (NSTimeInterval)st.st_birthtimespec.tv_nsec / 1e9;
    return @{NSFileSize: @((unsigned long long)st.st_size), NSFileType: type,
             NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:m],
             NSFileCreationDate: [NSDate dateWithTimeIntervalSince1970:b],
             NSFilePosixPermissions: @((unsigned)(st.st_mode & 07777)),
             NSFileOwnerAccountID: @(st.st_uid), NSFileGroupOwnerAccountID: @(st.st_gid)};
}
/* Permissions, owner and dates; other attributes have no equivalent here. */
- (BOOL)setAttributes:(NSDictionary<NSFileAttributeKey, id> *)attributes ofItemAtPath:(NSString *)path
                error:(NSError **)error {
    const char *p = FS(path);
    if (attributes[NSFilePosixPermissions] && chmod(p, (mode_t)[attributes[NSFilePosixPermissions] unsignedIntValue])) {
        BNSetPOSIXError(error, path, YES);
        return NO;
    }
    if (attributes[NSFileOwnerAccountID] || attributes[NSFileGroupOwnerAccountID]) {
        uid_t u = attributes[NSFileOwnerAccountID] ? [attributes[NSFileOwnerAccountID] unsignedIntValue] : (uid_t)-1;
        gid_t g = attributes[NSFileGroupOwnerAccountID] ? [attributes[NSFileGroupOwnerAccountID] unsignedIntValue] : (gid_t)-1;
        if (lchown(p, u, g)) {
            BNSetPOSIXError(error, path, YES);
            return NO;
        }
    }
    NSDate *m = attributes[NSFileModificationDate];
    if (m) {
        struct timeval tv[2];
        double t = m.timeIntervalSince1970;
        tv[0].tv_sec = tv[1].tv_sec = (time_t)t;
        tv[0].tv_usec = tv[1].tv_usec = (suseconds_t)((t - (double)(time_t)t) * 1e6);
        if (utimes(p, tv)) {
            BNSetPOSIXError(error, path, YES);
            return NO;
        }
    }
    return YES;
}
/* The name to show for a file: its last component, without the extension
 * for applications. */
- (NSString *)displayNameAtPath:(NSString *)path {
    NSString *name = path.lastPathComponent;
    if ([name.pathExtension isEqualToString:@"app"]) return name.stringByDeletingPathExtension;
    return name;
}
- (NSURL *)temporaryDirectory { return [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]; }
- (NSURL *)homeDirectoryForCurrentUser { return [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES]; }
- (NSArray<NSURL *> *)URLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domainMask {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *p in NSSearchPathForDirectoriesInDomains(directory, domainMask, YES))
        [out addObject:[NSURL fileURLWithPath:p isDirectory:YES]];
    return out;
}
- (NSURL *)URLForDirectory:(NSSearchPathDirectory)directory inDomain:(NSSearchPathDomainMask)domain
         appropriateForURL:(NSURL *)url create:(BOOL)shouldCreate error:(NSError **)error {
    NSString *path;
    if (directory == NSItemReplacementDirectory) {
        path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                           [NSString stringWithFormat:@"TemporaryItems/%@", [NSUUID UUID].UUIDString]];
        shouldCreate = YES;
    } else {
        path = NSSearchPathForDirectoriesInDomains(directory, domain, YES).firstObject;
    }
    if (!path) {
        errno = ENOENT;
        BNSetPOSIXError(error, nil, YES);
        return nil;
    }
    if (shouldCreate && ![self createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    return [NSURL fileURLWithPath:path isDirectory:YES];
}
- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)intermediates
                  attributes:(NSDictionary *)attributes error:(NSError **)error {
    return [self createDirectoryAtPath:url.path withIntermediateDirectories:intermediates attributes:attributes error:error];
}
- (BOOL)removeItemAtURL:(NSURL *)url error:(NSError **)error { return [self removeItemAtPath:url.path error:error]; }
- (BOOL)copyItemAtURL:(NSURL *)src toURL:(NSURL *)dst error:(NSError **)error {
    return [self copyItemAtPath:src.path toPath:dst.path error:error];
}
- (BOOL)moveItemAtURL:(NSURL *)src toURL:(NSURL *)dst error:(NSError **)error {
    return [self moveItemAtPath:src.path toPath:dst.path error:error];
}
- (NSArray<NSURL *> *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys
                                       options:(NSDirectoryEnumerationOptions)mask error:(NSError **)error {
    NSArray *names = [self contentsOfDirectoryAtPath:url.path error:error];
    if (!names) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in names) {
        if ((mask & NSDirectoryEnumerationSkipsHiddenFiles) && [n hasPrefix:@"."]) continue;
        [out addObject:[url URLByAppendingPathComponent:n]];
    }
    return out;
}
@end

/* The standard directories, rooted at $HOME for the user domain. */
NSArray<NSString *> *NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory directory, NSSearchPathDomainMask mask,
                                                         BOOL expandTilde) {
    NSString *sub = nil;
    switch (directory) {
    case NSApplicationDirectory: sub = @"Applications"; break;
    case NSDemoApplicationDirectory: sub = @"Applications/Demos"; break;
    case NSDeveloperApplicationDirectory: sub = @"Developer/Applications"; break;
    case NSAdminApplicationDirectory: sub = @"Applications/Utilities"; break;
    case NSLibraryDirectory: sub = @"Library"; break;
    case NSDeveloperDirectory: sub = @"Developer"; break;
    case NSDocumentationDirectory: sub = @"Library/Documentation"; break;
    case NSDocumentDirectory: sub = @"Documents"; break;
    case NSAutosavedInformationDirectory: sub = @"Library/Autosave Information"; break;
    case NSDesktopDirectory: sub = @"Desktop"; break;
    case NSCachesDirectory: sub = @"Library/Caches"; break;
    case NSApplicationSupportDirectory: sub = @"Library/Application Support"; break;
    case NSDownloadsDirectory: sub = @"Downloads"; break;
    case NSInputMethodsDirectory: sub = @"Library/Input Methods"; break;
    case NSMoviesDirectory: sub = @"Movies"; break;
    case NSMusicDirectory: sub = @"Music"; break;
    case NSPicturesDirectory: sub = @"Pictures"; break;
    case NSSharedPublicDirectory: sub = @"Public"; break;
    case NSPreferencePanesDirectory: sub = @"Library/PreferencePanes"; break;
    case NSApplicationScriptsDirectory: sub = @"Library/Application Scripts"; break;
    case NSTrashDirectory: sub = @".Trash"; break;
    case NSAllApplicationsDirectory: sub = @"Applications"; break;
    case NSAllLibrariesDirectory: sub = @"Library"; break;
    default: return @[];
    }
    NSMutableArray *out = [NSMutableArray array];
    if (mask & NSUserDomainMask)
        [out addObject:expandTilde ? [NSHomeDirectory() stringByAppendingPathComponent:sub]
                                   : [@"~" stringByAppendingPathComponent:sub]];
    if ((mask & NSLocalDomainMask) && directory != NSTrashDirectory) [out addObject:[@"/" stringByAppendingString:sub]];
    if ((mask & NSSystemDomainMask) && [sub hasPrefix:@"Library"]) [out addObject:[@"/System/" stringByAppendingString:sub]];
    return out;
}

@implementation NSString (Files)
/* The inverse of pathComponents: a leading "/" makes the path absolute. */
+ (NSString *)pathWithComponents:(NSArray<NSString *> *)components {
    NSMutableString *out = [NSMutableString string];
    for (NSString *c in components) {
        if ([c isEqualToString:@"/"]) {
            if (!out.length) [out appendString:@"/"];
            continue;
        }
        if (!c.length) continue;
        if (out.length && ![out hasSuffix:@"/"]) [out appendString:@"/"];
        [out appendString:c];
    }
    return out;
}
- (const char *)fileSystemRepresentation { return self.UTF8String; }
- (BOOL)isAbsolutePath { return [self hasPrefix:@"/"] || [self hasPrefix:@"~"]; }
- (NSArray<NSString *> *)pathComponents {
    NSMutableArray *parts = [NSMutableArray array];
    if ([self hasPrefix:@"/"]) [parts addObject:@"/"];
    for (NSString *p in [self componentsSeparatedByString:@"/"]) if (p.length) [parts addObject:p];
    if (self.length > 1 && [self hasSuffix:@"/"]) [parts addObject:@"/"];
    return parts;
}
- (NSString *)stringByExpandingTildeInPath {
    if (![self hasPrefix:@"~"]) return [self copy];
    NSRange slash = [self rangeOfString:@"/"];
    NSString *user = slash.location == NSNotFound ? [self substringFromIndex:1] : [self substringWithRange:NSMakeRange(1, slash.location - 1)];
    NSString *rest = slash.location == NSNotFound ? @"" : [self substringFromIndex:slash.location];
    NSString *home = user.length ? nil : NSHomeDirectory();
    if (user.length) {
        struct passwd *pw = getpwnam(user.UTF8String);
        if (pw && pw->pw_dir) home = [NSString stringWithUTF8String:pw->pw_dir];
    }
    return home ? [home stringByAppendingString:rest] : [self copy];
}
- (NSString *)stringByStandardizingPath {
    NSString *s = self.stringByExpandingTildeInPath;
    BOOL absolute = [s hasPrefix:@"/"];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *part in [s componentsSeparatedByString:@"/"]) {
        if (!part.length || [part isEqualToString:@"."]) continue;
        if ([part isEqualToString:@".."]) {
            if (out.count && ![out.lastObject isEqualToString:@".."]) [out removeLastObject];
            else if (!absolute) [out addObject:part];
            continue;
        }
        [out addObject:part];
    }
    NSString *joined = [out componentsJoinedByString:@"/"];
    return absolute ? [@"/" stringByAppendingString:joined] : joined;
}
+ (instancetype)stringWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error {
    return [[self alloc] initWithContentsOfFile:path encoding:enc error:error];
}
- (instancetype)initWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error {
    size_t length = 0;
    void *bytes = path ? BNReadFile(path.fileSystemRepresentation, &length) : NULL;
    if (!bytes) {
        if (!path) errno = ENOENT;
        BNSetPOSIXError(error, path, YES);
        return nil;
    }
    NSString *s = [self initWithBytes:bytes length:length encoding:enc];
    free(bytes);
    if (!s && error)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInapplicableStringEncodingError
                                 userInfo:@{NSFilePathErrorKey: path}];
    return s;
}
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically encoding:(NSStringEncoding)enc error:(NSError **)error {
    NSData *data = [self dataUsingEncoding:enc];
    if (!data || !path || !BNWriteFile(path.fileSystemRepresentation, data.bytes, data.length, atomically)) {
        if (!data) errno = EINVAL;
        BNSetPOSIXError(error, path, NO);
        return NO;
    }
    return YES;
}
@end
