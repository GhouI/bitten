/* NSImage: images from data and files (decoded by ImageIO into CGImages),
 * from bundles by name, drawn by handlers or with lockFocus, and SF Symbols,
 * which have no glyphs here: a symbol image is a small rounded square in
 * the current text colour, at the symbol's size, so layouts keep their
 * shape. */
#import <AppKit/AppKit.h>
#include <ctype.h>
#include <string.h>

typedef struct CGImageSource *CGImageSourceRef;
CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options);
CGImageRef CGImageSourceCreateImageAtIndex(CGImageSourceRef src, size_t index, CFDictionaryRef options);

void bn_draw_symbol(CGContextRef c, const char *name, double x, double y, double w, double h, double r,
                    double g, double b, double a, int flipped);

@implementation NSImageRep {
    NSSize _size;
    NSInteger _wide, _high;
    BOOL _alpha;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSSize)size { return _size; }
- (void)setSize:(NSSize)s { _size = s; }
- (NSInteger)pixelsWide { return _wide; }
- (void)setPixelsWide:(NSInteger)w { _wide = w; }
- (NSInteger)pixelsHigh { return _high; }
- (void)setPixelsHigh:(NSInteger)h { _high = h; }
- (BOOL)hasAlpha { return _alpha; }
- (void)setAlpha:(BOOL)a { _alpha = a; }
- (BOOL)draw { return [self drawInRect:NSMakeRect(0, 0, _size.width, _size.height)]; }
- (BOOL)drawInRect:(NSRect)rect {
    CGImageRef img = [self CGImageForProposedRect:NULL context:nil hints:nil];
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (!img || !c) return NO;
    CGContextDrawImage(c, rect, img);
    return YES;
}
- (CGImageRef)CGImageForProposedRect:(NSRect *)r context:(NSGraphicsContext *)c hints:(NSDictionary *)h { return NULL; }
@end

@implementation NSBitmapImageRep {
    CGImageRef _image;
}
- (instancetype)initWithCGImage:(CGImageRef)cgImage {
    if ((self = [super init])) {
        _image = CGImageRetain(cgImage);
        self.pixelsWide = (NSInteger)CGImageGetWidth(cgImage);
        self.pixelsHigh = (NSInteger)CGImageGetHeight(cgImage);
        self.size = NSMakeSize(self.pixelsWide, self.pixelsHigh);
        self.alpha = YES;
    }
    return self;
}
- (instancetype)initWithData:(NSData *)data {
    CGImageSourceRef src = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
    CGImageRef img = src ? CGImageSourceCreateImageAtIndex(src, 0, NULL) : NULL;
    if (src) CFRelease(src);
    if (!img) return nil;
    self = [self initWithCGImage:img];
    CGImageRelease(img);
    return self;
}
+ (instancetype)imageRepWithData:(NSData *)data { return [[self alloc] initWithData:data]; }
- (void)dealloc { CGImageRelease(_image); }
- (CGImageRef)CGImage { return _image; }
- (CGImageRef)CGImageForProposedRect:(NSRect *)r context:(NSGraphicsContext *)c hints:(NSDictionary *)h { return _image; }
@end

