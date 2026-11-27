#import "FoundationInternal.h"
#include <pwd.h>

int sysctlbyname(const char *, void *, size_t *, void *, size_t);

@implementation NSProcessInfo {
    NSString *_processName;
}
+ (NSProcessInfo *)processInfo {
    static NSProcessInfo *shared;
    @synchronized(self) {
        if (!shared) shared = [NSProcessInfo new];
    }
    return shared;
}
- (NSArray<NSString *> *)arguments {
    int argc = *_NSGetArgc();
    char **argv = *_NSGetArgv();
    NSMutableArray *args = [NSMutableArray array];
    for (int i = 0; i < argc; i++) [args addObject:[NSString stringWithUTF8String:argv[i]] ?: @""];
    return args;
}
- (NSDictionary<NSString *, NSString *> *)environment {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    for (char **e = *_NSGetEnviron(); e && *e; e++) {
        const char *eq = strchr(*e, '=');
        if (!eq) continue;
        NSString *key = [[NSString alloc] initWithBytes:*e length:(NSUInteger)(eq - *e) encoding:NSUTF8StringEncoding];
        NSString *value = [NSString stringWithUTF8String:eq + 1];
        if (key && value) env[key] = value;
    }
    return env;
}
- (NSString *)processName { return _processName ?: [NSString stringWithUTF8String:getprogname()]; }
- (void)setProcessName:(NSString *)name { _processName = [name copy]; }
- (int)processIdentifier { return getpid(); }
- (NSString *)hostName {
    char buf[256] = "localhost";
    gethostname(buf, sizeof buf - 1);
    return [NSString stringWithUTF8String:buf];
}
- (NSOperatingSystemVersion)operatingSystemVersion {
    char buf[64] = "15.0";
    size_t len = sizeof buf;
    sysctlbyname("kern.osproductversion", buf, &len, NULL, 0);
    NSArray<NSString *> *parts = [[NSString stringWithUTF8String:buf] componentsSeparatedByString:@"."];
    NSOperatingSystemVersion v = {parts.count > 0 ? parts[0].integerValue : 0, parts.count > 1 ? parts[1].integerValue : 0,
                                  parts.count > 2 ? parts[2].integerValue : 0};
    return v;
}
- (NSString *)operatingSystemVersionString {
    char build[64] = "";
    size_t len = sizeof build;
    sysctlbyname("kern.osversion", build, &len, NULL, 0);
    NSOperatingSystemVersion v = self.operatingSystemVersion;
    return [NSString stringWithFormat:@"Version %ld.%ld (Build %s)", (long)v.majorVersion, (long)v.minorVersion, build];
}
- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)w {
    NSOperatingSystemVersion v = self.operatingSystemVersion;
    if (v.majorVersion != w.majorVersion) return v.majorVersion > w.majorVersion;
    if (v.minorVersion != w.minorVersion) return v.minorVersion > w.minorVersion;
    return v.patchVersion >= w.patchVersion;
}
- (BOOL)isMacCatalystApp { return NO; }
- (BOOL)isiOSAppOnMac { return NO; }
- (NSUInteger)processorCount { long n = sysconf(_SC_NPROCESSORS_ONLN); return n > 0 ? (NSUInteger)n : 1; }
- (NSUInteger)activeProcessorCount { return self.processorCount; }
- (unsigned long long)physicalMemory { long pages = sysconf(_SC_PHYS_PAGES); return pages > 0 ? (unsigned long long)pages * 4096ULL : 0; }
- (NSTimeInterval)systemUptime {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (NSTimeInterval)ts.tv_sec + (NSTimeInterval)ts.tv_nsec / 1e9;
}
- (NSString *)globallyUniqueString {
    return [NSString stringWithFormat:@"%@-%d-%016llX", [NSUUID UUID].UUIDString, getpid(), (unsigned long long)(self.systemUptime * 1e9)];
}
- (NSString *)userName { return NSUserName(); }
- (void)disableAutomaticTermination:(NSString *)reason {}
- (void)enableAutomaticTermination:(NSString *)reason {}
- (void)disableSuddenTermination {}
- (void)enableSuddenTermination {}
- (BOOL)automaticTerminationSupportEnabled { return NO; }
- (void)setAutomaticTerminationSupportEnabled:(BOOL)enabled {}
@end

NSString *NSUserName(void) {
    struct passwd *pw = getpwuid(getuid());
    return pw && pw->pw_name ? [NSString stringWithUTF8String:pw->pw_name] : @"";
}
NSString *NSHomeDirectory(void) {
    const char *home = getenv("HOME");
    if (home && *home) return [NSString stringWithUTF8String:home];
    struct passwd *pw = getpwuid(getuid());
    return pw && pw->pw_dir ? [NSString stringWithUTF8String:pw->pw_dir] : @"/";
}
/* The full name: the GECOS field up to its first comma, or the login. */
NSString *NSFullUserName(void) {
    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_gecos && *pw->pw_gecos) {
        NSString *g = [NSString stringWithUTF8String:pw->pw_gecos];
        NSRange comma = [g rangeOfString:@","];
        if (comma.location != NSNotFound) g = [g substringToIndex:comma.location];
        if (g.length) return g;
    }
    return NSUserName();
}
NSString *NSHomeDirectoryForUser(NSString *user) {
    if (!user.length) return NSHomeDirectory();
    struct passwd *pw = getpwnam(user.UTF8String);
    return pw && pw->pw_dir ? [NSString stringWithUTF8String:pw->pw_dir] : nil;
}
NSString *NSTemporaryDirectory(void) {
    const char *tmp = getenv("TMPDIR");
    NSString *s = [NSString stringWithUTF8String:tmp && *tmp ? tmp : "/tmp"];
    return [s hasSuffix:@"/"] ? s : [s stringByAppendingString:@"/"];
}

@implementation NSUUID {
    uint8_t _bytes[16];
}
+ (instancetype)UUID { return [self new]; }
- (instancetype)init {
    if ((self = [super init])) {
        arc4random_buf(_bytes, 16);
        _bytes[6] = (_bytes[6] & 0x0f) | 0x40; /* version 4 */
        _bytes[8] = (_bytes[8] & 0x3f) | 0x80; /* RFC 4122 variant */
    }
    return self;
}
- (instancetype)initWithUUIDString:(NSString *)string {
    if (!(self = [super init])) return nil;
    const char *s = string.UTF8String;
    int n = 0;
    for (; s && *s && n < 32; s++) {
        int v;
        if (*s == '-') continue;
        if (*s >= '0' && *s <= '9') v = *s - '0';
        else if (*s >= 'a' && *s <= 'f') v = *s - 'a' + 10;
        else if (*s >= 'A' && *s <= 'F') v = *s - 'A' + 10;
        else return nil;
        if (n & 1) _bytes[n / 2] |= (uint8_t)v;
        else _bytes[n / 2] = (uint8_t)(v << 4);
        n++;
    }
    return n == 32 && s && !*s ? self : nil;
}
- (NSString *)UUIDString {
    const uint8_t *b = _bytes;
    return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]];
}
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[NSUUID class]] && !memcmp(((NSUUID *)other)->_bytes, _bytes, 16); }
- (NSUInteger)hash { NSUInteger h; memcpy(&h, _bytes, sizeof h); return h; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return self.UUIDString; }
@end
