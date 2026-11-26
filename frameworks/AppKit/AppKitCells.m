/* Cells. Controls here draw themselves rather than through cells, but
 * programs still reach for a control's cell (or subclass one, through
 * +cellClass) to set alignment, wrapping, fonts and the like, and some draw
 * with a cell directly. A cell holds that state and draws its title and
 * image in a frame. */
#import <AppKit/AppKit.h>
#import <AppKit/AppKitCells.h>
#include <math.h>
#include <objc/message.h>
#include <objc/runtime.h>

@implementation NSCell {
    id _objectValue;
}
@synthesize type = _type, image = _image, font = _font, alignment = _alignment, lineBreakMode = _lineBreakMode,
            wraps = _wraps, scrollable = _scrollable, usesSingleLineMode = _usesSingleLineMode,
            truncatesLastVisibleLine = _truncatesLastVisibleLine, enabled = _enabled, editable = _editable,
            selectable = _selectable, bordered = _bordered, bezeled = _bezeled, highlighted = _highlighted,
            state = _state, tag = _tag, target = _target, action = _action, representedObject = _representedObject,
            controlSize = _controlSize, focusRingType = _focusRingType, controlView = _controlView;

- (instancetype)init {
    if ((self = [super init])) {
        _enabled = YES;
        _alignment = NSTextAlignmentNatural;
        _lineBreakMode = NSLineBreakByWordWrapping;
        _objectValue = @"";
    }
    return self;
}
- (instancetype)initTextCell:(NSString *)string {
    if ((self = [self init])) {
        _type = NSTextCellType;
        _objectValue = [string copy] ?: @"";
    }
    return self;
}
- (instancetype)initImageCell:(NSImage *)image {
    if ((self = [self init])) {
        _type = NSImageCellType;
        _image = image;
        _objectValue = nil;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    NSCell *c = [[[self class] allocWithZone:zone] init];
    c->_type = _type;
    c->_objectValue = [_objectValue copy];
    c->_image = _image;
    c->_font = _font;
    c->_alignment = _alignment;
    c->_lineBreakMode = _lineBreakMode;
    c->_wraps = _wraps;
    c->_enabled = _enabled;
    c->_state = _state;
    c->_tag = _tag;
    c->_target = _target;
    c->_action = _action;
    return c;
}

- (id)objectValue { return _objectValue; }
- (void)setObjectValue:(id)v {
    _objectValue = [v respondsToSelector:@selector(copyWithZone:)] ? [v copy] : v;
    [_controlView setNeedsDisplay:YES];
}
- (NSString *)stringValue {
    id v = _objectValue;
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSAttributedString class]]) return [v string];
    return v ? [v description] : @"";
}
- (void)setStringValue:(NSString *)s { self.objectValue = s ?: @""; }
- (NSAttributedString *)attributedStringValue {
    id v = _objectValue;
    if ([v isKindOfClass:[NSAttributedString class]]) return v;
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    if (_font) attrs[NSFontAttributeName] = _font;
    return [[NSAttributedString alloc] initWithString:self.stringValue attributes:attrs];
}
- (void)setAttributedStringValue:(NSAttributedString *)s { self.objectValue = s; }
- (NSString *)title { return self.stringValue; }
- (void)setTitle:(NSString *)t { self.stringValue = t; }
- (double)doubleValue { return [self.stringValue doubleValue]; }
- (void)setDoubleValue:(double)v { self.objectValue = @(v); }
- (NSInteger)integerValue { return [self.stringValue integerValue]; }
- (void)setIntegerValue:(NSInteger)v { self.objectValue = @(v); }
- (int)intValue { return [self.stringValue intValue]; }
- (void)setIntValue:(int)v { self.objectValue = @(v); }
- (float)floatValue { return [self.stringValue floatValue]; }
- (void)setFloatValue:(float)v { self.objectValue = @(v); }

