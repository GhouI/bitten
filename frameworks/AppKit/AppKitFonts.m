/* NSFont and NSFontDescriptor are toll-free bridged to CoreText's CTFont
 * and CTFontDescriptor, as on macOS: a font is a CTFont object, so code
 * may pass one to CoreText (`font as CTFont`) or the other way. CT's
 * classes are re-parented under these when AppKit loads; the methods call
 * CoreText. NSFontManager keeps the font panel's API over them. */

#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <math.h>

extern Class class_setSuperclass(Class cls, Class super);

static CTFontRef CT(id f) { return (__bridge CTFontRef)f; }
static CTFontDescriptorRef CTD(id d) { return (__bridge CTFontDescriptorRef)d; }

__attribute__((constructor)) static void bridge_fonts(void) {
    Class ct = objc_getClass("__NSCFCTFont"), ctd = objc_getClass("__NSCFCTFontDescriptor");
    if (ct) class_setSuperclass(ct, [NSFont class]);
    if (ctd) class_setSuperclass(ctd, [NSFontDescriptor class]);
}

/* The system UI fonts by name: what CoreText resolves ".AppleSystemUIFont"
 * and friends to. */
static NSFont *font(NSString *name, CGFloat size) {
    if (size <= 0) size = [NSFont systemFontSize];
    CTFontRef f = CTFontCreateWithName((__bridge CFStringRef)name, size, NULL);
    return (__bridge_transfer NSFont *)f;
}

