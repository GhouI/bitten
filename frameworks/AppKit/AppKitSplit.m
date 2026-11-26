/* Split views: NSSplitView places its panes along one axis with dividers
 * between them, resizes them by holding priority when it changes size,
 * moves dividers when dragged (collapsing panes that may collapse), and
 * saves the arrangement under its autosave name. NSSplitViewController
 * keeps a split view of its items' views and is its delegate, applying the
 * items' thickness limits, collapse rules and behaviours.
 *
 * The panes keep frames the split view sets (they translate their
 * autoresizing masks); when the split view gets a new size from Auto Layout
 * it rearranges them, and the layout pass solves again for what is inside
 * them (bn_layout_note_rearranged). */
#import <AppKit/AppKit.h>
#import <AppKit/AppKitSplit.h>
#include <math.h>
#include <objc/runtime.h>

NSNotificationName const NSSplitViewWillResizeSubviewsNotification = @"NSSplitViewWillResizeSubviewsNotification";
NSNotificationName const NSSplitViewDidResizeSubviewsNotification = @"NSSplitViewDidResizeSubviewsNotification";
const CGFloat NSSplitViewItemUnspecifiedDimension = -1;
const CGFloat NSSplitViewControllerAutomaticDimension = -1;

extern void bn_layout_note_rearranged(void);

@interface NSSplitViewItem (BNPrivate)
- (void)_bn_setController:(NSSplitViewController *)c;
- (CGFloat)_bn_min;
- (CGFloat)_bn_max;
- (void)_bn_noteCollapsed:(BOOL)c;
@end

@interface NSSplitView (BNPrivate)
- (void)_bn_setPane:(NSView *)pane collapsed:(BOOL)collapse;
- (void)_bn_fit;
@end

@interface NSSplitViewController (BNPrivate)
- (nullable NSSplitViewItem *)_bn_itemForPane:(NSView *)pane;
@end

/* ---- the split view ---- */

@implementation NSSplitView {
    BOOL _vertical;
    NSSplitViewDividerStyle _style;
    NSString *_autosaveName;
    __weak id<NSSplitViewDelegate> _delegate;
    BOOL _arrangesAll;
    NSMutableArray<NSView *> *_arranged;      /* when not arranging all subviews */
    NSHashTable<NSView *> *_collapsed;
    NSMapTable<NSView *, NSNumber *> *_holding, *_expanded;
    NSInteger _drag;
    CGFloat _dragOffset;
    BOOL _placing, _restored, _needsFit;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _style = NSSplitViewDividerStyleThick;
        _arrangesAll = YES;
        _arranged = [NSMutableArray array];
        _collapsed = [NSHashTable weakObjectsHashTable];
        _holding = [NSMapTable weakToStrongObjectsMapTable];
        _expanded = [NSMapTable weakToStrongObjectsMapTable];
        _drag = -1;
    }
    return self;
}
- (BOOL)isFlipped { return YES; }

- (BOOL)isVertical { return _vertical; }
- (void)setVertical:(BOOL)v {
    _vertical = v;
    [self adjustSubviews];
}
- (NSSplitViewDividerStyle)dividerStyle { return _style; }
- (void)setDividerStyle:(NSSplitViewDividerStyle)s {
    _style = s;
    [self _bn_fit];
}
- (id<NSSplitViewDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSSplitViewDelegate>)d { _delegate = d; }
- (CGFloat)dividerThickness {
    switch (_style) {
    case NSSplitViewDividerStyleThin: return 1;
    case NSSplitViewDividerStylePaneSplitter: return 10;
    default: return 9;
    }
}
- (NSColor *)dividerColor {
    return _style == NSSplitViewDividerStyleThin ? [NSColor separatorColor] : [NSColor gridColor];
}

/* ---- panes ---- */

- (BOOL)arrangesAllSubviews { return _arrangesAll; }
- (void)setArrangesAllSubviews:(BOOL)b {
    if (b == _arrangesAll) return;
    if (!b) { [_arranged removeAllObjects]; [_arranged addObjectsFromArray:self.subviews]; }
    _arrangesAll = b;
    [self _bn_fit];
}
- (NSArray *)arrangedSubviews {
    if (!_arrangesAll) return [_arranged copy];
    return self.subviews;
}
- (void)_bn_adopt:(NSView *)v {
    v.translatesAutoresizingMaskIntoConstraints = YES;
    v.autoresizingMask = NSViewNotSizable;
}
- (void)addSubview:(NSView *)v {
    [super addSubview:v];
    if (_arrangesAll && v) {
        [self _bn_adopt:v];
        [self _bn_setNeedsFit];
    }
}
- (void)addArrangedSubview:(NSView *)v { [self insertArrangedSubview:v atIndex:(NSInteger)self.arrangedSubviews.count]; }
- (void)insertArrangedSubview:(NSView *)v atIndex:(NSInteger)i {
    if (!v) return;
    NSArray *cur = self.arrangedSubviews;
    if (i < 0 || (NSUInteger)i > cur.count) i = (NSInteger)cur.count;
    if (_arrangesAll) {
        NSView *after = (NSUInteger)i < cur.count ? cur[(NSUInteger)i] : nil;
        if (after) [super addSubview:v positioned:NSWindowBelow relativeTo:after];
        else [super addSubview:v];
    } else {
        [_arranged removeObjectIdenticalTo:v];
        [_arranged insertObject:v atIndex:MIN((NSUInteger)i, _arranged.count)];
        if (v.superview != self) [super addSubview:v];
    }
    [self _bn_adopt:v];
    [self _bn_setNeedsFit];
}
- (void)removeArrangedSubview:(NSView *)v {
    if (_arrangesAll) [v removeFromSuperview];
    else [_arranged removeObjectIdenticalTo:v];
    [self _bn_setNeedsFit];
}
- (void)willRemoveSubview:(NSView *)v { [_arranged removeObjectIdenticalTo:v]; }

