/* bitten SDK: CGColorSpace, CGColor, CGGradient. */
#ifndef BITTEN_CGCOLOR_H
#define BITTEN_CGCOLOR_H
#include <CoreGraphics/CGBase.h>

CG_ASSUME_BEGIN
typedef struct CG_BRIDGED_TYPE(id) CGColorSpace *CGColorSpaceRef;
typedef struct CG_BRIDGED_TYPE(id) CGColor *CGColorRef;
typedef struct CG_BRIDGED_TYPE(id) CGGradient *CGGradientRef;

typedef CG_ENUM(int32_t, CGColorSpaceModel) {
    kCGColorSpaceModelUnknown = -1, kCGColorSpaceModelMonochrome, kCGColorSpaceModelRGB,
    kCGColorSpaceModelCMYK, kCGColorSpaceModelLab, kCGColorSpaceModelDeviceN, kCGColorSpaceModelIndexed,
    kCGColorSpaceModelPattern, kCGColorSpaceModelXYZ,
};
typedef CG_ENUM(int32_t, CGColorRenderingIntent) {
    kCGRenderingIntentDefault, kCGRenderingIntentAbsoluteColorimetric, kCGRenderingIntentRelativeColorimetric,
    kCGRenderingIntentPerceptual, kCGRenderingIntentSaturation,
};
typedef CG_OPTIONS(uint32_t, CGGradientDrawingOptions) {
    kCGGradientDrawsBeforeStartLocation = 1, kCGGradientDrawsAfterEndLocation = 2,
};

CG_EXTERN const CFStringRef kCGColorSpaceGenericGray, kCGColorSpaceGenericRGB, kCGColorSpaceGenericCMYK,
    kCGColorSpaceSRGB, kCGColorSpaceExtendedSRGB, kCGColorSpaceLinearSRGB, kCGColorSpaceExtendedLinearSRGB,
    kCGColorSpaceDisplayP3, kCGColorSpaceExtendedDisplayP3, kCGColorSpaceGenericGrayGamma2_2,
    kCGColorSpaceLinearGray, kCGColorSpaceExtendedGray, kCGColorSpaceExtendedLinearGray,
    kCGColorSpaceGenericRGBLinear;
CG_EXTERN const CFStringRef kCGColorWhite, kCGColorBlack, kCGColorClear;

CFTypeID CGColorSpaceGetTypeID(void);
CGColorSpaceRef _Nullable CGColorSpaceCreateDeviceRGB(void);
CGColorSpaceRef _Nullable CGColorSpaceCreateDeviceGray(void);
CGColorSpaceRef _Nullable CGColorSpaceCreateWithName(CFStringRef _Nullable name);
CGColorSpaceRef _Nullable CGColorSpaceRetain(CGColorSpaceRef _Nullable space);
void CGColorSpaceRelease(CGColorSpaceRef _Nullable space);
size_t CGColorSpaceGetNumberOfComponents(CGColorSpaceRef _Nullable space);
CGColorSpaceModel CGColorSpaceGetModel(CGColorSpaceRef _Nullable space);
CFStringRef _Nullable CGColorSpaceGetName(CGColorSpaceRef _Nullable space);
CFStringRef _Nullable CGColorSpaceCopyName(CGColorSpaceRef _Nullable space);
bool CGColorSpaceSupportsOutput(CGColorSpaceRef space);
bool CGColorSpaceIsWideGamutRGB(CGColorSpaceRef space);

CFTypeID CGColorGetTypeID(void);
CGColorRef _Nullable CGColorCreate(CGColorSpaceRef _Nullable space, const CGFloat *_Nullable components);
CGColorRef CGColorCreateGenericRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
CGColorRef CGColorCreateSRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
CGColorRef CGColorCreateGenericGray(CGFloat gray, CGFloat alpha);
CGColorRef CGColorCreateGenericGrayGamma2_2(CGFloat gray, CGFloat alpha);
CGColorRef _Nullable CGColorCreateCopy(CGColorRef _Nullable color);
CGColorRef _Nullable CGColorCreateCopyWithAlpha(CGColorRef _Nullable color, CGFloat alpha);
CGColorRef _Nullable CGColorCreateCopyByMatchingToColorSpace(CGColorSpaceRef _Nullable space,
    CGColorRenderingIntent intent, CGColorRef _Nullable color, CFDictionaryRef _Nullable options);
CGColorRef _Nullable CGColorGetConstantColor(CFStringRef _Nullable name);
CGColorRef _Nullable CGColorRetain(CGColorRef _Nullable color);
void CGColorRelease(CGColorRef _Nullable color);
bool CGColorEqualToColor(CGColorRef _Nullable a, CGColorRef _Nullable b);
size_t CGColorGetNumberOfComponents(CGColorRef _Nullable color);
const CGFloat *_Nullable CGColorGetComponents(CGColorRef _Nullable color);
CGFloat CGColorGetAlpha(CGColorRef _Nullable color);
CGColorSpaceRef _Nullable CGColorGetColorSpace(CGColorRef _Nullable color);

CFTypeID CGGradientGetTypeID(void);
CGGradientRef _Nullable CGGradientCreateWithColors(CGColorSpaceRef _Nullable space, CFArrayRef _Nullable colors,
    const CGFloat *_Nullable locations);
CGGradientRef _Nullable CGGradientCreateWithColorComponents(CGColorSpaceRef _Nullable space,
    const CGFloat *_Nullable components, const CGFloat *_Nullable locations, size_t count);
CGGradientRef _Nullable CGGradientRetain(CGGradientRef _Nullable gradient);
void CGGradientRelease(CGGradientRef _Nullable gradient);
CG_ASSUME_END
#endif
