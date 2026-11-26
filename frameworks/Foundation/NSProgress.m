/* NSProgress: unit counts, a tree of children that report into their
 * parents' counts, cancellation and pausing with their handlers. */

#import <Foundation/Foundation.h>

@implementation NSProgress {
    int64_t _total, _completed;
    BOOL _cancelled, _paused, _cancellable, _pausable;
    void (^_cancellationHandler)(void);
    void (^_pausingHandler)(void);
    void (^_resumingHandler)(void);
    NSMutableDictionary *_userInfo;
    NSString *_localizedDescription, *_localizedAdditionalDescription, *_kind;
    __weak NSProgress *_parent;
    int64_t _pendingInParent;
    NSMutableArray<NSProgress *> *_children;
}
+ (NSProgress *)currentProgress { return nil; }
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)count {
    NSProgress *p = [[self alloc] initWithParent:nil userInfo:nil];
    p.totalUnitCount = count;
    return p;
}
+ (NSProgress *)discreteProgressWithTotalUnitCount:(int64_t)count { return [self progressWithTotalUnitCount:count]; }
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)count parent:(NSProgress *)parent
                          pendingUnitCount:(int64_t)pending {
    NSProgress *p = [self progressWithTotalUnitCount:count];
    [parent addChild:p withPendingUnitCount:pending];
    return p;
}
- (instancetype)init { return [self initWithParent:nil userInfo:nil]; }
- (instancetype)initWithParent:(NSProgress *)parent userInfo:(NSDictionary *)userInfo {
    self = [super init];
    _userInfo = userInfo ? [userInfo mutableCopy] : [NSMutableDictionary dictionary];
    _cancellable = YES;
    _children = [NSMutableArray array];
    return self;
}
- (void)addChild:(NSProgress *)child withPendingUnitCount:(int64_t)pending {
    if (!child) return;
    child->_parent = self;
    child->_pendingInParent = pending;
    [_children addObject:child];
    if (_cancelled) [child cancel];
    [self _changed];
}
- (double)fractionCompleted {
    if (_total <= 0) return _total == 0 && _completed > 0 ? 1 : 0;
    double done = (double)_completed;
    for (NSProgress *c in _children)
        if (c->_completed < c->_total || c->_total <= 0) done += c.fractionCompleted * (double)c->_pendingInParent;
    double f = done / (double)_total;
    return f > 1 ? 1 : f;
}
/* A child that finishes adds its pending units to its parent. */
- (void)_changed {
    [self willChangeValueForKey:@"fractionCompleted"];
    [self didChangeValueForKey:@"fractionCompleted"];
    NSProgress *p = _parent;
    if (!p) return;
    if (_total > 0 && _completed >= _total) {
        [p->_children removeObject:self];
        _parent = nil;
        p.completedUnitCount = p->_completed + _pendingInParent;
    } else {
        [p _changed];
    }
}
- (int64_t)totalUnitCount { return _total; }
- (void)setTotalUnitCount:(int64_t)n {
    [self willChangeValueForKey:@"totalUnitCount"];
    _total = n;
    [self didChangeValueForKey:@"totalUnitCount"];
    [self _changed];
}
- (int64_t)completedUnitCount { return _completed; }
- (void)setCompletedUnitCount:(int64_t)n {
    [self willChangeValueForKey:@"completedUnitCount"];
    _completed = n;
    [self didChangeValueForKey:@"completedUnitCount"];
    [self _changed];
}
- (BOOL)isFinished { return _total > 0 ? _completed >= _total : _completed > 0 && _total == 0; }
- (BOOL)isIndeterminate { return _total < 0 || (_total == 0 && _completed == 0); }
- (BOOL)isCancellable { return _cancellable; }
- (void)setCancellable:(BOOL)b { _cancellable = b; }
- (BOOL)isPausable { return _pausable; }
- (void)setPausable:(BOOL)b { _pausable = b; }
- (BOOL)isCancelled { return _cancelled; }
- (BOOL)isPaused { return _paused; }
- (void)cancel {
    if (_cancelled) return;
    [self willChangeValueForKey:@"cancelled"];
    _cancelled = YES;
    [self didChangeValueForKey:@"cancelled"];
    void (^h)(void) = _cancellationHandler;
    if (h) dispatch_async(dispatch_get_global_queue(0, 0), h);
    for (NSProgress *c in [_children copy]) [c cancel];
}
- (void)pause {
    if (_paused) return;
    _paused = YES;
    void (^h)(void) = _pausingHandler;
    if (h) dispatch_async(dispatch_get_global_queue(0, 0), h);
    for (NSProgress *c in [_children copy]) [c pause];
}
- (void)resume {
    if (!_paused) return;
    _paused = NO;
    void (^h)(void) = _resumingHandler;
    if (h) dispatch_async(dispatch_get_global_queue(0, 0), h);
    for (NSProgress *c in [_children copy]) [c resume];
}
- (void (^)(void))cancellationHandler { return _cancellationHandler; }
- (void)setCancellationHandler:(void (^)(void))h {
    _cancellationHandler = [h copy];
    if (_cancelled && h) dispatch_async(dispatch_get_global_queue(0, 0), h);
}
- (void (^)(void))pausingHandler { return _pausingHandler; }
- (void)setPausingHandler:(void (^)(void))h { _pausingHandler = [h copy]; }
- (void (^)(void))resumingHandler { return _resumingHandler; }
- (void)setResumingHandler:(void (^)(void))h { _resumingHandler = [h copy]; }
- (NSDictionary *)userInfo { return [_userInfo copy]; }
- (void)setUserInfoObject:(id)object forKey:(NSString *)key {
    if (object) _userInfo[key] = object;
    else [_userInfo removeObjectForKey:key];
}
- (NSString *)kind { return _kind; }
- (void)setKind:(NSString *)k { _kind = [k copy]; }
- (NSString *)localizedDescription {
    if (_localizedDescription) return _localizedDescription;
    return [NSString stringWithFormat:@"%d%% completed", (int)(self.fractionCompleted * 100)];
}
- (void)setLocalizedDescription:(NSString *)s { _localizedDescription = [s copy]; }
- (NSString *)localizedAdditionalDescription {
    if (_localizedAdditionalDescription) return _localizedAdditionalDescription;
    return _total > 0 ? [NSString stringWithFormat:@"%lld of %lld", _completed, _total] : @"";
}
- (void)setLocalizedAdditionalDescription:(NSString *)s { _localizedAdditionalDescription = [s copy]; }
- (void)becomeCurrentWithPendingUnitCount:(int64_t)unitCount {}
- (void)resignCurrent {}
- (NSString *)description {
    return [NSString stringWithFormat:@"<NSProgress %p> Fraction completed: %.4f / Completed: %lld of %lld", self,
                                      self.fractionCompleted, _completed, _total];
}
@end
