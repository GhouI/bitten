/* NSScrollView, NSClipView and NSScroller. The clip view's bounds origin
 * is the scroll position; the scroll view tiles the clip view inside its
 * insets and scrolls it with the wheel. Scrollers are overlay style and
 * report the knob position and proportion. */

#import <AppKit/AppKit.h>
#include <math.h>

@implementation NSScroller {
    double _value;
    CGFloat _knobProportion;
    NSScrollerStyle _style;
}
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)size scrollerStyle:(NSScrollerStyle)style {
    return style == NSScrollerStyleOverlay ? 0 : (size == NSControlSizeSmall ? 11 : 15);
}
+ (NSScrollerStyle)preferredScrollerStyle { return NSScrollerStyleOverlay; }
+ (BOOL)isCompatibleWithOverlayScrollers { return YES; }
- (double)doubleValue { return _value; }
- (void)setDoubleValue:(double)v { _value = v < 0 ? 0 : v > 1 ? 1 : v; }
- (CGFloat)knobProportion { return _knobProportion; }
- (void)setKnobProportion:(CGFloat)p { _knobProportion = p; }
- (NSScrollerStyle)scrollerStyle { return _style; }
- (void)setScrollerStyle:(NSScrollerStyle)s { _style = s; }
- (NSScrollerKnobStyle)knobStyle { return NSScrollerKnobStyleDefault; }
- (void)setKnobStyle:(NSScrollerKnobStyle)s {}
@end

@implementation NSClipView {
    BOOL _drawsBackground;
    NSColor *_backgroundColor;
    NSEdgeInsets _contentInsets;
    BOOL _autoInsets;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _drawsBackground = YES;
    _backgroundColor = NSColor.controlBackgroundColor;
    _autoInsets = YES;
    return self;
}
- (NSView *)documentView { return self.subviews.firstObject; }
- (void)setDocumentView:(NSView *)v {
    for (NSView *s in self.subviews) [s removeFromSuperview];
    if (v) [self addSubview:v];
    [self scrollToPoint:NSZeroPoint];
}
- (BOOL)isFlipped { return self.documentView ? self.documentView.isFlipped : NO; }
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)b { _drawsBackground = b; }
- (NSColor *)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(NSColor *)c { _backgroundColor = c; }
- (NSEdgeInsets)contentInsets { return _contentInsets; }
- (void)setContentInsets:(NSEdgeInsets)e { _contentInsets = e; }
- (BOOL)automaticallyAdjustsContentInsets { return _autoInsets; }
- (void)setAutomaticallyAdjustsContentInsets:(BOOL)b { _autoInsets = b; }
- (NSRect)documentRect {
    NSView *d = self.documentView;
    if (!d) return self.bounds;
    NSRect r = d.frame;
    NSSize s = self.bounds.size;
    r.size.width = MAX(r.size.width, s.width);
    r.size.height = MAX(r.size.height, s.height);
    return r;
}
- (NSRect)documentVisibleRect {
    NSView *d = self.documentView;
    return d ? [d convertRect:self.bounds fromView:self] : NSZeroRect;
}
/* Keeps the visible area inside the document. */
- (NSRect)constrainBoundsRect:(NSRect)proposed {
    NSRect doc = self.documentRect;
    proposed.origin.x = MAX(NSMinX(doc), MIN(proposed.origin.x, NSMaxX(doc) - proposed.size.width));
    proposed.origin.y = MAX(NSMinY(doc), MIN(proposed.origin.y, NSMaxY(doc) - proposed.size.height));
    return proposed;
}
- (void)scrollToPoint:(NSPoint)p {
    NSRect b = self.bounds;
    b.origin = p;
    b = [self constrainBoundsRect:b];
    if (NSEqualPoints(b.origin, self.bounds.origin)) return;
    self.bounds = b;
    self.needsDisplay = YES;
    if (self.postsBoundsChangedNotifications)
        [[NSNotificationCenter defaultCenter] postNotificationName:NSViewBoundsDidChangeNotification object:self];
    if ([self.superview isKindOfClass:[NSScrollView class]]) [(NSScrollView *)self.superview reflectScrolledClipView:self];
}
- (void)drawRect:(NSRect)dirty {
    if (!_drawsBackground || !_backgroundColor) return;
    [_backgroundColor setFill];
    NSRectFill(dirty);
}
- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    NSRect b = [self constrainBoundsRect:self.bounds];
    if (!NSEqualRects(b, self.bounds)) self.bounds = b;
}
@end

