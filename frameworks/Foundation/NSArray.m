#import "FoundationInternal.h"

static inline CFArrayRef CFA(NSArray *a) { return (__bridge CFArrayRef)a; }
static inline CFMutableArrayRef CFMA(NSArray *a) { return (__bridge CFMutableArrayRef)a; }
static BOOL wants_mutable(id self) { return [self isKindOfClass:[NSMutableArray class]]; }

static void check_objects(const id __unsafe_unretained objects[], NSUInteger count, const char *where) {
    for (NSUInteger i = 0; i < count; i++)
        if (!objects[i]) BNRaise("NSInvalidArgumentException", "%s: attempt to insert nil object from objects[%lu]", where, i);
}

static id make_array(id self, const id __unsafe_unretained objects[], NSUInteger count) {
    check_objects(objects, count, "-[NSArray initWithObjects:count:]");
    if (wants_mutable(self)) {
        CFMutableArrayRef m = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
        for (NSUInteger i = 0; i < count; i++) CFArrayAppendValue(m, (__bridge const void *)objects[i]);
        return (__bridge_transfer id)m;
    }
    return (__bridge_transfer id)CFArrayCreate(NULL, (const void **)(void *)objects, (CFIndex)count, &kCFTypeArrayCallBacks);
}

static void bounds(NSArray *a, NSUInteger index, const char *what) {
    NSUInteger n = a.count;
    if (index >= n) {
        if (n) BNRaise("NSRangeException", "-[NSArray %s]: index %lu beyond bounds [0 .. %lu]", what, index, n - 1);
        BNRaise("NSRangeException", "-[NSArray %s]: index %lu beyond bounds for empty array", what, index);
    }
}

struct sort_ctx {
    __unsafe_unretained NSComparator comparator;
    SEL selector;
};
static int sort_compare(void *ctx, const void *a, const void *b) {
    struct sort_ctx *c = ctx;
    id x = (__bridge id)(*(void *const *)a), y = (__bridge id)(*(void *const *)b);
    if (c->comparator) return (int)c->comparator(x, y);
    return (int)((NSComparisonResult (*)(id, SEL, id))objc_msgSend)(x, c->selector, y);
}
static NSArray *sorted(NSArray *self, NSComparator comparator, SEL selector, BOOL mutable) {
    NSUInteger n = self.count;
    void **items = malloc((n ? n : 1) * sizeof(void *));
    CFArrayGetValues(CFA(self), CFRangeMake(0, (CFIndex)n), (const void **)items);
    struct sort_ctx ctx = {comparator, selector};
    /* insertion-stable merge is not needed here: sort a pointer array */
    qsort_r(items, n, sizeof(void *), &ctx, sort_compare);
    id result;
    if (mutable) {
        CFMutableArrayRef m = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
        for (NSUInteger i = 0; i < n; i++) CFArrayAppendValue(m, items[i]);
        result = (__bridge_transfer id)m;
    } else {
        result = (__bridge_transfer id)CFArrayCreate(NULL, (const void **)items, (CFIndex)n, &kCFTypeArrayCallBacks);
    }
    free(items);
    return result;
}

@implementation NSArray (Foundation)
+ (instancetype)array { return [[self alloc] init]; }
+ (instancetype)arrayWithObject:(id)object { return [[self alloc] initWithObjects:&object count:1]; }
+ (instancetype)arrayWithObjects:(const id[])objects count:(NSUInteger)count {
    return [[self alloc] initWithObjects:objects count:count];
}
+ (instancetype)arrayWithObjects:(id)first, ... {
    NSMutableArray *m = [NSMutableArray array];
    va_list ap;
    va_start(ap, first);
    for (id o = first; o; o = va_arg(ap, id)) [m addObject:o];
    va_end(ap);
    return [[self alloc] initWithArray:m];
}
+ (instancetype)arrayWithArray:(NSArray *)array { return [[self alloc] initWithArray:array]; }
- (instancetype)init { return make_array(self, NULL, 0); }
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count { return make_array(self, objects, count); }
- (instancetype)initWithArray:(NSArray *)array {
    if (wants_mutable(self)) return (__bridge_transfer id)CFArrayCreateMutableCopy(NULL, 0, CFA(array ?: @[]));
    return (__bridge_transfer id)CFArrayCreateCopy(NULL, CFA(array ?: @[]));
}

