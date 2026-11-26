// Metal without a GPU: no device; descriptors keep their values and copy.
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

int main(void) {
    @autoreleasepool {
        CHECK(MTLCreateSystemDefaultDevice() == nil);
        CHECK(MTLCopyAllDevices().count == 0);

        MTLTextureDescriptor *t = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                     width:256 height:64 mipmapped:YES];
        CHECK(t.width == 256 && t.height == 64 && t.depth == 1 && t.mipmapLevelCount == 9);
        CHECK(t.textureType == MTLTextureType2D && t.pixelFormat == MTLPixelFormatBGRA8Unorm);
        t.usage = MTLTextureUsageRenderTarget;
        MTLTextureDescriptor *tc = [t copy];
        CHECK(tc != t && tc.usage == MTLTextureUsageRenderTarget && tc.width == 256);

        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        CHECK(pass.colorAttachments[0] == pass.colorAttachments[0]);
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0.5, 0, 1);
        CHECK(pass.colorAttachments[0].storeAction == MTLStoreActionStore);
        CHECK(pass.depthAttachment.clearDepth == 1);
        MTLRenderPassDescriptor *pc = [pass copy];
        CHECK(pc.colorAttachments[0] != pass.colorAttachments[0]);
        CHECK(pc.colorAttachments[0].loadAction == MTLLoadActionClear && pc.colorAttachments[0].clearColor.green == 0.5);
        pass.depthAttachment = nil;
        CHECK(pass.depthAttachment != nil);

        MTLRenderPipelineDescriptor *pipe = [MTLRenderPipelineDescriptor new];
        pipe.label = @"quad";
        pipe.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pipe.colorAttachments[0].blendingEnabled = YES;
        CHECK(pipe.colorAttachments[0].writeMask == MTLColorWriteMaskAll);
        CHECK(pipe.rasterSampleCount == 1 && pipe.isRasterizationEnabled);
        MTLRenderPipelineDescriptor *pp = [pipe copy];
        CHECK([pp.label isEqualToString:@"quad"] && pp.colorAttachments[0].isBlendingEnabled);
        [pipe reset];
        CHECK(pipe.label == nil && pipe.colorAttachments[0].pixelFormat == MTLPixelFormatInvalid);

        MTLFunctionConstantValues *k = [MTLFunctionConstantValues new];
        BOOL yes = YES;
        float f[3] = {1, 2, 3};
        [k setConstantValue:&yes type:MTLDataTypeBool atIndex:0];
        [k setConstantValues:f type:MTLDataTypeFloat withRange:NSMakeRange(1, 3)];
        [k setConstantValue:&yes type:MTLDataTypeBool withName:@"useAlpha"];
        CHECK([k copy] != nil);
        [k reset];
    }
    printf("metal ok\n");
    return 0;
}
