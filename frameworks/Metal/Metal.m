/* Metal without a GPU: no devices, and descriptors that only hold values. */
#import <Metal/Metal.h>
#include <string.h>

@interface MTLRenderPassAttachmentDescriptor ()
- (void)_bn_take:(id)other;
@end

id<MTLDevice> MTLCreateSystemDefaultDevice(void) { return nil; }
NSArray<id<MTLDevice>> *MTLCopyAllDevices(void) { return @[]; }

@implementation MTLTextureDescriptor
@synthesize textureType = _textureType, pixelFormat = _pixelFormat, width = _width, height = _height,
            depth = _depth, mipmapLevelCount = _mipmapLevelCount, sampleCount = _sampleCount,
            arrayLength = _arrayLength, resourceOptions = _resourceOptions, cpuCacheMode = _cpuCacheMode,
            storageMode = _storageMode, usage = _usage, allowGPUOptimizedContents = _allowGPUOptimizedContents;
- (instancetype)init {
    if ((self = [super init])) {
        _textureType = MTLTextureType2D;
        _pixelFormat = MTLPixelFormatRGBA8Unorm;
        _width = _height = _depth = _mipmapLevelCount = _sampleCount = _arrayLength = 1;
        _storageMode = MTLStorageModeManaged;
        _usage = MTLTextureUsageShaderRead;
        _allowGPUOptimizedContents = YES;
    }
    return self;
}
+ (MTLTextureDescriptor *)texture2DDescriptorWithPixelFormat:(MTLPixelFormat)format width:(NSUInteger)w
                                                      height:(NSUInteger)h mipmapped:(BOOL)mipmapped {
    MTLTextureDescriptor *d = [self new];
    d.pixelFormat = format;
    d.width = w;
    d.height = h;
    if (mipmapped) {
        NSUInteger n = 1;
        for (NSUInteger s = w > h ? w : h; s > 1; s >>= 1) n++;
        d.mipmapLevelCount = n;
    }
    return d;
}
- (id)copyWithZone:(NSZone *)zone {
    MTLTextureDescriptor *d = [[self class] new];
    d->_textureType = _textureType; d->_pixelFormat = _pixelFormat;
    d->_width = _width; d->_height = _height; d->_depth = _depth;
    d->_mipmapLevelCount = _mipmapLevelCount; d->_sampleCount = _sampleCount; d->_arrayLength = _arrayLength;
    d->_resourceOptions = _resourceOptions; d->_cpuCacheMode = _cpuCacheMode; d->_storageMode = _storageMode;
    d->_usage = _usage; d->_allowGPUOptimizedContents = _allowGPUOptimizedContents;
    return d;
}
@end

/* ---- render passes ---- */

@implementation MTLRenderPassAttachmentDescriptor
@synthesize texture = _texture, resolveTexture = _resolveTexture, level = _level, slice = _slice,
            depthPlane = _depthPlane, resolveLevel = _resolveLevel, resolveSlice = _resolveSlice,
            resolveDepthPlane = _resolveDepthPlane, loadAction = _loadAction, storeAction = _storeAction;
- (id)copyWithZone:(NSZone *)zone {
    MTLRenderPassAttachmentDescriptor *a = [[self class] new];
    [a _bn_take:self];
    return a;
}
- (void)_bn_take:(id)other {
    MTLRenderPassAttachmentDescriptor *o = other;
    _texture = o->_texture; _resolveTexture = o->_resolveTexture;
    _level = o->_level; _slice = o->_slice; _depthPlane = o->_depthPlane;
    _resolveLevel = o->_resolveLevel; _resolveSlice = o->_resolveSlice; _resolveDepthPlane = o->_resolveDepthPlane;
    _loadAction = o->_loadAction; _storeAction = o->_storeAction;
}
@end

@implementation MTLRenderPassColorAttachmentDescriptor
@synthesize clearColor = _clearColor;
- (instancetype)init {
    if ((self = [super init])) {
        self.storeAction = MTLStoreActionStore;
        _clearColor = MTLClearColorMake(0, 0, 0, 1);
    }
    return self;
}
- (void)_bn_take:(id)other {
    MTLRenderPassColorAttachmentDescriptor *o = other;
    [super _bn_take:o];
    _clearColor = o->_clearColor;
}
@end

@implementation MTLRenderPassDepthAttachmentDescriptor
@synthesize clearDepth = _clearDepth;
- (instancetype)init {
    if ((self = [super init])) _clearDepth = 1;
    return self;
}
- (void)_bn_take:(id)other {
    MTLRenderPassDepthAttachmentDescriptor *o = other;
    [super _bn_take:o];
    _clearDepth = o->_clearDepth;
}
@end