@implementation NSScrollView {
    NSClipView *_clip;
    NSScroller *_vScroller, *_hScroller;
    BOOL _hasV, _hasH, _autohides;
    NSBorderType _borderType;
    NSScrollerStyle _style;
    NSEdgeInsets _scrollerInsets;
    NSScrollElasticity _vElastic, _hElastic;
    BOOL _predominant, _allowsMagnification;
    CGFloat _magnification, _lineScroll;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _clip = [[NSClipView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    [self addSubview:_clip];
    _vScroller = [[NSScroller alloc] initWithFrame:NSZeroRect];
    _hScroller = [[NSScroller alloc] initWithFrame:NSZeroRect];
    _style = NSScrollerStyleOverlay;
    _magnification = 1;
    _lineScroll = 10;
    _predominant = YES;
    return self;
}
- (NSClipView *)contentView { return _clip; }
- (void)setContentView:(NSClipView *)clip {
    NSView *doc = _clip.documentView;
    [_clip removeFromSuperview];
    _clip = clip;
    if (clip) {
        [self addSubview:clip];
        if (!clip.documentView && doc) clip.documentView = doc;
    }
    [self tile];
}
- (NSView *)documentView { return _clip.documentView; }
- (void)setDocumentView:(NSView *)v {
    _clip.documentView = v;
    [self tile];
}
- (NSSize)contentSize { return _clip.frame.size; }
- (NSRect)documentVisibleRect { return _clip.documentVisibleRect; }
- (NSEdgeInsets)contentInsets { return _clip.contentInsets; }
- (void)setContentInsets:(NSEdgeInsets)e {
    _clip.contentInsets = e;
    [self tile];
}
- (BOOL)automaticallyAdjustsContentInsets { return _clip.automaticallyAdjustsContentInsets; }
- (void)setAutomaticallyAdjustsContentInsets:(BOOL)b { _clip.automaticallyAdjustsContentInsets = b; }
- (NSEdgeInsets)scrollerInsets { return _scrollerInsets; }
- (void)setScrollerInsets:(NSEdgeInsets)e { _scrollerInsets = e; }
- (BOOL)drawsBackground { return _clip.drawsBackground; }
- (void)setDrawsBackground:(BOOL)b { _clip.drawsBackground = b; }
- (NSColor *)backgroundColor { return _clip.backgroundColor; }
- (void)setBackgroundColor:(NSColor *)c { _clip.backgroundColor = c; }
- (NSBorderType)borderType { return _borderType; }
- (void)setBorderType:(NSBorderType)t {
    _borderType = t;
    [self tile];
}
- (BOOL)hasVerticalScroller { return _hasV; }
- (void)setHasVerticalScroller:(BOOL)b { _hasV = b; }
- (BOOL)hasHorizontalScroller { return _hasH; }
- (void)setHasHorizontalScroller:(BOOL)b { _hasH = b; }
- (NSScroller *)verticalScroller { return _hasV ? _vScroller : nil; }
- (void)setVerticalScroller:(NSScroller *)s { _vScroller = s; }
- (NSScroller *)horizontalScroller { return _hasH ? _hScroller : nil; }
- (void)setHorizontalScroller:(NSScroller *)s { _hScroller = s; }
- (BOOL)autohidesScrollers { return _autohides; }
- (void)setAutohidesScrollers:(BOOL)b { _autohides = b; }
- (NSScrollerStyle)scrollerStyle { return _style; }
- (void)setScrollerStyle:(NSScrollerStyle)s {
    _style = s;
    _vScroller.scrollerStyle = s;
    _hScroller.scrollerStyle = s;
    [self tile];
}
- (NSScrollElasticity)verticalScrollElasticity { return _vElastic; }
- (void)setVerticalScrollElasticity:(NSScrollElasticity)e { _vElastic = e; }
- (NSScrollElasticity)horizontalScrollElasticity { return _hElastic; }
- (void)setHorizontalScrollElasticity:(NSScrollElasticity)e { _hElastic = e; }
- (BOOL)usesPredominantAxisScrolling { return _predominant; }
- (void)setUsesPredominantAxisScrolling:(BOOL)b { _predominant = b; }
- (BOOL)allowsMagnification { return _allowsMagnification; }
- (void)setAllowsMagnification:(BOOL)b { _allowsMagnification = b; }
- (CGFloat)magnification { return _magnification; }
- (void)setMagnification:(CGFloat)m { _magnification = m; }
- (CGFloat)lineScroll { return _lineScroll; }
- (void)setLineScroll:(CGFloat)l { _lineScroll = l; }
- (CGFloat)verticalLineScroll { return _lineScroll; }
- (void)setVerticalLineScroll:(CGFloat)l { _lineScroll = l; }
- (CGFloat)horizontalLineScroll { return _lineScroll; }
- (void)setHorizontalLineScroll:(CGFloat)l { _lineScroll = l; }
- (BOOL)isFlipped { return NO; }
- (void)flashScrollers {}
- (void)tile {
    NSRect b = self.bounds;
    CGFloat border = _borderType == NSNoBorder ? 0 : 1;
    NSEdgeInsets e = _clip.contentInsets;
    CGFloat sw = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:_style];
    NSRect r = NSMakeRect(border + e.left, border + e.bottom + (_hasH ? sw : 0),
                          b.size.width - 2 * border - e.left - e.right - (_hasV ? sw : 0),
                          b.size.height - 2 * border - e.top - e.bottom - (_hasH ? sw : 0));
    r.size.width = MAX(0, r.size.width);
    r.size.height = MAX(0, r.size.height);
    _clip.frame = r;
    [self reflectScrolledClipView:_clip];
}
- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [self tile];
}
- (void)reflectScrolledClipView:(NSClipView *)clip {
    NSRect doc = clip.documentRect, vis = clip.bounds;
    CGFloat dh = doc.size.height - vis.size.height, dw = doc.size.width - vis.size.width;
    _vScroller.knobProportion = doc.size.height > 0 ? MIN(1, vis.size.height / doc.size.height) : 1;
    _hScroller.knobProportion = doc.size.width > 0 ? MIN(1, vis.size.width / doc.size.width) : 1;
    double v = dh > 0 ? (vis.origin.y - doc.origin.y) / dh : 0;
    _vScroller.doubleValue = clip.isFlipped ? v : 1 - v;
    _hScroller.doubleValue = dw > 0 ? (vis.origin.x - doc.origin.x) / dw : 0;
}
- (void)scrollWheel:(NSEvent *)event {
    CGFloat dx = event.scrollingDeltaX, dy = event.scrollingDeltaY;
    if (!event.hasPreciseScrollingDeltas) {
        dx *= _lineScroll;
        dy *= _lineScroll;
    }
    if (_predominant) {
        if (fabs(dx) > fabs(dy)) dy = 0;
        else dx = 0;
    }
    if (!_hasH && !_hasV && self.documentView.frame.size.height <= _clip.bounds.size.height &&
        self.documentView.frame.size.width <= _clip.bounds.size.width) {
        [super scrollWheel:event];
        return;
    }
    NSPoint o = _clip.bounds.origin;
    /* Positive deltaY scrolls content down, revealing what is above. */
    o.x -= dx;
    o.y += _clip.isFlipped ? -dy : dy;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSScrollViewWillStartLiveScrollNotification object:self];
    [_clip scrollToPoint:o];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSScrollViewDidLiveScrollNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSScrollViewDidEndLiveScrollNotification object:self];
}
- (void)drawRect:(NSRect)dirty {
    if (_borderType == NSNoBorder) return;
    [NSColor.separatorColor setStroke];
    NSFrameRect(self.bounds);
}
@end

@implementation NSView (BittenScrolling)
- (void)scrollPoint:(NSPoint)p {
    NSClipView *clip = (NSClipView *)self.superview;
    if ([clip isKindOfClass:[NSClipView class]]) [clip scrollToPoint:[self convertPoint:p toView:clip]];
}
- (BOOL)scrollRectToVisible:(NSRect)rect {
    NSClipView *clip = (NSClipView *)self.superview;
    if (![clip isKindOfClass:[NSClipView class]]) return NO;
    NSRect r = [self convertRect:rect toView:clip], b = clip.bounds;
    NSPoint o = b.origin;
    if (NSMinX(r) < NSMinX(b)) o.x = NSMinX(r);
    else if (NSMaxX(r) > NSMaxX(b)) o.x = NSMaxX(r) - b.size.width;
    if (NSMinY(r) < NSMinY(b)) o.y = NSMinY(r);
    else if (NSMaxY(r) > NSMaxY(b)) o.y = NSMaxY(r) - b.size.height;
    if (NSEqualPoints(o, b.origin)) return NO;
    [clip scrollToPoint:o];
    return YES;
}
@end
