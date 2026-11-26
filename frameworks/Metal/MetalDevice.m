/* A software Metal device.
 *
 * Buffers and textures are memory. A library is the program's metallib,
 * compiled to x86-64 by tools/metal-compile.py (through mrun, see
 * src/frameworks/metal/metal.c) into one function per shader,
 * bn_call_<name>(args, out), with a manifest naming what each argument
 * and output is. Render encoders draw as they are told to: each vertex is
 * shaded (arguments from the bound buffers, textures and the vertex and
 * instance ids), triangles are rasterised with perspective-correct
 * interpolation of the vertex outputs into the fragment inputs of the same
 * name, each covered pixel is shaded, and the colour is blended into the
 * attachment. Drawables come from CAMetalLayer and are handed back to it
 * when presented. */
#import <Metal/Metal.h>
#include <math.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- the native side (mrun) ---- */

struct bn_metal_lib;
extern struct bn_metal_lib *bitten_metal_open(const void *data, size_t len, char *why, size_t whylen);
extern const char *bitten_metal_manifest(struct bn_metal_lib *l);
extern void *bitten_metal_entry(struct bn_metal_lib *l, const char *name);

typedef void (*bn_shader_fn)(const void *args, void *out);

/* Shared with tools/metal-runtime.c. */
struct bn_mtl_texture {
    uint8_t *data;
    int32_t width, height, bytes_per_row;
    int32_t format;
};
enum { F_R8 = 0, F_RGBA8 = 1, F_BGRA8 = 2, F_RGBA32F = 3, F_RG8 = 4, F_RGBA16F = 5, F_RGBA8_SRGB = 6, F_BGRA8_SRGB = 7 };

static int format_code(MTLPixelFormat f) {
    switch ((NSUInteger)f) {
    case 1: case 10: return F_R8;      /* A8, R8 */
    case 30: return F_RG8;
    case 70: return F_RGBA8;
    case 71: return F_RGBA8_SRGB;
    case 80: return F_BGRA8;
    case 81: return F_BGRA8_SRGB;
    case 115: return F_RGBA16F;
    case 125: return F_RGBA32F;
    default: return F_BGRA8;
    }
}
static size_t format_bpp(int code) {
    switch (code) {
    case F_R8: return 1;
    case F_RG8: return 2;
    case F_RGBA16F: return 8;
    case F_RGBA32F: return 16;
    default: return 4;
    }
}

static float srgb_to_linear(float c) { return c <= 0.04045f ? c / 12.92f : powf((c + 0.055f) / 1.055f, 2.4f); }
static float linear_to_srgb(float c) { return c <= 0.0031308f ? c * 12.92f : 1.055f * powf(c, 1.0f / 2.4f) - 0.055f; }
static uint16_t float_to_half(float f) {
    uint32_t x;
    memcpy(&x, &f, 4);
    uint32_t s = (x >> 16) & 0x8000, e = (x >> 23) & 0xff, m = x & 0x7fffff;
    if (e == 0xff) return (uint16_t)(s | 0x7c00 | (m ? 0x200 : 0));
    int ne = (int)e - 127 + 15;
    if (ne >= 31) return (uint16_t)(s | 0x7c00);
    if (ne <= 0) return (uint16_t)s;
    return (uint16_t)(s | (uint32_t)ne << 10 | m >> 13);
}
static float half_to_float(uint16_t h) {
    uint32_t s = (uint32_t)(h & 0x8000) << 16, e = (h >> 10) & 0x1f, m = h & 0x3ff, f;
    if (e == 0) f = s;
    else if (e == 31) f = s | 0x7f800000 | m << 13;
    else f = s | (e + 127 - 15) << 23 | m << 13;
    float r;
    memcpy(&r, &f, 4);
    return r;
}
static uint8_t unorm8(float v) {
    if (!(v > 0)) return 0;
    if (v >= 1) return 255;
    return (uint8_t)(v * 255.0f + 0.5f);
}

static void load_pixel(const struct bn_mtl_texture *t, int x, int y, float *o) {
    const uint8_t *p = t->data + (size_t)y * (size_t)t->bytes_per_row;
    switch (t->format) {
    case F_R8: o[0] = p[x] / 255.0f; o[1] = o[2] = 0; o[3] = 1; break;
    case F_RG8: o[0] = p[2 * x] / 255.0f; o[1] = p[2 * x + 1] / 255.0f; o[2] = 0; o[3] = 1; break;
    case F_RGBA8: case F_RGBA8_SRGB:
        for (int i = 0; i < 4; i++) o[i] = p[4 * x + i] / 255.0f;
        break;
    case F_BGRA8: case F_BGRA8_SRGB:
        o[2] = p[4 * x] / 255.0f; o[1] = p[4 * x + 1] / 255.0f; o[0] = p[4 * x + 2] / 255.0f; o[3] = p[4 * x + 3] / 255.0f;
        break;
    case F_RGBA16F: for (int i = 0; i < 4; i++) o[i] = half_to_float(((const uint16_t *)p)[4 * x + i]); break;
    case F_RGBA32F: memcpy(o, p + 16 * x, 16); break;
    }
    if (t->format == F_RGBA8_SRGB || t->format == F_BGRA8_SRGB)
        for (int i = 0; i < 3; i++) o[i] = srgb_to_linear(o[i]);
}
static void store_pixel(struct bn_mtl_texture *t, int x, int y, const float *in) {
    uint8_t *p = t->data + (size_t)y * (size_t)t->bytes_per_row;
    float c[4] = {in[0], in[1], in[2], in[3]};
    if (t->format == F_RGBA8_SRGB || t->format == F_BGRA8_SRGB)
        for (int i = 0; i < 3; i++) c[i] = linear_to_srgb(c[i] < 0 ? 0 : c[i] > 1 ? 1 : c[i]);
    switch (t->format) {
    case F_R8: p[x] = unorm8(c[0]); break;
    case F_RG8: p[2 * x] = unorm8(c[0]); p[2 * x + 1] = unorm8(c[1]); break;
    case F_RGBA8: case F_RGBA8_SRGB: for (int i = 0; i < 4; i++) p[4 * x + i] = unorm8(c[i]); break;
    case F_BGRA8: case F_BGRA8_SRGB:
        p[4 * x] = unorm8(c[2]); p[4 * x + 1] = unorm8(c[1]); p[4 * x + 2] = unorm8(c[0]); p[4 * x + 3] = unorm8(c[3]);
        break;
    case F_RGBA16F: for (int i = 0; i < 4; i++) ((uint16_t *)p)[4 * x + i] = float_to_half(c[i]); break;
    case F_RGBA32F: memcpy(p + 16 * x, c, 16); break;
    }
}

/* BITTEN_METAL_DEBUG=1 traces what programs ask the device for. */
static int mtl_debug = -1;
#define TRACE(...) do { if (mtl_debug < 0) mtl_debug = getenv("BITTEN_METAL_DEBUG") != NULL; \
                        if (mtl_debug) fprintf(stderr, "metal: " __VA_ARGS__); } while (0)

/* ---- the device's objects ---- */

@class BNMTLDevice;
static BNMTLDevice *shared_device;

