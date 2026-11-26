// Weak references to toll-free-bridged (CF-backed) objects: storing,
// loading and clearing one must not change the object's retain count.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

@interface Holder : NSObject
@property (weak) id weakRef;
@end
@implementation Holder
@end

int main(void) {
    @autoreleasepool {
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:@"abc"];
        NSMutableArray *a = [NSMutableArray arrayWithObject:@1];
        CFIndex before = CFGetRetainCount((__bridge CFTypeRef)s), abefore = CFGetRetainCount((__bridge CFTypeRef)a);
        Holder *h = [Holder new];
        for (int i = 0; i < 10; i++) {
            h.weakRef = s;
            CHECK(h.weakRef == s);
            h.weakRef = a;
            CHECK(h.weakRef == a);
        }
        h.weakRef = nil;
        CHECK(CFGetRetainCount((__bridge CFTypeRef)s) == before);
        CHECK(CFGetRetainCount((__bridge CFTypeRef)a) == abefore);
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:@"d"]];
        CHECK([s.string isEqualToString:@"abcd"] && a.count == 1);
        {
            __weak id w;
            @autoreleasepool {
                NSMutableString *gone = [NSMutableString stringWithString:@"temporary"];
                w = gone;
                CHECK(w == gone);
            }
            CHECK(w == nil);
        }
        puts("foundation weakcf ok");
    }
    return 0;
}
