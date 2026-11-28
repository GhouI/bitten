/* CoreImage on the CPU. An image is pixels (premultiplied RGBA in a
 * CGImage, placed at its extent's origin) or a solid colour with an
 * infinite extent; filters compute their output when asked for it. */
#import <CoreImage/CoreImage.h>
#import <objc/message.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

CIImageOption const kCIImageColorSpace = @"kCIImageColorSpace";
CIContextOption const kCIContextCacheIntermediates = @"kCIContextCacheIntermediates",
    kCIContextWorkingColorSpace = @"kCIContextWorkingColorSpace",
    kCIContextUseSoftwareRenderer = @"kCIContextUseSoftwareRenderer";
NSString *const kCIInputImageKey = @"inputImage", *const kCIInputBackgroundImageKey = @"inputBackgroundImage",
    *const kCIInputColorKey = @"inputColor", *const kCIInputIntensityKey = @"inputIntensity",
    *const kCIInputSaturationKey = @"inputSaturation", *const kCIInputBrightnessKey = @"inputBrightness",
    *const kCIInputContrastKey = @"inputContrast", *const kCIOutputImageKey = @"outputImage";

static CGFloat clamp01(CGFloat v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

/* ---- colours ---- */

@implementation CIColor {
    CGFloat _c[4];
}
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    return [[self alloc] initWithRed:r green:g blue:b alpha:a];
}
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b { return [self colorWithRed:r green:g blue:b alpha:1]; }
+ (instancetype)colorWithCGColor:(CGColorRef)c { return [[self alloc] initWithCGColor:c]; }
- (instancetype)initWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    if ((self = [super init])) { _c[0] = r; _c[1] = g; _c[2] = b; _c[3] = a; }
    return self;
}
- (instancetype)initWithCGColor:(CGColorRef)c {
    size_t n = c ? CGColorGetNumberOfComponents(c) : 0;
    const CGFloat *v = c ? CGColorGetComponents(c) : NULL;
    if (n >= 4) return [self initWithRed:v[0] green:v[1] blue:v[2] alpha:v[3]];
    if (n == 2) return [self initWithRed:v[0] green:v[0] blue:v[0] alpha:v[1]];
    return [self initWithRed:0 green:0 blue:0 alpha:1];
}
- (CGFloat)red { return _c[0]; }
- (CGFloat)green { return _c[1]; }
- (CGFloat)blue { return _c[2]; }
- (CGFloat)alpha { return _c[3]; }
- (size_t)numberOfComponents { return 4; }
- (NSString *)stringRepresentation { return [NSString stringWithFormat:@"%g %g %g %g", _c[0], _c[1], _c[2], _c[3]]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)isEqual:(id)o {
    if (![o isKindOfClass:[CIColor class]]) return NO;
    CIColor *c = o;
    return c.red == _c[0] && c.green == _c[1] && c.blue == _c[2] && c.alpha == _c[3];
}
- (NSUInteger)hash { return (NSUInteger)(_c[0] * 1000 + _c[1] * 100 + _c[2] * 10 + _c[3]); }
+ (CIColor *)blackColor { return [self colorWithRed:0 green:0 blue:0]; }
+ (CIColor *)whiteColor { return [self colorWithRed:1 green:1 blue:1]; }
+ (CIColor *)clearColor { return [self colorWithRed:0 green:0 blue:0 alpha:0]; }
+ (CIColor *)grayColor { return [self colorWithRed:0.5 green:0.5 blue:0.5]; }
+ (CIColor *)redColor { return [self colorWithRed:1 green:0 blue:0]; }
+ (CIColor *)greenColor { return [self colorWithRed:0 green:1 blue:0]; }
+ (CIColor *)blueColor { return [self colorWithRed:0 green:0 blue:1]; }
/* AppKit's addition (CIColor from an NSColor), made here from the colour's
 * CGColor so CoreImage needn't link AppKit. */
- (instancetype)initWithColor:(id)color {
    SEL cg = sel_registerName("CGColor");
    if (![color respondsToSelector:cg]) return [self initWithRed:0 green:0 blue:0 alpha:1];
    CGColorRef c = ((CGColorRef (*)(id, SEL))objc_msgSend)(color, cg);
    return [self initWithCGColor:c];
}
@end

/* ---- pixels ---- */

/* A premultiplied RGBA buffer, rows top to bottom, covering `rect`. */
typedef struct {
    uint8_t *px;
    size_t w, h;
    CGRect rect;
} Pixels;