- (NSFont *)_bn_font { return _font ?: [NSFont systemFontOfSize:[NSFont systemFontSize]]; }
- (NSDictionary *)_bn_textAttributes {
    NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
    p.alignment = _alignment;
    p.lineBreakMode = _lineBreakMode;
    NSColor *color = _enabled ? [NSColor labelColor] : [NSColor disabledControlTextColor];
    if ([self respondsToSelector:@selector(textColor)]) {
        NSColor *c = ((NSColor * (*)(id, SEL))objc_msgSend)(self, @selector(textColor));
        if (c) color = c;
    }
    return @{NSFontAttributeName : [self _bn_font], NSParagraphStyleAttributeName : p,
             NSForegroundColorAttributeName : color};
}
- (NSAttributedString *)_bn_displayString {
    id v = _objectValue;
    if ([v isKindOfClass:[NSAttributedString class]]) return v;
    return [[NSAttributedString alloc] initWithString:self.stringValue attributes:[self _bn_textAttributes]];
}

- (NSSize)cellSize { return [self cellSizeForBounds:NSMakeRect(0, 0, 1e7, 1e7)]; }
- (NSSize)cellSizeForBounds:(NSRect)bounds {
    NSSize s = NSZeroSize;
    if (_type == NSImageCellType || (_image && !self.stringValue.length)) {
        s = _image ? _image.size : NSZeroSize;
    } else {
        s = [[self _bn_displayString] size];
        if (_image) {
            s.width += _image.size.width + 4;
            s.height = MAX(s.height, _image.size.height);
        }
    }
    if (_bordered || _bezeled) {
        s.width += 6;
        s.height += 4;
    }
    s.width = ceil(MIN(s.width, bounds.size.width));
    s.height = ceil(MIN(s.height, bounds.size.height));
    return s;
}
- (NSRect)drawingRectForBounds:(NSRect)rect {
    return (_bordered || _bezeled) ? NSInsetRect(rect, 3, 2) : rect;
}
- (NSRect)titleRectForBounds:(NSRect)rect { return [self drawingRectForBounds:rect]; }
- (NSRect)imageRectForBounds:(NSRect)rect {
    NSRect r = [self drawingRectForBounds:rect];
    if (!_image) return NSMakeRect(NSMidX(r), NSMidY(r), 0, 0);
    NSSize s = _image.size;
    CGFloat k = MIN(1, MIN(r.size.width / MAX(s.width, 1), r.size.height / MAX(s.height, 1)));
    s = NSMakeSize(s.width * k, s.height * k);
    return NSMakeRect(NSMidX(r) - s.width / 2, NSMidY(r) - s.height / 2, s.width, s.height);
}
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (_bordered || _bezeled) {
        [[NSColor colorWithWhite:0 alpha:0.2] setStroke];
        NSBezierPath *p = [NSBezierPath bezierPathWithRect:NSInsetRect(cellFrame, 0.5, 0.5)];
        p.lineWidth = 1;
        [p stroke];
    }
    [self drawInteriorWithFrame:cellFrame inView:controlView];
}
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (_image && (_type == NSImageCellType || !self.stringValue.length)) {
        [_image drawInRect:[self imageRectForBounds:cellFrame]];
        return;
    }
    NSRect r = [self titleRectForBounds:cellFrame];
    [[self _bn_displayString] drawInRect:r];
}
- (void)setNeedsDisplay { [_controlView setNeedsDisplay:YES]; }
@end

@implementation NSActionCell
@end

@implementation NSButtonCell
@synthesize bezelStyle = _bezelStyle, imagePosition = _imagePosition, alternateTitle = _alternateTitle,
            alternateImage = _alternateImage, backgroundColor = _backgroundColor,
            imageDimsWhenDisabled = _imageDimsWhenDisabled,
            showsBorderOnlyWhileMouseInside = _showsBorderOnlyWhileMouseInside;