@interface BNMTLResourceBase : NSObject <MTLResource> {
@public
    NSString *_label;
    __weak id<MTLDevice> _device;
}
@end
@implementation BNMTLResourceBase
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { _label = [l copy]; }
- (id<MTLDevice>)device { return _device; }
- (MTLStorageMode)storageMode { return MTLStorageModeShared; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)s { return MTLPurgeableStateNonVolatile; }
- (MTLCPUCacheMode)cpuCacheMode { return MTLCPUCacheModeDefaultCache; }
- (MTLResourceOptions)resourceOptions { return MTLResourceStorageModeShared; }
- (NSUInteger)allocatedSize { return 0; }
- (BOOL)isAliasable { return NO; }
- (void)makeAliasable {}
@end

@interface BNMTLBuffer : BNMTLResourceBase <MTLBuffer> {
@public
    void *_bytes;
    NSUInteger _length;
    void (^_deallocator)(void *, NSUInteger);
}
@end
@implementation BNMTLBuffer
- (void)dealloc {
    if (_deallocator) _deallocator(_bytes, _length);
    else free(_bytes);
}
- (NSUInteger)length { return _length; }
- (void *)contents { return _bytes; }
- (void)didModifyRange:(NSRange)r {}
- (uint64_t)gpuAddress { return (uint64_t)(uintptr_t)_bytes; }
- (NSUInteger)allocatedSize { return _length; }
@end

@interface BNMTLTexture : BNMTLResourceBase <MTLTexture> {
@public
    struct bn_mtl_texture _t;
    MTLPixelFormat _pixelFormat;
    MTLTextureType _type;
    MTLTextureUsage _usage;
    NSUInteger _mips, _arrayLength;
    BOOL _framebufferOnly, _ownsData;
    id _parent;
}
@end
@implementation BNMTLTexture
- (instancetype)initWithBNDescriptor:(MTLTextureDescriptor *)d device:(id<MTLDevice>)dev {
    if ((self = [super init])) {
        _device = dev;
        _pixelFormat = d.pixelFormat;
        _type = d.textureType;
        _usage = d.usage;
        _mips = d.mipmapLevelCount;
        _arrayLength = d.arrayLength;
        _t.format = format_code(d.pixelFormat);
        _t.width = (int32_t)d.width;
        _t.height = (int32_t)d.height;
        _t.bytes_per_row = (int32_t)(format_bpp(_t.format) * d.width);
        _t.data = calloc((size_t)_t.bytes_per_row * (size_t)(d.height ? d.height : 1), 1);
        _ownsData = YES;
    }
    return self;
}
- (void)dealloc {
    if (_ownsData) free(_t.data);
}
- (struct bn_mtl_texture *)_bn_texture { return &_t; }
- (MTLTextureType)textureType { return _type; }
- (MTLPixelFormat)pixelFormat { return _pixelFormat; }
- (NSUInteger)width { return (NSUInteger)_t.width; }
- (NSUInteger)height { return (NSUInteger)_t.height; }
- (NSUInteger)depth { return 1; }
- (NSUInteger)mipmapLevelCount { return _mips; }
- (NSUInteger)sampleCount { return 1; }
- (NSUInteger)arrayLength { return _arrayLength; }
- (MTLTextureUsage)usage { return _usage; }
- (BOOL)isFramebufferOnly { return _framebufferOnly; }
- (id)iosurface { return nil; }
- (id)parentTexture { return _parent; }
- (id)buffer { return nil; }
- (NSUInteger)allocatedSize { return (NSUInteger)_t.bytes_per_row * (NSUInteger)_t.height; }
- (void)replaceRegion:(MTLRegion)r mipmapLevel:(NSUInteger)level withBytes:(const void *)bytes bytesPerRow:(NSUInteger)bpr {
    if (level != 0 || !bytes) return;
    size_t bpp = format_bpp(_t.format);
    for (NSUInteger row = 0; row < r.size.height; row++) {
        NSUInteger y = r.origin.y + row;
        if (y >= (NSUInteger)_t.height) break;
        NSUInteger w = MIN(r.size.width, (NSUInteger)_t.width - MIN(r.origin.x, (NSUInteger)_t.width));
        memcpy(_t.data + y * (NSUInteger)_t.bytes_per_row + r.origin.x * bpp, (const uint8_t *)bytes + row * bpr, w * bpp);
    }
}
- (void)replaceRegion:(MTLRegion)r mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice withBytes:(const void *)bytes
          bytesPerRow:(NSUInteger)bpr bytesPerImage:(NSUInteger)bpi {
    if (slice == 0) [self replaceRegion:r mipmapLevel:level withBytes:bytes bytesPerRow:bpr];
}
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)bpr fromRegion:(MTLRegion)r mipmapLevel:(NSUInteger)level {
    size_t bpp = format_bpp(_t.format);
    for (NSUInteger row = 0; row < r.size.height && r.origin.y + row < (NSUInteger)_t.height; row++)
        memcpy((uint8_t *)bytes + row * bpr, _t.data + (r.origin.y + row) * (NSUInteger)_t.bytes_per_row + r.origin.x * bpp,
               r.size.width * bpp);
}
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)bpr bytesPerImage:(NSUInteger)bpi fromRegion:(MTLRegion)r
     mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice {
    [self getBytes:bytes bytesPerRow:bpr fromRegion:r mipmapLevel:level];
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)format {
    BNMTLTexture *v = [BNMTLTexture new];
    v->_device = _device;
    v->_t = _t;
    v->_t.format = format_code(format);
    v->_pixelFormat = format;
    v->_type = _type;
    v->_usage = _usage;
    v->_mips = _mips;
    v->_arrayLength = _arrayLength;
    v->_parent = self;
    return v;
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)format textureType:(MTLTextureType)type
                                         levels:(NSRange)levels slices:(NSRange)slices {
    return [self newTextureViewWithPixelFormat:format];
}
@end

@interface BNMTLSampler : NSObject <MTLSamplerState> {
@public
    uint64_t _state[2];   /* AIR's encoding, as constexpr samplers have it */
    NSString *_label;
    __weak id<MTLDevice> _device;
}
@end
@implementation BNMTLSampler
- (NSString *)label { return _label; }
- (id<MTLDevice>)device { return _device; }
@end

@implementation MTLSamplerDescriptor
@synthesize minFilter = _minFilter, magFilter = _magFilter, mipFilter = _mipFilter, sAddressMode = _sAddressMode,
            tAddressMode = _tAddressMode, rAddressMode = _rAddressMode, normalizedCoordinates = _normalizedCoordinates,
            label = _label;
- (instancetype)init {
    if ((self = [super init])) _normalizedCoordinates = YES;
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    MTLSamplerDescriptor *d = [MTLSamplerDescriptor new];
    d->_minFilter = _minFilter; d->_magFilter = _magFilter; d->_mipFilter = _mipFilter;
    d->_sAddressMode = _sAddressMode; d->_tAddressMode = _tAddressMode; d->_rAddressMode = _rAddressMode;
    d->_normalizedCoordinates = _normalizedCoordinates; d->_label = _label;
    return d;
}
@end

/* ---- libraries and functions ---- */

typedef enum { A_VERTEX_ID, A_INSTANCE_ID, A_BUFFER, A_TEXTURE, A_SAMPLER, A_POSITION, A_INPUT, A_OTHER } ArgKind;
typedef struct {
    int slot;          /* the argument's position */
    ArgKind kind;
    int index;         /* buffer/texture/sampler index */
    char input[96];    /* fragment input name */
} Arg;
typedef struct {
    int position;      /* output slot of the position, or -1 */
    char name[96];     /* user output name */
    int flat;          /* integer outputs are not interpolated */
    int components;
} Out;

