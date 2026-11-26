/* Metal: there is no GPU, so MTLCreateSystemDefaultDevice returns nil and
 * programs take their software path. The descriptor classes exist and
 * hold their properties, so code that builds descriptors before asking a
 * device for objects still runs. */
#ifndef BITTEN_METAL_H
#define BITTEN_METAL_H
#import <Foundation/Foundation.h>

#pragma clang assume_nonnull begin

typedef NS_ENUM(NSUInteger, MTLPixelFormat) {
    MTLPixelFormatInvalid = 0,
    MTLPixelFormatA8Unorm = 1,
    MTLPixelFormatR8Unorm = 10,
    MTLPixelFormatRGBA8Unorm = 70,
    MTLPixelFormatRGBA8Unorm_sRGB = 71,
    MTLPixelFormatBGRA8Unorm = 80,
    MTLPixelFormatBGRA8Unorm_sRGB = 81,
    MTLPixelFormatRGBA16Float = 115,
    MTLPixelFormatRGBA32Float = 125,
    MTLPixelFormatDepth32Float = 252,
};
typedef NS_ENUM(NSUInteger, MTLTextureType) {
    MTLTextureType1D = 0, MTLTextureType1DArray = 1, MTLTextureType2D = 2, MTLTextureType2DArray = 3,
    MTLTextureType2DMultisample = 4, MTLTextureTypeCube = 5, MTLTextureTypeCubeArray = 6, MTLTextureType3D = 7,
};
typedef NS_OPTIONS(NSUInteger, MTLTextureUsage) {
    MTLTextureUsageUnknown = 0, MTLTextureUsageShaderRead = 1, MTLTextureUsageShaderWrite = 2,
    MTLTextureUsageRenderTarget = 4, MTLTextureUsagePixelFormatView = 0x10,
};
typedef NS_ENUM(NSUInteger, MTLStorageMode) {
    MTLStorageModeShared = 0, MTLStorageModeManaged = 1, MTLStorageModePrivate = 2, MTLStorageModeMemoryless = 3,
};
typedef NS_ENUM(NSUInteger, MTLCPUCacheMode) { MTLCPUCacheModeDefaultCache = 0, MTLCPUCacheModeWriteCombined = 1 };
typedef NS_OPTIONS(NSUInteger, MTLResourceOptions) { MTLResourceStorageModeShared = 0, MTLResourceStorageModePrivate = 2 << 4 };
typedef NS_ENUM(NSUInteger, MTLLoadAction) { MTLLoadActionDontCare = 0, MTLLoadActionLoad = 1, MTLLoadActionClear = 2 };
typedef NS_ENUM(NSUInteger, MTLStoreAction) { MTLStoreActionDontCare = 0, MTLStoreActionStore = 1, MTLStoreActionMultisampleResolve = 2 };
typedef NS_ENUM(NSUInteger, MTLBlendFactor) {
    MTLBlendFactorZero = 0, MTLBlendFactorOne = 1, MTLBlendFactorSourceColor = 2, MTLBlendFactorOneMinusSourceColor = 3,
    MTLBlendFactorSourceAlpha = 4, MTLBlendFactorOneMinusSourceAlpha = 5,
};
typedef NS_ENUM(NSUInteger, MTLBlendOperation) { MTLBlendOperationAdd = 0, MTLBlendOperationSubtract = 1 };
typedef NS_OPTIONS(NSUInteger, MTLColorWriteMask) { MTLColorWriteMaskNone = 0, MTLColorWriteMaskAll = 0xf };
typedef NS_ENUM(NSUInteger, MTLDataType) {
    MTLDataTypeNone = 0, MTLDataTypeFloat = 3, MTLDataTypeFloat2 = 4, MTLDataTypeInt = 29, MTLDataTypeUInt = 33,
    MTLDataTypeBool = 53,
};

typedef struct { double red, green, blue, alpha; } MTLClearColor;
static inline MTLClearColor MTLClearColorMake(double r, double g, double b, double a) {
    MTLClearColor c = {r, g, b, a};
    return c;
}

@protocol MTLDevice <NSObject>
@property (readonly) NSString *name;
@end
@protocol MTLResource <NSObject>
@end
@protocol MTLTexture <MTLResource>
@end
@protocol MTLFunction <NSObject>
@end

/* nil: no GPU. */
id<MTLDevice> _Nullable MTLCreateSystemDefaultDevice(void);
NSArray<id<MTLDevice>> *MTLCopyAllDevices(void);