- (NSUInteger)count { return (NSUInteger)CFArrayGetCount(CFA(self)); }
- (id)objectAtIndex:(NSUInteger)index {
    bounds(self, index, "objectAtIndex:");
    return (__bridge id)CFArrayGetValueAtIndex(CFA(self), (CFIndex)index);
}
- (id)objectAtIndexedSubscript:(NSUInteger)index {
    bounds(self, index, "objectAtIndexedSubscript:");
    return (__bridge id)CFArrayGetValueAtIndex(CFA(self), (CFIndex)index);
}
- (id)firstObject { return self.count ? [self objectAtIndex:0] : nil; }
- (id)lastObject { NSUInteger n = self.count; return n ? [self objectAtIndex:n - 1] : nil; }
- (NSUInteger)indexOfObject:(id)object {
    NSUInteger n = self.count;
    for (NSUInteger i = 0; i < n; i++) {
        id o = [self objectAtIndex:i];
        if (o == object || [o isEqual:object]) return i;
    }
    return NSNotFound;
}
- (BOOL)containsObject:(id)object { return [self indexOfObject:object] != NSNotFound; }
- (NSUInteger)indexOfObjectIdenticalTo:(id)object {
    NSUInteger n = self.count;
    for (NSUInteger i = 0; i < n; i++)
        if ([self objectAtIndex:i] == object) return i;
    return NSNotFound;
}
- (NSArray *)arrayByAddingObject:(id)object {
    NSMutableArray *m = [self mutableCopy];
    [m addObject:object];
    return [m copy];
}
- (NSArray *)subarrayWithRange:(NSRange)range {
    if (NSMaxRange(range) > self.count) BNRaise("NSRangeException", "-[NSArray subarrayWithRange:]: range {%lu, %lu} extends beyond bounds", range.location, range.length);
    void **items = malloc((range.length ? range.length : 1) * sizeof(void *));
    CFArrayGetValues(CFA(self), CFRangeMake((CFIndex)range.location, (CFIndex)range.length), (const void **)items);
    NSArray *r = (__bridge_transfer NSArray *)CFArrayCreate(NULL, (const void **)items, (CFIndex)range.length, &kCFTypeArrayCallBacks);
    free(items);
    return r;
}
- (NSString *)componentsJoinedByString:(NSString *)separator {
    NSMutableString *s = [NSMutableString string];
    NSUInteger n = self.count;
    for (NSUInteger i = 0; i < n; i++) {
        if (i && separator) [s appendString:separator];
        [s appendString:BNDescribe([self objectAtIndex:i])];
    }
    return [s copy];
}
- (BOOL)isEqualToArray:(NSArray *)other {
    if (!other || other.count != self.count) return NO;
    NSUInteger n = self.count;
    for (NSUInteger i = 0; i < n; i++)
        if (![[self objectAtIndex:i] isEqual:[other objectAtIndex:i]]) return NO;
    return YES;
}
- (BOOL)isEqual:(id)other {
    return other == self || ([other isKindOfClass:[NSArray class]] && [self isEqualToArray:other]);
}
- (NSUInteger)hash { return self.count; }
- (void)enumerateObjectsUsingBlock:(void (^)(id, NSUInteger, BOOL *))block {
    BOOL stop = NO;
    NSUInteger n = self.count;
    for (NSUInteger i = 0; i < n && !stop; i++) block([self objectAtIndex:i], i, &stop);
}
- (NSArray *)sortedArrayUsingComparator:(NSComparator)comparator { return sorted(self, comparator, NULL, NO); }
- (NSArray *)sortedArrayUsingSelector:(SEL)selector { return sorted(self, nil, selector, NO); }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained[])buffer
                                    count:(NSUInteger)len {
    NSUInteger n = self.count, start = state->state;
    if (start >= n) return 0;
    NSUInteger take = n - start < len ? n - start : len;
    CFArrayGetValues(CFA(self), CFRangeMake((CFIndex)start, (CFIndex)take), (const void **)(void *)buffer);
    state->state = start + take;
    state->itemsPtr = buffer;
    state->mutationsPtr = &state->extra[0];
    return take;
}
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFArrayCreateCopy(NULL, CFA(self)); }
- (id)mutableCopyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFArrayCreateMutableCopy(NULL, 0, CFA(self)); }
- (NSString *)description {
    NSMutableString *s = [NSMutableString stringWithString:@"("];
    NSUInteger n = self.count;
    for (NSUInteger i = 0; i < n; i++) {
        [s appendFormat:@"\n    %@%s", [self objectAtIndex:i], i + 1 < n ? "," : ""];
    }
    [s appendString:n ? @"\n)" : @"\n)"];
    return s;
}
@end