- (NSLayoutPriority)holdingPriorityForSubviewAtIndex:(NSInteger)i {
    NSArray *a = self.arrangedSubviews;
    if (i < 0 || (NSUInteger)i >= a.count) return NSLayoutPriorityDefaultLow;
    NSNumber *n = [_holding objectForKey:a[(NSUInteger)i]];
    return n ? n.floatValue : NSLayoutPriorityDefaultLow;
}
- (void)setHoldingPriority:(NSLayoutPriority)p forSubviewAtIndex:(NSInteger)i {
    NSArray *a = self.arrangedSubviews;
    if (i >= 0 && (NSUInteger)i < a.count) [_holding setObject:@(p) forKey:a[(NSUInteger)i]];
}
- (NSLayoutPriority)_bn_holding:(NSView *)v {
    NSNumber *n = [_holding objectForKey:v];
    return n ? n.floatValue : NSLayoutPriorityDefaultLow;
}

- (BOOL)isSubviewCollapsed:(NSView *)v { return [_collapsed containsObject:v]; }
- (BOOL)_bn_out:(NSView *)v { return v.isHidden || [_collapsed containsObject:v]; }

/* ---- geometry ---- */

- (CGFloat)_bn_length { return _vertical ? self.bounds.size.width : self.bounds.size.height; }
- (CGFloat)_bn_thick:(NSView *)v {
    if ([self _bn_out:v]) return 0;
    return _vertical ? v.frame.size.width : v.frame.size.height;
}
- (CGFloat)_bn_start:(NSView *)v { return _vertical ? v.frame.origin.x : v.frame.origin.y; }
- (BOOL)_bn_dividerHidden:(NSInteger)i {
    id<NSSplitViewDelegate> d = _delegate;
    return [d respondsToSelector:@selector(splitView:shouldHideDividerAtIndex:)] &&
           [d splitView:self shouldHideDividerAtIndex:i];
}
- (CGFloat)_bn_divider:(NSInteger)i { return [self _bn_dividerHidden:i] ? 0 : self.dividerThickness; }
- (CGFloat)_bn_dividersTotal {
    CGFloat t = 0;
    NSInteger n = (NSInteger)self.arrangedSubviews.count;
    for (NSInteger i = 0; i + 1 < n; i++) t += [self _bn_divider:i];
    return t;
}
- (CGFloat)_bn_minOf:(NSView *)v {
    NSSplitViewItem *item = [self _bn_item:v];
    return item ? [item _bn_min] : 0;
}
- (CGFloat)_bn_maxOf:(NSView *)v {
    NSSplitViewItem *item = [self _bn_item:v];
    return item ? [item _bn_max] : INFINITY;
}
- (NSSplitViewItem *)_bn_item:(NSView *)v {
    id d = _delegate;
    return [d isKindOfClass:[NSSplitViewController class]] ? [(NSSplitViewController *)d _bn_itemForPane:v] : nil;
}

/* Sets the panes' frames from their thicknesses, one after another. */
- (void)_bn_place:(NSArray<NSNumber *> *)sizes {
    NSArray<NSView *> *panes = self.arrangedSubviews;
    NSRect b = self.bounds;
    CGFloat pos = 0;
    _placing = YES;
    BOOL moved = NO;
    for (NSUInteger i = 0; i < panes.count; i++) {
        NSView *v = panes[i];
        CGFloat s = [self _bn_out:v] ? 0 : fmax(0, sizes[i].doubleValue);
        NSRect f = _vertical ? NSMakeRect(b.origin.x + pos, b.origin.y, s, b.size.height)
                             : NSMakeRect(b.origin.x, b.origin.y + pos, b.size.width, s);
        if ([self _bn_out:v]) {
            /* collapsed panes keep their size, out of sight */
            NSRect o = v.frame;
            if (_vertical) f.size.width = o.size.width; else f.size.height = o.size.height;
        }
        if (!NSEqualRects(f, v.frame)) {
            v.frame = f;
            v.needsLayout = YES;
            moved = YES;
        }
        pos += s + ((NSInteger)i + 1 < (NSInteger)panes.count ? [self _bn_divider:(NSInteger)i] : 0);
    }
    _placing = NO;
    if (moved) bn_layout_note_rearranged();
    self.needsDisplay = YES;
}

