/* Common controls and the small value classes around them: NSImageView,
 * NSButton, NSProgressIndicator, NSSegmentedControl, NSCursor, paragraph
 * styles, NSGradient, NSSound, haptics, custom accessibility actions and
 * click/press gesture recognizers. */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdlib.h>
#import <objc/message.h>

static NSRect inset(NSRect r, CGFloat d) { return NSInsetRect(r, d, d); }
static NSSize fit(NSSize s, NSSize in) {
    if (s.width <= 0 || s.height <= 0) return in;
    CGFloat k = MIN(in.width / s.width, in.height / s.height);
    return NSMakeSize(s.width * k, s.height * k);
}

/* ---- NSImageView ---- */

@implementation NSImageView {
    NSImage *_image;
    NSImageScaling _scaling;
    NSImageAlignment _imageAlignment;
    NSColor *_tint;
    NSImageSymbolConfiguration *_symbolConfiguration;
    BOOL _editable, _animates;
    NSImageFrameStyle _frameStyle;
}
+ (instancetype)imageViewWithImage:(NSImage *)image {
    NSImageView *v = [[self alloc] initWithFrame:NSMakeRect(0, 0, image.size.width, image.size.height)];
    v.image = image;
    return v;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _scaling = NSImageScaleProportionallyDown;
    _imageAlignment = NSImageAlignCenter;
    return self;
}
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)image {
    _image = image;
    self.needsDisplay = YES;
}
- (NSImageScaling)imageScaling { return _scaling; }
- (void)setImageScaling:(NSImageScaling)s { _scaling = s; }
- (NSImageAlignment)imageAlignment { return _imageAlignment; }
- (void)setImageAlignment:(NSImageAlignment)a { _imageAlignment = a; }
- (NSImageFrameStyle)imageFrameStyle { return _frameStyle; }
- (void)setImageFrameStyle:(NSImageFrameStyle)s { _frameStyle = s; }
- (NSColor *)contentTintColor { return _tint; }
- (void)setContentTintColor:(NSColor *)c {
    _tint = c;
    self.needsDisplay = YES;
}
- (NSImageSymbolConfiguration *)symbolConfiguration { return _symbolConfiguration; }
- (void)setSymbolConfiguration:(NSImageSymbolConfiguration *)c { _symbolConfiguration = c; }
- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)b { _editable = b; }
- (BOOL)animates { return _animates; }
- (void)setAnimates:(BOOL)b { _animates = b; }
- (NSSize)intrinsicContentSize { return _image ? _image.size : NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric); }
- (void)drawRect:(NSRect)dirty {
    if (!_image) return;
    NSRect b = self.bounds;
    NSSize s = _image.size;
    switch (_scaling) {
    case NSImageScaleAxesIndependently: s = b.size; break;
    case NSImageScaleProportionallyUpOrDown: s = fit(s, b.size); break;
    case NSImageScaleProportionallyDown:
        if (s.width > b.size.width || s.height > b.size.height) s = fit(s, b.size);
        break;
    default: break;
    }
    NSRect r = NSMakeRect(NSMidX(b) - s.width / 2, NSMidY(b) - s.height / 2, s.width, s.height);
    [_image drawInRect:r];
}
@end

/* ---- NSButton ---- */

