/* CoreText and CFAttributedString: fonts and their metrics, glyphs, lines,
 * runs, fallback, and text drawn into a bitmap. Needs open TrueType fonts
 * (DejaVu) installed, as the Docker image has. */
#include "darwin.h"

typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { long location, length; } CFRange;
typedef const void *Ref;
Ref CFStringCreateWithCString(Ref, const char *, unsigned int);
long CFStringGetLength(Ref);
unsigned char CFStringGetCString(Ref, char *, long, unsigned int);
unsigned char CFEqual(Ref, Ref);
void CFRelease(Ref);
Ref CFDictionaryCreate(Ref, const void **, const void **, long, const void *, const void *);
extern const char kCFTypeDictionaryKeyCallBacks[], kCFTypeDictionaryValueCallBacks[];
long CFArrayGetCount(Ref);
Ref CFArrayGetValueAtIndex(Ref, long);
Ref CFAttributedStringCreate(Ref, Ref, Ref);
void *CFAttributedStringCreateMutable(Ref, long);
void CFAttributedStringReplaceString(void *, CFRange, Ref);
void CFAttributedStringSetAttribute(void *, CFRange, Ref, Ref);
Ref CFAttributedStringGetAttribute(Ref, long, Ref, CFRange *);
Ref CFAttributedStringGetString(Ref);
long CFAttributedStringGetLength(Ref);
Ref CGColorSpaceCreateDeviceRGB(void);
Ref CGColorCreateGenericRGB(CGFloat, CGFloat, CGFloat, CGFloat);
void *CGBitmapContextCreate(void *, unsigned long, unsigned long, unsigned long, unsigned long, Ref, unsigned int);
unsigned char *CGBitmapContextGetData(void *);
unsigned long CGBitmapContextGetBytesPerRow(void *);
void CGContextSetTextPosition(void *, CGFloat, CGFloat);
Ref CTFontCreateWithName(Ref, CGFloat, const void *);
Ref CTFontCreateCopyWithSymbolicTraits(Ref, CGFloat, const void *, unsigned int, unsigned int);
unsigned int CTFontGetSymbolicTraits(Ref);
CGFloat CTFontGetSize(Ref), CTFontGetAscent(Ref), CTFontGetDescent(Ref);
unsigned CTFontGetUnitsPerEm(Ref);
Ref CTFontCopyFamilyName(Ref);
unsigned char CTFontGetGlyphsForCharacters(Ref, const unsigned short *, unsigned short *, long);
double CTFontGetAdvancesForGlyphs(Ref, unsigned int, const unsigned short *, CGSize *, long);
Ref CTFontCreatePathForGlyph(Ref, unsigned short, const void *);
CGRect CGPathGetPathBoundingBox(Ref);
Ref CTLineCreateWithAttributedString(Ref);
double CTLineGetTypographicBounds(Ref, CGFloat *, CGFloat *, CGFloat *);
Ref CTLineGetGlyphRuns(Ref);
long CTLineGetGlyphCount(Ref);
long CTRunGetGlyphCount(Ref);
CFRange CTRunGetStringRange(Ref);
void CTRunGetPositions(Ref, CFRange, CGPoint *);
long CTLineGetStringIndexForPosition(Ref, CGPoint);
void CTLineDraw(Ref, void *);
extern Ref kCTFontAttributeName, kCTForegroundColorAttributeName;

static Ref S(const char *s) { return CFStringCreateWithCString(0, s, 0x08000100); }

static Ref attributed(const char *text, Ref font, Ref color) {
    const void *k[] = {kCTFontAttributeName, kCTForegroundColorAttributeName}, *v[] = {font, color};
    Ref attrs = CFDictionaryCreate(0, k, v, color ? 2 : 1, kCFTypeDictionaryKeyCallBacks, kCFTypeDictionaryValueCallBacks);
    return CFAttributedStringCreate(0, S(text), attrs);
}