static CGContextRef bitmap(size_t w, size_t h, void *data) {
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(data, w ? w : 1, h ? h : 1, 8, (w ? w : 1) * 4, rgb,
                                             kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(rgb);
    return ctx;
}

static CGImageRef image_from(Pixels p) CF_RETURNS_RETAINED {
    CGContextRef ctx = bitmap(p.w, p.h, p.px);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}

@interface CIImage ()
- (Pixels)_bn_pixelsIn:(CGRect)rect;
@end

@implementation CIImage {
    CGImageRef _image;         /* or NULL for a colour */
    CIColor *_color;
    CGRect _extent;
}
+ (instancetype)imageWithCGImage:(CGImageRef)image { return [[self alloc] initWithCGImage:image]; }
+ (instancetype)imageWithCGImage:(CGImageRef)image options:(NSDictionary *)options { return [[self alloc] initWithCGImage:image]; }
+ (instancetype)imageWithColor:(CIColor *)color { return [[self alloc] initWithColor:color]; }
+ (instancetype)emptyImage { return [[self alloc] initWithColor:[CIColor clearColor]]; }
- (instancetype)initWithCGImage:(CGImageRef)image options:(NSDictionary *)options { return [self initWithCGImage:image]; }
- (instancetype)initWithCGImage:(CGImageRef)image {
    if ((self = [super init])) {
        _image = image ? CGImageRetain(image) : NULL;
        _extent = CGRectMake(0, 0, image ? CGImageGetWidth(image) : 0, image ? CGImageGetHeight(image) : 0);
    }
    return self;
}
- (instancetype)initWithColor:(CIColor *)color {
    if ((self = [super init])) {
        _color = color ?: [CIColor clearColor];
        _extent = CGRectInfinite;
    }
    return self;
}
- (instancetype)initWithBNImage:(CGImageRef)image extent:(CGRect)extent {
    if ((self = [super init])) {
        _image = image ? CGImageRetain(image) : NULL;
        _extent = extent;
    }
    return self;
}
- (void)dealloc { if (_image) CGImageRelease(_image); }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (CGRect)extent { return _extent; }
- (CGImageRef)CGImage { return _image && CGPointEqualToPoint(_extent.origin, CGPointZero) ? _image : NULL; }

/* This image drawn into a buffer covering rect. */
- (Pixels)_bn_pixelsIn:(CGRect)rect {
    rect = CGRectIntegral(rect);
    Pixels p = {NULL, (size_t)fmax(rect.size.width, 0), (size_t)fmax(rect.size.height, 0), rect};
    p.px = calloc(p.w * p.h ? p.w * p.h : 1, 4);
    CGContextRef ctx = bitmap(p.w, p.h, p.px);
    CGContextTranslateCTM(ctx, -rect.origin.x, -rect.origin.y);
    if (_image) {
        CGContextDrawImage(ctx, _extent, _image);
    } else if (_color) {
        CGContextSetRGBFillColor(ctx, _color.red, _color.green, _color.blue, _color.alpha);
        CGContextFillRect(ctx, CGRectIsInfinite(_extent) ? rect : CGRectIntersection(rect, _extent));
    }
    CGContextRelease(ctx);
    return p;
}
- (CIImage *)_bn_imageWithPixels:(Pixels)p {
    CGImageRef img = image_from(p);
    free(p.px);
    CIImage *out = [[CIImage alloc] initWithBNImage:img extent:p.rect];
    CGImageRelease(img);
    return out;
}

- (CIImage *)imageByCroppingToRect:(CGRect)rect {
    CGRect r = CGRectIntersection(_extent, rect);
    if (CGRectIsNull(r) || CGRectIsEmpty(r)) return [[CIImage alloc] initWithBNImage:NULL extent:CGRectZero];
    return [self _bn_imageWithPixels:[self _bn_pixelsIn:r]];
}
- (CIImage *)imageByApplyingTransform:(CGAffineTransform)m {
    if (!_image) return self;
    CGRect r = CGRectIntegral(CGRectApplyAffineTransform(_extent, m));
    Pixels p = {NULL, (size_t)r.size.width, (size_t)r.size.height, r};
    p.px = calloc(p.w * p.h ? p.w * p.h : 1, 4);
    CGContextRef ctx = bitmap(p.w, p.h, p.px);
    CGContextTranslateCTM(ctx, -r.origin.x, -r.origin.y);
    CGContextConcatCTM(ctx, m);
    CGContextDrawImage(ctx, _extent, _image);
    CGContextRelease(ctx);
    return [self _bn_imageWithPixels:p];
}
- (CIImage *)imageByApplyingFilter:(NSString *)name withInputParameters:(NSDictionary *)params {
    CIFilter *f = [CIFilter filterWithName:name];
    if (!f) return self;
    [f setValue:self forKey:kCIInputImageKey];
    for (NSString *k in params) [f setValue:params[k] forKey:k];
    return f.outputImage ?: self;
}
- (CIImage *)imageByApplyingFilter:(NSString *)name { return [self imageByApplyingFilter:name withInputParameters:nil]; }
- (CIImage *)imageByCompositingOverImage:(CIImage *)dest {
    return [self imageByApplyingFilter:@"CISourceOverCompositing" withInputParameters:@{kCIInputBackgroundImageKey: dest}];
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<CIImage: %p extent [%g %g %g %g]>", (void *)self, _extent.origin.x,
            _extent.origin.y, _extent.size.width, _extent.size.height];
}
@end

