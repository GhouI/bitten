/* NSColorSpace, and NSColor's colour-space methods. Colours keep sRGB
 * components (extended: outside 0...1 for wider gamuts) and remember the
 * space they were made in; their component accessors report sRGB. */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <math.h>

@implementation NSColorSpace {
    NSString *_name;
    CFStringRef _cgName;
    NSInteger _model;
    NSInteger _components;
}
static NSColorSpace *space(NSString *name, CFStringRef cg, NSInteger model, NSInteger n) {
    NSColorSpace *s = [[NSColorSpace alloc] init];
    s->_name = name;
    s->_cgName = cg;
    s->_model = model;
    s->_components = n;
    return s;
}
#define SPACE(sel, label, cgname, model, n)                                \
    +(NSColorSpace *)sel {                                                 \
        static NSColorSpace *s;                                            \
        static dispatch_once_t once;                                       \
        dispatch_once(&once, ^{ s = space(@label, cgname, model, n); });   \
        return s;                                                          \
    }
SPACE(sRGBColorSpace, "sRGB IEC61966-2.1", kCGColorSpaceSRGB, NSColorSpaceModelRGB, 3)
SPACE(extendedSRGBColorSpace, "Extended sRGB", kCGColorSpaceExtendedSRGB, NSColorSpaceModelRGB, 3)
SPACE(displayP3ColorSpace, "Display P3", kCGColorSpaceDisplayP3, NSColorSpaceModelRGB, 3)
SPACE(genericRGBColorSpace, "Generic RGB", kCGColorSpaceSRGB, NSColorSpaceModelRGB, 3)
SPACE(deviceRGBColorSpace, "Device RGB", kCGColorSpaceSRGB, NSColorSpaceModelRGB, 3)
SPACE(genericGamma22GrayColorSpace, "Generic Gray Gamma 2.2", kCGColorSpaceGenericGrayGamma2_2,
      NSColorSpaceModelGray, 1)
SPACE(extendedGenericGamma22GrayColorSpace, "Extended Gray", kCGColorSpaceGenericGrayGamma2_2,
      NSColorSpaceModelGray, 1)
