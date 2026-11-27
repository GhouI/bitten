/* Key-value coding (valueForKey: / setValue:forKey: through accessors) and
 * key-value observing: observers registered on an object are told about
 * changes announced with -willChangeValueForKey: / -didChangeValueForKey:.
 * Classes are not rewritten to announce changes from their setters
 * automatically; Foundation classes whose values observers care about
 * (NSUserDefaults) announce their own. Key paths are observed as a whole. */
#import "FoundationInternal.h"

NSKeyValueChangeKey const NSKeyValueChangeKindKey = @"kind";
NSKeyValueChangeKey const NSKeyValueChangeNewKey = @"new";
NSKeyValueChangeKey const NSKeyValueChangeOldKey = @"old";
NSKeyValueChangeKey const NSKeyValueChangeIndexesKey = @"indexes";
NSKeyValueChangeKey const NSKeyValueChangeNotificationIsPriorKey = @"notificationIsPrior";

@interface BNObserverEntry : NSObject {
  @public
    __weak id observer;
    NSString *keyPath;
    NSKeyValueObservingOptions options;
    void *context;
}
@end
@implementation BNObserverEntry
@end

/* Per observed object: its observers and the old values of changes in progress. */
@interface BNObservationInfo : NSObject {
  @public
    NSMutableArray<BNObserverEntry *> *entries;
    NSMutableDictionary<NSString *, id> *pendingOld;
}
@end
@implementation BNObservationInfo
@end

static const char kInfoKey;

