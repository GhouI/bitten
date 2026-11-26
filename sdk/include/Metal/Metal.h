/* Metal: a software device (frameworks/Metal/MetalDevice.m). Buffers and
 * textures live in memory; shaders are the program's own, compiled from
 * its metallib to x86-64 (tools/metal-compile.py) and run by a software
 * rasteriser. */
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

typedef NS_ENUM(NSUInteger, MTLPrimitiveType) {
    MTLPrimitiveTypePoint = 0, MTLPrimitiveTypeLine = 1, MTLPrimitiveTypeLineStrip = 2, MTLPrimitiveTypeTriangle = 3,
    MTLPrimitiveTypeTriangleStrip = 4,
};
typedef NS_ENUM(NSUInteger, MTLIndexType) { MTLIndexTypeUInt16 = 0, MTLIndexTypeUInt32 = 1 };
typedef NS_ENUM(NSUInteger, MTLCullMode) { MTLCullModeNone = 0, MTLCullModeFront = 1, MTLCullModeBack = 2 };
typedef NS_ENUM(NSUInteger, MTLWinding) { MTLWindingClockwise = 0, MTLWindingCounterClockwise = 1 };
typedef NS_ENUM(NSUInteger, MTLTriangleFillMode) { MTLTriangleFillModeFill = 0, MTLTriangleFillModeLines = 1 };
typedef NS_ENUM(NSUInteger, MTLSamplerMinMagFilter) { MTLSamplerMinMagFilterNearest = 0, MTLSamplerMinMagFilterLinear = 1 };
typedef NS_ENUM(NSUInteger, MTLSamplerMipFilter) {
    MTLSamplerMipFilterNotMipmapped = 0, MTLSamplerMipFilterNearest = 1, MTLSamplerMipFilterLinear = 2,
};
typedef NS_ENUM(NSUInteger, MTLSamplerAddressMode) {
    MTLSamplerAddressModeClampToEdge = 0, MTLSamplerAddressModeMirrorClampToEdge = 1, MTLSamplerAddressModeRepeat = 2,
    MTLSamplerAddressModeMirrorRepeat = 3, MTLSamplerAddressModeClampToZero = 4, MTLSamplerAddressModeClampToBorderColor = 5,
};
typedef NS_ENUM(NSUInteger, MTLCommandBufferStatus) {
    MTLCommandBufferStatusNotEnqueued = 0, MTLCommandBufferStatusEnqueued = 1, MTLCommandBufferStatusCommitted = 2,
    MTLCommandBufferStatusScheduled = 3, MTLCommandBufferStatusCompleted = 4, MTLCommandBufferStatusError = 5,
};
typedef NS_ENUM(NSUInteger, MTLFunctionType) { MTLFunctionTypeVertex = 1, MTLFunctionTypeFragment = 2, MTLFunctionTypeKernel = 3 };
typedef NS_ENUM(NSUInteger, MTLPurgeableState) {
    MTLPurgeableStateKeepCurrent = 1, MTLPurgeableStateNonVolatile = 2, MTLPurgeableStateVolatile = 3, MTLPurgeableStateEmpty = 4,
};
typedef NS_ENUM(NSInteger, MTLGPUFamily) {
    MTLGPUFamilyApple1 = 1001, MTLGPUFamilyApple7 = 1007, MTLGPUFamilyMac1 = 2001, MTLGPUFamilyMac2 = 2002,
    MTLGPUFamilyCommon1 = 3001, MTLGPUFamilyCommon2 = 3002, MTLGPUFamilyCommon3 = 3003, MTLGPUFamilyMetal3 = 5001,
};

typedef struct { NSUInteger x, y, z; } MTLOrigin;
typedef struct { NSUInteger width, height, depth; } MTLSize;
typedef struct { MTLOrigin origin; MTLSize size; } MTLRegion;
typedef struct { double originX, originY, width, height, znear, zfar; } MTLViewport;
typedef struct { NSUInteger x, y, width, height; } MTLScissorRect;
static inline MTLOrigin MTLOriginMake(NSUInteger x, NSUInteger y, NSUInteger z) { MTLOrigin o = {x, y, z}; return o; }
static inline MTLSize MTLSizeMake(NSUInteger w, NSUInteger h, NSUInteger d) { MTLSize s = {w, h, d}; return s; }
static inline MTLRegion MTLRegionMake2D(NSUInteger x, NSUInteger y, NSUInteger w, NSUInteger h) {
    MTLRegion r = {{x, y, 0}, {w, h, 1}};
    return r;
}

