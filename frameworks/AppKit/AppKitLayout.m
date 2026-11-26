/* Auto Layout: constraints, anchors, layout guides, NSStackView, and the
 * layout pass that solves them (AppKitSolver.m) and sets frames.
 *
 * The pass works on the whole tree a view belongs to. Every item that a
 * constraint mentions, and every ancestor of such an item up to the root,
 * gets four variables: left, top, width and height in the root's
 * coordinates, y down. The root keeps its size. A view that translates its
 * autoresizing mask keeps its frame (moving or stretching with its
 * superview as the mask says); any other view gets its intrinsic size as
 * hugging and compression-resistance constraints at their priorities, and
 * is the one whose frame the solution sets. Stack views add constraints of
 * their own for their arranged views. */
#import <AppKit/AppKit.h>
#import <AppKit/AppKitLayout.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>

#include "AppKitSolver.h"

@interface NSLayoutConstraint (BNPrivate)
- (instancetype)initWithBNFirst:(NSLayoutAnchor *)first relation:(NSLayoutRelation)r second:(NSLayoutAnchor *)second
                   multiplier:(CGFloat)m constant:(CGFloat)c;
- (void)_bn_setHolder:(NSView *)v active:(BOOL)a;
- (NSView *)_bn_holder;
@end
@interface NSLayoutGuide (BNPrivate)
- (void)_bn_setFrame:(NSRect)f;
@end
@interface NSView (BNLayoutPrivate)
- (NSMutableArray *)_bn_constraintStore;
- (NSArray<NSLayoutConstraint *> *)_bn_generatedConstraints;
@end

static const char kConstraints, kGuides, kSafeGuide, kMarginsGuide, kNeedsUpdate;

/* ---- anchors ---- */

@interface NSLayoutAnchor () {
@public
    __weak id _item;
    NSLayoutAttribute _attr;
    NSLayoutAnchor *_from, *_to;  /* an offset anchor: to - from */
}
@end

@implementation NSLayoutAnchor
+ (instancetype)_bn_anchor:(id)item attribute:(NSLayoutAttribute)a {
    NSLayoutAnchor *x = [self new];
    x->_item = item;
    x->_attr = a;
    return x;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (id)item { return _item; }
- (NSLayoutAttribute)_bn_attribute { return _attr; }
- (NSString *)name {
    static NSArray *names;
    if (!names) names = @[@"none", @"left", @"right", @"top", @"bottom", @"leading", @"trailing", @"width",
                          @"height", @"centerX", @"centerY", @"lastBaseline", @"firstBaseline"];
    return _attr >= 0 && (NSUInteger)_attr < names.count ? names[_attr] : @"offset";
}
- (BOOL)isEqual:(id)o {
    if (![o isKindOfClass:[NSLayoutAnchor class]]) return NO;
    NSLayoutAnchor *a = o;
    return a->_item == _item && a->_attr == _attr && a->_from == _from && a->_to == _to;
}
- (NSUInteger)hash { return (NSUInteger)(__bridge void *)_item ^ (NSUInteger)_attr; }
- (NSString *)description { return [NSString stringWithFormat:@"%@.%@", _item, self.name]; }

- (NSLayoutConstraint *)_bn_to:(NSLayoutAnchor *)a rel:(NSLayoutRelation)r m:(CGFloat)m c:(CGFloat)c {
    NSLayoutConstraint *k = [NSLayoutConstraint alloc];
    return [k initWithBNFirst:self relation:r second:a multiplier:m constant:c];
}
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a { return [self _bn_to:a rel:0 m:1 c:0]; }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a { return [self _bn_to:a rel:1 m:1 c:0]; }
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a { return [self _bn_to:a rel:-1 m:1 c:0]; }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c { return [self _bn_to:a rel:0 m:1 c:c]; }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c {
    return [self _bn_to:a rel:1 m:1 c:c];
}
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c {
    return [self _bn_to:a rel:-1 m:1 c:c];
}
@end

@implementation NSLayoutXAxisAnchor
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutXAxisAnchor *)other {
    NSLayoutDimension *d = [NSLayoutDimension new];
    d->_from = self;
    d->_to = other;
    d->_item = _item;
    return d;
}
- (NSLayoutConstraint *)constraintEqualToSystemSpacingAfterAnchor:(NSLayoutXAxisAnchor *)a multiplier:(CGFloat)m {
    return [self _bn_to:a rel:0 m:1 c:8 * m];
}
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToSystemSpacingAfterAnchor:(NSLayoutXAxisAnchor *)a multiplier:(CGFloat)m {
    return [self _bn_to:a rel:1 m:1 c:8 * m];
}
@end

@implementation NSLayoutYAxisAnchor
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutYAxisAnchor *)other {
    NSLayoutDimension *d = [NSLayoutDimension new];
    d->_from = self;
    d->_to = other;
    d->_item = _item;
    return d;
}
- (NSLayoutConstraint *)constraintEqualToSystemSpacingBelowAnchor:(NSLayoutYAxisAnchor *)a multiplier:(CGFloat)m {
    return [self _bn_to:a rel:0 m:1 c:8 * m];
}
@end

@implementation NSLayoutDimension
- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c { return [self _bn_to:nil rel:0 m:0 c:c]; }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToConstant:(CGFloat)c { return [self _bn_to:nil rel:1 m:0 c:c]; }
- (NSLayoutConstraint *)constraintLessThanOrEqualToConstant:(CGFloat)c { return [self _bn_to:nil rel:-1 m:0 c:c]; }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m { return [self _bn_to:a rel:0 m:m c:0]; }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m {
    return [self _bn_to:a rel:1 m:m c:0];
}
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m {
    return [self _bn_to:a rel:-1 m:m c:0];
}
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m constant:(CGFloat)c {
    return [self _bn_to:a rel:0 m:m c:c];
}
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m constant:(CGFloat)c {
    return [self _bn_to:a rel:1 m:m c:c];
}
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m constant:(CGFloat)c {
    return [self _bn_to:a rel:-1 m:m c:c];
}
@end

