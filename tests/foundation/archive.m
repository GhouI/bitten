// Keyed archiving (collections, dates, URLs, custom NSCoding classes,
// shared references) and memory and file streams.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

@interface Point3 : NSObject <NSSecureCoding>
@property double x, y;
@property (copy) NSString *label;
@property (strong) Point3 *next;
@end
@implementation Point3
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeDouble:_x forKey:@"x"];
    [c encodeDouble:_y forKey:@"y"];
    [c encodeObject:_label forKey:@"label"];
    [c encodeObject:_next forKey:@"next"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    _x = [c decodeDoubleForKey:@"x"];
    _y = [c decodeDoubleForKey:@"y"];
    _label = [c decodeObjectOfClass:[NSString class] forKey:@"label"];
    _next = [c decodeObjectOfClass:[Point3 class] forKey:@"next"];
    return self;
}
@end

int main(void) {
    @autoreleasepool {
        NSDate *when = [NSDate dateWithTimeIntervalSinceReferenceDate:1234.5];
        NSDictionary *root = @{@"name" : @"bitten", @"n" : @42, @"list" : @[ @1, @"two", when ],
                               @"url" : [NSURL URLWithString:@"https://example.com/a"], @"blob" : [@"xyz" dataUsingEncoding:NSUTF8StringEncoding]};
        NSError *err = nil;
        NSData *d = [NSKeyedArchiver archivedDataWithRootObject:root requiringSecureCoding:YES error:&err];
        CHECK(d.length > 0 && !err);
        NSDictionary *back = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSDictionary class] fromData:d error:&err];
        CHECK([back[@"name"] isEqual:@"bitten"] && [back[@"n"] isEqual:@42]);
        CHECK([back[@"list"] count] == 3 && [back[@"list"][2] isEqual:when]);
        CHECK([[back[@"url"] absoluteString] isEqual:@"https://example.com/a"]);
        CHECK([back[@"blob"] isEqual:root[@"blob"]]);

        Point3 *a = [Point3 new], *b = [Point3 new];
        a.x = 1.5; a.y = -2; a.label = @"a"; a.next = b;
        b.x = 3; b.label = @"b";
        NSArray *pair = @[ a, b ];
        d = [NSKeyedArchiver archivedDataWithRootObject:pair requiringSecureCoding:YES error:NULL];
        NSArray *pb = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithObjects:[NSArray class], [Point3 class], nil]
                                                          fromData:d error:NULL];
        CHECK(pb.count == 2);
        Point3 *a2 = pb[0], *b2 = pb[1];
        CHECK(a2.x == 1.5 && a2.y == -2 && [a2.label isEqual:@"a"] && b2.x == 3);
        CHECK(a2.next == b2);  // the shared object decodes once
        CHECK(![NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:d error:NULL]);

        NSInputStream *in = [NSInputStream inputStreamWithData:[@"hello stream" dataUsingEncoding:NSUTF8StringEncoding]];
        [in open];
        uint8_t buf[5];
        NSMutableData *got = [NSMutableData data];
        while (in.hasBytesAvailable) {
            NSInteger n = [in read:buf maxLength:sizeof buf];
            if (n <= 0) break;
            [got appendBytes:buf length:n];
        }
        CHECK(in.streamStatus == NSStreamStatusAtEnd && [[[NSString alloc] initWithData:got encoding:NSUTF8StringEncoding] isEqual:@"hello stream"]);
        NSOutputStream *out = [NSOutputStream outputStreamToMemory];
        [out open];
        CHECK([out write:(const uint8_t *)"abc" maxLength:3] == 3);
        CHECK([[out propertyForKey:NSStreamDataWrittenToMemoryStreamKey] length] == 3);
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"bitten-stream-test"];
        NSOutputStream *fo = [NSOutputStream outputStreamToFileAtPath:path append:NO];
        [fo open];
        [fo write:(const uint8_t *)"file!" maxLength:5];
        [fo close];
        NSInputStream *fi = [NSInputStream inputStreamWithFileAtPath:path];
        [fi open];
        uint8_t fb[16] = {0};
        CHECK([fi read:fb maxLength:sizeof fb] == 5 && !memcmp(fb, "file!", 5));
        [fi close];
        puts("foundation archive ok");
    }
    return 0;
}