@protocol MTLDevice, MTLCommandQueue, MTLCommandBuffer, MTLTexture, MTLBuffer, MTLFunction, MTLLibrary,
    MTLRenderPipelineState, MTLSamplerState, MTLRenderCommandEncoder, MTLBlitCommandEncoder, MTLDrawable;
@class MTLTextureDescriptor, MTLRenderPassDescriptor, MTLRenderPipelineDescriptor, MTLSamplerDescriptor,
    MTLFunctionConstantValues;

@protocol MTLResource <NSObject>
@property (nullable, copy) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) MTLStorageMode storageMode;
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state;
@end

@protocol MTLBuffer <MTLResource>
@property (readonly) NSUInteger length;
- (void *)contents __attribute__((objc_returns_inner_pointer));
- (void)didModifyRange:(NSRange)range;
@end

@protocol MTLTexture <MTLResource>
@property (readonly) MTLTextureType textureType;
@property (readonly) MTLPixelFormat pixelFormat;
@property (readonly) NSUInteger width, height, depth, mipmapLevelCount, sampleCount, arrayLength;
@property (readonly) MTLTextureUsage usage;
@property (readonly, getter=isFramebufferOnly) BOOL framebufferOnly;
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level withBytes:(const void *)bytes bytesPerRow:(NSUInteger)bpr;
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice withBytes:(const void *)bytes
          bytesPerRow:(NSUInteger)bpr bytesPerImage:(NSUInteger)bpi;
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)bpr fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level;
- (nullable id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat;
@end

@protocol MTLSamplerState <NSObject>
@property (nullable, readonly) NSString *label;
@property (readonly) id<MTLDevice> device;
@end

@protocol MTLFunction <NSObject>
@property (nullable, copy) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) MTLFunctionType functionType;
@property (readonly) NSString *name;
@end

@protocol MTLLibrary <NSObject>
@property (nullable, copy) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) NSArray<NSString *> *functionNames;
- (nullable id<MTLFunction>)newFunctionWithName:(NSString *)functionName;
- (nullable id<MTLFunction>)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)values
                                          error:(NSError **)error;
@end

@protocol MTLRenderPipelineState <NSObject>
@property (nullable, readonly) NSString *label;
@property (readonly) id<MTLDevice> device;
@end

@protocol MTLCommandEncoder <NSObject>
@property (nullable, copy) NSString *label;
@property (readonly) id<MTLDevice> device;
- (void)endEncoding;
- (void)pushDebugGroup:(NSString *)string;
- (void)popDebugGroup;
- (void)insertDebugSignpost:(NSString *)string;
@end

@protocol MTLRenderCommandEncoder <MTLCommandEncoder>
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)state;
- (void)setVertexBuffer:(nullable id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setVertexTexture:(nullable id<MTLTexture>)texture atIndex:(NSUInteger)index;
- (void)setVertexSamplerState:(nullable id<MTLSamplerState>)sampler atIndex:(NSUInteger)index;
- (void)setFragmentBuffer:(nullable id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setFragmentTexture:(nullable id<MTLTexture>)texture atIndex:(NSUInteger)index;
- (void)setFragmentSamplerState:(nullable id<MTLSamplerState>)sampler atIndex:(NSUInteger)index;
- (void)setViewport:(MTLViewport)viewport;
- (void)setScissorRect:(MTLScissorRect)rect;
- (void)setCullMode:(MTLCullMode)cullMode;
- (void)setFrontFacingWinding:(MTLWinding)winding;
- (void)setTriangleFillMode:(MTLTriangleFillMode)mode;
- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;
- (void)setDepthStencilState:(nullable id)state;
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start vertexCount:(NSUInteger)count;
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start vertexCount:(NSUInteger)count
         instanceCount:(NSUInteger)instances;
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start vertexCount:(NSUInteger)count
         instanceCount:(NSUInteger)instances baseInstance:(NSUInteger)base;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)type indexCount:(NSUInteger)count indexType:(MTLIndexType)indexType
                  indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)offset;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)type indexCount:(NSUInteger)count indexType:(MTLIndexType)indexType
                  indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)offset
                instanceCount:(NSUInteger)instances;