@implementation NSButton {
    NSString *_title, *_alternateTitle, *_keyEquivalent;
    NSAttributedString *_attributedTitle;
    NSImage *_image, *_alternateImage;
    NSCellImagePosition _imagePosition;
    NSBezelStyle _bezelStyle;
    NSButtonType _type;
    NSControlStateValue _state;
    BOOL _bordered, _transparent, _allowsMixed, _borderOnHover, _pressed, _springLoaded;
    NSColor *_tint, *_bezelColor;
    NSEventModifierFlags _keyMask;
    NSImageScaling _imageScaling;
    NSImageSymbolConfiguration *_symbolConfiguration;
}
+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    NSButton *b = [[self alloc] initWithFrame:NSZeroRect];
    b.title = title;
    b.target = target;
    b.action = action;
    [b sizeToFit];
    return b;
}
+ (instancetype)buttonWithImage:(NSImage *)image target:(id)target action:(SEL)action {
    NSButton *b = [self buttonWithTitle:@"" target:target action:action];
    b.image = image;
    b.imagePosition = NSImageOnly;
    [b sizeToFit];
    return b;
}
+ (instancetype)buttonWithTitle:(NSString *)title image:(NSImage *)image target:(id)target action:(SEL)action {
    NSButton *b = [self buttonWithTitle:title target:target action:action];
    b.image = image;
    b.imagePosition = NSImageLeading;
    [b sizeToFit];
    return b;
}
+ (instancetype)checkboxWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    NSButton *b = [self buttonWithTitle:title target:target action:action];
    [b setButtonType:NSButtonTypeSwitch];
    [b sizeToFit];
    return b;
}
+ (instancetype)radioButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    NSButton *b = [self buttonWithTitle:title target:target action:action];
    [b setButtonType:NSButtonTypeRadio];
    [b sizeToFit];
    return b;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _title = @"Button";
    _bordered = YES;
    _bezelStyle = NSBezelStylePush;
    _keyEquivalent = @"";
    _imagePosition = NSNoImage;
    _imageScaling = NSImageScaleProportionallyDown;
    return self;
}
- (NSString *)title { return _attributedTitle ? _attributedTitle.string : _title; }
- (void)setTitle:(NSString *)t {
    _title = [t copy] ?: @"";
    _attributedTitle = nil;
    self.needsDisplay = YES;
}
- (NSAttributedString *)attributedTitle {
    return _attributedTitle ?: [[NSAttributedString alloc] initWithString:_title attributes:@{NSFontAttributeName : self.font}];
}
- (void)setAttributedTitle:(NSAttributedString *)a {
    _attributedTitle = [a copy];
    self.needsDisplay = YES;
}
- (NSString *)alternateTitle { return _alternateTitle ?: @""; }
- (void)setAlternateTitle:(NSString *)t { _alternateTitle = [t copy]; }
- (NSString *)stringValue { return _title; }
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)i {
    _image = i;
    if (i && _imagePosition == NSNoImage) _imagePosition = _title.length ? NSImageLeft : NSImageOnly;
    self.needsDisplay = YES;
}
- (NSImage *)alternateImage { return _alternateImage; }
- (void)setAlternateImage:(NSImage *)i { _alternateImage = i; }
- (NSCellImagePosition)imagePosition { return _imagePosition; }
- (void)setImagePosition:(NSCellImagePosition)p { _imagePosition = p; }
- (NSImageScaling)imageScaling { return _imageScaling; }
- (void)setImageScaling:(NSImageScaling)s { _imageScaling = s; }
- (BOOL)imageHugsTitle { return YES; }
- (void)setImageHugsTitle:(BOOL)b {}
- (NSBezelStyle)bezelStyle { return _bezelStyle; }
- (void)setBezelStyle:(NSBezelStyle)s { _bezelStyle = s; }
- (void)setButtonType:(NSButtonType)t { _type = t; }
- (NSControlStateValue)state { return _state; }
- (void)setState:(NSControlStateValue)s {
    _state = s;
    self.needsDisplay = YES;
}
- (BOOL)allowsMixedState { return _allowsMixed; }
- (void)setAllowsMixedState:(BOOL)b { _allowsMixed = b; }
- (BOOL)isBordered { return _bordered; }
- (void)setBordered:(BOOL)b { _bordered = b; }
- (BOOL)isTransparent { return _transparent; }
- (void)setTransparent:(BOOL)b { _transparent = b; }
- (BOOL)showsBorderOnlyWhileMouseInside { return _borderOnHover; }
- (void)setShowsBorderOnlyWhileMouseInside:(BOOL)b { _borderOnHover = b; }
- (BOOL)isSpringLoaded { return _springLoaded; }
- (void)setSpringLoaded:(BOOL)b { _springLoaded = b; }
- (NSColor *)contentTintColor { return _tint; }
- (void)setContentTintColor:(NSColor *)c { _tint = c; }
- (NSColor *)bezelColor { return _bezelColor; }
- (void)setBezelColor:(NSColor *)c { _bezelColor = c; }
- (NSString *)keyEquivalent { return _keyEquivalent; }
- (void)setKeyEquivalent:(NSString *)k { _keyEquivalent = [k copy] ?: @""; }
- (NSEventModifierFlags)keyEquivalentModifierMask { return _keyMask; }
- (void)setKeyEquivalentModifierMask:(NSEventModifierFlags)m { _keyMask = m; }
- (NSImageSymbolConfiguration *)symbolConfiguration { return _symbolConfiguration; }
- (void)setSymbolConfiguration:(NSImageSymbolConfiguration *)c { _symbolConfiguration = c; }
- (BOOL)hasDestructiveAction { return NO; }
- (void)setHasDestructiveAction:(BOOL)b {}
- (void)setPeriodicDelay:(float)delay interval:(float)interval {}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isFlipped { return YES; }
- (void)_bn_toggle {
    if (_type == NSButtonTypeSwitch || _type == NSButtonTypePushOnPushOff || _type == NSButtonTypeToggle ||
        _type == NSButtonTypeOnOff)
        self.state = _state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn;
    else if (_type == NSButtonTypeRadio)
        self.state = NSControlStateValueOn;
}
- (void)performClick:(id)sender {
    if (!self.isEnabled) return;
    [self _bn_toggle];
    [self sendAction:self.action to:self.target];
}
- (void)mouseDown:(NSEvent *)event {
    if (!self.isEnabled) return;
    _pressed = YES;
    self.highlighted = YES;
    self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)event {
    if (!_pressed) return;
    _pressed = NO;
    self.highlighted = NO;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, self.bounds)) [self performClick:self];
    self.needsDisplay = YES;
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (!_keyEquivalent.length || ![event.charactersIgnoringModifiers isEqualToString:_keyEquivalent]) return NO;
    NSEventModifierFlags relevant = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption |
                                    NSEventModifierFlagControl;
    if ((event.modifierFlags & relevant) != (_keyMask & relevant)) return NO;
    [self performClick:self];
    return YES;
}
- (BOOL)_bn_isCheck { return _type == NSButtonTypeSwitch || _type == NSButtonTypeRadio; }
- (NSSize)intrinsicContentSize {
    NSSize t = _imagePosition == NSImageOnly ? NSZeroSize : self.attributedTitle.size;
    NSSize i = _image && _imagePosition != NSNoImage ? _image.size : NSZeroSize;
    CGFloat w = t.width + i.width + (t.width && i.width ? 4 : 0), h = MAX(t.height, i.height);
    if (self._bn_isCheck) return NSMakeSize(w + 20, MAX(h, 16));
    if (!_bordered) return NSMakeSize(w + 4, h + 2);
    return NSMakeSize(w + 24, MAX(h + 8, 22));
}
- (NSSize)fittingSize { return self.intrinsicContentSize; }
- (void)drawRect:(NSRect)dirty {
    if (_transparent) return;
    NSRect b = self.bounds;
    BOOL on = _state == NSControlStateValueOn, pressed = self.isHighlighted;
    NSColor *fg = self.isEnabled ? (_tint ?: NSColor.controlTextColor) : NSColor.disabledControlTextColor;
    NSRect content = b;
    if (self._bn_isCheck) {
        NSRect box = NSMakeRect(2, (b.size.height - 14) / 2, 14, 14);
        NSBezierPath *p = _type == NSButtonTypeRadio ? [NSBezierPath bezierPathWithOvalInRect:box]
                                                     : [NSBezierPath bezierPathWithRoundedRect:box xRadius:3 yRadius:3];
        [(on ? NSColor.controlAccentColor : NSColor.controlBackgroundColor) setFill];
        [p fill];
        [NSColor.separatorColor setStroke];
        [p stroke];
        if (on) {
            [NSColor.whiteColor setFill];
            [[NSBezierPath bezierPathWithOvalInRect:inset(box, 4)] fill];
        }
        content = NSMakeRect(20, 0, b.size.width - 20, b.size.height);
    } else if (_bordered) {
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:inset(b, 1) xRadius:5 yRadius:5];
        NSColor *fill = _bezelColor ?: (on && _type != NSButtonTypeMomentaryPushIn ? NSColor.controlAccentColor
                                                                                    : NSColor.controlColor);
        if (pressed) fill = [fill blendedColorWithFraction:0.15 ofColor:NSColor.blackColor];
        [fill setFill];
        [p fill];
        [NSColor.separatorColor setStroke];
        [p stroke];
    } else if (pressed) {
        [[NSColor.labelColor colorWithAlphaComponent:0.1] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:b xRadius:4 yRadius:4] fill];
    }
    NSImage *img = on && _alternateImage ? _alternateImage : _image;
    NSSize is = img && _imagePosition != NSNoImage ? img.size : NSZeroSize;
    NSString *title = on && _alternateTitle.length ? _alternateTitle : self.title;
    NSDictionary *attrs = @{NSFontAttributeName : self.font, NSForegroundColorAttributeName : fg};
    NSSize ts = _imagePosition == NSImageOnly || !title.length ? NSZeroSize : [title sizeWithAttributes:attrs];
    CGFloat total = ts.width + is.width + (ts.width && is.width ? 4 : 0);
    CGFloat x = self._bn_isCheck ? NSMinX(content) : NSMidX(content) - total / 2;
    if (is.width) {
        [img drawInRect:NSMakeRect(x, NSMidY(content) - is.height / 2, is.width, is.height)];
        x += is.width + 4;
    }
    if (ts.width) [title drawAtPoint:NSMakePoint(x, NSMidY(content) - ts.height / 2) withAttributes:attrs];
}
@end

