// Foundation basics through bitten's own SDK headers and framework.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

@interface Point3 : NSObject <NSCopying>
@property (nonatomic) int x, y, z;
@end
@implementation Point3
- (NSString *)description { return [NSString stringWithFormat:@"(%d, %d, %d)", _x, _y, _z]; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[Point3 class]] && [o x] == _x && [o y] == _y && [o z] == _z; }
- (NSUInteger)hash { return (NSUInteger)(_x * 31 + _y * 7 + _z); }
- (id)copyWithZone:(NSZone *)zone { Point3 *p = [Point3 new]; p.x = _x; p.y = _y; p.z = _z; return p; }
@end

int main(void) {
    @autoreleasepool {
        // strings: literals, formatting, UTF-16 semantics
        NSString *s = @"hello";
        CHECK(s.length == 5 && [s characterAtIndex:1] == 'e');
        CHECK(strcmp(s.UTF8String, "hello") == 0);
        CHECK([s isEqualToString:[NSString stringWithUTF8String:"hello"]]);
        CHECK([s isEqual:@"hello"] && ![s isEqual:@"Hello"] && s.hash == @"hello".hash);
        NSString *f = [NSString stringWithFormat:@"%@-%d-%5.2f-%s-%lu-%c-%%-%@", s, -42, 3.14159, "c", 7UL, 'x', @7];
        CHECK([f isEqualToString:@"hello--42- 3.14-c-7-x-%-7"]);
        NSString *u = @"naïve 日本 😀";
        CHECK(u.length == 11 && [u lengthOfBytesUsingEncoding:NSUTF8StringEncoding] == 18);
        CHECK([[u substringWithRange:NSMakeRange(6, 2)] isEqualToString:@"日本"]);
        CHECK([u hasPrefix:@"naï"] && [u hasSuffix:@"😀"] && [u containsString:@"日"]);
        CHECK([@"a,b,,c" componentsSeparatedByString:@","].count == 4);
        CHECK([[@"a-b-c" stringByReplacingOccurrencesOfString:@"-" withString:@"+"] isEqualToString:@"a+b+c"]);
        CHECK([[@"MiXed" uppercaseString] isEqualToString:@"MIXED"] && [[@"MiXed" lowercaseString] isEqualToString:@"mixed"]);
        CHECK(@"42abc".intValue == 42 && @"3.5".doubleValue == 3.5 && @"YES".boolValue && !@"no".boolValue);
        CHECK([@"apple" compare:@"banana"] == NSOrderedAscending && [@"A" caseInsensitiveCompare:@"a"] == NSOrderedSame);
        CHECK([[@"/usr/local/bin/tool.tar.gz" lastPathComponent] isEqualToString:@"tool.tar.gz"]);
        CHECK([[@"/usr/local/bin/tool.tar.gz" pathExtension] isEqualToString:@"gz"]);
        CHECK([[@"/usr/local/bin/" stringByDeletingLastPathComponent] isEqualToString:@"/usr/local"]);
        CHECK([[@"/usr" stringByAppendingPathComponent:@"lib"] isEqualToString:@"/usr/lib"]);
        NSMutableString *m = [NSMutableString stringWithString:@"abc"];
        [m appendString:@"def"];
        [m appendFormat:@"%d", 123];
        [m insertString:@">" atIndex:0];
        [m deleteCharactersInRange:NSMakeRange(1, 1)];
        CHECK([m isEqualToString:@">bcdef123"]);
        NSString *frozen = [m copy];
        [m setString:@"changed"];
        CHECK([frozen isEqualToString:@">bcdef123"]);

        // numbers
        NSNumber *n = @42, *d = @2.5, *yes = @YES;
        CHECK(n.intValue == 42 && d.doubleValue == 2.5 && yes.boolValue && [n isEqualToNumber:@42LL]);
        CHECK([n compare:d] == NSOrderedDescending && [[d stringValue] isEqualToString:@"2.5"]);
        CHECK([[n description] isEqualToString:@"42"] && [@(-7) integerValue] == -7 && strcmp(d.objCType, "d") == 0);

        // arrays
        NSArray *a = @[@"one", @2, d, [Point3 new]];
        CHECK(a.count == 4 && [a[0] isEqualToString:@"one"] && [a[1] intValue] == 2);
        CHECK([a containsObject:@2] && [a indexOfObject:@"nope"] == NSNotFound && a.lastObject == a[3]);
        NSMutableArray *ma = [a mutableCopy];
        [ma addObject:@"five"];
        [ma insertObject:@"zero" atIndex:0];
        [ma removeObjectAtIndex:1];
        ma[0] = @"ZERO";
        CHECK(ma.count == 5 && a.count == 4 && [ma[0] isEqualToString:@"ZERO"]);
        int seen = 0;
        for (id o in ma) seen += o != nil;
        CHECK(seen == 5);
        NSArray *words = @[@"pear", @"apple", @"fig"];
        NSArray *sorted = [words sortedArrayUsingSelector:@selector(compare:)];
        CHECK([[sorted componentsJoinedByString:@","] isEqualToString:@"apple,fig,pear"]);
        NSArray *byLength = [words sortedArrayUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
            return x.length < y.length ? NSOrderedAscending : x.length > y.length ? NSOrderedDescending : NSOrderedSame;
        }];
        CHECK([byLength[0] isEqualToString:@"fig"] && [byLength[2] isEqualToString:@"apple"]);
        __block NSUInteger total = 0;
        [words enumerateObjectsUsingBlock:^(NSString *w, NSUInteger i, BOOL *stop) { total += w.length; if (i == 1) *stop = YES; }];
        CHECK(total == 9);
        CHECK([@[@1, @2] isEqualToArray:@[@1, @2]] && ![@[@1] isEqual:@[@2]]);

        // dictionaries with string, number and custom keys
        Point3 *p = [Point3 new];
        p.x = 1; p.y = 2; p.z = 3;
        NSDictionary *dict = @{@"name": @"bitten", @"count": @3, @7: @"seven", p: @"point"};
        CHECK(dict.count == 4 && [dict[@"name"] isEqualToString:@"bitten"] && [dict[@"count"] intValue] == 3);
        CHECK([dict[@7] isEqualToString:@"seven"] && dict[@"missing"] == nil);
        Point3 *same = [p copy];
        CHECK(same != p && [dict[same] isEqualToString:@"point"]);   // found by isEqual:/hash
        NSMutableDictionary *md = [dict mutableCopy];
        md[@"extra"] = @[@1, @2];
        md[@"name"] = nil;
        CHECK(md.count == 4 && md[@"name"] == nil && dict.count == 4);
        NSUInteger keys = 0;
        for (id k in md) keys += md[k] != nil;
        CHECK(keys == 4);
        __block int visited = 0;
        [md enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { visited++; }];
        CHECK(visited == 4);
        CHECK([[@{@"a": @1} description] isEqualToString:@"{\n    a = 1;\n}"]);
        CHECK([[@[@1, @"x"] description] isEqualToString:@"(\n    1,\n    x\n)"]);
        CHECK([[NSString stringWithFormat:@"%@", p] isEqualToString:@"(1, 2, 3)"]);
        CHECK([[NSNull null] isEqual:[NSNull null]] && [NSStringFromClass([Point3 class]) isEqualToString:@"Point3"]);
        CHECK(NSClassFromString(@"Point3") == [Point3 class] && NSClassFromString(@"Nope") == Nil);
        NSLog(@"foundation says %@ with %lu keys", dict[@"name"], (unsigned long)dict.count);
    }
    // Sorting is stable: equal items keep their order.
    NSArray *words = @[@"bb", @"a2", @"cc", @"a1", @"dd", @"a3"];
    NSArray *byLength = [words sortedArrayUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
        return [@(x.length) compare:@(y.length)];
    }];
    CHECK([byLength isEqualToArray:words]);
    NSArray *byFirst = [words sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSString *x, NSString *y) {
        return [[x substringToIndex:1] compare:[y substringToIndex:1]];
    }];
    CHECK([byFirst isEqualToArray:(@[@"a2", @"a1", @"a3", @"bb", @"cc", @"dd"])]);
    NSDictionary *scores = @{@"x" : @3, @"y" : @1, @"z" : @2};
    CHECK([[scores keysSortedByValueUsingSelector:@selector(compare:)] isEqualToArray:(@[@"y", @"z", @"x"])]);
    puts("foundation basics ok");
    return 0;
}
