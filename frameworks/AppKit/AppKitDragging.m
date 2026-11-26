/* Drag and drop inside the application. A view starts a session with
 * beginDraggingSessionWithItems:event:source:, which writes the items to the
 * drag pasteboard; from then until the mouse goes up the window hands its
 * mouse events to the session (bn_dragging_route, from -[NSWindow
 * sendEvent:]), which finds the view (or window) under the pointer that is
 * registered for one of the pasteboard's types and runs the destination
 * protocol with it: entered, updated, exited, then prepare, perform and
 * conclude on a drop, with the operation the source allows. */
#import <AppKit/AppKit.h>
#import <AppKit/AppKitDragging.h>
#include <objc/runtime.h>

NSDraggingImageComponentKey const NSDraggingImageComponentIconKey = @"icon";
NSDraggingImageComponentKey const NSDraggingImageComponentLabelKey = @"label";

static const char kWindowDragTypes;

@implementation NSDraggingImageComponent
@synthesize key = _key, contents = _contents, frame = _frame;
+ (instancetype)draggingImageComponentWithKey:(NSDraggingImageComponentKey)key { return [[self alloc] initWithKey:key]; }
- (instancetype)initWithKey:(NSDraggingImageComponentKey)key {
    if ((self = [super init])) _key = [key copy];
    return self;
}
@end

@implementation NSDraggingItem {
    id _item;
    NSArray<NSDraggingImageComponent *> *_components;
}
@synthesize draggingFrame = _draggingFrame, imageComponentsProvider = _imageComponentsProvider;
- (instancetype)initWithPasteboardWriter:(id<NSPasteboardWriting>)writer {
    if ((self = [super init])) _item = writer;
    return self;
}
- (instancetype)initWithBNObject:(id)o {
    if ((self = [super init])) _item = o;
    return self;
}
- (id)item { return _item; }
- (void)setDraggingFrame:(NSRect)frame contents:(id)contents {
    _draggingFrame = frame;
    NSDraggingImageComponent *c = [NSDraggingImageComponent draggingImageComponentWithKey:NSDraggingImageComponentIconKey];
    c.contents = contents;
    c.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
    _components = contents ? @[c] : nil;
    _imageComponentsProvider = nil;
}
- (NSArray<NSDraggingImageComponent *> *)imageComponents {
    if (_imageComponentsProvider) return _imageComponentsProvider();
    return _components;
}
@end

/* ---- the session and what destinations see ---- */

@class BNDraggingInfo;

@interface NSDraggingSession () {
@public
    NSPasteboard *_pasteboard;
    NSArray<NSDraggingItem *> *_items;
    __weak id<NSDraggingSource> _source;
    __weak NSWindow *_sourceWindow;
    NSInteger _sequence;
    NSPoint _location;
    id _destination;              /* the view or window under the pointer taking the drag */
    NSWindow *_destWindow;
    NSDragOperation _operation;
    BNDraggingInfo *_info;
}
@end

@interface BNDraggingInfo : NSObject <NSDraggingInfo> {
@public
    __weak NSDraggingSession *_session;
    NSPoint _windowLocation;
}
@end

static NSDraggingSession *current;
static NSInteger sequenceCounter;

static NSDragOperation source_mask(NSDraggingSession *s) {
    id<NSDraggingSource> src = s->_source;
    if (![src respondsToSelector:@selector(draggingSession:sourceOperationMaskForDraggingContext:)])
        return NSDragOperationEvery;
    return [src draggingSession:s sourceOperationMaskForDraggingContext:NSDraggingContextWithinApplication];
}

static void enumerate_items(NSDraggingSession *s, NSArray<Class> *classes,
                            void (^block)(NSDraggingItem *, NSInteger, BOOL *)) {
    NSArray<NSPasteboardItem *> *items = s->_pasteboard.pasteboardItems;
    NSInteger idx = 0;
    BOOL stop = NO;
    for (NSUInteger i = 0; i < items.count && !stop; i++) {
        NSPasteboard *one = [NSPasteboard pasteboardWithUniqueName];
        [one writeObjects:@[items[i]]];
        NSArray *objs = [one readObjectsForClasses:classes.count ? classes : @[[NSPasteboardItem class]] options:nil];
        [one releaseGlobally];
        if (!objs.count) continue;
        NSDraggingItem *d = [[NSDraggingItem alloc] initWithBNObject:objs[0]];
        if (i < s->_items.count) d.draggingFrame = s->_items[i].draggingFrame;
        block(d, idx++, &stop);
    }
}

@implementation NSDraggingSession
@synthesize draggingFormation = _draggingFormation, draggingLeaderIndex = _draggingLeaderIndex,
            animatesToStartingPositionsOnCancelOrFail = _animatesToStartingPositionsOnCancelOrFail;
