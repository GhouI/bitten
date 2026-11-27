/* NSImage: images from data and files (decoded by ImageIO into CGImages),
 * from bundles by name, drawn by handlers or with lockFocus, and SF Symbols,
 * which have no glyphs here: a symbol image is a small rounded square in
 * the current text colour, at the symbol's size, so layouts keep their
 * shape. */
#import <AppKit/AppKit.h>
#include <ctype.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct CGImageSource *CGImageSourceRef;
CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options);
CGImageRef CGImageSourceCreateImageAtIndex(CGImageSourceRef src, size_t index, CFDictionaryRef options);

int bn_blend_mode_for_operation(NSCompositingOperation op);
NSImage *bn_asset_catalog_image(NSBundle *bundle, NSString *name);
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

/* A bitmap: either a CGImage it was made from, or pixels of its own (8-bit
 * samples, chunky, rows from the top, alpha last and premultiplied, as
 * AppKit lays them out) that a graphics context can draw into. */
@implementation NSBitmapImageRep {
    CGImageRef _image;
    unsigned char *_data;
    BOOL _ownsData;
    NSInteger _bytesPerRow, _bitsPerPixel, _samplesPerPixel, _bitsPerSample;
}
- (instancetype)initWithCGImage:(CGImageRef)cgImage {
    if ((self = [super init])) {
        _image = CGImageRetain(cgImage);
        self.pixelsWide = (NSInteger)CGImageGetWidth(cgImage);
        self.pixelsHigh = (NSInteger)CGImageGetHeight(cgImage);
        self.size = NSMakeSize(self.pixelsWide, self.pixelsHigh);
        self.alpha = YES;
        _bitsPerSample = 8;
        _samplesPerPixel = 4;
        _bitsPerPixel = 32;
    }
    return self;
}
- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height bitsPerSample:(NSInteger)bps
                         samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)alpha isPlanar:(BOOL)planar
                          colorSpaceName:(NSString *)space bytesPerRow:(NSInteger)rowBytes
                            bitsPerPixel:(NSInteger)pixelBits {
    if (width <= 0 || height <= 0 || bps != 8 || planar || spp < 1 || spp > 4) return nil;
    if (!pixelBits) pixelBits = bps * spp;
    if (pixelBits != 8 * spp && !(pixelBits == 32 && spp == 3)) return nil;
    if (!rowBytes) rowBytes = (width * pixelBits + 7) / 8;
    if ((self = [super init])) {
        self.pixelsWide = width;
        self.pixelsHigh = height;
        self.size = NSMakeSize(width, height);
        self.alpha = alpha;
        _bitsPerSample = bps;
        _samplesPerPixel = spp;
        _bitsPerPixel = pixelBits;
        _bytesPerRow = rowBytes;
        if (planes && planes[0]) {
            _data = planes[0];
        } else {
            _data = calloc((size_t)height, (size_t)rowBytes);
            if (!_data) return nil;
            _ownsData = YES;
        }
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
- (void)dealloc {
    CGImageRelease(_image);
    if (_ownsData) free(_data);
}
- (NSInteger)bitsPerSample { return _bitsPerSample; }
- (NSInteger)samplesPerPixel { return _samplesPerPixel; }
- (NSInteger)bitsPerPixel { return _bitsPerPixel; }
- (BOOL)isPlanar { return NO; }
- (NSInteger)numberOfPlanes { return 1; }
- (NSString *)colorSpaceName { return NSDeviceRGBColorSpace; }
/* Pixels made from the image, for a rep made from one. */
- (void)_bn_makeData {
    if (_data || !_image) return;
    size_t w = (size_t)self.pixelsWide, h = (size_t)self.pixelsHigh;
    _bytesPerRow = (NSInteger)(w * 4);
    _data = calloc(h, w * 4);
    if (!_data) return;
    _ownsData = YES;
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(_data, w, h, 8, w * 4, rgb, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(rgb);
    if (c) {
        CGContextDrawImage(c, CGRectMake(0, 0, w, h), _image);
        CGContextRelease(c);
    }
}
- (unsigned char *)bitmapData {
    [self _bn_makeData];
    return _data;
}
- (void)getBitmapDataPlanes:(unsigned char **)planes {
    if (planes) planes[0] = self.bitmapData;
}
- (NSInteger)bytesPerRow {
    [self _bn_makeData];
    return _bytesPerRow;
}
- (NSInteger)bytesPerPlane { return self.bytesPerRow * self.pixelsHigh; }
/* How CoreGraphics reads the pixels. */
- (CGBitmapInfo)_bn_bitmapInfo {
    if (self.hasAlpha) return (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    return (CGBitmapInfo)(_bitsPerPixel == 32 ? kCGImageAlphaNoneSkipLast : kCGImageAlphaNone);
}
- (CGImageRef)CGImage {
    if (!_data) return _image;
    /* Pixels may have been drawn since: an image of them as they are now. */
    CGImageRelease(_image);
    size_t h = (size_t)self.pixelsHigh;
    CFDataRef bytes = CFDataCreate(NULL, _data, (CFIndex)(h * (size_t)_bytesPerRow));
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(bytes);
    CFRelease(bytes);
    CGColorSpaceRef space = _samplesPerPixel < 3 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB();
    _image = CGImageCreate((size_t)self.pixelsWide, h, 8, (size_t)_bitsPerPixel, (size_t)_bytesPerRow, space,
                           _samplesPerPixel < 3 ? (CGBitmapInfo)(self.hasAlpha ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNone)
                                                : self._bn_bitmapInfo,
                           provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return _image;
}
- (CGImageRef)CGImageForProposedRect:(NSRect *)r context:(NSGraphicsContext *)c hints:(NSDictionary *)h { return self.CGImage; }
/* The colour of a pixel, (0, 0) at the top left. */
- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y {
    unsigned char *d = self.bitmapData;
    if (!d || x < 0 || y < 0 || x >= self.pixelsWide || y >= self.pixelsHigh) return nil;
    const unsigned char *p = d + y * _bytesPerRow + x * (_bitsPerPixel / 8);
    if (_samplesPerPixel < 3) {
        CGFloat a = self.hasAlpha ? p[1] / 255.0 : 1;
        return [NSColor colorWithWhite:(a > 0 ? p[0] / 255.0 / (self.hasAlpha ? a : 1) : 0) alpha:a];
    }
    CGFloat a = self.hasAlpha ? p[3] / 255.0 : 1;
    CGFloat k = self.hasAlpha && a > 0 ? 1 / a : 1;
    return [NSColor colorWithSRGBRed:fmin(1, p[0] / 255.0 * k) green:fmin(1, p[1] / 255.0 * k)
                                blue:fmin(1, p[2] / 255.0 * k) alpha:a];
}

static void png_put32(NSMutableData *d, uint32_t v) {
    uint8_t b[4] = {(uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v};
    [d appendBytes:b length:4];
}
static uint32_t png_crc(const uint8_t *p, size_t n, uint32_t c) {
    static uint32_t table[256];
    if (!table[1]) {
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t v = i;
            for (int k = 0; k < 8; k++) v = v & 1 ? 0xedb88320u ^ (v >> 1) : v >> 1;
            table[i] = v;
        }
    }
    for (size_t i = 0; i < n; i++) c = table[(c ^ p[i]) & 0xff] ^ (c >> 8);
    return c;
}
static void png_chunk(NSMutableData *out, const char *type, NSData *body) {
    png_put32(out, (uint32_t)body.length);
    NSUInteger start = out.length;
    [out appendBytes:type length:4];
    [out appendData:body];
    uint32_t crc = png_crc((const uint8_t *)out.bytes + start, out.length - start, 0xffffffffu) ^ 0xffffffffu;
    png_put32(out, crc);
}
/* A PNG of 8-bit RGBA rows (straight alpha), its pixels stored uncompressed
 * in deflate's stored blocks. */
static NSData *png_encode(const uint8_t *rgba, size_t w, size_t h) {
    NSMutableData *raw = [NSMutableData dataWithCapacity:h * (w * 4 + 1)];
    for (size_t y = 0; y < h; y++) {
        uint8_t filter = 0;
        [raw appendBytes:&filter length:1];
        [raw appendBytes:rgba + y * w * 4 length:w * 4];
    }
    NSMutableData *z = [NSMutableData data];
    uint8_t head[2] = {0x78, 0x01};
    [z appendBytes:head length:2];
    const uint8_t *r = raw.bytes;
    size_t n = raw.length, at = 0;
    uint32_t s1 = 1, s2 = 0;
    for (size_t i = 0; i < n; i++) {
        s1 = (s1 + r[i]) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    do {
        size_t len = n - at > 65535 ? 65535 : n - at;
        uint8_t b[5] = {at + len == n, (uint8_t)len, (uint8_t)(len >> 8), (uint8_t)~len, (uint8_t)(~len >> 8)};
        [z appendBytes:b length:5];
        [z appendBytes:r + at length:len];
        at += len;
    } while (at < n);
    png_put32(z, s2 << 16 | s1);
    NSMutableData *out = [NSMutableData data];
    static const uint8_t sig[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    [out appendBytes:sig length:8];
    NSMutableData *ihdr = [NSMutableData data];
    png_put32(ihdr, (uint32_t)w);
    png_put32(ihdr, (uint32_t)h);
    uint8_t rest[5] = {8, 6, 0, 0, 0};
    [ihdr appendBytes:rest length:5];
    png_chunk(out, "IHDR", ihdr);
    png_chunk(out, "IDAT", z);
    png_chunk(out, "IEND", [NSData data]);
    return out;
}
/* Only PNG can be written (NSBitmapImageFileTypePNG). */
- (NSData *)representationUsingType:(NSUInteger)type properties:(NSDictionary *)properties {
    if (type != 4) return nil;
    size_t w = (size_t)self.pixelsWide, h = (size_t)self.pixelsHigh;
    if (!w || !h) return nil;
    uint8_t *rgba = malloc(w * h * 4);
    if (!rgba) return nil;
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(rgba, w, h, 8, w * 4, rgb, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(rgb);
    CGImageRef img = self.CGImage;
    if (!c || !img) {
        if (c) CGContextRelease(c);
        free(rgba);
        return nil;
    }
    CGContextClearRect(c, CGRectMake(0, 0, w, h));
    CGContextDrawImage(c, CGRectMake(0, 0, w, h), img);
    CGContextRelease(c);
    for (size_t i = 0; i < w * h; i++) {
        uint8_t *p = rgba + i * 4;
        if (p[3] && p[3] < 255)
            for (int k = 0; k < 3; k++) p[k] = (uint8_t)fmin(255, p[k] * 255.0 / p[3] + 0.5);
    }
    NSData *png = png_encode(rgba, w, h);
    free(rgba);
    return png;
}
@end

@implementation NSGraphicsContext (BittenBitmap)
/* Drawing into a bitmap rep's own pixels. */
+ (NSGraphicsContext *)graphicsContextWithBitmapImageRep:(NSBitmapImageRep *)rep {
    unsigned char *data = rep.bitmapData;
    if (!data || rep.bitsPerSample != 8 || rep.samplesPerPixel < 3) return nil;
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(data, (size_t)rep.pixelsWide, (size_t)rep.pixelsHigh, 8,
                                           (size_t)rep.bytesPerRow, rgb, rep._bn_bitmapInfo);
    CGColorSpaceRelease(rgb);
    if (!c) return nil;
    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithCGContext:c flipped:NO];
    CGContextRelease(c);
    return g;
}
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
/* Icon files (.icns): a big-endian "icns" header and (type, length,
 * data) entries. The PNG entries become one representation each, sized in
 * points (types ic11..ic14 and ic10 are @2x), the largest first. Older
 * raw-bitmap entries are skipped. */
static NSImage *bn_icns_image(NSImage *img, NSData *data) {
    const uint8_t *b = data.bytes;
    NSUInteger n = data.length;
    if (n < 8 || memcmp(b, "icns", 4) != 0) return nil;
    struct { char type[5]; CGFloat points; } kinds[] = {
        {"icp4", 16}, {"icp5", 32}, {"icp6", 64}, {"ic07", 128}, {"ic08", 256}, {"ic09", 512},
        {"ic11", 16}, {"ic12", 32}, {"ic13", 128}, {"ic14", 256}, {"ic10", 512},
    };
    NSMutableArray<NSBitmapImageRep *> *reps = [NSMutableArray array];
    CGFloat largest = 0;
    for (NSUInteger i = 8; i + 8 <= n;) {
        uint32_t len = (uint32_t)b[i + 4] << 24 | (uint32_t)b[i + 5] << 16 | (uint32_t)b[i + 6] << 8 | b[i + 7];
        if (len < 8 || i + len > n) break;
        for (size_t k = 0; k < sizeof kinds / sizeof kinds[0]; k++) {
            if (memcmp(b + i, kinds[k].type, 4) != 0 || len < 16 || memcmp(b + i + 8, "\x89PNG", 4) != 0) continue;
            NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[data subdataWithRange:NSMakeRange(i + 8, len - 8)]];
            if (!rep) break;
            rep.size = NSMakeSize(kinds[k].points, kinds[k].points);
            [reps addObject:rep];
            largest = MAX(largest, kinds[k].points);
            break;
        }
        i += len;
    }
    if (!reps.count) return nil;
    [reps sortUsingComparator:^NSComparisonResult(NSBitmapImageRep *x, NSBitmapImageRep *y) {
        return x.pixelsWide > y.pixelsWide ? NSOrderedAscending : x.pixelsWide < y.pixelsWide ? NSOrderedDescending : NSOrderedSame;
    }];
    if (!(img = [img initWithSize:NSMakeSize(largest, largest)])) return nil;
    for (NSBitmapImageRep *rep in reps) [img addRepresentation:rep];
    return img;
}

- (instancetype)initWithData:(NSData *)data {
    if (data.length >= 8 && memcmp(data.bytes, "icns", 4) == 0) return bn_icns_image(self, data);
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
    /* Each name is looked for once per catalog (a catalog is megabytes). */
    static NSMutableDictionary<NSString *, NSNumber *> *answers;
    NSString *key = [path stringByAppendingFormat:@"\n%@", name];
    @synchronized([NSImage class]) {
        if (!answers) answers = [NSMutableDictionary dictionary];
        NSNumber *known = answers[key];
        if (known) return known.boolValue;
    }
    BOOL found = NO;
    NSData *needle = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (needle.length && car.length >= needle.length) {
        const unsigned char *h = car.bytes, *n = needle.bytes;
        size_t hl = car.length, nl = needle.length;
        for (const unsigned char *at = memmem(h, hl, n, nl); at; at = memmem(at + 1, hl - (size_t)(at + 1 - h), n, nl)) {
            size_t i = (size_t)(at - h);
            /* A whole name: not part of a longer identifier. */
            unsigned char after = i + nl < hl ? h[i + nl] : 0;
            unsigned char before = i ? h[i - 1] : 0;
            if (after > ' ' && after != '"' && after < 0x80 && (isalnum(after) || after == '.' || after == '_' || after == '-')) continue;
            if (before && (isalnum(before) || before == '.' || before == '_' || before == '-')) continue;
            found = YES;
            break;
        }
    }
    @synchronized([NSImage class]) { answers[key] = @(found); }
    return found;
}
/* Names looked up and not found: asked again, they cost nothing (until
 * an image takes the name). */
static NSMutableSet<NSString *> *missing_images;
+ (NSImage *)imageNamed:(NSImageName)name {
    if (!name) return nil;
    NSImage *cached = named_images[name];
    if (cached) return cached;
    if ([missing_images containsObject:name]) return nil;
    NSBundle *b = [NSBundle mainBundle];
    NSString *path = nil;
    for (NSString *ext in @[ @"png", @"tiff", @"jpg", @"icns", @"pdf" ]) {
        path = [b pathForResource:name ofType:ext];
        if (path) break;
    }
    if (!path && name.pathExtension.length) path = [b pathForResource:name ofType:nil];
    NSImage *img = path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
    if (!img) img = bn_asset_catalog_image(b, name);
    if (!img && asset_catalog_has(b, name)) {
        /* Named in the catalog but not decodable here (a vector rendition):
         * an empty image of the usual icon size stands in (callers may rely
         * on the image existing, as it does on macOS). */
        img = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    }
    if (!img) {
        if (!missing_images) missing_images = [NSMutableSet set];
        [missing_images addObject:[name copy]];
        return nil;
    }
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
    if (n) [missing_images removeObject:n];
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
        /* The handler draws into the image's own buffer, as on macOS: in a
         * transparency layer clipped to the image, so its compositing (a
         * tint filled source-atop over what it drew) sees only its own
         * drawing, not what is behind the image. */
        CGContextSaveGState(c);
        CGContextClipToRect(c, rect);
        CGContextBeginTransparencyLayerWithRect(c, rect, NULL);
        CGContextTranslateCTM(c, rect.origin.x, rect.origin.y);
        if (_size.width > 0 && _size.height > 0)
            CGContextScaleCTM(c, rect.size.width / _size.width, rect.size.height / _size.height);
        CGContextSaveGState(c);
        _handler(NSMakeRect(0, 0, _size.width, _size.height));
        CGContextRestoreGState(c);
        CGContextEndTransparencyLayer(c);
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
/* A template image drawn as AppKit's views draw one: its shape (alpha)
 * filled with `color` (the view's tint, or the label colour of the current
 * appearance). Other images draw as they are. */
- (void)_bn_drawTemplateInRect:(NSRect)rect color:(NSColor *)color {
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (!c || !_template) {
        [self drawInRect:rect];
        return;
    }
    CGContextSaveGState(c);
    /* a layer the size of the image, not of the whole context */
    CGContextClipToRect(c, rect);
    CGContextBeginTransparencyLayerWithRect(c, rect, NULL);
    [self drawInRect:rect];
    /* The colour where the image has coverage, at the colour's own opacity
     * (source-in: a translucent tint, like a disabled control's, lightens
     * the image instead of leaving its own colour showing). */
    CGContextSetBlendMode(c, kCGBlendModeSourceIn);
    CGContextSetFillColorWithColor(c, (color ?: NSColor.labelColor).CGColor);
    CGContextFillRect(c, rect);
    CGContextEndTransparencyLayer(c);
    CGContextRestoreGState(c);
}
- (void)drawInRect:(NSRect)dst fromRect:(NSRect)src operation:(NSCompositingOperation)op fraction:(CGFloat)alpha {
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (c) {
        CGContextSaveGState(c);
        CGContextSetAlpha(c, alpha);
        CGContextSetBlendMode(c, (CGBlendMode)bn_blend_mode_for_operation(op));
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