- (NSMutableArray<NSNumber *> *)_bn_sizes {
    NSMutableArray *s = [NSMutableArray array];
    for (NSView *v in self.arrangedSubviews) [s addObject:@([self _bn_thick:v])];
    return s;
}

/* Grows or shrinks the panes by delta, those holding least first, within
 * their limits. */
- (void)_bn_give:(CGFloat)delta to:(NSMutableArray<NSNumber *> *)sizes except:(NSView *)skip {
    NSArray<NSView *> *panes = self.arrangedSubviews;
    id<NSSplitViewDelegate> d = _delegate;
    NSMutableArray<NSNumber *> *prios = [NSMutableArray array];
    for (NSView *v in panes) {
        if ([self _bn_out:v] || v == skip) continue;
        if ([d respondsToSelector:@selector(splitView:shouldAdjustSizeOfSubview:)] &&
            ![d splitView:self shouldAdjustSizeOfSubview:v])
            continue;
        NSNumber *p = @([self _bn_holding:v]);
        if (![prios containsObject:p]) [prios addObject:p];
    }
    [prios sortUsingComparator:^NSComparisonResult(NSNumber *x, NSNumber *y) { return [x compare:y]; }];
    for (NSNumber *p in prios) {
        for (int round = 0; round < 8 && fabs(delta) > 0.001; round++) {
            NSMutableArray<NSNumber *> *open = [NSMutableArray array];
            for (NSUInteger i = 0; i < panes.count; i++) {
                NSView *v = panes[i];
                if ([self _bn_out:v] || v == skip || [self _bn_holding:v] != p.floatValue) continue;
                if ([d respondsToSelector:@selector(splitView:shouldAdjustSizeOfSubview:)] &&
                    ![d splitView:self shouldAdjustSizeOfSubview:v])
                    continue;
                CGFloat s = sizes[i].doubleValue;
                if ((delta > 0 && s < [self _bn_maxOf:v]) || (delta < 0 && s > [self _bn_minOf:v])) [open addObject:@(i)];
            }
            if (!open.count) break;
            CGFloat each = delta / open.count;
            for (NSNumber *n in open) {
                NSUInteger i = n.unsignedIntegerValue;
                NSView *v = panes[i];
                CGFloat s = sizes[i].doubleValue;
                CGFloat t = fmin(fmax(s + each, [self _bn_minOf:v]), [self _bn_maxOf:v]);
                sizes[i] = @(t);
                delta -= t - s;
            }
        }
    }
    /* Whatever is left (every pane at its limit) goes to the last pane. */
    if (fabs(delta) > 0.001) {
        for (NSInteger i = (NSInteger)panes.count - 1; i >= 0; i--)
            if (![self _bn_out:panes[(NSUInteger)i]] && panes[(NSUInteger)i] != skip) {
                sizes[(NSUInteger)i] = @(fmax(0, sizes[(NSUInteger)i].doubleValue + delta));
                break;
            }
    }
}

/* Panes added or removed: they are fitted before the next layout pass
 * (or anything that needs their places). */
- (void)_bn_setNeedsFit {
    _needsFit = YES;
    self.needsUpdateConstraints = YES;
}
- (void)_bn_fitIfNeeded {
    if (_needsFit) [self _bn_fit];
}
- (void)updateConstraints {
    [self _bn_fitIfNeeded];
    [super updateConstraints];
}

/* Makes the panes fill the view, by holding priority. */
- (void)_bn_fit {
    if (_placing) return;
    _needsFit = NO;
    CGFloat len = [self _bn_length];
    if (len <= 0 || !self.arrangedSubviews.count) return;
    if (!_restored && _autosaveName) [self _bn_restore];
    NSMutableArray<NSNumber *> *sizes = [self _bn_sizes];
    CGFloat total = [self _bn_dividersTotal];
    for (NSNumber *n in sizes) total += n.doubleValue;
    [self _bn_give:len - total to:sizes except:nil];
    [self _bn_place:sizes];
}

- (void)adjustSubviews {
    _needsFit = NO;
    CGFloat len = [self _bn_length];
    NSMutableArray<NSNumber *> *sizes = [self _bn_sizes];
    CGFloat sum = 0;
    NSUInteger visible = 0;
    for (NSUInteger i = 0; i < sizes.count; i++) {
        sum += sizes[i].doubleValue;
        if (![self _bn_out:self.arrangedSubviews[i]]) visible++;
    }
    CGFloat avail = fmax(0, len - [self _bn_dividersTotal]);
    for (NSUInteger i = 0; i < sizes.count; i++) {
        if ([self _bn_out:self.arrangedSubviews[i]]) continue;
        sizes[i] = @(sum > 0 ? sizes[i].doubleValue * avail / sum : avail / MAX(visible, 1u));
    }
    [self _bn_place:sizes];
}