@implementation NSImageSymbolConfiguration {
  @public
    CGFloat _pointSize;
    NSImageSymbolScale _scale;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
+ (instancetype)configurationWithPointSize:(CGFloat)pointSize weight:(NSFontWeight)weight {
    NSImageSymbolConfiguration *c = [self new];
    c->_pointSize = pointSize;
    return c;
}
+ (instancetype)configurationWithPointSize:(CGFloat)pointSize weight:(NSFontWeight)weight scale:(NSImageSymbolScale)scale {
    NSImageSymbolConfiguration *c = [self configurationWithPointSize:pointSize weight:weight];
    c->_scale = scale;
    return c;
}
+ (instancetype)configurationWithScale:(NSImageSymbolScale)scale {
    NSImageSymbolConfiguration *c = [self new];
    c->_scale = scale;
    return c;
}
+ (instancetype)configurationWithTextStyle:(NSString *)style { return [self new]; }
+ (instancetype)configurationWithHierarchicalColor:(NSColor *)color { return [self new]; }
+ (instancetype)configurationWithPaletteColors:(NSArray<NSColor *> *)colors { return [self new]; }
+ (instancetype)configurationPreferringMonochrome { return [self new]; }
+ (instancetype)configurationPreferringHierarchical { return [self new]; }
+ (instancetype)configurationWithTextStyle:(NSString *)style scale:(NSImageSymbolScale)scale {
    NSImageSymbolConfiguration *c = [self new];
    c->_scale = scale;
    return c;
}
+ (instancetype)configurationPreferringMulticolor { return [self new]; }
- (instancetype)configurationByApplyingConfiguration:(NSImageSymbolConfiguration *)other {
    NSImageSymbolConfiguration *c = [NSImageSymbolConfiguration new];
    c->_pointSize = other->_pointSize ?: _pointSize;
    c->_scale = other->_scale ?: _scale;
    return c;
}
@end

static NSMutableDictionary<NSString *, NSImage *> *named_images;

@implementation NSImage {
    NSSize _size;
    BOOL _template;
    NSString *_description, *_name, *_symbol;
    NSMutableArray<NSImageRep *> *_reps;
    BOOL (^_handler)(NSRect);
    BOOL _handlerFlipped;
    NSImageSymbolConfiguration *_symbolConfiguration;
    CGContextRef _focus;
    NSGraphicsContext *_savedContext;
    NSRect _alignmentRect;
    BOOL _hasAlignmentRect;
    NSEdgeInsets _capInsets;
    NSInteger _resizingMode;
    NSColor *_backgroundColor;
}
- (NSRect)alignmentRect { return _hasAlignmentRect ? _alignmentRect : NSMakeRect(0, 0, _size.width, _size.height); }
- (void)setAlignmentRect:(NSRect)r {
    _alignmentRect = r;
    _hasAlignmentRect = YES;
}
- (NSEdgeInsets)capInsets { return _capInsets; }
- (void)setCapInsets:(NSEdgeInsets)i { _capInsets = i; }
- (NSInteger)resizingMode { return _resizingMode; }
- (void)setResizingMode:(NSInteger)m { _resizingMode = m; }
- (BOOL)matchesOnlyOnBestFittingAxis { return NO; }
- (void)setMatchesOnlyOnBestFittingAxis:(BOOL)b {}
- (NSUInteger)cacheMode { return 0; }
- (void)setCacheMode:(NSUInteger)m {}
- (NSColor *)backgroundColor { return _backgroundColor ?: [NSColor clearColor]; }
- (void)setBackgroundColor:(NSColor *)c { _backgroundColor = [c copy]; }
- (BOOL)usesEPSOnResolutionMismatch { return NO; }
- (void)setUsesEPSOnResolutionMismatch:(BOOL)b {}
- (BOOL)prefersColorMatch { return YES; }
- (void)setPrefersColorMatch:(BOOL)b {}
- (BOOL)matchesOnMultipleResolution { return YES; }
- (void)setMatchesOnMultipleResolution:(BOOL)b {}
- (BOOL)isFlipped { return NO; }
- (void)setFlipped:(BOOL)f {}
- (void)recache {}
- (NSImageRep *)bestRepresentationForRect:(NSRect)rect context:(NSGraphicsContext *)c hints:(NSDictionary *)h {
    return _reps.firstObject;
}
- (NSImage *)imageWithLocale:(id)locale { return self; }
- (instancetype)init { return [self initWithSize:NSZeroSize]; }
- (instancetype)initWithSize:(NSSize)size {
    if ((self = [super init])) {
        _size = size;
        _reps = [NSMutableArray array];
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    NSImage *c = [[NSImage alloc] initWithSize:_size];
    c->_template = _template;
    c->_description = _description;
    c->_symbol = _symbol;
    c->_reps = [_reps mutableCopy];
    c->_handler = _handler;
    c->_handlerFlipped = _handlerFlipped;
    c->_symbolConfiguration = _symbolConfiguration;
    return c;
}
- (instancetype)initWithCGImage:(CGImageRef)cgImage size:(NSSize)size {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    if (size.width == 0 && size.height == 0) size = rep.size;
    if ((self = [self initWithSize:size])) [self addRepresentation:rep];
    return self;
}
- (instancetype)initWithData:(NSData *)data {
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:data];
    if (!rep) return nil;
    if ((self = [self initWithSize:rep.size])) [self addRepresentation:rep];
    return self;
}
- (instancetype)initWithContentsOfFile:(NSString *)file { return [self initWithData:[NSData dataWithContentsOfFile:file]]; }
- (instancetype)initWithContentsOfURL:(NSURL *)url { return [self initWithData:(url.isFileURL ? [NSData dataWithContentsOfFile:url.path] : nil)]; }
- (instancetype)initByReferencingFile:(NSString *)file { return [self initWithContentsOfFile:file]; }
- (instancetype)initByReferencingURL:(NSURL *)url { return [self initWithContentsOfURL:url]; }

/* Whether a bundle's Assets.car names an asset: the catalog stores each
 * asset's name as plain text in its facet keys. */
static BOOL asset_catalog_has(NSBundle *bundle, NSString *name) {
    static NSMutableDictionary<NSString *, NSData *> *catalogs;
    NSString *path = [bundle pathForResource:@"Assets" ofType:@"car"];
    if (!path || !name.length) return NO;
    NSData *car;
    @synchronized([NSImage class]) {
        if (!catalogs) catalogs = [NSMutableDictionary dictionary];
        car = catalogs[path];
        if (!car) {
            car = [NSData dataWithContentsOfFile:path] ?: [NSData data];
            catalogs[path] = car;
        }
    }
    NSData *needle = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (!needle.length || car.length < needle.length) return NO;
    const unsigned char *h = car.bytes, *n = needle.bytes;
    size_t hl = car.length, nl = needle.length;
    for (size_t i = 0; i + nl <= hl; i++) {
        if (h[i] != n[0] || memcmp(h + i, n, nl)) continue;
        /* A whole name: not part of a longer identifier. */
        unsigned char after = i + nl < hl ? h[i + nl] : 0;
        unsigned char before = i ? h[i - 1] : 0;
        if (after > ' ' && after != '"' && after < 0x80 && (isalnum(after) || after == '.' || after == '_' || after == '-')) continue;
        if (before && (isalnum(before) || before == '.' || before == '_' || before == '-')) continue;
        return YES;
    }
    return NO;
}
+ (NSImage *)imageNamed:(NSImageName)name {
    if (!name) return nil;
    NSImage *cached = named_images[name];
    if (cached) return cached;
    NSBundle *b = [NSBundle mainBundle];
    NSString *path = nil;
    for (NSString *ext in @[ @"png", @"tiff", @"jpg", @"icns", @"pdf" ]) {
        path = [b pathForResource:name ofType:ext];
        if (path) break;
    }
    if (!path && name.pathExtension.length) path = [b pathForResource:name ofType:nil];
    NSImage *img = path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
    if (!img && asset_catalog_has(b, name)) {
        /* In the compiled asset catalog, which is not decoded yet: an empty
         * image of the usual icon size stands in (callers may rely on the
         * image existing, as it does on macOS). */
        img = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    }
    if (!img) return nil;
    img->_name = [name copy];
    if (!named_images) named_images = [NSMutableDictionary dictionary];
    named_images[name] = img;
    return img;
}
+ (instancetype)imageWithSystemSymbolName:(NSString *)name accessibilityDescription:(NSString *)description {
    if (!name) return nil;
    NSImage *img = [[self alloc] initWithSize:NSMakeSize(16, 16)];
    img->_symbol = [name copy];
    img->_description = [description copy];
    img->_template = YES;
    return img;
}
+ (instancetype)imageWithSystemSymbolName:(NSString *)name variableValue:(double)value
                 accessibilityDescription:(NSString *)description {
    return [self imageWithSystemSymbolName:name accessibilityDescription:description];
}
+ (instancetype)imageWithSymbolName:(NSString *)name variableValue:(double)value {
    return [self imageWithSystemSymbolName:name accessibilityDescription:nil];
}
+ (instancetype)imageWithSize:(NSSize)size flipped:(BOOL)flipped drawingHandler:(BOOL (^)(NSRect))handler {
    NSImage *img = [[self alloc] initWithSize:size];
    img->_handler = [handler copy];
    img->_handlerFlipped = flipped;
    return img;
}
- (NSSize)size { return _size; }
- (void)setSize:(NSSize)s { _size = s; }
- (BOOL)isTemplate { return _template; }
- (void)setTemplate:(BOOL)t { _template = t; }
- (NSString *)accessibilityDescription { return _description; }
- (void)setAccessibilityDescription:(NSString *)d { _description = [d copy]; }
- (NSArray<NSImageRep *> *)representations { return [_reps copy]; }
- (BOOL)isValid { return _reps.count || _handler || _symbol || (_size.width > 0 && _size.height > 0); }
- (NSImageName)name { return _name; }
- (BOOL)setName:(NSImageName)n {
    if (_name) [named_images removeObjectForKey:_name];
    _name = [n copy];
    if (n) {
        if (!named_images) named_images = [NSMutableDictionary dictionary];
        named_images[n] = self;
    }
    return YES;
}
- (void)addRepresentation:(NSImageRep *)rep { [_reps addObject:rep]; }
- (void)removeRepresentation:(NSImageRep *)rep { [_reps removeObjectIdenticalTo:rep]; }
- (NSImageSymbolConfiguration *)symbolConfiguration { return _symbolConfiguration ?: [NSImageSymbolConfiguration new]; }
- (NSImage *)imageWithSymbolConfiguration:(NSImageSymbolConfiguration *)configuration {
    NSImage *c = [self copy];
    c->_symbolConfiguration = configuration;
    if (configuration->_pointSize > 0) c->_size = NSMakeSize(configuration->_pointSize, configuration->_pointSize);
    return c;
}

/* A bitmap of the image, rendering a drawing handler or symbol if needed. */
- (CGImageRef)CGImageForProposedRect:(NSRect *)proposed context:(NSGraphicsContext *)context hints:(NSDictionary *)hints {
    for (NSImageRep *r in _reps) {
        CGImageRef img = [r CGImageForProposedRect:proposed context:context hints:hints];
        if (img) return img;
    }
    size_t w = (size_t)(_size.width > 0 ? _size.width : 1), h = (size_t)(_size.height > 0 ? _size.height : 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!c) return NULL;
    NSGraphicsContext *saved = [NSGraphicsContext currentContext];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:c flipped:NO]];
    [self drawInRect:NSMakeRect(0, 0, w, h)];
    [NSGraphicsContext setCurrentContext:saved];
    CGImageRef img = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    if (!img) return NULL;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
    CGImageRelease(img);
    [_reps addObject:rep];
    return rep.CGImage;
}
- (NSData *)TIFFRepresentation { return nil; }

