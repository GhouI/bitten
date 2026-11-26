// QuartzCore: transforms, layer geometry and the tree, hit testing,
// rendering a layer tree into a bitmap, shape and gradient layers,
// animations reporting to their delegate, transactions, display links.
#import <QuartzCore/QuartzCore.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)
#define NEAR(a, b) (fabs((double)(a) - (double)(b)) < 1e-6)

static BOOL spin_until(BOOL (^done)(void)) {
    for (int i = 0; i < 300; i++) {
        if (done()) return YES;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return done();
}

@interface AnimDelegate : NSObject <CAAnimationDelegate>
@property int started, stopped;
@property BOOL finished;
@end
@implementation AnimDelegate
- (void)animationDidStart:(CAAnimation *)anim { self.started++; }
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag { self.stopped++; self.finished = flag; }
@end

@interface Painter : NSObject <CALayerDelegate>
@property int draws;
@end
@implementation Painter
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
    self.draws++;
    CGContextSetRGBFillColor(ctx, 1, 1, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, 4, 4));
}
@end

@interface Ticker : NSObject
@property int ticks;
@end
@implementation Ticker
- (void)tick:(CADisplayLink *)link { self.ticks++; }
@end

static uint8_t px[64 * 64 * 4];
/* RGBA at (x, y), y from the bottom (CoreGraphics' coordinates). */
static const uint8_t *at(int x, int y) { return px + ((63 - y) * 64 + x) * 4; }

