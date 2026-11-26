/* PhotosUI's picker view controller (see the header). */
#import <PhotosUI/PhotosUI.h>
#include <dispatch/dispatch.h>

@implementation PHPickerViewController {
    BOOL _reported;
}
- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 360)];
}
- (void)viewDidAppear {
    [super viewDidAppear];
    if (_reported) return;
    _reported = YES;
    void (^appear)(void) = self._bn_onAppear;
    if (appear) dispatch_async(dispatch_get_main_queue(), appear);
}
@end
