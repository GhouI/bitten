/* NSVisualEffectView: translucent material backgrounds, drawn as the
 * material's tint over what is behind (there is no blur). */

#import <AppKit/AppKit.h>
#import <objc/message.h>

@implementation NSVisualEffectView {
    NSVisualEffectMaterial _material;
    NSVisualEffectBlendingMode _blendingMode;
    NSVisualEffectState _state;
    BOOL _emphasized;
    NSImage *_maskImage;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _material = NSVisualEffectMaterialAppearanceBased;
    _blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _state = NSVisualEffectStateFollowsWindowActiveState;
    return self;
}
- (NSVisualEffectMaterial)material { return _material; }
- (void)setMaterial:(NSVisualEffectMaterial)m {
    _material = m;
    self.needsDisplay = YES;
}
- (NSVisualEffectBlendingMode)blendingMode { return _blendingMode; }
- (void)setBlendingMode:(NSVisualEffectBlendingMode)m {
    _blendingMode = m;
    self.needsDisplay = YES;
}
- (NSVisualEffectState)state { return _state; }
- (void)setState:(NSVisualEffectState)s { _state = s; }
- (BOOL)isEmphasized { return _emphasized; }
- (void)setEmphasized:(BOOL)e { _emphasized = e; }
- (NSImage *)maskImage { return _maskImage; }
- (void)setMaskImage:(NSImage *)image { _maskImage = image; }
- (NSBackgroundStyle)interiorBackgroundStyle { return NSBackgroundStyleNormal; }
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    NSWindow *w = self.window;
    if (w) ((void (*)(id, SEL, id))objc_msgSend)(w, sel_registerName("_bn_noteEffectView:"), self);
}
/* A behind-window material in a see-through window, which the display
 * blurs behind: what shows through is blurred, so the tint can be as
 * light as macOS's. */
- (BOOL)_bn_blurredBehind {
    NSWindow *w = self.window;
    if (_blendingMode != NSVisualEffectBlendingModeBehindWindow || !w) return NO;
    CGFloat bgAlpha = w.backgroundColor ? w.backgroundColor.alphaComponent : 1;
    return !w.isOpaque || bgAlpha < 1;
}
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirty {
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua
    ]] isEqualToString:NSAppearanceNameDarkAqua];
    CGFloat alpha;
    switch (_material) {
    case NSVisualEffectMaterialSelection: [[NSColor.controlAccentColor colorWithAlphaComponent:0.8] setFill];
        NSRectFill(self.bounds);
        return;
    case NSVisualEffectMaterialHUDWindow: case NSVisualEffectMaterialFullScreenUI: alpha = 0.85; break;
    case NSVisualEffectMaterialMenu: case NSVisualEffectMaterialPopover: alpha = 0.9; break;
    default: alpha = 0.75;
    }
    /* Without a blur, what lies under a material (a palette window over
     * terminal text) would stay legible; macOS blurs it past reading, so
     * the material is all but opaque. */
    alpha = [self _bn_blurredBehind] ? MIN(alpha, 0.8) : MAX(alpha, 0.96);
    [[NSColor colorWithWhite:dark ? 0.15 : 0.93 alpha:alpha] setFill];
    NSRectFill(self.bounds);
}
@end
