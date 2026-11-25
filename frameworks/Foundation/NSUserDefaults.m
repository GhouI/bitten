/* NSUserDefaults: layered key/value preferences. Lookups go through the
 * argument domain (-key value on the command line), the application's
 * persistent domain (~/Library/Preferences/<bundle id>.plist), added suites,
 * the global domain, then registered defaults. Writes go to the persistent
 * domain and are saved immediately as an XML property list. */
#import "FoundationInternal.h"

NSString *const NSGlobalDomain = @"NSGlobalDomain";
NSString *const NSArgumentDomain = @"NSArgumentDomain";
NSString *const NSRegistrationDomain = @"NSRegistrationDomain";
NSString *const NSUserDefaultsDidChangeNotification = @"NSUserDefaultsDidChangeNotification";

static NSString *prefs_dir(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"];
}
static NSString *domain_path(NSString *name) {
    return [prefs_dir() stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
}
static NSMutableDictionary *load_domain(NSString *name) {
    NSData *data = [NSData dataWithContentsOfFile:domain_path(name)];
    id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers
                                                                 format:NULL error:NULL]
                    : nil;
    return [plist isKindOfClass:[NSDictionary class]] ? [plist mutableCopy] : [NSMutableDictionary dictionary];
}
static void save_domain(NSString *name, NSDictionary *d) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    if (!data) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:prefs_dir() withIntermediateDirectories:YES attributes:nil error:NULL];
    [data writeToFile:domain_path(name) atomically:YES];
}

static NSDictionary *argument_domain(void) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSArray *args = [NSProcessInfo processInfo].arguments;
    for (NSUInteger i = 1; i + 1 < args.count; i++) {
        NSString *a = args[i];
        if (a.length < 2 || [a characterAtIndex:0] != '-' || [a characterAtIndex:1] == '-') continue;
        NSString *v = args[i + 1];
        NSData *vd = [v dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = [v hasPrefix:@"<"] ? [NSPropertyListSerialization propertyListWithData:vd options:0 format:NULL error:NULL] : nil;
        d[[a substringFromIndex:1]] = parsed ?: v;
        i++;
    }
    return d;
}

@implementation NSUserDefaults {
    NSString *_suite; /* persistent domain this object writes */
    NSMutableDictionary *_domain, *_global, *_registered;
    NSDictionary *_arguments;
    NSMutableArray<NSString *> *_suites;
    NSMutableDictionary<NSString *, NSMutableDictionary *> *_suiteDomains;
    NSMutableDictionary<NSString *, NSDictionary *> *_volatile;
}

static NSUserDefaults *standard;

+ (NSUserDefaults *)standardUserDefaults {
    @synchronized(self) {
        if (!standard) standard = [[NSUserDefaults alloc] init];
        return standard;
    }
}
+ (void)resetStandardUserDefaults {
    @synchronized(self) { standard = nil; }
}

- (instancetype)init { return [self initWithSuiteName:nil]; }
- (instancetype)initWithSuiteName:(NSString *)suite {
    if (!(self = [super init])) return nil;
    if ([suite isEqualToString:NSGlobalDomain]) return nil;
    NSString *app = [NSBundle mainBundle].bundleIdentifier ?: [NSProcessInfo processInfo].processName;
    _suite = [suite ?: app copy];
    _domain = load_domain(_suite);
    _global = load_domain(@".GlobalPreferences");
    _registered = [NSMutableDictionary dictionary];
    _arguments = argument_domain();
    _suites = [NSMutableArray array];
    _suiteDomains = [NSMutableDictionary dictionary];
    _volatile = [NSMutableDictionary dictionary];
    return self;
}
- (instancetype)initWithUser:(NSString *)user { return [self init]; }

- (id)objectForKey:(NSString *)key {
    if (!key) return nil;
    @synchronized(self) {
        id v = _arguments[key];
        if (!v) v = _domain[key];
        for (NSString *s in _suites) {
            if (v) break;
            v = _suiteDomains[s][key];
        }
        if (!v) v = _global[key];
        if (!v) v = _registered[key];
        return v;
    }
}
- (void)_changed {
    save_domain(_suite, _domain);
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}
- (void)setObject:(id)value forKey:(NSString *)key {
    if (!key) return;
    if (!value) {
        [self removeObjectForKey:key];
        return;
    }
    @synchronized(self) {
        if (![NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListXMLFormat_v1_0])
            BNRaise("NSInvalidArgumentException", "Attempt to insert non-property list object %s for key %s",
                    BNDescribe(value).UTF8String, key.UTF8String);
        _domain[key] = [value copy];
    }
    [self _changed];
}
- (void)removeObjectForKey:(NSString *)key {
    if (!key) return;
    @synchronized(self) {
        if (!_domain[key]) return;
        [_domain removeObjectForKey:key];
    }
    [self _changed];
}