- (void)drawInRect:(NSRect)rect {
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (!c) return;
    if (_reps.count) {
        CGImageRef img = [_reps[0] CGImageForProposedRect:NULL context:nil hints:nil];
        if (img) CGContextDrawImage(c, rect, img);
        return;
    }
    if (_handler) {
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, rect.origin.x, rect.origin.y);
        if (_size.width > 0 && _size.height > 0)
            CGContextScaleCTM(c, rect.size.width / _size.width, rect.size.height / _size.height);
        _handler(NSMakeRect(0, 0, _size.width, _size.height));
        CGContextRestoreGState(c);
        return;
    }
    if (_symbol) {
        /* Templates draw black (views tint them); see AppKitSymbols.m. */
        BOOL flipped = [NSGraphicsContext currentContext].isFlipped;
        bn_draw_symbol(c, _symbol.UTF8String, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, 0, 0, 0,
                       0.85, flipped);
    }
}
- (void)drawInRect:(NSRect)dst fromRect:(NSRect)src operation:(NSCompositingOperation)op fraction:(CGFloat)alpha {
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (c) {
        CGContextSaveGState(c);
        CGContextSetAlpha(c, alpha);
    }
    [self drawInRect:dst];
    if (c) CGContextRestoreGState(c);
}
- (void)drawAtPoint:(NSPoint)p fromRect:(NSRect)src operation:(NSCompositingOperation)op fraction:(CGFloat)alpha {
    [self drawInRect:NSMakeRect(p.x, p.y, _size.width, _size.height) fromRect:src operation:op fraction:alpha];
}

/* lockFocus: drawing goes into a bitmap that becomes the image. */
- (void)lockFocus {
    size_t w = (size_t)MAX(1, _size.width), h = (size_t)MAX(1, _size.height);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    _focus = CGBitmapContextCreate(NULL, w, h, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    _savedContext = [NSGraphicsContext currentContext];
    if (_reps.count) [self drawInRect:NSMakeRect(0, 0, w, h)];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:_focus flipped:NO]];
}
- (void)unlockFocus {
    [NSGraphicsContext setCurrentContext:_savedContext];
    _savedContext = nil;
    if (!_focus) return;
    CGImageRef img = CGBitmapContextCreateImage(_focus);
    CGContextRelease(_focus);
    _focus = NULL;
    [_reps removeAllObjects];
    if (img) {
        [_reps addObject:[[NSBitmapImageRep alloc] initWithCGImage:img]];
        CGImageRelease(img);
    }
}
@end
