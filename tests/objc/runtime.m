// Objective-C runtime: classes, messaging, categories, protocols, ARC,
// weak references, blocks, properties, dynamic classes.
#include "objc.h"

static int deallocs, loads, initializes;
static char order[64];
static int order_len;
static void note(char c) { if (order_len < 63) order[order_len++] = c; }

@protocol Shape
- (int)sides;
@optional
- (int)optionalThing;
@end

@interface Animal : NSObject <NSCopying> {
    int _legs;
}
@property (nonatomic, strong) id friend;
@property (atomic, strong) id guardian;
@property (nonatomic, weak) id owner;
@property (nonatomic, assign) long tag;
+ (int)kingdom;
- (id)initWithLegs:(int)legs;
- (int)legs;
- (const char *)sound;
- (long)add:(long)a to:(long)b and:(long)c and:(long)d and:(long)e and:(long)f and:(long)g and:(long)h;
- (double)half:(double)x;
@end

@implementation Animal
+ (void)load { loads++; note('A'); }
+ (void)initialize { if (self == [Animal class]) { initializes++; note('i'); } }
+ (int)kingdom { return 7; }
- (id)initWithLegs:(int)legs { if ((self = [super init])) _legs = legs; return self; }
- (int)legs { return _legs; }
- (const char *)sound { return "..."; }
- (long)add:(long)a to:(long)b and:(long)c and:(long)d and:(long)e and:(long)f and:(long)g and:(long)h {
    return a + b + c + d + e + f + g + h + _legs;
}
- (double)half:(double)x { return x / 2; }
- (id)copyWithZone:(void *)zone { Animal *a = [[[self class] alloc] initWithLegs:_legs]; a.tag = self.tag; return a; }
- (void)dealloc { deallocs++; }
@end

@interface Dog : Animal <Shape> {
    long _bones;       // lives after the superclass's ivars
    id _toy;           // released by ARC's .cxx_destruct
}
- (long)bones;
- (void)setToy:(id)toy;
@end

@implementation Dog
+ (void)load { loads++; note('D'); }
- (id)initWithLegs:(int)legs { if ((self = [super initWithLegs:legs])) _bones = 1000 + legs; return self; }
- (const char *)sound { return "woof"; }
- (long)bones { return _bones; }
- (int)sides { return 4; }
- (void)setToy:(id)toy { _toy = toy; }
@end

@interface Animal (Tricks)
- (int)trick;
- (const char *)sound2;
@end
@implementation Animal (Tricks)
+ (void)load { loads++; note('c'); }
- (int)trick { return 42; }
- (const char *)sound2 { return [self sound]; }
@end

struct Big { long a, b, c, d; };
@interface Maker : NSObject
- (struct Big)bigWith:(long)x;
- (long double)pi;
@end
@implementation Maker
- (struct Big)bigWith:(long)x { struct Big b = {x, x * 2, x * 3, x * 4}; return b; }
- (long double)pi { return 3.25L; }
@end

@interface Proxyish : NSObject {
    id _target;
}
- (id)initWithTarget:(id)t;
@end
@implementation Proxyish
- (id)initWithTarget:(id)t { if ((self = [super init])) _target = t; return self; }
- (id)forwardingTargetForSelector:(SEL)sel { return _target; }
@end

static int dynamic_answer(id self, SEL _cmd) { return 99; }
@interface Lazy : NSObject
@end
@implementation Lazy
+ (BOOL)resolveInstanceMethod:(SEL)sel {
    if (strcmp(sel_getName(sel), "lazyValue") == 0) {
        class_addMethod(self, sel, (void (*)(void))dynamic_answer, "i16@0:8");
        return YES;
    }
    return [super resolveInstanceMethod:sel];
}
@end
@interface Lazy (Declared)
- (int)lazyValue;
@end

static int swapped_a(id self, SEL _cmd) { return 1; }
static int swapped_b(id self, SEL _cmd) { return 2; }

