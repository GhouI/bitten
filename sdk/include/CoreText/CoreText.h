/* bitten SDK: CoreText (src/frameworks/coretext). Written from the public
 * documentation. Fonts are the open TrueType fonts installed on the host;
 * Apple's font names map to open families. */
#ifndef BITTEN_CORETEXT_H
#define BITTEN_CORETEXT_H
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>

CG_ASSUME_BEGIN
typedef const struct CF_BRIDGED(id) __CTFont *CTFontRef;
typedef const struct CF_BRIDGED(id) __CTFontDescriptor *CTFontDescriptorRef;
typedef const struct CF_BRIDGED(id) __CTFontCollection *CTFontCollectionRef;
typedef const struct CF_BRIDGED(id) __CTLine *CTLineRef;
typedef const struct CF_BRIDGED(id) __CTRun *CTRunRef;

typedef CG_OPTIONS(uint32_t, CTFontSymbolicTraits) {
    kCTFontTraitItalic = 1 << 0, kCTFontTraitBold = 1 << 1, kCTFontTraitExpanded = 1 << 5,
    kCTFontTraitCondensed = 1 << 6, kCTFontTraitMonoSpace = 1 << 10, kCTFontTraitVertical = 1 << 11,
    kCTFontTraitUIOptimized = 1 << 12, kCTFontTraitColorGlyphs = 1 << 13, kCTFontTraitComposite = 1 << 14,
};
typedef CG_ENUM(uint32_t, CTFontOrientation) {
    kCTFontOrientationDefault = 0, kCTFontOrientationHorizontal = 1, kCTFontOrientationVertical = 2,
};
typedef CG_ENUM(uint32_t, CTFontUIFontType) {
    kCTFontUIFontNone = (uint32_t)-1, kCTFontUIFontUser = 0, kCTFontUIFontUserFixedPitch = 1,
    kCTFontUIFontSystem = 2, kCTFontUIFontEmphasizedSystem = 3, kCTFontUIFontSmallSystem = 4,
    kCTFontUIFontLabel = 10, kCTFontUIFontMenuItem = 12, kCTFontUIFontToolTip = 25,
};
typedef CG_OPTIONS(CFOptionFlags, CTLineBoundsOptions) {
    kCTLineBoundsExcludeTypographicLeading = 1 << 0, kCTLineBoundsExcludeTypographicShifts = 1 << 1,
    kCTLineBoundsUseHangingPunctuation = 1 << 2, kCTLineBoundsUseGlyphPathBounds = 1 << 3,
    kCTLineBoundsUseOpticalBounds = 1 << 4, kCTLineBoundsIncludeLanguageExtents = 1 << 5,
};
typedef uint32_t CTFontTableTag;
typedef uint32_t CTFontTableOptions;
typedef uint32_t CTFontManagerScope;

extern const CFStringRef kCTFontAttributeName, kCTForegroundColorAttributeName,
    kCTForegroundColorFromContextAttributeName, kCTKernAttributeName, kCTParagraphStyleAttributeName,
    kCTUnderlineStyleAttributeName, kCTUnderlineColorAttributeName, kCTStrokeWidthAttributeName,
    kCTStrokeColorAttributeName, kCTLigatureAttributeName, kCTBaselineOffsetAttributeName;
extern const CFStringRef kCTFontNameAttribute, kCTFontDisplayNameAttribute, kCTFontFamilyNameAttribute,
    kCTFontStyleNameAttribute, kCTFontTraitsAttribute, kCTFontSizeAttribute, kCTFontMatrixAttribute,
    kCTFontURLAttribute, kCTFontCascadeListAttribute, kCTFontCharacterSetAttribute, kCTFontLanguagesAttribute,
    kCTFontFeatureSettingsAttribute, kCTFontFeaturesAttribute, kCTFontVariationAttribute,
    kCTFontOpticalSizeAttribute, kCTFontFixedAdvanceAttribute;
extern const CFStringRef kCTFontSymbolicTrait, kCTFontWeightTrait, kCTFontWidthTrait, kCTFontSlantTrait;
extern const CFStringRef kCTFontCopyrightNameKey, kCTFontFamilyNameKey, kCTFontSubFamilyNameKey,
    kCTFontStyleNameKey, kCTFontUniqueNameKey, kCTFontFullNameKey, kCTFontVersionNameKey,
    kCTFontPostScriptNameKey;