- (void)resizeSubviewsWithOldSize:(NSSize)old {
    id<NSSplitViewDelegate> d = _delegate;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSSplitViewWillResizeSubviewsNotification object:self];
    if ([d respondsToSelector:@selector(splitView:resizeSubviewsWithOldSize:)])
        [d splitView:self resizeSubviewsWithOldSize:old];
    else
        [self _bn_fit];
    [self _bn_didResize];
}
- (void)_bn_didResize {
    NSNotification *n = [NSNotification notificationWithName:NSSplitViewDidResizeSubviewsNotification object:self];
    id<NSSplitViewDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(splitViewDidResizeSubviews:)]) [d splitViewDidResizeSubviews:n];
    [[NSNotificationCenter defaultCenter] postNotification:n];
    [self _bn_save];
}

/* Resizing the split view resizes its panes: NSView's setFrameSize: calls
 * resizeSubviewsWithOldSize:, overridden above. */

/* ---- dividers ---- */

- (CGFloat)minPossiblePositionOfDividerAtIndex:(NSInteger)i {
    NSArray *panes = self.arrangedSubviews;
    if (i < 0 || (NSUInteger)i + 1 >= panes.count) return 0;
    return [self _bn_dividerStart:i] - [self _bn_thick:panes[(NSUInteger)i]];
}
- (CGFloat)maxPossiblePositionOfDividerAtIndex:(NSInteger)i {
    NSArray *panes = self.arrangedSubviews;
    if (i < 0 || (NSUInteger)i + 1 >= panes.count) return 0;
    return [self _bn_dividerStart:i] + [self _bn_thick:panes[(NSUInteger)i + 1]];
}
/* Where divider i begins: after pane i. */
- (CGFloat)_bn_dividerStart:(NSInteger)i {
    NSArray *panes = self.arrangedSubviews;
    CGFloat pos = 0;
    for (NSInteger k = 0; k <= i && (NSUInteger)k < panes.count; k++) {
        pos += [self _bn_thick:panes[(NSUInteger)k]];
        if (k < i) pos += [self _bn_divider:k];
    }
    return pos;
}
- (NSRect)_bn_dividerRect:(NSInteger)i {
    CGFloat s = [self _bn_dividerStart:i], t = [self _bn_divider:i];
    NSRect b = self.bounds;
    return _vertical ? NSMakeRect(b.origin.x + s, b.origin.y, t, b.size.height)
                     : NSMakeRect(b.origin.x, b.origin.y + s, b.size.width, t);
}

- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)i { [self _bn_move:i to:position dragging:NO]; }

- (void)_bn_move:(NSInteger)i to:(CGFloat)position dragging:(BOOL)dragging {
    [self _bn_fitIfNeeded];
    NSArray<NSView *> *panes = self.arrangedSubviews;
    if (i < 0 || (NSUInteger)i + 1 >= panes.count) return;
    NSView *a = panes[(NSUInteger)i], *b = panes[(NSUInteger)i + 1];
    id<NSSplitViewDelegate> d = _delegate;
    CGFloat div = [self _bn_divider:i];
    CGFloat start = [self _bn_dividerStart:i] - [self _bn_thick:a];          /* pane a's start */
    CGFloat end = [self _bn_dividerStart:i] + div + [self _bn_thick:b];      /* pane b's end */
    CGFloat lo = start, hi = end - div;
    CGFloat cmin = fmax(lo, start + [self _bn_minOf:a]), cmax = fmin(hi, start + [self _bn_maxOf:a]);
    cmin = fmax(cmin, end - div - [self _bn_maxOf:b]);
    cmax = fmin(cmax, end - div - [self _bn_minOf:b]);
    if ([d respondsToSelector:@selector(splitView:constrainMinCoordinate:ofSubviewAt:)])
        cmin = [d splitView:self constrainMinCoordinate:cmin ofSubviewAt:i];
    if ([d respondsToSelector:@selector(splitView:constrainMaxCoordinate:ofSubviewAt:)])
        cmax = [d splitView:self constrainMaxCoordinate:cmax ofSubviewAt:i];
    if (dragging && [d respondsToSelector:@selector(splitView:constrainSplitPosition:ofSubviewAt:)])
        position = [d splitView:self constrainSplitPosition:position ofSubviewAt:i];
    BOOL canA = [d respondsToSelector:@selector(splitView:canCollapseSubview:)] && [d splitView:self canCollapseSubview:a];
    BOOL canB = [d respondsToSelector:@selector(splitView:canCollapseSubview:)] && [d splitView:self canCollapseSubview:b];
    BOOL collapseA = NO, collapseB = NO;
    if (position < cmin) {
        if (canA && position < (lo + cmin) / 2) collapseA = YES;
        else position = cmin;
    }
    if (position > cmax) {
        if (canB && position > (hi + cmax) / 2) collapseB = YES;
        else position = cmax;
    }
    position = fmin(fmax(position, lo), hi);
    [[NSNotificationCenter defaultCenter] postNotificationName:NSSplitViewWillResizeSubviewsNotification object:self];
    NSMutableArray<NSNumber *> *sizes = [self _bn_sizes];
    if (collapseA || collapseB) {
        NSView *gone = collapseA ? a : b, *other = collapseA ? b : a;
        [_expanded setObject:@([self _bn_thick:gone]) forKey:gone];
        NSUInteger gi = collapseA ? (NSUInteger)i : (NSUInteger)i + 1, oi = collapseA ? (NSUInteger)i + 1 : (NSUInteger)i;
        sizes[oi] = @([self _bn_thick:other] + sizes[gi].doubleValue);
        sizes[gi] = @0;
        [_collapsed addObject:gone];
        gone.hidden = YES;
        [self _bn_itemCollapsed:gone];
    } else {
        if ([self _bn_out:a] || [self _bn_out:b]) {
            /* dragging a collapsed pane back out */
            NSView *back = [self _bn_out:a] ? a : b;
            [_collapsed removeObject:back];
            back.hidden = NO;
            [self _bn_itemCollapsed:back];
        }
        sizes[(NSUInteger)i] = @(position - start);
        sizes[(NSUInteger)i + 1] = @(end - position - div);
    }
    [self _bn_place:sizes];
    [self _bn_didResize];
}