static Class anchor_class(NSLayoutAttribute a) {
    switch (a) {
    case NSLayoutAttributeWidth: case NSLayoutAttributeHeight: return [NSLayoutDimension class];
    case NSLayoutAttributeTop: case NSLayoutAttributeBottom: case NSLayoutAttributeCenterY:
    case NSLayoutAttributeFirstBaseline: case NSLayoutAttributeLastBaseline: return [NSLayoutYAxisAnchor class];
    default: return [NSLayoutXAxisAnchor class];
    }
}
static id make_anchor(id item, NSLayoutAttribute a) { return [anchor_class(a) _bn_anchor:item attribute:a]; }

/* The view an item lives in: a view, or a guide's owning view. */
static NSView *item_view(id item) {
    if ([item isKindOfClass:[NSView class]]) return item;
    if ([item isKindOfClass:[NSLayoutGuide class]]) return ((NSLayoutGuide *)item).owningView;
    return nil;
}

static void schedule(NSView *v) {
    if (!v) return;
    v.needsLayout = YES;
    NSWindow *w = v.window;
    if ([w respondsToSelector:@selector(_bn_scheduleDisplay)])
        ((void (*)(id, SEL))objc_msgSend)(w, @selector(_bn_scheduleDisplay));
}

/* ---- constraints ---- */

@implementation NSLayoutConstraint {
    NSLayoutAnchor *_first, *_second;
    NSLayoutRelation _relation;
    CGFloat _multiplier, _constant;
    BOOL _active;
    __weak NSView *_holder;
}
@synthesize priority = _priority, identifier = _identifier, shouldBeArchived = _shouldBeArchived;

- (instancetype)initWithBNFirst:(NSLayoutAnchor *)first relation:(NSLayoutRelation)r second:(NSLayoutAnchor *)second
                   multiplier:(CGFloat)m constant:(CGFloat)c {
    if ((self = [super init])) {
        _first = first;
        _second = second;
        _relation = r;
        _multiplier = second ? m : 0;
        _constant = c;
        _priority = NSLayoutPriorityRequired;
    }
    return self;
}
+ (instancetype)constraintWithItem:(id)view1 attribute:(NSLayoutAttribute)attr1 relatedBy:(NSLayoutRelation)relation
                            toItem:(id)view2 attribute:(NSLayoutAttribute)attr2 multiplier:(CGFloat)multiplier
                          constant:(CGFloat)c {
    NSLayoutAnchor *second = view2 && attr2 != NSLayoutAttributeNotAnAttribute ? make_anchor(view2, attr2) : nil;
    return [[self alloc] initWithBNFirst:make_anchor(view1, attr1) relation:relation second:second multiplier:multiplier
                              constant:c];
}
/* The visual format language is not parsed here: no constraints. */
+ (NSArray *)constraintsWithVisualFormat:(NSString *)format options:(NSLayoutFormatOptions)opts metrics:(NSDictionary *)m
                                   views:(NSDictionary *)views {
    return @[];
}
+ (void)activateConstraints:(NSArray<NSLayoutConstraint *> *)cs { for (NSLayoutConstraint *c in cs) c.active = YES; }
+ (void)deactivateConstraints:(NSArray<NSLayoutConstraint *> *)cs { for (NSLayoutConstraint *c in cs) c.active = NO; }

- (id)firstItem { return _first ? _first->_item : nil; }
- (id)secondItem { return _second ? _second->_item : nil; }
- (NSLayoutAttribute)firstAttribute { return _first ? _first->_attr : NSLayoutAttributeNotAnAttribute; }
- (NSLayoutAttribute)secondAttribute { return _second ? _second->_attr : NSLayoutAttributeNotAnAttribute; }
- (NSLayoutAnchor *)firstAnchor { return _first; }
- (NSLayoutAnchor *)secondAnchor { return _second; }
- (NSLayoutRelation)relation { return _relation; }
- (CGFloat)multiplier { return _second ? _multiplier : 1; }
- (CGFloat)constant { return _constant; }
- (void)setConstant:(CGFloat)c {
    _constant = c;
    if (_active) schedule(_holder);
}
- (void)setPriority:(NSLayoutPriority)p {
    _priority = p;
    if (_active) schedule(_holder);
}
- (BOOL)isActive { return _active; }
- (NSLayoutPriority)priority { return _priority; }

/* The nearest common ancestor of the items' views holds an active constraint. */
- (NSView *)_bn_commonAncestor {
    NSView *a = item_view(self.firstItem), *b = item_view(self.secondItem);
    if (!a) return b;
    if (!b) return a;
    for (NSView *x = a; x; x = x.superview)
        for (NSView *y = b; y; y = y.superview)
            if (x == y) return x;
    return a;
}
- (void)setActive:(BOOL)active {
    if (active == _active) return;
    if (active) [[self _bn_commonAncestor] addConstraint:self];
    else [_holder removeConstraint:self];
}
- (void)_bn_setHolder:(NSView *)v active:(BOOL)a {
    _holder = v;
    _active = a;
    schedule(v);
}
- (NSView *)_bn_holder { return _holder; }

- (NSString *)description {
    static const char *rel[] = {"<=", "==", ">="};
    NSMutableString *s = [NSMutableString stringWithFormat:@"<NSLayoutConstraint %p %@ %s ", (void *)self, _first,
                                                           rel[_relation + 1]];
    if (_second) [s appendFormat:@"%g*%@ + ", _multiplier, _second];
    [s appendFormat:@"%g @%g>", _constant, _priority];
    return s;
}
@end

/* ---- layout guides ---- */

