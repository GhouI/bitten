/* NSUndoManager: groups of recorded actions on an undo and a redo stack.
 * Actions registered while undoing land on the redo stack and vice versa.
 * Groups made by event close at the end of each run loop turn. */
#import "FoundationInternal.h"
#import <objc/message.h>

NSNotificationName const NSUndoManagerCheckpointNotification = @"NSUndoManagerCheckpointNotification";
NSNotificationName const NSUndoManagerWillUndoChangeNotification = @"NSUndoManagerWillUndoChangeNotification";
NSNotificationName const NSUndoManagerWillRedoChangeNotification = @"NSUndoManagerWillRedoChangeNotification";
NSNotificationName const NSUndoManagerDidUndoChangeNotification = @"NSUndoManagerDidUndoChangeNotification";
NSNotificationName const NSUndoManagerDidRedoChangeNotification = @"NSUndoManagerDidRedoChangeNotification";
NSNotificationName const NSUndoManagerDidOpenUndoGroupNotification = @"NSUndoManagerDidOpenUndoGroupNotification";
NSNotificationName const NSUndoManagerWillCloseUndoGroupNotification = @"NSUndoManagerWillCloseUndoGroupNotification";
NSNotificationName const NSUndoManagerDidCloseUndoGroupNotification = @"NSUndoManagerDidCloseUndoGroupNotification";

@interface _BNUndoAction : NSObject {
  @public
    __unsafe_unretained id _target;
    SEL _selector;
    id _object;
    void (^_handler)(id);
}
@end
@implementation _BNUndoAction
- (void)perform {
    if (_handler) _handler(_target);
    else ((void (*)(id, SEL, id))objc_msgSend)(_target, _selector, _object);
}
@end

@interface _BNUndoGroup : NSObject {
  @public
    NSMutableArray<_BNUndoAction *> *_actions;
    NSString *_name;
}
@end
@implementation _BNUndoGroup
- (instancetype)init {
    if ((self = [super init])) {
        _actions = [NSMutableArray array];
        _name = @"";
    }
    return self;
}
@end

@implementation NSUndoManager {
    NSMutableArray<_BNUndoGroup *> *_undo, *_redo;
    _BNUndoGroup *_open;
    NSInteger _level, _disabled;
    BOOL _undoing, _redoing, _groupsByEvent, _autoGroupScheduled;
    NSUInteger _levels;
    NSArray *_modes;
}
- (instancetype)init {
    if ((self = [super init])) {
        _undo = [NSMutableArray array];
        _redo = [NSMutableArray array];
        _groupsByEvent = YES;
        _modes = @[ NSDefaultRunLoopMode ];
    }
    return self;
}
- (void)_post:(NSNotificationName)n { [[NSNotificationCenter defaultCenter] postNotificationName:n object:self]; }

- (void)beginUndoGrouping {
    if (_level == 0) _open = [_BNUndoGroup new];
    _level++;
    [self _post:NSUndoManagerDidOpenUndoGroupNotification];
}
- (void)endUndoGrouping {
    if (_level <= 0) return;
    [self _post:NSUndoManagerWillCloseUndoGroupNotification];
    _level--;
    if (_level == 0 && _open) {
        if (_open->_actions.count) {
            NSMutableArray *stack = _undoing ? _redo : _undo;
            [stack addObject:_open];
            if (!_undoing && !_redoing) [_redo removeAllObjects];
            if (_levels && stack.count > _levels) [stack removeObjectAtIndex:0];
        }
        _open = nil;
    }
    [self _post:NSUndoManagerDidCloseUndoGroupNotification];
}
- (NSInteger)groupingLevel { return _level; }
- (void)disableUndoRegistration { _disabled++; }
- (void)enableUndoRegistration {
    if (_disabled > 0) _disabled--;
}
- (BOOL)isUndoRegistrationEnabled { return _disabled == 0; }
- (BOOL)groupsByEvent { return _groupsByEvent; }
- (void)setGroupsByEvent:(BOOL)g { _groupsByEvent = g; }
- (NSUInteger)levelsOfUndo { return _levels; }
- (void)setLevelsOfUndo:(NSUInteger)l { _levels = l; }
- (NSArray *)runLoopModes { return _modes; }
- (void)setRunLoopModes:(NSArray *)m { _modes = [m copy]; }

