/* ScreenCaptureKit with nothing to capture: bitten's windows live in the
 * display server's browser page, and no screen can be read. Shareable
 * content has no displays, windows or applications; capturing fails with
 * SCStreamErrorUserDeclined, as when recording is not permitted. */
#ifndef BITTEN_SCREENCAPTUREKIT_H
#define BITTEN_SCREENCAPTUREKIT_H
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <sys/types.h>

typedef uint32_t CGDirectDisplayID;
typedef uint32_t OSType;

#pragma clang assume_nonnull begin

extern NSString *const SCStreamErrorDomain;
typedef NS_ENUM(NSInteger, SCStreamErrorCode) {
    SCStreamErrorUserDeclined = -3801,
    SCStreamErrorFailedToStart = -3802,
    SCStreamErrorNoCaptureSource = -3815,
};

@interface SCRunningApplication : NSObject
@property (readonly) NSString *bundleIdentifier, *applicationName;
@property (readonly) pid_t processID;
@end

@interface SCDisplay : NSObject
@property (readonly) CGDirectDisplayID displayID;
@property (readonly) NSInteger width, height;
@property (readonly) CGRect frame;
@end

@interface SCWindow : NSObject
@property (readonly) CGWindowID windowID;
@property (readonly) CGRect frame;
@property (nullable, readonly) NSString *title;
@property (readonly) NSInteger windowLayer;
@property (nullable, readonly) SCRunningApplication *owningApplication;
@property (readonly, getter=isOnScreen) BOOL onScreen;
@property (readonly, getter=isActive) BOOL active;
@end

@interface SCShareableContent : NSObject
+ (void)getShareableContentWithCompletionHandler:(void (^)(SCShareableContent *_Nullable content,
                                                           NSError *_Nullable error))completionHandler;
+ (void)getCurrentProcessShareableContentWithCompletionHandler:(void (^)(SCShareableContent *_Nullable content, NSError *_Nullable error))completionHandler;
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)excludeDesktopWindows
                               onScreenWindowsOnly:(BOOL)onScreenWindowsOnly
                                 completionHandler:(void (^)(SCShareableContent *_Nullable content,
                                                             NSError *_Nullable error))completionHandler;
@property (readonly) NSArray<SCWindow *> *windows;
@property (readonly) NSArray<SCDisplay *> *displays;
@property (readonly) NSArray<SCRunningApplication *> *applications;
@end

@interface SCContentFilter : NSObject
- (instancetype)initWithDesktopIndependentWindow:(SCWindow *)window;
- (instancetype)initWithDisplay:(SCDisplay *)display excludingWindows:(NSArray<SCWindow *> *)excluded;
- (instancetype)initWithDisplay:(SCDisplay *)display includingWindows:(NSArray<SCWindow *> *)included;
@property (readonly) CGRect contentRect;
@property (readonly) float pointPixelScale;
@end

@interface SCStreamConfiguration : NSObject
@property size_t width, height;
@property BOOL showsCursor, capturesAudio, scalesToFit, ignoreShadowsSingleWindow;
@property CGRect sourceRect, destinationRect;
@property OSType pixelFormat;
@property (nullable) CGColorRef backgroundColor;
/* SCCaptureResolutionType: automatic (0), best (1), nominal (2) */
@property NSInteger captureResolution;
@end

@interface SCScreenshotManager : NSObject
+ (void)captureImageWithFilter:(SCContentFilter *)filter configuration:(SCStreamConfiguration *)config
             completionHandler:(nullable void (^)(CGImageRef _Nullable image, NSError *_Nullable error))completionHandler;
@end

#pragma clang assume_nonnull end
#endif