/* ---- NSProgressIndicator ---- */

@implementation NSProgressIndicator {
    double _value, _min, _max;
    BOOL _indeterminate, _animating, _displayedWhenStopped;
    NSProgressIndicatorStyle _style;
    NSControlSize _controlSize;
    NSProgress *_observed;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _max = 100;
    _indeterminate = YES;
    _displayedWhenStopped = YES;
    return self;
}
- (double)doubleValue { return _value; }
- (void)setDoubleValue:(double)v {
    _value = v;
    self.needsDisplay = YES;
}
- (void)incrementBy:(double)d { self.doubleValue = _value + d; }
- (double)minValue { return _min; }
- (void)setMinValue:(double)v { _min = v; }
- (double)maxValue { return _max; }
- (void)setMaxValue:(double)v { _max = v; }
- (BOOL)isIndeterminate { return _indeterminate; }
- (void)setIndeterminate:(BOOL)b { _indeterminate = b; }
- (NSProgressIndicatorStyle)style { return _style; }
- (void)setStyle:(NSProgressIndicatorStyle)s { _style = s; }
- (NSControlSize)controlSize { return _controlSize; }
- (void)setControlSize:(NSControlSize)s { _controlSize = s; }
- (BOOL)isDisplayedWhenStopped { return _displayedWhenStopped; }
- (void)setDisplayedWhenStopped:(BOOL)b { _displayedWhenStopped = b; }
- (BOOL)usesThreadedAnimation { return NO; }
- (void)setUsesThreadedAnimation:(BOOL)b {}
- (BOOL)isBezeled { return YES; }
- (void)setBezeled:(BOOL)b {}
- (void)startAnimation:(id)sender {
    _animating = YES;
    self.needsDisplay = YES;
}
- (void)stopAnimation:(id)sender {
    _animating = NO;
    self.needsDisplay = YES;
}
- (NSProgress *)observedProgress { return _observed; }
- (void)setObservedProgress:(NSProgress *)p {
    _observed = p;
    if (p) {
        _indeterminate = p.isIndeterminate;
        _min = 0;
        _max = 1;
        _value = p.fractionCompleted;
    }
}
- (void)sizeToFit {
    NSRect f = self.frame;
    if (_style == NSProgressIndicatorStyleSpinning) f.size = _controlSize == NSControlSizeSmall ? NSMakeSize(16, 16) : NSMakeSize(32, 32);
    else f.size.height = 20;
    self.frame = f;
}
- (void)drawRect:(NSRect)dirty {
    if (!_animating && !_displayedWhenStopped) return;
    NSRect b = self.bounds;
    if (_style == NSProgressIndicatorStyleSpinning) {
        CGFloat r = MIN(b.size.width, b.size.height) / 2 - 1;
        NSPoint c = NSMakePoint(NSMidX(b), NSMidY(b));
        for (int i = 0; i < 8; i++) {
            double a = i * M_PI / 4;
            NSBezierPath *p = [NSBezierPath bezierPath];
            [p moveToPoint:NSMakePoint(c.x + cos(a) * r * 0.45, c.y + sin(a) * r * 0.45)];
            [p lineToPoint:NSMakePoint(c.x + cos(a) * r, c.y + sin(a) * r)];
            p.lineWidth = MAX(1.5, r / 6);
            [[NSColor.secondaryLabelColor colorWithAlphaComponent:0.25 + 0.09 * i] setStroke];
            [p stroke];
        }
        return;
    }
    NSRect track = NSMakeRect(0, NSMidY(b) - 3, b.size.width, 6);
    [NSColor.quaternaryLabelColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:track xRadius:3 yRadius:3] fill];
    double f = _indeterminate ? 0.3 : (_max > _min ? (_value - _min) / (_max - _min) : 0);
    f = f < 0 ? 0 : f > 1 ? 1 : f;
    track.size.width *= f;
    [NSColor.controlAccentColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:track xRadius:3 yRadius:3] fill];
}
@end

/* ---- NSSegmentedControl ---- */

