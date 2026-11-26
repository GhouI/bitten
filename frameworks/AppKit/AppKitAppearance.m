/* NSAppearance: light ("Aqua") by default; BITTEN_APPEARANCE=dark selects
 * the dark one. Views and windows inherit their effective appearance from
 * their superview, window and finally the application. */
#import <AppKit/AppKit.h>
#include <pthread.h>
#include <stdlib.h>
#include <strings.h>

NSAppearanceName const NSAppearanceNameVibrantDark = @"NSAppearanceNameVibrantDark";
NSAppearanceName const NSAppearanceNameVibrantLight = @"NSAppearanceNameVibrantLight";
NSAppearanceName const NSAppearanceNameAccessibilityHighContrastAqua = @"NSAppearanceNameAccessibilityAqua";
NSAppearanceName const NSAppearanceNameAccessibilityHighContrastDarkAqua = @"NSAppearanceNameAccessibilityDarkAqua";
NSAppearanceName const NSAppearanceNameAccessibilityHighContrastVibrantLight =
    @"NSAppearanceNameAccessibilityVibrantLight";
NSAppearanceName const NSAppearanceNameAccessibilityHighContrastVibrantDark =
    @"NSAppearanceNameAccessibilityVibrantDark";
NSAppearanceName const NSAppearanceNameLightContent = @"NSAppearanceNameLightContent";

static pthread_key_t drawing_key;
static pthread_once_t drawing_once = PTHREAD_ONCE_INIT;
static void make_drawing_key(void) { pthread_key_create(&drawing_key, NULL); }

@implementation NSAppearance {
    NSAppearanceName _name;
}

+ (NSAppearance *)appearanceNamed:(NSAppearanceName)name {
    static NSMutableDictionary *cache;
    @synchronized(self) {
        if (!cache) cache = [NSMutableDictionary dictionary];
        NSAppearance *a = cache[name];
        if (!a) {
            a = [NSAppearance new];
            a->_name = [name copy];
            cache[name] = a;
        }
        return a;
    }
}
- (instancetype)initWithAppearanceNamed:(NSAppearanceName)name bundle:(NSBundle *)bundle {
    return [NSAppearance appearanceNamed:name];
}

/* The system appearance the container presents. */
+ (NSAppearance *)_bn_systemAppearance {
    const char *env = getenv("BITTEN_APPEARANCE");
    BOOL dark = env && !strcasecmp(env, "dark");
    return [self appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
}

- (NSAppearanceName)name { return _name; }
- (BOOL)_bn_isDark { return [_name rangeOfString:@"Dark"].location != NSNotFound; }
- (BOOL)allowsVibrancy { return [_name rangeOfString:@"Vibrant"].location != NSNotFound; }

- (NSAppearanceName)bestMatchFromAppearancesWithNames:(NSArray<NSAppearanceName> *)names {
    if ([names containsObject:_name]) return _name;
    BOOL dark = [self _bn_isDark];
    for (NSAppearanceName n in names)
        if (([n rangeOfString:@"Dark"].location != NSNotFound) == dark) return n;
    return nil;
}

+ (NSAppearance *)currentDrawingAppearance {
    pthread_once(&drawing_once, make_drawing_key);
    NSAppearance *a = (__bridge NSAppearance *)pthread_getspecific(drawing_key);
    return a ?: [NSApplication sharedApplication].effectiveAppearance;
}
+ (NSAppearance *)currentAppearance { return [self currentDrawingAppearance]; }
+ (void)setCurrentAppearance:(NSAppearance *)appearance {
    pthread_once(&drawing_once, make_drawing_key);
    pthread_setspecific(drawing_key, (__bridge void *)appearance);
}
- (void)performAsCurrentDrawingAppearance:(void (^)(void))block {
    pthread_once(&drawing_once, make_drawing_key);
    void *previous = pthread_getspecific(drawing_key);
    pthread_setspecific(drawing_key, (__bridge void *)self);
    block();
    pthread_setspecific(drawing_key, previous);
}

+ (BOOL)supportsSecureCoding { return YES; }
- (NSString *)description { return [NSString stringWithFormat:@"<NSAppearance: %p %@>", self, _name]; }
@end

@implementation NSApplication (BittenAppearance)
- (NSAppearance *)effectiveAppearance { return self.appearance ?: [NSAppearance _bn_systemAppearance]; }
@end

@implementation NSWindow (BittenAppearance)
- (NSAppearance *)appearance { return objc_getAssociatedObject(self, @selector(appearance)); }
- (void)setAppearance:(NSAppearance *)appearance {
    objc_setAssociatedObject(self, @selector(appearance), appearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSAppearance *)effectiveAppearance { return self.appearance ?: [NSApplication sharedApplication].effectiveAppearance; }
@end

@implementation NSView (BittenAppearance)
- (NSAppearance *)appearance { return objc_getAssociatedObject(self, @selector(appearance)); }
- (void)setAppearance:(NSAppearance *)appearance {
    objc_setAssociatedObject(self, @selector(appearance), appearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSAppearance *)effectiveAppearance {
    NSAppearance *a = self.appearance;
    if (a) return a;
    if (self.superview) return self.superview.effectiveAppearance;
    if (self.window) return self.window.effectiveAppearance;
    return [NSApplication sharedApplication].effectiveAppearance;
}
- (void)viewDidChangeEffectiveAppearance {}
@end