@implementation NSMutableArray (Foundation)
+ (instancetype)arrayWithCapacity:(NSUInteger)capacity { return [[self alloc] init]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity {
    return (__bridge_transfer id)CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
}
- (void)addObject:(id)object {
    if (!object) BNRaise("NSInvalidArgumentException", "-[NSMutableArray addObject:]: object cannot be nil");
    CFArrayAppendValue(CFMA(self), (__bridge const void *)object);
}
- (void)addObjectsFromArray:(NSArray *)array {
    NSUInteger n = array.count;
    for (NSUInteger i = 0; i < n; i++) [self addObject:[array objectAtIndex:i]];
}
- (void)insertObject:(id)object atIndex:(NSUInteger)index {
    if (!object) BNRaise("NSInvalidArgumentException", "-[NSMutableArray insertObject:atIndex:]: object cannot be nil");
    if (index > self.count) BNRaise("NSRangeException", "-[NSMutableArray insertObject:atIndex:]: index %lu beyond bounds", index);
    CFArrayInsertValueAtIndex(CFMA(self), (CFIndex)index, (__bridge const void *)object);
}
- (void)removeObjectAtIndex:(NSUInteger)index {
    bounds(self, index, "removeObjectAtIndex:");
    CFArrayRemoveValueAtIndex(CFMA(self), (CFIndex)index);
}
- (void)removeLastObject {
    NSUInteger n = self.count;
    if (n) CFArrayRemoveValueAtIndex(CFMA(self), (CFIndex)n - 1);
}
- (void)removeObject:(id)object {
    for (NSUInteger i = self.count; i-- > 0;) {
        id o = [self objectAtIndex:i];
        if (o == object || [o isEqual:object]) CFArrayRemoveValueAtIndex(CFMA(self), (CFIndex)i);
    }
}
- (void)removeObjectIdenticalTo:(id)object {
    for (NSUInteger i = self.count; i-- > 0;)
        if ([self objectAtIndex:i] == object) CFArrayRemoveValueAtIndex(CFMA(self), (CFIndex)i);
}
- (void)removeAllObjects { CFArrayRemoveAllValues(CFMA(self)); }
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)object {
    if (!object) BNRaise("NSInvalidArgumentException", "-[NSMutableArray replaceObjectAtIndex:withObject:]: object cannot be nil");
    bounds(self, index, "replaceObjectAtIndex:withObject:");
    CFArraySetValueAtIndex(CFMA(self), (CFIndex)index, (__bridge const void *)object);
}
- (void)setObject:(id)object atIndexedSubscript:(NSUInteger)index {
    if (index == self.count) [self addObject:object];
    else [self replaceObjectAtIndex:index withObject:object];
}
- (void)sortUsingComparator:(NSComparator)comparator {
    NSArray *s = sorted(self, comparator, NULL, NO);
    [self removeAllObjects];
    [self addObjectsFromArray:s];
}
- (id)copyWithZone:(NSZone *)zone { return (__bridge_transfer id)CFArrayCreateCopy(NULL, CFA(self)); }
@end