@interface BNMTLFunction : NSObject <MTLFunction> {
@public
    NSString *_name, *_label;
    __weak id<MTLDevice> _device;
    MTLFunctionType _type;
    bn_shader_fn _entry;
    Arg _args[24];
    int _nargs;
    Out _outs[16];
    int _nouts;
}
@end
@implementation BNMTLFunction
- (NSString *)name { return _name; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { _label = [l copy]; }
- (id<MTLDevice>)device { return _device; }
- (MTLFunctionType)functionType { return _type; }
- (NSDictionary *)functionConstantsDictionary { return @{}; }
- (NSArray *)vertexAttributes { return @[]; }
- (NSArray *)stageInputAttributes { return @[]; }
- (NSInteger)patchControlPointCount { return 0; }
@end

@interface BNMTLLibrary : NSObject <MTLLibrary> {
@public
    struct bn_metal_lib *_lib;
    NSMutableDictionary<NSString *, BNMTLFunction *> *_functions;
    NSString *_label;
    __weak id<MTLDevice> _device;
}
@end
@implementation BNMTLLibrary
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { _label = [l copy]; }
- (id<MTLDevice>)device { return _device; }
- (NSArray<NSString *> *)functionNames { return _functions.allKeys; }
- (NSString *)installName { return nil; }
- (id<MTLFunction>)newFunctionWithName:(NSString *)name {
    TRACE("function %s -> %p\n", name.UTF8String, (__bridge void *)_functions[name]);
    return _functions[name];
}
- (id<MTLFunction>)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)values
                                 error:(NSError **)error {
    BNMTLFunction *f = _functions[name];
    TRACE("function %s (constants) -> %p\n", name.UTF8String, (__bridge void *)f);
    if (!f && error)
        *error = [NSError errorWithDomain:@"MTLLibraryErrorDomain" code:5
                                 userInfo:@{NSLocalizedDescriptionKey : [@"Function not found: " stringByAppendingString:name ?: @""]}];
    return f;
}
- (void)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)values
          completionHandler:(void (^)(id<MTLFunction>, NSError *))handler {
    NSError *e = nil;
    id f = [self newFunctionWithName:name constantValues:values error:&e];
    handler(f, e);
}

/* The manifest: "function NAME KIND", then "arg I KIND ...", "out J ...". */
- (void)_bn_readManifest:(const char *)text {
    _functions = [NSMutableDictionary dictionary];
    BNMTLFunction *cur = nil;
    for (NSString *line in [@(text) componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *w = [line componentsSeparatedByString:@" "];
        if (w.count < 2) continue;
        if ([w[0] isEqual:@"function"] && w.count >= 3) {
            cur = [BNMTLFunction new];
            cur->_name = w[1];
            cur->_device = _device;
            cur->_type = [w[2] isEqual:@"vertex"] ? MTLFunctionTypeVertex : [w[2] isEqual:@"fragment"] ? MTLFunctionTypeFragment
                                                                                                        : MTLFunctionTypeKernel;
            cur->_entry = (bn_shader_fn)bitten_metal_entry(_lib, w[1].UTF8String);
            if (cur->_entry) _functions[w[1]] = cur;
        } else if ([w[0] isEqual:@"arg"] && cur && w.count >= 3 && cur->_nargs < 24) {
            Arg *a = &cur->_args[cur->_nargs++];
            memset(a, 0, sizeof *a);
            a->slot = w[1].intValue;
            NSString *k = w[2];
            if ([k isEqual:@"vertex_id"]) a->kind = A_VERTEX_ID;
            else if ([k isEqual:@"instance_id"]) a->kind = A_INSTANCE_ID;
            else if ([k isEqual:@"position"]) a->kind = A_POSITION;
            else if ([k isEqual:@"buffer"]) a->kind = A_BUFFER;
            else if ([k isEqual:@"texture"]) a->kind = A_TEXTURE;
            else if ([k isEqual:@"sampler"]) a->kind = A_SAMPLER;
            else if ([k isEqual:@"input"]) a->kind = A_INPUT;
            else a->kind = A_OTHER;
            if ((a->kind == A_BUFFER || a->kind == A_TEXTURE || a->kind == A_SAMPLER) && w.count > 3) a->index = w[3].intValue;
            if (a->kind == A_INPUT && w.count > 3) snprintf(a->input, sizeof a->input, "%s", w[3].UTF8String);
        } else if ([w[0] isEqual:@"out"] && cur && w.count >= 3 && cur->_nouts < 16) {
            Out *o = &cur->_outs[cur->_nouts++];
            memset(o, 0, sizeof *o);
            o->position = [w[2] isEqual:@"position"];
            if ([w[2] isEqual:@"user"] && w.count >= 5) {
                snprintf(o->name, sizeof o->name, "%s", w[3].UTF8String);
                NSString *t = w[4];
                o->flat = [t hasPrefix:@"uint"] || [t hasPrefix:@"int"] || [t hasPrefix:@"ushort"] || [t hasPrefix:@"short"] ||
                          [t hasPrefix:@"uchar"] || [t hasPrefix:@"char"] || [t hasPrefix:@"bool"];
                unichar last = t.length ? [t characterAtIndex:t.length - 1] : '1';
                o->components = (last >= '2' && last <= '4') ? last - '0' : 1;
            }
        }
    }
}
@end

static NSError *mtl_error(NSString *msg) {
    return [NSError errorWithDomain:@"MTLLibraryErrorDomain" code:1 userInfo:@{NSLocalizedDescriptionKey : msg ?: @"error"}];
}

/* ---- pipelines ---- */

@interface BNMTLPipeline : NSObject <MTLRenderPipelineState> {
@public
    BNMTLFunction *_vertex, *_fragment;
    BOOL _blend;
    MTLBlendFactor _srcRGB, _dstRGB, _srcA, _dstA;
    MTLBlendOperation _opRGB, _opA;
    MTLColorWriteMask _mask;
    NSString *_label;
    __weak id<MTLDevice> _device;
    int _map[16];     /* fragment argument -> vertex output slot */
}
@end
@implementation BNMTLPipeline
- (NSString *)label { return _label; }
- (id<MTLDevice>)device { return _device; }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return 1; }
- (BOOL)supportIndirectCommandBuffers { return NO; }
@end

/* ---- the rasteriser ---- */

typedef struct {
    id buffers[31];
    NSUInteger offsets[31];
    NSData *bytes[31];
    id textures[31];
    id samplers[16];
} Bindings;

static const void *binding_buffer(Bindings *b, int i) {
    if (i < 0 || i >= 31) return NULL;
    if (b->bytes[i]) return b->bytes[i].bytes;
    BNMTLBuffer *buf = b->buffers[i];
    return buf ? (const uint8_t *)buf->_bytes + b->offsets[i] : NULL;
}

/* A vertex: its clip position and outputs, 16 bytes each. */
typedef struct { float v[16][4]; } VOut;

typedef struct {
    BNMTLPipeline *p;
    Bindings *vb, *fb;
    struct bn_mtl_texture *target;
    MTLViewport vp;
    MTLScissorRect scissor;
    BOOL scissorSet;
    float blend[4];
} DrawState;