@interface BNSegment : NSObject
@property (copy) NSString *label, *toolTip;
@property (strong) NSImage *image;
@property CGFloat width;
@property BOOL selected, enabled;
@property NSInteger tag;
@property (strong) NSMenu *menu;
@end
@implementation BNSegment
@end

@implementation NSSegmentedControl {
    NSMutableArray<BNSegment *> *_segments;
    NSSegmentSwitchTracking _tracking;
    NSSegmentStyle _segmentStyle;
    NSColor *_selectedTint;
}
+ (instancetype)segmentedControlWithLabels:(NSArray<NSString *> *)labels trackingMode:(NSSegmentSwitchTracking)mode
                                    target:(id)target action:(SEL)action {
    NSSegmentedControl *s = [[self alloc] initWithFrame:NSZeroRect];
    s.segmentCount = labels.count;
    for (NSUInteger i = 0; i < labels.count; i++) [s setLabel:labels[i] forSegment:i];
    s.trackingMode = mode;
    s.target = target;
    s.action = action;
    [s sizeToFit];
    return s;
}
+ (instancetype)segmentedControlWithImages:(NSArray<NSImage *> *)images trackingMode:(NSSegmentSwitchTracking)mode
                                    target:(id)target action:(SEL)action {
    NSSegmentedControl *s = [[self alloc] initWithFrame:NSZeroRect];
    s.segmentCount = images.count;
    for (NSUInteger i = 0; i < images.count; i++) [s setImage:images[i] forSegment:i];
    s.trackingMode = mode;
    s.target = target;
    s.action = action;
    [s sizeToFit];
    return s;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _segments = [NSMutableArray array];
    return self;
}
- (BNSegment *)_seg:(NSInteger)i { return i >= 0 && i < (NSInteger)_segments.count ? _segments[i] : nil; }
- (NSInteger)segmentCount { return _segments.count; }
- (void)setSegmentCount:(NSInteger)n {
    while ((NSInteger)_segments.count < n) {
        BNSegment *s = [BNSegment new];
        s.enabled = YES;
        s.label = @"";
        [_segments addObject:s];
    }
    while ((NSInteger)_segments.count > n) [_segments removeLastObject];
    self.needsDisplay = YES;
}
- (NSSegmentSwitchTracking)trackingMode { return _tracking; }
- (void)setTrackingMode:(NSSegmentSwitchTracking)m { _tracking = m; }
- (NSSegmentStyle)segmentStyle { return _segmentStyle; }
- (void)setSegmentStyle:(NSSegmentStyle)s { _segmentStyle = s; }
- (NSColor *)selectedSegmentBezelColor { return _selectedTint; }
- (void)setSelectedSegmentBezelColor:(NSColor *)c { _selectedTint = c; }
- (void)setLabel:(NSString *)l forSegment:(NSInteger)i { [self _seg:i].label = l; }
- (NSString *)labelForSegment:(NSInteger)i { return [self _seg:i].label; }
- (void)setImage:(NSImage *)img forSegment:(NSInteger)i { [self _seg:i].image = img; }
- (NSImage *)imageForSegment:(NSInteger)i { return [self _seg:i].image; }
- (void)setImageScaling:(NSImageScaling)s forSegment:(NSInteger)i {}
- (void)setWidth:(CGFloat)w forSegment:(NSInteger)i { [self _seg:i].width = w; }
- (CGFloat)widthForSegment:(NSInteger)i { return [self _seg:i].width; }
- (void)setToolTip:(NSString *)t forSegment:(NSInteger)i { [self _seg:i].toolTip = t; }
- (NSString *)toolTipForSegment:(NSInteger)i { return [self _seg:i].toolTip; }
- (void)setTag:(NSInteger)t forSegment:(NSInteger)i { [self _seg:i].tag = t; }
- (NSInteger)tagForSegment:(NSInteger)i { return [self _seg:i].tag; }
- (void)setMenu:(NSMenu *)m forSegment:(NSInteger)i { [self _seg:i].menu = m; }
- (NSMenu *)menuForSegment:(NSInteger)i { return [self _seg:i].menu; }
- (void)setEnabled:(BOOL)e forSegment:(NSInteger)i { [self _seg:i].enabled = e; }
- (BOOL)isEnabledForSegment:(NSInteger)i { return [self _seg:i].enabled; }
- (void)setSelected:(BOOL)sel forSegment:(NSInteger)i {
    if (sel && _tracking != NSSegmentSwitchTrackingSelectAny)
        for (BNSegment *s in _segments) s.selected = NO;
    [self _seg:i].selected = sel;
    self.needsDisplay = YES;
}
- (BOOL)isSelectedForSegment:(NSInteger)i { return [self _seg:i].selected; }
- (NSInteger)selectedSegment {
    for (NSUInteger i = 0; i < _segments.count; i++)
        if (_segments[i].selected) return i;
    return -1;
}
- (void)setSelectedSegment:(NSInteger)i {
    for (BNSegment *s in _segments) s.selected = NO;
    [self _seg:i].selected = YES;
    self.needsDisplay = YES;
}
- (BOOL)selectSegmentWithTag:(NSInteger)tag {
    for (NSUInteger i = 0; i < _segments.count; i++)
        if (_segments[i].tag == tag) {
            self.selectedSegment = i;
            return YES;
        }
    return NO;
}
- (NSInteger)indexOfSelectedItem { return self.selectedSegment; }
- (BOOL)isFlipped { return YES; }
- (CGFloat)_bn_width:(BNSegment *)s {
    if (s.width > 0) return s.width;
    CGFloat w = s.image ? s.image.size.width : 0;
    if (s.label.length) w += [s.label sizeWithAttributes:@{NSFontAttributeName : self.font}].width + (w ? 4 : 0);
    return w + 16;
}
- (NSSize)intrinsicContentSize {
    CGFloat w = 0;
    for (BNSegment *s in _segments) w += [self _bn_width:s];
    return NSMakeSize(w + 2, 22);
}
- (NSSize)fittingSize { return self.intrinsicContentSize; }
- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat x = 1;
    for (NSUInteger i = 0; i < _segments.count; i++) {
        CGFloat w = [self _bn_width:_segments[i]];
        if (p.x >= x && p.x < x + w && _segments[i].enabled) {
            if (_tracking == NSSegmentSwitchTrackingSelectAny) [self setSelected:!_segments[i].selected forSegment:i];
            else self.selectedSegment = i;
            [self sendAction:self.action to:self.target];
            if (_tracking == NSSegmentSwitchTrackingMomentary) [self setSelected:NO forSegment:i];
            return;
        }
        x += w;
    }
}
- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    [NSColor.controlColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:5 yRadius:5] fill];
    CGFloat x = 1;
    for (BNSegment *s in _segments) {
        CGFloat w = [self _bn_width:s];
        NSRect r = NSMakeRect(x, 1, w, b.size.height - 2);
        if (s.selected) {
            [(_selectedTint ?: NSColor.selectedControlColor) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] fill];
        }
        NSDictionary *attrs = @{NSFontAttributeName : self.font,
                                NSForegroundColorAttributeName : s.enabled ? NSColor.controlTextColor
                                                                           : NSColor.disabledControlTextColor};
        NSSize ts = s.label.length ? [s.label sizeWithAttributes:attrs] : NSZeroSize;
        NSSize is = s.image ? s.image.size : NSZeroSize;
        CGFloat cx = NSMidX(r) - (ts.width + is.width + (ts.width && is.width ? 4 : 0)) / 2;
        if (s.image) {
            [s.image drawInRect:NSMakeRect(cx, NSMidY(r) - is.height / 2, is.width, is.height)];
            cx += is.width + 4;
        }
        if (ts.width) [s.label drawAtPoint:NSMakePoint(cx, NSMidY(r) - ts.height / 2) withAttributes:attrs];
        x += w;
    }
}
@end

