// NSMethodSignature and NSInvocation: integer, floating-point, struct
// (in registers and in memory) arguments and returns, and arguments
// spilled to the stack.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

typedef struct { double a, b, c, d; } Big;

@interface Callee : NSObject
@end
@implementation Callee
- (long)add:(long)x to:(long)y { return x + y; }
- (double)scale:(double)v by:(float)f { return v * f; }
- (NSRect)grow:(NSRect)r by:(double)d {
    return NSMakeRect(r.origin.x - d, r.origin.y - d, r.size.width + 2 * d, r.size.height + 2 * d);
}
- (Big)big:(double)x { return (Big){x, x * 2, x * 3, x * 4}; }
- (long)sum:(long)a :(long)b :(long)c :(long)d :(long)e :(long)f :(long)g :(long)h { return a + b + c + d + e + f + g + h; }
- (NSString *)describe:(id)o withPoint:(NSPoint)p { return [NSString stringWithFormat:@"%@@%g,%g", o, p.x, p.y]; }
@end

int main(void) {
    @autoreleasepool {
        Callee *c = [Callee new];
        NSMethodSignature *s = [c methodSignatureForSelector:@selector(add:to:)];
        CHECK(s.numberOfArguments == 4 && *s.methodReturnType == 'q' && s.methodReturnLength == 8);
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:s];
        inv.target = c;
        inv.selector = @selector(add:to:);
        long x = 40, y = 2, r = 0;
        [inv setArgument:&x atIndex:2];
        [inv setArgument:&y atIndex:3];
        [inv invoke];
        [inv getReturnValue:&r];
        CHECK(r == 42);

        inv = [NSInvocation invocationWithMethodSignature:[c methodSignatureForSelector:@selector(scale:by:)]];
        inv.target = c;
        inv.selector = @selector(scale:by:);
        double v = 1.5, dr = 0;
        float f = 4;
        [inv setArgument:&v atIndex:2];
        [inv setArgument:&f atIndex:3];
        [inv invoke];
        [inv getReturnValue:&dr];
        CHECK(dr == 6);

        inv = [NSInvocation invocationWithMethodSignature:[c methodSignatureForSelector:@selector(grow:by:)]];
        inv.selector = @selector(grow:by:);
        NSRect rect = NSMakeRect(10, 20, 30, 40), out;
        double d = 5;
        [inv setArgument:&rect atIndex:2];
        [inv setArgument:&d atIndex:3];
        [inv invokeWithTarget:c];
        [inv getReturnValue:&out];
        CHECK(NSEqualRects(out, NSMakeRect(5, 15, 40, 50)));

        inv = [NSInvocation invocationWithMethodSignature:[c methodSignatureForSelector:@selector(big:)]];
        inv.selector = @selector(big:);
        double bx = 2;
        Big big;
        [inv setArgument:&bx atIndex:2];
        [inv invokeWithTarget:c];
        [inv getReturnValue:&big];
        CHECK(big.a == 2 && big.d == 8);

        SEL sum = @selector(sum::::::::);
        inv = [NSInvocation invocationWithMethodSignature:[c methodSignatureForSelector:sum]];
        inv.selector = sum;
        for (long i = 0; i < 8; i++) {
            long a = i + 1;
            [inv setArgument:&a atIndex:2 + i];
        }
        [inv invokeWithTarget:c];
        long total = 0;
        [inv getReturnValue:&total];
        CHECK(total == 36);

        inv = [NSInvocation invocationWithMethodSignature:[c methodSignatureForSelector:@selector(describe:withPoint:)]];
        inv.selector = @selector(describe:withPoint:);
        NSString *obj = @"x";
        NSPoint pt = NSMakePoint(1, 2);
        [inv setArgument:&obj atIndex:2];
        [inv setArgument:&pt atIndex:3];
        [inv retainArguments];
        [inv invokeWithTarget:c];
        __unsafe_unretained NSString *res = nil;
        [inv getReturnValue:&res];
        CHECK([res isEqualToString:@"x@1,2"]);
        puts("foundation invocation ok");
    }
    return 0;
}
