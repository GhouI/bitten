/* QuickLookUI's preview panel (see the header). */
#import <QuickLookUI/QuickLookUI.h>

static QLPreviewPanel *shared;

@implementation QLPreviewPanel
@synthesize dataSource = _dataSource;
+ (QLPreviewPanel *)sharedPreviewPanel {
    if (!shared) {
        shared = [[QLPreviewPanel alloc] initWithContentRect:NSMakeRect(200, 200, 640, 480)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
        shared.title = @"Quick Look";
    }
    return shared;
}
+ (BOOL)sharedPreviewPanelExists { return shared != nil; }

- (id<QLPreviewItem>)currentPreviewItem {
    id<QLPreviewPanelDataSource> ds = self.dataSource;
    NSInteger n = ds ? [ds numberOfPreviewItemsInPreviewPanel:self] : 0;
    if (_currentPreviewItemIndex < 0 || _currentPreviewItemIndex >= n) return nil;
    return [ds previewPanel:self previewItemAtIndex:_currentPreviewItemIndex];
}
@synthesize currentPreviewItemIndex = _currentPreviewItemIndex;
- (void)setCurrentPreviewItemIndex:(NSInteger)i {
    _currentPreviewItemIndex = i;
    [self refreshCurrentPreviewItem];
}

/* The window title names the item: there is nothing to render it with. */
- (void)refreshCurrentPreviewItem {
    id<QLPreviewItem> item = self.currentPreviewItem;
    NSString *title = [item respondsToSelector:@selector(previewItemTitle)] ? item.previewItemTitle : nil;
    if (!title) title = item.previewItemURL.lastPathComponent;
    self.title = title.length ? title : @"Quick Look";
}
- (void)reloadData { [self refreshCurrentPreviewItem]; }
- (void)updateController {}
- (BOOL)isInFullScreenMode { return NO; }
- (BOOL)enterFullScreenMode:(NSScreen *)screen withOptions:(NSDictionary *)options { return NO; }
- (void)exitFullScreenModeWithOptions:(NSDictionary *)options {}
@end
