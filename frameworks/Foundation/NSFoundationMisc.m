/* Smaller Foundation classes: NSLocale (as its identifier), NSCache,
 * NSAssertionHandler, NSValueTransformer's names, NSUserActivity,
 * NSAffineTransform, NSDecimalNumber over double, NSInvocation's
 * argument storage, and keyed archiving through property lists. */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* ---- NSLocale ---- */

@implementation NSLocale (Foundation)
static const char k_locale_ident;
+ (instancetype)localeWithLocaleIdentifier:(NSString *)ident { return [[self alloc] initWithLocaleIdentifier:ident]; }
- (instancetype)initWithLocaleIdentifier:(NSString *)ident {
    self = [super init];
    objc_setAssociatedObject(self, &k_locale_ident, [ident copy] ?: @"en_US", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}
- (NSString *)localeIdentifier { return objc_getAssociatedObject(self, &k_locale_ident) ?: @"en_US"; }
static NSString *env_locale(void) {
    const char *l = getenv("LC_ALL");
    if (!l || !*l) l = getenv("LANG");
    if (!l || !*l || !strcmp(l, "C") || !strcmp(l, "POSIX")) return @"en_US";
    NSString *s = [NSString stringWithUTF8String:l];
    NSRange dot = [s rangeOfString:@"."];
    return dot.location == NSNotFound ? s : [s substringToIndex:dot.location];
}
+ (NSLocale *)currentLocale { return [self localeWithLocaleIdentifier:env_locale()]; }
+ (NSLocale *)autoupdatingCurrentLocale { return [self currentLocale]; }
+ (NSLocale *)systemLocale { return [self localeWithLocaleIdentifier:@""]; }
+ (NSArray<NSString *> *)availableLocaleIdentifiers { return @[ @"en_US", @"en_GB", @"de_DE", @"fr_FR", @"ja_JP" ]; }
+ (NSArray<NSString *> *)preferredLanguages {
    NSString *l = env_locale();
    return @[ [l stringByReplacingOccurrencesOfString:@"_" withString:@"-"] ];
}
- (NSString *)languageCode {
    NSString *i = self.localeIdentifier;
    NSRange u = [i rangeOfString:@"_"];
    return u.location == NSNotFound ? i : [i substringToIndex:u.location];
}
- (NSString *)countryCode {
    NSString *i = self.localeIdentifier;
    NSRange u = [i rangeOfString:@"_"];
    return u.location == NSNotFound ? nil : [i substringFromIndex:NSMaxRange(u)];
}
- (NSString *)localizedStringForLocaleIdentifier:(NSString *)ident { return ident; }
- (id)objectForKey:(id)key { return nil; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSLocale class]] && [[o localeIdentifier] isEqual:self.localeIdentifier]; }
- (NSUInteger)hash { return self.localeIdentifier.hash; }
- (NSString *)description { return [NSString stringWithFormat:@"%@ (fixed)", self.localeIdentifier]; }
@end

/* ---- NSCache: a dictionary with limits that evicts the oldest ---- */