- (void)_bn_itemCollapsed:(NSView *)pane {
    NSSplitViewItem *item = [self _bn_item:pane];
    if (item && item.isCollapsed != [self isSubviewCollapsed:pane])
        [item _bn_noteCollapsed:[self isSubviewCollapsed:pane]];
}

/* Collapses or expands a pane, the space going to or coming from the
 * others by holding priority. */
- (void)_bn_setPane:(NSView *)pane collapsed:(BOOL)collapse {
    if (collapse == [self isSubviewCollapsed:pane]) return;
    [self _bn_fitIfNeeded];
    NSUInteger i = [self.arrangedSubviews indexOfObjectIdenticalTo:pane];
    if (i == NSNotFound) return;
    NSMutableArray<NSNumber *> *sizes = [self _bn_sizes];
    if (collapse) {
        CGFloat s = sizes[i].doubleValue;
        [_expanded setObject:@(s) forKey:pane];
        [_collapsed addObject:pane];
        pane.hidden = YES;
        sizes[i] = @0;
    } else {
        NSNumber *e = [_expanded objectForKey:pane];
        CGFloat s = e ? e.doubleValue : 0;
        if (s <= 0) s = fmax([self _bn_minOf:pane], [self _bn_length] / MAX(self.arrangedSubviews.count, 1u));
        [_collapsed removeObject:pane];
        pane.hidden = NO;
        sizes[i] = @(s);
    }
    if ([self _bn_length] > 0) {
        CGFloat total = [self _bn_dividersTotal];
        for (NSNumber *n in sizes) total += n.doubleValue;
        [self _bn_give:[self _bn_length] - total to:sizes except:pane];
        [self _bn_place:sizes];
        [self _bn_didResize];
    }
}

- (void)drawDividerInRect:(NSRect)rect {
    [self.dividerColor setFill];
    if (_style == NSSplitViewDividerStyleThin) NSRectFill(rect);
    else {
        NSRect line = _vertical ? NSMakeRect(NSMidX(rect) - 0.5, rect.origin.y, 1, rect.size.height)
                                : NSMakeRect(rect.origin.x, NSMidY(rect) - 0.5, rect.size.width, 1);
        NSRectFill(line);
    }
}
- (void)drawRect:(NSRect)dirty {
    [self _bn_fitIfNeeded];
    NSInteger n = (NSInteger)self.arrangedSubviews.count;
    for (NSInteger i = 0; i + 1 < n; i++)
        if (![self _bn_dividerHidden:i]) [self drawDividerInRect:[self _bn_dividerRect:i]];
}

/* ---- dragging ---- */

/* A window point in this view's coordinates, minding flipped views. */
static NSPoint local_point(NSView *v, NSPoint p) {
    if (!v.superview) {
        NSRect f = v.frame, b = v.bounds;
        CGFloat y = p.y - f.origin.y;
        return NSMakePoint(p.x - f.origin.x + b.origin.x, (v.isFlipped ? f.size.height - y : y) + b.origin.y);
    }
    NSPoint s = local_point(v.superview, p);
    NSRect f = v.frame, b = v.bounds;
    CGFloat dy = s.y - f.origin.y;                 /* along the superview's y */
    BOOL sf = v.superview.isFlipped;
    CGFloat y = v.isFlipped ? (sf ? dy : f.size.height - dy) : (sf ? f.size.height - dy : dy);
    return NSMakePoint(s.x - f.origin.x + b.origin.x, y + b.origin.y);
}

