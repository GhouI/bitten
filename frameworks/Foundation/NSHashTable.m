/* NSHashTable and NSMapTable: sets and dictionaries that may hold their
 * members weakly, and may compare them by identity instead of -isEqual:.
 * Entries live in arrays of small boxes (searched linearly, as these tables
 * stay small); weak entries whose object went away are dropped when seen. */
#import "FoundationInternal.h"

@interface BNTableBox : NSObject {
  @public
    __weak id _weak;
    id _strong;
    BOOL _isWeak;
}
@end
@implementation BNTableBox
+ (instancetype)box:(id)object weak:(BOOL)weak {
    BNTableBox *b = [BNTableBox new];
    b->_isWeak = weak;
    if (weak) b->_weak = object; else b->_strong = object;
    return b;
}
- (id)object { return _isWeak ? _weak : _strong; }
@end

static BOOL is_weak(NSPointerFunctionsOptions o) { return (o & 0xFF) == NSPointerFunctionsWeakMemory; }
static BOOL by_identity(NSPointerFunctionsOptions o) { return (o & 0xFF00) == NSPointerFunctionsObjectPointerPersonality; }
static BOOL same(id a, id b, NSPointerFunctionsOptions o) {
    if (a == b) return YES;
    if (!a || !b || by_identity(o)) return NO;
    return [a isEqual:b];
}
static id copy_in(id object, NSPointerFunctionsOptions o) {
    return (o & NSPointerFunctionsCopyIn) ? [object copy] : object;
}

@implementation NSPointerFunctions {
    NSPointerFunctionsOptions _options;
}
+ (instancetype)pointerFunctionsWithOptions:(NSPointerFunctionsOptions)options {
    return [[self alloc] initWithOptions:options];
}
- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options {
    if ((self = [super init])) _options = options;
    return self;
}
- (BOOL)usesWeakReadAndWriteBarriers { return is_weak(_options); }
@end

@implementation NSHashTable {
    NSMutableArray<BNTableBox *> *_boxes;
    NSPointerFunctionsOptions _options;
}

+ (instancetype)hashTableWithOptions:(NSPointerFunctionsOptions)options {
    return [[self alloc] initWithOptions:options capacity:0];
}
+ (instancetype)weakObjectsHashTable { return [self hashTableWithOptions:NSPointerFunctionsWeakMemory]; }
- (instancetype)init { return [self initWithOptions:NSPointerFunctionsStrongMemory capacity:0]; }
- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options capacity:(NSUInteger)capacity {
    if ((self = [super init])) {
        _options = options;
        _boxes = [NSMutableArray arrayWithCapacity:capacity];
    }
    return self;
}
- (NSPointerFunctions *)pointerFunctions { return [NSPointerFunctions pointerFunctionsWithOptions:_options]; }

/* Live members, dropping boxes whose weak object is gone. */
- (NSArray *)allObjects {
    @synchronized(self) {
        for (NSInteger i = (NSInteger)_boxes.count - 1; i >= 0; i--)
            if (![_boxes[i] object]) [_boxes removeObjectAtIndex:i];
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:_boxes.count];
        for (BNTableBox *b in _boxes) [out addObject:[b object]];
        return out;
    }
}
- (NSUInteger)count { return [self allObjects].count; }
- (id)anyObject { return [self allObjects].firstObject; }
- (NSSet *)setRepresentation { return [NSSet setWithArray:[self allObjects]]; }
- (NSEnumerator *)objectEnumerator { return [[self allObjects] objectEnumerator]; }

