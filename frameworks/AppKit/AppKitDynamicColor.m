/* Dynamic colours (resolved against the current drawing appearance each
 * time their components are read) and the system colours made from them. */

#import <AppKit/AppKit.h>

@interface BNDynamicColor : NSColor
@end
@implementation BNDynamicColor {
    NSColorName _name;
    NSColor * (^_provider)(NSAppearance *);
    NSColor *_lastResolved;
    /* made by colorWithAlphaComponent: from this colour, with this alpha */
    BNDynamicColor *_base;
    CGFloat _alpha;
}
- (instancetype)initWithName:(NSColorName)name provider:(NSColor * (^)(NSAppearance *))provider {
    self = [super init];
    _name = [name copy];
    _provider = [provider copy];
    return self;
}
- (NSColor *)resolved {
    NSColor *c = _provider([NSAppearance currentDrawingAppearance]);
    /* A provider returning another dynamic colour resolves through it. */
    return c ? c : [NSColor blackColor];
}
- (CGFloat)redComponent { return self.resolved.redComponent; }
- (CGFloat)greenComponent { return self.resolved.greenComponent; }
- (CGFloat)blueComponent { return self.resolved.blueComponent; }
- (CGFloat)alphaComponent { return self.resolved.alphaComponent; }
- (NSColorSpace *)colorSpace { return self.resolved.colorSpace; }
/* Resolved afresh (the appearance may change), but the colour resolved is
 * kept until the next call: the CGColor returned belongs to it. */
- (CGColorRef)CGColor {
    _lastResolved = self.resolved;
    return _lastResolved.CGColor;
}
- (NSColor *)colorWithAlphaComponent:(CGFloat)a {
    NSColor * (^p)(NSAppearance *) = _provider;
    BNDynamicColor *c = (BNDynamicColor *)[NSColor colorWithName:_name dynamicProvider:^NSColor *(NSAppearance *ap) {
        return [p(ap) colorWithAlphaComponent:a];
    }];
    if ([c isKindOfClass:[BNDynamicColor class]]) {
        c->_base = _base ?: self;
        c->_alpha = a;
    }
    return c;
}
- (NSColor *)colorUsingColorSpace:(NSColorSpace *)space { return [self.resolved colorUsingColorSpace:space]; }
- (NSColorName)colorNameComponent { return _name; }
- (NSString *)description {
    if (_base) return [NSString stringWithFormat:@"%@ alpha %g", _base.description, _alpha];
    /* with its value now: two different unnamed colours don't read alike */
    return [NSString stringWithFormat:@"Dynamic color %@ (%@)", _name ?: @"(unnamed)", self.resolved.description];
}
/* The same named colour from the same provider (its components depend on
 * the appearance, not on stored values). */
- (BOOL)isEqual:(id)other {
    if (other == self) return YES;
    if (![other isKindOfClass:[BNDynamicColor class]]) return NO;
    BNDynamicColor *o = other;
    if (_base || o->_base) return _base && o->_base && _alpha == o->_alpha && [_base isEqual:o->_base];
    return o->_provider == _provider && (o->_name == _name || [o->_name isEqual:_name]);
}
- (NSUInteger)hash {
    if (_base) return _base.hash ^ (NSUInteger)(_alpha * 1000);
    return _name.hash ^ (NSUInteger)(__bridge void *)_provider;
}
@end

static BOOL dark(NSAppearance *a) {
    return [[a bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
        isEqualToString:NSAppearanceNameDarkAqua];
}
static NSColor *rgb(unsigned hex, CGFloat a) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xFF) / 255.0 green:((hex >> 8) & 0xFF) / 255.0
                                blue:(hex & 0xFF) / 255.0 alpha:a];
}
static NSColor *pair(NSString *name, unsigned light, CGFloat la, unsigned darkc, CGFloat da) {
    return [NSColor colorWithName:name dynamicProvider:^NSColor *(NSAppearance *ap) {
        return dark(ap) ? rgb(darkc, da) : rgb(light, la);
    }];
}

@implementation NSColor (BittenDynamic)
+ (NSColor *)colorWithName:(NSColorName)name dynamicProvider:(NSColor * (^)(NSAppearance *))provider {
    return [[BNDynamicColor alloc] initWithName:name provider:provider];
}
- (NSColor *)blendedColorWithFraction:(CGFloat)f ofColor:(NSColor *)other {
    if (!other) return nil;
    CGFloat g = 1 - f;
    return [NSColor colorWithSRGBRed:self.redComponent * g + other.redComponent * f
                               green:self.greenComponent * g + other.greenComponent * f
                                blue:self.blueComponent * g + other.blueComponent * f
                               alpha:self.alphaComponent * g + other.alphaComponent * f];
}
- (NSColor *)highlightWithLevel:(CGFloat)level { return [self blendedColorWithFraction:level ofColor:NSColor.whiteColor]; }
- (NSColor *)shadowWithLevel:(CGFloat)level { return [self blendedColorWithFraction:level ofColor:NSColor.blackColor]; }