int main(void) {
    // +load ran for classes (superclass first) and then the category, before main
    CHECK(loads == 3);
    CHECK(order[0] == 'A' && order[1] == 'D' && order[2] == 'c');
    CHECK(initializes == 0);

    @autoreleasepool {
        Dog *d = [[Dog alloc] initWithLegs:4];
        CHECK(initializes == 1);
        CHECK([d legs] == 4 && [d bones] == 1004);
        CHECK(strcmp([d sound], "woof") == 0);
        CHECK([Dog kingdom] == 7);
        CHECK([d trick] == 42 && strcmp([d sound2], "woof") == 0);
        CHECK([d add:1 to:2 and:3 and:4 and:5 and:6 and:7 and:8] == 40);
        CHECK([d half:9.0] == 4.5);
        CHECK([d isKindOfClass:[Animal class]] && ![d isMemberOfClass:[Animal class]]);
        CHECK([d class] == [Dog class] && [Dog superclass] == [Animal class]);
        CHECK([d respondsToSelector:@selector(sides)] && ![d respondsToSelector:@selector(optionalThing)]);
        CHECK([d conformsToProtocol:@protocol(Shape)] && [d conformsToProtocol:@protocol(NSCopying)]);
        CHECK(![[Animal new] conformsToProtocol:@protocol(Shape)]);
        CHECK(strcmp(class_getName([d class]), "Dog") == 0);
        CHECK(objc_getClass("Dog") == [Dog class] && objc_getClass("NoSuchClass") == nil);
        CHECK(class_getInstanceSize([Dog class]) >= class_getInstanceSize([Animal class]) + 16);
        CHECK((long)[d performSelector:@selector(legs)] == 4);

        // nil receives everything and returns zero
        Dog *none = nil;
        CHECK([none legs] == 0 && [none half:3.0] == 0.0 && [none sound] == NULL);

        // struct and long double returns
        Maker *m = [Maker new];
        struct Big b = [m bigWith:5];
        CHECK(b.a == 5 && b.b == 10 && b.c == 15 && b.d == 20);
        CHECK([m pi] == 3.25L);

        // copy through NSCopying
        d.tag = 77;
        Animal *copy = [d copy];
        CHECK(copy != d && [copy class] == [Dog class] && copy.tag == 77 && [copy legs] == 4);
    }
    // d, its copy, the Animal from +new and Maker are gone
    CHECK(deallocs == 3);

    // strong / weak properties and ivars under ARC
    deallocs = 0;
    __weak Animal *weak_friend;
    @autoreleasepool {
        Dog *d = [[Dog alloc] initWithLegs:3];
        @autoreleasepool {
            Animal *f = [[Animal alloc] initWithLegs:2];
            weak_friend = f;
            d.friend = f;
            d.guardian = f;
            [d setToy:f];
            d.owner = f;
        }
        CHECK(deallocs == 0 && weak_friend != nil && d.owner == weak_friend);
        d.friend = nil;
        d.guardian = nil;
        CHECK(deallocs == 0);       // still held by the _toy ivar
        [d setToy:nil];
        CHECK(deallocs == 1);
        CHECK(weak_friend == nil && d.owner == nil);   // weak references were cleared
        Animal *again = [[Animal alloc] initWithLegs:1];
        [d setToy:again];
    }
    CHECK(deallocs == 3);  // the dog, and the toy released by .cxx_destruct

    // blocks capturing objects
    deallocs = 0;
    int (^blk)(void);
    @autoreleasepool {
        Animal *a = [[Animal alloc] initWithLegs:6];
        __block int calls = 0;
        blk = ^{ calls++; return [a legs] + calls; };
        CHECK(blk() == 7 && blk() == 8);
    }
    CHECK(deallocs == 0 && blk() == 9);   // the block keeps the animal alive
    blk = nil;
    CHECK(deallocs == 1);

    // forwarding target
    @autoreleasepool {
        Dog *d = [[Dog alloc] initWithLegs:8];
        Proxyish *p = [[Proxyish alloc] initWithTarget:d];
        CHECK([(id)p legs] == 8 && strcmp([(id)p sound], "woof") == 0);
        struct Big b = [(Maker *)[[Proxyish alloc] initWithTarget:[Maker new]] bigWith:2];
        CHECK(b.d == 8);
    }

    // dynamic method resolution
    CHECK([[Lazy new] lazyValue] == 99);
    CHECK([Lazy instancesRespondToSelector:@selector(lazyValue)]);

    // classes built at run time, method swizzling, associated objects
    Class dyn = objc_allocateClassPair([Animal class], "Robot", 0);
    CHECK(dyn != nil);
    class_addMethod(dyn, @selector(one), (void (*)(void))swapped_a, "i16@0:8");
    class_addMethod(dyn, @selector(two), (void (*)(void))swapped_b, "i16@0:8");
    objc_registerClassPair(dyn);
    CHECK(objc_getClass("Robot") == dyn && class_getSuperclass(dyn) == [Animal class]);
    id robot = [[dyn alloc] initWithLegs:2];
    CHECK([robot legs] == 2 && [robot trick] == 42);
    CHECK((int)(long)[robot performSelector:@selector(one)] == 1);
    method_exchangeImplementations(class_getInstanceMethod(dyn, @selector(one)),
                                   class_getInstanceMethod(dyn, @selector(two)));
    CHECK((int)(long)[robot performSelector:@selector(one)] == 2);

    deallocs = 0;
    static char key;
    @autoreleasepool {
        Animal *holder = [[Animal alloc] initWithLegs:1];
        @autoreleasepool {
            objc_setAssociatedObject(holder, &key, [[Animal alloc] initWithLegs:5], 1 /* RETAIN_NONATOMIC */);
        }
        CHECK(deallocs == 0);
        CHECK([objc_getAssociatedObject(holder, &key) legs] == 5);
    }
    CHECK(deallocs == 2);   // holder and its associated object

    @synchronized([Animal class]) { @synchronized([Animal class]) { deallocs = -1; } }
    CHECK(deallocs == -1);
    puts("objc runtime ok");
    return 0;
}