/* ---- filters ---- */

typedef enum { F_MONOCHROME, F_INVERT, F_SEPIA, F_CONTROLS, F_OVER, F_CONSTANT } FilterKind;

static NSDictionary<NSString *, NSNumber *> *filter_kinds(void) {
    static NSDictionary *d;
    if (!d) d = @{@"CIColorMonochrome": @(F_MONOCHROME), @"CIColorInvert": @(F_INVERT), @"CISepiaTone": @(F_SEPIA),
                  @"CIColorControls": @(F_CONTROLS), @"CISourceOverCompositing": @(F_OVER),
                  @"CIConstantColorGenerator": @(F_CONSTANT)};
    return d;
}

@implementation CIFilter {
    NSString *_name;
    FilterKind _kind;
    NSMutableDictionary *_values;
}
+ (CIFilter *)filterWithName:(NSString *)name {
    NSNumber *k = name ? filter_kinds()[name] : nil;
    if (!k) return nil;
    CIFilter *f = [self new];
    f->_name = [name copy];
    f->_kind = (FilterKind)k.intValue;
    f->_values = [NSMutableDictionary dictionary];
    [f setDefaults];
    return f;
}
+ (CIFilter *)filterWithName:(NSString *)name withInputParameters:(NSDictionary *)params {
    CIFilter *f = [self filterWithName:name];
    for (NSString *k in params) [f setValue:params[k] forKey:k];
    return f;
}
+ (NSArray<NSString *> *)filterNamesInCategory:(NSString *)category {
    return [filter_kinds().allKeys sortedArrayUsingSelector:@selector(compare:)];
}
- (NSString *)name { return _name; }
- (id)copyWithZone:(NSZone *)zone {
    CIFilter *f = [CIFilter filterWithName:_name];
    [f->_values removeAllObjects];
    [f->_values addEntriesFromDictionary:_values];
    return f;
}
- (void)setDefaults {
    switch (_kind) {
    case F_MONOCHROME:
        _values[kCIInputColorKey] = [CIColor colorWithRed:0.6 green:0.45 blue:0.3];
        _values[kCIInputIntensityKey] = @1.0;
        break;
    case F_SEPIA: _values[kCIInputIntensityKey] = @1.0; break;
    case F_CONTROLS:
        _values[kCIInputSaturationKey] = @1.0;
        _values[kCIInputBrightnessKey] = @0.0;
        _values[kCIInputContrastKey] = @1.0;
        break;
    case F_CONSTANT: _values[kCIInputColorKey] = [CIColor blackColor]; break;
    default: break;
    }
}
- (NSArray<NSString *> *)inputKeys {
    switch (_kind) {
    case F_MONOCHROME: return @[kCIInputImageKey, kCIInputColorKey, kCIInputIntensityKey];
    case F_SEPIA: return @[kCIInputImageKey, kCIInputIntensityKey];
    case F_CONTROLS: return @[kCIInputImageKey, kCIInputSaturationKey, kCIInputBrightnessKey, kCIInputContrastKey];
    case F_OVER: return @[kCIInputImageKey, kCIInputBackgroundImageKey];
    case F_CONSTANT: return @[kCIInputColorKey];
    default: return @[kCIInputImageKey];
    }
}
- (NSArray<NSString *> *)outputKeys { return @[kCIOutputImageKey]; }
- (NSDictionary *)attributes { return @{@"CIAttributeFilterName": _name}; }
- (void)setValue:(id)value forKey:(NSString *)key {
    if (value) _values[key] = value;
    else [_values removeObjectForKey:key];
}
- (id)valueForKey:(NSString *)key {
    if ([key isEqualToString:kCIOutputImageKey]) return self.outputImage;
    return _values[key];
}

static CGFloat number(id v, CGFloat fallback) { return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback; }