- (NSInteger)_bn_dividerAt:(NSPoint)p {
    NSInteger n = (NSInteger)self.arrangedSubviews.count;
    id<NSSplitViewDelegate> d = _delegate;
    for (NSInteger i = 0; i + 1 < n; i++) {
        if ([self _bn_dividerHidden:i]) continue;
        NSRect drawn = [self _bn_dividerRect:i], eff = drawn;
        if (_style == NSSplitViewDividerStyleThin) eff = _vertical ? NSInsetRect(drawn, -2, 0) : NSInsetRect(drawn, 0, -2);
        if ([d respondsToSelector:@selector(splitView:effectiveRect:forDrawnRect:ofDividerAtIndex:)])
            eff = [d splitView:self effectiveRect:eff forDrawnRect:drawn ofDividerAtIndex:i];
        if (NSPointInRect(p, eff)) return i;
        if ([d respondsToSelector:@selector(splitView:additionalEffectiveRectOfDividerAtIndex:)] &&
            NSPointInRect(p, [d splitView:self additionalEffectiveRectOfDividerAtIndex:i]))
            return i;
    }
    return -1;
}

/* point is in the superview's coordinates. */
- (NSView *)hitTest:(NSPoint)point {
    if (self.isHidden || !NSPointInRect(point, self.frame)) return nil;
    [self _bn_fitIfNeeded];
    NSRect f = self.frame;
    BOOL sf = self.superview.isFlipped;
    CGFloat dy = point.y - f.origin.y;
    NSPoint local = NSMakePoint(point.x - f.origin.x + self.bounds.origin.x,
                                (sf ? dy : f.size.height - dy) + self.bounds.origin.y);
    if ([self _bn_dividerAt:local] >= 0) return self;
    for (NSView *v in [self.subviews reverseObjectEnumerator]) {
        NSView *hit = [v hitTest:local];
        if (hit) return hit;
    }
    return self;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = local_point(self, event.locationInWindow);
    NSInteger i = [self _bn_dividerAt:p];
    if (i < 0) {
        [super mouseDown:event];
        return;
    }
    if (event.clickCount == 2) {
        id<NSSplitViewDelegate> d = _delegate;
        NSArray *panes = self.arrangedSubviews;
        for (NSUInteger k = (NSUInteger)i; k <= (NSUInteger)i + 1; k++)
            if ([d respondsToSelector:@selector(splitView:shouldCollapseSubview:forDoubleClickOnDividerAtIndex:)] &&
                [d respondsToSelector:@selector(splitView:canCollapseSubview:)] &&
                [d splitView:self canCollapseSubview:panes[k]] &&
                [d splitView:self shouldCollapseSubview:panes[k] forDoubleClickOnDividerAtIndex:i]) {
                [self _bn_setPane:panes[k] collapsed:![self isSubviewCollapsed:panes[k]]];
                return;
            }
    }
    _drag = i;
    _dragOffset = (_vertical ? p.x : p.y) - [self _bn_dividerStart:i];
}
- (void)mouseDragged:(NSEvent *)event {
    if (_drag < 0) {
        [super mouseDragged:event];
        return;
    }
    NSPoint p = local_point(self, event.locationInWindow);
    [self _bn_move:_drag to:(_vertical ? p.x : p.y) - _dragOffset dragging:YES];
}
- (void)mouseUp:(NSEvent *)event {
    if (_drag < 0) {
        [super mouseUp:event];
        return;
    }
    _drag = -1;
}

/* ---- autosave ---- */

- (NSString *)autosaveName { return _autosaveName; }
- (void)setAutosaveName:(NSString *)name {
    _autosaveName = [name copy];
    _restored = NO;
    if (name.length && [self _bn_length] > 0) [self _bn_fit];
}
- (NSString *)_bn_key { return [@"NSSplitView Subview Frames " stringByAppendingString:_autosaveName]; }
- (void)_bn_save {
    if (!_autosaveName.length) return;
    NSMutableArray *out = [NSMutableArray array];
    for (NSView *v in self.arrangedSubviews) {
        NSRect f = v.frame;
        [out addObject:[NSString stringWithFormat:@"%f, %f, %f, %f, %@, %@", f.origin.x, f.origin.y, f.size.width,
                                                  f.size.height, [self isSubviewCollapsed:v] ? @"YES" : @"NO",
                                                  v.isHidden ? @"YES" : @"NO"]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:out forKey:[self _bn_key]];
}
- (void)_bn_restore {
    _restored = YES;
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:[self _bn_key]];
    NSArray<NSView *> *panes = self.arrangedSubviews;
    if (saved.count != panes.count) return;
    for (NSUInteger i = 0; i < panes.count; i++) {
        NSArray *parts = [saved[i] componentsSeparatedByString:@", "];
        if (parts.count < 4) continue;
        NSView *v = panes[i];
        NSRect f = v.frame;
        if (_vertical) f.size.width = [parts[2] doubleValue];
        else f.size.height = [parts[3] doubleValue];
        v.frame = f;
        BOOL c = parts.count > 4 && [parts[4] isEqual:@"YES"];
        if (c) {
            [_expanded setObject:@(_vertical ? f.size.width : f.size.height) forKey:v];
            [_collapsed addObject:v];
            v.hidden = YES;
            [self _bn_itemCollapsed:v];
        }
    }
}
@end

