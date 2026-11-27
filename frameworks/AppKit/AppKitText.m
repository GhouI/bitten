/* String drawing (NSString and NSAttributedString, through CoreText) and
 * NSTextField: labels and fields that draw their string in their font and
 * colour, wrap or truncate, and size themselves to it. */

#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <math.h>

/* ---- string drawing ---- */

static CFAttributedStringRef ct_string(NSAttributedString *s) {
    CFMutableAttributedStringRef m = CFAttributedStringCreateMutable(NULL, 0);
    CFAttributedStringReplaceString(m, CFRangeMake(0, 0), (__bridge CFStringRef)s.string);
    NSUInteger i = 0, n = s.length;
    while (i < n) {
        NSRange r;
        NSDictionary *d = [s attributesAtIndex:i effectiveRange:&r];
        NSFont *font = d[NSFontAttributeName] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
        NSColor *color = d[NSForegroundColorAttributeName] ?: NSColor.labelColor;
        CTFontRef ct = CTFontCreateWithName((__bridge CFStringRef)font.fontName, font.pointSize, NULL);
        CFRange cr = CFRangeMake((CFIndex)r.location, (CFIndex)r.length);
        if (ct) {
            CFAttributedStringSetAttribute(m, cr, kCTFontAttributeName, ct);
            CFRelease(ct);
        }
        CFAttributedStringSetAttribute(m, cr, kCTForegroundColorAttributeName, color.CGColor);
        i = NSMaxRange(r);
    }
    return m;
}
static NSFont *first_font(NSAttributedString *s) {
    NSFont *f = s.length ? [s attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] : nil;
    return f ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

/* Splits at newlines, then wraps each paragraph at word boundaries into
 * `width` (no wrapping when width <= 0). */
static NSArray<NSAttributedString *> *lines_of(NSAttributedString *s, CGFloat width) {
    NSMutableArray *out = [NSMutableArray array];
    NSString *str = s.string;
    NSUInteger start = 0, n = str.length;
    while (start <= n) {
        NSRange nl = [str rangeOfString:@"\n" options:0 range:NSMakeRange(start, n - start)];
        NSUInteger end = nl.location == NSNotFound ? n : nl.location;
        NSAttributedString *para = [s attributedSubstringFromRange:NSMakeRange(start, end - start)];
        if (width <= 0 || para.length == 0) {
            [out addObject:para];
        } else {
            NSUInteger ls = 0;
            while (ls < para.length) {
                NSUInteger best = para.length, lastSpace = NSNotFound;
                for (NSUInteger i = ls; i < para.length; i++) {
                    if ([para.string characterAtIndex:i] == ' ') lastSpace = i;
                    CFAttributedStringRef ct = ct_string([para attributedSubstringFromRange:NSMakeRange(ls, i + 1 - ls)]);
                    CTLineRef line = CTLineCreateWithAttributedString(ct);
                    double w = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
                    CFRelease(line);
                    CFRelease(ct);
                    if (w > width && i > ls) {
                        best = lastSpace != NSNotFound && lastSpace > ls ? lastSpace + 1 : i;
                        break;
                    }
                }
                [out addObject:[para attributedSubstringFromRange:NSMakeRange(ls, best - ls)]];
                ls = best;
            }
        }
        if (nl.location == NSNotFound) break;
        start = end + 1;
    }
    return out;
}
static NSSize line_size(NSAttributedString *line, CGFloat *ascent) {
    CFAttributedStringRef ct = ct_string(line);
    CTLineRef l = CTLineCreateWithAttributedString(ct);
    CGFloat a = 0, d = 0, lead = 0;
    double w = CTLineGetTypographicBounds(l, &a, &d, &lead);
    CFRelease(l);
    CFRelease(ct);
    if (a == 0 && d == 0) {
        NSFont *f = first_font(line);
        a = f.ascender;
        d = -f.descender;
    }
    if (ascent) *ascent = a;
    return NSMakeSize(ceil(w), ceil(a + d + lead));
}
static NSSize text_size(NSAttributedString *s, CGFloat width, NSInteger maxLines) {
    NSArray *lines = lines_of(s, width);
    if (maxLines > 0 && (NSInteger)lines.count > maxLines) lines = [lines subarrayWithRange:NSMakeRange(0, maxLines)];
    CGFloat w = 0, h = 0;
    for (NSAttributedString *l in lines) {
        NSSize z = line_size(l, NULL);
        w = MAX(w, z.width);
        h += z.height;
    }
    return NSMakeSize(w, h);
}
/* Draws lines from the top of `rect`, in the current context's
 * orientation. */
static void draw_text(NSAttributedString *s, NSRect rect, NSInteger maxLines, BOOL wrap) {
    NSGraphicsContext *g = [NSGraphicsContext currentContext];
    CGContextRef c = g.CGContext;
    if (!c) return;
    BOOL flipped = g.isFlipped;
    NSArray *lines = lines_of(s, wrap ? rect.size.width : 0);
    if (maxLines > 0 && (NSInteger)lines.count > maxLines) lines = [lines subarrayWithRange:NSMakeRange(0, maxLines)];
    CGFloat y = flipped ? NSMinY(rect) : NSMaxY(rect);
    CGContextSaveGState(c);
    CGContextClipToRect(c, rect);
    for (NSAttributedString *l in lines) {
        CGFloat ascent;
        NSSize z = line_size(l, &ascent);
        CFAttributedStringRef ct = ct_string(l);
        CTLineRef line = CTLineCreateWithAttributedString(ct);
        CGFloat baseline = flipped ? y + ascent : y - ascent;
        CGContextSetTextMatrix(c, flipped ? CGAffineTransformMake(1, 0, 0, -1, 0, 0) : CGAffineTransformIdentity);
        CGContextSetTextPosition(c, NSMinX(rect), baseline);
        CTLineDraw(line, c);
        CFRelease(line);
        CFRelease(ct);
        y += flipped ? z.height : -z.height;
    }
    CGContextRestoreGState(c);
}

@implementation NSAttributedString (NSStringDrawing)
- (NSSize)size { return text_size(self, 0, 0); }
- (void)drawAtPoint:(NSPoint)p {
    NSSize s = self.size;
    BOOL flipped = [NSGraphicsContext currentContext].isFlipped;
    draw_text(self, NSMakeRect(p.x, flipped ? p.y : p.y, s.width + 1, s.height), 0, NO);
}
- (void)drawInRect:(NSRect)r { draw_text(self, r, 0, YES); }
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options context:(id)context {
    NSSize s = text_size(self, (options & NSStringDrawingUsesLineFragmentOrigin) ? size.width : 0, 0);
    return NSMakeRect(0, 0, s.width, s.height);
}
@end

@implementation NSString (NSStringDrawing)
- (NSSize)sizeWithAttributes:(NSDictionary *)attrs {
    return [[NSAttributedString alloc] initWithString:self attributes:attrs].size;
}
- (void)drawAtPoint:(NSPoint)p withAttributes:(NSDictionary *)attrs {
    [[[NSAttributedString alloc] initWithString:self attributes:attrs] drawAtPoint:p];
}
- (void)drawInRect:(NSRect)r withAttributes:(NSDictionary *)attrs {
    [[[NSAttributedString alloc] initWithString:self attributes:attrs] drawInRect:r];
}
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options attributes:(NSDictionary *)attrs
                       context:(id)context {
    return [[[NSAttributedString alloc] initWithString:self attributes:attrs] boundingRectWithSize:size
                                                                                             options:options
                                                                                             context:context];
}
@end

/* ---- NSControl state shared by its subclasses ---- */

@implementation NSControl (BittenText)
- (NSTextAlignment)alignment { return [objc_getAssociatedObject(self, @selector(alignment)) integerValue]; }
- (void)setAlignment:(NSTextAlignment)a {
    objc_setAssociatedObject(self, @selector(alignment), @(a), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.needsDisplay = YES;
}
- (NSLineBreakMode)lineBreakMode {
    NSNumber *n = objc_getAssociatedObject(self, @selector(lineBreakMode));
    return n ? n.integerValue : NSLineBreakByWordWrapping;
}
- (void)setLineBreakMode:(NSLineBreakMode)m {
    objc_setAssociatedObject(self, @selector(lineBreakMode), @(m), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSControlSize)controlSize { return [objc_getAssociatedObject(self, @selector(controlSize)) integerValue]; }
- (void)setControlSize:(NSControlSize)s {
    objc_setAssociatedObject(self, @selector(controlSize), @(s), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)isHighlighted { return [objc_getAssociatedObject(self, @selector(isHighlighted)) boolValue]; }
- (void)setHighlighted:(BOOL)h {
    objc_setAssociatedObject(self, @selector(isHighlighted), @(h), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSInteger)tag { return [objc_getAssociatedObject(self, @selector(tag)) integerValue]; }
- (void)setTag:(NSInteger)t { objc_setAssociatedObject(self, @selector(tag), @(t), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)objectValue { return self.stringValue; }
- (void)setObjectValue:(id)v {
    self.stringValue = [v isKindOfClass:[NSString class]] ? v : [v description] ?: @"";
}
- (NSAttributedString *)attributedStringValue {
    return [[NSAttributedString alloc] initWithString:self.stringValue attributes:@{NSFontAttributeName : self.font}];
}
- (void)setAttributedStringValue:(NSAttributedString *)a { self.stringValue = a.string ?: @""; }
- (BOOL)sendAction:(SEL)action to:(id)target {
    return action ? [NSApp sendAction:action to:target from:self] : NO;
}
- (void)sizeToFit {
    NSSize s = self.fittingSize;
    NSRect f = self.frame;
    f.size = s;
    self.frame = f;
}
- (NSText *)currentEditor { return nil; }
- (BOOL)refusesFirstResponder { return [objc_getAssociatedObject(self, @selector(refusesFirstResponder)) boolValue]; }
- (void)setRefusesFirstResponder:(BOOL)b {
    objc_setAssociatedObject(self, @selector(refusesFirstResponder), @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

@implementation NSView (BittenLayoutPriority)
- (NSLayoutPriority)contentHuggingPriorityForOrientation:(NSLayoutConstraintOrientation)o {
    NSNumber *n = objc_getAssociatedObject(self, o ? @selector(setContentHuggingPriority:forOrientation:)
                                                   : @selector(contentHuggingPriorityForOrientation:));
    return n ? n.floatValue : 250;
}
- (void)setContentHuggingPriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o {
    objc_setAssociatedObject(self, o ? @selector(setContentHuggingPriority:forOrientation:)
                                     : @selector(contentHuggingPriorityForOrientation:),
                             @(p), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSLayoutPriority)contentCompressionResistancePriorityForOrientation:(NSLayoutConstraintOrientation)o {
    NSNumber *n = objc_getAssociatedObject(self, o ? @selector(setContentCompressionResistancePriority:forOrientation:)
                                                   : @selector(contentCompressionResistancePriorityForOrientation:));
    return n ? n.floatValue : 750;
}
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o {
    objc_setAssociatedObject(self, o ? @selector(setContentCompressionResistancePriority:forOrientation:)
                                     : @selector(contentCompressionResistancePriorityForOrientation:),
                             @(p), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* ---- NSTextField ---- */

@implementation NSTextField {
    NSColor *_textColor, *_backgroundColor;
    BOOL _editable, _selectable, _bordered, _bezeled, _drawsBackground, _singleLine, _truncatesLast, _wraps;
    NSInteger _maxLines;
    NSString *_placeholder;
    NSAttributedString *_placeholderAttributed, *_attributed;
    CGFloat _preferredMaxWidth;
    NSTextFieldBezelStyle _bezelStyle;
    __weak id<NSTextFieldDelegate> _delegate;
}
+ (instancetype)labelWithString:(NSString *)s {
    NSTextField *t = [[self alloc] initWithFrame:NSZeroRect];
    t.stringValue = s ?: @"";
    t.editable = NO;
    t.selectable = NO;
    t.bezeled = NO;
    t.bordered = NO;
    t.drawsBackground = NO;
    t.lineBreakMode = NSLineBreakByClipping;
    t.maximumNumberOfLines = 1;
    [t sizeToFit];
    return t;
}
+ (instancetype)wrappingLabelWithString:(NSString *)s {
    NSTextField *t = [self labelWithString:s];
    t.lineBreakMode = NSLineBreakByWordWrapping;
    t.maximumNumberOfLines = 0;
    t.selectable = YES;
    return t;
}
+ (instancetype)labelWithAttributedString:(NSAttributedString *)a {
    NSTextField *t = [self labelWithString:a.string];
    t.attributedStringValue = a;
    [t sizeToFit];
    return t;
}
+ (instancetype)textFieldWithString:(NSString *)s {
    NSTextField *t = [[self alloc] initWithFrame:NSZeroRect];
    t.stringValue = s ?: @"";
    [t sizeToFit];
    return t;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    /* bezeled, not bordered: the two are exclusive, as in AppKit */
    _editable = _selectable = _bezeled = _drawsBackground = YES;
    _backgroundColor = NSColor.textBackgroundColor;
    _wraps = YES;
    return self;
}
- (NSColor *)textColor { return _textColor ?: NSColor.labelColor; }
- (void)setTextColor:(NSColor *)c {
    _textColor = c;
    self.needsDisplay = YES;
}
- (NSColor *)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(NSColor *)c { _backgroundColor = c; }
- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)b { _editable = b; }
- (BOOL)isSelectable { return _selectable; }
- (void)setSelectable:(BOOL)b { _selectable = b; }
- (BOOL)isBordered { return _bordered; }
- (void)setBordered:(BOOL)b {
    _bordered = b;
    if (b) _bezeled = NO;
    self.needsDisplay = YES;
}
- (BOOL)isBezeled { return _bezeled; }
- (void)setBezeled:(BOOL)b {
    _bezeled = b;
    if (b) _bordered = NO;
    self.needsDisplay = YES;
}
- (NSTextFieldBezelStyle)bezelStyle { return _bezelStyle; }
- (void)setBezelStyle:(NSTextFieldBezelStyle)s { _bezelStyle = s; }
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)b { _drawsBackground = b; }
- (NSInteger)maximumNumberOfLines { return _maxLines; }
- (void)setMaximumNumberOfLines:(NSInteger)n { _maxLines = n; }
- (BOOL)usesSingleLineMode { return _singleLine; }
- (void)setUsesSingleLineMode:(BOOL)b { _singleLine = b; }
- (BOOL)truncatesLastVisibleLine { return _truncatesLast; }
- (void)setTruncatesLastVisibleLine:(BOOL)b { _truncatesLast = b; }
- (BOOL)wraps { return _wraps; }
- (void)setWraps:(BOOL)b { _wraps = b; }
- (void)setScrollable:(BOOL)b {}
- (void)setAllowsDefaultTighteningForTruncation:(BOOL)b {}
- (void)setImportsGraphics:(BOOL)b {}
- (void)setAllowsEditingTextAttributes:(BOOL)b {}
- (NSString *)placeholderString { return _placeholder; }
- (void)setPlaceholderString:(NSString *)s { _placeholder = [s copy]; }
- (NSAttributedString *)placeholderAttributedString { return _placeholderAttributed; }
- (void)setPlaceholderAttributedString:(NSAttributedString *)a { _placeholderAttributed = [a copy]; }
- (CGFloat)preferredMaxLayoutWidth { return _preferredMaxWidth; }
- (void)setPreferredMaxLayoutWidth:(CGFloat)w { _preferredMaxWidth = w; }
- (id<NSTextFieldDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSTextFieldDelegate>)d { _delegate = d; }
- (void)setStringValue:(NSString *)s {
    _attributed = nil;
    [super setStringValue:s];
}
- (NSAttributedString *)attributedStringValue {
    return _attributed ?: [[NSAttributedString alloc] initWithString:self.stringValue
                                                          attributes:@{NSFontAttributeName : self.font,
                                                                       NSForegroundColorAttributeName : self.textColor}];
}
- (void)setAttributedStringValue:(NSAttributedString *)a {
    [super setStringValue:a.string ?: @""];
    _attributed = [a copy];
    self.needsDisplay = YES;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return _editable || _selectable; }
- (NSEdgeInsets)_bn_insets {
    return (_bezeled || _bordered) ? NSEdgeInsetsMake(3, 4, 3, 4) : NSEdgeInsetsMake(0, 2, 0, 2);
}
- (BOOL)_bn_wraps { return !_singleLine && _maxLines != 1 && self.lineBreakMode == NSLineBreakByWordWrapping; }
- (NSSize)intrinsicContentSize {
    NSEdgeInsets e = self._bn_insets;
    CGFloat w = self._bn_wraps && _preferredMaxWidth > 0 ? _preferredMaxWidth - e.left - e.right : 0;
    NSAttributedString *a = self.attributedStringValue;
    if (!a.length && _placeholder) a = [[NSAttributedString alloc] initWithString:_placeholder
                                                                       attributes:@{NSFontAttributeName : self.font}];
    NSSize s = text_size(a, w, _maxLines);
    if (s.height == 0) s.height = ceil(self.font.ascender - self.font.descender);
    return NSMakeSize(s.width + e.left + e.right, s.height + e.top + e.bottom);
}
- (NSSize)fittingSize { return self.intrinsicContentSize; }
- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    if (_drawsBackground && _backgroundColor) {
        [_backgroundColor setFill];
        NSRectFill(b);
    }
    if (_bezeled || _bordered) {
        [NSColor.separatorColor setStroke];
        NSFrameRect(b);
    }
    NSEdgeInsets e = self._bn_insets;
    NSRect r = NSMakeRect(e.left, e.top, b.size.width - e.left - e.right, b.size.height - e.top - e.bottom);
    NSAttributedString *a = self.attributedStringValue;
    if (!a.length) {
        a = _placeholderAttributed;
        if (!a && _placeholder)
            a = [[NSAttributedString alloc] initWithString:_placeholder
                                                attributes:@{NSFontAttributeName : self.font,
                                                             NSForegroundColorAttributeName : NSColor.placeholderTextColor}];
    }
    if (!a.length) return;
    NSSize s = text_size(a, self._bn_wraps ? r.size.width : 0, _maxLines);
    NSTextAlignment al = self.alignment;
    if (al == NSTextAlignmentCenter) r.origin.x += MAX(0, (r.size.width - s.width) / 2);
    else if (al == NSTextAlignmentRight) r.origin.x += MAX(0, r.size.width - s.width);
    draw_text(a, r, _maxLines, self._bn_wraps);
}
@end