@end

@protocol MTLBlitCommandEncoder <MTLCommandEncoder>
- (void)copyFromBuffer:(id<MTLBuffer>)src sourceOffset:(NSUInteger)so toBuffer:(id<MTLBuffer>)dst
     destinationOffset:(NSUInteger)dof size:(NSUInteger)size;
- (void)copyFromTexture:(id<MTLTexture>)src toTexture:(id<MTLTexture>)dst;
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value;
- (void)synchronizeResource:(id<MTLResource>)resource;
- (void)generateMipmapsForTexture:(id<MTLTexture>)texture;
@end

@protocol MTLDrawable <NSObject>
- (void)present;
- (void)presentAtTime:(CFTimeInterval)time;
@property (readonly) NSUInteger drawableID;
@property (readonly) CFTimeInterval presentedTime;
- (void)addPresentedHandler:(void (^)(id<MTLDrawable> drawable))block;
@end

typedef void (^MTLCommandBufferHandler)(id<MTLCommandBuffer> buffer);

@protocol MTLCommandBuffer <NSObject>
@property (nullable, copy) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) id<MTLCommandQueue> commandQueue;
@property (readonly) MTLCommandBufferStatus status;
@property (nullable, readonly) NSError *error;
- (nullable id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)descriptor;
- (nullable id<MTLBlitCommandEncoder>)blitCommandEncoder;
- (void)presentDrawable:(id<MTLDrawable>)drawable;
- (void)presentDrawable:(id<MTLDrawable>)drawable atTime:(CFTimeInterval)time;
- (void)addScheduledHandler:(MTLCommandBufferHandler)block;
- (void)addCompletedHandler:(MTLCommandBufferHandler)block;
- (void)enqueue;
- (void)commit;
- (void)waitUntilScheduled;
- (void)waitUntilCompleted;
- (void)pushDebugGroup:(NSString *)string;
- (void)popDebugGroup;
@end

@protocol MTLCommandQueue <NSObject>
@property (nullable, copy) NSString *label;
@property (readonly) id<MTLDevice> device;
- (nullable id<MTLCommandBuffer>)commandBuffer;
- (nullable id<MTLCommandBuffer>)commandBufferWithUnretainedReferences;
@end

@protocol MTLDevice <NSObject>
@property (readonly) NSString *name;
@property (readonly) uint64_t registryID;
@property (readonly) BOOL hasUnifiedMemory, lowPower, headless, removable;
@property (readonly) uint64_t recommendedMaxWorkingSetSize;
@property (readonly) NSUInteger maxBufferLength;
- (nullable id<MTLCommandQueue>)newCommandQueue;
- (nullable id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)count;
- (nullable id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
- (nullable id<MTLBuffer>)newBufferWithBytes:(const void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options;
- (nullable id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (nullable id<MTLSamplerState>)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)descriptor;
- (nullable id<MTLLibrary>)newDefaultLibrary;
- (nullable id<MTLLibrary>)newDefaultLibraryWithBundle:(NSBundle *)bundle error:(NSError **)error;
- (nullable id<MTLLibrary>)newLibraryWithURL:(NSURL *)url error:(NSError **)error;
- (nullable id<MTLLibrary>)newLibraryWithFile:(NSString *)path error:(NSError **)error;
- (nullable id<MTLLibrary>)newLibraryWithData:(id)data error:(NSError **)error;
- (nullable id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
                                                                     error:(NSError **)error;
- (BOOL)supportsFamily:(MTLGPUFamily)family;
- (BOOL)supportsTextureSampleCount:(NSUInteger)count;
@end

/* The software device. */
id<MTLDevice> _Nullable MTLCreateSystemDefaultDevice(void);
NSArray<id<MTLDevice>> *MTLCopyAllDevices(void);

@interface MTLSamplerDescriptor : NSObject <NSCopying>
@property MTLSamplerMinMagFilter minFilter, magFilter;
@property MTLSamplerMipFilter mipFilter;
@property MTLSamplerAddressMode sAddressMode, tAddressMode, rAddressMode;
@property BOOL normalizedCoordinates;
@property (nullable, copy) NSString *label;
@end

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