#define SYS(sel, l, la, d, da) \
    +(NSColor *)sel { return pair(@#sel, l, la, d, da); }
SYS(systemRedColor, 0xFF3B30, 1, 0xFF453A, 1)
SYS(systemOrangeColor, 0xFF9500, 1, 0xFF9F0A, 1)
SYS(systemYellowColor, 0xFFCC00, 1, 0xFFD60A, 1)
SYS(systemGreenColor, 0x28CD41, 1, 0x32D74B, 1)
SYS(systemMintColor, 0x00C7BE, 1, 0x63E6E2, 1)
SYS(systemTealColor, 0x59ADC4, 1, 0x6AC4DC, 1)
SYS(systemCyanColor, 0x55BEF0, 1, 0x5AC8F5, 1)
SYS(systemBlueColor, 0x007AFF, 1, 0x0A84FF, 1)
SYS(systemIndigoColor, 0x5856D6, 1, 0x5E5CE6, 1)
SYS(systemPurpleColor, 0xAF52DE, 1, 0xBF5AF2, 1)
SYS(systemPinkColor, 0xFF2D55, 1, 0xFF375F, 1)
SYS(systemBrownColor, 0xA2845E, 1, 0xAC8E68, 1)
SYS(systemGrayColor, 0x8E8E93, 1, 0x98989D, 1)
SYS(labelColor, 0x000000, 0.85, 0xFFFFFF, 0.85)
SYS(secondaryLabelColor, 0x000000, 0.5, 0xFFFFFF, 0.55)
SYS(textColor, 0x000000, 1, 0xFFFFFF, 1)
SYS(textBackgroundColor, 0xFFFFFF, 1, 0x1E1E1E, 1)
SYS(windowBackgroundColor, 0xECECEC, 1, 0x323232, 1)
SYS(controlBackgroundColor, 0xFFFFFF, 1, 0x1E1E1E, 1)
SYS(separatorColor, 0x000000, 0.1, 0xFFFFFF, 0.1)
SYS(tertiaryLabelColor, 0x000000, 0.26, 0xFFFFFF, 0.25)
SYS(quaternaryLabelColor, 0x000000, 0.1, 0xFFFFFF, 0.1)
SYS(placeholderTextColor, 0x000000, 0.25, 0xFFFFFF, 0.25)
SYS(controlColor, 0xFFFFFF, 1, 0xFFFFFF, 0.25)
SYS(controlTextColor, 0x000000, 0.85, 0xFFFFFF, 0.85)
SYS(disabledControlTextColor, 0x000000, 0.25, 0xFFFFFF, 0.25)
SYS(selectedControlColor, 0xB3D7FF, 1, 0x3F638B, 1)
SYS(selectedControlTextColor, 0x000000, 0.85, 0xFFFFFF, 0.85)
SYS(alternateSelectedControlTextColor, 0xFFFFFF, 1, 0xFFFFFF, 1)
SYS(selectedMenuItemTextColor, 0xFFFFFF, 1, 0xFFFFFF, 1)
SYS(selectedTextBackgroundColor, 0xB3D7FF, 1, 0x3F638B, 1)
SYS(selectedTextColor, 0x000000, 1, 0xFFFFFF, 1)
SYS(unemphasizedSelectedContentBackgroundColor, 0xDCDCDC, 1, 0x464646, 1)
SYS(unemphasizedSelectedTextBackgroundColor, 0xDCDCDC, 1, 0x464646, 1)
SYS(underPageBackgroundColor, 0x969696, 0.9, 0x282828, 1)
SYS(tertiarySystemFillColor, 0x000000, 0.05, 0xFFFFFF, 0.05)
SYS(quaternarySystemFillColor, 0x000000, 0.03, 0xFFFFFF, 0.03)
SYS(secondarySystemFillColor, 0x000000, 0.08, 0xFFFFFF, 0.08)
SYS(systemFillColor, 0x000000, 0.1, 0xFFFFFF, 0.1)
SYS(linkColor, 0x0068DA, 1, 0x419CFF, 1)
SYS(keyboardFocusIndicatorColor, 0x0067F4, 0.5, 0x1AA9FF, 0.5)
SYS(gridColor, 0xE6E6E6, 1, 0x1A1A1A, 1)
SYS(headerTextColor, 0x000000, 0.85, 0xFFFFFF, 1)
SYS(findHighlightColor, 0xFFFF00, 1, 0xFFFF00, 1)
SYS(shadowColor, 0x000000, 1, 0x000000, 1)
SYS(highlightColor, 0xFFFFFF, 1, 0xB4B4B4, 1)
SYS(windowFrameTextColor, 0x000000, 0.85, 0xFFFFFF, 0.85)
SYS(scrubberTexturedBackgroundColor, 0xFFFFFF, 1, 0x1E1E1E, 1)
@end