extern const CFStringRef kCTFontOpenTypeFeatureTag, kCTFontOpenTypeFeatureValue,
    kCTFontFeatureTypeIdentifierKey, kCTFontFeatureSelectorIdentifierKey;
extern const CFStringRef kCTFontVariationAxisIdentifierKey, kCTFontVariationAxisMinimumValueKey,
    kCTFontVariationAxisMaximumValueKey, kCTFontVariationAxisDefaultValueKey, kCTFontVariationAxisNameKey;

CFTypeID CTFontGetTypeID(void);
CTFontRef CTFontCreateWithName(CFStringRef _Nullable name, CGFloat size, const CGAffineTransform *_Nullable matrix);
CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef descriptor, CGFloat size, const CGAffineTransform *_Nullable matrix);
CTFontRef _Nullable CTFontCreateUIFontForLanguage(CTFontUIFontType uiType, CGFloat size, CFStringRef _Nullable language);
CTFontRef CTFontCreateCopyWithAttributes(CTFontRef font, CGFloat size, const CGAffineTransform *_Nullable matrix,
    CTFontDescriptorRef _Nullable attributes);
CTFontRef _Nullable CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size, const CGAffineTransform *_Nullable matrix,
    CTFontSymbolicTraits symTraitValue, CTFontSymbolicTraits symTraitMask);
CTFontRef CTFontCreateForString(CTFontRef currentFont, CFStringRef string, CFRange range);
CTFontDescriptorRef CTFontCopyFontDescriptor(CTFontRef font);
CFTypeRef _Nullable CTFontCopyAttribute(CTFontRef font, CFStringRef attribute);
CGFloat CTFontGetSize(CTFontRef font);
CGAffineTransform CTFontGetMatrix(CTFontRef font);
CTFontSymbolicTraits CTFontGetSymbolicTraits(CTFontRef font);
CFDictionaryRef CTFontCopyTraits(CTFontRef font);
CFStringRef CTFontCopyPostScriptName(CTFontRef font);
CFStringRef CTFontCopyFamilyName(CTFontRef font);
CFStringRef CTFontCopyFullName(CTFontRef font);
CFStringRef CTFontCopyDisplayName(CTFontRef font);
CFStringRef _Nullable CTFontCopyName(CTFontRef font, CFStringRef nameKey);
CGFloat CTFontGetAscent(CTFontRef font);
CGFloat CTFontGetDescent(CTFontRef font);
CGFloat CTFontGetLeading(CTFontRef font);
unsigned CTFontGetUnitsPerEm(CTFontRef font);
CFIndex CTFontGetGlyphCount(CTFontRef font);
CGRect CTFontGetBoundingBox(CTFontRef font);
CGFloat CTFontGetUnderlinePosition(CTFontRef font);
CGFloat CTFontGetUnderlineThickness(CTFontRef font);
CGFloat CTFontGetSlantAngle(CTFontRef font);
CGFloat CTFontGetCapHeight(CTFontRef font);
CGFloat CTFontGetXHeight(CTFontRef font);
bool CTFontGetGlyphsForCharacters(CTFontRef font, const UniChar characters[], CGGlyph glyphs[], CFIndex count);
CGRect CTFontGetBoundingRectsForGlyphs(CTFontRef font, CTFontOrientation orientation, const CGGlyph glyphs[],
    CGRect *_Nullable boundingRects, CFIndex count);
double CTFontGetAdvancesForGlyphs(CTFontRef font, CTFontOrientation orientation, const CGGlyph glyphs[],
    CGSize *_Nullable advances, CFIndex count);
CGPathRef _Nullable CTFontCreatePathForGlyph(CTFontRef font, CGGlyph glyph, const CGAffineTransform *_Nullable matrix);
void CTFontDrawGlyphs(CTFontRef font, const CGGlyph glyphs[], const CGPoint positions[], size_t count, CGContextRef context);
CFArrayRef CTFontCopyDefaultCascadeListForLanguages(CTFontRef font, CFArrayRef _Nullable languagePrefList);
CFDataRef _Nullable CTFontCopyTable(CTFontRef font, CTFontTableTag table, CTFontTableOptions options);
CFDictionaryRef _Nullable CTFontCopyVariation(CTFontRef font);
CFArrayRef _Nullable CTFontCopyVariationAxes(CTFontRef font);