/* ---- NSCursor ---- */

@implementation NSCursor {
    NSImage *_image;
    NSPoint _hotSpot;
    NSString *_name;
}
static NSCursor *current_cursor;
static NSMutableArray *cursor_stack;
static NSCursor *named(NSString *name) {
    static NSMutableDictionary *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ all = [NSMutableDictionary dictionary]; });
    @synchronized(all) {
        NSCursor *c = all[name];
        if (!c) {
            c = [[NSCursor alloc] initWithImage:nil hotSpot:NSZeroPoint];
            c->_name = name;
            all[name] = c;
        }
        return c;
    }
}
+ (NSCursor *)arrowCursor { return named(@"arrow"); }
+ (NSCursor *)IBeamCursor { return named(@"IBeam"); }
+ (NSCursor *)IBeamCursorForVerticalLayout { return named(@"IBeamVertical"); }
+ (NSCursor *)pointingHandCursor { return named(@"pointingHand"); }
+ (NSCursor *)closedHandCursor { return named(@"closedHand"); }
+ (NSCursor *)openHandCursor { return named(@"openHand"); }
+ (NSCursor *)resizeLeftCursor { return named(@"resizeLeft"); }
+ (NSCursor *)resizeRightCursor { return named(@"resizeRight"); }
+ (NSCursor *)resizeLeftRightCursor { return named(@"resizeLeftRight"); }
+ (NSCursor *)resizeUpCursor { return named(@"resizeUp"); }
+ (NSCursor *)resizeDownCursor { return named(@"resizeDown"); }
+ (NSCursor *)resizeUpDownCursor { return named(@"resizeUpDown"); }
+ (NSCursor *)crosshairCursor { return named(@"crosshair"); }
+ (NSCursor *)disappearingItemCursor { return named(@"disappearingItem"); }
+ (NSCursor *)operationNotAllowedCursor { return named(@"operationNotAllowed"); }
+ (NSCursor *)dragLinkCursor { return named(@"dragLink"); }
+ (NSCursor *)dragCopyCursor { return named(@"dragCopy"); }
+ (NSCursor *)contextualMenuCursor { return named(@"contextualMenu"); }
+ (NSCursor *)columnResizeCursor { return named(@"columnResize"); }
+ (NSCursor *)rowResizeCursor { return named(@"rowResize"); }
+ (NSCursor *)zoomInCursor { return named(@"zoomIn"); }
+ (NSCursor *)zoomOutCursor { return named(@"zoomOut"); }
+ (NSCursor *)columnResizeCursorInDirections:(NSCursorFrameResizeDirections)d { return named(@"columnResize"); }
+ (NSCursor *)rowResizeCursorInDirections:(NSCursorFrameResizeDirections)d { return named(@"rowResize"); }
+ (NSCursor *)frameResizeCursorFromPosition:(NSCursorFrameResizePosition)p inDirections:(NSCursorFrameResizeDirections)d {
    return named([NSString stringWithFormat:@"frameResize%lu", (unsigned long)p]);
}
+ (NSCursor *)currentCursor { return current_cursor ?: [self arrowCursor]; }
+ (NSCursor *)currentSystemCursor { return [self currentCursor]; }
+ (void)hide {}
+ (void)unhide {}
+ (void)setHiddenUntilMouseMoves:(BOOL)flag {}
+ (void)pop {
    if (cursor_stack.count) {
        current_cursor = cursor_stack.lastObject;
        [cursor_stack removeLastObject];
    }
}
- (instancetype)initWithImage:(NSImage *)image hotSpot:(NSPoint)hotSpot {
    self = [super init];
    _image = image;
    _hotSpot = hotSpot;
    return self;
}
- (NSImage *)image { return _image; }
- (NSPoint)hotSpot { return _hotSpot; }
- (void)set { current_cursor = self; }
- (void)push {
    if (!cursor_stack) cursor_stack = [NSMutableArray array];
    [cursor_stack addObject:[NSCursor currentCursor]];
    current_cursor = self;
}
- (void)pop { [NSCursor pop]; }
- (NSString *)description { return [NSString stringWithFormat:@"<NSCursor %@>", _name ?: @"custom"]; }
@end