@interface MTLTextureDescriptor : NSObject <NSCopying>
+ (MTLTextureDescriptor *)texture2DDescriptorWithPixelFormat:(MTLPixelFormat)pixelFormat width:(NSUInteger)width
                                                      height:(NSUInteger)height mipmapped:(BOOL)mipmapped;
@property MTLTextureType textureType;
@property MTLPixelFormat pixelFormat;
@property NSUInteger width, height, depth, mipmapLevelCount, sampleCount, arrayLength;
@property MTLResourceOptions resourceOptions;
@property MTLCPUCacheMode cpuCacheMode;
@property MTLStorageMode storageMode;
@property MTLTextureUsage usage;
@property BOOL allowGPUOptimizedContents;
@end

@interface MTLRenderPassAttachmentDescriptor : NSObject <NSCopying>
@property (nullable, strong) id<MTLTexture> texture, resolveTexture;
@property NSUInteger level, slice, depthPlane, resolveLevel, resolveSlice, resolveDepthPlane;
@property MTLLoadAction loadAction;
@property MTLStoreAction storeAction;
@end
@interface MTLRenderPassColorAttachmentDescriptor : MTLRenderPassAttachmentDescriptor
@property MTLClearColor clearColor;
@end
@interface MTLRenderPassDepthAttachmentDescriptor : MTLRenderPassAttachmentDescriptor
@property double clearDepth;
@end
@interface MTLRenderPassStencilAttachmentDescriptor : MTLRenderPassAttachmentDescriptor
@property uint32_t clearStencil;
@end
@interface MTLRenderPassColorAttachmentDescriptorArray : NSObject
- (MTLRenderPassColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx;
- (void)setObject:(nullable MTLRenderPassColorAttachmentDescriptor *)a atIndexedSubscript:(NSUInteger)idx;
@end
@interface MTLRenderPassDescriptor : NSObject <NSCopying>
+ (MTLRenderPassDescriptor *)renderPassDescriptor;
@property (readonly) MTLRenderPassColorAttachmentDescriptorArray *colorAttachments;
@property (copy, null_resettable) MTLRenderPassDepthAttachmentDescriptor *depthAttachment;
@property (copy, null_resettable) MTLRenderPassStencilAttachmentDescriptor *stencilAttachment;
@property NSUInteger renderTargetWidth, renderTargetHeight, renderTargetArrayLength, defaultRasterSampleCount;
@end

@interface MTLRenderPipelineColorAttachmentDescriptor : NSObject <NSCopying>
@property MTLPixelFormat pixelFormat;
@property (getter=isBlendingEnabled) BOOL blendingEnabled;
@property MTLBlendFactor sourceRGBBlendFactor, destinationRGBBlendFactor, sourceAlphaBlendFactor, destinationAlphaBlendFactor;
@property MTLBlendOperation rgbBlendOperation, alphaBlendOperation;
@property MTLColorWriteMask writeMask;
@end
@interface MTLRenderPipelineColorAttachmentDescriptorArray : NSObject
- (MTLRenderPipelineColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx;
- (void)setObject:(nullable MTLRenderPipelineColorAttachmentDescriptor *)a atIndexedSubscript:(NSUInteger)idx;
@end
@interface MTLRenderPipelineDescriptor : NSObject <NSCopying>
@property (nullable, copy) NSString *label;
@property (nullable, strong) id<MTLFunction> vertexFunction, fragmentFunction;
@property (nullable, copy) id vertexDescriptor;
@property NSUInteger rasterSampleCount, sampleCount;
@property (getter=isAlphaToCoverageEnabled) BOOL alphaToCoverageEnabled;
@property (getter=isRasterizationEnabled) BOOL rasterizationEnabled;
@property (readonly) MTLRenderPipelineColorAttachmentDescriptorArray *colorAttachments;
@property MTLPixelFormat depthAttachmentPixelFormat, stencilAttachmentPixelFormat;
- (void)reset;
@end

@interface MTLFunctionConstantValues : NSObject <NSCopying>
- (void)setConstantValue:(const void *)value type:(MTLDataType)type atIndex:(NSUInteger)index;
- (void)setConstantValues:(const void *)values type:(MTLDataType)type withRange:(NSRange)range;
- (void)setConstantValue:(const void *)value type:(MTLDataType)type withName:(NSString *)name;
- (void)reset;
@end

#pragma clang assume_nonnull end
#endif