- (id)member:(id)object {
    for (id o in [self allObjects])
        if (same(o, object, _options)) return o;
    return nil;
}
- (BOOL)containsObject:(id)object { return object && [self member:object] != nil; }
- (void)addObject:(id)object {
    if (!object) return;
    @synchronized(self) {
        if ([self member:object]) return;
        [_boxes addObject:[BNTableBox box:copy_in(object, _options) weak:is_weak(_options)]];
    }
}
- (void)removeObject:(id)object {
    @synchronized(self) {
        for (NSUInteger i = 0; i < _boxes.count; i++) {
            if (same([_boxes[i] object], object, _options)) {
                [_boxes removeObjectAtIndex:i];
                return;
            }
        }
    }
}
- (void)removeAllObjects {
    @synchronized(self) { [_boxes removeAllObjects]; }
}
- (void)unionHashTable:(NSHashTable *)other {
    for (id o in [other allObjects]) [self addObject:o];
}
- (void)minusHashTable:(NSHashTable *)other {
    for (id o in [other allObjects]) [self removeObject:o];
}
- (void)intersectHashTable:(NSHashTable *)other {
    for (id o in [self allObjects])
        if (![other containsObject:o]) [self removeObject:o];
}
- (BOOL)intersectsHashTable:(NSHashTable *)other {
    for (id o in [self allObjects])
        if ([other containsObject:o]) return YES;
    return NO;
}
- (BOOL)isSubsetOfHashTable:(NSHashTable *)other {
    for (id o in [self allObjects])
        if (![other containsObject:o]) return NO;
    return YES;
}
- (BOOL)isEqualToHashTable:(NSHashTable *)other {
    return self.count == other.count && [self isSubsetOfHashTable:other];
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained *)buffer count:(NSUInteger)len {
    /* Enumerate a snapshot kept alive by the state's extra slot. */
    /* NSArray keeps its position in state->state and uses extra[0] as the
     * mutation counter; the snapshot it walks lives in extra[1]. */
    if (state->state == 0 && !state->extra[1]) {
        NSArray *snapshot = [self allObjects];
        state->extra[1] = (unsigned long)(__bridge_retained void *)snapshot;
    }
    if (!state->extra[1]) return 0;
    NSArray *snapshot = (__bridge NSArray *)(void *)state->extra[1];
    NSUInteger n = [snapshot countByEnumeratingWithState:state objects:buffer count:len];
    if (n == 0) {
        CFRelease((__bridge CFTypeRef)snapshot);
        state->extra[1] = 0;
    }
    return n;
}
- (id)copyWithZone:(NSZone *)zone {
    NSHashTable *t = [[NSHashTable alloc] initWithOptions:_options capacity:0];
    [t unionHashTable:self];
    return t;
}
- (NSString *)description { return [NSString stringWithFormat:@"NSHashTable %@", [self allObjects]]; }
@end

@implementation NSMapTable {
    NSMutableArray<BNTableBox *> *_keys, *_values;
    NSPointerFunctionsOptions _keyOptions, _valueOptions;
}

+ (instancetype)mapTableWithKeyOptions:(NSPointerFunctionsOptions)k valueOptions:(NSPointerFunctionsOptions)v {
    return [[self alloc] initWithKeyOptions:k valueOptions:v capacity:0];
}
+ (instancetype)strongToStrongObjectsMapTable {
    return [self mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory];
}
+ (instancetype)weakToStrongObjectsMapTable {
    return [self mapTableWithKeyOptions:NSPointerFunctionsWeakMemory valueOptions:NSPointerFunctionsStrongMemory];
}
+ (instancetype)strongToWeakObjectsMapTable {
    return [self mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory];
}
+ (instancetype)weakToWeakObjectsMapTable {
    return [self mapTableWithKeyOptions:NSPointerFunctionsWeakMemory valueOptions:NSPointerFunctionsWeakMemory];
}
- (instancetype)init {
    return [self initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory capacity:0];
}
- (instancetype)initWithKeyOptions:(NSPointerFunctionsOptions)k valueOptions:(NSPointerFunctionsOptions)v
                          capacity:(NSUInteger)capacity {
    if ((self = [super init])) {
        _keyOptions = k;
        _valueOptions = v;
        _keys = [NSMutableArray array];
        _values = [NSMutableArray array];
    }
    return self;
}

