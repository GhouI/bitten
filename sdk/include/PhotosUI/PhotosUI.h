/* PhotosUI's picker. There is no photo library here: a picker that appears
 * reports an empty selection to its delegate, as when the user cancels.
 * The Swift API (configuration, results, the delegate) is in the
 * framework's Swift part (frameworks/PhotosUI/swift). */
#ifndef BITTEN_PHOTOSUI_H
#define BITTEN_PHOTOSUI_H
#import <AppKit/AppKit.h>

#pragma clang assume_nonnull begin
@interface PHPickerViewController : NSViewController
/* For the Swift part: the delegate (a Swift object) and what to run when
 * the picker appears. */
@property (nullable, weak) id _bn_delegate;
@property (nullable, copy) void (^_bn_onAppear)(void);
@end
#pragma clang assume_nonnull end
#endif