/* ---- paragraph styles ---- */

@implementation NSParagraphStyle {
  @protected
    NSTextAlignment _alignment;
    NSLineBreakMode _lineBreakMode;
    CGFloat _lineSpacing, _paragraphSpacing, _paragraphSpacingBefore, _headIndent, _tailIndent, _firstLineHeadIndent,
        _minimumLineHeight, _maximumLineHeight, _lineHeightMultiple, _defaultTabInterval, _hyphenationFactor;
    NSWritingDirection _baseWritingDirection;
    NSArray *_tabStops;
    BOOL _allowsDefaultTighteningForTruncation;
}
+ (NSParagraphStyle *)defaultParagraphStyle {
    static NSParagraphStyle *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[NSParagraphStyle alloc] init]; });
    return s;
}
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(NSString *)language { return NSWritingDirectionLeftToRight; }
- (instancetype)init {
    self = [super init];
    _alignment = NSTextAlignmentNatural;
    _baseWritingDirection = NSWritingDirectionNatural;
    _tabStops = @[];
    _defaultTabInterval = 28;
    return self;
}
#define GET(type, name, ivar) - (type)name { return ivar; }
GET(NSTextAlignment, alignment, _alignment)
GET(NSLineBreakMode, lineBreakMode, _lineBreakMode)
GET(CGFloat, lineSpacing, _lineSpacing)
GET(CGFloat, paragraphSpacing, _paragraphSpacing)
GET(CGFloat, paragraphSpacingBefore, _paragraphSpacingBefore)
GET(CGFloat, headIndent, _headIndent)
GET(CGFloat, tailIndent, _tailIndent)
GET(CGFloat, firstLineHeadIndent, _firstLineHeadIndent)
GET(CGFloat, minimumLineHeight, _minimumLineHeight)
GET(CGFloat, maximumLineHeight, _maximumLineHeight)
GET(CGFloat, lineHeightMultiple, _lineHeightMultiple)
GET(CGFloat, defaultTabInterval, _defaultTabInterval)
GET(float, hyphenationFactor, (float)_hyphenationFactor)
GET(NSWritingDirection, baseWritingDirection, _baseWritingDirection)
GET(NSArray *, tabStops, _tabStops)
GET(BOOL, allowsDefaultTighteningForTruncation, _allowsDefaultTighteningForTruncation)
#undef GET
- (id)copyWithZone:(NSZone *)zone {
    NSParagraphStyle *p = [[NSParagraphStyle alloc] init];
    [p _bn_take:self];
    return p;
}
- (id)mutableCopyWithZone:(NSZone *)zone {
    NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
    [p _bn_take:self];
    return p;
}
- (void)_bn_take:(NSParagraphStyle *)o {
    _alignment = o->_alignment;
    _lineBreakMode = o->_lineBreakMode;
    _lineSpacing = o->_lineSpacing;
    _paragraphSpacing = o->_paragraphSpacing;
    _paragraphSpacingBefore = o->_paragraphSpacingBefore;
    _headIndent = o->_headIndent;
    _tailIndent = o->_tailIndent;
    _firstLineHeadIndent = o->_firstLineHeadIndent;
    _minimumLineHeight = o->_minimumLineHeight;
    _maximumLineHeight = o->_maximumLineHeight;
    _lineHeightMultiple = o->_lineHeightMultiple;
    _defaultTabInterval = o->_defaultTabInterval;
    _hyphenationFactor = o->_hyphenationFactor;
    _baseWritingDirection = o->_baseWritingDirection;
    _tabStops = [o->_tabStops copy];
    _allowsDefaultTighteningForTruncation = o->_allowsDefaultTighteningForTruncation;
}
- (BOOL)isEqual:(id)o {
    if (![o isKindOfClass:[NSParagraphStyle class]]) return NO;
    NSParagraphStyle *p = o;
    return p->_alignment == _alignment && p->_lineBreakMode == _lineBreakMode && p->_lineSpacing == _lineSpacing &&
           p->_paragraphSpacing == _paragraphSpacing && p->_headIndent == _headIndent &&
           p->_tailIndent == _tailIndent && p->_firstLineHeadIndent == _firstLineHeadIndent &&
           p->_minimumLineHeight == _minimumLineHeight && p->_maximumLineHeight == _maximumLineHeight &&
           p->_lineHeightMultiple == _lineHeightMultiple && [p->_tabStops isEqual:_tabStops];
}
- (NSUInteger)hash { return (NSUInteger)_alignment * 31 + (NSUInteger)_lineBreakMode; }
@end

@implementation NSMutableParagraphStyle
#define SET(type, sel, ivar) - (void)sel:(type)v { ivar = v; }
SET(NSTextAlignment, setAlignment, _alignment)
SET(NSLineBreakMode, setLineBreakMode, _lineBreakMode)
SET(CGFloat, setLineSpacing, _lineSpacing)
SET(CGFloat, setParagraphSpacing, _paragraphSpacing)
SET(CGFloat, setParagraphSpacingBefore, _paragraphSpacingBefore)
SET(CGFloat, setHeadIndent, _headIndent)
SET(CGFloat, setTailIndent, _tailIndent)
SET(CGFloat, setFirstLineHeadIndent, _firstLineHeadIndent)
SET(CGFloat, setMinimumLineHeight, _minimumLineHeight)
SET(CGFloat, setMaximumLineHeight, _maximumLineHeight)
SET(CGFloat, setLineHeightMultiple, _lineHeightMultiple)
SET(CGFloat, setDefaultTabInterval, _defaultTabInterval)
SET(NSWritingDirection, setBaseWritingDirection, _baseWritingDirection)
SET(BOOL, setAllowsDefaultTighteningForTruncation, _allowsDefaultTighteningForTruncation)
#undef SET
- (void)setHyphenationFactor:(float)f { _hyphenationFactor = f; }
- (void)setTabStops:(NSArray *)t { _tabStops = [t copy] ?: @[]; }
- (void)setParagraphStyle:(NSParagraphStyle *)p { [self _bn_take:p]; }
@end

