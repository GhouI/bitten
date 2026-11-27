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
/* The thread's drawing appearance is owned by the thread (retained). */
static void set_drawing(NSAppearance *appearance) {
    pthread_once(&drawing_once, make_drawing_key);
    void *old = pthread_getspecific(drawing_key);
    pthread_setspecific(drawing_key, appearance ? (__bridge_retained void *)appearance : NULL);
    if (old) (void)(__bridge_transfer NSAppearance *)old;
}
+ (void)setCurrentAppearance:(NSAppearance *)appearance { set_drawing(appearance); }
/* Sets the drawing appearance and returns what was set before (nil when
 * nothing was: the application's appearance applied). */
+ (NSAppearance *)_bn_swapDrawingAppearance:(NSAppearance *)appearance {
    pthread_once(&drawing_once, make_drawing_key);
    void *raw = pthread_getspecific(drawing_key);
    NSAppearance *previous = raw ? (__bridge NSAppearance *)raw : nil;
    set_drawing(appearance);
    return previous;
}
- (void)performAsCurrentDrawingAppearance:(NS_NOESCAPE void (^)(void))block {
    pthread_once(&drawing_once, make_drawing_key);
    void *raw = pthread_getspecific(drawing_key);
    NSAppearance *previous = raw ? (__bridge NSAppearance *)raw : nil;
    set_drawing(self);
    block();
    set_drawing(previous);
}

+ (BOOL)supportsSecureCoding { return YES; }
- (NSString *)description { return [NSString stringWithFormat:@"<NSAppearance: %p %@>", self, _name]; }
@end

@implementation NSApplication (BittenAppearance)
- (NSAppearance *)effectiveAppearance { return self.appearance ?: [NSAppearance _bn_systemAppearance]; }
@end

/* Views whose effective appearance may have changed hear of it, and redraw. */
static void tell_appearance_changed(NSView *v) {
    [v viewDidChangeEffectiveAppearance];
    v.needsDisplay = YES;
    for (NSView *s in v.subviews) tell_appearance_changed(s);
}

@interface NSWindow (BittenScheduleDisplay)
- (void)_bn_scheduleDisplay;
@end
@implementation NSWindow (BittenAppearance)
- (NSAppearance *)appearance { return objc_getAssociatedObject(self, @selector(appearance)); }
- (void)setAppearance:(NSAppearance *)appearance {
    objc_setAssociatedObject(self, @selector(appearance), appearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _bn_appearanceChanged];
}
- (void)_bn_appearanceChanged {
    if (self._bn_frameView) tell_appearance_changed(self._bn_frameView);
    if (self.isVisible) [self _bn_scheduleDisplay]; /* may come in the middle of drawing */
}
- (NSAppearance *)effectiveAppearance { return self.appearance ?: [NSApplication sharedApplication].effectiveAppearance; }
@end

@implementation NSView (BittenAppearance)
- (NSAppearance *)appearance { return objc_getAssociatedObject(self, @selector(appearance)); }
- (void)setAppearance:(NSAppearance *)appearance {
    if (appearance == self.appearance) return;
    objc_setAssociatedObject(self, @selector(appearance), appearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    tell_appearance_changed(self);
    self.needsDisplay = YES;
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