@implementation NSCache {
    NSMutableDictionary *_objects;
    NSMutableArray *_order;
    NSMutableDictionary *_costs;
    NSUInteger _totalCost, _countLimit, _totalCostLimit;
    NSString *_name;
    BOOL _evicts;
    __weak id<NSCacheDelegate> _delegate;
}
- (instancetype)init {
    self = [super init];
    _objects = [NSMutableDictionary dictionary];
    _order = [NSMutableArray array];
    _costs = [NSMutableDictionary dictionary];
    _name = @"";
    _evicts = YES;
    return self;
}
- (NSString *)name { return _name; }
- (void)setName:(NSString *)n { _name = [n copy] ?: @""; }
- (id<NSCacheDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSCacheDelegate>)d { _delegate = d; }
- (NSUInteger)countLimit { return _countLimit; }
- (void)setCountLimit:(NSUInteger)l {
    _countLimit = l;
    [self _bn_trim];
}
- (NSUInteger)totalCostLimit { return _totalCostLimit; }
- (void)setTotalCostLimit:(NSUInteger)l {
    _totalCostLimit = l;
    [self _bn_trim];
}
- (BOOL)evictsObjectsWithDiscardedContent { return _evicts; }
- (void)setEvictsObjectsWithDiscardedContent:(BOOL)b { _evicts = b; }
- (id)objectForKey:(id)key {
    @synchronized(self) { return key ? _objects[key] : nil; }
}
- (void)setObject:(id)obj forKey:(id)key { [self setObject:obj forKey:key cost:0]; }
- (void)setObject:(id)obj forKey:(id)key cost:(NSUInteger)cost {
    if (!key) return;
    if (!obj) {
        [self removeObjectForKey:key];
        return;
    }
    @synchronized(self) {
        if (_objects[key]) {
            _totalCost -= [_costs[key] unsignedIntegerValue];
            [_order removeObject:key];
        }
        _objects[key] = obj;
        _costs[key] = @(cost);
        _totalCost += cost;
        [_order addObject:key];
    }
    [self _bn_trim];
}
- (void)removeObjectForKey:(id)key {
    if (!key) return;
    @synchronized(self) {
        if (!_objects[key]) return;
        _totalCost -= [_costs[key] unsignedIntegerValue];
        [_objects removeObjectForKey:key];
        [_costs removeObjectForKey:key];
        [_order removeObject:key];
    }
}
- (void)removeAllObjects {
    @synchronized(self) {
        [_objects removeAllObjects];
        [_costs removeAllObjects];
        [_order removeAllObjects];
        _totalCost = 0;
    }
}
- (void)_bn_trim {
    for (;;) {
        id key, obj;
        @synchronized(self) {
            BOOL over = (_countLimit && _objects.count > _countLimit) || (_totalCostLimit && _totalCost > _totalCostLimit);
            if (!over || !_order.count) return;
            key = _order.firstObject;
            obj = _objects[key];
        }
        id<NSCacheDelegate> d = _delegate;
        if ([d respondsToSelector:@selector(cache:willEvictObject:)]) [d cache:self willEvictObject:obj];
        [self removeObjectForKey:key];
    }
}
@end

/* ---- NSAssertionHandler ---- */

@implementation NSAssertionHandler
+ (NSAssertionHandler *)currentHandler {
    NSMutableDictionary *t = [NSThread currentThread].threadDictionary;
    NSAssertionHandler *h = t[@"NSAssertionHandler"];
    if (!h) t[@"NSAssertionHandler"] = h = [NSAssertionHandler new];
    return h;
}
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)file lineNumber:(NSInteger)line
                  description:(NSString *)format, ... {
    va_list ap;
    va_start(ap, format);
    NSString *d = format ? [[NSString alloc] initWithFormat:format arguments:ap] : @"";
    va_end(ap);
    NSLog(@"*** Assertion failure in -[%@ %@], %@:%ld", [object class], NSStringFromSelector(selector), file, (long)line);
    [NSException raise:NSInternalInconsistencyException format:@"%@", d];
}
- (void)handleFailureInFunction:(NSString *)function file:(NSString *)file lineNumber:(NSInteger)line
                    description:(NSString *)format, ... {
    va_list ap;
    va_start(ap, format);
    NSString *d = format ? [[NSString alloc] initWithFormat:format arguments:ap] : @"";
    va_end(ap);
    NSLog(@"*** Assertion failure in %@(), %@:%ld", function, file, (long)line);
    [NSException raise:NSInternalInconsistencyException format:@"%@", d];
}
@end

NSValueTransformerName const NSNegateBooleanTransformerName = @"NSNegateBoolean";
NSValueTransformerName const NSIsNilTransformerName = @"NSIsNil";
NSValueTransformerName const NSIsNotNilTransformerName = @"NSIsNotNil";
NSValueTransformerName const NSUnarchiveFromDataTransformerName = @"NSUnarchiveFromData";
NSValueTransformerName const NSKeyedUnarchiveFromDataTransformerName = @"NSKeyedUnarchiveFromData";
NSValueTransformerName const NSSecureUnarchiveFromDataTransformerName = @"NSSecureUnarchiveFromData";

/* ---- NSUserActivity: handoff and indexing state, not published ---- */

