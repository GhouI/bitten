// What an app does with a command-line helper's output: split the bytes it
// read from the pipe into lines (-[NSData rangeOfData:options:range:],
// -[NSString enumerateLinesUsingBlock:]) and resolve the endpoint it
// printed against a base URL (+[NSURL URLWithString:relativeToURL:]).
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

static BOOL same(NSRange r, NSUInteger location, NSUInteger length) { return r.location == location && r.length == length; }

static NSString *resolve(NSString *ref, NSString *base) {
    return [NSURL URLWithString:ref relativeToURL:[NSURL URLWithString:base]].absoluteString;
}

int main(void) {
    @autoreleasepool {
        NSData *out = [@"{\"pid\": 7}\nready\r\nlast" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *nl = [NSData dataWithBytes:"\n" length:1];
        NSRange all = NSMakeRange(0, out.length);
        CHECK(same([out rangeOfData:nl options:0 range:all], 10, 1));
        CHECK(same([out rangeOfData:nl options:NSDataSearchBackwards range:all], 17, 1));
        CHECK(same([out rangeOfData:nl options:0 range:NSMakeRange(11, out.length - 11)], 17, 1));
        CHECK([out rangeOfData:nl options:NSDataSearchAnchored range:all].location == NSNotFound);
        CHECK(same([out rangeOfData:[NSData dataWithBytes:"{" length:1] options:NSDataSearchAnchored range:all], 0, 1));
        CHECK(same([out rangeOfData:[NSData dataWithBytes:"last" length:4] options:NSDataSearchBackwards | NSDataSearchAnchored range:all], 18, 4));
        CHECK([out rangeOfData:[NSData dataWithBytes:"none" length:4] options:0 range:all].location == NSNotFound);
        CHECK([out rangeOfData:[NSData data] options:0 range:all].location == NSNotFound);
        CHECK([out rangeOfData:nl options:0 range:NSMakeRange(0, 10)].location == NSNotFound);

        NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
        NSMutableArray *lines = [NSMutableArray array];
        [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) { [lines addObject:line]; }];
        CHECK([lines isEqualToArray:(@[@"{\"pid\": 7}", @"ready", @"last"])]);
        [lines removeAllObjects];
        [@"a\n\nb\n" enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) { [lines addObject:line]; *stop = lines.count == 2; }];
        CHECK([lines isEqualToArray:(@[@"a", @""])]);
        [lines removeAllObjects];
        [@"" enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) { [lines addObject:line]; }];
        CHECK(lines.count == 0);

        // RFC 3986 section 5.4's examples, base http://a/b/c/d;p?q
        NSString *base = @"http://a/b/c/d;p?q";
        NSDictionary *cases = @{
            @"g:h": @"g:h", @"g": @"http://a/b/c/g", @"./g": @"http://a/b/c/g", @"g/": @"http://a/b/c/g/",
            @"/g": @"http://a/g", @"//g": @"http://g", @"?y": @"http://a/b/c/d;p?y", @"g?y": @"http://a/b/c/g?y",
            @"#s": @"http://a/b/c/d;p?q#s", @"g#s": @"http://a/b/c/g#s", @"g?y#s": @"http://a/b/c/g?y#s",
            @";x": @"http://a/b/c/;x", @"g;x": @"http://a/b/c/g;x", @"g;x?y#s": @"http://a/b/c/g;x?y#s", @"": @"http://a/b/c/d;p?q",
            @".": @"http://a/b/c/", @"./": @"http://a/b/c/", @"..": @"http://a/b/", @"../g": @"http://a/b/g",
            @"../..": @"http://a/", @"../../g": @"http://a/g", @"../../../g": @"http://a/g", @"g/../h": @"http://a/b/c/h",
        };
        for (NSString *ref in cases) {
            NSString *got = resolve(ref, base);
            if (![got isEqualToString:cases[ref]]) printf("  %s -> %s\n", ref.UTF8String, got.UTF8String);
            CHECK([got isEqualToString:cases[ref]]);
        }
        CHECK([resolve(@"api/control", @"http://rex/") isEqualToString:@"http://rex/api/control"]);
        CHECK([resolve(@"server.sock", @"file:///run/user/0/rex/") isEqualToString:@"file:///run/user/0/rex/server.sock"]);
        CHECK([[NSURL URLWithString:@"http://h/x" relativeToURL:nil].absoluteString isEqualToString:@"http://h/x"]);
        CHECK([NSURL URLWithString:@"has space" relativeToURL:[NSURL URLWithString:base]] == nil);
    }
    puts("helper output ok");
    return 0;
}
