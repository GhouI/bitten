#import "FoundationInternal.h"

static inline CFSetRef CFSE(NSSet *s) { return (__bridge CFSetRef)s; }
static inline CFMutableSetRef CFMSE(NSSet *s) { return (__bridge CFMutableSetRef)s; }
static BOOL wants_mutable(id self) { return [self isKindOfClass:[NSMutableSet class]]; }

static id make_set(id self, const id __unsafe_unretained objects[], NSUInteger count) {
    CFMutableSetRef m = CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks);
    for (NSUInteger i = 0; i < count; i++) {
        if (!objects[i]) BNRaise("NSInvalidArgumentException", "-[NSSet initWithObjects:count:]: attempt to insert nil object from objects[%lu]", i);
        CFSetAddValue(m, (__bridge const void *)objects[i]);
    }
    if (wants_mutable(self)) return (__bridge_transfer id)m;
    CFSetRef frozen = CFSetCreateCopy(NULL, m);
    CFRelease(m);
    return (__bridge_transfer id)frozen;
}

@implementation NSSet (Foundation)
+ (instancetype)set { return [[self alloc] init]; }
+ (instancetype)setWithObject:(id)object { return [[self alloc] initWithObjects:&object count:1]; }
+ (instancetype)setWithObjects:(const id[])objects count:(NSUInteger)count { return [[self alloc] initWithObjects:objects count:count]; }
+ (instancetype)setWithObjects:(id)first, ... {
    NSMutableArray *m = [NSMutableArray array];
    va_list ap;
    va_start(ap, first);
    for (id o = first; o; o = va_arg(ap, id)) [m addObject:o];
    va_end(ap);
    return [[self alloc] initWithArray:m];
}
+ (instancetype)setWithArray:(NSArray *)array { return [[self alloc] initWithArray:array]; }
- (instancetype)init { return make_set(self, NULL, 0); }
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count { return make_set(self, objects, count); }
- (instancetype)initWithArray:(NSArray *)array {
    NSUInteger n = array.count;
    void **items = malloc((n ? n : 1) * sizeof(void *));
    CFArrayGetValues((__bridge CFArrayRef)array, CFRangeMake(0, (CFIndex)n), (const void **)items);
    id result = make_set(self, (const id __unsafe_unretained *)(void *)items, n);
    free(items);
    return result;
}
- (instancetype)initWithSet:(NSSet *)set { return [self initWithArray:set.allObjects]; }

- (NSUInteger)count { return (NSUInteger)CFSetGetCount(CFSE(self)); }
- (BOOL)containsObject:(id)object { return object && CFSetContainsValue(CFSE(self), (__bridge const void *)object); }
- (id)member:(id)object { return object ? (__bridge id)CFSetGetValue(CFSE(self), (__bridge const void *)object) : nil; }
- (NSArray *)allObjects {
    NSUInteger n = self.count;
    void **items = malloc((n ? n : 1) * sizeof(void *));
    CFSetGetValues(CFSE(self), (const void **)items);
    NSArray *a = (__bridge_transfer NSArray *)CFArrayCreate(NULL, (const void **)items, (CFIndex)n, &kCFTypeArrayCallBacks);
    free(items);
    return a;
}
- (id)anyObject { return self.allObjects.firstObject; }
- (BOOL)isSubsetOfSet:(NSSet *)other {
    for (id o in self) if (![other containsObject:o]) return NO;
    return YES;
}
- (BOOL)isEqualToSet:(NSSet *)other { return other && other.count == self.count && [self isSubsetOfSet:other]; }
- (BOOL)isEqual:(id)other { return other == self || ([other isKindOfClass:[NSSet class]] && [self isEqualToSet:other]); }
- (NSUInteger)hash { return self.count; }
- (BOOL)intersectsSet:(NSSet *)other {
    for (id o in self) if ([other containsObject:o]) return YES;
    return NO;
}
- (void)enumerateObjectsUsingBlock:(void (^)(id, BOOL *))block {
    BOOL stop = NO;
    for (id o in self.allObjects) {
        block(o, &stop);
        if (stop) break;
    }
}
- (NSSet *)setByAddingObject:(id)object {
    NSMutableSet *m = [self mutableCopy];
    [m addObject:object];
    return [m copy];
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained[])buffer count:(NSUInteger)len {
    if (state->state == 0) {
        id __autoreleasing snapshot = self.allObjects;
        state->extra[1] = (unsigned long)(__bridge void *)snapshot;
    }
    NSArray *items = (__bridge NSArray *)(void *)state->extra[1];
    NSUInteger n = items.count, start = state->state;
    if (start >= n) return 0;
    NSUInteger take = n - start < len ? n - start : len;
    CFArrayGetValues((__bridge CFArrayRef)items, CFRangeMake((CFIndex)start, (CFIndex)take), (const void **)(void *)buffer);
    state->state = start + take;
    state->itemsPtr = buffer;
    state->mutationsPtr = &state->extra[0];
    return take;
}
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFSetCreateCopy(NULL, CFSE(self)); }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableSet alloc] initWithArray:self.allObjects]; }
- (NSString *)description {
    NSMutableString *s = [NSMutableString stringWithString:@"{("];
    NSArray *items = self.allObjects;
    for (NSUInteger i = 0; i < items.count; i++) [s appendFormat:@"\n    %@%s", items[i], i + 1 < items.count ? "," : ""];
    [s appendString:@"\n)}"];
    return s;
}
@end

@implementation NSMutableSet (Foundation)
+ (instancetype)setWithCapacity:(NSUInteger)capacity { return [[self alloc] init]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity { return (__bridge_transfer id)CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks); }
- (void)addObject:(id)object {
    if (!object) BNRaise("NSInvalidArgumentException", "-[NSMutableSet addObject:]: object cannot be nil");
    CFSetAddValue(CFMSE(self), (__bridge const void *)object);
}
- (void)removeObject:(id)object { if (object) CFSetRemoveValue(CFMSE(self), (__bridge const void *)object); }
- (void)removeAllObjects { CFSetRemoveAllValues(CFMSE(self)); }
- (void)addObjectsFromArray:(NSArray *)array { for (id o in array) [self addObject:o]; }
- (void)unionSet:(NSSet *)other { for (id o in other.allObjects) [self addObject:o]; }
- (void)minusSet:(NSSet *)other { for (id o in other.allObjects) [self removeObject:o]; }
- (void)intersectSet:(NSSet *)other {
    for (id o in self.allObjects) if (![other containsObject:o]) [self removeObject:o];
}
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFSetCreateCopy(NULL, CFSE(self)); }
@end
