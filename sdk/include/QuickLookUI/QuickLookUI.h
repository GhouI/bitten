/* QuickLookUI's preview panel: a real (empty) panel. bitten has no
 * QuickLook generators, so the panel shows the current item's title only;
 * data sources and delegates are asked as on macOS. */
#ifndef BITTEN_QUICKLOOKUI_H
#define BITTEN_QUICKLOOKUI_H
#import <AppKit/AppKit.h>

#pragma clang assume_nonnull begin

@protocol QLPreviewItem <NSObject>
@property (nullable, readonly) NSURL *previewItemURL;
@optional
@property (nullable, readonly) NSString *previewItemTitle;
@end

@class QLPreviewPanel;
@protocol QLPreviewPanelDataSource <NSObject>
- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel;
- (nullable id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)index;
@end
@protocol QLPreviewPanelDelegate <NSWindowDelegate>
@optional
- (BOOL)previewPanel:(QLPreviewPanel *)panel handleEvent:(NSEvent *)event;
- (NSRect)previewPanel:(QLPreviewPanel *)panel sourceFrameOnScreenForPreviewItem:(id<QLPreviewItem>)item;
@end

@interface QLPreviewPanel : NSPanel
+ (nullable QLPreviewPanel *)sharedPreviewPanel;
+ (BOOL)sharedPreviewPanelExists;
@property (nullable, weak) id<QLPreviewPanelDataSource> dataSource;
@property NSInteger currentPreviewItemIndex;
@property (nullable, readonly) id<QLPreviewItem> currentPreviewItem;
@property (readonly, getter=isInFullScreenMode) BOOL inFullScreenMode;
- (void)reloadData;
- (void)refreshCurrentPreviewItem;
- (void)updateController;
- (BOOL)enterFullScreenMode:(nullable NSScreen *)screen withOptions:(nullable NSDictionary *)options;
- (void)exitFullScreenModeWithOptions:(nullable NSDictionary *)options;
@end

#pragma clang assume_nonnull end
#endif