@implementation MTLRenderPassStencilAttachmentDescriptor
@synthesize clearStencil = _clearStencil;
- (void)_bn_take:(id)other {
    MTLRenderPassStencilAttachmentDescriptor *o = other;
    [super _bn_take:o];
    _clearStencil = o->_clearStencil;
}
@end

/* Eight slots, made on first use, as Apple's arrays are. */
#define SLOTS 8
@implementation MTLRenderPassColorAttachmentDescriptorArray {
@public
    MTLRenderPassColorAttachmentDescriptor *_a[SLOTS];
}
- (MTLRenderPassColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)i {
    if (i >= SLOTS) [NSException raise:NSRangeException format:@"color attachment %lu out of range", (unsigned long)i];
    if (!_a[i]) _a[i] = [MTLRenderPassColorAttachmentDescriptor new];
    return _a[i];
}
- (void)setObject:(MTLRenderPassColorAttachmentDescriptor *)a atIndexedSubscript:(NSUInteger)i {
    if (i < SLOTS) _a[i] = [a copy];
}
@end

@implementation MTLRenderPassDescriptor {
    MTLRenderPassColorAttachmentDescriptorArray *_colors;
    MTLRenderPassDepthAttachmentDescriptor *_depth;
    MTLRenderPassStencilAttachmentDescriptor *_stencil;
}
@synthesize renderTargetWidth = _renderTargetWidth, renderTargetHeight = _renderTargetHeight,
            renderTargetArrayLength = _renderTargetArrayLength, defaultRasterSampleCount = _defaultRasterSampleCount;
+ (MTLRenderPassDescriptor *)renderPassDescriptor { return [self new]; }
- (instancetype)init {
    if ((self = [super init])) {
        _colors = [MTLRenderPassColorAttachmentDescriptorArray new];
        _depth = [MTLRenderPassDepthAttachmentDescriptor new];
        _stencil = [MTLRenderPassStencilAttachmentDescriptor new];
    }
    return self;
}
- (MTLRenderPassColorAttachmentDescriptorArray *)colorAttachments { return _colors; }
- (MTLRenderPassDepthAttachmentDescriptor *)depthAttachment { return _depth; }
- (void)setDepthAttachment:(MTLRenderPassDepthAttachmentDescriptor *)d { _depth = d ? [d copy] : [MTLRenderPassDepthAttachmentDescriptor new]; }
- (MTLRenderPassStencilAttachmentDescriptor *)stencilAttachment { return _stencil; }
- (void)setStencilAttachment:(MTLRenderPassStencilAttachmentDescriptor *)s { _stencil = s ? [s copy] : [MTLRenderPassStencilAttachmentDescriptor new]; }
- (id)copyWithZone:(NSZone *)zone {
    MTLRenderPassDescriptor *d = [[self class] new];
    for (int i = 0; i < SLOTS; i++) d->_colors->_a[i] = [_colors->_a[i] copy];
    d->_depth = [_depth copy];
    d->_stencil = [_stencil copy];
    d->_renderTargetWidth = _renderTargetWidth;
    d->_renderTargetHeight = _renderTargetHeight;
    d->_renderTargetArrayLength = _renderTargetArrayLength;
    d->_defaultRasterSampleCount = _defaultRasterSampleCount;
    return d;
}
@end

/* ---- render pipelines ---- */

@implementation MTLRenderPipelineColorAttachmentDescriptor
@synthesize pixelFormat = _pixelFormat, blendingEnabled = _blendingEnabled,
            sourceRGBBlendFactor = _sourceRGBBlendFactor, destinationRGBBlendFactor = _destinationRGBBlendFactor,
            sourceAlphaBlendFactor = _sourceAlphaBlendFactor, destinationAlphaBlendFactor = _destinationAlphaBlendFactor,
            rgbBlendOperation = _rgbBlendOperation, alphaBlendOperation = _alphaBlendOperation, writeMask = _writeMask;