- (NSPasteboard *)draggingPasteboard { return _pasteboard; }
- (NSInteger)draggingSequenceNumber { return _sequence; }
- (NSPoint)draggingLocation { return _location; }
- (void)enumerateDraggingItemsWithOptions:(NSDraggingItemEnumerationOptions)o forView:(NSView *)view
                                  classes:(NSArray<Class> *)classes searchOptions:(NSDictionary *)search
                               usingBlock:(void (^)(NSDraggingItem *, NSInteger, BOOL *))block {
    enumerate_items(self, classes, block);
}
@end

@implementation BNDraggingInfo
@synthesize draggingFormation = _draggingFormation, animatesToDestination = _animatesToDestination,
            numberOfValidItemsForDrop = _numberOfValidItemsForDrop;
- (NSWindow *)draggingDestinationWindow { return _session->_destWindow; }
- (NSDragOperation)draggingSourceOperationMask { return source_mask(_session); }
- (NSPoint)draggingLocation { return _windowLocation; }
- (NSPoint)draggedImageLocation { return _windowLocation; }
- (NSImage *)draggedImage { return nil; }
- (NSPasteboard *)draggingPasteboard { return _session->_pasteboard; }
- (id)draggingSource { return _session->_source; }
- (NSInteger)draggingSequenceNumber { return _session->_sequence; }
- (void)slideDraggedImageTo:(NSPoint)p {}
- (void)enumerateDraggingItemsWithOptions:(NSDraggingItemEnumerationOptions)o forView:(NSView *)view
                                  classes:(NSArray<Class> *)classes searchOptions:(NSDictionary *)search
                               usingBlock:(void (^)(NSDraggingItem *, NSInteger, BOOL *))block {
    enumerate_items(_session, classes, block);
}
- (NSSpringLoadingHighlight)springLoadingHighlight { return NSSpringLoadingHighlightNone; }
- (void)resetSpringLoading {}
@end

/* ---- starting ---- */

@implementation NSView (NSDraggingSession)
- (NSDraggingSession *)beginDraggingSessionWithItems:(NSArray<NSDraggingItem *> *)items event:(NSEvent *)event
                                              source:(id<NSDraggingSource>)source {
    NSDraggingSession *s = [NSDraggingSession new];
    s->_pasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
    [s->_pasteboard clearContents];
    NSMutableArray *writers = [NSMutableArray array];
    for (NSDraggingItem *i in items) if (i.item) [writers addObject:i.item];
    [s->_pasteboard writeObjects:writers];
    s->_items = [items copy];
    s->_source = source;
    s->_sourceWindow = self.window;
    s->_sequence = ++sequenceCounter;
    s->_info = [BNDraggingInfo new];
    s->_info->_session = s;
    s->_info.numberOfValidItemsForDrop = (NSInteger)items.count;
    NSRect wf = self.window.frame;
    NSPoint p = event ? event.locationInWindow : NSZeroPoint;
    s->_location = NSMakePoint(wf.origin.x + p.x, wf.origin.y + p.y);
    current = s;
    if ([source respondsToSelector:@selector(draggingSession:willBeginAtPoint:)])
        [source draggingSession:s willBeginAtPoint:s->_location];
    return s;
}
@end

