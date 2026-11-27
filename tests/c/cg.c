/* CoreGraphics: draw into bitmap contexts and check the pixels. */
#include "darwin.h"

typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;
typedef void *CGContextRef;
typedef const void *CGRef;

static CGRect R(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { CGRect r = {{x, y}, {w, h}}; return r; }
static CGPoint P(CGFloat x, CGFloat y) { CGPoint p = {x, y}; return p; }

CGRef CGColorSpaceCreateDeviceRGB(void), CGColorSpaceCreateDeviceGray(void);
void CGColorSpaceRelease(CGRef);
CGContextRef CGBitmapContextCreate(void *, size_t, size_t, size_t, size_t, CGRef, uint32_t);
unsigned char *CGBitmapContextGetData(CGContextRef);
size_t CGBitmapContextGetBytesPerRow(CGContextRef);
CGRef CGBitmapContextCreateImage(CGContextRef);
void CGContextRelease(CGContextRef);
void CGContextSetRGBFillColor(CGContextRef, CGFloat, CGFloat, CGFloat, CGFloat);
void CGContextSetRGBStrokeColor(CGContextRef, CGFloat, CGFloat, CGFloat, CGFloat);
void CGContextSetGrayFillColor(CGContextRef, CGFloat, CGFloat);
void CGContextFillRect(CGContextRef, CGRect), CGContextClipToRect(CGContextRef, CGRect);
void CGContextFillEllipseInRect(CGContextRef, CGRect);
void CGContextSaveGState(CGContextRef), CGContextRestoreGState(CGContextRef);
void CGContextMoveToPoint(CGContextRef, CGFloat, CGFloat), CGContextAddLineToPoint(CGContextRef, CGFloat, CGFloat);
void CGContextSetLineWidth(CGContextRef, CGFloat), CGContextStrokePath(CGContextRef), CGContextEOFillPath(CGContextRef);
void CGContextAddRect(CGContextRef, CGRect);
void CGContextSetLineDash(CGContextRef, CGFloat, const CGFloat *, size_t);
void CGContextTranslateCTM(CGContextRef, CGFloat, CGFloat), CGContextScaleCTM(CGContextRef, CGFloat, CGFloat);
CGAffineTransform CGContextGetCTM(CGContextRef);
CGPoint CGContextConvertPointToDeviceSpace(CGContextRef, CGPoint);
void CGContextSetAlpha(CGContextRef, CGFloat);
void CGContextBeginTransparencyLayer(CGContextRef, CGRef), CGContextEndTransparencyLayer(CGContextRef);
void CGContextBeginTransparencyLayerWithRect(CGContextRef, CGRect, CGRef);
void CGContextSetInterpolationQuality(CGContextRef, int);
void CGContextDrawImage(CGContextRef, CGRect, CGRef);
void CGContextClearRect(CGContextRef, CGRect);
CGRect CGContextGetClipBoundingBox(CGContextRef);
CGRef CGColorCreateGenericRGB(CGFloat, CGFloat, CGFloat, CGFloat);
CGRef CGArrayFromTwo(void);
CGRef CFArrayCreate(CGRef, const void **, long, const void *);
extern const char kCFTypeArrayCallBacks[];
CGRef CGGradientCreateWithColors(CGRef, CGRef, const CGFloat *);
void CGContextDrawLinearGradient(CGContextRef, CGRef, CGPoint, CGPoint, uint32_t);
CGRef CFDataCreate(CGRef, const unsigned char *, long);
CGRef CGDataProviderCreateWithCFData(CGRef);
CGRef CGImageCreate(size_t, size_t, size_t, size_t, size_t, CGRef, uint32_t, CGRef, const CGFloat *, int, int);
size_t CGImageGetWidth(CGRef);
void *CGPathCreateMutable(void);
void CGPathAddEllipseInRect(void *, const CGAffineTransform *, CGRect);
void CGPathAddArc(void *, const CGAffineTransform *, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, int);
CGRect CGPathGetPathBoundingBox(CGRef);
int CGPathContainsPoint(CGRef, const CGAffineTransform *, CGPoint, int);
void CFRelease(CGRef);

enum { PREMUL_LAST = 1, PREMUL_FIRST = 2, ORDER32_LITTLE = 0x2000 };

static CGContextRef rgba(size_t w, size_t h) {
    CGRef s = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, s, PREMUL_LAST);
    CGColorSpaceRelease(s);
    return c;
}