static void shade_vertex(DrawState *s, uint32_t vid, uint32_t iid, VOut *out) {
    BNMTLFunction *f = s->p->_vertex;
    uint8_t args[24 * 16] __attribute__((aligned(16)));
    memset(args, 0, sizeof args);
    for (int i = 0; i < f->_nargs; i++) {
        Arg *a = &f->_args[i];
        uint8_t *slot = args + 16 * a->slot;
        switch (a->kind) {
        case A_VERTEX_ID: memcpy(slot, &vid, 4); break;
        case A_INSTANCE_ID: memcpy(slot, &iid, 4); break;
        case A_BUFFER: {
            const void *p = binding_buffer(s->vb, a->index);
            memcpy(slot, &p, sizeof p);
            break;
        }
        case A_TEXTURE: {
            BNMTLTexture *t = a->index < 31 ? s->vb->textures[a->index] : nil;
            const void *p = t ? &t->_t : NULL;
            memcpy(slot, &p, sizeof p);
            break;
        }
        case A_SAMPLER: {
            BNMTLSampler *sm = a->index < 16 ? s->vb->samplers[a->index] : nil;
            const void *p = sm ? sm->_state : NULL;
            memcpy(slot, &p, sizeof p);
            break;
        }
        default: break;
        }
    }
    memset(out, 0, sizeof *out);
    f->_entry(args, out);
}

static float blend_factor(MTLBlendFactor f, const float *src, const float *dst, int c, const float *k) {
    switch ((NSUInteger)f) {
    case 0: return 0;
    case 1: return 1;
    case 2: return src[c];
    case 3: return 1 - src[c];
    case 4: return src[3];
    case 5: return 1 - src[3];
    case 6: return dst[c];             /* destination colour */
    case 7: return 1 - dst[c];
    case 8: return dst[3];             /* destination alpha */
    case 9: return 1 - dst[3];
    case 10: { float m = 1 - dst[3]; return c == 3 ? 1 : (src[3] < m ? src[3] : m); } /* saturate */
    case 11: return k[c];              /* blend colour */
    case 12: return 1 - k[c];
    case 13: return k[3];
    case 14: return 1 - k[3];
    default: return 1;
    }
}

static void write_fragment(DrawState *s, int x, int y, const float *src) {
    BNMTLPipeline *p = s->p;
    float out[4] = {src[0], src[1], src[2], src[3]};
    if (p->_blend) {
        float dst[4];
        load_pixel(s->target, x, y, dst);
        for (int c = 0; c < 4; c++) {
            MTLBlendFactor sf = c < 3 ? p->_srcRGB : p->_srcA, df = c < 3 ? p->_dstRGB : p->_dstA;
            MTLBlendOperation op = c < 3 ? p->_opRGB : p->_opA;
            float a = src[c] * blend_factor(sf, src, dst, c, s->blend), b = dst[c] * blend_factor(df, src, dst, c, s->blend);
            switch ((NSUInteger)op) {
            case 1: out[c] = a - b; break;           /* subtract */
            case 2: out[c] = b - a; break;           /* reverse subtract */
            case 3: out[c] = src[c] < dst[c] ? src[c] : dst[c]; break;
            case 4: out[c] = src[c] > dst[c] ? src[c] : dst[c]; break;
            default: out[c] = a + b;
            }
        }
    }
    if (p->_mask != MTLColorWriteMaskAll) {
        float dst[4];
        load_pixel(s->target, x, y, dst);
        /* red 8, green 4, blue 2, alpha 1 */
        if (!(p->_mask & 8)) out[0] = dst[0];
        if (!(p->_mask & 4)) out[1] = dst[1];
        if (!(p->_mask & 2)) out[2] = dst[2];
        if (!(p->_mask & 1)) out[3] = dst[3];
    }
    store_pixel(s->target, x, y, out);
}

static float edge(float ax, float ay, float bx, float by, float px, float py) {
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax);
}

static void raster_triangle(DrawState *s, const VOut *v0, const VOut *v1, const VOut *v2) {
    BNMTLPipeline *p = s->p;
    BNMTLFunction *vf = p->_vertex, *ff = p->_fragment;
    if (!ff) return;
    int pos = 0;
    for (int i = 0; i < vf->_nouts; i++)
        if (vf->_outs[i].position) pos = i;
    const VOut *v[3] = {v0, v1, v2};
    float sx[3], sy[3], sz[3], iw[3];
    for (int i = 0; i < 3; i++) {
        const float *c = v[i]->v[pos];
        float w = c[3] != 0 ? c[3] : 1e-6f;
        float nx = c[0] / w, ny = c[1] / w;
        sx[i] = (float)(s->vp.originX + (nx + 1) * 0.5 * s->vp.width);
        sy[i] = (float)(s->vp.originY + (1 - ny) * 0.5 * s->vp.height);
        sz[i] = c[2] / w;
        iw[i] = 1.0f / w;
    }
    float area = edge(sx[0], sy[0], sx[1], sy[1], sx[2], sy[2]);
    if (fabsf(area) < 1e-12f) return;
    int minx = (int)floorf(fminf(sx[0], fminf(sx[1], sx[2]))), maxx = (int)ceilf(fmaxf(sx[0], fmaxf(sx[1], sx[2])));
    int miny = (int)floorf(fminf(sy[0], fminf(sy[1], sy[2]))), maxy = (int)ceilf(fmaxf(sy[0], fmaxf(sy[1], sy[2])));
    int cx0 = 0, cy0 = 0, cx1 = s->target->width, cy1 = s->target->height;
    if (s->scissorSet) {
        cx0 = (int)s->scissor.x;
        cy0 = (int)s->scissor.y;
        cx1 = (int)MIN((NSUInteger)cx1, s->scissor.x + s->scissor.width);
        cy1 = (int)MIN((NSUInteger)cy1, s->scissor.y + s->scissor.height);
    }
    if (minx < cx0) minx = cx0;
    if (miny < cy0) miny = cy0;
    if (maxx > cx1) maxx = cx1;
    if (maxy > cy1) maxy = cy1;
    if (minx >= maxx || miny >= maxy) return;

    uint8_t args[24 * 16] __attribute__((aligned(16)));
    memset(args, 0, sizeof args);
    /* the bindings and constants once */
    for (int i = 0; i < ff->_nargs; i++) {
        Arg *a = &ff->_args[i];
        uint8_t *slot = args + 16 * a->slot;
        const void *ptr = NULL;
        if (a->kind == A_BUFFER) ptr = binding_buffer(s->fb, a->index);
        else if (a->kind == A_TEXTURE) {
            BNMTLTexture *t = a->index < 31 ? s->fb->textures[a->index] : nil;
            ptr = t ? &t->_t : NULL;
        } else if (a->kind == A_SAMPLER) {
            BNMTLSampler *sm = a->index < 16 ? s->fb->samplers[a->index] : nil;
            ptr = sm ? sm->_state : NULL;
        } else {
            continue;
        }
        memcpy(slot, &ptr, sizeof ptr);
    }
    float inv = 1.0f / area;
    for (int y = miny; y < maxy; y++) {
        float py = (float)y + 0.5f;
        for (int x = minx; x < maxx; x++) {
            float px = (float)x + 0.5f;
            float w0 = edge(sx[1], sy[1], sx[2], sy[2], px, py) * inv;
            float w1 = edge(sx[2], sy[2], sx[0], sy[0], px, py) * inv;
            float w2 = edge(sx[0], sy[0], sx[1], sy[1], px, py) * inv;
            if (w0 < 0 || w1 < 0 || w2 < 0) continue;
            /* perspective-correct weights */
            float q0 = w0 * iw[0], q1 = w1 * iw[1], q2 = w2 * iw[2], qs = q0 + q1 + q2;
            if (qs == 0) continue;
            q0 /= qs; q1 /= qs; q2 /= qs;
            for (int i = 0; i < ff->_nargs; i++) {
                Arg *a = &ff->_args[i];
                float *slot = (float *)(args + 16 * a->slot);
                if (a->kind == A_POSITION) {
                    slot[0] = px;
                    slot[1] = py;
                    slot[2] = w0 * sz[0] + w1 * sz[1] + w2 * sz[2];
                    slot[3] = w0 * iw[0] + w1 * iw[1] + w2 * iw[2];
                } else if (a->kind == A_INPUT) {
                    int o = p->_map[i];
                    if (o < 0) {
                        memset(slot, 0, 16);
                        continue;
                    }
                    if (vf->_outs[o].flat) {
                        memcpy(slot, v0->v[o], 16);
                    } else {
                        for (int c = 0; c < 4; c++) slot[c] = q0 * v0->v[o][c] + q1 * v1->v[o][c] + q2 * v2->v[o][c];
                    }
                }
            }
            float color[4] __attribute__((aligned(16))) = {0, 0, 0, 0};
            float outbuf[16 * 4] __attribute__((aligned(16)));
            ff->_entry(args, outbuf);
            memcpy(color, outbuf, 16);
            write_fragment(s, x, y, color);
        }
    }
}

