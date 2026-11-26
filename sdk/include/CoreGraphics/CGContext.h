/* bitten SDK: CGContext and bitmap contexts. */
#ifndef BITTEN_CGCONTEXT_H
#define BITTEN_CGCONTEXT_H
#include <CoreGraphics/CGImage.h>
#include <CoreGraphics/CGPath.h>

CG_ASSUME_BEGIN
typedef struct CG_BRIDGED_TYPE(id) CGContext *CGContextRef;
typedef struct CG_BRIDGED_TYPE(id) CGFont *CGFontRef;
typedef uint16_t CGGlyph;

typedef CG_ENUM(int32_t, CGPathDrawingMode) {
    kCGPathFill, kCGPathEOFill, kCGPathStroke, kCGPathFillStroke, kCGPathEOFillStroke,
};
typedef CG_ENUM(int32_t, CGTextDrawingMode) {
    kCGTextFill, kCGTextStroke, kCGTextFillStroke, kCGTextInvisible, kCGTextFillClip, kCGTextStrokeClip,
    kCGTextFillStrokeClip, kCGTextClip,
};
typedef CG_ENUM(int32_t, CGInterpolationQuality) {
    kCGInterpolationDefault = 0, kCGInterpolationNone = 1, kCGInterpolationLow = 2,
    kCGInterpolationMedium = 4, kCGInterpolationHigh = 3,
};
typedef CG_ENUM(int32_t, CGBlendMode) {
    kCGBlendModeNormal, kCGBlendModeMultiply, kCGBlendModeScreen, kCGBlendModeOverlay, kCGBlendModeDarken,
    kCGBlendModeLighten, kCGBlendModeColorDodge, kCGBlendModeColorBurn, kCGBlendModeSoftLight,
    kCGBlendModeHardLight, kCGBlendModeDifference, kCGBlendModeExclusion, kCGBlendModeHue,
    kCGBlendModeSaturation, kCGBlendModeColor, kCGBlendModeLuminosity, kCGBlendModeClear, kCGBlendModeCopy,
    kCGBlendModeSourceIn, kCGBlendModeSourceOut, kCGBlendModeSourceAtop, kCGBlendModeDestinationOver,
    kCGBlendModeDestinationIn, kCGBlendModeDestinationOut, kCGBlendModeDestinationAtop, kCGBlendModeXOR,
    kCGBlendModePlusDarker, kCGBlendModePlusLighter,
};
typedef void (*CGBitmapContextReleaseDataCallback)(void *_Nullable releaseInfo, void *_Nullable data);

CFTypeID CGContextGetTypeID(void);
CGContextRef _Nullable CGContextRetain(CGContextRef _Nullable c);
void CGContextRelease(CGContextRef _Nullable c);
void CGContextFlush(CGContextRef _Nullable c);
void CGContextSynchronize(CGContextRef _Nullable c);

void CGContextSaveGState(CGContextRef _Nullable c);
void CGContextRestoreGState(CGContextRef _Nullable c);
void CGContextScaleCTM(CGContextRef _Nullable c, CGFloat sx, CGFloat sy);
void CGContextTranslateCTM(CGContextRef _Nullable c, CGFloat tx, CGFloat ty);
void CGContextRotateCTM(CGContextRef _Nullable c, CGFloat angle);
void CGContextConcatCTM(CGContextRef _Nullable c, CGAffineTransform transform);
CGAffineTransform CGContextGetCTM(CGContextRef _Nullable c);
CGAffineTransform CGContextGetUserSpaceToDeviceSpaceTransform(CGContextRef _Nullable c);

void CGContextSetLineWidth(CGContextRef _Nullable c, CGFloat width);
void CGContextSetLineCap(CGContextRef _Nullable c, CGLineCap cap);
void CGContextSetLineJoin(CGContextRef _Nullable c, CGLineJoin join);
void CGContextSetMiterLimit(CGContextRef _Nullable c, CGFloat limit);
void CGContextSetLineDash(CGContextRef _Nullable c, CGFloat phase, const CGFloat *_Nullable lengths, size_t count);
void CGContextSetFlatness(CGContextRef _Nullable c, CGFloat flatness);
void CGContextSetAlpha(CGContextRef _Nullable c, CGFloat alpha);
void CGContextSetBlendMode(CGContextRef _Nullable c, CGBlendMode mode);
void CGContextSetShouldAntialias(CGContextRef _Nullable c, bool shouldAntialias);
void CGContextSetAllowsAntialiasing(CGContextRef _Nullable c, bool allowsAntialiasing);
void CGContextSetInterpolationQuality(CGContextRef _Nullable c, CGInterpolationQuality quality);
CGInterpolationQuality CGContextGetInterpolationQuality(CGContextRef _Nullable c);
void CGContextSetRenderingIntent(CGContextRef _Nullable c, CGColorRenderingIntent intent);
void CGContextSetShadow(CGContextRef _Nullable c, CGSize offset, CGFloat blur);
void CGContextSetShadowWithColor(CGContextRef _Nullable c, CGSize offset, CGFloat blur, CGColorRef _Nullable color);

