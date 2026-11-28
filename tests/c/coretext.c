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
Ref CTFontCopyPostScriptName(Ref);
Ref CTFontDescriptorCreateWithAttributes(Ref);
Ref CTFontDescriptorCreateMatchingFontDescriptors(Ref, Ref);
extern Ref kCTFontFamilyNameAttribute, kCTFontTraitsAttribute, kCTFontSymbolicTrait, kCTFontSlantTrait;
extern Ref kCTFontStyleNameAttribute, kCTFontStyleNameKey;
Ref CTFontDescriptorCopyAttribute(Ref, Ref);
Ref CTFontCopyName(Ref, Ref);
Ref CTFontCopyTraits(Ref);
Ref CFDictionaryGetValue(Ref, Ref);
unsigned char CFNumberGetValue(Ref, long, void *);
Ref CTFontCollectionCreateWithFontDescriptors(Ref, Ref);
Ref CTFontCollectionCreateFromAvailableFonts(Ref);
Ref CTFontCollectionCreateMatchingFontDescriptors(Ref);
Ref CTFontManagerCopyAvailableFontFamilyNames(void);
Ref CTFontManagerCopyAvailablePostScriptNames(void);
Ref CTFontCreateWithFontDescriptor(Ref, CGFloat, const void *);
Ref CFArrayCreate(Ref, const void **, long, const void *);
extern const char kCFTypeArrayCallBacks[];
Ref CFNumberCreate(Ref, long, const void *);
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
    /* Apple's fonts report their own names, whatever stands in for them */
    CHECK(CFStringGetCString(CTFontCopyFamilyName(mono), family, sizeof family, 0x08000100) && !strcmp(family, "Menlo"));
    CHECK(CFStringGetCString(CTFontCopyPostScriptName(mono), family, sizeof family, 0x08000100) &&
          !strcmp(family, "Menlo-Regular"));
    CHECK(CFStringGetCString(CTFontCopyFamilyName(sans), family, sizeof family, 0x08000100) &&
          !strcmp(family, ".AppleSystemUIFont"));
    /* matching: an Apple family matches, under its name; a missing family does not */
    {
        const void *k[] = {kCTFontFamilyNameAttribute}, *v[] = {S("menlo")};
        Ref d = CTFontDescriptorCreateWithAttributes(CFDictionaryCreate(0, k, v, 1, kCFTypeDictionaryKeyCallBacks,
                                                                        kCFTypeDictionaryValueCallBacks));
        Ref m = CTFontDescriptorCreateMatchingFontDescriptors(d, 0);
        /* an Apple family gives all of its stand-in's faces, under Apple's
         * names (DejaVu Sans Mono: Book, Bold, Oblique, Bold Oblique) */
        CHECK(m && CFArrayGetCount(m) >= 4);
        int bolds = 0, bolditalics = 0;
        for (long i = 0; i < CFArrayGetCount(m); i++) {
            Ref font = CTFontCreateWithFontDescriptor(CFArrayGetValueAtIndex(m, i), 12, 0);
            char ps[64], fm[64];
            CHECK(CFStringGetCString(CTFontCopyPostScriptName(font), ps, sizeof ps, 0x08000100) && !memcmp(ps, "Menlo-", 6));
            CHECK(CFStringGetCString(CTFontCopyFamilyName(font), fm, sizeof fm, 0x08000100) && !strcmp(fm, "Menlo"));
            bolds += !strcmp(ps, "Menlo-Bold");
            /* the font says the same style as its descriptor, in Apple's words */
            char ds[64], fs[64];
            CHECK(CFStringGetCString(CTFontDescriptorCopyAttribute(CFArrayGetValueAtIndex(m, i), kCTFontStyleNameAttribute), ds,
                                     sizeof ds, 0x08000100));
            CHECK(CFStringGetCString(CTFontCopyName(font, kCTFontStyleNameKey), fs, sizeof fs, 0x08000100) && !strcmp(ds, fs));
            if (!strcmp(ps, "Menlo-Regular")) CHECK(!strcmp(fs, "Regular"));
            /* italics slant clockwise: a positive slant */
            double slant = 0;
            CHECK(CFNumberGetValue(CFDictionaryGetValue(CTFontCopyTraits(font), kCTFontSlantTrait), 13, &slant));
            CHECK((CTFontGetSymbolicTraits(font) & 1) ? slant > 0 : slant == 0);
            bolditalics += !strcmp(ps, "Menlo-BoldItalic");
        }
        CHECK(bolds == 1 && bolditalics == 1);
        v[0] = S("No Such Font Family");
        d = CTFontDescriptorCreateWithAttributes(CFDictionaryCreate(0, k, v, 1, kCFTypeDictionaryKeyCallBacks,
                                                                    kCFTypeDictionaryValueCallBacks));
        CHECK(CTFontDescriptorCreateMatchingFontDescriptors(d, 0) == 0);
        v[0] = S("DejaVu Sans");
        d = CTFontDescriptorCreateWithAttributes(CFDictionaryCreate(0, k, v, 1, kCFTypeDictionaryKeyCallBacks,
                                                                    kCFTypeDictionaryValueCallBacks));
        Ref all = CTFontDescriptorCreateMatchingFontDescriptors(d, 0);
        CHECK(all != 0);
        /* a family gives every face of it (DejaVu Sans: Book and Bold) */
        CHECK(CFArrayGetCount(all) >= 2);
        char fam[64];
        for (long i = 0; i < CFArrayGetCount(all); i++)
            CHECK(CFStringGetCString(CTFontCopyFamilyName(CTFontCreateWithFontDescriptor(CFArrayGetValueAtIndex(all, i), 12, 0)),
                                     fam, sizeof fam, 0x08000100) && !strcmp(fam, "DejaVu Sans"));
    }
    /* collections match the installed fonts: all of them when empty */
    {
        Ref every = CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionCreateFromAvailableFonts(0));
        Ref ps = CTFontManagerCopyAvailablePostScriptNames();
        CHECK(every && CFArrayGetCount(every) >= 4 && CFArrayGetCount(every) == CFArrayGetCount(ps));
        Ref empty = CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionCreateWithFontDescriptors(0, 0));
        CHECK(empty && CFArrayGetCount(empty) == CFArrayGetCount(every));
        /* narrowed by a trait: monospaced faces only */
        int mono = 1 << 10;
        Ref num = CFNumberCreate(0, 9 /* kCFNumberIntType */, &mono);
        const void *tk[] = {kCTFontSymbolicTrait}, *tv[] = {num};
        Ref traits = CFDictionaryCreate(0, tk, tv, 1, kCFTypeDictionaryKeyCallBacks, kCFTypeDictionaryValueCallBacks);
        const void *dk[] = {kCTFontTraitsAttribute}, *dv[] = {traits};
        Ref md = CTFontDescriptorCreateWithAttributes(CFDictionaryCreate(0, dk, dv, 1, kCFTypeDictionaryKeyCallBacks,
                                                                         kCFTypeDictionaryValueCallBacks));
        const void *one[] = {md};
        Ref monos = CTFontCollectionCreateMatchingFontDescriptors(
            CTFontCollectionCreateWithFontDescriptors(CFArrayCreate(0, one, 1, kCFTypeArrayCallBacks), 0));
        CHECK(monos && CFArrayGetCount(monos) >= 1 && CFArrayGetCount(monos) < CFArrayGetCount(every));
        for (long i = 0; i < CFArrayGetCount(monos); i++)
            CHECK(CTFontGetSymbolicTraits(CTFontCreateWithFontDescriptor(CFArrayGetValueAtIndex(monos, i), 12, 0)) & (1 << 10));
        /* a family that is not there: nothing */
        const void *fk[] = {kCTFontFamilyNameAttribute}, *fv[] = {S("No Such Family")};
        Ref nd = CTFontDescriptorCreateWithAttributes(CFDictionaryCreate(0, fk, fv, 1, kCFTypeDictionaryKeyCallBacks,
                                                                         kCFTypeDictionaryValueCallBacks));
        const void *none[] = {nd};
        CHECK(CTFontCollectionCreateMatchingFontDescriptors(
                  CTFontCollectionCreateWithFontDescriptors(CFArrayCreate(0, none, 1, kCFTypeArrayCallBacks), 0)) == 0);
        /* the family names, sorted and each once */
        Ref fams = CTFontManagerCopyAvailableFontFamilyNames();
        int dejavu = 0;
        for (long i = 0; i < CFArrayGetCount(fams); i++) {
            char f[96];
            CHECK(CFStringGetCString(CFArrayGetValueAtIndex(fams, i), f, sizeof f, 0x08000100));
            dejavu += !strcmp(f, "DejaVu Sans");
        }
        CHECK(dejavu == 1);
    }

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