@implementation NSWindow (NSDragging)
- (void)registerForDraggedTypes:(NSArray<NSPasteboardType> *)types {
    objc_setAssociatedObject(self, &kWindowDragTypes, [types copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)unregisterDraggedTypes { objc_setAssociatedObject(self, &kWindowDragTypes, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

/* ---- strings and URLs as pasteboard objects ---- */

@implementation NSString (NSPasteboardSupport)
- (NSArray<NSPasteboardType> *)writableTypesForPasteboard:(NSPasteboard *)pb { return @[NSPasteboardTypeString]; }
- (id)pasteboardPropertyListForType:(NSPasteboardType)type { return self; }
+ (NSArray<NSPasteboardType> *)readableTypesForPasteboard:(NSPasteboard *)pb { return @[NSPasteboardTypeString]; }
- (id)initWithPasteboardPropertyList:(id)plist ofType:(NSPasteboardType)type {
    return [plist isKindOfClass:[NSString class]] ? [self initWithString:plist] : nil;
}
@end

@implementation NSURL (NSPasteboardSupport)
- (NSArray<NSPasteboardType> *)writableTypesForPasteboard:(NSPasteboard *)pb {
    return self.isFileURL ? @[NSPasteboardTypeFileURL, NSPasteboardTypeString] : @[NSPasteboardTypeURL, NSPasteboardTypeString];
}
- (id)pasteboardPropertyListForType:(NSPasteboardType)type { return self.absoluteString; }
+ (NSArray<NSPasteboardType> *)readableTypesForPasteboard:(NSPasteboard *)pb {
    return @[NSPasteboardTypeFileURL, NSPasteboardTypeURL];
}
- (id)initWithPasteboardPropertyList:(id)plist ofType:(NSPasteboardType)type {
    return [plist isKindOfClass:[NSString class]] ? [self initWithString:plist] : nil;
}
+ (NSURL *)URLFromPasteboard:(NSPasteboard *)pb {
    return [pb readObjectsForClasses:@[[NSURL class]] options:nil].firstObject;
}
- (void)writeToPasteboard:(NSPasteboard *)pb { [pb writeObjects:@[self]]; }
@end

/* ---- moving and dropping ---- */

static BOOL accepts(NSArray<NSPasteboardType> *registered, NSPasteboard *pb) {
    if (!registered.count) return NO;
    for (NSPasteboardItem *i in pb.pasteboardItems)
        if ([i availableTypeFromArray:registered]) return YES;
    return NO;
}

/* The window under a screen point: the source's first, then any other. */
static NSWindow *window_at(NSDraggingSession *s, NSPoint screen) {
    NSWindow *src = s->_sourceWindow;
    if (src.isVisible && NSPointInRect(screen, src.frame)) return src;
    for (NSWindow *w in [NSApp.windows reverseObjectEnumerator])
        if (w.isVisible && NSPointInRect(screen, w.frame)) return w;
    return nil;
}

/* What takes the drag at a point: the innermost registered view, else the
 * window (whose delegate may answer for it). */
static id destination_at(NSDraggingSession *s, NSWindow *w, NSPoint inWindow) {
    if (!w) return nil;
    for (NSView *v = [w.contentView hitTest:inWindow]; v; v = v.superview)
        if (accepts(v.registeredDraggedTypes, s->_pasteboard)) return v;
    if (accepts(objc_getAssociatedObject(w, &kWindowDragTypes), s->_pasteboard)) {
        id d = w.delegate;
        return [d respondsToSelector:@selector(draggingEntered:)] || [d respondsToSelector:@selector(performDragOperation:)]
                   ? d
                   : w;
    }
    return nil;
}

static void move_to(NSDraggingSession *s, NSPoint screen) {
    s->_location = screen;
    NSWindow *w = window_at(s, screen);
    NSPoint inWindow = w ? NSMakePoint(screen.x - w.frame.origin.x, screen.y - w.frame.origin.y) : screen;
    s->_info->_windowLocation = inWindow;
    id dest = destination_at(s, w, inWindow);
    NSDragOperation mask = source_mask(s);
    if (dest != s->_destination) {
        if ([s->_destination respondsToSelector:@selector(draggingExited:)]) [s->_destination draggingExited:s->_info];
        s->_destination = dest;
        s->_destWindow = dest ? w : nil;
        s->_operation = NSDragOperationNone;
        if ([dest respondsToSelector:@selector(draggingEntered:)]) s->_operation = [dest draggingEntered:s->_info] & mask;
    } else if (dest) {
        if ([dest respondsToSelector:@selector(draggingUpdated:)]) s->_operation = [dest draggingUpdated:s->_info] & mask;
    }
    id<NSDraggingSource> src = s->_source;
    if ([src respondsToSelector:@selector(draggingSession:movedToPoint:)]) [src draggingSession:s movedToPoint:screen];
}

static void drop(NSDraggingSession *s) {
    id dest = s->_destination;
    NSDragOperation op = s->_operation;
    if (dest && op != NSDragOperationNone) {
        BOOL ok = ![dest respondsToSelector:@selector(prepareForDragOperation:)] || [dest prepareForDragOperation:s->_info];
        ok = ok && [dest respondsToSelector:@selector(performDragOperation:)] && [dest performDragOperation:s->_info];
        if (ok) {
            if ([dest respondsToSelector:@selector(concludeDragOperation:)]) [dest concludeDragOperation:s->_info];
        } else {
            op = NSDragOperationNone;
        }
    } else {
        if ([dest respondsToSelector:@selector(draggingExited:)]) [dest draggingExited:s->_info];
        op = NSDragOperationNone;
    }
    id<NSDraggingSource> src = s->_source;
    if ([src respondsToSelector:@selector(draggingSession:endedAtPoint:operation:)])
        [src draggingSession:s endedAtPoint:s->_location operation:op];
    if ([dest respondsToSelector:@selector(draggingEnded:)]) [dest draggingEnded:s->_info];
}

/* A window's mouse event during a drag: YES when the session took it. */
BOOL bn_dragging_route(NSWindow *w, NSEvent *e) {
    NSDraggingSession *s = current;
    if (!s) return NO;
    NSEventType t = e.type;
    if (t != NSEventTypeLeftMouseDragged && t != NSEventTypeLeftMouseUp && t != NSEventTypeMouseMoved) return NO;
    NSRect wf = w.frame;
    NSPoint screen = NSMakePoint(wf.origin.x + e.locationInWindow.x, wf.origin.y + e.locationInWindow.y);
    if (t != NSEventTypeLeftMouseUp || !NSEqualPoints(screen, s->_location)) move_to(s, screen);
    if (t == NSEventTypeLeftMouseUp) {
        current = nil;
        drop(s);
    }
    return YES;
}