static void draw(DrawState *s, MTLPrimitiveType type, NSUInteger start, NSUInteger count, NSUInteger instances,
                 NSUInteger base, const uint32_t *indices) {
    if (!s->p || !s->p->_vertex || !s->target || !s->target->data || !count) return;
    VOut *verts = malloc(sizeof(VOut) * count);
    for (NSUInteger inst = 0; inst < instances; inst++) {
        for (NSUInteger i = 0; i < count; i++)
            shade_vertex(s, indices ? indices[i] : (uint32_t)(start + i), (uint32_t)(base + inst), &verts[i]);
        if (type == MTLPrimitiveTypeTriangle) {
            for (NSUInteger i = 0; i + 2 < count; i += 3) raster_triangle(s, &verts[i], &verts[i + 1], &verts[i + 2]);
        } else if (type == MTLPrimitiveTypeTriangleStrip) {
            for (NSUInteger i = 0; i + 2 < count; i++) {
                if (i & 1) raster_triangle(s, &verts[i + 1], &verts[i], &verts[i + 2]);
                else raster_triangle(s, &verts[i], &verts[i + 1], &verts[i + 2]);
            }
        }
    }
    free(verts);
}

/* ---- encoders ---- */

@interface BNMTLRenderEncoder : NSObject <MTLRenderCommandEncoder> {
@public
    Bindings _vb, _fb;
    DrawState _s;
    BNMTLTexture *_target;
    NSString *_label;
    __weak id<MTLDevice> _device;
}
@end
@implementation BNMTLRenderEncoder
- (instancetype)initWithBNPass:(MTLRenderPassDescriptor *)d device:(id<MTLDevice>)dev {
    if ((self = [super init])) {
        _device = dev;
        MTLRenderPassColorAttachmentDescriptor *c = d.colorAttachments[0];
        _target = (BNMTLTexture *)c.texture;
        if ([_target isKindOfClass:[BNMTLTexture class]]) {
            _s.target = &_target->_t;
            if (c.loadAction == MTLLoadActionClear) {
                MTLClearColor cc = c.clearColor;
                float col[4] = {(float)cc.red, (float)cc.green, (float)cc.blue, (float)cc.alpha};
                for (int y = 0; y < _target->_t.height; y++)
                    for (int x = 0; x < _target->_t.width; x++) store_pixel(&_target->_t, x, y, col);
            }
            _s.vp = (MTLViewport){0, 0, _target->_t.width, _target->_t.height, 0, 1};
        }
        _s.vb = &_vb;
        _s.fb = &_fb;
    }
    return self;
}
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { _label = [l copy]; }
- (id<MTLDevice>)device { return _device; }
- (void)endEncoding {}
- (void)pushDebugGroup:(NSString *)s {}
- (void)popDebugGroup {}
- (void)insertDebugSignpost:(NSString *)s {}
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)st { _s.p = (BNMTLPipeline *)st; }
static void set_buffer(Bindings *b, id buf, NSUInteger off, NSUInteger i) {
    if (i >= 31) return;
    b->buffers[i] = buf;
    b->offsets[i] = off;
    b->bytes[i] = nil;
}
static void set_bytes(Bindings *b, const void *p, NSUInteger n, NSUInteger i) {
    if (i >= 31) return;
    b->bytes[i] = [NSData dataWithBytes:p length:n];
    b->buffers[i] = nil;
}
- (void)setVertexBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i { set_buffer(&_vb, b, o, i); }
- (void)setVertexBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i { if (i < 31) _vb.offsets[i] = o; }
- (void)setVertexBytes:(const void *)p length:(NSUInteger)n atIndex:(NSUInteger)i { set_bytes(&_vb, p, n, i); }
- (void)setVertexTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i { if (i < 31) _vb.textures[i] = t; }
- (void)setVertexSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i { if (i < 16) _vb.samplers[i] = s; }
- (void)setFragmentBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i { set_buffer(&_fb, b, o, i); }
- (void)setFragmentBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i { if (i < 31) _fb.offsets[i] = o; }
- (void)setFragmentBytes:(const void *)p length:(NSUInteger)n atIndex:(NSUInteger)i { set_bytes(&_fb, p, n, i); }
- (void)setFragmentTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i { if (i < 31) _fb.textures[i] = t; }
- (void)setFragmentSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i { if (i < 16) _fb.samplers[i] = s; }
- (void)setViewport:(MTLViewport)v { _s.vp = v; }
- (void)setScissorRect:(MTLScissorRect)r {
    _s.scissor = r;
    _s.scissorSet = YES;
}
- (void)setCullMode:(MTLCullMode)m {}
- (void)setFrontFacingWinding:(MTLWinding)w {}
- (void)setTriangleFillMode:(MTLTriangleFillMode)m {}
- (void)setDepthStencilState:(id)s {}
- (void)setStencilReferenceValue:(uint32_t)v {}
- (void)setDepthBias:(float)b slopeScale:(float)s clamp:(float)c {}
- (void)setBlendColorRed:(float)r green:(float)g blue:(float)b alpha:(float)a {
    _s.blend[0] = r; _s.blend[1] = g; _s.blend[2] = b; _s.blend[3] = a;
}
- (void)useResource:(id)r usage:(NSUInteger)u {}
- (void)useResource:(id)r usage:(NSUInteger)u stages:(NSUInteger)s {}
- (void)memoryBarrierWithScope:(NSUInteger)scope afterStages:(NSUInteger)a beforeStages:(NSUInteger)b {}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)c {
    draw(&_s, t, s, c, 1, 0, NULL);
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)c instanceCount:(NSUInteger)n {
    draw(&_s, t, s, c, n, 0, NULL);
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)c instanceCount:(NSUInteger)n
          baseInstance:(NSUInteger)b {
    draw(&_s, t, s, c, n, b, NULL);
}
- (void)_bn_indexed:(MTLPrimitiveType)t count:(NSUInteger)c type:(MTLIndexType)it buffer:(id<MTLBuffer>)ib
             offset:(NSUInteger)o instances:(NSUInteger)n base:(NSUInteger)b {
    uint32_t *idx = malloc(sizeof(uint32_t) * (c ? c : 1));
    const uint8_t *src = (const uint8_t *)ib.contents + o;
    for (NSUInteger i = 0; i < c; i++)
        idx[i] = it == MTLIndexTypeUInt16 ? ((const uint16_t *)src)[i] : ((const uint32_t *)src)[i];
    draw(&_s, t, 0, c, n, b, idx);
    free(idx);
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)c indexType:(MTLIndexType)it
                  indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)o {
    [self _bn_indexed:t count:c type:it buffer:ib offset:o instances:1 base:0];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)c indexType:(MTLIndexType)it
                  indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)o instanceCount:(NSUInteger)n {
    [self _bn_indexed:t count:c type:it buffer:ib offset:o instances:n base:0];
}
@end