int main(void) {
    @autoreleasepool {
        /* transforms */
        CHECK(CATransform3DIsIdentity(CATransform3DIdentity));
        CATransform3D t = CATransform3DMakeTranslation(10, 20, 0);
        t = CATransform3DScale(t, 2, 3, 1);
        CGAffineTransform a = CATransform3DGetAffineTransform(t);
        CGPoint p = CGPointApplyAffineTransform(CGPointMake(1, 1), a);
        CHECK(NEAR(p.x, 12) && NEAR(p.y, 23));              /* scale, then translate */
        CATransform3D inv = CATransform3DInvert(t);
        CHECK(CATransform3DIsIdentity(CATransform3DConcat(t, inv)) ||
              NEAR(CATransform3DConcat(t, inv).m11, 1));
        CATransform3D r = CATransform3DMakeRotation(M_PI / 2, 0, 0, 1);
        p = CGPointApplyAffineTransform(CGPointMake(1, 0), CATransform3DGetAffineTransform(r));
        CHECK(NEAR(p.x, 0) && NEAR(p.y, 1));
        CHECK(CATransform3DIsAffine(r));
        CHECK(CATransform3DEqualToTransform(CATransform3DMakeAffineTransform(a), t));
        NSValue *v = [NSValue valueWithCATransform3D:t];
        CHECK(CATransform3DEqualToTransform(v.CATransform3DValue, t));
        CAFrameRateRange fr = CAFrameRateRangeMake(30, 120, 60);
        CHECK(fr.preferred == 60 && CAFrameRateRangeIsEqualToRange(fr, fr));
        CHECK(!CAFrameRateRangeIsEqualToRange(fr, CAFrameRateRangeDefault));
        CFTimeInterval t0 = CACurrentMediaTime();
        CHECK(t0 > 0 && CACurrentMediaTime() >= t0);

        /* constants carry Apple's values */
        CHECK([kCAGravityResize isEqualToString:@"resize"]);
        CHECK([kCAFillRuleEvenOdd isEqualToString:@"even-odd"]);
        CHECK([kCAMediaTimingFunctionEaseInEaseOut isEqualToString:@"easeInEaseOut"]);
        CHECK([kCATransition isEqualToString:@"transition"]);

        /* geometry */
        CALayer *root = [CALayer layer];
        root.frame = CGRectMake(0, 0, 64, 64);
        CHECK(NEAR(root.position.x, 32) && NEAR(root.bounds.size.width, 64));
        CALayer *child = [CALayer layer];
        child.frame = CGRectMake(10, 20, 30, 10);
        CHECK(NEAR(child.position.x, 25) && NEAR(child.position.y, 25));
        CHECK(CGRectEqualToRect(child.frame, CGRectMake(10, 20, 30, 10)));
        child.anchorPoint = CGPointZero;
        CHECK(NEAR(child.frame.origin.x, 25));             /* the position stays put */
        child.anchorPoint = CGPointMake(0.5, 0.5);

        /* the tree */
        [root addSublayer:child];
        CHECK(child.superlayer == root && root.sublayers.count == 1);
        CALayer *under = [CALayer layer];
        [root insertSublayer:under below:child];
        CHECK(root.sublayers[0] == under);
        [under removeFromSuperlayer];
        CHECK(root.sublayers.count == 1 && under.superlayer == nil);

        /* conversion and hit testing */
        CGPoint q = [child convertPoint:CGPointMake(0, 0) toLayer:root];
        CHECK(NEAR(q.x, 10) && NEAR(q.y, 20));
        q = [root convertPoint:CGPointMake(15, 25) toLayer:child];
        CHECK(NEAR(q.x, 5) && NEAR(q.y, 5));
        CHECK([root hitTest:CGPointMake(15, 25)] == child);
        CHECK([root hitTest:CGPointMake(5, 5)] == root);
        CHECK([root hitTest:CGPointMake(100, 100)] == nil);

        /* rendering */
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(px, 64, 64, 8, 64 * 4, rgb, kCGImageAlphaPremultipliedLast);
        CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1), blue = CGColorCreateGenericRGB(0, 0, 1, 1);
        root.backgroundColor = red;
        child.backgroundColor = blue;
        Painter *painter = [Painter new];
        CALayer *painted = [CALayer layer];
        painted.frame = CGRectMake(50, 50, 10, 10);
        painted.delegate = painter;
        [root addSublayer:painted];
        [root renderInContext:ctx];
        CHECK(at(2, 2)[0] == 255 && at(2, 2)[2] == 0);       /* root: red */
        CHECK(at(15, 25)[2] == 255 && at(15, 25)[0] == 0);   /* child: blue */
        CHECK(at(51, 51)[0] == 255 && at(51, 51)[1] == 255); /* delegate drew yellow */
        CHECK(at(58, 58)[0] == 255 && at(58, 58)[1] == 0);   /* outside its 4x4: red */
        CHECK(painter.draws == 1);

        /* hidden layers and opacity */
        child.hidden = YES;
        [root renderInContext:ctx];
        CHECK(at(15, 25)[0] == 255 && at(15, 25)[2] == 0);
        child.hidden = NO;
        child.opacity = 0.5;
        [root renderInContext:ctx];
        CHECK(at(15, 25)[0] > 100 && at(15, 25)[0] < 160 && at(15, 25)[2] > 100);
        child.opacity = 1;

        /* masksToBounds clips sublayers */
        CALayer *box = [CALayer layer];
        box.frame = CGRectMake(0, 40, 10, 10);
        box.masksToBounds = YES;
        CALayer *big = [CALayer layer];
        big.frame = CGRectMake(0, 0, 30, 30);
        big.backgroundColor = blue;
        [box addSublayer:big];
        [root addSublayer:box];
        [root renderInContext:ctx];
        CHECK(at(5, 45)[2] == 255);                           /* inside the box */
        CHECK(at(20, 45)[0] == 255 && at(20, 45)[2] == 0);    /* clipped */
        [box removeFromSuperlayer];

        /* shape and gradient layers */
        CAShapeLayer *shape = [CAShapeLayer layer];
        shape.frame = CGRectMake(0, 0, 64, 64);
        CGPathRef path = CGPathCreateWithEllipseInRect(CGRectMake(40, 0, 20, 20), NULL);
        shape.path = path;
        CGPathRelease(path);
        shape.fillColor = blue;
        CALayer *plain = [CALayer layer];
        plain.frame = CGRectMake(0, 0, 64, 64);
        plain.backgroundColor = red;
        [plain addSublayer:shape];
        [plain renderInContext:ctx];
        CHECK(at(50, 10)[2] == 255 && at(50, 10)[0] == 0);   /* inside the circle */
        CHECK(at(41, 1)[0] == 255);                           /* the corner outside it */
        CAGradientLayer *grad = [CAGradientLayer layer];
        grad.frame = CGRectMake(0, 0, 64, 64);
        grad.colors = @[(__bridge id)red, (__bridge id)blue];
        grad.startPoint = CGPointMake(0, 0);
        grad.endPoint = CGPointMake(1, 0);
        [grad renderInContext:ctx];
        CHECK(at(1, 30)[0] > 240 && at(62, 30)[2] > 240 && at(32, 30)[0] > 90 && at(32, 30)[0] < 165);

        /* a text layer draws something with a font present */
        CATextLayer *text = [CATextLayer layer];
        text.frame = CGRectMake(0, 0, 64, 64);
        text.string = @"Hi";
        text.fontSize = 30;
        text.foregroundColor = blue;
        CGContextClearRect(ctx, CGRectMake(0, 0, 64, 64));
        [text renderInContext:ctx];
        int inked = 0;
        for (int i = 0; i < 64 * 64; i++) if (px[i * 4 + 3]) inked++;
        CHECK(inked > 20);

        /* animations: start, then a finished stop after the duration */
        AnimDelegate *del = [AnimDelegate new];
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        anim.fromValue = @0;
        anim.toValue = @1;
        anim.duration = 0.05;
        anim.delegate = del;
        [child addAnimation:anim forKey:@"fade"];
        CHECK(del.started == 1);
        CHECK([[child animationForKey:@"fade"] isKindOfClass:[CABasicAnimation class]]);
        CHECK([[(CABasicAnimation *)[child animationForKey:@"fade"] keyPath] isEqualToString:@"opacity"]);
        CHECK([child.animationKeys isEqualToArray:@[@"fade"]]);
        CHECK(spin_until(^{ return (BOOL)(del.stopped == 1); }));
        CHECK(del.finished && [child animationForKey:@"fade"] == nil);
        AnimDelegate *del2 = [AnimDelegate new];
        CAKeyframeAnimation *kf = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        kf.duration = 10;
        kf.delegate = del2;
        [child addAnimation:kf forKey:nil];
        CHECK(child.animationKeys.count == 1);
        [child removeAllAnimations];
        CHECK(del2.stopped == 1 && !del2.finished && child.animationKeys == nil);

        CASpringAnimation *spring = [[CASpringAnimation alloc] initWithPerceptualDuration:0.5 bounce:0];
        CHECK(fabs(spring.perceptualDuration - 0.5) < 1e-6 && fabs(spring.bounce) < 1e-6 && spring.settlingDuration > 0);
        float cp[2];
        [[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn] getControlPointAtIndex:1 values:cp];
        CHECK(fabsf(cp[0] - 0.42f) < 1e-6f && cp[1] == 0);

        /* transactions: nested values, the completion block at the outer commit */
        __block int completed = 0;
        [CATransaction begin];
        [CATransaction setAnimationDuration:2];
        [CATransaction setCompletionBlock:^{ completed++; }];
        [CATransaction begin];
        CHECK([CATransaction animationDuration] == 2);
        [CATransaction setDisableActions:YES];
        CHECK([CATransaction disableActions]);
        [CATransaction commit];
        CHECK(![CATransaction disableActions]);
        [CATransaction commit];
        CHECK([CATransaction animationDuration] == 0.25);
        CHECK(spin_until(^{ return (BOOL)(completed == 1); }));

        /* display links tick on the run loop */
        Ticker *ticker = [Ticker new];
        CADisplayLink *link = [CADisplayLink _bn_displayLinkWithTarget:ticker selector:@selector(tick:)];
        [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        CHECK(spin_until(^{ return (BOOL)(ticker.ticks >= 3); }));
        CHECK(link.timestamp > 0 && NEAR(link.duration, 1.0 / 60));
        [link invalidate];
        int ticks = ticker.ticks;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        CHECK(ticker.ticks == ticks);

        CGContextRelease(ctx);
        CGColorSpaceRelease(rgb);
        CGColorRelease(red);
        CGColorRelease(blue);
    }
    printf("quartzcore ok\n");
    return 0;
}
