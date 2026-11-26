// Drag and drop: a source view starts a session from mouseDragged:, the
// window routes the drag to registered destination views and windows, and
// the destination protocol runs with the operations the source allows.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static char trace[512];
static void note(const char *s) {
    strcat(trace, s);
    strcat(trace, " ");
}

@interface Source : NSView <NSDraggingSource>
@property NSDragOperation mask, ended;
@property NSDraggingSession *session;
@end
@implementation Source
- (void)mouseDown:(NSEvent *)e { note("down"); }
- (void)mouseDragged:(NSEvent *)e {
    if (self.session) return;
    NSDraggingItem *a = [[NSDraggingItem alloc] initWithPasteboardWriter:@"hello"];
    [a setDraggingFrame:self.bounds contents:nil];
    NSDraggingItem *b = [[NSDraggingItem alloc] initWithPasteboardWriter:[NSURL fileURLWithPath:@"/tmp/x.txt"]];
    self.session = [self beginDraggingSessionWithItems:@[a, b] event:e source:self];
}
- (void)mouseUp:(NSEvent *)e { note("source-up"); }
- (NSDragOperation)draggingSession:(NSDraggingSession *)s sourceOperationMaskForDraggingContext:(NSDraggingContext)c {
    CHECK(c == NSDraggingContextWithinApplication);
    return self.mask;
}
- (void)draggingSession:(NSDraggingSession *)s willBeginAtPoint:(NSPoint)p { note("begin"); }
- (void)draggingSession:(NSDraggingSession *)s endedAtPoint:(NSPoint)p operation:(NSDragOperation)op {
    note("end");
    self.ended = op;
    self.session = nil;
}
@end

@interface Dest : NSView
@property NSDragOperation wants;
@property NSString *text;
@property NSURL *url;
@property NSPoint at;
@end
@implementation Dest
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
    note("entered");
    CHECK(info.draggingSequenceNumber > 0 && info.draggingSource != nil);
    return self.wants;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info {
    note("updated");
    return self.wants;
}
- (void)draggingExited:(id<NSDraggingInfo>)info { note("exited"); }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info {
    note("prepare");
    return YES;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    note("perform");
    self.at = info.draggingLocation;
    self.text = [info.draggingPasteboard readObjectsForClasses:@[[NSString class]] options:nil].firstObject;
    __block int n = 0;
    [info enumerateDraggingItemsWithOptions:0 forView:self classes:@[[NSURL class]] searchOptions:@{}
                                 usingBlock:^(NSDraggingItem *item, NSInteger idx, BOOL *stop) {
                                     n++;
                                     self.url = item.item;
                                 }];
    CHECK(n == 1);
    return YES;
}
- (void)concludeDragOperation:(id<NSDraggingInfo>)info { note("conclude"); }
- (void)draggingEnded:(id<NSDraggingInfo>)info { note("ended"); }
@end

@interface WindowDrop : NSObject <NSWindowDelegate>
@property int dropped;
@end
@implementation WindowDrop
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return NSDragOperationCopy; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    self.dropped++;
    return YES;
}
@end

static NSEvent *mouse(NSEventType t, NSWindow *w, CGFloat x, CGFloat y) {
    return [NSEvent mouseEventWithType:t location:NSMakePoint(x, y) modifierFlags:0 timestamp:0
                          windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

int main(void) {
    [NSApplication sharedApplication];
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:NO];
    Source *src = [[Source alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    src.mask = NSDragOperationCopy | NSDragOperationMove;
    Dest *dst = [[Dest alloc] initWithFrame:NSMakeRect(200, 0, 100, 100)];
    dst.wants = NSDragOperationCopy;
    [dst registerForDraggedTypes:@[NSPasteboardTypeString]];
    CHECK([dst.registeredDraggedTypes isEqual:@[NSPasteboardTypeString]]);
    NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(10, 10, 20, 20)];   /* inside dst, not registered */
    [dst addSubview:child];
    [w.contentView addSubview:src];
    [w.contentView addSubview:dst];
    [w makeKeyAndOrderFront:nil];

    /* A drop: entered, updated, out and back in, then the drop. */
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, 50, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 60, 50)];
    CHECK(src.session && [src.session.draggingPasteboard.name isEqual:NSPasteboardNameDrag]);
    CHECK(src.session.draggingPasteboard.pasteboardItems.count == 2);
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 225, 25)];   /* over the child: dst takes it */
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 260, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 150, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 250, 60)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, 250, 60)];
    CHECK(!strcmp(trace, "down begin entered updated exited entered prepare perform conclude end ended "));
    CHECK(src.ended == NSDragOperationCopy && !src.session);
    CHECK([dst.text isEqual:@"hello"] && [dst.url.path isEqual:@"/tmp/x.txt"]);
    CHECK(dst.at.x == 250 && dst.at.y == 60);

    /* The destination wants an operation the source does not allow: no drop. */
    trace[0] = 0;
    dst.wants = NSDragOperationLink;
    dst.text = nil;
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, 50, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 60, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 250, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, 250, 50)];
    CHECK(!strcmp(trace, "down begin entered exited end ended "));
    CHECK(src.ended == NSDragOperationNone && !dst.text);

    /* Released over nothing that takes it. */
    trace[0] = 0;
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, 50, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 60, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, 380, 250)];
    CHECK(!strcmp(trace, "down begin end "));

    /* Not registered for the type: not a destination. */
    trace[0] = 0;
    [dst registerForDraggedTypes:@[NSPasteboardTypePNG]];
    dst.wants = NSDragOperationCopy;
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, 50, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 60, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, 250, 50)];
    CHECK(!strcmp(trace, "down begin end "));

    /* A window registered for a type, its delegate taking the drop. */
    trace[0] = 0;
    NSWindow *w2 = [[NSWindow alloc] initWithContentRect:NSMakeRect(600, 0, 200, 200) styleMask:NSWindowStyleMaskTitled
                                                 backing:NSBackingStoreBuffered defer:NO];
    WindowDrop *wd = [WindowDrop new];
    w2.delegate = wd;
    [w2 registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    [w2 orderFront:nil];
    NSPoint over = NSMakePoint(w2.frame.origin.x + 50 - w.frame.origin.x, w2.frame.origin.y + 50 - w.frame.origin.y);
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, 50, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, 60, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, over.x, over.y)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, over.x, over.y)];
    CHECK(wd.dropped == 1 && src.ended == NSDragOperationCopy);

    /* Afterwards the mouse goes back to the views. */
    trace[0] = 0;
    [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, 50, 50)];
    [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, 50, 50)];
    CHECK(!strcmp(trace, "down source-up "));

    printf("dragging ok\n");
    return 0;
}