@implementation NSLayoutGuide {
    NSRect _frame;
}
@synthesize owningView = _owningView, identifier = _identifier;
- (instancetype)init {
    if ((self = [super init])) _identifier = @"";
    return self;
}
- (NSRect)frame { return _frame; }
- (void)_bn_setFrame:(NSRect)f { _frame = f; }
- (BOOL)hasAmbiguousLayout { return NO; }
- (NSLayoutXAxisAnchor *)leadingAnchor { return make_anchor(self, NSLayoutAttributeLeading); }
- (NSLayoutXAxisAnchor *)trailingAnchor { return make_anchor(self, NSLayoutAttributeTrailing); }
- (NSLayoutXAxisAnchor *)leftAnchor { return make_anchor(self, NSLayoutAttributeLeft); }
- (NSLayoutXAxisAnchor *)rightAnchor { return make_anchor(self, NSLayoutAttributeRight); }
- (NSLayoutYAxisAnchor *)topAnchor { return make_anchor(self, NSLayoutAttributeTop); }
- (NSLayoutYAxisAnchor *)bottomAnchor { return make_anchor(self, NSLayoutAttributeBottom); }
- (NSLayoutDimension *)widthAnchor { return make_anchor(self, NSLayoutAttributeWidth); }
- (NSLayoutDimension *)heightAnchor { return make_anchor(self, NSLayoutAttributeHeight); }
- (NSLayoutXAxisAnchor *)centerXAnchor { return make_anchor(self, NSLayoutAttributeCenterX); }
- (NSLayoutYAxisAnchor *)centerYAnchor { return make_anchor(self, NSLayoutAttributeCenterY); }
@end

/* ---- views ---- */