@implementation NSUserActivity {
    NSString *_activityType, *_title, *_persistentIdentifier;
    NSMutableDictionary *_userInfo;
    NSURL *_webpageURL;
    BOOL _eligibleForHandoff, _eligibleForSearch, _eligibleForPublicIndexing, _needsSave, _current;
    NSSet<NSString *> *_requiredUserInfoKeys, *_keywords;
    __weak id<NSUserActivityDelegate> _delegate;
}
- (instancetype)initWithActivityType:(NSString *)type {
    self = [super init];
    _activityType = [type copy];
    _userInfo = [NSMutableDictionary dictionary];
    _eligibleForHandoff = YES;
    return self;
}
- (instancetype)init { return [self initWithActivityType:[NSBundle mainBundle].bundleIdentifier ?: @"activity"]; }
- (NSString *)activityType { return _activityType; }
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t { _title = [t copy]; }
- (NSDictionary *)userInfo { return [_userInfo copy]; }
- (void)setUserInfo:(NSDictionary *)u { _userInfo = [u mutableCopy] ?: [NSMutableDictionary dictionary]; }
- (void)addUserInfoEntriesFromDictionary:(NSDictionary *)d { [_userInfo addEntriesFromDictionary:d]; }
- (NSSet *)requiredUserInfoKeys { return _requiredUserInfoKeys; }
- (void)setRequiredUserInfoKeys:(NSSet *)k { _requiredUserInfoKeys = [k copy]; }
- (NSSet *)keywords { return _keywords ?: [NSSet set]; }
- (void)setKeywords:(NSSet *)k { _keywords = [k copy]; }
- (NSURL *)webpageURL { return _webpageURL; }
- (void)setWebpageURL:(NSURL *)u { _webpageURL = u; }
- (NSString *)persistentIdentifier { return _persistentIdentifier; }
- (void)setPersistentIdentifier:(NSString *)p { _persistentIdentifier = [p copy]; }
- (BOOL)isEligibleForHandoff { return _eligibleForHandoff; }
- (void)setEligibleForHandoff:(BOOL)b { _eligibleForHandoff = b; }
- (BOOL)isEligibleForSearch { return _eligibleForSearch; }
- (void)setEligibleForSearch:(BOOL)b { _eligibleForSearch = b; }
- (BOOL)isEligibleForPublicIndexing { return _eligibleForPublicIndexing; }
- (void)setEligibleForPublicIndexing:(BOOL)b { _eligibleForPublicIndexing = b; }
- (BOOL)needsSave { return _needsSave; }
- (void)setNeedsSave:(BOOL)b { _needsSave = b; }
- (id<NSUserActivityDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSUserActivityDelegate>)d { _delegate = d; }
- (void)becomeCurrent { _current = YES; }
- (void)resignCurrent { _current = NO; }
- (void)invalidate { _current = NO; }
@end

/* ---- NSAffineTransform ---- */

@implementation NSAffineTransform {
    NSAffineTransformStruct _t;
}
+ (NSAffineTransform *)transform { return [self new]; }
- (instancetype)init {
    self = [super init];
    _t = (NSAffineTransformStruct){1, 0, 0, 1, 0, 0};
    return self;
}
- (instancetype)initWithTransform:(NSAffineTransform *)t {
    self = [super init];
    _t = t ? t.transformStruct : (NSAffineTransformStruct){1, 0, 0, 1, 0, 0};
    return self;
}
- (NSAffineTransformStruct)transformStruct { return _t; }
- (void)setTransformStruct:(NSAffineTransformStruct)t { _t = t; }
- (void)prependTransform:(NSAffineTransform *)o {
    NSAffineTransformStruct a = o.transformStruct, b = _t;
    _t = (NSAffineTransformStruct){a.m11 * b.m11 + a.m12 * b.m21, a.m11 * b.m12 + a.m12 * b.m22,
                                   a.m21 * b.m11 + a.m22 * b.m21, a.m21 * b.m12 + a.m22 * b.m22,
                                   a.tX * b.m11 + a.tY * b.m21 + b.tX, a.tX * b.m12 + a.tY * b.m22 + b.tY};
}
- (void)appendTransform:(NSAffineTransform *)o {
    NSAffineTransformStruct a = _t, b = o.transformStruct;
    _t = (NSAffineTransformStruct){a.m11 * b.m11 + a.m12 * b.m21, a.m11 * b.m12 + a.m12 * b.m22,
                                   a.m21 * b.m11 + a.m22 * b.m21, a.m21 * b.m12 + a.m22 * b.m22,
                                   a.tX * b.m11 + a.tY * b.m21 + b.tX, a.tX * b.m12 + a.tY * b.m22 + b.tY};
}
- (void)translateXBy:(CGFloat)x yBy:(CGFloat)y {
    NSAffineTransform *t = [NSAffineTransform new];
    t.transformStruct = (NSAffineTransformStruct){1, 0, 0, 1, x, y};
    [self prependTransform:t];
}
- (void)scaleBy:(CGFloat)s { [self scaleXBy:s yBy:s]; }
- (void)scaleXBy:(CGFloat)x yBy:(CGFloat)y {
    NSAffineTransform *t = [NSAffineTransform new];
    t.transformStruct = (NSAffineTransformStruct){x, 0, 0, y, 0, 0};
    [self prependTransform:t];
}
- (void)rotateByRadians:(CGFloat)a {
    NSAffineTransform *t = [NSAffineTransform new];
    t.transformStruct = (NSAffineTransformStruct){cos(a), sin(a), -sin(a), cos(a), 0, 0};
    [self prependTransform:t];
}
- (void)rotateByDegrees:(CGFloat)a { [self rotateByRadians:a * M_PI / 180]; }
- (void)invert {
    NSAffineTransformStruct t = _t;
    CGFloat det = t.m11 * t.m22 - t.m12 * t.m21;
    if (det == 0) return;
    _t = (NSAffineTransformStruct){t.m22 / det, -t.m12 / det, -t.m21 / det, t.m11 / det,
                                   (t.m21 * t.tY - t.m22 * t.tX) / det, (t.m12 * t.tX - t.m11 * t.tY) / det};
}
- (NSPoint)transformPoint:(NSPoint)p {
    return NSMakePoint(_t.m11 * p.x + _t.m21 * p.y + _t.tX, _t.m12 * p.x + _t.m22 * p.y + _t.tY);
}
- (NSSize)transformSize:(NSSize)s {
    return NSMakeSize(_t.m11 * s.width + _t.m21 * s.height, _t.m12 * s.width + _t.m22 * s.height);
}
- (id)copyWithZone:(NSZone *)zone { return [[NSAffineTransform alloc] initWithTransform:self]; }
@end

