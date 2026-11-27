#import "FoundationInternal.h"

static inline CFDictionaryRef CFD(NSDictionary *d) { return (__bridge CFDictionaryRef)d; }
static inline CFMutableDictionaryRef CFMD(NSDictionary *d) { return (__bridge CFMutableDictionaryRef)d; }
static BOOL wants_mutable(id self) { return [self isKindOfClass:[NSMutableDictionary class]]; }

static CFMutableDictionaryRef new_table(void) {
    return CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}
/* Keys are copied, as NSDictionary documents. */
static void put(CFMutableDictionaryRef table, id key, id value, const char *where) {
    if (!key) BNRaise("NSInvalidArgumentException", "%s: key cannot be nil", where);
    if (!value) BNRaise("NSInvalidArgumentException", "%s: object cannot be nil (key: %s)", where, BNDescribe(key).UTF8String);
    id copied = [key copy];
    CFDictionarySetValue(table, (__bridge const void *)copied, (__bridge const void *)value);
}
static id freeze(id self, CFMutableDictionaryRef table) {
    if (wants_mutable(self)) return (__bridge_transfer id)table;
    CFDictionaryRef frozen = CFDictionaryCreateCopy(NULL, table);
    CFRelease(table);
    return (__bridge_transfer id)frozen;
}

@implementation NSDictionary (Foundation)
+ (instancetype)dictionary { return [[self alloc] init]; }
+ (instancetype)dictionaryWithObject:(id)object forKey:(id)key {
    return [[self alloc] initWithObjects:&object forKeys:&key count:1];
}
+ (instancetype)dictionaryWithObjects:(const id[])objects forKeys:(const id[])keys count:(NSUInteger)count {
    return [[self alloc] initWithObjects:objects forKeys:keys count:count];
}
+ (instancetype)dictionaryWithDictionary:(NSDictionary *)other { return [[self alloc] initWithDictionary:other]; }
- (instancetype)init { return freeze(self, new_table()); }
- (instancetype)initWithObjects:(const id[])objects forKeys:(const id[])keys count:(NSUInteger)count {
    CFMutableDictionaryRef t = new_table();
    for (NSUInteger i = 0; i < count; i++) put(t, keys[i], objects[i], "-[NSDictionary initWithObjects:forKeys:count:]");
    return freeze(self, t);
}
+ (instancetype)dictionaryWithObjects:(NSArray *)objects forKeys:(NSArray *)keys {
    return [[self alloc] initWithObjects:objects forKeys:keys];
}
- (instancetype)initWithObjects:(NSArray *)objects forKeys:(NSArray *)keys {
    if (objects.count != keys.count)
        BNRaise("NSInvalidArgumentException", "-[NSDictionary initWithObjects:forKeys:]: count of objects (%lu) differs from count of keys (%lu)",
                (unsigned long)objects.count, (unsigned long)keys.count);
    CFMutableDictionaryRef t = new_table();
    for (NSUInteger i = 0; i < objects.count; i++) put(t, keys[i], objects[i], "-[NSDictionary initWithObjects:forKeys:]");
    return freeze(self, t);
}
- (instancetype)initWithDictionary:(NSDictionary *)other {
    if (!other) return [self init];
    if (wants_mutable(self)) return (__bridge_transfer id)CFDictionaryCreateMutableCopy(NULL, 0, CFD(other));
    return (__bridge_transfer id)CFDictionaryCreateCopy(NULL, CFD(other));
}