@implementation NSView (NSConstraintBasedLayout)
- (NSMutableArray *)_bn_constraintStore {
    NSMutableArray *a = objc_getAssociatedObject(self, &kConstraints);
    if (!a) {
        a = [NSMutableArray array];
        objc_setAssociatedObject(self, &kConstraints, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return a;
}
- (NSArray *)constraints { return [objc_getAssociatedObject(self, &kConstraints) copy] ?: @[]; }
- (void)addConstraint:(NSLayoutConstraint *)c {
    if (!c) return;
    NSView *old = [c _bn_holder];
    if (old && old != self) [[old _bn_constraintStore] removeObjectIdenticalTo:c];
    NSMutableArray *a = [self _bn_constraintStore];
    if ([a indexOfObjectIdenticalTo:c] == NSNotFound) [a addObject:c];
    [c _bn_setHolder:self active:YES];
}
- (void)addConstraints:(NSArray *)cs { for (NSLayoutConstraint *c in cs) [self addConstraint:c]; }
- (void)removeConstraint:(NSLayoutConstraint *)c {
    if (!c) return;
    [[self _bn_constraintStore] removeObjectIdenticalTo:c];
    if ([c _bn_holder] == self) [c _bn_setHolder:nil active:NO];
    schedule(self);
}
- (void)removeConstraints:(NSArray *)cs { for (NSLayoutConstraint *c in [cs copy]) [self removeConstraint:c]; }

- (NSArray *)layoutGuides { return [objc_getAssociatedObject(self, &kGuides) copy] ?: @[]; }
- (void)addLayoutGuide:(NSLayoutGuide *)g {
    NSMutableArray *a = objc_getAssociatedObject(self, &kGuides);
    if (!a) objc_setAssociatedObject(self, &kGuides, a = [NSMutableArray array], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (g && [a indexOfObjectIdenticalTo:g] == NSNotFound) [a addObject:g];
    g.owningView = self;
}
- (void)removeLayoutGuide:(NSLayoutGuide *)g {
    [objc_getAssociatedObject(self, &kGuides) removeObjectIdenticalTo:g];
    if (g.owningView == self) g.owningView = nil;
}
- (NSLayoutGuide *)_bn_guide:(const void *)key {
    NSLayoutGuide *g = objc_getAssociatedObject(self, key);
    if (!g) {
        g = [NSLayoutGuide new];
        g.owningView = self;
        objc_setAssociatedObject(self, key, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return g;
}
- (NSLayoutGuide *)safeAreaLayoutGuide { return [self _bn_guide:&kSafeGuide]; }
- (NSLayoutGuide *)layoutMarginsGuide { return [self _bn_guide:&kMarginsGuide]; }

- (NSLayoutXAxisAnchor *)leadingAnchor { return make_anchor(self, NSLayoutAttributeLeading); }
- (NSLayoutXAxisAnchor *)trailingAnchor { return make_anchor(self, NSLayoutAttributeTrailing); }
- (NSLayoutXAxisAnchor *)leftAnchor { return make_anchor(self, NSLayoutAttributeLeft); }
- (NSLayoutXAxisAnchor *)rightAnchor { return make_anchor(self, NSLayoutAttributeRight); }
- (NSLayoutYAxisAnchor *)topAnchor { return make_anchor(self, NSLayoutAttributeTop); }
- (NSLayoutYAxisAnchor *)bottomAnchor { return make_anchor(self, NSLayoutAttributeBottom); }
- (NSLayoutDimension *)widthAnchor { return make_anchor(self, NSLayoutAttributeWidth); }
- (NSLayoutDimension *)heightAnchor { return make_anchor(self, NSLayoutAttributeHeight); }
- (NSLayoutXAxisAnchor *)centerXAnchor { return make_anchor(self, NSLayoutAttributeCenterX); }
- (NSLayoutYAxisAnchor *)centerYAnchor { return make_anchor(self, NSLayoutAttributeCenterY); }
- (NSLayoutYAxisAnchor *)firstBaselineAnchor { return make_anchor(self, NSLayoutAttributeFirstBaseline); }
- (NSLayoutYAxisAnchor *)lastBaselineAnchor { return make_anchor(self, NSLayoutAttributeLastBaseline); }

/* Text sits about a quarter of a line above a control's bottom edge. */
- (CGFloat)firstBaselineOffsetFromTop {
    NSSize s = self.intrinsicContentSize;
    CGFloat h = s.height != NSViewNoIntrinsicMetric ? s.height : self.frame.size.height;
    return h - self.lastBaselineOffsetFromBottom;
}
- (CGFloat)lastBaselineOffsetFromBottom {
    NSSize s = self.intrinsicContentSize;
    return s.height != NSViewNoIntrinsicMetric ? floor(s.height * 0.25) : 0;
}

- (BOOL)needsUpdateConstraints { return [objc_getAssociatedObject(self, &kNeedsUpdate) boolValue]; }
- (void)setNeedsUpdateConstraints:(BOOL)b {
    objc_setAssociatedObject(self, &kNeedsUpdate, @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (b) schedule(self);
}
- (void)updateConstraints {}
- (void)updateConstraintsForSubtreeIfNeeded {
    for (NSView *v in self.subviews) [v updateConstraintsForSubtreeIfNeeded];
    if (self.needsUpdateConstraints) {
        self.needsUpdateConstraints = NO;
        [self updateConstraints];
    }
}
- (NSArray *)constraintsAffectingLayoutForOrientation:(NSLayoutConstraintOrientation)o {
    NSMutableArray *out = [NSMutableArray array];
    for (NSView *v = self; v; v = v.superview)
        for (NSLayoutConstraint *c in v.constraints)
            if (c.firstItem == self || c.secondItem == self) [out addObject:c];
    return out;
}
- (BOOL)hasAmbiguousLayout { return NO; }

/* Constraints a view adds to the pass itself (stack views). */
- (NSArray<NSLayoutConstraint *> *)_bn_generatedConstraints { return nil; }
@end

/* ---- the layout pass ---- */

typedef struct {
    int var[8];
    double coef[8];
    int n;
    double c;
} Expr;

static void expr_add(Expr *e, int var, double coef) {
    for (int i = 0; i < e->n; i++)
        if (e->var[i] == var) { e->coef[i] += coef; return; }
    if (e->n < 8) { e->var[e->n] = var; e->coef[e->n] = coef; e->n++; }
}

/* The variables of one item: left, top, width, height (root coords, y down). */
typedef struct { int l, t, w, h; } Vars;

@interface BNLayoutPass : NSObject {
@public
    bn_solver *_s;
    NSMapTable *_items;          /* item -> NSData(Vars) */
    NSView *_root;
}
@end
@implementation BNLayoutPass
- (void)dealloc { bn_solver_free(_s); }
- (BOOL)_bn_has:(id)item { return [_items objectForKey:item] != nil; }
- (Vars)_bn_vars:(id)item {
    NSData *v = [_items objectForKey:item];
    Vars x = {0, 0, 0, 0};
    if (v) [v getBytes:&x length:sizeof x];
    return x;
}
- (void)_bn_addItem:(id)item {
    if (!item || [self _bn_has:item]) return;
    Vars x = {bn_solver_variable(_s), bn_solver_variable(_s), bn_solver_variable(_s), bn_solver_variable(_s)};
    [_items setObject:[NSData dataWithBytes:&x length:sizeof x] forKey:item];
}
@end

static double strength_of(NSLayoutPriority p) {
    if (p >= NSLayoutPriorityRequired) return BN_STRENGTH_REQUIRED;
    if (p < 1) p = 1;
    return pow(10.0, p / 100.0);
}

static void add(BNLayoutPass *P, Expr *e, int relation, NSLayoutPriority p) {
    bn_solver_add(P->_s, e->var, e->coef, e->n, e->c, relation, strength_of(p));
}

/* An anchor's value as an expression (scaled by k), into e. */
static BOOL anchor_expr(BNLayoutPass *P, NSLayoutAnchor *a, double k, Expr *e) {
    if (a->_from || a->_to) {
        return anchor_expr(P, a->_to, k, e) && anchor_expr(P, a->_from, -k, e);
    }
    id item = a->_item;
    if (!item || ![P _bn_has:item]) return NO;
    Vars v = [P _bn_vars:item];
    NSView *view = [item isKindOfClass:[NSView class]] ? item : nil;
    switch (a->_attr) {
    case NSLayoutAttributeLeft: case NSLayoutAttributeLeading: expr_add(e, v.l, k); break;
    case NSLayoutAttributeRight: case NSLayoutAttributeTrailing: expr_add(e, v.l, k); expr_add(e, v.w, k); break;
    case NSLayoutAttributeTop: expr_add(e, v.t, k); break;
    case NSLayoutAttributeBottom: expr_add(e, v.t, k); expr_add(e, v.h, k); break;
    case NSLayoutAttributeWidth: expr_add(e, v.w, k); break;
    case NSLayoutAttributeHeight: expr_add(e, v.h, k); break;
    case NSLayoutAttributeCenterX: expr_add(e, v.l, k); expr_add(e, v.w, k * 0.5); break;
    case NSLayoutAttributeCenterY: expr_add(e, v.t, k); expr_add(e, v.h, k * 0.5); break;
    case NSLayoutAttributeFirstBaseline:
        expr_add(e, v.t, k);
        e->c += k * (view ? view.firstBaselineOffsetFromTop : 0);
        break;
    case NSLayoutAttributeLastBaseline:
        expr_add(e, v.t, k);
        expr_add(e, v.h, k);
        e->c -= k * (view ? view.lastBaselineOffsetFromBottom : 0);
        break;
    default: return NO;
    }
    return YES;
}

static int layout_debug = -1;
static void add_constraint(BNLayoutPass *P, NSLayoutConstraint *c) {
    if (layout_debug < 0) layout_debug = getenv("BITTEN_LAYOUT_DEBUG") != NULL;
    Expr e = {{0}, {0}, 0, 0};
    if (!anchor_expr(P, c.firstAnchor, 1, &e) || (c.secondAnchor && !anchor_expr(P, c.secondAnchor, -c.multiplier, &e))) {
        if (layout_debug) fprintf(stderr, "layout: skipped (item not in the pass) %s\n", c.description.UTF8String);
        return;
    }
    e.c -= c.constant;
    int ok = bn_solver_add(P->_s, e.var, e.coef, e.n, e.c, (int)c.relation, strength_of(c.priority));
    if (!ok && layout_debug) fprintf(stderr, "layout: unsatisfiable, dropped %s\n", c.description.UTF8String);
}

/* var = constant, or a + coef*b = constant... small helpers. */
static void eq(BNLayoutPass *P, int a, double ka, int b, double kb, double c, NSLayoutPriority p) {
    Expr e = {{0}, {0}, 0, -c};
    expr_add(&e, a, ka);
    if (b) expr_add(&e, b, kb);
    add(P, &e, BN_EQ, p);
}

/* A view keeping its frame (and its autoresizing mask) relative to its superview. */
static void autoresizing(BNLayoutPass *P, NSView *v) {
    NSView *s = v.superview;
    Vars me = [P _bn_vars:v], sup = [P _bn_vars:s];
    NSRect f = v.frame, sb = s.bounds;
    NSAutoresizingMaskOptions m = v.autoresizingMask;
    /* x axis */
    CGFloat left = f.origin.x - sb.origin.x, right = sb.size.width - left - f.size.width;
    BOOL fl = m & NSViewMinXMargin, fw = m & NSViewWidthSizable, fr = m & NSViewMaxXMargin;
    if (fw && !fl && !fr) {
        eq(P, me.l, 1, sup.l, -1, left, NSLayoutPriorityRequired);
        eq(P, me.w, 1, sup.w, -1, -(left + right), NSLayoutPriorityRequired);
    } else {
        if (!fw) eq(P, me.w, 1, 0, 0, f.size.width, NSLayoutPriorityRequired);
        else eq(P, me.w, 1, sup.w, -(sb.size.width > 0 ? f.size.width / sb.size.width : 0), 0, NSLayoutPriorityRequired);
        if (fl && !fr) {                                   /* right margin fixed */
            Expr e = {{0}, {0}, 0, right};
            expr_add(&e, me.l, 1); expr_add(&e, me.w, 1); expr_add(&e, sup.l, -1); expr_add(&e, sup.w, -1);
            add(P, &e, BN_EQ, NSLayoutPriorityRequired);
        } else if (fl && fr && sb.size.width > 0) {        /* centre where it was, proportionally */
            Expr e = {{0}, {0}, 0, 0};
            expr_add(&e, me.l, 1); expr_add(&e, me.w, 0.5); expr_add(&e, sup.l, -1);
            expr_add(&e, sup.w, -(left + f.size.width / 2) / sb.size.width);
            add(P, &e, BN_EQ, NSLayoutPriorityRequired);
        } else {
            eq(P, me.l, 1, sup.l, -1, left, NSLayoutPriorityRequired);
        }
    }
    /* y axis, in top-down terms */
    CGFloat top, bottom;
    BOOL ft, fb;
    if (s.isFlipped) {
        top = f.origin.y - sb.origin.y;
        ft = m & NSViewMinYMargin;
        fb = m & NSViewMaxYMargin;
    } else {
        top = sb.size.height - (f.origin.y - sb.origin.y) - f.size.height;
        ft = m & NSViewMaxYMargin;
        fb = m & NSViewMinYMargin;
    }
    bottom = sb.size.height - top - f.size.height;
    BOOL fh = m & NSViewHeightSizable;
    if (fh && !ft && !fb) {
        eq(P, me.t, 1, sup.t, -1, top, NSLayoutPriorityRequired);
        eq(P, me.h, 1, sup.h, -1, -(top + bottom), NSLayoutPriorityRequired);
    } else {
        if (!fh) eq(P, me.h, 1, 0, 0, f.size.height, NSLayoutPriorityRequired);
        else eq(P, me.h, 1, sup.h, -(sb.size.height > 0 ? f.size.height / sb.size.height : 0), 0, NSLayoutPriorityRequired);
        if (ft && !fb) {                                   /* bottom margin fixed */
            Expr e = {{0}, {0}, 0, bottom};
            expr_add(&e, me.t, 1); expr_add(&e, me.h, 1); expr_add(&e, sup.t, -1); expr_add(&e, sup.h, -1);
            add(P, &e, BN_EQ, NSLayoutPriorityRequired);
        } else if (ft && fb && sb.size.height > 0) {
            Expr e = {{0}, {0}, 0, 0};
            expr_add(&e, me.t, 1); expr_add(&e, me.h, 0.5); expr_add(&e, sup.t, -1);
            expr_add(&e, sup.h, -(top + f.size.height / 2) / sb.size.height);
            add(P, &e, BN_EQ, NSLayoutPriorityRequired);
        } else {
            eq(P, me.t, 1, sup.t, -1, top, NSLayoutPriorityRequired);
        }
    }
}

/* A view's frame in the root's coordinates, y down. */
static NSRect root_rect(NSView *v, NSView *root) {
    if (v == root || !v.superview) return NSMakeRect(0, 0, v.bounds.size.width, v.bounds.size.height);
    NSView *s = v.superview;
    NSRect r = root_rect(s, root), f = v.frame, sb = s.bounds;
    CGFloat top = s.isFlipped ? f.origin.y - sb.origin.y : sb.size.height - (f.origin.y - sb.origin.y) - f.size.height;
    return NSMakeRect(r.origin.x + f.origin.x - sb.origin.x, r.origin.y + top, f.size.width, f.size.height);
}

/* The weakest wish: stay where it is, so an unconstrained edge does not move. */
static void stay(BNLayoutPass *P, NSView *v) {
    Vars x = [P _bn_vars:v];
    NSRect r = root_rect(v, P->_root);
    int vars[4] = {x.l, x.t, x.w, x.h};
    double at[4] = {r.origin.x, r.origin.y, r.size.width, r.size.height};
    for (int i = 0; i < 4; i++) {
        double one = 1;
        bn_solver_add(P->_s, &vars[i], &one, 1, -at[i], BN_EQ, 1.0e-3);
    }
}

static void intrinsic(BNLayoutPass *P, NSView *v) {
    Vars x = [P _bn_vars:v];
    stay(P, v);
    NSSize s = v.intrinsicContentSize;
    if (s.width != NSViewNoIntrinsicMetric && s.width >= 0) {
        Expr e = {{x.w}, {1}, 1, -s.width};
        add(P, &e, BN_LE, [v contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationHorizontal]);
        add(P, &e, BN_GE, [v contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal]);
    }
    if (s.height != NSViewNoIntrinsicMetric && s.height >= 0) {
        Expr e = {{x.h}, {1}, 1, -s.height};
        add(P, &e, BN_LE, [v contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationVertical]);
        add(P, &e, BN_GE, [v contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationVertical]);
    }
    /* Sizes are never negative. */
    Expr w = {{x.w}, {1}, 1, 0}, h = {{x.h}, {1}, 1, 0};
    add(P, &w, BN_GE, NSLayoutPriorityRequired);
    add(P, &h, BN_GE, NSLayoutPriorityRequired);
}

static void collect(NSView *v, NSMutableArray *out) {
    [out addObjectsFromArray:v.constraints];
    NSArray *g = [v _bn_generatedConstraints];
    if (g) [out addObjectsFromArray:g];
    for (NSView *s in v.subviews) collect(s, out);
}

static BOOL in_tree(NSView *v, NSView *root) {
    for (; v; v = v.superview) if (v == root) return YES;
    return NO;
}

static void add_with_ancestors(BNLayoutPass *P, NSView *v) {
    for (; v; v = v.superview) {
        if ([P _bn_has:v]) return;
        [P _bn_addItem:v];
    }
}

static void place(BNLayoutPass *P, NSView *v) {
    for (NSView *sub in v.subviews) {
        if ([P _bn_has:sub] && !sub.translatesAutoresizingMaskIntoConstraints) {
            Vars me = [P _bn_vars:sub], sup = [P _bn_vars:v];
            double l = bn_solver_value(P->_s, me.l), t = bn_solver_value(P->_s, me.t);
            double w = fmax(0, bn_solver_value(P->_s, me.w)), h = fmax(0, bn_solver_value(P->_s, me.h));
            double sl = bn_solver_value(P->_s, sup.l), st = bn_solver_value(P->_s, sup.t);
            double sh = bn_solver_value(P->_s, sup.h);
            NSRect sb = v.bounds;
            double x = l - sl + sb.origin.x;
            double y = v.isFlipped ? t - st + sb.origin.y : (st + sh) - (t + h) + sb.origin.y;
            NSRect f = NSMakeRect(round(x * 2) / 2, round(y * 2) / 2, round(w * 2) / 2, round(h * 2) / 2);
            NSRect old = sub.frame;
            if (fabs(old.origin.x - f.origin.x) > 0.01 || fabs(old.origin.y - f.origin.y) > 0.01 ||
                fabs(old.size.width - f.size.width) > 0.01 || fabs(old.size.height - f.size.height) > 0.01)
                sub.frame = f;
        }
        place(P, sub);
    }
}

static void place_guides(BNLayoutPass *P) {
    for (id item in P->_items) {
        if (![item isKindOfClass:[NSLayoutGuide class]]) continue;
        NSLayoutGuide *g = item;
        NSView *o = g.owningView;
        if (!o || ![P _bn_has:o]) continue;
        Vars me = [P _bn_vars:g], ov = [P _bn_vars:o];
        double l = bn_solver_value(P->_s, me.l) - bn_solver_value(P->_s, ov.l);
        double t = bn_solver_value(P->_s, me.t) - bn_solver_value(P->_s, ov.t);
        double w = bn_solver_value(P->_s, me.w), h = bn_solver_value(P->_s, me.h);
        double oh = bn_solver_value(P->_s, ov.h);
        [g _bn_setFrame:NSMakeRect(l, o.isFlipped ? t : oh - t - h, w, h)];
    }
}

static BOOL in_pass;
static unsigned rearranged;

/* A view that places its own subviews (split views) moved them: what was
 * solved from their old frames is solved again. */
void bn_layout_note_rearranged(void) { rearranged++; }

static void solve(NSView *root) {
    @autoreleasepool {
        NSMutableArray *all = [NSMutableArray array];
        collect(root, all);
        if (all.count) {
            BNLayoutPass *P = [BNLayoutPass new];
            P->_s = bn_solver_new();
            P->_items = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality |
                                                           NSPointerFunctionsStrongMemory
                                              valueOptions:NSPointerFunctionsStrongMemory];
            P->_root = root;
            NSMutableArray *usable = [NSMutableArray array];
            for (NSLayoutConstraint *c in all) {
                NSView *a = item_view(c.firstItem), *b = c.secondItem ? item_view(c.secondItem) : nil;
                if (!a || !in_tree(a, root) || (c.secondItem && (!b || !in_tree(b, root)))) continue;
                [usable addObject:c];
                for (id item in @[c.firstItem ?: [NSNull null], c.secondItem ?: [NSNull null]]) {
                    if (item == [NSNull null]) continue;
                    if ([item isKindOfClass:[NSLayoutGuide class]]) {
                        add_with_ancestors(P, ((NSLayoutGuide *)item).owningView);
                        [P _bn_addItem:item];
                    } else {
                        add_with_ancestors(P, item);
                    }
                }
            }
            /* Structure: the root's size, frames kept by masks, intrinsic sizes, guides. */
            NSArray *items = [[P->_items keyEnumerator] allObjects];
            for (id item in items) {
                Vars x = [P _bn_vars:item];
                if (item == root) {
                    eq(P, x.l, 1, 0, 0, 0, NSLayoutPriorityRequired);
                    eq(P, x.t, 1, 0, 0, 0, NSLayoutPriorityRequired);
                    eq(P, x.w, 1, 0, 0, root.bounds.size.width, NSLayoutPriorityRequired);
                    eq(P, x.h, 1, 0, 0, root.bounds.size.height, NSLayoutPriorityRequired);
                } else if ([item isKindOfClass:[NSLayoutGuide class]]) {
                    NSLayoutGuide *g = item;
                    NSView *o = g.owningView;
                    Vars ov = [P _bn_vars:o];
                    NSEdgeInsets in = NSEdgeInsetsZero;
                    if (g == objc_getAssociatedObject(o, &kSafeGuide)) in = o.safeAreaInsets;
                    BOOL builtIn = g == objc_getAssociatedObject(o, &kSafeGuide) ||
                                   g == objc_getAssociatedObject(o, &kMarginsGuide);
                    if (builtIn) {
                        eq(P, x.l, 1, ov.l, -1, in.left, NSLayoutPriorityRequired);
                        eq(P, x.t, 1, ov.t, -1, in.top, NSLayoutPriorityRequired);
                        eq(P, x.w, 1, ov.w, -1, -(in.left + in.right), NSLayoutPriorityRequired);
                        eq(P, x.h, 1, ov.h, -1, -(in.top + in.bottom), NSLayoutPriorityRequired);
                    }
                } else {
                    NSView *v = item;
                    if (v.translatesAutoresizingMaskIntoConstraints) autoresizing(P, v);
                    else intrinsic(P, v);
                }
            }
            if (layout_debug > 0)
                fprintf(stderr, "layout: pass over %s: %lu constraints, %lu usable, %lu items\n",
                        object_getClassName(root), (unsigned long)all.count, (unsigned long)usable.count,
                        (unsigned long)P->_items.count);
            for (NSLayoutConstraint *c in usable) add_constraint(P, c);
            place(P, root);
            place_guides(P);
        }
    }
}

/* Solves the constraints of the tree rooted at root and sets frames. */
void bn_layout_tree(NSView *root) {
    if (in_pass || !root) return;
    if (layout_debug < 0) layout_debug = getenv("BITTEN_LAYOUT_DEBUG") != NULL;
    in_pass = YES;
    [root updateConstraintsForSubtreeIfNeeded];
    for (int i = 0; i < 4; i++) {
        unsigned before = rearranged;
        solve(root);
        if (rearranged == before) break;
    }
    in_pass = NO;
}

/* ---- stack views ---- */

@implementation NSStackView {
    NSMutableArray<NSView *> *_arranged;
    NSMapTable<NSView *, NSNumber *> *_custom;
    NSLayoutPriority _hug[2], _clip[2];
    BOOL _alignmentSet;
}
@synthesize orientation = _orientation, alignment = _alignment, edgeInsets = _edgeInsets,
            distribution = _distribution, spacing = _spacing, detachesHiddenViews = _detachesHiddenViews;

+ (instancetype)stackViewWithViews:(NSArray<NSView *> *)views {
    NSStackView *s = [[self alloc] initWithFrame:NSZeroRect];
    for (NSView *v in views) [s addArrangedSubview:v];
    return s;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _arranged = [NSMutableArray array];
        _custom = [NSMapTable weakToStrongObjectsMapTable];
        _orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _alignment = NSLayoutAttributeCenterY;
        _distribution = NSStackViewDistributionGravityAreas;
        _spacing = 8;
        _detachesHiddenViews = YES;
        _hug[0] = _hug[1] = NSLayoutPriorityDefaultLow;
        _clip[0] = _clip[1] = NSLayoutPriorityRequired;
    }
    return self;
}
- (void)_bn_changed { schedule(self); }
- (NSUserInterfaceLayoutOrientation)orientation { return _orientation; }
- (NSLayoutAttribute)alignment { return _alignment; }
- (CGFloat)spacing { return _spacing; }
- (NSStackViewDistribution)distribution { return _distribution; }
- (NSEdgeInsets)edgeInsets { return _edgeInsets; }
- (BOOL)detachesHiddenViews { return _detachesHiddenViews; }
- (void)setOrientation:(NSUserInterfaceLayoutOrientation)o {
    _orientation = o;
    if (!_alignmentSet) _alignment = o == NSUserInterfaceLayoutOrientationHorizontal ? NSLayoutAttributeCenterY
                                                                                     : NSLayoutAttributeCenterX;
    [self _bn_changed];
}
- (void)setAlignment:(NSLayoutAttribute)a { _alignment = a; _alignmentSet = YES; [self _bn_changed]; }
- (void)setSpacing:(CGFloat)s { _spacing = s; [self _bn_changed]; }
- (void)setDistribution:(NSStackViewDistribution)d { _distribution = d; [self _bn_changed]; }
- (void)setEdgeInsets:(NSEdgeInsets)e { _edgeInsets = e; [self _bn_changed]; }
- (void)setDetachesHiddenViews:(BOOL)b { _detachesHiddenViews = b; [self _bn_changed]; }

- (NSArray *)arrangedSubviews { return [_arranged copy]; }
- (void)insertArrangedSubview:(NSView *)v atIndex:(NSInteger)i {
    if (!v) return;
    [_arranged removeObjectIdenticalTo:v];
    if (i < 0 || (NSUInteger)i > _arranged.count) i = (NSInteger)_arranged.count;
    [_arranged insertObject:v atIndex:(NSUInteger)i];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    if (v.superview != self) [self addSubview:v];
    [self _bn_changed];
}
- (void)addArrangedSubview:(NSView *)v { [self insertArrangedSubview:v atIndex:(NSInteger)_arranged.count]; }
- (void)removeArrangedSubview:(NSView *)v { [_arranged removeObjectIdenticalTo:v]; [self _bn_changed]; }
- (NSArray *)views { return self.arrangedSubviews; }
- (void)setViews:(NSArray *)views {
    for (NSView *v in [_arranged copy]) { [self removeArrangedSubview:v]; [v removeFromSuperview]; }
    for (NSView *v in views) [self addArrangedSubview:v];
}
- (void)setViews:(NSArray *)views inGravity:(NSStackViewGravity)gravity { for (NSView *v in views) [self addArrangedSubview:v]; }
- (void)addView:(NSView *)view inGravity:(NSStackViewGravity)gravity { [self addArrangedSubview:view]; }
- (void)setCustomSpacing:(CGFloat)s afterView:(NSView *)v { if (v) [_custom setObject:@(s) forKey:v]; [self _bn_changed]; }
- (CGFloat)customSpacingAfterView:(NSView *)v { NSNumber *n = [_custom objectForKey:v]; return n ? n.doubleValue : _spacing; }
- (NSLayoutPriority)huggingPriorityForOrientation:(NSLayoutConstraintOrientation)o { return _hug[o ? 1 : 0]; }
- (void)setHuggingPriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o { _hug[o ? 1 : 0] = p; [self _bn_changed]; }
- (NSLayoutPriority)clippingResistancePriorityForOrientation:(NSLayoutConstraintOrientation)o { return _clip[o ? 1 : 0]; }
- (void)setClippingResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o { _clip[o ? 1 : 0] = p; }
- (void)setVisibilityPriority:(NSLayoutPriority)p forView:(NSView *)v { v.hidden = p <= NSStackViewVisibilityPriorityNotVisible; }

static NSLayoutConstraint *K(id a, NSLayoutAttribute aa, NSLayoutRelation r, id b, NSLayoutAttribute ba, CGFloat c,
                             NSLayoutPriority p) {
    NSLayoutConstraint *k = [NSLayoutConstraint constraintWithItem:a attribute:aa relatedBy:r toItem:b attribute:ba
                                                        multiplier:1 constant:c];
    k.priority = p;
    return k;
}

/* The arranged views placed one after another along the axis, aligned across it. */
- (NSArray<NSLayoutConstraint *> *)_bn_generatedConstraints {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    for (NSView *v in _arranged)
        if (v.superview == self && !(_detachesHiddenViews && v.isHidden)) [views addObject:v];
    BOOL h = _orientation == NSUserInterfaceLayoutOrientationHorizontal;
    NSLayoutAttribute lead = h ? NSLayoutAttributeLeading : NSLayoutAttributeTop;
    NSLayoutAttribute trail = h ? NSLayoutAttributeTrailing : NSLayoutAttributeBottom;
    NSLayoutAttribute size = h ? NSLayoutAttributeWidth : NSLayoutAttributeHeight;
    NSLayoutAttribute xlead = h ? NSLayoutAttributeTop : NSLayoutAttributeLeading;
    NSLayoutAttribute xtrail = h ? NSLayoutAttributeBottom : NSLayoutAttributeTrailing;
    NSLayoutAttribute xsize = h ? NSLayoutAttributeHeight : NSLayoutAttributeWidth;
    CGFloat inLead = h ? _edgeInsets.left : _edgeInsets.top, inTrail = h ? _edgeInsets.right : _edgeInsets.bottom;
    CGFloat inXLead = h ? _edgeInsets.top : _edgeInsets.left, inXTrail = h ? _edgeInsets.bottom : _edgeInsets.right;
    NSLayoutPriority hugMain = _hug[h ? 0 : 1], hugCross = _hug[h ? 1 : 0];
    if (!views.count) {
        [out addObject:K(self, size, 0, nil, 0, inLead + inTrail, hugMain)];
        return out;
    }
    /* along the axis */
    [out addObject:K(views[0], lead, 0, self, lead, inLead, NSLayoutPriorityRequired)];
    for (NSUInteger i = 1; i < views.count; i++) {
        CGFloat gap = [self customSpacingAfterView:views[i - 1]];
        NSLayoutRelation r = _distribution == NSStackViewDistributionEqualSpacing ? NSLayoutRelationGreaterThanOrEqual : 0;
        [out addObject:K(views[i], lead, r, views[i - 1], trail, gap, NSLayoutPriorityRequired)];
        if (_distribution == NSStackViewDistributionFillEqually)
            [out addObject:K(views[i], size, 0, views[0], size, 0, NSLayoutPriorityRequired)];
    }
    if (_distribution == NSStackViewDistributionGravityAreas) {
        [out addObject:K(self, trail, NSLayoutRelationGreaterThanOrEqual, views.lastObject, trail, inTrail,
                         NSLayoutPriorityRequired)];
        [out addObject:K(self, trail, 0, views.lastObject, trail, inTrail, hugMain)];
    } else {
        [out addObject:K(self, trail, 0, views.lastObject, trail, inTrail, NSLayoutPriorityRequired)];
    }
    /* across it */
    for (NSView *v in views) {
        [out addObject:K(v, xlead, NSLayoutRelationGreaterThanOrEqual, self, xlead, inXLead, NSLayoutPriorityRequired)];
        [out addObject:K(self, xtrail, NSLayoutRelationGreaterThanOrEqual, v, xtrail, inXTrail, NSLayoutPriorityRequired)];
        [out addObject:K(self, xsize, 0, v, xsize, inXLead + inXTrail, hugCross)];
        switch (_alignment) {
        case NSLayoutAttributeTop: case NSLayoutAttributeLeading: case NSLayoutAttributeLeft:
            [out addObject:K(v, xlead, 0, self, xlead, inXLead, NSLayoutPriorityRequired)];
            break;
        case NSLayoutAttributeBottom: case NSLayoutAttributeTrailing: case NSLayoutAttributeRight:
            [out addObject:K(self, xtrail, 0, v, xtrail, inXTrail, NSLayoutPriorityRequired)];
            break;
        case NSLayoutAttributeFirstBaseline: case NSLayoutAttributeLastBaseline:
            if (v != views[0])
                [out addObject:K(v, _alignment, 0, views[0], _alignment, 0, NSLayoutPriorityRequired)];
            break;
        case NSLayoutAttributeWidth: case NSLayoutAttributeHeight: case NSLayoutAttributeNotAnAttribute:
            [out addObject:K(v, xlead, 0, self, xlead, inXLead, NSLayoutPriorityRequired)];
            [out addObject:K(self, xtrail, 0, v, xtrail, inXTrail, NSLayoutPriorityRequired)];
            break;
        default: {
            NSLayoutAttribute center = h ? NSLayoutAttributeCenterY : NSLayoutAttributeCenterX;
            [out addObject:K(v, center, 0, self, center, (inXLead - inXTrail) / 2, NSLayoutPriorityRequired)];
        }
        }
    }
    return out;
}
@end
