// CoreFoundation over Foundation (bundle info dictionaries, preferences,
// character sets) and QuickLookUI's preview panel.
#import <QuickLookUI/QuickLookUI.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

CFDictionaryRef CFBundleCopyInfoDictionaryInDirectory(CFURLRef);
CFTypeRef CFPreferencesCopyAppValue(CFStringRef, CFStringRef);
void CFPreferencesSetAppValue(CFStringRef, CFTypeRef, CFStringRef);
extern const CFStringRef kCFPreferencesCurrentApplication;
typedef struct { CFIndex location, length; } Range;
CFTypeRef CFCharacterSetCreateWithCharactersInRange(CFAllocatorRef, Range);

@interface Item : NSObject <QLPreviewItem>
@end
@implementation Item
- (NSURL *)previewItemURL { return [NSURL fileURLWithPath:@"/tmp/notes.txt"]; }
@end
@interface Source : NSObject <QLPreviewPanelDataSource>
@end
@implementation Source
- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)p { return 1; }
- (id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)p previewItemAtIndex:(NSInteger)i { return [Item new]; }
@end

int main(void) {
    @autoreleasepool {
        NSString *dir = [NSString stringWithFormat:@"/tmp/bitten-cfb-%d.app", getpid()];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"Contents"]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        NSDictionary *info = @{@"CFBundleIdentifier": @"com.example.cfb", @"CFBundleVersion": @"42"};
        NSData *plist = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0
                                                                  options:0 error:NULL];
        CHECK([plist writeToFile:[dir stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES]);
        NSDictionary *got = (__bridge_transfer id)(CFBundleCopyInfoDictionaryInDirectory((__bridge CFURLRef)[NSURL fileURLWithPath:dir]));
        CHECK([got[@"CFBundleIdentifier"] isEqualToString:@"com.example.cfb"] && [got[@"CFBundleVersion"] isEqualToString:@"42"]);
        CHECK(CFBundleCopyInfoDictionaryInDirectory((__bridge CFURLRef)[NSURL fileURLWithPath:@"/nonexistent"]) == NULL);

        CFPreferencesSetAppValue((__bridge CFStringRef)@"BittenTestKey", (__bridge CFTypeRef)@"value", kCFPreferencesCurrentApplication);
        NSString *v = (__bridge_transfer id)(CFPreferencesCopyAppValue((__bridge CFStringRef)@"BittenTestKey", kCFPreferencesCurrentApplication));
        CHECK([v isEqualToString:@"value"]);
        CHECK(CFPreferencesCopyAppValue((__bridge CFStringRef)@"BittenNoSuchKey", kCFPreferencesCurrentApplication) == NULL);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BittenTestKey"];

        NSCharacterSet *digits = (__bridge_transfer id)(CFCharacterSetCreateWithCharactersInRange(NULL, (Range){'0', 10}));
        CHECK([digits characterIsMember:'5'] && ![digits characterIsMember:'a']);

        CHECK(![QLPreviewPanel sharedPreviewPanelExists]);
        QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
        CHECK(panel && [QLPreviewPanel sharedPreviewPanelExists] && [QLPreviewPanel sharedPreviewPanel] == panel);
        Source *src = [Source new];
        panel.dataSource = src;
        panel.currentPreviewItemIndex = 0;
        CHECK([panel.title isEqualToString:@"notes.txt"] && panel.currentPreviewItem != nil);
    }
    printf("cfbridge ok\n");
    return 0;
}
