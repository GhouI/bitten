// Foundation, third slice: property lists (XML and binary), bundles and
// user defaults.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

static void write_file(NSString *path, NSString *text) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:@{} error:NULL];
    CHECK([[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // XML round trip.
        NSDictionary *plist = @{
            @"name" : @"a <b> & c",
            @"count" : @42,
            @"ratio" : @0.5,
            @"on" : @YES,
            @"off" : @NO,
            @"list" : @[ @"x", @1, @[] ],
            @"blob" : [NSData dataWithBytes:"\x00\x01\x02hello" length:8],
            @"when" : [NSDate dateWithTimeIntervalSince1970:1700000000],
            @"nested" : @{@"k" : @"v"},
        };
        NSError *err = nil;
        NSData *xml = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0
                                                                options:0 error:&err];
        CHECK(xml != nil && err == nil);
        NSPropertyListFormat fmt = 0;
        NSDictionary *back = [NSPropertyListSerialization propertyListWithData:xml options:0 format:&fmt error:&err];
        CHECK(fmt == NSPropertyListXMLFormat_v1_0);
        CHECK([back[@"name"] isEqualToString:@"a <b> & c"]);
        CHECK([back[@"count"] integerValue] == 42 && [back[@"ratio"] doubleValue] == 0.5);
        CHECK([back[@"on"] boolValue] && ![back[@"off"] boolValue]);
        CHECK([back[@"list"] count] == 3 && [back[@"list"][2] count] == 0);
        CHECK([back[@"blob"] isEqualToData:plist[@"blob"]]);
        CHECK([back[@"when"] timeIntervalSince1970] == 1700000000);
        CHECK([back[@"nested"][@"k"] isEqualToString:@"v"]);
        CHECK(![NSPropertyListSerialization propertyList:@{@"bad" : [NSObject new]} isValidForFormat:NSPropertyListXMLFormat_v1_0]);
        CHECK([NSPropertyListSerialization propertyListWithData:[NSData dataWithBytes:"<plist><dict><key>" length:18]
                                                        options:0 format:NULL error:&err] == nil && err.code == 3840);

        // Binary: {"a": 1, "b": [true, "hi"]} laid out by hand.
        static const uint8_t bp[] = {
            'b', 'p', 'l', 'i', 's', 't', '0', '0',
            0xD2, 1, 2, 3, 4,     /* 8: dict, keys 1 2, values 3 4 */
            0x51, 'a',            /* 13 */
            0x51, 'b',            /* 15 */
            0x10, 1,              /* 17 */
            0xA2, 5, 6,           /* 19: array [5, 6] */
            0x09,                 /* 22: true */
            0x52, 'h', 'i',       /* 23 */
            8, 13, 15, 17, 19, 22, 23, /* 26: offsets */
            0, 0, 0, 0, 0, 0, 1, 1,
            0, 0, 0, 0, 0, 0, 0, 7,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 26,
        };
        NSDictionary *bin = [NSPropertyListSerialization propertyListWithData:[NSData dataWithBytes:bp length:sizeof bp]
                                                                      options:0 format:&fmt error:NULL];
        CHECK(fmt == NSPropertyListBinaryFormat_v1_0);
        CHECK([bin[@"a"] integerValue] == 1);
        CHECK([bin[@"b"][0] boolValue] && [bin[@"b"][1] isEqualToString:@"hi"]);

        // A bundle laid out like an app.
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                     [NSString stringWithFormat:@"bundle-test-%d", getpid()]];
        NSString *app = [root stringByAppendingPathComponent:@"Demo.app"];
        write_file([app stringByAppendingPathComponent:@"Contents/Info.plist"],
                   @"<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>"
                   @"<key>CFBundleIdentifier</key><string>org.example.demo</string>"
                   @"<key>CFBundleExecutable</key><string>Demo</string>"
                   @"<key>CFBundleShortVersionString</key><string>1.2</string></dict></plist>");
        write_file([app stringByAppendingPathComponent:@"Contents/MacOS/Demo"], @"");
        write_file([app stringByAppendingPathComponent:@"Contents/Resources/thing.json"], @"{}");
        write_file([app stringByAppendingPathComponent:@"Contents/Resources/en.lproj/Localizable.strings"],
                   @"/* greeting */\n\"hello\" = \"Hello, \\\"world\\\"\";\n// done\n");
        NSBundle *b = [NSBundle bundleWithPath:app];
        CHECK(b && [b.bundleIdentifier isEqualToString:@"org.example.demo"]);
        CHECK([[b objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqualToString:@"1.2"]);
        CHECK([b.executablePath hasSuffix:@"Contents/MacOS/Demo"]);
        CHECK([[b pathForResource:@"thing" ofType:@"json"] hasSuffix:@"Contents/Resources/thing.json"]);
        CHECK([b URLForResource:@"missing" withExtension:@"txt"] == nil);
        CHECK([[b localizedStringForKey:@"hello" value:nil table:nil] isEqualToString:@"Hello, \"world\""]);
        CHECK([[b localizedStringForKey:@"other" value:@"fallback" table:nil] isEqualToString:@"fallback"]);
        CHECK([NSBundle bundleWithPath:app] == b);
        CHECK([NSBundle bundleWithIdentifier:@"org.example.demo"] == b);
        CHECK(NSBundle.mainBundle.bundlePath.length > 0);

        // User defaults, kept under a scratch HOME.
        setenv("HOME", root.fileSystemRepresentation, 1);
        NSUserDefaults *u = [[NSUserDefaults alloc] initWithSuiteName:@"org.example.prefs"];
        [u registerDefaults:@{@"size" : @12, @"theme" : @"dark"}];
        CHECK([u integerForKey:@"size"] == 12 && [[u stringForKey:@"theme"] isEqualToString:@"dark"]);
        [u setInteger:14 forKey:@"size"];
        [u setBool:YES forKey:@"flag"];
        [u setObject:@[ @"a", @"b" ] forKey:@"recent"];
        CHECK([u integerForKey:@"size"] == 14 && [u boolForKey:@"flag"]);
        CHECK([[u stringArrayForKey:@"recent"] count] == 2);
        [u removeObjectForKey:@"size"];
        CHECK([u integerForKey:@"size"] == 12);
        CHECK([u objectForKey:@"nothing"] == nil && [u doubleForKey:@"nothing"] == 0);
        NSUserDefaults *again = [[NSUserDefaults alloc] initWithSuiteName:@"org.example.prefs"];
        CHECK([again boolForKey:@"flag"] && [[again arrayForKey:@"recent"][1] isEqualToString:@"b"]);
        CHECK([[NSFileManager defaultManager]
            fileExistsAtPath:[root stringByAppendingPathComponent:@"Library/Preferences/org.example.prefs.plist"]]);
        CHECK(NSUserDefaults.standardUserDefaults != nil);

        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        printf("ok\n");
    }
    return 0;
}
