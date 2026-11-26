#import "FoundationInternal.h"
#include <unistd.h>

/* Components of a parsed URL (strong references: the pieces are fresh
 * substrings that nothing else keeps alive). */
@interface BNURLParts : NSObject {
  @public
    NSString *scheme, *host, *path, *query, *fragment;
    NSInteger port;
}
@end
@implementation BNURLParts
@end

static NSString *percent_decode(NSString *s) {
    const char *in = s.UTF8String;
    if (!in || !strchr(in, '%')) return s;
    size_t n = strlen(in), o = 0;
    char *out = malloc(n + 1);
    for (size_t i = 0; i < n; i++) {
        if (in[i] == '%' && i + 2 < n + 0 && in[i + 1] && in[i + 2]) {
            char hex[3] = {in[i + 1], in[i + 2], 0};
            char *end;
            long v = strtol(hex, &end, 16);
            if (end == hex + 2) {
                out[o++] = (char)v;
                i += 2;
                continue;
            }
        }
        out[o++] = in[i];
    }
    out[o] = 0;
    NSString *r = [NSString stringWithUTF8String:out];
    free(out);
    return r ?: s;
}

static NSString *percent_encode_path(NSString *path) {
    const unsigned char *in = (const unsigned char *)path.UTF8String;
    NSMutableString *out = [NSMutableString string];
    for (; in && *in; in++) {
        unsigned char c = *in;
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || strchr("-._~/!$&'()*+,;=:@", c))
            [out appendFormat:@"%c", c];
        else
            [out appendFormat:@"%%%02X", c];
    }
    return out;
}

/* Split an absolute URL string into its components. */
static BNURLParts *parse(NSString *url) {
    BNURLParts *p = [BNURLParts new];
    p->port = -1;
    NSString *rest = url;
    NSRange hash = [rest rangeOfString:@"#"];
    if (hash.location != NSNotFound) {
        p->fragment = [rest substringFromIndex:hash.location + 1];
        rest = [rest substringToIndex:hash.location];
    }
    NSRange q = [rest rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        p->query = [rest substringFromIndex:q.location + 1];
        rest = [rest substringToIndex:q.location];
    }
    NSRange colon = [rest rangeOfString:@":"];
    NSRange slash = [rest rangeOfString:@"/"];
    if (colon.location != NSNotFound && colon.location > 0 && (slash.location == NSNotFound || colon.location < slash.location)) {
        p->scheme = [rest substringToIndex:colon.location].lowercaseString;
        rest = [rest substringFromIndex:colon.location + 1];
    }
    if ([rest hasPrefix:@"//"]) {
        rest = [rest substringFromIndex:2];
        NSRange end = [rest rangeOfString:@"/"];
        NSString *authority = end.location == NSNotFound ? rest : [rest substringToIndex:end.location];
        rest = end.location == NSNotFound ? @"" : [rest substringFromIndex:end.location];
        NSRange at = [authority rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) authority = [authority substringFromIndex:at.location + 1];
        NSRange port = [authority rangeOfString:@":" options:NSBackwardsSearch];
        if (port.location != NSNotFound && ![authority hasSuffix:@"]"]) {
            p->port = [authority substringFromIndex:port.location + 1].integerValue;
            authority = [authority substringToIndex:port.location];
        }
        if (authority.length) p->host = authority;
    }
    p->path = percent_decode(rest);
    return p;
}

