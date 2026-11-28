/* CoreImage over CoreGraphics, on the CPU: images are CGImages (or a
 * solid colour), filters run when a context renders them. Filters:
 * CIColorMonochrome, CIColorInvert, CISepiaTone, CIColorControls,
 * CISourceOverCompositing, CIConstantColorGenerator; others are nil. */
#ifndef BITTEN_COREIMAGE_H
#define BITTEN_COREIMAGE_H
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>

#pragma clang assume_nonnull begin

typedef NSString *CIImageOption NS_TYPED_ENUM;
typedef NSString *CIContextOption NS_TYPED_ENUM;
extern CIImageOption const kCIImageColorSpace;
extern CIContextOption const kCIContextCacheIntermediates, kCIContextWorkingColorSpace, kCIContextUseSoftwareRenderer;
extern NSString *const kCIInputImageKey, *const kCIInputBackgroundImageKey, *const kCIInputColorKey,
    *const kCIInputIntensityKey, *const kCIInputSaturationKey, *const kCIInputBrightnessKey,
    *const kCIInputContrastKey, *const kCIOutputImageKey;

@interface CIColor : NSObject <NSCopying>
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b;
+ (instancetype)colorWithCGColor:(CGColorRef)c;
- (instancetype)initWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
- (instancetype)initWithCGColor:(CGColorRef)c;
/* AppKit's: from an NSColor */
- (nullable instancetype)initWithColor:(id)color;
@property (readonly) CGFloat red, green, blue, alpha;
@property (readonly) size_t numberOfComponents;
@property (readonly) NSString *stringRepresentation;
@property (class, readonly) CIColor *blackColor, *whiteColor, *clearColor, *grayColor, *redColor, *greenColor, *blueColor;
@end

@interface CIImage : NSObject <NSCopying>
+ (instancetype)imageWithCGImage:(CGImageRef)image;
+ (instancetype)imageWithCGImage:(CGImageRef)image options:(nullable NSDictionary<CIImageOption, id> *)options;
+ (instancetype)imageWithColor:(CIColor *)color;
+ (instancetype)emptyImage;
- (instancetype)initWithCGImage:(CGImageRef)image;
- (instancetype)initWithCGImage:(CGImageRef)image options:(nullable NSDictionary<CIImageOption, id> *)options;
- (instancetype)initWithColor:(CIColor *)color;
/* from a Metal texture (id<MTLTexture>), 8-bit RGBA or BGRA */
+ (instancetype)imageWithMTLTexture:(id)texture options:(nullable NSDictionary *)options;
- (instancetype)initWithMTLTexture:(id)texture options:(nullable NSDictionary *)options;
@property (readonly) CGRect extent;
@property (nullable, readonly) CGImageRef CGImage;
- (CIImage *)imageByCroppingToRect:(CGRect)rect;
- (CIImage *)imageByApplyingTransform:(CGAffineTransform)matrix;
- (CIImage *)imageByApplyingFilter:(NSString *)filterName withInputParameters:(nullable NSDictionary<NSString *, id> *)params;
- (CIImage *)imageByApplyingFilter:(NSString *)filterName;
- (CIImage *)imageByCompositingOverImage:(CIImage *)dest;
@end

@interface CIFilter : NSObject <NSCopying>
+ (nullable CIFilter *)filterWithName:(NSString *)name;
+ (nullable CIFilter *)filterWithName:(NSString *)name withInputParameters:(nullable NSDictionary<NSString *, id> *)params;
+ (NSArray<NSString *> *)filterNamesInCategory:(nullable NSString *)category;
@property (readonly) NSString *name;
@property (readonly, nullable) CIImage *outputImage;
@property (readonly) NSArray<NSString *> *inputKeys, *outputKeys;
@property (readonly) NSDictionary<NSString *, id> *attributes;
- (void)setDefaults;
- (void)setValue:(nullable id)value forKey:(NSString *)key;
- (nullable id)valueForKey:(NSString *)key;
/* CIFilterBuiltins: the QR code generator (inputMessage, inputCorrectionLevel) */
+ (CIFilter *)QRCodeGenerator;
@property (nullable, copy) NSData *message;
@property (copy) NSString *correctionLevel;
@end

@interface CIContext : NSObject
+ (instancetype)context;
+ (instancetype)contextWithOptions:(nullable NSDictionary<CIContextOption, id> *)options;
+ (instancetype)contextWithCGContext:(CGContextRef)ctx options:(nullable NSDictionary<CIContextOption, id> *)options;
+ (instancetype)contextWithMTLDevice:(id)device;
+ (instancetype)contextWithMTLDevice:(id)device options:(nullable NSDictionary<CIContextOption, id> *)options;
- (instancetype)initWithOptions:(nullable NSDictionary<CIContextOption, id> *)options;
- (nullable CGImageRef)createCGImage:(CIImage *)image fromRect:(CGRect)rect CF_RETURNS_RETAINED;
- (void)drawImage:(CIImage *)image inRect:(CGRect)inRect fromRect:(CGRect)fromRect;
@end

#pragma clang assume_nonnull end
#endif