/* The pixel whose center is at device point (x + 0.5, y + 0.5), y up. */
static unsigned char *px(CGContextRef c, size_t h, int x, int y) {
    return CGBitmapContextGetData(c) + (h - 1 - (size_t)y) * CGBitmapContextGetBytesPerRow(c) + (size_t)x * 4;
}

static int near(int a, int b, int tol) { return a - b <= tol && b - a <= tol; }

int main(void) {
    CGContextRef c = rgba(100, 100);
    CHECK(c != NULL);
    /* fill */
    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextFillRect(c, R(10, 10, 20, 20));
    unsigned char *p = px(c, 100, 15, 15);
    CHECK(p[0] == 255 && p[1] == 0 && p[2] == 0 && p[3] == 255);
    CHECK(px(c, 100, 35, 15)[3] == 0 && px(c, 100, 15, 35)[3] == 0);
    CHECK(px(c, 100, 10, 10)[3] == 255 && px(c, 100, 29, 29)[3] == 255 && px(c, 100, 30, 29)[3] == 0);
    /* antialiased edge: half a pixel */
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextFillRect(c, R(50.5, 50, 10, 10));
    CHECK(near(px(c, 100, 50, 55)[3], 128, 3) && px(c, 100, 51, 55)[3] == 255);
    /* translucent paint over red: premultiplied blend */
    CGContextSetRGBFillColor(c, 0, 0, 1, 0.5);
    CGContextFillRect(c, R(10, 10, 5, 5));
    p = px(c, 100, 12, 12);
    CHECK(near(p[0], 128, 2) && near(p[2], 128, 2) && p[3] == 255);
    /* clip */
    CGContextClearRect(c, R(0, 0, 100, 100));
    CHECK(px(c, 100, 15, 15)[3] == 0);
    CGContextSaveGState(c);
    CGContextClipToRect(c, R(20, 20, 10, 10));
    CGRect cb = CGContextGetClipBoundingBox(c);
    CHECK(cb.origin.x == 20 && cb.origin.y == 20 && cb.size.width == 10 && cb.size.height == 10);
    CGContextSetRGBFillColor(c, 0, 1, 0, 1);
    CGContextFillRect(c, R(0, 0, 100, 100));
    CGContextRestoreGState(c);
    CHECK(px(c, 100, 25, 25)[1] == 255 && px(c, 100, 15, 25)[3] == 0 && px(c, 100, 35, 25)[3] == 0);
    CGContextRelease(c);

    /* stroke, dashes, even-odd, ellipse */
    c = rgba(100, 100);
    CGContextSetRGBStrokeColor(c, 0, 0, 0, 1);
    CGContextSetLineWidth(c, 4);
    CGContextMoveToPoint(c, 10, 50);
    CGContextAddLineToPoint(c, 90, 50);
    CGContextStrokePath(c);
    CHECK(px(c, 100, 50, 49)[3] == 255 && px(c, 100, 50, 51)[3] == 255 && px(c, 100, 50, 55)[3] == 0);
    CHECK(px(c, 100, 5, 50)[3] == 0);                      /* butt cap */
    CGFloat dash[] = {10, 10};
    CGContextSetLineDash(c, 0, dash, 2);
    CGContextMoveToPoint(c, 0, 80);
    CGContextAddLineToPoint(c, 100, 80);
    CGContextStrokePath(c);
    CHECK(px(c, 100, 5, 80)[3] == 255 && px(c, 100, 15, 80)[3] == 0 && px(c, 100, 25, 80)[3] == 255);
    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextAddRect(c, R(0, 0, 40, 40));
    CGContextAddRect(c, R(10, 10, 20, 20));
    CGContextEOFillPath(c);
    CHECK(px(c, 100, 5, 5)[0] == 255 && px(c, 100, 20, 20)[3] == 0);
    CGContextFillEllipseInRect(c, R(60, 0, 40, 40));
    CHECK(px(c, 100, 80, 20)[3] == 255 && px(c, 100, 61, 1)[3] == 0);
    CGContextRelease(c);

    /* CTM */
    c = rgba(50, 50);
    CGContextTranslateCTM(c, 10, 5);
    CGContextScaleCTM(c, 2, 2);
    CGAffineTransform t = CGContextGetCTM(c);
    CHECK(t.a == 2 && t.d == 2 && t.tx == 10 && t.ty == 5);
    CGPoint d = CGContextConvertPointToDeviceSpace(c, P(1, 1));
    CHECK(d.x == 12 && d.y == 7);
    CGContextSetRGBFillColor(c, 0, 1, 0, 1);
    CGContextFillRect(c, R(0, 0, 5, 5));                    /* device 10..20, 5..15 */
    CHECK(px(c, 50, 15, 10)[1] == 255 && px(c, 50, 25, 10)[3] == 0);
    CGContextRelease(c);

    /* gradient */
    c = rgba(100, 10);
    CGRef black = CGColorCreateGenericRGB(0, 0, 0, 1), white = CGColorCreateGenericRGB(1, 1, 1, 1);
    const void *colors[] = {black, white};
    CGRef array = CFArrayCreate(NULL, colors, 2, kCFTypeArrayCallBacks);
    CGRef g = CGGradientCreateWithColors(NULL, array, NULL);
    CGContextDrawLinearGradient(c, g, P(0, 0), P(100, 0), 0);
    CHECK(px(c, 10, 0, 5)[0] < 10 && px(c, 10, 99, 5)[0] > 245 && near(px(c, 10, 50, 5)[0], 128, 4));
    CGContextRelease(c);

    /* images: a 2x2 image drawn at 20x20 without interpolation */
    unsigned char pixels[16] = {255, 0, 0, 255,   0, 255, 0, 255,
                                0, 0, 255, 255,   255, 255, 255, 255};
    CGRef data = CFDataCreate(NULL, pixels, 16);
    CGRef provider = CGDataProviderCreateWithCFData(data);
    CGRef rgb = CGColorSpaceCreateDeviceRGB();
    CGRef img = CGImageCreate(2, 2, 8, 32, 8, rgb, PREMUL_LAST, provider, NULL, 0, 0);
    CHECK(img != NULL && CGImageGetWidth(img) == 2);
    c = rgba(20, 20);
    CGContextSetInterpolationQuality(c, 1);
    CGContextDrawImage(c, R(0, 0, 20, 20), img);
    CHECK(px(c, 20, 2, 17)[0] == 255 && px(c, 20, 17, 17)[1] == 255);   /* top row: red, green */
    CHECK(px(c, 20, 2, 2)[2] == 255 && px(c, 20, 17, 2)[0] == 255 && px(c, 20, 17, 2)[2] == 255);
    /* round trip through CGBitmapContextCreateImage */
    CGRef copy = CGBitmapContextCreateImage(c);
    CGContextRef c2 = rgba(20, 20);
    CGContextDrawImage(c2, R(0, 0, 20, 20), copy);
    CHECK(px(c2, 20, 2, 17)[0] == 255 && px(c2, 20, 2, 17)[1] == 0);
    CGContextRelease(c2);
    CGContextRelease(c);

    /* transparency layer at half alpha */
    c = rgba(10, 10);
    CGContextSetAlpha(c, 0.5);
    CGContextBeginTransparencyLayer(c, NULL);
    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextFillRect(c, R(0, 0, 10, 10));
    CGContextFillRect(c, R(0, 0, 5, 5));                    /* overlap stays one layer */
    CGContextEndTransparencyLayer(c);
    CHECK(near(px(c, 10, 2, 2)[3], 128, 2) && near(px(c, 10, 7, 7)[3], 128, 2));
    CGContextRelease(c);

    /* a layer with a rectangle holds only that rectangle (in device space,
     * here moved by the CTM): drawing outside it is discarded */
    c = rgba(20, 20);
    CGContextTranslateCTM(c, 2, 3);
    CGContextBeginTransparencyLayerWithRect(c, R(1, 1, 5, 5), NULL);   /* device x 3..8, y 4..9 */
    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextFillRect(c, R(-2, -3, 20, 20));
    CGContextEndTransparencyLayer(c);
    CHECK(px(c, 20, 5, 6)[0] == 255 && px(c, 20, 5, 6)[3] == 255);
    CHECK(px(c, 20, 3, 4)[3] == 255 && px(c, 20, 7, 8)[3] == 255);
    CHECK(px(c, 20, 2, 6)[3] == 0 && px(c, 20, 8, 6)[3] == 0 && px(c, 20, 5, 3)[3] == 0 && px(c, 20, 5, 9)[3] == 0);
    CHECK(px(c, 20, 15, 15)[3] == 0);
    CGContextRelease(c);
    /* a plain layer under a clip composites inside the clip only */
    c = rgba(20, 20);
    CGContextClipToRect(c, R(10, 10, 5, 5));
    CGContextBeginTransparencyLayer(c, NULL);
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextFillRect(c, R(0, 0, 20, 20));
    CGContextEndTransparencyLayer(c);
    CHECK(px(c, 20, 12, 12)[2] == 255 && px(c, 20, 12, 12)[3] == 255 && px(c, 20, 5, 5)[3] == 0 && px(c, 20, 16, 16)[3] == 0);
    CGContextRelease(c);
    /* drawing that pops the layer's own state (so its clip grows back)
     * still stays inside the layer's pixels */
    c = rgba(20, 20);
    CGContextSaveGState(c);
    CGContextBeginTransparencyLayerWithRect(c, R(0, 0, 4, 4), NULL);
    CGContextRestoreGState(c);
    CGContextSetRGBFillColor(c, 0, 1, 0, 1);
    CGContextFillRect(c, R(0, 0, 20, 20));
    CGContextEndTransparencyLayer(c);
    CHECK(px(c, 20, 1, 1)[1] == 255 && px(c, 20, 10, 10)[3] == 0);
    CGContextRelease(c);

    /* BGRA little-endian and gray contexts */
    CGContextRef b = CGBitmapContextCreate(NULL, 4, 4, 8, 16, rgb, PREMUL_FIRST | ORDER32_LITTLE);
    CGContextSetRGBFillColor(b, 1, 0, 0, 1);
    CGContextFillRect(b, R(0, 0, 4, 4));
    unsigned char *q = CGBitmapContextGetData(b);
    CHECK(q[0] == 0 && q[1] == 0 && q[2] == 255 && q[3] == 255);
    CGContextRelease(b);
    CGRef gs = CGColorSpaceCreateDeviceGray();
    CGContextRef gc = CGBitmapContextCreate(NULL, 4, 4, 8, 4, gs, 0);
    CGContextSetGrayFillColor(gc, 0.5, 1);
    CGContextFillRect(gc, R(0, 0, 4, 4));
    CHECK(near(CGBitmapContextGetData(gc)[5], 128, 1));
    CGContextRelease(gc);

    /* paths */
    void *path = CGPathCreateMutable();
    CGPathAddEllipseInRect(path, NULL, R(0, 0, 10, 20));
    CGRect bb = CGPathGetPathBoundingBox(path);
    CHECK(near((int)(bb.size.width * 100), 1000, 2) && near((int)(bb.size.height * 100), 2000, 2));
    CHECK(CGPathContainsPoint(path, NULL, P(5, 10), 0) && !CGPathContainsPoint(path, NULL, P(0.5, 0.5), 0));
    CFRelease(path);
    puts("coregraphics ok");
    return 0;
}