void CGContextSetFillColorWithColor(CGContextRef _Nullable c, CGColorRef _Nullable color);
void CGContextSetStrokeColorWithColor(CGContextRef _Nullable c, CGColorRef _Nullable color);
void CGContextSetFillColorSpace(CGContextRef _Nullable c, CGColorSpaceRef _Nullable space);
void CGContextSetStrokeColorSpace(CGContextRef _Nullable c, CGColorSpaceRef _Nullable space);
void CGContextSetFillColor(CGContextRef _Nullable c, const CGFloat *_Nullable components);
void CGContextSetStrokeColor(CGContextRef _Nullable c, const CGFloat *_Nullable components);
void CGContextSetGrayFillColor(CGContextRef _Nullable c, CGFloat gray, CGFloat alpha);
void CGContextSetGrayStrokeColor(CGContextRef _Nullable c, CGFloat gray, CGFloat alpha);
void CGContextSetRGBFillColor(CGContextRef _Nullable c, CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
void CGContextSetRGBStrokeColor(CGContextRef _Nullable c, CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
void CGContextSetCMYKFillColor(CGContextRef _Nullable c, CGFloat cyan, CGFloat magenta, CGFloat yellow, CGFloat black, CGFloat alpha);
void CGContextSetCMYKStrokeColor(CGContextRef _Nullable c, CGFloat cyan, CGFloat magenta, CGFloat yellow, CGFloat black, CGFloat alpha);

void CGContextBeginPath(CGContextRef _Nullable c);
void CGContextMoveToPoint(CGContextRef _Nullable c, CGFloat x, CGFloat y);
void CGContextAddLineToPoint(CGContextRef _Nullable c, CGFloat x, CGFloat y);
void CGContextAddCurveToPoint(CGContextRef _Nullable c, CGFloat cp1x, CGFloat cp1y, CGFloat cp2x, CGFloat cp2y, CGFloat x, CGFloat y);
void CGContextAddQuadCurveToPoint(CGContextRef _Nullable c, CGFloat cpx, CGFloat cpy, CGFloat x, CGFloat y);
void CGContextClosePath(CGContextRef _Nullable c);
void CGContextAddRect(CGContextRef _Nullable c, CGRect rect);
void CGContextAddRects(CGContextRef _Nullable c, const CGRect *_Nullable rects, size_t count);
void CGContextAddLines(CGContextRef _Nullable c, const CGPoint *_Nullable points, size_t count);
void CGContextAddEllipseInRect(CGContextRef _Nullable c, CGRect rect);
void CGContextAddArc(CGContextRef _Nullable c, CGFloat x, CGFloat y, CGFloat radius, CGFloat startAngle, CGFloat endAngle, int clockwise);
void CGContextAddArcToPoint(CGContextRef _Nullable c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat radius);
void CGContextAddPath(CGContextRef _Nullable c, CGPathRef _Nullable path);
void CGContextReplacePathWithStrokedPath(CGContextRef _Nullable c);
bool CGContextIsPathEmpty(CGContextRef _Nullable c);
CGPoint CGContextGetPathCurrentPoint(CGContextRef _Nullable c);
CGRect CGContextGetPathBoundingBox(CGContextRef _Nullable c);
CGPathRef _Nullable CGContextCopyPath(CGContextRef _Nullable c);
bool CGContextPathContainsPoint(CGContextRef _Nullable c, CGPoint point, CGPathDrawingMode mode);

void CGContextDrawPath(CGContextRef _Nullable c, CGPathDrawingMode mode);
void CGContextFillPath(CGContextRef _Nullable c);
void CGContextEOFillPath(CGContextRef _Nullable c);
void CGContextStrokePath(CGContextRef _Nullable c);
void CGContextFillRect(CGContextRef _Nullable c, CGRect rect);
void CGContextFillRects(CGContextRef _Nullable c, const CGRect *_Nullable rects, size_t count);
void CGContextStrokeRect(CGContextRef _Nullable c, CGRect rect);
void CGContextStrokeRectWithWidth(CGContextRef _Nullable c, CGRect rect, CGFloat width);
void CGContextClearRect(CGContextRef _Nullable c, CGRect rect);
void CGContextFillEllipseInRect(CGContextRef _Nullable c, CGRect rect);
void CGContextStrokeEllipseInRect(CGContextRef _Nullable c, CGRect rect);
void CGContextStrokeLineSegments(CGContextRef _Nullable c, const CGPoint *_Nullable points, size_t count);

void CGContextClip(CGContextRef _Nullable c);
void CGContextEOClip(CGContextRef _Nullable c);
void CGContextClipToRect(CGContextRef _Nullable c, CGRect rect);
void CGContextClipToRects(CGContextRef _Nullable c, const CGRect *rects, size_t count);
void CGContextClipToMask(CGContextRef _Nullable c, CGRect rect, CGImageRef _Nullable mask);
CGRect CGContextGetClipBoundingBox(CGContextRef _Nullable c);

void CGContextDrawImage(CGContextRef _Nullable c, CGRect rect, CGImageRef _Nullable image);
void CGContextDrawTiledImage(CGContextRef _Nullable c, CGRect rect, CGImageRef _Nullable image);
void CGContextDrawLinearGradient(CGContextRef _Nullable c, CGGradientRef _Nullable gradient, CGPoint startPoint,
    CGPoint endPoint, CGGradientDrawingOptions options);
void CGContextDrawRadialGradient(CGContextRef _Nullable c, CGGradientRef _Nullable gradient, CGPoint startCenter,
    CGFloat startRadius, CGPoint endCenter, CGFloat endRadius, CGGradientDrawingOptions options);
void CGContextBeginTransparencyLayer(CGContextRef _Nullable c, CFDictionaryRef _Nullable auxiliaryInfo);
void CGContextBeginTransparencyLayerWithRect(CGContextRef _Nullable c, CGRect rect, CFDictionaryRef _Nullable auxInfo);
void CGContextEndTransparencyLayer(CGContextRef _Nullable c);

CGPoint CGContextConvertPointToDeviceSpace(CGContextRef _Nullable c, CGPoint point);
CGPoint CGContextConvertPointToUserSpace(CGContextRef _Nullable c, CGPoint point);
CGSize CGContextConvertSizeToDeviceSpace(CGContextRef _Nullable c, CGSize size);
CGSize CGContextConvertSizeToUserSpace(CGContextRef _Nullable c, CGSize size);
CGRect CGContextConvertRectToDeviceSpace(CGContextRef _Nullable c, CGRect rect);
CGRect CGContextConvertRectToUserSpace(CGContextRef _Nullable c, CGRect rect);

void CGContextSetCharacterSpacing(CGContextRef _Nullable c, CGFloat spacing);
void CGContextSetTextPosition(CGContextRef _Nullable c, CGFloat x, CGFloat y);
CGPoint CGContextGetTextPosition(CGContextRef _Nullable c);
void CGContextSetTextMatrix(CGContextRef _Nullable c, CGAffineTransform t);
CGAffineTransform CGContextGetTextMatrix(CGContextRef _Nullable c);
void CGContextSetTextDrawingMode(CGContextRef _Nullable c, CGTextDrawingMode mode);
void CGContextSetFont(CGContextRef _Nullable c, CGFontRef _Nullable font);
void CGContextSetFontSize(CGContextRef _Nullable c, CGFloat size);
void CGContextSetShouldSmoothFonts(CGContextRef _Nullable c, bool shouldSmoothFonts);
void CGContextSetAllowsFontSmoothing(CGContextRef _Nullable c, bool allowsFontSmoothing);
void CGContextSetShouldSubpixelPositionFonts(CGContextRef _Nullable c, bool shouldSubpixelPositionFonts);
void CGContextSetAllowsFontSubpixelPositioning(CGContextRef _Nullable c, bool allowsFontSubpixelPositioning);
void CGContextSetShouldSubpixelQuantizeFonts(CGContextRef _Nullable c, bool shouldSubpixelQuantizeFonts);
void CGContextSetAllowsFontSubpixelQuantization(CGContextRef _Nullable c, bool allowsFontSubpixelQuantization);

CGContextRef _Nullable CGBitmapContextCreate(void *_Nullable data, size_t width, size_t height, size_t bitsPerComponent,
    size_t bytesPerRow, CGColorSpaceRef _Nullable space, uint32_t bitmapInfo);
CGContextRef _Nullable CGBitmapContextCreateWithData(void *_Nullable data, size_t width, size_t height,
    size_t bitsPerComponent, size_t bytesPerRow, CGColorSpaceRef _Nullable space, uint32_t bitmapInfo,
    CGBitmapContextReleaseDataCallback _Nullable releaseCallback, void *_Nullable releaseInfo);
void *_Nullable CGBitmapContextGetData(CGContextRef _Nullable context);
size_t CGBitmapContextGetWidth(CGContextRef _Nullable context);
size_t CGBitmapContextGetHeight(CGContextRef _Nullable context);
size_t CGBitmapContextGetBitsPerComponent(CGContextRef _Nullable context);
size_t CGBitmapContextGetBitsPerPixel(CGContextRef _Nullable context);
size_t CGBitmapContextGetBytesPerRow(CGContextRef _Nullable context);
CGColorSpaceRef _Nullable CGBitmapContextGetColorSpace(CGContextRef _Nullable context);
CGImageAlphaInfo CGBitmapContextGetAlphaInfo(CGContextRef _Nullable context);
CGBitmapInfo CGBitmapContextGetBitmapInfo(CGContextRef _Nullable context);
CGImageRef _Nullable CGBitmapContextCreateImage(CGContextRef _Nullable context);
CG_ASSUME_END
#endif