@interface BNMTLBlitEncoder : NSObject <MTLBlitCommandEncoder> {
@public
    NSString *_label;
    __weak id<MTLDevice> _device;
}
@end
@implementation BNMTLBlitEncoder
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { _label = [l copy]; }
- (id<MTLDevice>)device { return _device; }
- (void)endEncoding {}
- (void)pushDebugGroup:(NSString *)s {}
- (void)popDebugGroup {}
- (void)insertDebugSignpost:(NSString *)s {}
- (void)copyFromBuffer:(id<MTLBuffer>)src sourceOffset:(NSUInteger)so toBuffer:(id<MTLBuffer>)dst
     destinationOffset:(NSUInteger)dof size:(NSUInteger)size {
    memmove((uint8_t *)dst.contents + dof, (const uint8_t *)src.contents + so, size);
}
- (void)copyFromTexture:(id<MTLTexture>)src toTexture:(id<MTLTexture>)dst {
    BNMTLTexture *s = (BNMTLTexture *)src, *d = (BNMTLTexture *)dst;
    int h = MIN(s->_t.height, d->_t.height);
    size_t n = MIN((size_t)s->_t.bytes_per_row, (size_t)d->_t.bytes_per_row);
    for (int y = 0; y < h; y++) memcpy(d->_t.data + (size_t)y * d->_t.bytes_per_row, s->_t.data + (size_t)y * s->_t.bytes_per_row, n);
}
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl
           sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)dst
       destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)dorg {
    BNMTLTexture *s = (BNMTLTexture *)src, *d = (BNMTLTexture *)dst;
    size_t bpp = format_bpp(s->_t.format);
    for (NSUInteger y = 0; y < size.height; y++) {
        if (so.y + y >= (NSUInteger)s->_t.height || dorg.y + y >= (NSUInteger)d->_t.height) break;
        memcpy(d->_t.data + (dorg.y + y) * (NSUInteger)d->_t.bytes_per_row + dorg.x * bpp,
               s->_t.data + (so.y + y) * (NSUInteger)s->_t.bytes_per_row + so.x * bpp, size.width * bpp);
    }
}
- (void)copyFromBuffer:(id<MTLBuffer>)src sourceOffset:(NSUInteger)so sourceBytesPerRow:(NSUInteger)bpr
    sourceBytesPerImage:(NSUInteger)bpi sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)dst
       destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)o {
    [dst replaceRegion:(MTLRegion){o, size} mipmapLevel:0 withBytes:(const uint8_t *)src.contents + so bytesPerRow:bpr];
}
- (void)fillBuffer:(id<MTLBuffer>)b range:(NSRange)r value:(uint8_t)v { memset((uint8_t *)b.contents + r.location, v, r.length); }
- (void)synchronizeResource:(id<MTLResource>)r {}
- (void)synchronizeTexture:(id<MTLTexture>)t slice:(NSUInteger)s level:(NSUInteger)l {}
- (void)generateMipmapsForTexture:(id<MTLTexture>)t {}
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)t {}
@end

/* ---- command buffers and queues ---- */

@interface BNMTLCommandQueue : NSObject <MTLCommandQueue> {
@public
    NSString *_label;
    __weak id<MTLDevice> _device;
    dispatch_queue_t _completion;
}
@end

@interface BNMTLCommandBuffer : NSObject <MTLCommandBuffer> {
@public
    BNMTLCommandQueue *_queue;
    NSMutableArray *_scheduled, *_completed, *_drawables;
    MTLCommandBufferStatus _status;
    NSString *_label;
    dispatch_semaphore_t _done;
}
@end
@implementation BNMTLCommandBuffer
- (instancetype)initWithBNQueue:(BNMTLCommandQueue *)q {
    if ((self = [super init])) {
        _queue = q;
        _scheduled = [NSMutableArray array];
        _completed = [NSMutableArray array];
        _drawables = [NSMutableArray array];
        _done = dispatch_semaphore_create(0);
    }
    return self;
}
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { _label = [l copy]; }
- (id<MTLDevice>)device { return _queue->_device; }
- (id<MTLCommandQueue>)commandQueue { return _queue; }
- (MTLCommandBufferStatus)status {
    @synchronized(self) { return _status; }
}
- (NSError *)error { return nil; }
- (BOOL)retainedReferences { return YES; }
- (CFTimeInterval)kernelStartTime { return 0; }
- (CFTimeInterval)kernelEndTime { return 0; }
- (CFTimeInterval)GPUStartTime { return 0; }
- (CFTimeInterval)GPUEndTime { return 0; }
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)d {
    return [[BNMTLRenderEncoder alloc] initWithBNPass:d device:_queue->_device];
}
- (id<MTLBlitCommandEncoder>)blitCommandEncoder {
    BNMTLBlitEncoder *e = [BNMTLBlitEncoder new];
    e->_device = _queue->_device;
    return e;
}
- (id)computeCommandEncoder { return nil; }
- (void)presentDrawable:(id<MTLDrawable>)d {
    if (d) [_drawables addObject:d];
}
- (void)presentDrawable:(id<MTLDrawable>)d atTime:(CFTimeInterval)t { [self presentDrawable:d]; }
- (void)presentDrawable:(id<MTLDrawable>)d afterMinimumDuration:(CFTimeInterval)t { [self presentDrawable:d]; }
- (void)addScheduledHandler:(MTLCommandBufferHandler)b {
    if (b) [_scheduled addObject:[b copy]];
}
- (void)addCompletedHandler:(MTLCommandBufferHandler)b {
    if (b) [_completed addObject:[b copy]];
}
- (void)enqueue {
    @synchronized(self) {
        if (_status < MTLCommandBufferStatusEnqueued) _status = MTLCommandBufferStatusEnqueued;
    }
}
/* The work was done as it was encoded: present, then report. */
- (void)commit {
    @synchronized(self) { _status = MTLCommandBufferStatusCommitted; }
    for (id d in _drawables) [d present];
    NSArray *scheduled = [_scheduled copy], *completed = [_completed copy];
    dispatch_async(_queue->_completion, ^{
        @synchronized(self) { self->_status = MTLCommandBufferStatusScheduled; }
        for (MTLCommandBufferHandler h in scheduled) h(self);
        @synchronized(self) { self->_status = MTLCommandBufferStatusCompleted; }
        for (MTLCommandBufferHandler h in completed) h(self);
        dispatch_semaphore_signal(self->_done);
    });
}
- (void)waitUntilScheduled { [self waitUntilCompleted]; }
- (void)waitUntilCompleted {
    if (self.status < MTLCommandBufferStatusCommitted) return;
    dispatch_semaphore_wait(_done, DISPATCH_TIME_FOREVER);
    dispatch_semaphore_signal(_done);
}
- (void)pushDebugGroup:(NSString *)s {}
- (void)popDebugGroup {}
- (void)encodeSignalEvent:(id)e value:(uint64_t)v {}
- (void)encodeWaitForEvent:(id)e value:(uint64_t)v {}
@end