/* ---- NSDecimalNumber, over double precision ---- */

@implementation NSDecimalNumber {
    double _value;
}
+ (NSDecimalNumber *)zero { return [[self alloc] initWithDouble:0]; }
+ (NSDecimalNumber *)one { return [[self alloc] initWithDouble:1]; }
+ (NSDecimalNumber *)notANumber { return [[self alloc] initWithDouble:NAN]; }
+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)s { return [[self alloc] initWithString:s]; }
+ (NSDecimalNumber *)decimalNumberWithMantissa:(unsigned long long)m exponent:(short)e isNegative:(BOOL)neg {
    return [[self alloc] initWithDouble:(neg ? -1.0 : 1.0) * (double)m * pow(10, e)];
}
- (instancetype)initWithDouble:(double)v {
    self = [super init];
    _value = v;
    return self;
}
- (instancetype)initWithString:(NSString *)s { return [self initWithDouble:s ? s.doubleValue : NAN]; }
- (instancetype)initWithMantissa:(unsigned long long)m exponent:(short)e isNegative:(BOOL)neg {
    return [self initWithDouble:(neg ? -1.0 : 1.0) * (double)m * pow(10, e)];
}
- (double)doubleValue { return _value; }
- (float)floatValue { return (float)_value; }
- (long long)longLongValue { return (long long)_value; }
- (NSInteger)integerValue { return (NSInteger)_value; }
- (int)intValue { return (int)_value; }
- (BOOL)boolValue { return _value != 0; }
- (const char *)objCType { return "d"; }
- (NSString *)stringValue { return [NSString stringWithFormat:@"%.15g", _value]; }
- (NSString *)description { return self.stringValue; }
- (NSString *)descriptionWithLocale:(id)locale { return self.stringValue; }
- (NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)o { return [[NSDecimalNumber alloc] initWithDouble:_value + o.doubleValue]; }
- (NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)o { return [[NSDecimalNumber alloc] initWithDouble:_value - o.doubleValue]; }
- (NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)o { return [[NSDecimalNumber alloc] initWithDouble:_value * o.doubleValue]; }
- (NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)o { return [[NSDecimalNumber alloc] initWithDouble:_value / o.doubleValue]; }
- (NSDecimalNumber *)decimalNumberByRaisingToPower:(NSUInteger)p { return [[NSDecimalNumber alloc] initWithDouble:pow(_value, (double)p)]; }
- (NSComparisonResult)compare:(NSNumber *)o {
    double v = o.doubleValue;
    return _value < v ? NSOrderedAscending : _value > v ? NSOrderedDescending : NSOrderedSame;
}
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSNumber class]] && [o doubleValue] == _value; }
- (NSUInteger)hash { return (NSUInteger)_value; }
- (id)copyWithZone:(NSZone *)zone { return self; }
@end