@implementation NSURL (Foundation)
+ (instancetype)URLWithString:(NSString *)string { return [[self alloc] initWithString:string]; }
+ (instancetype)fileURLWithPath:(NSString *)path { return [[self alloc] initFileURLWithPath:path]; }
+ (instancetype)fileURLWithPath:(NSString *)path isDirectory:(BOOL)isDirectory {
    if (isDirectory && ![path hasSuffix:@"/"]) path = [path stringByAppendingString:@"/"];
    return [[self alloc] initFileURLWithPath:path];
}
- (instancetype)initWithString:(NSString *)string {
    if (!string.length) return nil;
    /* spaces and control characters make a string invalid as a URL */
    const char *u = string.UTF8String;
    for (const char *c = u; c && *c; c++)
        if ((unsigned char)*c <= ' ') return nil;
    return (__bridge_transfer id)CFURLCreateWithString(NULL, (__bridge CFStringRef)string, NULL);
}
- (instancetype)initFileURLWithPath:(NSString *)path {
    if (!path) BNRaise("NSInvalidArgumentException", "-[NSURL initFileURLWithPath:]: nil string parameter");
    if (![path hasPrefix:@"/"]) {
        NSString *cwd = [NSFileManager defaultManager].currentDirectoryPath ?: @"/";
        path = [cwd stringByAppendingPathComponent:path];
    }
    NSString *s = [@"file://" stringByAppendingString:percent_encode_path(path)];
    return (__bridge_transfer id)CFURLCreateWithString(NULL, (__bridge CFStringRef)s, NULL);
}
- (NSString *)absoluteString { return (__bridge NSString *)CFURLGetString((__bridge CFURLRef)self); }
- (NSString *)scheme { return parse(self.absoluteString)->scheme; }
- (NSString *)host { return parse(self.absoluteString)->host; }
- (NSNumber *)port { BNURLParts *p = parse(self.absoluteString); return p->port >= 0 ? @(p->port) : nil; }
- (NSString *)query { return parse(self.absoluteString)->query; }
- (NSString *)fragment { return parse(self.absoluteString)->fragment; }
- (NSString *)path {
    NSString *path = parse(self.absoluteString)->path;
    while (path.length > 1 && [path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    return path;
}
- (BOOL)isFileURL { return [self.scheme isEqualToString:@"file"]; }
- (BOOL)checkResourceIsReachableAndReturnError:(NSError **)error {
    if (self.isFileURL && access(self.path.fileSystemRepresentation, F_OK) == 0) return YES;
    if (error) {
        NSInteger code = self.isFileURL ? NSFileReadNoSuchFileError : NSFileReadUnsupportedSchemeError;
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:code
                                 userInfo:@{NSURLErrorKey : self, NSFilePathErrorKey : self.path ?: @""}];
    }
    return NO;
}
- (BOOL)checkPromisedItemIsReachableAndReturnError:(NSError **)error {
    return [self checkResourceIsReachableAndReturnError:error];
}
- (NSString *)lastPathComponent { return self.path.lastPathComponent; }
- (NSString *)pathExtension { return self.path.pathExtension; }
- (NSURL *)URLByAppendingPathComponent:(NSString *)component {
    NSString *s = self.absoluteString, *tail = @"";
    NSRange cut = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (cut.location != NSNotFound) {
        tail = [s substringFromIndex:cut.location];
        s = [s substringToIndex:cut.location];
    }
    if (![s hasSuffix:@"/"]) s = [s stringByAppendingString:@"/"];
    return [NSURL URLWithString:[[s stringByAppendingString:percent_encode_path(component)] stringByAppendingString:tail]];
}
- (NSURL *)URLByDeletingLastPathComponent {
    NSString *s = self.absoluteString;
    NSRange cut = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (cut.location != NSNotFound) s = [s substringToIndex:cut.location];
    while (s.length > 1 && [s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    NSRange slash = [s rangeOfString:@"/" options:NSBackwardsSearch];
    NSRange authority = [s rangeOfString:@"://"];
    if (slash.location == NSNotFound || (authority.location != NSNotFound && slash.location < authority.location + 3)) return self;
    return [NSURL URLWithString:[s substringToIndex:slash.location + 1]];
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return self.absoluteString; }
@end

/* URL resource keys: their values are their names. */
NSString *const NSURLNameKey = @"NSURLNameKey";
NSString *const NSURLLocalizedNameKey = @"NSURLLocalizedNameKey";
NSString *const NSURLIsRegularFileKey = @"NSURLIsRegularFileKey";
NSString *const NSURLIsDirectoryKey = @"NSURLIsDirectoryKey";
NSString *const NSURLIsSymbolicLinkKey = @"NSURLIsSymbolicLinkKey";
NSString *const NSURLIsVolumeKey = @"NSURLIsVolumeKey";
NSString *const NSURLIsPackageKey = @"NSURLIsPackageKey";
NSString *const NSURLIsApplicationKey = @"NSURLIsApplicationKey";
NSString *const NSURLIsHiddenKey = @"NSURLIsHiddenKey";
NSString *const NSURLIsReadableKey = @"NSURLIsReadableKey";
NSString *const NSURLIsWritableKey = @"NSURLIsWritableKey";
NSString *const NSURLIsExecutableKey = @"NSURLIsExecutableKey";
NSString *const NSURLCreationDateKey = @"NSURLCreationDateKey";
NSString *const NSURLContentAccessDateKey = @"NSURLContentAccessDateKey";
NSString *const NSURLContentModificationDateKey = @"NSURLContentModificationDateKey";
NSString *const NSURLAttributeModificationDateKey = @"NSURLAttributeModificationDateKey";
NSString *const NSURLFileSizeKey = @"NSURLFileSizeKey";
NSString *const NSURLFileAllocatedSizeKey = @"NSURLFileAllocatedSizeKey";
NSString *const NSURLTotalFileSizeKey = @"NSURLTotalFileSizeKey";
NSString *const NSURLTotalFileAllocatedSizeKey = @"NSURLTotalFileAllocatedSizeKey";
NSString *const NSURLContentTypeKey = @"NSURLContentTypeKey";
NSString *const NSURLIsExcludedFromBackupKey = @"NSURLIsExcludedFromBackupKey";
NSString *const NSURLPathKey = @"NSURLPathKey";
NSString *const NSURLParentDirectoryURLKey = @"NSURLParentDirectoryURLKey";
NSString *const NSURLFileResourceTypeKey = @"NSURLFileResourceTypeKey";
NSString *const NSURLTypeIdentifierKey = @"NSURLTypeIdentifierKey";
NSString *const NSURLLinkCountKey = @"NSURLLinkCountKey";
NSString *const NSURLFileSecurityKey = @"NSURLFileSecurityKey";
NSString *const NSURLQuarantinePropertiesKey = @"NSURLQuarantinePropertiesKey";
NSString *const NSURLVolumeAvailableCapacityKey = @"NSURLVolumeAvailableCapacityKey";
NSString *const NSURLVolumeTotalCapacityKey = @"NSURLVolumeTotalCapacityKey";
NSString *const NSURLIsUbiquitousItemKey = @"NSURLIsUbiquitousItemKey";
NSString *const NSURLFileProtectionKey = @"NSURLFileProtectionKey";
NSString *const NSURLAddedToDirectoryDateKey = @"NSURLAddedToDirectoryDateKey";