@implementation BNMTLCommandQueue
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { _label = [l copy]; }
- (id<MTLDevice>)device { return _device; }
- (id<MTLCommandBuffer>)commandBuffer { return [[BNMTLCommandBuffer alloc] initWithBNQueue:self]; }
- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences { return [self commandBuffer]; }
- (id<MTLCommandBuffer>)commandBufferWithDescriptor:(id)d { return [self commandBuffer]; }
- (void)insertDebugCaptureBoundary {}
@end

/* ---- drawables ---- */

@interface BNMTLDrawable : NSObject <MTLDrawable> {
@public
    BNMTLTexture *_texture;
    __weak id _layer;
    NSUInteger _id;
    CFTimeInterval _presented;
    NSMutableArray *_handlers;
}
@end
@implementation BNMTLDrawable
- (id<MTLTexture>)texture { return _texture; }
- (id)layer { return _layer; }
- (NSUInteger)drawableID { return _id; }
- (CFTimeInterval)presentedTime { return _presented; }
- (void)addPresentedHandler:(void (^)(id<MTLDrawable>))b {
    if (!_handlers) _handlers = [NSMutableArray array];
    if (b) [_handlers addObject:[b copy]];
}
/* The layer shows the pixels (QuartzCore turns them into its contents). */
- (void)present {
    id layer = _layer;
    struct bn_mtl_texture *t = &_texture->_t;
    if (layer && [layer respondsToSelector:@selector(_bn_presentPixels:width:height:bytesPerRow:format:)])
        ((void (*)(id, SEL, const void *, NSUInteger, NSUInteger, NSUInteger, int))objc_msgSend)(
            layer, @selector(_bn_presentPixels:width:height:bytesPerRow:format:), t->data, (NSUInteger)t->width,
            (NSUInteger)t->height, (NSUInteger)t->bytes_per_row, t->format);
    _presented = CFAbsoluteTimeGetCurrent();
    for (void (^h)(id) in _handlers) h(self);
}
- (void)presentAtTime:(CFTimeInterval)t { [self present]; }
- (void)presentAfterMinimumDuration:(CFTimeInterval)t { [self present]; }
@end

/* Called by CAMetalLayer -nextDrawable (QuartzCore does not link Metal;
 * it finds this through the runtime). */
@interface BNMTLDrawable (BNLayer)
+ (id)_bn_drawableForLayer:(id)layer device:(id)device format:(NSUInteger)format width:(NSUInteger)width
                    height:(NSUInteger)height;
@end
static id bn_metal_new_drawable(id layer, id device, NSUInteger format, NSUInteger width, NSUInteger height);
@implementation BNMTLDrawable (BNLayer)
+ (id)_bn_drawableForLayer:(id)layer device:(id)device format:(NSUInteger)format width:(NSUInteger)width
                    height:(NSUInteger)height {
    return bn_metal_new_drawable(layer, device ?: MTLCreateSystemDefaultDevice(), format, width, height);
}
@end
static id bn_metal_new_drawable(id layer, id device, NSUInteger format, NSUInteger width, NSUInteger height) {
    static NSUInteger next = 1;
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:(MTLPixelFormat)format
                                                                                 width:width ? width : 1
                                                                                height:height ? height : 1
                                                                             mipmapped:NO];
    d.usage = MTLTextureUsageRenderTarget;
    BNMTLDrawable *dr = [BNMTLDrawable new];
    dr->_texture = [[BNMTLTexture alloc] initWithBNDescriptor:d device:device];
    dr->_texture->_framebufferOnly = YES;
    dr->_layer = layer;
    dr->_id = next++;
    return dr;
}

/* ---- the device ---- */

@interface BNMTLDevice : NSObject <MTLDevice>
@end
@implementation BNMTLDevice {
    NSMutableDictionary<NSString *, BNMTLLibrary *> *_libraries;
}
- (instancetype)init {
    if ((self = [super init])) _libraries = [NSMutableDictionary dictionary];
    return self;
}
- (NSString *)name { return @"bitten Software Renderer"; }
- (uint64_t)registryID { return 1; }
- (BOOL)hasUnifiedMemory { return YES; }
- (BOOL)isLowPower { return NO; }
- (BOOL)isHeadless { return NO; }
- (BOOL)isRemovable { return NO; }
- (BOOL)lowPower { return NO; }
- (BOOL)headless { return NO; }
- (BOOL)removable { return NO; }
- (NSUInteger)location { return 0; }
- (NSUInteger)locationNumber { return 0; }
- (uint64_t)peerGroupID { return 0; }
- (uint64_t)recommendedMaxWorkingSetSize { return 1ULL << 30; }
- (NSUInteger)maxBufferLength { return 1UL << 30; }
- (NSUInteger)maxThreadgroupMemoryLength { return 32768; }
- (MTLSize)maxThreadsPerThreadgroup { return MTLSizeMake(1024, 1024, 1024); }
- (NSUInteger)currentAllocatedSize { return 0; }
- (BOOL)supportsFamily:(MTLGPUFamily)f { return f == MTLGPUFamilyMac1 || f == MTLGPUFamilyMac2 || f == MTLGPUFamilyCommon1 ||
                                                f == MTLGPUFamilyCommon2 || f == MTLGPUFamilyCommon3; }
- (BOOL)supportsFeatureSet:(NSUInteger)f { return YES; }
- (BOOL)supportsTextureSampleCount:(NSUInteger)c { return c == 1; }
- (BOOL)areRasterOrderGroupsSupported { return NO; }
- (BOOL)isDepth24Stencil8PixelFormatSupported { return NO; }
- (BOOL)supportsShaderBarycentricCoordinates { return NO; }
- (BOOL)areProgrammableSamplePositionsSupported { return NO; }
- (NSUInteger)argumentBuffersSupport { return 0; }
- (NSUInteger)readWriteTextureSupport { return 0; }
- (NSUInteger)minimumLinearTextureAlignmentForPixelFormat:(MTLPixelFormat)f { return 16; }
- (NSUInteger)minimumTextureBufferAlignmentForPixelFormat:(MTLPixelFormat)f { return 16; }

