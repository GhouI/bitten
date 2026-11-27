// The software Metal device: a library compiled from AIR (the test's own
// tests/metal/shaders, packed into a metallib next to this program), a
// pipeline, buffers, textures, a render pass that clears, instanced
// triangles with interpolated vertex outputs, a texture read in the
// fragment shader, alpha blending, and command buffer completion.
#import <Metal/Metal.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

typedef struct {
    float x, y, pad0, pad1;
    float r, g, b, a;
} Vertex;

static void pixel(id<MTLTexture> t, int x, int y, uint8_t out[4]) {
    [t getBytes:out bytesPerRow:4 * t.width fromRegion:MTLRegionMake2D(x, y, 1, 1) mipmapLevel:0];
}
static BOOL near(uint8_t a, int b) { return abs((int)a - b) <= 2; }

int main(int argc, char **argv) {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    CHECK(dev && dev.name.length && dev.hasUnifiedMemory);
    NSString *dir = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
    NSError *err = nil;
    id<MTLLibrary> lib = [dev newLibraryWithFile:[dir stringByAppendingPathComponent:@"render.metallib"] error:&err];
    if (!lib && [err.localizedDescription containsString:@"compiling the Metal library failed"]) {
        printf("render skipped (no clang for AIR): %s\n", err.localizedDescription.UTF8String);
        return 0;
    }
    CHECK(lib && !err);
    CHECK([lib.functionNames containsObject:@"tri_vertex"] && [lib.functionNames containsObject:@"tri_fragment"]);
    id<MTLFunction> vf = [lib newFunctionWithName:@"tri_vertex"], ff = [lib newFunctionWithName:@"tri_fragment"];
    CHECK(vf.functionType == MTLFunctionTypeVertex && ff.functionType == MTLFunctionTypeFragment);
    CHECK([lib newFunctionWithName:@"missing"] == nil);

    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = vf;
    pd.fragmentFunction = ff;
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    id<MTLRenderPipelineState> opaque = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
    CHECK(opaque && !err);
    pd.colorAttachments[0].blendingEnabled = YES;
    pd.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pd.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pd.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pd.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    id<MTLRenderPipelineState> blended = [dev newRenderPipelineStateWithDescriptor:pd error:&err];

    /* the target: 16x16, cleared to blue */
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                 width:16 height:16 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [dev newTextureWithDescriptor:td];
    CHECK(target.width == 16 && target.pixelFormat == MTLPixelFormatBGRA8Unorm);

    /* the fragment shader multiplies by a texture: white, except the
     * texel at (15, 10), which is black */
    MTLTextureDescriptor *wd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:16 height:16 mipmapped:NO];
    id<MTLTexture> mask = [dev newTextureWithDescriptor:wd];
    uint8_t white[16 * 16 * 4];
    memset(white, 255, sizeof white);
    memset(white + (10 * 16 + 15) * 4, 0, 3);
    [mask replaceRegion:MTLRegionMake2D(0, 0, 16, 16) mipmapLevel:0 withBytes:white bytesPerRow:16 * 4];

    /* a triangle covering the left half: red at the top left, green at the
     * bottom left, red at the top middle */
    Vertex tri[3] = {{-1, 1, 0, 0, 1, 0, 0, 1}, {-1, -1, 0, 0, 0, 1, 0, 1}, {0, 1, 0, 0, 1, 0, 0, 1}};
    id<MTLBuffer> vb = [dev newBufferWithBytes:tri length:sizeof tri options:MTLResourceStorageModeShared];
    CHECK(vb.length == sizeof tri && memcmp(vb.contents, tri, sizeof tri) == 0);

    id<MTLCommandQueue> q = [dev newCommandQueue];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = target;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1);
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:opaque];
    [enc setVertexBuffer:vb offset:0 atIndex:0];
    [enc setFragmentTexture:mask atIndex:0];
    /* two instances: the second moved right by half the target */
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:2];
    [enc endEncoding];
    __block int completed = 0;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> b) { completed++; }];
    [cb commit];
    [cb waitUntilCompleted];
    CHECK(completed == 1 && cb.status == MTLCommandBufferStatusCompleted);

    uint8_t p[4];
    pixel(target, 0, 0, p);                       /* top left: red (BGRA) */
    CHECK(p[2] > 230 && p[1] < 30 && near(p[0], 0) && near(p[3], 255));   /* a little green at the pixel centre */
    pixel(target, 0, 14, p);                      /* bottom left: mostly green */
    CHECK(p[1] > 180 && p[2] < 80);
    pixel(target, 1, 7, p);                       /* half way down: a mix */
    CHECK(p[1] > 80 && p[2] > 80 && p[0] < 10);
    pixel(target, 7, 12, p);                      /* below the diagonal: the clear colour */
    CHECK(near(p[0], 255) && near(p[1], 0) && near(p[2], 0));
    pixel(target, 4, 0, p);                       /* the second instance starts at x = 4 */
    CHECK(p[2] > 230 && near(p[0], 0));
    pixel(target, 15, 15, p);                     /* untouched: blue */
    CHECK(near(p[0], 255));

    /* blending: a half-transparent white triangle over the right half */
    Vertex over[3] = {{0, 1, 0, 0, 1, 1, 1, 0.5f}, {1, 1, 0, 0, 1, 1, 1, 0.5f}, {1, -1, 0, 0, 1, 1, 1, 0.5f}};
    id<MTLCommandBuffer> cb2 = [q commandBuffer];
    rp.colorAttachments[0].loadAction = MTLLoadActionLoad;
    enc = [cb2 renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:blended];
    [enc setVertexBytes:over length:sizeof over atIndex:0];
    [enc setFragmentTexture:mask atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];
    [cb2 commit];
    [cb2 waitUntilCompleted];
    pixel(target, 14, 1, p);                      /* blue blended with white: (127, 127, 255) */
    CHECK(near(p[0], 255) && near(p[1], 128) && near(p[2], 128));
    pixel(target, 15, 10, p);                     /* the black texel: black at half alpha over blue */
    CHECK(near(p[0], 128) && near(p[1], 0));

    /* samplers and blits */
    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
    sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
    CHECK([dev newSamplerStateWithDescriptor:sd] != nil);
    id<MTLTexture> copy = [dev newTextureWithDescriptor:td];
    id<MTLCommandBuffer> cb3 = [q commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb3 blitCommandEncoder];
    [blit copyFromTexture:target toTexture:copy];
    [blit endEncoding];
    [cb3 commit];
    [cb3 waitUntilCompleted];
    pixel(copy, 0, 0, p);
    CHECK(p[2] > 230);

    /* how long a window-sized pass takes: a clear and two blended
     * triangles over every pixel (reported, not checked) */
    MTLTextureDescriptor *bd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                 width:1024 height:640 mipmapped:NO];
    bd.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> big = [dev newTextureWithDescriptor:bd];
    Vertex full[6] = {{-1, 1, 0, 0, 1, 1, 1, 0.5f}, {1, 1, 0, 0, 1, 1, 1, 0.5f}, {1, -1, 0, 0, 1, 1, 1, 0.5f},
                      {-1, 1, 0, 0, 1, 1, 1, 0.5f}, {1, -1, 0, 0, 1, 1, 1, 0.5f}, {-1, -1, 0, 0, 1, 1, 1, 0.5f}};
    rp.colorAttachments[0].texture = big;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    NSTimeInterval t0 = [NSDate timeIntervalSinceReferenceDate];
    for (int i = 0; i < 5; i++) {
        id<MTLCommandBuffer> b = [q commandBuffer];
        enc = [b renderCommandEncoderWithDescriptor:rp];
        [enc setRenderPipelineState:blended];
        [enc setVertexBytes:full length:sizeof full atIndex:0];
        [enc setFragmentTexture:mask atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        [enc endEncoding];
        [b commit];
        [b waitUntilCompleted];
    }
    printf("render: a 1024x640 pass takes %.1f ms\n", ([NSDate timeIntervalSinceReferenceDate] - t0) * 1000 / 5);
    pixel(big, 512, 320, p);                      /* white at half alpha over blue */
    CHECK(near(p[0], 255) && near(p[1], 128) && near(p[2], 128));

    printf("render ok\n");
    return 0;
}