/* ---- items ---- */

@implementation NSSplitViewItem {
    NSSplitViewItemBehavior _behavior;
    __weak NSSplitViewController *_controller;
    BOOL _collapsed;
}
@synthesize viewController = _viewController, canCollapse = _canCollapse,
            canCollapseFromWindowResize = _canCollapseFromWindowResize, collapseBehavior = _collapseBehavior,
            minimumThickness = _minimumThickness, maximumThickness = _maximumThickness,
            preferredThicknessFraction = _preferredThicknessFraction, holdingPriority = _holdingPriority,
            automaticMaximumThickness = _automaticMaximumThickness, springLoaded = _springLoaded,
            allowsFullHeightLayout = _allowsFullHeightLayout, titlebarSeparatorStyle = _titlebarSeparatorStyle;

- (instancetype)init {
    if ((self = [super init])) {
        _minimumThickness = NSSplitViewItemUnspecifiedDimension;
        _maximumThickness = NSSplitViewItemUnspecifiedDimension;
        _preferredThicknessFraction = NSSplitViewItemUnspecifiedDimension;
        _automaticMaximumThickness = NSSplitViewItemUnspecifiedDimension;
        _holdingPriority = NSLayoutPriorityDefaultLow;
        _canCollapseFromWindowResize = YES;
        _allowsFullHeightLayout = YES;
    }
    return self;
}
+ (instancetype)_bn_item:(NSViewController *)vc behavior:(NSSplitViewItemBehavior)b {
    NSSplitViewItem *i = [self new];
    i.viewController = vc;
    i->_behavior = b;
    if (b == NSSplitViewItemBehaviorSidebar || b == NSSplitViewItemBehaviorInspector) {
        i->_canCollapse = YES;
        i->_holdingPriority = NSLayoutPriorityDefaultLow + 10;
    } else if (b == NSSplitViewItemBehaviorContentList) {
        i->_holdingPriority = NSLayoutPriorityDefaultLow + 10;
    }
    return i;
}
+ (instancetype)splitViewItemWithViewController:(NSViewController *)vc {
    return [self _bn_item:vc behavior:NSSplitViewItemBehaviorDefault];
}
+ (instancetype)sidebarWithViewController:(NSViewController *)vc {
    return [self _bn_item:vc behavior:NSSplitViewItemBehaviorSidebar];
}
+ (instancetype)contentListWithViewController:(NSViewController *)vc {
    return [self _bn_item:vc behavior:NSSplitViewItemBehaviorContentList];
}
+ (instancetype)inspectorWithViewController:(NSViewController *)vc {
    return [self _bn_item:vc behavior:NSSplitViewItemBehaviorInspector];
}
- (NSSplitViewItemBehavior)behavior { return _behavior; }
- (instancetype)animator { return self; }
- (void)_bn_setController:(NSSplitViewController *)c { _controller = c; }
- (CGFloat)_bn_min { return _minimumThickness > 0 ? _minimumThickness : 0; }
- (CGFloat)_bn_max { return _maximumThickness > 0 ? _maximumThickness : INFINITY; }

- (BOOL)isCollapsed { return _collapsed; }
- (void)setCollapsed:(BOOL)c {
    if (c == _collapsed) return;
    _collapsed = c;
    NSSplitViewController *ctl = _controller;
    if (ctl && _viewController.isViewLoaded) [ctl.splitView _bn_setPane:_viewController.view collapsed:c];
}
/* The split view noting a pane it collapsed or expanded itself. */
- (void)_bn_noteCollapsed:(BOOL)c { _collapsed = c; }
- (void)setHoldingPriority:(NSLayoutPriority)p {
    _holdingPriority = p;
    NSSplitViewController *ctl = _controller;
    NSInteger i = ctl ? (NSInteger)[ctl.splitViewItems indexOfObjectIdenticalTo:self] : NSNotFound;
    if (ctl && i != NSNotFound) [ctl.splitView setHoldingPriority:p forSubviewAtIndex:i];
}
- (NSLayoutPriority)holdingPriority { return _holdingPriority; }
@end

/* ---- the controller ---- */

@implementation NSSplitViewController {
    NSSplitView *_splitView;
    NSMutableArray<NSSplitViewItem *> *_items;
}
@synthesize minimumThicknessForInlineSidebars = _minimumThicknessForInlineSidebars;

