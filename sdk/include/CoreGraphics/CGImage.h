/* bitten SDK: CGDataProvider and CGImage. */
#ifndef BITTEN_CGIMAGE_H
#define BITTEN_CGIMAGE_H
#include <CoreGraphics/CGColorSpace.h>

CG_ASSUME_BEGIN
typedef struct CG_BRIDGED_TYPE(id) CGDataProvider *CGDataProviderRef;
typedef struct CG_BRIDGED_TYPE(id) CGImage *CGImageRef;

typedef CG_ENUM(uint32_t, CGImageAlphaInfo) {
    kCGImageAlphaNone, kCGImageAlphaPremultipliedLast, kCGImageAlphaPremultipliedFirst, kCGImageAlphaLast,
    kCGImageAlphaFirst, kCGImageAlphaNoneSkipLast, kCGImageAlphaNoneSkipFirst, kCGImageAlphaOnly,
};
typedef CG_OPTIONS(uint32_t, CGBitmapInfo) {
    kCGBitmapAlphaInfoMask = 0x1F, kCGBitmapFloatInfoMask = 0xF00, kCGBitmapFloatComponents = 1 << 8,
    kCGBitmapByteOrderMask = 0x7000, kCGBitmapByteOrderDefault = 0, kCGBitmapByteOrder16Little = 1 << 12,
    kCGBitmapByteOrder32Little = 2 << 12, kCGBitmapByteOrder16Big = 3 << 12, kCGBitmapByteOrder32Big = 4 << 12,
};
typedef void (*CGDataProviderReleaseDataCallback)(void *_Nullable info, const void *data, size_t size);

CFTypeID CGDataProviderGetTypeID(void);
CGDataProviderRef _Nullable CGDataProviderCreateWithCFData(CFDataRef _Nullable data);
CGDataProviderRef _Nullable CGDataProviderCreateWithData(void *_Nullable info, const void *_Nullable data,
    size_t size, CGDataProviderReleaseDataCallback _Nullable releaseData);
CFDataRef _Nullable CGDataProviderCopyData(CGDataProviderRef _Nullable provider);
CGDataProviderRef _Nullable CGDataProviderRetain(CGDataProviderRef _Nullable provider);
void CGDataProviderRelease(CGDataProviderRef _Nullable provider);

CFTypeID CGImageGetTypeID(void);
CGImageRef _Nullable CGImageCreate(size_t width, size_t height, size_t bitsPerComponent, size_t bitsPerPixel,
    size_t bytesPerRow, CGColorSpaceRef _Nullable space, CGBitmapInfo bitmapInfo, CGDataProviderRef _Nullable provider,
    const CGFloat *_Nullable decode, bool shouldInterpolate, CGColorRenderingIntent intent);
CGImageRef _Nullable CGImageMaskCreate(size_t width, size_t height, size_t bitsPerComponent, size_t bitsPerPixel,
    size_t bytesPerRow, CGDataProviderRef _Nullable provider, const CGFloat *_Nullable decode, bool shouldInterpolate);
CGImageRef _Nullable CGImageCreateWithImageInRect(CGImageRef _Nullable image, CGRect rect);
CGImageRef _Nullable CGImageCreateCopy(CGImageRef _Nullable image);
CGImageRef _Nullable CGImageCreateCopyWithColorSpace(CGImageRef _Nullable image, CGColorSpaceRef _Nullable space);
CGImageRef _Nullable CGImageRetain(CGImageRef _Nullable image);
void CGImageRelease(CGImageRef _Nullable image);
bool CGImageIsMask(CGImageRef _Nullable image);
size_t CGImageGetWidth(CGImageRef _Nullable image);
size_t CGImageGetHeight(CGImageRef _Nullable image);
size_t CGImageGetBitsPerComponent(CGImageRef _Nullable image);
size_t CGImageGetBitsPerPixel(CGImageRef _Nullable image);
size_t CGImageGetBytesPerRow(CGImageRef _Nullable image);
CGColorSpaceRef _Nullable CGImageGetColorSpace(CGImageRef _Nullable image);
CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef _Nullable image);
CGBitmapInfo CGImageGetBitmapInfo(CGImageRef _Nullable image);
CGDataProviderRef _Nullable CGImageGetDataProvider(CGImageRef _Nullable image);
bool CGImageGetShouldInterpolate(CGImageRef _Nullable image);
CG_ASSUME_END
#endif
