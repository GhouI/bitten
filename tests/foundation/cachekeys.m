// NSCache retains its keys rather than copying them, so keys need not be
// NSCopying; equal keys find the same entry; limits evict oldest first.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

@interface Key : NSObject
@property NSInteger n;
@end
@implementation Key
- (NSUInteger)hash { return (NSUInteger)self.n; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[Key class]] && ((Key *)o).n == self.n; }
@end
static Key *key(NSInteger n) {
    Key *k = [Key new];
    k.n = n;
    return k;
}

int main(void) {
    @autoreleasepool {
        NSCache *c = [NSCache new];
        Key *a = key(1);
        [c setObject:@"one" forKey:a];
        CHECK([[c objectForKey:key(1)] isEqual:@"one"]);
        CHECK([c objectForKey:key(2)] == nil);
        c.countLimit = 2;
        [c setObject:@"two" forKey:key(2)];
        [c setObject:@"three" forKey:key(3)];
        CHECK([c objectForKey:key(1)] == nil);
        CHECK([[c objectForKey:key(3)] isEqual:@"three"]);
        [c removeObjectForKey:key(3)];
        CHECK([c objectForKey:key(3)] == nil);
        [c removeAllObjects];
        CHECK([c objectForKey:key(2)] == nil);
        printf("ok\n");
    }
    return 0;
}