@implementation NSFont
+ (NSFont *)fontWithName:(NSString *)name size:(CGFloat)size { return name ? font(name, size) : nil; }
+ (NSFont *)fontWithName:(NSString *)name matrix:(const CGFloat *)m {
    return font(name, m ? hypot(m[0], m[1]) : 0);
}
+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)d size:(CGFloat)size {
    if (!d) return nil;
    if (size <= 0) size = d.pointSize > 0 ? d.pointSize : [self systemFontSize];
    return (__bridge_transfer NSFont *)CTFontCreateWithFontDescriptor(CTD(d), size, NULL);
}
+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)d textTransform:(NSAffineTransform *)t {
    return [self fontWithDescriptor:d size:0];
}
+ (NSFont *)systemFontOfSize:(CGFloat)size { return font(@".AppleSystemUIFont", size); }
+ (NSFont *)systemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return font(weight >= NSFontWeightSemibold ? @".AppleSystemUIFontBold" : @".AppleSystemUIFont", size);
}
+ (NSFont *)systemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight width:(NSFontWidth)width {
    return [self systemFontOfSize:size weight:weight];
}
+ (NSFont *)boldSystemFontOfSize:(CGFloat)size { return font(@".AppleSystemUIFontBold", size); }
+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return font(weight >= NSFontWeightSemibold ? @".AppleSystemUIFontMonospaced-Bold" : @".AppleSystemUIFontMonospaced",
                size);
}
+ (NSFont *)monospacedDigitSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return [self systemFontOfSize:size weight:weight];
}
+ (NSFont *)userFontOfSize:(CGFloat)size { return [self systemFontOfSize:size]; }
+ (NSFont *)userFixedPitchFontOfSize:(CGFloat)size { return font(@"Menlo-Regular", size); }
+ (NSFont *)menuFontOfSize:(CGFloat)size { return [self systemFontOfSize:size > 0 ? size : 13]; }
+ (NSFont *)menuBarFontOfSize:(CGFloat)size { return [self systemFontOfSize:size > 0 ? size : 13]; }
+ (NSFont *)labelFontOfSize:(CGFloat)size { return [self systemFontOfSize:size > 0 ? size : [self labelFontSize]]; }
+ (NSFont *)messageFontOfSize:(CGFloat)size { return [self systemFontOfSize:size]; }
+ (NSFont *)titleBarFontOfSize:(CGFloat)size { return [self boldSystemFontOfSize:size]; }
+ (NSFont *)toolTipsFontOfSize:(CGFloat)size { return [self systemFontOfSize:size > 0 ? size : 11]; }
+ (NSFont *)paletteFontOfSize:(CGFloat)size { return [self systemFontOfSize:size > 0 ? size : 11]; }
+ (NSFont *)controlContentFontOfSize:(CGFloat)size { return [self systemFontOfSize:size]; }
+ (NSFont *)preferredFontForTextStyle:(NSFontTextStyle)style options:(NSDictionary *)options {
    static NSDictionary *sizes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sizes = @{
            NSFontTextStyleLargeTitle : @26, NSFontTextStyleTitle1 : @22, NSFontTextStyleTitle2 : @17,
            NSFontTextStyleTitle3 : @15, NSFontTextStyleHeadline : @13, NSFontTextStyleSubheadline : @11,
            NSFontTextStyleBody : @13, NSFontTextStyleCallout : @12, NSFontTextStyleFootnote : @10,
            NSFontTextStyleCaption1 : @10, NSFontTextStyleCaption2 : @10
        };
    });
    CGFloat size = [sizes[style] doubleValue] ?: 13;
    return [style isEqualToString:NSFontTextStyleHeadline] ? [self boldSystemFontOfSize:size]
                                                          : [self systemFontOfSize:size];
}
+ (CGFloat)systemFontSize { return 13; }
+ (CGFloat)smallSystemFontSize { return 11; }
+ (CGFloat)labelFontSize { return 10; }
+ (CGFloat)systemFontSizeForControlSize:(NSControlSize)s {
    switch (s) {
    case NSControlSizeSmall: return 11;
    case NSControlSizeMini: return 9;
    case NSControlSizeLarge: return 15;
    default: return 13;
    }
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)fontName { return (__bridge_transfer NSString *)CTFontCopyPostScriptName(CT(self)); }
- (NSString *)familyName { return (__bridge_transfer NSString *)CTFontCopyFamilyName(CT(self)); }
- (NSString *)displayName { return (__bridge_transfer NSString *)CTFontCopyDisplayName(CT(self)); }
- (CGFloat)pointSize { return CTFontGetSize(CT(self)); }
- (CGFloat)ascender { return CTFontGetAscent(CT(self)); }
- (CGFloat)descender { return -CTFontGetDescent(CT(self)); }
- (CGFloat)leading { return CTFontGetLeading(CT(self)); }
- (CGFloat)capHeight { return CTFontGetCapHeight(CT(self)); }
- (CGFloat)xHeight { return CTFontGetXHeight(CT(self)); }
- (CGFloat)underlinePosition { return CTFontGetUnderlinePosition(CT(self)); }
- (CGFloat)underlineThickness { return CTFontGetUnderlineThickness(CT(self)); }
- (CGFloat)italicAngle { return CTFontGetSlantAngle(CT(self)); }
- (NSRect)boundingRectForFont { return CTFontGetBoundingBox(CT(self)); }
- (NSSize)maximumAdvancement { return NSMakeSize(CTFontGetBoundingBox(CT(self)).size.width, 0); }
- (NSUInteger)numberOfGlyphs { return (NSUInteger)CTFontGetGlyphCount(CT(self)); }
- (BOOL)isFixedPitch { return (CTFontGetSymbolicTraits(CT(self)) & kCTFontTraitMonoSpace) != 0; }
- (BOOL)isVertical { return (CTFontGetSymbolicTraits(CT(self)) & kCTFontTraitVertical) != 0; }
- (NSFont *)verticalFont { return self; }
- (NSFont *)screenFont { return self; }
- (NSFont *)printerFont { return self; }
- (const CGFloat *)matrix {
    static CGFloat m[6];
    CGFloat s = self.pointSize;
    m[0] = s; m[1] = 0; m[2] = 0; m[3] = s; m[4] = 0; m[5] = 0;
    return m;
}
- (NSFontDescriptor *)fontDescriptor { return (__bridge_transfer NSFontDescriptor *)CTFontCopyFontDescriptor(CT(self)); }
- (NSSize)advancementForGlyph:(NSGlyph)g {
    CGGlyph glyph = (CGGlyph)g;
    CGSize a;
    CTFontGetAdvancesForGlyphs(CT(self), kCTFontOrientationDefault, &glyph, &a, 1);
    return a;
}
- (NSRect)boundingRectForCGGlyph:(CGGlyph)g {
    CGRect r;
    CTFontGetBoundingRectsForGlyphs(CT(self), kCTFontOrientationDefault, &g, &r, 1);
    return r;
}
- (void)set {
    NSGraphicsContext *g = [NSGraphicsContext currentContext];
    (void)g;
}
- (BOOL)isEqual:(id)o {
    return o == self || ([o isKindOfClass:[NSFont class]] && [[o fontName] isEqualToString:self.fontName] &&
                         [o pointSize] == self.pointSize);
}
- (NSUInteger)hash { return self.fontName.hash ^ (NSUInteger)self.pointSize; }
- (NSString *)description { return [NSString stringWithFormat:@"\"%@ %gpt.\"", self.fontName, self.pointSize]; }
@end

