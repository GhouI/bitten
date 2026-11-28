// Foundation, second slice: data, dates, errors, sets, values, character
// sets, enumerators, process info, files, URLs, JSON, notifications, locks
// and threads.
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

@interface Listener : NSObject
@property (nonatomic) int heard;
@property (nonatomic, copy) NSString *last;
@end
@implementation Listener
- (void)got:(NSNotification *)n { _heard++; _last = n.userInfo[@"word"]; }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        // NSData
        NSData *d = [NSData dataWithBytes:"hello world" length:11];
        CHECK(d.length == 11 && memcmp(d.bytes, "hello world", 11) == 0);
        CHECK([[d subdataWithRange:NSMakeRange(6, 5)] isEqualToData:[NSData dataWithBytes:"world" length:5]]);
        NSString *b64 = [d base64EncodedStringWithOptions:0];
        CHECK([b64 isEqualToString:@"aGVsbG8gd29ybGQ="]);
        CHECK([[[NSData alloc] initWithBase64EncodedString:b64 options:0] isEqualToData:d]);
        CHECK([[NSData alloc] initWithBase64EncodedString:@"@@@" options:0] == nil);
        NSMutableData *md = [NSMutableData data];
        [md appendBytes:"abc" length:3];
        [md appendData:d];
        md.length = 5;
        [md replaceBytesInRange:NSMakeRange(4, 3) withBytes:"XYZ"];
        CHECK(md.length == 7 && memcmp(md.bytes, "abchXYZ", 7) == 0);
        NSData *frozen = [md copy];
        [md setLength:0];
        CHECK(frozen.length == 7 && md.length == 0);
        CHECK([[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] isEqualToString:@"hello world"]);

        // NSDate
        NSDate *epoch = [NSDate dateWithTimeIntervalSince1970:0];
        CHECK(epoch.timeIntervalSinceReferenceDate == -978307200.0);
        CHECK([[epoch description] isEqualToString:@"1970-01-01 00:00:00 +0000"]);
        NSDate *now = [NSDate date], *later = [now dateByAddingTimeInterval:60];
        CHECK([later timeIntervalSinceDate:now] == 60 && [now compare:later] == NSOrderedAscending);
        CHECK([now earlierDate:later] == now && [now laterDate:later] == later && now.timeIntervalSince1970 > 1.7e9);

        // NSError
        NSError *e = [NSError errorWithDomain:@"bitten.test" code:42 userInfo:@{NSLocalizedDescriptionKey: @"it broke"}];
        CHECK([e.domain isEqualToString:@"bitten.test"] && e.code == 42 && [e.localizedDescription isEqualToString:@"it broke"]);
        CHECK([[NSError errorWithDomain:NSPOSIXErrorDomain code:2 userInfo:nil].localizedDescription containsString:@"No such file"]);

        // NSSet
        NSSet *s = [NSSet setWithObjects:@"a", @"b", @"a", @3, nil];
        CHECK(s.count == 3 && [s containsObject:@"a"] && [s containsObject:@3] && ![s containsObject:@"z"]);
        NSMutableSet *ms = [s mutableCopy];
        [ms addObject:@"c"];
        [ms removeObject:@"a"];
        [ms unionSet:[NSSet setWithArray:@[@"x", @"y"]]];
        CHECK(ms.count == 5 && s.count == 3);
        [ms intersectSet:[NSSet setWithArray:@[@"x", @"b", @"nope"]]];
        CHECK([ms isEqualToSet:[NSSet setWithArray:@[@"b", @"x"]]] && [ms isSubsetOfSet:[NSSet setWithArray:@[@"b", @"x", @"q"]]]);
        NSUInteger seen = 0;
        for (id o in s) seen += o != nil;
        CHECK(seen == 3);

        // NSValue, enumerators
        NSValue *rv = [NSValue valueWithRange:NSMakeRange(3, 4)];
        CHECK(rv.rangeValue.location == 3 && rv.rangeValue.length == 4 && [rv isEqual:[NSValue valueWithRange:NSMakeRange(3, 4)]]);
        int local = 0;
        CHECK([NSValue valueWithPointer:&local].pointerValue == &local);
        NSEnumerator *en = [@[@1, @2, @3] reverseObjectEnumerator];
        CHECK([[en nextObject] intValue] == 3 && en.allObjects.count == 2 && [en nextObject] == nil);
        NSMutableString *joined = [NSMutableString string];
        for (NSString *k in [[@{@"k1": @1} keyEnumerator] allObjects]) [joined appendString:k];
        CHECK([joined isEqualToString:@"k1"]);

        // character sets and trimming
        CHECK([[@"  \t padded \n" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqualToString:@"padded"]);
        CHECK([@"a1b22c" componentsSeparatedByCharactersInSet:[NSCharacterSet decimalDigitCharacterSet]].count == 4);
        NSCharacterSet *vowels = [NSCharacterSet characterSetWithCharactersInString:@"aeiou"];
        CHECK([vowels characterIsMember:'e'] && ![vowels characterIsMember:'z'] && [[vowels invertedSet] characterIsMember:'z']);
        CHECK([@"xyzebc" rangeOfCharacterFromSet:vowels].location == 3);
        CHECK([[@"hello wORLD it's" capitalizedString] isEqualToString:@"Hello World It's"]);
        CHECK([[NSCharacterSet letterCharacterSet] characterIsMember:0x65e5] && ![[NSCharacterSet letterCharacterSet] characterIsMember:'7']);

        // process info
        NSProcessInfo *pi = [NSProcessInfo processInfo];
        CHECK(pi.arguments.count == (NSUInteger)argc && [pi.arguments[0] isEqualToString:[NSString stringWithUTF8String:argv[0]]]);
        CHECK(pi.processIdentifier == getpid() && pi.processorCount >= 1 && pi.physicalMemory > 1000000);
        CHECK(pi.environment[@"PATH"] != nil && pi.operatingSystemVersion.majorVersion == 15);
        CHECK([pi isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){14, 0, 0}] && pi.hostName.length > 0);
        CHECK([NSUUID UUID].UUIDString.length == 36 && ![[NSUUID UUID] isEqual:[NSUUID UUID]]);
        NSUUID *fixed = [[NSUUID alloc] initWithUUIDString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"];
        CHECK([fixed.UUIDString isEqualToString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"]);

        // files
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"bitten-fnd-%d", getpid()]];
        NSError *err = nil;
        CHECK([fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"a/b"] withIntermediateDirectories:YES attributes:nil error:&err]);
        NSString *file = [dir stringByAppendingPathComponent:@"a/note.txt"];
        CHECK([@"línea uno\nline two\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&err]);
        BOOL isDir = NO;
        CHECK([fm fileExistsAtPath:file isDirectory:&isDir] && !isDir && [fm fileExistsAtPath:dir isDirectory:&isDir] && isDir);
        NSString *back = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:&err];
        CHECK([back isEqualToString:@"línea uno\nline two\n"]);
        NSDictionary *attrs = [fm attributesOfItemAtPath:file error:&err];
        CHECK([attrs[NSFileSize] intValue] == 20 && [attrs[NSFileType] isEqualToString:NSFileTypeRegular]);
        CHECK([fm copyItemAtPath:[dir stringByAppendingPathComponent:@"a"] toPath:[dir stringByAppendingPathComponent:@"copy"] error:&err]);
        CHECK([[fm subpathsOfDirectoryAtPath:dir error:&err] isEqualToArray:@[@"a", @"a/b", @"a/note.txt", @"copy", @"copy/b", @"copy/note.txt"]]);
        CHECK([fm moveItemAtPath:[dir stringByAppendingPathComponent:@"copy/note.txt"] toPath:[dir stringByAppendingPathComponent:@"moved.txt"] error:&err]);
        CHECK([[fm contentsAtPath:[dir stringByAppendingPathComponent:@"moved.txt"]] length] == 20);
        err = nil;
        CHECK([NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"missing"] encoding:NSUTF8StringEncoding error:&err] == nil);
        CHECK(err && [err.domain isEqualToString:NSCocoaErrorDomain] && err.code == NSFileReadNoSuchFileError);
        CHECK([err.userInfo[NSUnderlyingErrorKey] code] == 2);
        CHECK([fm removeItemAtPath:dir error:&err] && ![fm fileExistsAtPath:dir]);
        CHECK([[@"/a/./b/../c//d/" stringByStandardizingPath] isEqualToString:@"/a/c/d"]);
        CHECK([[@"~/x" stringByExpandingTildeInPath] isEqualToString:[NSHomeDirectory() stringByAppendingString:@"/x"]]);
        CHECK([[@"/usr/local/bin" pathComponents] isEqualToArray:@[@"/", @"usr", @"local", @"bin"]]);

        // URLs
        NSURL *u = [NSURL URLWithString:@"https://user@example.com:8443/a%20b/c.txt?x=1&y=2#frag"];
        CHECK([u.scheme isEqualToString:@"https"] && [u.host isEqualToString:@"example.com"] && u.port.intValue == 8443);
        CHECK([u.path isEqualToString:@"/a b/c.txt"] && [u.query isEqualToString:@"x=1&y=2"] && [u.fragment isEqualToString:@"frag"]);
        CHECK([u.lastPathComponent isEqualToString:@"c.txt"] && [u.pathExtension isEqualToString:@"txt"] && !u.isFileURL);
        NSURL *fu = [NSURL fileURLWithPath:@"/tmp/some dir/file.bin"];
        CHECK(fu.isFileURL && [fu.path isEqualToString:@"/tmp/some dir/file.bin"] && [fu.absoluteString isEqualToString:@"file:///tmp/some%20dir/file.bin"]);
        CHECK([[fu.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"other"].path isEqualToString:@"/tmp/some dir/other"]);
        CHECK([NSURL URLWithString:@"not a url"] == nil);

        // JSON
        NSString *text = @"{\"name\": \"bitten\", \"n\": [1, 2.5, -3e2, true, false, null], \"nested\": {\"s\": \"a\\n\\u00e9\\ud83d\\ude00\"}}";
        id obj = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&err];
        CHECK([obj isKindOfClass:[NSDictionary class]] && [obj[@"name"] isEqualToString:@"bitten"]);
        NSArray *n = obj[@"n"];
        CHECK(n.count == 6 && [n[0] intValue] == 1 && [n[1] doubleValue] == 2.5 && [n[2] doubleValue] == -300.0);
        CHECK([n[3] boolValue] && ![n[4] boolValue] && n[5] == [NSNull null]);
        CHECK([obj[@"nested"][@"s"] isEqualToString:@"a\né😀"]);
        NSData *out = [NSJSONSerialization dataWithJSONObject:@{@"b": @[@1, @YES, [NSNull null], @"q\"t"], @"a": @1.5}
                                                      options:NSJSONWritingSortedKeys error:&err];
        NSString *outs = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
        CHECK([outs isEqualToString:@"{\"a\":1.5,\"b\":[1,true,null,\"q\\\"t\"]}"]);
        id round = [NSJSONSerialization JSONObjectWithData:out options:NSJSONReadingMutableContainers error:&err];
        CHECK([round isEqual:@{@"b": @[@1, @YES, [NSNull null], @"q\"t"], @"a": @1.5}]);
        [round setObject:@2 forKey:@"c"];
        err = nil;
        CHECK([NSJSONSerialization JSONObjectWithData:[@"{\"a\": }" dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&err] == nil && err != nil);
        CHECK([NSJSONSerialization isValidJSONObject:@[@1]] && ![NSJSONSerialization isValidJSONObject:@{@1: @2}]);

        // notifications
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        Listener *l = [Listener new];
        [nc addObserver:l selector:@selector(got:) name:@"Ping" object:nil];
        __block int blocks = 0;
        id token = [nc addObserverForName:@"Ping" object:nil queue:nil usingBlock:^(NSNotification *note) { blocks++; }];
        [nc postNotificationName:@"Ping" object:nil userInfo:@{@"word": @"one"}];
        [nc postNotificationName:@"Other" object:nil];
        CHECK(l.heard == 1 && [l.last isEqualToString:@"one"] && blocks == 1);
        [nc removeObserver:l];
        [nc removeObserver:token];
        [nc postNotificationName:@"Ping" object:nil];
        CHECK(l.heard == 1 && blocks == 1);

        // locks and threads
        NSLock *lock = [NSLock new];
        NSCondition *cond = [NSCondition new];
        __block long total = 0;
        __block int finished = 0;
        CHECK([NSThread isMainThread] && [NSThread currentThread] == [NSThread mainThread]);
        for (int t = 0; t < 4; t++) {
            [NSThread detachNewThreadWithBlock:^{
                BOOL onMain = [NSThread isMainThread];
                [[NSThread currentThread] threadDictionary][@"k"] = @(t);
                for (int i = 0; i < 5000; i++) {
                    [lock lock];
                    total += onMain ? 0 : 1;
                    [lock unlock];
                }
                [cond lock];
                finished++;
                [cond signal];
                [cond unlock];
            }];
        }
        [cond lock];
        while (finished < 4) [cond wait];
        [cond unlock];
        CHECK(total == 20000 && [lock tryLock]);
        [lock unlock];
        NSRecursiveLock *rl = [NSRecursiveLock new];
        [rl lock]; [rl lock]; [rl unlock]; [rl unlock];
        NSDate *before = [NSDate date];
        [NSThread sleepForTimeInterval:0.05];
        CHECK([[NSDate date] timeIntervalSinceDate:before] >= 0.045);
    }
    @autoreleasepool {
        /* NSDecimalNumber to NSDecimal and back */
        NSDecimalNumber *n = [NSDecimalNumber decimalNumberWithString:@"-12.375"];
        NSDecimal d = n.decimalValue;
        CHECK(d._isNegative && d._exponent == -3 && d._length == 1 && d._mantissa[0] == 12375);
        CHECK([[NSDecimalNumber decimalNumberWithDecimal:d] doubleValue] == -12.375);
        NSDecimal big = [[NSDecimalNumber alloc] initWithDouble:123456789012.0].decimalValue;
        CHECK([[[NSDecimalNumber alloc] initWithDecimal:big] doubleValue] == 123456789012.0);
        NSDecimal nan = [NSDecimalNumber notANumber].decimalValue;
        CHECK(nan._length == 0 && nan._isNegative && isnan([[NSDecimalNumber decimalNumberWithDecimal:nan] doubleValue]));
        NSDecimal zero = [NSDecimalNumber zero].decimalValue;
        CHECK(zero._length == 0 && !zero._isNegative);
    }
    puts("foundation more ok");
    return 0;
}