CFTypeID CTFontDescriptorGetTypeID(void);
CTFontDescriptorRef CTFontDescriptorCreateWithAttributes(CFDictionaryRef attributes);
CTFontDescriptorRef CTFontDescriptorCreateWithNameAndSize(CFStringRef name, CGFloat size);
CTFontDescriptorRef CTFontDescriptorCreateCopyWithAttributes(CTFontDescriptorRef original, CFDictionaryRef attributes);
CFTypeRef _Nullable CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute);
CFDictionaryRef CTFontDescriptorCopyAttributes(CTFontDescriptorRef descriptor);
CFArrayRef _Nullable CTFontDescriptorCreateMatchingFontDescriptors(CTFontDescriptorRef descriptor, CFSetRef _Nullable mandatoryAttributes);
CTFontDescriptorRef _Nullable CTFontDescriptorCreateMatchingFontDescriptor(CTFontDescriptorRef descriptor, CFSetRef _Nullable mandatoryAttributes);

CFTypeID CTFontCollectionGetTypeID(void);
CTFontCollectionRef CTFontCollectionCreateWithFontDescriptors(CFArrayRef _Nullable queryDescriptors, CFDictionaryRef _Nullable options);
CFArrayRef _Nullable CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionRef collection);
CFArrayRef _Nullable CTFontManagerCreateFontDescriptorsFromURL(CFURLRef fileURL);
bool CTFontManagerRegisterFontsForURL(CFURLRef fontURL, CTFontManagerScope scope, CFErrorRef _Nullable *_Nullable error);

CFTypeID CTLineGetTypeID(void);
CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef attrString);
CFIndex CTLineGetGlyphCount(CTLineRef line);
CFArrayRef CTLineGetGlyphRuns(CTLineRef line);
CFRange CTLineGetStringRange(CTLineRef line);
double CTLineGetTypographicBounds(CTLineRef line, CGFloat *_Nullable ascent, CGFloat *_Nullable descent, CGFloat *_Nullable leading);
CGRect CTLineGetBoundsWithOptions(CTLineRef line, CTLineBoundsOptions options);
double CTLineGetTrailingWhitespaceWidth(CTLineRef line);
CGRect CTLineGetImageBounds(CTLineRef line, CGContextRef _Nullable context);
CFIndex CTLineGetStringIndexForPosition(CTLineRef line, CGPoint position);
CGFloat CTLineGetOffsetForStringIndex(CTLineRef line, CFIndex charIndex, CGFloat *_Nullable secondaryOffset);
void CTLineDraw(CTLineRef line, CGContextRef context);

CFTypeID CTRunGetTypeID(void);
CFIndex CTRunGetGlyphCount(CTRunRef run);
CFDictionaryRef CTRunGetAttributes(CTRunRef run);
uint32_t CTRunGetStatus(CTRunRef run);
const CGGlyph *_Nullable CTRunGetGlyphsPtr(CTRunRef run);
void CTRunGetGlyphs(CTRunRef run, CFRange range, CGGlyph buffer[]);
const CGPoint *_Nullable CTRunGetPositionsPtr(CTRunRef run);
void CTRunGetPositions(CTRunRef run, CFRange range, CGPoint buffer[]);
const CGSize *_Nullable CTRunGetAdvancesPtr(CTRunRef run);
void CTRunGetAdvances(CTRunRef run, CFRange range, CGSize buffer[]);
const CFIndex *_Nullable CTRunGetStringIndicesPtr(CTRunRef run);
void CTRunGetStringIndices(CTRunRef run, CFRange range, CFIndex buffer[]);
CFRange CTRunGetStringRange(CTRunRef run);
double CTRunGetTypographicBounds(CTRunRef run, CFRange range, CGFloat *_Nullable ascent, CGFloat *_Nullable descent,
    CGFloat *_Nullable leading);
void CTRunDraw(CTRunRef run, CGContextRef context, CFRange range);
CG_ASSUME_END
#endif