- (instancetype)initWithNibName:(NSString *)nib bundle:(NSBundle *)bundle {
    if ((self = [super initWithNibName:nib bundle:bundle])) {
        _items = [NSMutableArray array];
        _minimumThicknessForInlineSidebars = NSSplitViewControllerAutomaticDimension;
    }
    return self;
}
- (NSSplitView *)splitView {
    if (!_splitView) {
        _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        _splitView.vertical = YES;
        _splitView.dividerStyle = NSSplitViewDividerStyleThin;
        _splitView.delegate = self;
    }
    return _splitView;
}
- (void)setSplitView:(NSSplitView *)s {
    _splitView = s;
    s.delegate = self;
    for (NSSplitViewItem *item in _items) [self _bn_attach:item at:(NSInteger)[_items indexOfObjectIdenticalTo:item]];
}
- (void)loadView { self.view = self.splitView; }

- (NSArray<NSSplitViewItem *> *)splitViewItems { return [_items copy]; }
- (void)setSplitViewItems:(NSArray<NSSplitViewItem *> *)items {
    for (NSSplitViewItem *i in [_items copy]) [self removeSplitViewItem:i];
    for (NSSplitViewItem *i in items) [self addSplitViewItem:i];
}
- (void)addSplitViewItem:(NSSplitViewItem *)item { [self insertSplitViewItem:item atIndex:(NSInteger)_items.count]; }
- (void)insertSplitViewItem:(NSSplitViewItem *)item atIndex:(NSInteger)i {
    if (!item) return;
    if (i < 0 || (NSUInteger)i > _items.count) i = (NSInteger)_items.count;
    [_items insertObject:item atIndex:(NSUInteger)i];
    [item _bn_setController:self];
    if (item.viewController) [self addChildViewController:item.viewController];
    [self _bn_attach:item at:i];
}
- (void)_bn_attach:(NSSplitViewItem *)item at:(NSInteger)i {
    NSView *pane = item.viewController.view;
    if (!pane) return;
    NSSplitView *sv = self.splitView;
    CGFloat len = sv.isVertical ? sv.bounds.size.width : sv.bounds.size.height;
    CGFloat want = sv.isVertical ? pane.frame.size.width : pane.frame.size.height;
    if (item.preferredThicknessFraction > 0 && len > 0) want = item.preferredThicknessFraction * len;
    want = fmax(want, [item _bn_min]);
    want = fmin(want, [item _bn_max]);
    NSRect f = pane.frame;
    if (sv.isVertical) f.size.width = want; else f.size.height = want;
    pane.frame = f;
    [sv insertArrangedSubview:pane atIndex:i];
    [sv setHoldingPriority:item.holdingPriority forSubviewAtIndex:i];
    if (item.isCollapsed) [sv _bn_setPane:pane collapsed:YES];
}
- (void)removeSplitViewItem:(NSSplitViewItem *)item {
    NSUInteger i = [_items indexOfObjectIdenticalTo:item];
    if (i == NSNotFound) return;
    [_items removeObjectAtIndex:i];
    [item _bn_setController:nil];
    if (item.viewController.isViewLoaded) [self.splitView removeArrangedSubview:item.viewController.view];
    [item.viewController removeFromParentViewController];
}
- (NSSplitViewItem *)splitViewItemForViewController:(NSViewController *)vc {
    for (NSSplitViewItem *i in _items) if (i.viewController == vc) return i;
    return nil;
}
- (NSSplitViewItem *)_bn_itemForPane:(NSView *)pane {
    for (NSSplitViewItem *i in _items) if (i.viewController.viewIfLoaded == pane) return i;
    return nil;
}

- (void)_bn_toggle:(NSSplitViewItemBehavior)b {
    for (NSSplitViewItem *i in _items)
        if (i.behavior == b) {
            i.animator.collapsed = !i.isCollapsed;
            return;
        }
}
- (void)toggleSidebar:(id)sender { [self _bn_toggle:NSSplitViewItemBehaviorSidebar]; }
- (void)toggleInspector:(id)sender { [self _bn_toggle:NSSplitViewItemBehaviorInspector]; }

/* ---- as the split view's delegate ---- */

- (BOOL)splitView:(NSSplitView *)sv canCollapseSubview:(NSView *)v { return [self _bn_itemForPane:v].canCollapse; }
- (BOOL)splitView:(NSSplitView *)sv shouldHideDividerAtIndex:(NSInteger)i {
    NSArray *items = _items;
    if (i < 0 || (NSUInteger)i + 1 >= items.count) return NO;
    NSSplitViewItem *a = items[(NSUInteger)i], *b = items[(NSUInteger)i + 1];
    /* a collapsed edge pane takes its divider with it */
    return (a.isCollapsed && i == 0) || (b.isCollapsed && (NSUInteger)i + 2 == items.count);
}
- (NSRect)splitView:(NSSplitView *)sv effectiveRect:(NSRect)proposed forDrawnRect:(NSRect)drawn
    ofDividerAtIndex:(NSInteger)i {
    return proposed;
}
- (NSRect)splitView:(NSSplitView *)sv additionalEffectiveRectOfDividerAtIndex:(NSInteger)i { return NSZeroRect; }
@end