/* Registration outside a group opens one that closes after this turn. */
- (void)_autoGroup {
    if (_level > 0 || !_groupsByEvent || _undoing || _redoing) return;
    [self beginUndoGrouping];
    if (_autoGroupScheduled) return;
    _autoGroupScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_autoGroupScheduled = NO;
        while (self->_level > 0) [self endUndoGrouping];
    });
}
- (void)_add:(_BNUndoAction *)a {
    if (_disabled) return;
    if (_undoing || _redoing) {
        if (!_open) {
            _open = [_BNUndoGroup new];
            _level = 1;
        }
    } else {
        [self _autoGroup];
    }
    [_open->_actions addObject:a];
}
- (void)registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)object {
    _BNUndoAction *a = [_BNUndoAction new];
    a->_target = target;
    a->_selector = selector;
    a->_object = object;
    [self _add:a];
}
- (void)registerUndoWithTarget:(id)target handler:(void (^)(id))handler {
    _BNUndoAction *a = [_BNUndoAction new];
    a->_target = target;
    a->_handler = [handler copy];
    [self _add:a];
}
- (void)setActionName:(NSString *)name {
    if (_open) _open->_name = [name copy];
    else [_undo lastObject]->_name = [name copy];
}

/* Runs the last group's actions in reverse; what they register while
 * undoing becomes one redo group (and the other way round). */
- (void)_run:(NSMutableArray<_BNUndoGroup *> *)from undoing:(BOOL)undoing {
    while (_level > 0) [self endUndoGrouping];
    _BNUndoGroup *g = from.lastObject;
    if (!g) return;
    [from removeLastObject];
    [self _post:undoing ? NSUndoManagerWillUndoChangeNotification : NSUndoManagerWillRedoChangeNotification];
    if (undoing) _undoing = YES;
    else _redoing = YES;
    _open = [_BNUndoGroup new];
    _open->_name = g->_name;
    _level = 1;
    for (_BNUndoAction *a in g->_actions.reverseObjectEnumerator) [a perform];
    _BNUndoGroup *made = _open;
    _open = nil;
    _level = 0;
    if (made->_actions.count) [undoing ? _redo : _undo addObject:made];
    _undoing = _redoing = NO;
    [self _post:undoing ? NSUndoManagerDidUndoChangeNotification : NSUndoManagerDidRedoChangeNotification];
}
- (void)undo { [self _run:_undo undoing:YES]; }
- (void)redo { [self _run:_redo undoing:NO]; }
- (void)undoNestedGroup { [self undo]; }
- (BOOL)canUndo { return _undo.count > 0 || (_open && _open->_actions.count && !_undoing); }
- (BOOL)canRedo { return _redo.count > 0; }
- (BOOL)isUndoing { return _undoing; }
- (BOOL)isRedoing { return _redoing; }
- (void)removeAllActions {
    [_undo removeAllObjects];
    [_redo removeAllObjects];
    _open = nil;
    _level = 0;
}
- (void)removeAllActionsWithTarget:(id)target {
    for (NSMutableArray<_BNUndoGroup *> *stack in @[ _undo, _redo ]) {
        for (_BNUndoGroup *g in stack) {
            NSMutableArray *keep = [NSMutableArray array];
            for (_BNUndoAction *a in g->_actions) if (a->_target != target) [keep addObject:a];
            g->_actions = keep;
        }
    }
}
- (NSString *)undoActionName { return _undo.lastObject->_name ?: @""; }
- (NSString *)redoActionName { return _redo.lastObject->_name ?: @""; }
- (NSString *)undoMenuItemTitle {
    NSString *n = self.undoActionName;
    return n.length ? [@"Undo " stringByAppendingString:n] : @"Undo";
}
- (NSString *)redoMenuItemTitle {
    NSString *n = self.redoActionName;
    return n.length ? [@"Redo " stringByAppendingString:n] : @"Redo";
}
@end
