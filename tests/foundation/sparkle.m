// Foundation selectors the target app's update framework calls: string
// enumeration and percent-encoding, URL resolution, file-system
// representations and resource values, directory enumerators, and the
// URL-based reading and writing of strings and data.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

static NSString *resolve(NSString *ref) {
    NSURL *base = [NSURL URLWithString:@"http://a/b/c/d;p?q"];
    return [NSURL URLWithString:ref relativeToURL:base].absoluteString;
}

int main(void) {
    @autoreleasepool {
        NSMutableArray *lines = [NSMutableArray array];
        [@"one\ntwo\r\nthree\n\nfive" enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) { [lines addObject:line]; }];
        CHECK([lines isEqualToArray:(@[ @"one", @"two", @"three", @"", @"five" ])]);
        [lines removeAllObjects];
        [@"a\nb\nc" enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            [lines addObject:line];
            *stop = [line isEqualToString:@"b"];
        }];
        CHECK(lines.count == 2);

        NSString *text = @"Hello, world! It's 2 o'clock.";
        NSMutableArray *words = [NSMutableArray array];
        __block NSRange firstEnclosing = {0, 0};
        [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByWords
                              usingBlock:^(NSString *w, NSRange r, NSRange e, BOOL *stop) {
                                  if (!words.count) firstEnclosing = e;
                                  [words addObject:w];
                              }];
        CHECK([words isEqualToArray:(@[ @"Hello", @"world", @"It's", @"2", @"o'clock" ])]);
        CHECK(firstEnclosing.location == 0 && firstEnclosing.length == 7);
        [words removeAllObjects];
        [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByWords | NSStringEnumerationReverse
                              usingBlock:^(NSString *w, NSRange r, NSRange e, BOOL *stop) { [words addObject:w]; }];
        CHECK([words.firstObject isEqualToString:@"o'clock"] && words.count == 5);
        NSMutableArray *sentences = [NSMutableArray array];
        [@"First one. Second?  Third" enumerateSubstringsInRange:NSMakeRange(0, 25) options:NSStringEnumerationBySentences
                                                     usingBlock:^(NSString *s, NSRange r, NSRange e, BOOL *stop) { [sentences addObject:s]; }];
        CHECK([sentences isEqualToArray:(@[ @"First one.", @"Second?", @"Third" ])]);
        __block NSUInteger chars = 0;
        __block BOOL nilText = YES;
        [@"ab\u00e9" enumerateSubstringsInRange:NSMakeRange(0, 3)
                                       options:NSStringEnumerationByComposedCharacterSequences | NSStringEnumerationSubstringNotRequired
                                    usingBlock:^(NSString *s, NSRange r, NSRange e, BOOL *stop) {
                                        chars++;
                                        nilText = nilText && !s;
                                    }];
        CHECK(chars == 3 && nilText);

        NSString *q = [@"a b&c=d/é?" stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        CHECK([q isEqualToString:@"a%20b&c=d/%C3%A9?"]);
        NSString *host = [@"a:b@c" stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLUserAllowedCharacterSet];
        CHECK([host isEqualToString:@"a%3Ab%40c"]);
        CHECK([[q stringByRemovingPercentEncoding] isEqualToString:@"a b&c=d/é?"]);
        CHECK([@"bad%zz" stringByRemovingPercentEncoding] == nil);

        CHECK([resolve(@"g") isEqualToString:@"http://a/b/c/g"]);
        CHECK([resolve(@"./g") isEqualToString:@"http://a/b/c/g"]);
        CHECK([resolve(@"g/") isEqualToString:@"http://a/b/c/g/"]);
        CHECK([resolve(@"/g") isEqualToString:@"http://a/g"]);
        CHECK([resolve(@"//g") isEqualToString:@"http://g"]);
        CHECK([resolve(@"?y") isEqualToString:@"http://a/b/c/d;p?y"]);
        CHECK([resolve(@"g?y#s") isEqualToString:@"http://a/b/c/g?y#s"]);
        CHECK([resolve(@"#s") isEqualToString:@"http://a/b/c/d;p?q#s"]);
        CHECK([resolve(@"..") isEqualToString:@"http://a/b/"]);
        CHECK([resolve(@"../../g") isEqualToString:@"http://a/g"]);
        CHECK([resolve(@"https://other/x") isEqualToString:@"https://other/x"]);

        NSURL *dir = [NSURL fileURLWithPath:@"/tmp/x"];
        CHECK([[dir URLByAppendingPathComponent:@"y" isDirectory:YES].absoluteString isEqualToString:@"file:///tmp/x/y/"]);
        CHECK([[dir URLByAppendingPathExtension:@"zip"].path isEqualToString:@"/tmp/x.zip"]);
        CHECK([[[NSURL URLWithString:@"https://h/a/b.tar?q=1"] URLByDeletingPathExtension].absoluteString isEqualToString:@"https://h/a/b?q=1"]);
        char buf[64];
        CHECK([dir getFileSystemRepresentation:buf maxLength:sizeof buf] && !strcmp(buf, "/tmp/x"));
        CHECK(![dir getFileSystemRepresentation:buf maxLength:3]);
        CHECK([[NSURL fileURLWithFileSystemRepresentation:"/tmp/z" isDirectory:YES relativeToURL:nil].absoluteString isEqualToString:@"file:///tmp/z/"]);

        char tmpl[] = "/tmp/bitten-sparkle-XXXXXX";
        NSString *root = [NSString stringWithUTF8String:mkdtemp(tmpl)];
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"sub/deep"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"skip/inner"] withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *file = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"sub/file.txt"]];
        NSError *error = nil;
        CHECK([@"hello" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error]);
        CHECK([[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:&error] isEqualToString:@"hello"]);
        NSData *bytes = [NSData dataWithContentsOfFile:file.path options:0 error:&error];
        CHECK(bytes.length == 5);
        CHECK([NSData dataWithContentsOfFile:@"/nonexistent/x" options:0 error:&error] == nil && error.code == NSFileReadNoSuchFileError);
        NSURL *copyURL = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@".hidden"]];
        CHECK([bytes writeToURL:copyURL atomically:YES] && [[NSData dataWithContentsOfURL:copyURL] isEqualToData:bytes]);
        CHECK([NSString stringWithContentsOfURL:[NSURL URLWithString:@"https://h/x"] encoding:NSUTF8StringEncoding error:&error] == nil);

        id value = nil;
        CHECK([file getResourceValue:&value forKey:NSURLFileSizeKey error:&error] && [value integerValue] == 5);
        CHECK([file.URLByDeletingLastPathComponent getResourceValue:&value forKey:NSURLIsDirectoryKey error:&error] && [value boolValue]);
        CHECK([file getResourceValue:&value forKey:NSURLNameKey error:&error] && [value isEqualToString:@"file.txt"]);
        CHECK(![[NSURL fileURLWithPath:@"/nonexistent/x"] getResourceValue:&value forKey:NSURLNameKey error:&error]);
        NSDictionary *values = [file resourceValuesForKeys:@[ NSURLIsRegularFileKey, NSURLContentModificationDateKey ] error:&error];
        CHECK([values[NSURLIsRegularFileKey] boolValue] && [values[NSURLContentModificationDateKey] isKindOfClass:[NSDate class]]);
        NSString *resolved = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"sub/../sub/file.txt"]].URLByResolvingSymlinksInPath.path;
        CHECK([resolved hasSuffix:@"/sub/file.txt"] && [resolved rangeOfString:@".."].location == NSNotFound);

        NSMutableArray *seen = [NSMutableArray array];
        NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
        for (NSString *p; (p = [e nextObject]);) {
            [seen addObject:p];
            if ([p isEqualToString:@"skip"]) [e skipDescendants];
            if ([p isEqualToString:@"sub/deep"]) CHECK(e.level == 2);
        }
        CHECK([seen isEqualToArray:(@[ @".hidden", @"skip", @"sub", @"sub/deep", @"sub/file.txt" ])]);
        [seen removeAllObjects];
        NSDirectoryEnumerator *u = [fm enumeratorAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:nil
                                               options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                          errorHandler:nil];
        for (NSURL *url in u) [seen addObject:url.lastPathComponent];
        CHECK([seen isEqualToArray:(@[ @"skip", @"sub" ])]);
        CHECK([fm removeItemAtPath:root error:NULL]);

        CHECK([[@[ @1 ] arrayByAddingObjectsFromArray:@[ @2, @3 ]] isEqualToArray:(@[ @1, @2, @3 ])]);
        CHECK([[NSDictionary dictionaryWithObjects:@[ @1, @2 ] forKeys:@[ @"a", @"b" ]] isEqualToDictionary:(@{@"a" : @1, @"b" : @2})]);
        CHECK(@(-2).shortValue == -2 && @(65535).unsignedShortValue == 65535);
        CHECK([[NSBundle preferredLocalizationsFromArray:@[ @"de", @"en", @"fr" ] forPreferences:@[ @"fr-CA" ]] isEqualToArray:@[ @"fr" ]]);
        CHECK([[NSBundle preferredLocalizationsFromArray:@[ @"de", @"en" ] forPreferences:@[ @"ja" ]] isEqualToArray:@[ @"en" ]]);
        CHECK(!NSProcessInfo.processInfo.isMacCatalystApp && !NSProcessInfo.processInfo.isiOSAppOnMac);
    }
    printf("sparkle ok\n");
    return 0;
}