- (instancetype)init {
    if ((self = [super init])) {
        _sourceRGBBlendFactor = _sourceAlphaBlendFactor = MTLBlendFactorOne;
        _destinationRGBBlendFactor = _destinationAlphaBlendFactor = MTLBlendFactorZero;
        _writeMask = MTLColorWriteMaskAll;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    MTLRenderPipelineColorAttachmentDescriptor *c = [[self class] new];
    c->_pixelFormat = _pixelFormat; c->_blendingEnabled = _blendingEnabled;
    c->_sourceRGBBlendFactor = _sourceRGBBlendFactor; c->_destinationRGBBlendFactor = _destinationRGBBlendFactor;
    c->_sourceAlphaBlendFactor = _sourceAlphaBlendFactor; c->_destinationAlphaBlendFactor = _destinationAlphaBlendFactor;
    c->_rgbBlendOperation = _rgbBlendOperation; c->_alphaBlendOperation = _alphaBlendOperation; c->_writeMask = _writeMask;
    return c;
}
@end

@implementation MTLRenderPipelineColorAttachmentDescriptorArray {
@public
    MTLRenderPipelineColorAttachmentDescriptor *_a[SLOTS];
}
- (MTLRenderPipelineColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)i {
    if (i >= SLOTS) [NSException raise:NSRangeException format:@"color attachment %lu out of range", (unsigned long)i];
    if (!_a[i]) _a[i] = [MTLRenderPipelineColorAttachmentDescriptor new];
    return _a[i];
}
- (void)setObject:(MTLRenderPipelineColorAttachmentDescriptor *)a atIndexedSubscript:(NSUInteger)i {
    if (i < SLOTS) _a[i] = [a copy];
}
@end

@implementation MTLRenderPipelineDescriptor {
    MTLRenderPipelineColorAttachmentDescriptorArray *_colors;
}
@synthesize label = _label, vertexFunction = _vertexFunction, fragmentFunction = _fragmentFunction,
            vertexDescriptor = _vertexDescriptor, rasterSampleCount = _rasterSampleCount,
            alphaToCoverageEnabled = _alphaToCoverageEnabled, rasterizationEnabled = _rasterizationEnabled,
            depthAttachmentPixelFormat = _depthAttachmentPixelFormat,
            stencilAttachmentPixelFormat = _stencilAttachmentPixelFormat;
- (instancetype)init {
    if ((self = [super init])) [self reset];
    return self;
}
- (void)reset {
    _colors = [MTLRenderPipelineColorAttachmentDescriptorArray new];
    _label = nil;
    _vertexFunction = _fragmentFunction = nil;
    _vertexDescriptor = nil;
    _rasterSampleCount = 1;
    _alphaToCoverageEnabled = NO;
    _rasterizationEnabled = YES;
    _depthAttachmentPixelFormat = _stencilAttachmentPixelFormat = MTLPixelFormatInvalid;
}
- (NSUInteger)sampleCount { return _rasterSampleCount; }
- (void)setSampleCount:(NSUInteger)n { _rasterSampleCount = n; }
- (MTLRenderPipelineColorAttachmentDescriptorArray *)colorAttachments { return _colors; }
- (id)copyWithZone:(NSZone *)zone {
    MTLRenderPipelineDescriptor *d = [[self class] new];
    for (int i = 0; i < SLOTS; i++) d->_colors->_a[i] = [_colors->_a[i] copy];
    d->_label = [_label copy];
    d->_vertexFunction = _vertexFunction;
    d->_fragmentFunction = _fragmentFunction;
    d->_vertexDescriptor = [_vertexDescriptor copy];
    d->_rasterSampleCount = _rasterSampleCount;
    d->_alphaToCoverageEnabled = _alphaToCoverageEnabled;
    d->_rasterizationEnabled = _rasterizationEnabled;
    d->_depthAttachmentPixelFormat = _depthAttachmentPixelFormat;
    d->_stencilAttachmentPixelFormat = _stencilAttachmentPixelFormat;
    return d;
}
@end

/* ---- function constants: kept by index and by name as bytes ---- */

static size_t data_type_size(MTLDataType t) {
    switch (t) {
    case MTLDataTypeBool: return 1;
    case MTLDataTypeFloat2: return 8;
    default: return 4;
    }
}

@implementation MTLFunctionConstantValues {
    NSMutableDictionary<id, NSData *> *_values;
}
- (instancetype)init {
    if ((self = [super init])) _values = [NSMutableDictionary dictionary];
    return self;
}
- (void)setConstantValue:(const void *)value type:(MTLDataType)type atIndex:(NSUInteger)index {
    _values[@(index)] = [NSData dataWithBytes:value length:data_type_size(type)];
}
- (void)setConstantValues:(const void *)values type:(MTLDataType)type withRange:(NSRange)range {
    size_t n = data_type_size(type);
    for (NSUInteger i = 0; i < range.length; i++)
        [self setConstantValue:(const char *)values + i * n type:type atIndex:range.location + i];
}
- (void)setConstantValue:(const void *)value type:(MTLDataType)type withName:(NSString *)name {
    _values[[name copy]] = [NSData dataWithBytes:value length:data_type_size(type)];
}
- (void)reset { [_values removeAllObjects]; }
- (id)copyWithZone:(NSZone *)zone {
    MTLFunctionConstantValues *c = [[self class] new];
    [c->_values addEntriesFromDictionary:_values];
    return c;
}
@end