@implementation NSFontDescriptor
+ (NSFontDescriptor *)fontDescriptorWithFontAttributes:(NSDictionary *)attrs {
    return (__bridge_transfer NSFontDescriptor *)CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)(attrs ?: @{}));
}
+ (NSFontDescriptor *)fontDescriptorWithName:(NSString *)name size:(CGFloat)size {
    return (__bridge_transfer NSFontDescriptor *)CTFontDescriptorCreateWithNameAndSize((__bridge CFStringRef)name, size);
}
+ (NSFontDescriptor *)preferredFontDescriptorForTextStyle:(NSFontTextStyle)style options:(NSDictionary *)options {
    return [NSFont preferredFontForTextStyle:style options:options].fontDescriptor;
}
- (NSDictionary *)fontAttributes { return (__bridge_transfer NSDictionary *)CTFontDescriptorCopyAttributes(CTD(self)); }
- (id)objectForKey:(NSFontDescriptorAttributeName)key {
    return (__bridge_transfer id)CTFontDescriptorCopyAttribute(CTD(self), (__bridge CFStringRef)key);
}
- (NSString *)postscriptName { return [self objectForKey:(__bridge NSString *)kCTFontNameAttribute]; }
- (CGFloat)pointSize { return [[self objectForKey:(__bridge NSString *)kCTFontSizeAttribute] doubleValue]; }
- (NSFontDescriptorSymbolicTraits)symbolicTraits {
    NSDictionary *t = [self objectForKey:(__bridge NSString *)kCTFontTraitsAttribute];
    return [t[(__bridge NSString *)kCTFontSymbolicTrait] unsignedIntValue];
}
- (NSFontDescriptor *)fontDescriptorByAddingAttributes:(NSDictionary *)attrs {
    return (__bridge_transfer NSFontDescriptor *)CTFontDescriptorCreateCopyWithAttributes(CTD(self),
                                                                                         (__bridge CFDictionaryRef)attrs);
}
- (NSFontDescriptor *)fontDescriptorWithSize:(CGFloat)size {
    return [self fontDescriptorByAddingAttributes:@{(__bridge NSString *)kCTFontSizeAttribute : @(size)}];
}
- (NSFontDescriptor *)fontDescriptorWithFamily:(NSString *)family {
    return [self fontDescriptorByAddingAttributes:@{(__bridge NSString *)kCTFontFamilyNameAttribute : family}];
}
- (NSFontDescriptor *)fontDescriptorWithSymbolicTraits:(NSFontDescriptorSymbolicTraits)traits {
    NSMutableDictionary *t = [[self objectForKey:(__bridge NSString *)kCTFontTraitsAttribute] mutableCopy] ?: [NSMutableDictionary dictionary];
    t[(__bridge NSString *)kCTFontSymbolicTrait] = @(traits);
    return [self fontDescriptorByAddingAttributes:@{(__bridge NSString *)kCTFontTraitsAttribute : t}];
}
- (NSFontDescriptor *)fontDescriptorWithDesign:(NSFontDescriptorSystemDesign)design { return self; }
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation NSFontManager {
    NSFont *_selected;
    __weak id _target;
    SEL _action;
}
+ (NSFontManager *)sharedFontManager {
    static NSFontManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [NSFontManager new]; });
    return m;
}
- (NSArray<NSString *> *)availableFontFamilies {
    CTFontCollectionRef all = CTFontCollectionCreateWithFontDescriptors(NULL, NULL);
    CFArrayRef descs = all ? CTFontCollectionCreateMatchingFontDescriptors(all) : NULL;
    NSMutableSet *families = [NSMutableSet set];
    for (id d in (__bridge NSArray *)descs) {
        NSString *f = (__bridge_transfer NSString *)(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)d, kCTFontFamilyNameAttribute));
        if (f) [families addObject:f];
    }
    if (descs) CFRelease(descs);
    if (all) CFRelease(all);
    return [families.allObjects sortedArrayUsingSelector:@selector(compare:)];
}
- (NSArray<NSString *> *)availableFonts {
    CTFontCollectionRef all = CTFontCollectionCreateWithFontDescriptors(NULL, NULL);
    CFArrayRef descs = all ? CTFontCollectionCreateMatchingFontDescriptors(all) : NULL;
    NSMutableArray *names = [NSMutableArray array];
    for (id d in (__bridge NSArray *)descs) {
        NSString *n = (__bridge_transfer NSString *)(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)d, kCTFontNameAttribute));
        if (n) [names addObject:n];
    }
    if (descs) CFRelease(descs);
    if (all) CFRelease(all);
    return names;
}
- (NSArray<NSArray *> *)availableMembersOfFontFamily:(NSString *)family {
    NSFont *f = [self fontWithFamily:family traits:0 weight:5 size:13];
    return f ? @[ @[ f.fontName, @"Regular", @5, @0 ] ] : @[];
}
- (NSFontTraitMask)traitsOfFont:(NSFont *)f {
    CTFontSymbolicTraits t = CTFontGetSymbolicTraits(CT(f));
    NSFontTraitMask m = 0;
    if (t & kCTFontTraitBold) m |= NSBoldFontMask;
    if (t & kCTFontTraitItalic) m |= NSItalicFontMask;
    if (t & kCTFontTraitMonoSpace) m |= NSFixedPitchFontMask;
    return m ?: NSUnboldFontMask;
}
- (NSInteger)weightOfFont:(NSFont *)f { return (CTFontGetSymbolicTraits(CT(f)) & kCTFontTraitBold) ? 9 : 5; }
- (NSFont *)fontWithFamily:(NSString *)family traits:(NSFontTraitMask)traits weight:(NSInteger)weight size:(CGFloat)size {
    NSDictionary *attrs = @{(__bridge NSString *)kCTFontFamilyNameAttribute : family ?: @"",
                            (__bridge NSString *)kCTFontSizeAttribute : @(size)};
    NSFontDescriptor *d = [NSFontDescriptor fontDescriptorWithFontAttributes:attrs];
    NSFont *f = [NSFont fontWithDescriptor:d size:size];
    if (f && ((traits & NSBoldFontMask) || weight >= 8)) f = [self convertFont:f toHaveTrait:NSBoldFontMask];
    if (f && (traits & NSItalicFontMask)) f = [self convertFont:f toHaveTrait:NSItalicFontMask];
    return f;
}
- (NSFont *)convertFont:(NSFont *)f toSize:(CGFloat)size {
    return (__bridge_transfer NSFont *)CTFontCreateCopyWithAttributes(CT(f), size, NULL, NULL);
}
- (NSFont *)convertFont:(NSFont *)f toHaveTrait:(NSFontTraitMask)trait {
    CTFontSymbolicTraits t = 0;
    if (trait & NSBoldFontMask) t |= kCTFontTraitBold;
    if (trait & NSItalicFontMask) t |= kCTFontTraitItalic;
    CTFontRef c = CTFontCreateCopyWithSymbolicTraits(CT(f), 0, NULL, t, t);
    return c ? (__bridge_transfer NSFont *)c : f;
}
- (NSFont *)convertFont:(NSFont *)f toNotHaveTrait:(NSFontTraitMask)trait {
    CTFontSymbolicTraits t = 0;
    if (trait & NSBoldFontMask) t |= kCTFontTraitBold;
    if (trait & NSItalicFontMask) t |= kCTFontTraitItalic;
    CTFontRef c = CTFontCreateCopyWithSymbolicTraits(CT(f), 0, NULL, 0, t);
    return c ? (__bridge_transfer NSFont *)c : f;
}
- (NSFont *)convertFont:(NSFont *)f toFamily:(NSString *)family {
    return [self fontWithFamily:family traits:[self traitsOfFont:f] weight:[self weightOfFont:f] size:f.pointSize] ?: f;
}
- (NSFont *)convertFont:(NSFont *)f { return f; }
- (NSFont *)selectedFont { return _selected; }
- (void)setSelectedFont:(NSFont *)f isMultiple:(BOOL)multiple { _selected = f; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; }
- (void)setAction:(SEL)a { _action = a; }
- (void)orderFrontFontPanel:(id)sender {}
- (BOOL)isEnabled { return YES; }
- (void)setEnabled:(BOOL)e {}
@end
