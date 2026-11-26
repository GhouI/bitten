/* bitten SDK: AppKit drag and drop (dragging sessions, items, sources and
 * destinations). */
#ifndef BITTEN_APPKIT_DRAGGING_H
#define BITTEN_APPKIT_DRAGGING_H
#import <AppKit/AppKitCore.h>

#pragma clang assume_nonnull begin

typedef NS_OPTIONS(NSUInteger, NSDragOperation) {
    NSDragOperationNone = 0,
    NSDragOperationCopy = 1,
    NSDragOperationLink = 2,
    NSDragOperationGeneric = 4,
    NSDragOperationPrivate = 8,
    NSDragOperationMove = 16,
    NSDragOperationDelete = 32,
    NSDragOperationEvery = NSUIntegerMax,
};
typedef NS_ENUM(NSInteger, NSDraggingFormation) {
    NSDraggingFormationDefault = 0, NSDraggingFormationNone, NSDraggingFormationPile, NSDraggingFormationList,
    NSDraggingFormationStack,
};
typedef NS_ENUM(NSInteger, NSDraggingContext) {
    NSDraggingContextOutsideApplication = 0,
    NSDraggingContextWithinApplication,
};
typedef NS_OPTIONS(NSUInteger, NSDraggingItemEnumerationOptions) {
    NSDraggingItemEnumerationConcurrent = 1UL << 0,
    NSDraggingItemEnumerationClearNonenumeratedImages = 1UL << 16,
};
typedef NS_ENUM(NSInteger, NSSpringLoadingHighlight) {
    NSSpringLoadingHighlightNone = 0, NSSpringLoadingHighlightStandard, NSSpringLoadingHighlightEmphasized,
};

typedef NSString *NSDraggingImageComponentKey NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSDraggingItem.ImageComponentKey);
APPKIT_EXTERN NSDraggingImageComponentKey const NSDraggingImageComponentIconKey;
APPKIT_EXTERN NSDraggingImageComponentKey const NSDraggingImageComponentLabelKey;

@class NSDraggingSession, NSDraggingItem;

@interface NSDraggingImageComponent : NSObject
+ (instancetype)draggingImageComponentWithKey:(NSDraggingImageComponentKey)key;
- (instancetype)initWithKey:(NSDraggingImageComponentKey)key;
@property (copy) NSDraggingImageComponentKey key;
@property (nullable, strong) id contents;
@property NSRect frame;
@end

@interface NSDraggingItem : NSObject
- (instancetype)initWithPasteboardWriter:(id<NSPasteboardWriting>)pasteboardWriter;
@property (readonly, strong) id item;
@property NSRect draggingFrame;
@property (nullable, copy) NSArray<NSDraggingImageComponent *> * (^imageComponentsProvider)(void);
- (void)setDraggingFrame:(NSRect)frame contents:(nullable id)contents;
@property (nullable, readonly, copy) NSArray<NSDraggingImageComponent *> *imageComponents;
@end

@protocol NSDraggingInfo <NSObject>
@property (nullable, readonly, strong) NSWindow *draggingDestinationWindow;
@property (readonly) NSDragOperation draggingSourceOperationMask;
@property (readonly) NSPoint draggingLocation;
@property (readonly) NSPoint draggedImageLocation;
@property (nullable, readonly, strong) NSImage *draggedImage;
@property (readonly, strong) NSPasteboard *draggingPasteboard;
@property (nullable, readonly, strong) id draggingSource;
@property (readonly) NSInteger draggingSequenceNumber;
- (void)slideDraggedImageTo:(NSPoint)screenPoint;
@property NSDraggingFormation draggingFormation;
@property BOOL animatesToDestination;
@property NSInteger numberOfValidItemsForDrop;
- (void)enumerateDraggingItemsWithOptions:(NSDraggingItemEnumerationOptions)enumOpts
                                  forView:(nullable NSView *)view
                                  classes:(NSArray<Class> *)classArray
                            searchOptions:(NSDictionary<NSPasteboardReadingOptionKey, id> *)searchOptions
                               usingBlock:(void (^)(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop))block;
@property (readonly) NSSpringLoadingHighlight springLoadingHighlight;
- (void)resetSpringLoading;
@end

@protocol NSDraggingDestination <NSObject>
@optional
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender;
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender;
- (void)draggingExited:(nullable id<NSDraggingInfo>)sender;
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender;
- (void)concludeDragOperation:(nullable id<NSDraggingInfo>)sender;
- (void)draggingEnded:(id<NSDraggingInfo>)sender;
- (BOOL)wantsPeriodicDraggingUpdates;
- (void)updateDraggingItemsForDrag:(nullable id<NSDraggingInfo>)sender;
@end

@protocol NSDraggingSource <NSObject>
@required
- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context;
@optional
- (void)draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint;
- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint;
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation;
- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session;
@end

/* A drag in progress, from beginDraggingSessionWithItems:event:source:
 * until the mouse goes up. */
@interface NSDraggingSession : NSObject
@property NSDraggingFormation draggingFormation;
@property BOOL animatesToStartingPositionsOnCancelOrFail;
@property NSInteger draggingLeaderIndex;
@property (readonly) NSPasteboard *draggingPasteboard;
@property (readonly) NSInteger draggingSequenceNumber;
@property (readonly) NSPoint draggingLocation;           /* screen coordinates */
- (void)enumerateDraggingItemsWithOptions:(NSDraggingItemEnumerationOptions)enumOpts
                                  forView:(nullable NSView *)view
                                  classes:(NSArray<Class> *)classArray
                            searchOptions:(NSDictionary<NSPasteboardReadingOptionKey, id> *)searchOptions
                               usingBlock:(void (^)(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop))block;
@end

@interface NSView (NSDraggingSession)
- (NSDraggingSession *)beginDraggingSessionWithItems:(NSArray<NSDraggingItem *> *)items event:(NSEvent *)event
                                              source:(id<NSDraggingSource>)source;
@end

/* Strings and URLs go on pasteboards (and in dragging items) as they are. */
@interface NSString (NSPasteboardSupport) <NSPasteboardWriting, NSPasteboardReading>
@end
@interface NSURL (NSPasteboardSupport) <NSPasteboardWriting, NSPasteboardReading>
+ (nullable NSURL *)URLFromPasteboard:(NSPasteboard *)pasteBoard;
- (void)writeToPasteboard:(NSPasteboard *)pasteBoard;
@end

@interface NSWindow (NSDragging)
- (void)registerForDraggedTypes:(NSArray<NSPasteboardType> *)newTypes;
- (void)unregisterDraggedTypes;
@end

#pragma clang assume_nonnull end
#endif
