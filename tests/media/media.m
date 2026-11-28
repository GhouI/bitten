// CoreImage (monochrome, invert, compositing, cropping, rendering),
// AVFAudio (formats, PCM buffers, an engine pulling a source node) and
// ScreenCaptureKit (empty content, declined capture).
#import <CoreImage/CoreImage.h>
#import <AVFAudio/AVFAudio.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#import <objc/message.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static CGImageRef solid(int w, int h, uint8_t r, uint8_t g, uint8_t b) {
    uint8_t *px = malloc((size_t)w * h * 4);
    for (int i = 0; i < w * h; i++) { px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = 255; }
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, w * 4, rgb, kCGImageAlphaPremultipliedLast);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CGColorSpaceRelease(rgb);
    free(px);
    return img;
}

static void pixel(CGImageRef img, int x, int y, uint8_t out[4]) {
    size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    uint8_t *px = calloc(w * h, 4);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, w * 4, rgb, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    memcpy(out, px + ((h - 1 - y) * w + x) * 4, 4);
    CGContextRelease(ctx);
    CGColorSpaceRelease(rgb);
    free(px);
}

int main(void) {
    @autoreleasepool {
        /* CoreImage */
        CGImageRef red = solid(8, 8, 255, 0, 0);
        CIImage *img = [[CIImage alloc] initWithCGImage:red];
        CHECK(CGRectEqualToRect(img.extent, CGRectMake(0, 0, 8, 8)));
        CIFilter *mono = [CIFilter filterWithName:@"CIColorMonochrome"];
        CHECK(mono && [CIFilter filterWithName:@"CINoSuchFilter"] == nil);
        [mono setValue:img forKey:kCIInputImageKey];
        [mono setValue:[CIColor colorWithRed:1 green:1 blue:1] forKey:kCIInputColorKey];
        [mono setValue:@1.0 forKey:kCIInputIntensityKey];
        CIContext *ctx = [CIContext contextWithOptions:@{kCIContextCacheIntermediates: @NO}];
        CGImageRef out = [ctx createCGImage:mono.outputImage fromRect:mono.outputImage.extent];
        CHECK(out && CGImageGetWidth(out) == 8);
        uint8_t p[4];
        pixel(out, 3, 3, p);
        CHECK(p[0] == p[1] && p[1] == p[2] && p[0] > 45 && p[0] < 65 && p[3] == 255);   /* 0.2125 of white */
        CGImageRelease(out);
        CIImage *inv = [img imageByApplyingFilter:@"CIColorInvert"];
        out = [ctx createCGImage:inv fromRect:CGRectMake(2, 2, 4, 4)];
        CHECK(CGImageGetWidth(out) == 4);
        pixel(out, 0, 0, p);
        CHECK(p[0] == 0 && p[1] == 255 && p[2] == 255);
        CGImageRelease(out);
        CIImage *blue = [[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:1]] imageByCroppingToRect:CGRectMake(0, 0, 8, 8)];
        CIImage *over = [[CIImage imageWithColor:[CIColor colorWithRed:0 green:1 blue:0 alpha:0.5]] imageByCompositingOverImage:blue];
        out = [ctx createCGImage:over fromRect:CGRectMake(0, 0, 8, 8)];
        pixel(out, 1, 1, p);
        CHECK(p[1] > 120 && p[1] < 135 && p[2] > 120 && p[2] < 135 && p[3] == 255);
        CGImageRelease(out);
        CHECK(CGRectIsInfinite([CIImage imageWithColor:[CIColor redColor]].extent));
        CGImageRelease(red);

        /* AVFAudio */
        AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
        CHECK(fmt.isStandard && fmt.channelCount == 2 && fmt.sampleRate == 44100 && !fmt.isInterleaved);
        AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fmt frameCapacity:512];
        CHECK(buf.frameCapacity == 512 && buf.floatChannelData && buf.int16ChannelData == NULL);
        buf.frameLength = 100;
        buf.floatChannelData[1][99] = 0.5f;
        CHECK(buf.audioBufferList->mNumberBuffers == 2 && buf.audioBufferList->mBuffers[1].mDataByteSize == 400);
        CHECK(((float *)buf.audioBufferList->mBuffers[1].mData)[99] == 0.5f);
        __block long frames = 0;
        __block double phase = 0;
        AVAudioSourceNode *src = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(
            BOOL *silence, const AudioTimeStamp *ts, AVAudioFrameCount n, AudioBufferList *list) {
            for (UInt32 b = 0; b < list->mNumberBuffers; b++) {
                float *d = list->mBuffers[b].mData;
                for (AVAudioFrameCount i = 0; i < n; i++) d[i] = (float)sin(phase + i * 0.01);
            }
            phase += n * 0.01;
            frames += n;
            return 0;
        }];
        AVAudioEngine *engine = [AVAudioEngine new];
        [engine attachNode:src];
        [engine connect:src to:engine.mainMixerNode format:fmt];
        [engine connect:engine.mainMixerNode to:engine.outputNode format:nil];
        CHECK(src.engine == engine && [engine.attachedNodes containsObject:src]);
        NSError *err = nil;
        CHECK([engine startAndReturnError:&err] && engine.isRunning);
        [NSThread sleepForTimeInterval:0.3];
        [engine stop];
        CHECK(!engine.isRunning);
        CHECK(frames > 48000 * 0.15 && frames < 48000 * 0.6);   /* about real time at 48 kHz */

        /* ScreenCaptureKit */
        dispatch_semaphore_t got = dispatch_semaphore_create(0);
        __block SCShareableContent *content = nil;
        [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES
                                                     completionHandler:^(SCShareableContent *c, NSError *e) {
            content = c;
            dispatch_semaphore_signal(got);
        }];
        CHECK(dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        CHECK(content && content.windows.count == 0 && content.displays.count == 0);
        __block NSError *capture = nil;
        [SCScreenshotManager captureImageWithFilter:[[SCContentFilter alloc] initWithDesktopIndependentWindow:[SCWindow new]]
                                      configuration:[SCStreamConfiguration new]
                                  completionHandler:^(CGImageRef image, NSError *e) {
            capture = e;
            dispatch_semaphore_signal(got);
        }];
        CHECK(dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        CHECK(capture.code == SCStreamErrorUserDeclined && [capture.domain isEqualToString:SCStreamErrorDomain]);
        __block SCShareableContent *mine = nil;
        [SCShareableContent getCurrentProcessShareableContentWithCompletionHandler:^(SCShareableContent *c, NSError *e) {
            mine = c;
            dispatch_semaphore_signal(got);
        }];
        CHECK(dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        CHECK(mine && mine.windows.count == 0);
        SCStreamConfiguration *cfg = [SCStreamConfiguration new];
        cfg.captureResolution = 1;
        CHECK(cfg.captureResolution == 1);

        /* CoreImage from a Metal texture (Metal loaded, not linked) */
        CHECK(dlopen("/System/Library/Frameworks/Metal.framework/Versions/A/Metal", RTLD_NOW) != NULL);
        id (*makeDevice)(void) = (id (*)(void))dlsym(RTLD_DEFAULT, "MTLCreateSystemDefaultDevice");
        id device = makeDevice ? makeDevice() : nil;
        CHECK(device != nil);
        id desc = ((id (*)(id, SEL, NSUInteger, NSUInteger, NSUInteger, BOOL))objc_msgSend)(
            objc_getClass("MTLTextureDescriptor"),
            sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"), 80, 2, 1, NO);
        id tex = ((id (*)(id, SEL, id))objc_msgSend)(device, sel_registerName("newTextureWithDescriptor:"), desc);
        CHECK(tex != nil);
        const uint8_t bgra[8] = {255, 0, 0, 255, 0, 0, 255, 255};   /* blue, red */
        typedef struct { NSUInteger x, y, z, w, h, d; } Region;
        ((void (*)(id, SEL, Region, NSUInteger, const void *, NSUInteger))objc_msgSend)(
            tex, sel_registerName("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"), (Region){0, 0, 0, 2, 1, 1}, 0, bgra, 8);
        CIImage *fromTexture = [[CIImage alloc] initWithMTLTexture:tex options:nil];
        CHECK(CGRectEqualToRect(fromTexture.extent, CGRectMake(0, 0, 2, 1)));
        CGImageRef texImage = [[CIContext contextWithMTLDevice:device] createCGImage:fromTexture fromRect:fromTexture.extent];
        uint8_t first[4], second[4];
        pixel(texImage, 0, 0, first);
        pixel(texImage, 1, 0, second);
        CHECK(first[2] > 200 && first[0] < 50 && second[0] > 200 && second[2] < 50);
        CGImageRelease(texImage);
    }
    printf("media ok\n");
    return 0;
}