/* Per pixel, on unpremultiplied colour. */
- (void)_bn_map:(Pixels)p {
    CIColor *color = _values[kCIInputColorKey];
    CGFloat intensity = clamp01(number(_values[kCIInputIntensityKey], 1));
    CGFloat sat = number(_values[kCIInputSaturationKey], 1), bri = number(_values[kCIInputBrightnessKey], 0),
            con = number(_values[kCIInputContrastKey], 1);
    for (size_t i = 0; i < p.w * p.h; i++) {
        uint8_t *q = p.px + i * 4;
        CGFloat a = q[3] / 255.0;
        if (a <= 0) continue;
        CGFloat r = q[0] / 255.0 / a, g = q[1] / 255.0 / a, b = q[2] / 255.0 / a;
        CGFloat l = 0.2125 * r + 0.7154 * g + 0.0721 * b;
        CGFloat nr = r, ng = g, nb = b;
        switch (_kind) {
        case F_MONOCHROME:
            nr = r + (color.red * l - r) * intensity;
            ng = g + (color.green * l - g) * intensity;
            nb = b + (color.blue * l - b) * intensity;
            break;
        case F_INVERT: nr = 1 - r; ng = 1 - g; nb = 1 - b; break;
        case F_SEPIA: {
            CGFloat sr = 0.393 * r + 0.769 * g + 0.189 * b, sg = 0.349 * r + 0.686 * g + 0.168 * b,
                    sb = 0.272 * r + 0.534 * g + 0.131 * b;
            nr = r + (sr - r) * intensity;
            ng = g + (sg - g) * intensity;
            nb = b + (sb - b) * intensity;
            break;
        }
        case F_CONTROLS:
            nr = ((l + (r - l) * sat) + bri - 0.5) * con + 0.5;
            ng = ((l + (g - l) * sat) + bri - 0.5) * con + 0.5;
            nb = ((l + (b - l) * sat) + bri - 0.5) * con + 0.5;
            break;
        default: break;
        }
        q[0] = (uint8_t)lround(clamp01(nr) * a * 255);
        q[1] = (uint8_t)lround(clamp01(ng) * a * 255);
        q[2] = (uint8_t)lround(clamp01(nb) * a * 255);
    }
}

- (CIImage *)outputImage {
    if (_kind == F_CONSTANT) return [CIImage imageWithColor:_values[kCIInputColorKey] ?: [CIColor blackColor]];
    CIImage *input = _values[kCIInputImageKey];
    if (![input isKindOfClass:[CIImage class]]) return nil;
    if (_kind == F_OVER) {
        CIImage *bg = _values[kCIInputBackgroundImageKey];
        if (![bg isKindOfClass:[CIImage class]]) return input;
        CGRect r = CGRectUnion(input.extent, bg.extent);
        if (CGRectIsInfinite(r)) r = CGRectIsInfinite(input.extent) ? bg.extent : input.extent;
        Pixels p = [bg _bn_pixelsIn:r];
        Pixels top = [input _bn_pixelsIn:r];
        for (size_t i = 0; i < p.w * p.h * 4; i += 4) {
            unsigned ta = top.px[i + 3];
            for (int c = 0; c < 4; c++) p.px[i + c] = (uint8_t)(top.px[i + c] + p.px[i + c] * (255 - ta) / 255);
        }
        free(top.px);
        return [input _bn_imageWithPixels:p];
    }
    if (CGRectIsInfinite(input.extent)) return input;        /* a colour: map it once */
    Pixels p = [input _bn_pixelsIn:input.extent];
    [self _bn_map:p];
    return [input _bn_imageWithPixels:p];
}
@end

/* ---- contexts ---- */

@implementation CIContext {
    CGContextRef _cg;
}
+ (instancetype)context { return [[self alloc] initWithOptions:nil]; }
+ (instancetype)contextWithOptions:(NSDictionary *)options { return [[self alloc] initWithOptions:options]; }
+ (instancetype)contextWithCGContext:(CGContextRef)ctx options:(NSDictionary *)options {
    CIContext *c = [[self alloc] initWithOptions:options];
    c->_cg = ctx ? CGContextRetain(ctx) : NULL;
    return c;
}
- (instancetype)initWithOptions:(NSDictionary *)options { return [super init]; }
- (instancetype)init { return [self initWithOptions:nil]; }
- (void)dealloc { if (_cg) CGContextRelease(_cg); }
- (CGImageRef)createCGImage:(CIImage *)image fromRect:(CGRect)rect {
    if (!image || CGRectIsInfinite(rect) || CGRectIsEmpty(rect) || CGRectIsNull(rect)) return NULL;
    Pixels p = [image _bn_pixelsIn:rect];
    CGImageRef img = image_from(p);
    free(p.px);
    return img;
}
- (void)drawImage:(CIImage *)image inRect:(CGRect)inRect fromRect:(CGRect)fromRect {
    if (!_cg) return;
    CGImageRef img = [self createCGImage:image fromRect:fromRect];
    if (!img) return;
    CGContextDrawImage(_cg, inRect, img);
    CGImageRelease(img);
}
@end