static BNObservationInfo *info_of(id object, BOOL create) {
    BNObservationInfo *info = objc_getAssociatedObject(object, &kInfoKey);
    if (!info && create) {
        info = [BNObservationInfo new];
        info->entries = [NSMutableArray array];
        info->pendingOld = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(object, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return info;
}

static NSArray<BNObserverEntry *> *entries_for(id object, NSString *key) {
    BNObservationInfo *info = info_of(object, NO);
    if (!info) return @[];
    NSMutableArray *out = [NSMutableArray array];
    @synchronized(info) {
        for (BNObserverEntry *e in info->entries)
            if (e->observer && [e->keyPath isEqualToString:key]) [out addObject:e];
    }
    return out;
}

static void notify(id object, BNObserverEntry *e, NSDictionary *change) {
    id observer = e->observer;
    if (!observer) return;
    [observer observeValueForKeyPath:e->keyPath ofObject:object change:change context:e->context];
}

/* Structs and other values without a case of their own (CGRect, NSRange,
 * short integers) go through an invocation, boxed in an NSValue. */
static id kvc_get_boxed(id self, SEL sel) {
    NSMethodSignature *sig = [self methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.selector = sel;
    NSUInteger size = sig.methodReturnLength;
    void *buf = calloc(1, size ? size : 1);
    [inv invokeWithTarget:self];
    [inv getReturnValue:buf];
    const char *t = sig.methodReturnType;
    id v;
    switch (*t) {
    case 's': v = @(*(short *)buf); break;
    case 'S': v = @(*(unsigned short *)buf); break;
    case 'C': v = @(*(unsigned char *)buf); break;
    default: v = [NSValue valueWithBytes:buf objCType:t]; break;
    }
    free(buf);
    return v;
}
static void kvc_set_boxed(id self, SEL sel, id value) {
    NSMethodSignature *sig = [self methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments < 3) return;
    const char *t = [sig getArgumentTypeAtIndex:2];
    NSUInteger size = 0;
    NSGetSizeAndAlignment(t, &size, NULL);
    void *buf = calloc(1, size ? size : 1);
    switch (*t) {
    case 's': *(short *)buf = [value shortValue]; break;
    case 'S': *(unsigned short *)buf = [value unsignedShortValue]; break;
    case 'C': *(unsigned char *)buf = (unsigned char)[value unsignedIntValue]; break;
    default:
        /* nil for a struct sets it to zero, as setNilValueForKey: would */
        if ([value isKindOfClass:[NSValue class]]) [(NSValue *)value getValue:buf size:size];
        break;
    }
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.selector = sel;
    [inv setArgument:buf atIndex:2];
    [inv invokeWithTarget:self];
    free(buf);
}

@implementation NSObject (BittenKeyValueCoding)

/* The getter for `key`: key, isKey, getKey; then an ivar _key / key. */
- (id)valueForKey:(NSString *)key {
    if (!key) return nil;
    NSString *cap = key.length ? [[[key substringToIndex:1] uppercaseString] stringByAppendingString:[key substringFromIndex:1]] : key;
    for (NSString *name in @[ key, [@"is" stringByAppendingString:cap], [@"get" stringByAppendingString:cap] ]) {
        SEL sel = NSSelectorFromString(name);
        if (![self respondsToSelector:sel]) continue;
        const char *types = method_getTypeEncoding(class_getInstanceMethod(object_getClass(self), sel));
        char ret = types ? types[0] : '@';
        switch (ret) {
        case '@': case '#': return ((id(*)(id, SEL))objc_msgSend)(self, sel);
        case 'c': case 'B': return @(((BOOL(*)(id, SEL))objc_msgSend)(self, sel));
        case 'i': return @(((int(*)(id, SEL))objc_msgSend)(self, sel));
        case 'I': return @(((unsigned(*)(id, SEL))objc_msgSend)(self, sel));
        case 'q': case 'l': return @(((long long(*)(id, SEL))objc_msgSend)(self, sel));
        case 'Q': case 'L': return @(((unsigned long long(*)(id, SEL))objc_msgSend)(self, sel));
        case 'd': return @(((double(*)(id, SEL))objc_msgSend)(self, sel));
        case 'f': return @(((float(*)(id, SEL))objc_msgSend)(self, sel));
        case 'v': return nil;
        default: return kvc_get_boxed(self, sel);
        }
    }
    for (NSString *name in @[ [@"_" stringByAppendingString:key], key ]) {
        Ivar iv = class_getInstanceVariable(object_getClass(self), name.UTF8String);
        if (iv) {
            const char *t = ivar_getTypeEncoding(iv);
            if (t && t[0] == '@') return object_getIvar(self, iv);
        }
    }
    return [self valueForUndefinedKey:key];
}
- (id)valueForUndefinedKey:(NSString *)key {
    BNRaise("NSUnknownKeyException", "[%s valueForUndefinedKey:]: this class is not key value coding-compliant for the key %s.",
            object_getClassName(self), key.UTF8String);
}
- (id)valueForKeyPath:(NSString *)keyPath {
    id v = self;
    for (NSString *k in [keyPath componentsSeparatedByString:@"."]) {
        v = [v valueForKey:k];
        if (!v) return nil;
    }
    return v;
}
- (void)setValue:(id)value forKey:(NSString *)key {
    NSString *cap = key.length ? [[[key substringToIndex:1] uppercaseString] stringByAppendingString:[key substringFromIndex:1]] : key;
    SEL sel = NSSelectorFromString([NSString stringWithFormat:@"set%@:", cap]);
    if ([self respondsToSelector:sel]) {
        const char *types = method_getTypeEncoding(class_getInstanceMethod(object_getClass(self), sel));
        /* types: v24@0:8X16 — find the argument's type after the second ':' */
        const char *arg = types ? strchr(types, ':') : NULL;
        while (arg && *arg && (*arg == ':' || (*arg >= '0' && *arg <= '9'))) arg++;
        char t = arg && *arg ? *arg : '@';
        [self willChangeValueForKey:key];
        switch (t) {
        case 'c': case 'B': ((void (*)(id, SEL, BOOL))objc_msgSend)(self, sel, [value boolValue]); break;
        case 'i': ((void (*)(id, SEL, int))objc_msgSend)(self, sel, [value intValue]); break;
        case 'q': case 'l': ((void (*)(id, SEL, long long))objc_msgSend)(self, sel, [value longLongValue]); break;
        case 'Q': case 'L': ((void (*)(id, SEL, unsigned long long))objc_msgSend)(self, sel, [value unsignedLongLongValue]); break;
        case 'd': ((void (*)(id, SEL, double))objc_msgSend)(self, sel, [value doubleValue]); break;
        case 'f': ((void (*)(id, SEL, float))objc_msgSend)(self, sel, [value floatValue]); break;
        case '@': case '#': ((void (*)(id, SEL, id))objc_msgSend)(self, sel, value); break;
        default: kvc_set_boxed(self, sel, value); break;
        }
        [self didChangeValueForKey:key];
        return;
    }
    [self setValue:value forUndefinedKey:key];
}
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    BNRaise("NSUnknownKeyException", "[%s setValue:forUndefinedKey:]: this class is not key value coding-compliant for the key %s.",
            object_getClassName(self), key.UTF8String);
}
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath {
    NSArray *parts = [keyPath componentsSeparatedByString:@"."];
    id target = self;
    for (NSUInteger i = 0; i + 1 < parts.count; i++) target = [target valueForKey:parts[i]];
    [target setValue:value forKey:parts.lastObject];
}
@end

@implementation NSObject (BittenKeyValueObserving)

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options
            context:(void *)context {
    BNObserverEntry *e = [BNObserverEntry new];
    e->observer = observer;
    e->keyPath = [keyPath copy];
    e->options = options;
    e->context = context;
    BNObservationInfo *info = info_of(self, YES);
    @synchronized(info) { [info->entries addObject:e]; }
    if (options & NSKeyValueObservingOptionInitial) {
        NSMutableDictionary *change = [NSMutableDictionary dictionaryWithObject:@(NSKeyValueChangeSetting) forKey:NSKeyValueChangeKindKey];
        if (options & NSKeyValueObservingOptionNew) change[NSKeyValueChangeNewKey] = [self valueForKeyPath:keyPath] ?: [NSNull null];
        notify(self, e, change);
    }
}
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(void *)context {
    BNObservationInfo *info = info_of(self, NO);
    if (!info) return;
    @synchronized(info) {
        for (NSInteger i = (NSInteger)info->entries.count - 1; i >= 0; i--) {
            BNObserverEntry *e = info->entries[i];
            if ((!e->observer || e->observer == observer) && [e->keyPath isEqualToString:keyPath] &&
                (!context || e->context == context)) {
                [info->entries removeObjectAtIndex:i];
                if (context) break;
            }
        }
    }
}
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath {
    [self removeObserver:observer forKeyPath:keyPath context:NULL];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
}

- (void)willChangeValueForKey:(NSString *)key {
    NSArray *entries = entries_for(self, key);
    if (!entries.count) return;
    BOOL wantsOld = NO;
    for (BNObserverEntry *e in entries) wantsOld |= (e->options & NSKeyValueObservingOptionOld) != 0;
    id old = wantsOld ? ([self valueForKeyPath:key] ?: [NSNull null]) : nil;
    BNObservationInfo *info = info_of(self, YES);
    @synchronized(info) {
        if (old) info->pendingOld[key] = old;
    }
    for (BNObserverEntry *e in entries) {
        if (!(e->options & NSKeyValueObservingOptionPrior)) continue;
        NSMutableDictionary *change = [NSMutableDictionary dictionaryWithObject:@(NSKeyValueChangeSetting) forKey:NSKeyValueChangeKindKey];
        change[NSKeyValueChangeNotificationIsPriorKey] = @YES;
        if ((e->options & NSKeyValueObservingOptionOld) && old) change[NSKeyValueChangeOldKey] = old;
        notify(self, e, change);
    }
}
- (void)didChangeValueForKey:(NSString *)key {
    NSArray *entries = entries_for(self, key);
    if (!entries.count) return;
    BNObservationInfo *info = info_of(self, YES);
    id old;
    @synchronized(info) {
        old = info->pendingOld[key];
        [info->pendingOld removeObjectForKey:key];
    }
    BOOL wantsNew = NO;
    for (BNObserverEntry *e in entries) wantsNew |= (e->options & NSKeyValueObservingOptionNew) != 0;
    id new = wantsNew ? ([self valueForKeyPath:key] ?: [NSNull null]) : nil;
    for (BNObserverEntry *e in entries) {
        NSMutableDictionary *change = [NSMutableDictionary dictionaryWithObject:@(NSKeyValueChangeSetting) forKey:NSKeyValueChangeKindKey];
        if ((e->options & NSKeyValueObservingOptionNew) && new) change[NSKeyValueChangeNewKey] = new;
        if ((e->options & NSKeyValueObservingOptionOld) && old) change[NSKeyValueChangeOldKey] = old;
        notify(self, e, change);
    }
}
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key { return YES; }
@end