- (id<MTLCommandQueue>)newCommandQueue {
    BNMTLCommandQueue *q = [BNMTLCommandQueue new];
    q->_device = self;
    q->_completion = dispatch_queue_create("bitten.metal.completion", DISPATCH_QUEUE_SERIAL);
    return q;
}
- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)n { return [self newCommandQueue]; }
- (id<MTLCommandQueue>)newCommandQueueWithDescriptor:(id)d { return [self newCommandQueue]; }
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)n options:(MTLResourceOptions)o {
    BNMTLBuffer *b = [BNMTLBuffer new];
    b->_device = self;
    b->_length = n;
    b->_bytes = calloc(n ? n : 1, 1);
    return b;
}
- (id<MTLBuffer>)newBufferWithBytes:(const void *)p length:(NSUInteger)n options:(MTLResourceOptions)o {
    BNMTLBuffer *b = (BNMTLBuffer *)[self newBufferWithLength:n options:o];
    if (p && n) memcpy(b->_bytes, p, n);
    return b;
}
- (id<MTLBuffer>)newBufferWithBytesNoCopy:(void *)p length:(NSUInteger)n options:(MTLResourceOptions)o
                              deallocator:(void (^)(void *, NSUInteger))d {
    BNMTLBuffer *b = [BNMTLBuffer new];
    b->_device = self;
    b->_length = n;
    b->_bytes = p;
    if (d) b->_deallocator = [d copy];
    else b->_deallocator = ^(void *x, NSUInteger y) {};
    return b;
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d {
    return [[BNMTLTexture alloc] initWithBNDescriptor:d device:self];
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d iosurface:(id)s plane:(NSUInteger)p {
    return [self newTextureWithDescriptor:d];
}
- (id<MTLSamplerState>)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)d {
    BNMTLSampler *s = [BNMTLSampler new];
    s->_device = self;
    s->_label = d.label;
    uint64_t v = 0x49;                                         /* clamp to edge on s, t, r */
    if (d.magFilter == MTLSamplerMinMagFilterLinear) v |= 1 << 9;
    if (d.minFilter == MTLSamplerMinMagFilterLinear) v |= 1 << 11;
    if (!d.normalizedCoordinates) v |= 1 << 15;
    s->_state[0] = v;
    return s;
}
- (id)newDepthStencilStateWithDescriptor:(id)d { return [NSObject new]; }
- (id)newFence { return [NSObject new]; }
- (id)newEvent { return [NSObject new]; }
- (id)newSharedEvent { return [NSObject new]; }

- (id<MTLLibrary>)_bn_libraryWithData:(NSData *)data error:(NSError **)error {
    TRACE("library from %lu bytes\n", (unsigned long)data.length);
    if (data.length < 4 || memcmp(data.bytes, "MTLB", 4)) {
        if (error) *error = mtl_error(@"not a Metal library");
        return nil;
    }
    char why[512] = "";
    struct bn_metal_lib *l = bitten_metal_open(data.bytes, data.length, why, sizeof why);
    if (!l) {
        TRACE("library failed: %s\n", why);
        if (error) *error = mtl_error([NSString stringWithFormat:@"cannot compile the Metal library: %s", why]);
        return nil;
    }
    BNMTLLibrary *lib = [BNMTLLibrary new];
    lib->_lib = l;
    lib->_device = self;
    [lib _bn_readManifest:bitten_metal_manifest(l)];
    return lib;
}
- (id<MTLLibrary>)newLibraryWithData:(id)data error:(NSError **)error {
    /* NSData; a dispatch_data_t is bridged to it on Apple's systems */
    NSData *d = [data isKindOfClass:[NSData class]] ? data : nil;
    return [self _bn_libraryWithData:d error:error];
}
- (id<MTLLibrary>)newLibraryWithFile:(NSString *)path error:(NSError **)error {
    TRACE("newLibraryWithFile %s\n", path.UTF8String);
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) {
        if (error) *error = mtl_error([@"cannot read " stringByAppendingString:path ?: @""]);
        return nil;
    }
    return [self _bn_libraryWithData:d error:error];
}
- (id<MTLLibrary>)newLibraryWithURL:(NSURL *)url error:(NSError **)error { return [self newLibraryWithFile:url.path error:error]; }
- (id<MTLLibrary>)newDefaultLibraryWithBundle:(NSBundle *)bundle error:(NSError **)error {
    TRACE("newDefaultLibraryWithBundle %s\n", bundle.bundlePath.UTF8String);
    NSString *p = [bundle pathForResource:@"default" ofType:@"metallib"];
    if (!p) {
        if (error) *error = mtl_error(@"no default.metallib in the bundle");
        return nil;
    }
    return [self newLibraryWithFile:p error:error];
}
- (id<MTLLibrary>)newDefaultLibrary { return [self newDefaultLibraryWithBundle:[NSBundle mainBundle] error:NULL]; }
- (id<MTLLibrary>)newLibraryWithSource:(NSString *)source options:(id)options error:(NSError **)error {
    if (error) *error = mtl_error(@"compiling Metal source is not supported");
    return nil;
}

- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d error:(NSError **)error {
    TRACE("pipeline %s + %s\n", [(BNMTLFunction *)d.vertexFunction name].UTF8String, [(BNMTLFunction *)d.fragmentFunction name].UTF8String);
    BNMTLFunction *vf = (BNMTLFunction *)d.vertexFunction, *ff = (BNMTLFunction *)d.fragmentFunction;
    if (![vf isKindOfClass:[BNMTLFunction class]]) {
        if (error) *error = mtl_error(@"no vertex function");
        return nil;
    }
    BNMTLPipeline *p = [BNMTLPipeline new];
    p->_device = self;
    p->_label = d.label;
    p->_vertex = vf;
    p->_fragment = [ff isKindOfClass:[BNMTLFunction class]] ? ff : nil;
    MTLRenderPipelineColorAttachmentDescriptor *c = d.colorAttachments[0];
    p->_blend = c.blendingEnabled;
    p->_srcRGB = c.sourceRGBBlendFactor;
    p->_dstRGB = c.destinationRGBBlendFactor;
    p->_srcA = c.sourceAlphaBlendFactor;
    p->_dstA = c.destinationAlphaBlendFactor;
    p->_opRGB = c.rgbBlendOperation;
    p->_opA = c.alphaBlendOperation;
    p->_mask = c.writeMask;
    /* fragment inputs to vertex outputs, by name */
    for (int i = 0; i < 16; i++) p->_map[i] = -1;
    for (int i = 0; p->_fragment && i < p->_fragment->_nargs && i < 16; i++) {
        Arg *a = &p->_fragment->_args[i];
        if (a->kind != A_INPUT) continue;
        for (int o = 0; o < vf->_nouts; o++)
            if (!strcmp(vf->_outs[o].name, a->input)) p->_map[i] = o;
    }
    return p;
}
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d
                           completionHandler:(void (^)(id<MTLRenderPipelineState>, NSError *))h {
    NSError *e = nil;
    id p = [self newRenderPipelineStateWithDescriptor:d error:&e];
    h(p, e);
}
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d options:(NSUInteger)o
                                                        reflection:(id *)r error:(NSError **)error {
    if (r) *r = nil;
    return [self newRenderPipelineStateWithDescriptor:d error:error];
}
@end

id<MTLDevice> MTLCreateSystemDefaultDevice(void) {
    TRACE("MTLCreateSystemDefaultDevice\n");
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared_device = [BNMTLDevice new]; });
    return shared_device;
}
NSArray<id<MTLDevice>> *MTLCopyAllDevices(void) { return @[ MTLCreateSystemDefaultDevice() ]; }