- (instancetype)init {
    if ((self = [super init])) {
        self.alignment = NSTextAlignmentCenter;
        self.lineBreakMode = NSLineBreakByTruncatingTail;
        _imageDimsWhenDisabled = YES;
    }
    return self;
}
- (instancetype)initTextCell:(NSString *)string {
    if ((self = [super initTextCell:string])) {
        self.alignment = NSTextAlignmentCenter;
        _bezelStyle = NSBezelStylePush;
    }
    return self;
}
- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView {
    if (!self.isBordered) return;
    [(_backgroundColor ?: [NSColor controlColor]) setFill];
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 0.5, 0.5) xRadius:5 yRadius:5];
    [p fill];
    [[NSColor colorWithWhite:0 alpha:0.15] setStroke];
    [p stroke];
}
- (void)drawImage:(NSImage *)image withFrame:(NSRect)frame inView:(NSView *)controlView {
    [image drawInRect:frame];
}
- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)controlView {
    NSSize s = title.size;
    NSRect r = NSMakeRect(frame.origin.x, NSMidY(frame) - s.height / 2, frame.size.width, s.height);
    [title drawInRect:r];
    return r;
}
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    [self drawBezelWithFrame:cellFrame inView:controlView];
    [self drawInteriorWithFrame:cellFrame inView:controlView];
}
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSImage *img = self.state == NSControlStateValueOn && _alternateImage ? _alternateImage : self.image;
    if (img && _imagePosition != NSNoImage) [self drawImage:img withFrame:[self imageRectForBounds:cellFrame] inView:controlView];
    if (self.stringValue.length && _imagePosition != NSImageOnly)
        [self drawTitle:[self _bn_displayString] withFrame:[self titleRectForBounds:cellFrame] inView:controlView];
}
@end

@implementation NSTextFieldCell
@synthesize textColor = _textColor, backgroundColor = _backgroundColor, drawsBackground = _drawsBackground,
            placeholderString = _placeholderString, placeholderAttributedString = _placeholderAttributedString;
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (_drawsBackground && _backgroundColor) {
        [_backgroundColor setFill];
        NSRectFill(cellFrame);
    }
    if (!self.stringValue.length && (_placeholderAttributedString || _placeholderString.length)) {
        NSAttributedString *p = _placeholderAttributedString
            ?: [[NSAttributedString alloc] initWithString:_placeholderString
                                               attributes:@{NSFontAttributeName : [self _bn_font],
                                                            NSForegroundColorAttributeName : [NSColor placeholderTextColor]}];
        [p drawInRect:[self titleRectForBounds:cellFrame]];
        return;
    }
    [super drawInteriorWithFrame:cellFrame inView:controlView];
}
@end

/* ---- controls and their cells ---- */

@implementation NSControl (BittenCells)
static const char kCellKey;
/* The class a control's cell is made from: what the program set for the
 * class (or a superclass), else the usual one for text fields and buttons. */
+ (Class)_bn_cellClass {
    for (Class c = self; c && c != [NSControl class]; c = class_getSuperclass(c)) {
        Class set = objc_getAssociatedObject(c, @selector(cellClass));
        if (set) return set;
    }
    if ([self isSubclassOfClass:[NSTextField class]]) return [NSTextFieldCell class];
    if ([self isSubclassOfClass:[NSButton class]]) return [NSButtonCell class];
    return [NSActionCell class];
}
- (id)cell {
    NSCell *c = objc_getAssociatedObject(self, &kCellKey);
    if (!c) {
        c = [[[[self class] _bn_cellClass] alloc] initTextCell:@""];
        c.controlView = self;
        objc_setAssociatedObject(self, &kCellKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return c;
}
- (void)setCell:(id)cell {
    if ([cell isKindOfClass:[NSCell class]]) ((NSCell *)cell).controlView = self;
    objc_setAssociatedObject(self, &kCellKey, cell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end