/* ---- NSGradient ---- */

@implementation NSGradient {
    NSArray<NSColor *> *_colors;
    NSArray<NSNumber *> *_locations;
}
- (instancetype)initWithStartingColor:(NSColor *)a endingColor:(NSColor *)b {
    return [self initWithColors:@[ a, b ]];
}
- (instancetype)initWithColors:(NSArray<NSColor *> *)colors {
    NSMutableArray *l = [NSMutableArray array];
    for (NSUInteger i = 0; i < colors.count; i++) [l addObject:@(colors.count > 1 ? (double)i / (colors.count - 1) : 0)];
    return [self initWithColors:colors locations:l];
}
- (instancetype)initWithColors:(NSArray<NSColor *> *)colors locations:(NSArray<NSNumber *> *)locations {
    if (colors.count < 1) return nil;
    self = [super init];
    _colors = [colors copy];
    _locations = [locations copy];
    return self;
}
- (instancetype)initWithColorsAndLocations:(NSColor *)first, ... {
    NSMutableArray *c = [NSMutableArray array], *l = [NSMutableArray array];
    va_list ap;
    va_start(ap, first);
    for (NSColor *color = first; color; color = va_arg(ap, NSColor *)) {
        [c addObject:color];
        [l addObject:@(va_arg(ap, double))];
    }
    va_end(ap);
    return [self initWithColors:c locations:l];
}
- (NSInteger)numberOfColorStops { return _colors.count; }
- (void)getColor:(NSColor **)color location:(CGFloat *)location atIndex:(NSInteger)i {
    if (color) *color = _colors[i];
    if (location) *location = _locations[i].doubleValue;
}
- (NSColor *)interpolatedColorAtLocation:(CGFloat)t {
    if (_colors.count == 1 || t <= _locations.firstObject.doubleValue) return _colors.firstObject;
    for (NSUInteger i = 1; i < _colors.count; i++) {
        double a = _locations[i - 1].doubleValue, b = _locations[i].doubleValue;
        if (t <= b) return [_colors[i - 1] blendedColorWithFraction:b > a ? (t - a) / (b - a) : 1 ofColor:_colors[i]];
    }
    return _colors.lastObject;
}
- (CGGradientRef)_bn_cg {
    size_t n = _colors.count;
    CGFloat *comps = calloc(n * 4, sizeof(CGFloat)), *locs = calloc(n, sizeof(CGFloat));
    for (size_t i = 0; i < n; i++) {
        NSColor *c = _colors[i];
        comps[4 * i] = c.redComponent;
        comps[4 * i + 1] = c.greenComponent;
        comps[4 * i + 2] = c.blueComponent;
        comps[4 * i + 3] = c.alphaComponent;
        locs[i] = _locations[i].doubleValue;
    }
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(rgb, comps, locs, n);
    CGColorSpaceRelease(rgb);
    free(comps);
    free(locs);
    return g;
}
- (void)drawFromPoint:(NSPoint)a toPoint:(NSPoint)b options:(NSGradientDrawingOptions)options {
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (!c) return;
    CGGradientRef g = [self _bn_cg];
    CGContextDrawLinearGradient(c, g, a, b, (CGGradientDrawingOptions)options);
    CGGradientRelease(g);
}
- (void)drawInRect:(NSRect)rect angle:(CGFloat)angle {
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (!c) return;
    double r = angle * M_PI / 180, dx = cos(r) * rect.size.width / 2, dy = sin(r) * rect.size.height / 2;
    NSPoint m = NSMakePoint(NSMidX(rect), NSMidY(rect));
    CGContextSaveGState(c);
    CGContextClipToRect(c, rect);
    [self drawFromPoint:NSMakePoint(m.x - dx, m.y - dy) toPoint:NSMakePoint(m.x + dx, m.y + dy)
                options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
    CGContextRestoreGState(c);
}
- (void)drawInBezierPath:(NSBezierPath *)path angle:(CGFloat)angle {
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (!c) return;
    CGContextSaveGState(c);
    [path addClip];
    [self drawInRect:path.bounds angle:angle];
    CGContextRestoreGState(c);
}
- (void)drawInRect:(NSRect)rect relativeCenterPosition:(NSPoint)p {
    CGContextRef c = [NSGraphicsContext currentContext].CGContext;
    if (!c) return;
    NSPoint m = NSMakePoint(NSMidX(rect) + p.x * rect.size.width / 2, NSMidY(rect) + p.y * rect.size.height / 2);
    CGGradientRef g = [self _bn_cg];
    CGContextSaveGState(c);
    CGContextClipToRect(c, rect);
    CGContextDrawRadialGradient(c, g, m, 0, m, hypot(rect.size.width, rect.size.height) / 2, 3);
    CGContextRestoreGState(c);
    CGGradientRelease(g);
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

/* ---- NSSound, haptics ---- */

@implementation NSSound {
    NSString *_name;
    NSURL *_url;
    float _volume;
    BOOL _loops, _playing;
    __weak id<NSSoundDelegate> _delegate;
}
+ (instancetype)soundNamed:(NSSoundName)name {
    NSSound *s = [[self alloc] init];
    s->_name = [name copy];
    s->_volume = 1;
    return s;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url byReference:(BOOL)byRef {
    self = [super init];
    _url = url;
    _volume = 1;
    return self;
}
- (instancetype)initWithContentsOfFile:(NSString *)path byReference:(BOOL)byRef {
    return [self initWithContentsOfURL:[NSURL fileURLWithPath:path] byReference:byRef];
}
- (NSSoundName)name { return _name; }
- (BOOL)setName:(NSSoundName)name {
    _name = [name copy];
    return YES;
}
/* No audio output: playing finishes at once. */
- (BOOL)play {
    _playing = NO;
    id<NSSoundDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(sound:didFinishPlaying:)])
        dispatch_async(dispatch_get_main_queue(), ^{ [d sound:self didFinishPlaying:YES]; });
    return YES;
}
- (BOOL)stop { return YES; }
- (BOOL)pause { return NO; }
- (BOOL)resume { return NO; }
- (BOOL)isPlaying { return _playing; }
- (float)volume { return _volume; }
- (void)setVolume:(float)v { _volume = v; }
- (BOOL)loops { return _loops; }
- (void)setLoops:(BOOL)b { _loops = b; }
- (NSTimeInterval)duration { return 0; }
- (NSTimeInterval)currentTime { return 0; }
- (void)setCurrentTime:(NSTimeInterval)t {}
- (id<NSSoundDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSSoundDelegate>)d { _delegate = d; }
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface BNHapticPerformer : NSObject <NSHapticFeedbackPerformer>
@end
@implementation BNHapticPerformer
- (void)performFeedbackPattern:(NSHapticFeedbackPattern)pattern performanceTime:(NSHapticFeedbackPerformanceTime)time {}
@end
@implementation NSHapticFeedbackManager
+ (id<NSHapticFeedbackPerformer>)defaultPerformer {
    static BNHapticPerformer *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [BNHapticPerformer new]; });
    return p;
}
@end

