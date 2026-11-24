#import "FoundationInternal.h"

/* Enumerators walk a snapshot array. */
@interface BNArrayEnumerator : NSEnumerator {
  @public
    NSArray *_items;
    NSUInteger _next;
    BOOL _reverse;
}
@end

@implementation NSEnumerator
- (id)nextObject { return nil; }
- (NSArray *)allObjects {
    NSMutableArray *rest = [NSMutableArray array];
    for (id o; (o = [self nextObject]);) [rest addObject:o];
    return rest;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained[])buffer count:(NSUInteger)len {
    id o = [self nextObject];
    if (!o) return 0;
    id __autoreleasing keep = o;
    buffer[0] = keep;
    state->state = 1;
    state->itemsPtr = buffer;
    state->mutationsPtr = &state->extra[0];
    return 1;
}
@end

@implementation BNArrayEnumerator
- (id)nextObject {
    NSUInteger n = _items.count;
    if (_next >= n) return nil;
    NSUInteger i = _next++;
    return [_items objectAtIndex:_reverse ? n - 1 - i : i];
}
@end

static NSEnumerator *enumerator_over(NSArray *items, BOOL reverse) {
    BNArrayEnumerator *e = [BNArrayEnumerator new];
    e->_items = [items copy];
    e->_reverse = reverse;
    return e;
}

@implementation NSArray (Enumerators)
- (NSEnumerator *)objectEnumerator { return enumerator_over(self, NO); }
- (NSEnumerator *)reverseObjectEnumerator { return enumerator_over(self, YES); }
- (NSUInteger)indexOfObjectPassingTest:(BOOL (^)(id, NSUInteger, BOOL *))predicate {
    BOOL stop = NO;
    NSUInteger n = self.count;
    for (NSUInteger i = 0; i < n && !stop; i++)
        if (predicate([self objectAtIndex:i], i, &stop)) return i;
    return NSNotFound;
}
@end

@implementation NSDictionary (Enumerators)
- (NSEnumerator *)keyEnumerator { return enumerator_over(self.allKeys, NO); }
- (NSEnumerator *)objectEnumerator { return enumerator_over(self.allValues, NO); }
- (NSArray *)allKeysForObject:(id)object {
    NSMutableArray *keys = [NSMutableArray array];
    for (id key in self) if ([[self objectForKey:key] isEqual:object]) [keys addObject:key];
    return keys;
}
@end