int main(void) {
    /* fonts: Apple names map to open families; sizes and metrics */
    Ref sans = CTFontCreateWithName(S(".AppleSystemUIFont"), 20, 0);
    CHECK(sans && CTFontGetSize(sans) == 20 && CTFontGetUnitsPerEm(sans) >= 1000);
    CHECK(CTFontGetAscent(sans) > 14 && CTFontGetAscent(sans) < 22 && CTFontGetDescent(sans) > 2);
    Ref mono = CTFontCreateWithName(S("Menlo"), 12, 0);
    CHECK(CTFontGetSymbolicTraits(mono) & (1 << 10));                 /* monospace */
    Ref bold = CTFontCreateCopyWithSymbolicTraits(sans, 0, 0, 1 << 1, 1 << 1);
    CHECK(bold && (CTFontGetSymbolicTraits(bold) & (1 << 1)) && CTFontGetSize(bold) == 20);
    char family[64];
    CHECK(CFStringGetCString(CTFontCopyFamilyName(sans), family, sizeof family, 0x08000100) && family[0]);

    /* glyphs and advances: 'W' is wider than 'i'; monospace is even */
    unsigned short chars[] = {'W', 'i'}, glyphs[2];
    CHECK(CTFontGetGlyphsForCharacters(sans, chars, glyphs, 2) && glyphs[0] && glyphs[1] && glyphs[0] != glyphs[1]);
    CGSize adv[2];
    double total = CTFontGetAdvancesForGlyphs(sans, 0, glyphs, adv, 2);
    CHECK(adv[0].width > adv[1].width && total == adv[0].width + adv[1].width);
    unsigned short mg[2];
    CTFontGetGlyphsForCharacters(mono, chars, mg, 2);
    CGSize madv[2];
    CTFontGetAdvancesForGlyphs(mono, 0, mg, madv, 2);
    CHECK(madv[0].width == madv[1].width);
    CGRect box = CGPathGetPathBoundingBox(CTFontCreatePathForGlyph(sans, glyphs[0], 0));
    CHECK(box.size.width > 10 && box.size.height > 10 && box.origin.y > -1);   /* 'W' sits on the baseline */

    /* lines and runs */
    Ref line = CTLineCreateWithAttributedString(attributed("Hello", sans, 0));
    CGFloat a, d, l;
    double w = CTLineGetTypographicBounds(line, &a, &d, &l);
    CHECK(w > 40 && w < 70 && a == CTFontGetAscent(sans) && CTLineGetGlyphCount(line) == 5);
    Ref runs = CTLineGetGlyphRuns(line);
    CHECK(CFArrayGetCount(runs) == 1 && CTRunGetGlyphCount(CFArrayGetValueAtIndex(runs, 0)) == 5);
    CGPoint pos[5];
    CTRunGetPositions(CFArrayGetValueAtIndex(runs, 0), (CFRange){0, 0}, pos);
    CHECK(pos[0].x == 0 && pos[1].x > 0 && pos[4].x > pos[3].x);
    CHECK(CTLineGetStringIndexForPosition(line, (CGPoint){0.5, 0}) == 0);
    CHECK(CTLineGetStringIndexForPosition(line, (CGPoint){w + 5, 0}) == 5);
    /* a character the font lacks goes to a fallback face: its own run */
    Ref mixed = CTLineCreateWithAttributedString(attributed("A\xe4\xbd\xa0", mono, 0));
    CHECK(CTLineGetGlyphCount(mixed) == 2);

    /* drawing: red "I" at (10, 10) in a 40x40 bitmap */
    void *c = CGBitmapContextCreate(0, 40, 40, 8, 0, CGColorSpaceCreateDeviceRGB(), 1);
    CGContextSetTextPosition(c, 10, 10);
    CTLineDraw(CTLineCreateWithAttributedString(attributed("I", sans, CGColorCreateGenericRGB(1, 0, 0, 1))), c);
    unsigned char *px = CGBitmapContextGetData(c);
    unsigned long bpr = CGBitmapContextGetBytesPerRow(c);
    int painted = 0, above = 0, below = 0, red = 1;
    for (int row = 0; row < 40; row++)
        for (int x = 0; x < 40; x++) {
            unsigned char *p = px + row * bpr + x * 4;
            if (p[3] > 128) {
                painted++;
                int y = 39 - row;                 /* y up */
                if (y > 10 + 16) above++;
                if (y < 9) below++;
                if (p[1] > 10 || p[2] > 10) red = 0;
            }
        }
    CHECK(painted > 20 && above == 0 && below == 0 && red);

    /* CFAttributedString: ranges and editing */
    void *m = CFAttributedStringCreateMutable(0, 0);
    CFAttributedStringReplaceString(m, (CFRange){0, 0}, S("abcdef"));
    CFAttributedStringSetAttribute(m, (CFRange){2, 2}, kCTFontAttributeName, mono);
    CFRange eff;
    CHECK(CFAttributedStringGetAttribute(m, 3, kCTFontAttributeName, &eff) == mono && eff.location == 2 && eff.length == 2);
    CHECK(CFAttributedStringGetAttribute(m, 0, kCTFontAttributeName, &eff) == 0 && eff.location == 0 && eff.length == 2);
    CFAttributedStringReplaceString(m, (CFRange){0, 1}, S("XY"));
    CHECK(CFAttributedStringGetLength(m) == 7 && CFEqual(CFAttributedStringGetString(m), S("XYbcdef")));
    CHECK(CFAttributedStringGetAttribute(m, 4, kCTFontAttributeName, &eff) == mono && eff.location == 3);
    puts("coretext ok");
    return 0;
}
