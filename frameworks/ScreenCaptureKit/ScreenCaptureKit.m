/* ScreenCaptureKit with nothing to capture (see the header). */
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <dispatch/dispatch.h>

NSString *const SCStreamErrorDomain = @"com.apple.ScreenCaptureKit.SCStreamErrorDomain";

static NSError *declined(void) {
    return [NSError errorWithDomain:SCStreamErrorDomain code:SCStreamErrorUserDeclined
                           userInfo:@{NSLocalizedDescriptionKey: @"The user declined TCCs for application, window, display capture"}];
}

@implementation SCRunningApplication
- (NSString *)bundleIdentifier { return @""; }
- (NSString *)applicationName { return @""; }
- (pid_t)processID { return 0; }
@end
@implementation SCDisplay
- (CGDirectDisplayID)displayID { return 0; }
- (NSInteger)width { return 0; }
- (NSInteger)height { return 0; }
- (CGRect)frame { return CGRectZero; }
@end
@implementation SCWindow
- (CGWindowID)windowID { return 0; }
- (CGRect)frame { return CGRectZero; }
- (NSString *)title { return nil; }
- (NSInteger)windowLayer { return 0; }
- (SCRunningApplication *)owningApplication { return nil; }
- (BOOL)isOnScreen { return NO; }
- (BOOL)isActive { return NO; }
@end

@implementation SCShareableContent
+ (void)getShareableContentWithCompletionHandler:(void (^)(SCShareableContent *, NSError *))handler {
    [self getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO completionHandler:handler];
}
/* Nothing is shareable, which is not an error: the lists are empty. */
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)exclude onScreenWindowsOnly:(BOOL)onScreen
                                 completionHandler:(void (^)(SCShareableContent *, NSError *))handler {
    if (!handler) return;
    SCShareableContent *c = [SCShareableContent new];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ handler(c, nil); });
}
- (NSArray<SCWindow *> *)windows { return @[]; }
- (NSArray<SCDisplay *> *)displays { return @[]; }
- (NSArray<SCRunningApplication *> *)applications { return @[]; }
@end

@implementation SCContentFilter
- (instancetype)initWithDesktopIndependentWindow:(SCWindow *)window { return [super init]; }
- (instancetype)initWithDisplay:(SCDisplay *)display excludingWindows:(NSArray<SCWindow *> *)excluded { return [super init]; }
- (instancetype)initWithDisplay:(SCDisplay *)display includingWindows:(NSArray<SCWindow *> *)included { return [super init]; }
- (CGRect)contentRect { return CGRectZero; }
- (float)pointPixelScale { return 1; }
@end

@implementation SCStreamConfiguration
@synthesize width = _width, height = _height, showsCursor = _showsCursor, capturesAudio = _capturesAudio,
            scalesToFit = _scalesToFit, ignoreShadowsSingleWindow = _ignoreShadowsSingleWindow,
            sourceRect = _sourceRect, destinationRect = _destinationRect, pixelFormat = _pixelFormat;
- (instancetype)init {
    if ((self = [super init])) {
        _width = 1920;
        _height = 1080;
        _showsCursor = YES;
        _pixelFormat = 0x42475241;           /* 'BGRA' */
    }
    return self;
}
- (CGColorRef)backgroundColor { return NULL; }
- (void)setBackgroundColor:(CGColorRef)c {}
@end

@implementation SCScreenshotManager
+ (void)captureImageWithFilter:(SCContentFilter *)filter configuration:(SCStreamConfiguration *)config
             completionHandler:(void (^)(CGImageRef, NSError *))handler {
    if (!handler) return;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ handler(NULL, declined()); });
}
@end