/* ---- custom accessibility actions ---- */

@implementation NSAccessibilityCustomAction {
    NSString *_name;
    BOOL (^_handler)(void);
    __weak id _target;
    SEL _selector;
}
- (instancetype)initWithName:(NSString *)name handler:(BOOL (^)(void))handler {
    self = [super init];
    _name = [name copy];
    _handler = [handler copy];
    return self;
}
- (instancetype)initWithName:(NSString *)name target:(id)target selector:(SEL)selector {
    self = [super init];
    _name = [name copy];
    _target = target;
    _selector = selector;
    return self;
}
- (NSString *)name { return _name; }
- (void)setName:(NSString *)n { _name = [n copy]; }
- (BOOL (^)(void))handler { return _handler; }
- (void)setHandler:(BOOL (^)(void))h { _handler = [h copy]; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (SEL)selector { return _selector; }
- (void)setSelector:(SEL)s { _selector = s; }
@end

/* ---- click and press gesture recognizers ---- */

@implementation NSGestureRecognizer {
  @protected
    __weak id _target;
    SEL _action;
    __weak NSView *_view;
    NSGestureRecognizerState _state;
    BOOL _enabled;
    __weak id<NSGestureRecognizerDelegate> _delegate;
}
- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super init];
    _target = target;
    _action = action;
    _enabled = YES;
    return self;
}
- (instancetype)init { return [self initWithTarget:nil action:NULL]; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; }
- (void)setAction:(SEL)a { _action = a; }
- (NSView *)view { return _view; }
- (void)_bn_setView:(NSView *)v { _view = v; }
- (NSGestureRecognizerState)state { return _state; }
- (void)setState:(NSGestureRecognizerState)s { _state = s; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)e { _enabled = e; }
- (id<NSGestureRecognizerDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSGestureRecognizerDelegate>)d { _delegate = d; }
- (BOOL)delaysPrimaryMouseButtonEvents { return NO; }
- (void)setDelaysPrimaryMouseButtonEvents:(BOOL)b {}
- (NSPoint)locationInView:(NSView *)view {
    NSEvent *e = [NSApp currentEvent];
    return e ? [view convertPoint:e.locationInWindow fromView:nil] : NSZeroPoint;
}
- (void)_bn_fire {
    id t = _target;
    if (t && _action) ((void (*)(id, SEL, id))objc_msgSend)(t, _action, self);
}
@end
@implementation NSClickGestureRecognizer {
    NSInteger _clicks, _touches;
    NSUInteger _buttonMask;
}
- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithTarget:target action:action];
    _clicks = 1;
    _buttonMask = 1;
    return self;
}
- (NSInteger)numberOfClicksRequired { return _clicks; }
- (void)setNumberOfClicksRequired:(NSInteger)n { _clicks = n; }
- (NSInteger)numberOfTouchesRequired { return 1; }
- (void)setNumberOfTouchesRequired:(NSInteger)n {}
- (NSUInteger)buttonMask { return _buttonMask; }
- (void)setButtonMask:(NSUInteger)m { _buttonMask = m; }
@end
@implementation NSPressGestureRecognizer {
    NSTimeInterval _minimumPressDuration;
    CGFloat _allowableMovement;
}
- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithTarget:target action:action];
    _minimumPressDuration = 0.5;
    _allowableMovement = 10;
    return self;
}
- (NSTimeInterval)minimumPressDuration { return _minimumPressDuration; }
- (void)setMinimumPressDuration:(NSTimeInterval)d { _minimumPressDuration = d; }
- (CGFloat)allowableMovement { return _allowableMovement; }
- (void)setAllowableMovement:(CGFloat)m { _allowableMovement = m; }
- (NSUInteger)buttonMask { return 1; }
- (void)setButtonMask:(NSUInteger)m {}
@end

@implementation NSView (BittenGestures)
- (NSArray<NSGestureRecognizer *> *)gestureRecognizers {
    return [objc_getAssociatedObject(self, @selector(gestureRecognizers)) copy] ?: @[];
}
- (void)setGestureRecognizers:(NSArray<NSGestureRecognizer *> *)g {
    objc_setAssociatedObject(self, @selector(gestureRecognizers), [g mutableCopy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSGestureRecognizer *r in g) [r _bn_setView:self];
}
- (void)addGestureRecognizer:(NSGestureRecognizer *)r {
    NSMutableArray *a = objc_getAssociatedObject(self, @selector(gestureRecognizers));
    if (!a) objc_setAssociatedObject(self, @selector(gestureRecognizers), a = [NSMutableArray array],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (r) [a addObject:r];
    [r _bn_setView:self];
}
- (void)removeGestureRecognizer:(NSGestureRecognizer *)r {
    [objc_getAssociatedObject(self, @selector(gestureRecognizers)) removeObject:r];
    [r _bn_setView:nil];
}
@end