/* Drops entries whose weak key or value is gone; call with the lock held. */
- (void)_bn_prune {
    for (NSInteger i = (NSInteger)_keys.count - 1; i >= 0; i--) {
        if (![_keys[i] object] || ![_values[i] object]) {
            [_keys removeObjectAtIndex:i];
            [_values removeObjectAtIndex:i];
        }
    }
}
- (NSInteger)_bn_indexOfKey:(id)key {
    for (NSUInteger i = 0; i < _keys.count; i++)
        if (same([_keys[i] object], key, _keyOptions)) return (NSInteger)i;
    return -1;
}

- (id)objectForKey:(id)key {
    if (!key) return nil;
    @synchronized(self) {
        [self _bn_prune];
        NSInteger i = [self _bn_indexOfKey:key];
        return i < 0 ? nil : [_values[i] object];
    }
}
- (void)setObject:(id)object forKey:(id)key {
    if (!key) return;
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    @synchronized(self) {
        [self _bn_prune];
        NSInteger i = [self _bn_indexOfKey:key];
        BNTableBox *v = [BNTableBox box:copy_in(object, _valueOptions) weak:is_weak(_valueOptions)];
        if (i >= 0) {
            _values[i] = v;
        } else {
            [_keys addObject:[BNTableBox box:copy_in(key, _keyOptions) weak:is_weak(_keyOptions)]];
            [_values addObject:v];
        }
    }
}
- (void)removeObjectForKey:(id)key {
    @synchronized(self) {
        NSInteger i = [self _bn_indexOfKey:key];
        if (i >= 0) {
            [_keys removeObjectAtIndex:i];
            [_values removeObjectAtIndex:i];
        }
    }
}
- (void)removeAllObjects {
    @synchronized(self) {
        [_keys removeAllObjects];
        [_values removeAllObjects];
    }
}
- (NSUInteger)count {
    @synchronized(self) {
        [self _bn_prune];
        return _keys.count;
    }
}
- (NSArray *)_bn_liveKeys {
    @synchronized(self) {
        [self _bn_prune];
        NSMutableArray *out = [NSMutableArray array];
        for (BNTableBox *b in _keys) [out addObject:[b object]];
        return out;
    }
}
- (NSArray *)_bn_liveValues {
    @synchronized(self) {
        [self _bn_prune];
        NSMutableArray *out = [NSMutableArray array];
        for (BNTableBox *b in _values) [out addObject:[b object]];
        return out;
    }
}
- (NSEnumerator *)keyEnumerator { return [[self _bn_liveKeys] objectEnumerator]; }
- (NSEnumerator *)objectEnumerator { return [[self _bn_liveValues] objectEnumerator]; }
- (NSDictionary *)dictionaryRepresentation {
    NSArray *ks = [self _bn_liveKeys], *vs = [self _bn_liveValues];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:ks.count];
    for (NSUInteger i = 0; i < ks.count; i++) d[ks[i]] = vs[i];
    return d;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained *)buffer count:(NSUInteger)len {
    /* NSArray keeps its position in state->state and uses extra[0] as the
     * mutation counter; the snapshot it walks lives in extra[1]. */
    if (state->state == 0 && !state->extra[1]) {
        NSArray *snapshot = [self _bn_liveKeys];
        state->extra[1] = (unsigned long)(__bridge_retained void *)snapshot;
    }
    if (!state->extra[1]) return 0;
    NSArray *snapshot = (__bridge NSArray *)(void *)state->extra[1];
    NSUInteger n = [snapshot countByEnumeratingWithState:state objects:buffer count:len];
    if (n == 0) {
        CFRelease((__bridge CFTypeRef)snapshot);
        state->extra[1] = 0;
    }
    return n;
}
- (id)copyWithZone:(NSZone *)zone {
    NSMapTable *t = [[NSMapTable alloc] initWithKeyOptions:_keyOptions valueOptions:_valueOptions capacity:0];
    NSArray *ks = [self _bn_liveKeys], *vs = [self _bn_liveValues];
    for (NSUInteger i = 0; i < ks.count; i++) [t setObject:vs[i] forKey:ks[i]];
    return t;
}
- (NSString *)description { return [NSString stringWithFormat:@"NSMapTable %@", [self dictionaryRepresentation]]; }
@end