- (NSString *)stringForKey:(NSString *)key {
    id v = [self objectForKey:key];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return nil;
}
- (NSArray *)arrayForKey:(NSString *)key {
    id v = [self objectForKey:key];
    return [v isKindOfClass:[NSArray class]] ? v : nil;
}
- (NSDictionary<NSString *, id> *)dictionaryForKey:(NSString *)key {
    id v = [self objectForKey:key];
    return [v isKindOfClass:[NSDictionary class]] ? v : nil;
}
- (NSData *)dataForKey:(NSString *)key {
    id v = [self objectForKey:key];
    return [v isKindOfClass:[NSData class]] ? v : nil;
}
- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key {
    NSArray *a = [self arrayForKey:key];
    for (id e in a)
        if (![e isKindOfClass:[NSString class]]) return nil;
    return a;
}
- (NSInteger)integerForKey:(NSString *)key {
    id v = [self objectForKey:key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}
- (float)floatForKey:(NSString *)key { return (float)[self doubleForKey:key]; }
- (double)doubleForKey:(NSString *)key {
    id v = [self objectForKey:key];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0;
}
- (BOOL)boolForKey:(NSString *)key {
    id v = [self objectForKey:key];
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [v lowercaseString];
        return [s isEqualToString:@"yes"] || [s isEqualToString:@"true"] || [s integerValue] != 0;
    }
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}
- (NSURL *)URLForKey:(NSString *)key {
    id v = [self objectForKey:key];
    if ([v isKindOfClass:[NSURL class]]) return v;
    if ([v isKindOfClass:[NSString class]]) return [NSURL fileURLWithPath:[v stringByExpandingTildeInPath]];
    if ([v isKindOfClass:[NSData class]]) {
        NSString *s = [[NSString alloc] initWithData:v encoding:NSUTF8StringEncoding];
        return s ? [NSURL URLWithString:s] : nil;
    }
    return nil;
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setFloat:(float)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setDouble:(double)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { [self setObject:[NSNumber numberWithBool:value] forKey:key]; }
- (void)setURL:(NSURL *)url forKey:(NSString *)key {
    [self setObject:url ? [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding] : nil forKey:key];
}

- (void)registerDefaults:(NSDictionary<NSString *, id> *)registration {
    @synchronized(self) { [_registered addEntriesFromDictionary:registration]; }
}
- (void)addSuiteNamed:(NSString *)name {
    @synchronized(self) {
        if (!name || [_suites containsObject:name]) return;
        [_suites addObject:name];
        _suiteDomains[name] = load_domain(name);
    }
}
- (void)removeSuiteNamed:(NSString *)name {
    @synchronized(self) {
        [_suites removeObject:name];
        [_suiteDomains removeObjectForKey:name];
    }
}
- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    @synchronized(self) {
        NSMutableDictionary *d = [_registered mutableCopy];
        [d addEntriesFromDictionary:_global];
        for (NSString *s in _suites.reverseObjectEnumerator.allObjects) [d addEntriesFromDictionary:_suiteDomains[s]];
        [d addEntriesFromDictionary:_domain];
        [d addEntriesFromDictionary:_arguments];
        return d;
    }
}
- (NSArray<NSString *> *)volatileDomainNames { return @[ NSArgumentDomain, NSRegistrationDomain ]; }
- (NSDictionary<NSString *, id> *)volatileDomainForName:(NSString *)name {
    if ([name isEqualToString:NSArgumentDomain]) return _arguments;
    if ([name isEqualToString:NSRegistrationDomain]) return [_registered copy];
    return _volatile[name] ?: @{};
}
- (void)setVolatileDomain:(NSDictionary<NSString *, id> *)domain forName:(NSString *)name { _volatile[name] = [domain copy]; }
- (void)removeVolatileDomainForName:(NSString *)name { [_volatile removeObjectForKey:name]; }
- (NSDictionary<NSString *, id> *)persistentDomainForName:(NSString *)name {
    if ([name isEqualToString:_suite]) return [_domain copy];
    return load_domain([name isEqualToString:NSGlobalDomain] ? @".GlobalPreferences" : name);
}
- (void)setPersistentDomain:(NSDictionary<NSString *, id> *)domain forName:(NSString *)name {
    if ([name isEqualToString:_suite]) {
        @synchronized(self) { _domain = [domain mutableCopy]; }
        [self _changed];
        return;
    }
    save_domain([name isEqualToString:NSGlobalDomain] ? @".GlobalPreferences" : name, domain);
}
- (void)removePersistentDomainForName:(NSString *)name { [self setPersistentDomain:@{} forName:name]; }
- (BOOL)objectIsForcedForKey:(NSString *)key { return NO; }
- (BOOL)objectIsForcedForKey:(NSString *)key inDomain:(NSString *)domain { return NO; }
- (BOOL)synchronize {
    @synchronized(self) {
        save_domain(_suite, _domain);
    }
    return YES;
}
@end