SPACE(deviceGrayColorSpace, "Device Gray", kCGColorSpaceGenericGrayGamma2_2, NSColorSpaceModelGray, 1)
- (instancetype)initWithCGColorSpace:(CGColorSpaceRef)cs {
    self = [super init];
    _name = @"Color space";
    _cgName = kCGColorSpaceSRGB;
    _model = CGColorSpaceGetModel(cs) == kCGColorSpaceModelMonochrome ? NSColorSpaceModelGray : NSColorSpaceModelRGB;
    _components = _model == NSColorSpaceModelGray ? 1 : 3;
    return self;
}
- (NSString *)localizedName { return _name; }
- (NSColorSpaceModel)colorSpaceModel { return _model; }
- (NSInteger)numberOfColorComponents { return _components; }
- (CGColorSpaceRef)CGColorSpace {
    static const char key;
    id cached = objc_getAssociatedObject(self, &key);
    if (cached) return (__bridge CGColorSpaceRef)cached;
    CGColorSpaceRef c = CGColorSpaceCreateWithName(_cgName);
    if (!c) return NULL;
    objc_setAssociatedObject(self, &key, (__bridge_transfer id)c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return c;
}
- (BOOL)isP3 { return _cgName == kCGColorSpaceDisplayP3; }
- (NSString *)description { return [NSString stringWithFormat:@"%@ colorspace", _name]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

/* Display P3 and sRGB share the transfer curve and white point; only the
 * primaries differ. */
static double to_linear(double v) {
    double a = fabs(v), r = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4);
    return v < 0 ? -r : r;
}
static double from_linear(double v) {
    double a = fabs(v), r = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055;
    return v < 0 ? -r : r;
}
static void p3_to_srgb(const CGFloat in[3], CGFloat out[3]) {
    static const double m[3][3] = {{1.2249401, -0.2249404, 0.0}, {-0.0420569, 1.0420571, 0.0},
                                   {-0.0196376, -0.0786361, 1.0982735}};
    double l[3] = {to_linear(in[0]), to_linear(in[1]), to_linear(in[2])};
    for (int i = 0; i < 3; i++) out[i] = from_linear(m[i][0] * l[0] + m[i][1] * l[1] + m[i][2] * l[2]);
}
static void srgb_to_p3(const CGFloat in[3], CGFloat out[3]) {
    static const double m[3][3] = {{0.8224621, 0.1775380, 0.0}, {0.0331941, 0.9668058, 0.0},
                                   {0.0170827, 0.0723974, 0.9105199}};
    double l[3] = {to_linear(in[0]), to_linear(in[1]), to_linear(in[2])};
    for (int i = 0; i < 3; i++) out[i] = from_linear(m[i][0] * l[0] + m[i][1] * l[1] + m[i][2] * l[2]);
}

static const char space_key;

@implementation NSColor (BittenColorSpace)
+ (NSColor *)colorWithDisplayP3Red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    CGFloat in[3] = {r, g, b}, out[3];
    p3_to_srgb(in, out);
    NSColor *c = [NSColor colorWithSRGBRed:out[0] green:out[1] blue:out[2] alpha:a];
    objc_setAssociatedObject(c, &space_key, [NSColorSpace displayP3ColorSpace], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return c;
}
+ (NSColor *)colorWithColorSpace:(NSColorSpace *)space components:(const CGFloat *)comps count:(NSInteger)n {
    NSColor *c;
    if (space.colorSpaceModel == NSColorSpaceModelGray || n < 3) {
        c = [NSColor colorWithWhite:n > 0 ? comps[0] : 0 alpha:n > 1 ? comps[1] : 1];
    } else if ([space isP3]) {
        return [self colorWithDisplayP3Red:comps[0] green:comps[1] blue:comps[2] alpha:n > 3 ? comps[3] : 1];
    } else {
        c = [NSColor colorWithSRGBRed:comps[0] green:comps[1] blue:comps[2] alpha:n > 3 ? comps[3] : 1];
    }
    objc_setAssociatedObject(c, &space_key, space, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return c;
}
+ (NSColor *)colorWithDeviceRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    return [self colorWithSRGBRed:r green:g blue:b alpha:a];
}
+ (NSColor *)colorWithDeviceWhite:(CGFloat)w alpha:(CGFloat)a { return [self colorWithWhite:w alpha:a]; }
+ (NSColor *)colorWithCalibratedWhite:(CGFloat)w alpha:(CGFloat)a { return [self colorWithWhite:w alpha:a]; }
- (NSColorSpace *)colorSpace {
    NSColorSpace *s = objc_getAssociatedObject(self, &space_key);
    return s ? s : [NSColorSpace sRGBColorSpace];
}
- (NSColor *)colorUsingColorSpace:(NSColorSpace *)space {
    if (!space) return nil;
    if (space == self.colorSpace) return self;
    CGFloat srgb[3] = {self.redComponent, self.greenComponent, self.blueComponent};
    if ([space isP3]) {
        CGFloat p3[4];
        srgb_to_p3(srgb, p3);
        p3[3] = self.alphaComponent;
        return [NSColor colorWithColorSpace:space components:p3 count:4];
    }
    if (space.colorSpaceModel == NSColorSpaceModelGray) {
        CGFloat g[2] = {0.2126 * srgb[0] + 0.7152 * srgb[1] + 0.0722 * srgb[2], self.alphaComponent};
        return [NSColor colorWithColorSpace:space components:g count:2];
    }
    CGFloat out[4] = {srgb[0], srgb[1], srgb[2], self.alphaComponent};
    return [NSColor colorWithColorSpace:space components:out count:4];
}
- (NSInteger)numberOfComponents { return self.colorSpace.numberOfColorComponents + 1; }
- (void)getComponents:(CGFloat *)components {
    components[0] = self.redComponent;
    components[1] = self.greenComponent;
    components[2] = self.blueComponent;
    components[3] = self.alphaComponent;
}
- (void)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a {
    if (r) *r = self.redComponent;
    if (g) *g = self.greenComponent;
    if (b) *b = self.blueComponent;
    if (a) *a = self.alphaComponent;
}
- (CGFloat)whiteComponent { return 0.2126 * self.redComponent + 0.7152 * self.greenComponent + 0.0722 * self.blueComponent; }
@end
