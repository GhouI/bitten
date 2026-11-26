// -[NSFileManager contentsEqualAtPath:andPath:]: files by bytes, symbolic
// links by destination, directories recursively.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"filecompare-%d", getpid()]];
        NSString *a = [root stringByAppendingPathComponent:@"a"], *b = [root stringByAppendingPathComponent:@"b"];
        CHECK([fm createDirectoryAtPath:[a stringByAppendingPathComponent:@"sub"] withIntermediateDirectories:YES
                             attributes:nil error:NULL]);
        CHECK([fm createDirectoryAtPath:[b stringByAppendingPathComponent:@"sub"] withIntermediateDirectories:YES
                             attributes:nil error:NULL]);
        NSData *d = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
        for (NSString *dir in @[ a, b ]) {
            CHECK([d writeToFile:[dir stringByAppendingPathComponent:@"sub/f"] atomically:NO]);
            CHECK([fm createSymbolicLinkAtPath:[dir stringByAppendingPathComponent:@"l"] withDestinationPath:@"sub/f"
                                         error:NULL]);
        }
        CHECK([fm contentsEqualAtPath:a andPath:b]);
        CHECK([fm contentsEqualAtPath:[a stringByAppendingPathComponent:@"sub/f"]
                              andPath:[b stringByAppendingPathComponent:@"sub/f"]]);
        CHECK(![fm contentsEqualAtPath:[a stringByAppendingPathComponent:@"sub/f"] andPath:a]);
        CHECK([[@"hellp" dataUsingEncoding:NSUTF8StringEncoding]
            writeToFile:[b stringByAppendingPathComponent:@"sub/f"] atomically:NO]);
        CHECK(![fm contentsEqualAtPath:a andPath:b]);
        CHECK(![fm contentsEqualAtPath:a andPath:[root stringByAppendingPathComponent:@"missing"]]);
        [fm removeItemAtPath:root error:NULL];
        printf("ok\n");
    }
    return 0;
}