- (NSUInteger)count { return (NSUInteger)CFDictionaryGetCount(CFD(self)); }
- (id)objectForKey:(id)key { return key ? (__bridge id)CFDictionaryGetValue(CFD(self), (__bridge const void *)key) : nil; }
- (id)objectForKeyedSubscript:(id)key { return [self objectForKey:key]; }
- (id)__swift_objectForKeyedSubscript:(id)key { return [self objectForKey:key]; }
- (NSArray *)allKeys {
    NSUInteger n = self.count;
    void **keys = malloc((n ? n : 1) * sizeof(void *));
    CFDictionaryGetKeysAndValues(CFD(self), (const void **)keys, NULL);
    NSArray *a = (__bridge_transfer NSArray *)CFArrayCreate(NULL, (const void **)keys, (CFIndex)n, &kCFTypeArrayCallBacks);
    free(keys);
    return a;
}
- (NSArray *)allValues {
    NSUInteger n = self.count;
    void **values = malloc((n ? n : 1) * sizeof(void *));
    CFDictionaryGetKeysAndValues(CFD(self), NULL, (const void **)values);
    NSArray *a = (__bridge_transfer NSArray *)CFArrayCreate(NULL, (const void **)values, (CFIndex)n, &kCFTypeArrayCallBacks);
    free(values);
    return a;
}
- (BOOL)isEqualToDictionary:(NSDictionary *)other {
    if (!other || other.count != self.count) return NO;
    for (id key in self) {
        id mine = [self objectForKey:key], theirs = [other objectForKey:key];
        if (!theirs || ![mine isEqual:theirs]) return NO;
    }
    return YES;
}
- (BOOL)isEqual:(id)other {
    return other == self || ([other isKindOfClass:[NSDictionary class]] && [self isEqualToDictionary:other]);
}
- (NSUInteger)hash { return self.count; }
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id, id, BOOL *))block {
    BOOL stop = NO;
    for (id key in self.allKeys) {
        block(key, [self objectForKey:key], &stop);
        if (stop) break;
    }
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained[])buffer
                                    count:(NSUInteger)len {
    /* Enumerate a snapshot of the keys. Assigning to an __autoreleasing
     * variable keeps it alive until the enclosing pool drains. */
    if (state->state == 0) {
        id __autoreleasing snapshot = self.allKeys;
        state->extra[1] = (unsigned long)(__bridge void *)snapshot;
    }
    NSArray *keys = (__bridge NSArray *)(void *)state->extra[1];
    NSUInteger n = keys.count, start = state->state;
    if (start >= n) return 0;
    NSUInteger take = n - start < len ? n - start : len;
    CFArrayGetValues((__bridge CFArrayRef)keys, CFRangeMake((CFIndex)start, (CFIndex)take), (const void **)(void *)buffer);
    state->state = start + take;
    state->itemsPtr = buffer;
    state->mutationsPtr = &state->extra[0];
    return take;
}
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFDictionaryCreateCopy(NULL, CFD(self)); }
- (id)mutableCopyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFDictionaryCreateMutableCopy(NULL, 0, CFD(self)); }
- (NSString *)description {
    NSMutableString *s = [NSMutableString stringWithString:@"{"];
    NSArray *keys = self.allKeys;
    if ([keys.firstObject respondsToSelector:@selector(compare:)]) keys = [keys sortedArrayUsingSelector:@selector(compare:)];
    for (id key in keys) [s appendFormat:@"\n    %@ = %@;", key, [self objectForKey:key]];
    [s appendString:@"\n}"];
    return s;
}
@end

@implementation NSMutableDictionary (Foundation)
+ (instancetype)dictionaryWithCapacity:(NSUInteger)capacity { return [[self alloc] init]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity { return (__bridge_transfer id)new_table(); }
- (void)setObject:(id)object forKey:(id)key { put(CFMD(self), key, object, "-[NSMutableDictionary setObject:forKey:]"); }
- (void)setObject:(id)object forKeyedSubscript:(id)key {
    if (object) [self setObject:object forKey:key];
    else [self removeObjectForKey:key];
}
- (void)__swift_setObject:(id)object forKeyedSubscript:(id)key { [self setObject:object forKeyedSubscript:key]; }
- (void)removeObjectForKey:(id)key {
    if (key) CFDictionaryRemoveValue(CFMD(self), (__bridge const void *)key);
}
- (void)removeAllObjects { CFDictionaryRemoveAllValues(CFMD(self)); }
- (void)addEntriesFromDictionary:(NSDictionary *)other {
    for (id key in other) [self setObject:[other objectForKey:key] forKey:key];
}
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFDictionaryCreateCopy(NULL, CFD(self)); }
@end
