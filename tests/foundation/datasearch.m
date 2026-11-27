// -[NSData rangeOfData:options:range:]: forwards, backwards, anchored, and
// empty needles and needles longer than the range.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

static NSData *D(const char *s) { return [NSData dataWithBytes:s length:strlen(s)]; }

int main(void) {
    @autoreleasepool {
        NSData *hay = D("abcabcab");
        NSRange all = NSMakeRange(0, hay.length);
        NSRange r = [hay rangeOfData:D("bc") options:0 range:all];
        CHECK(r.location == 1 && r.length == 2);
        r = [hay rangeOfData:D("bc") options:NSDataSearchBackwards range:all];
        CHECK(r.location == 4 && r.length == 2);
        r = [hay rangeOfData:D("bc") options:0 range:NSMakeRange(2, 6)];
        CHECK(r.location == 4);
        r = [hay rangeOfData:D("ab") options:NSDataSearchAnchored range:all];
        CHECK(r.location == 0);
        r = [hay rangeOfData:D("bc") options:NSDataSearchAnchored range:all];
        CHECK(r.location == NSNotFound);
        r = [hay rangeOfData:D("ab") options:NSDataSearchAnchored | NSDataSearchBackwards range:all];
        CHECK(r.location == 6);
        r = [hay rangeOfData:D("ca") options:NSDataSearchAnchored | NSDataSearchBackwards range:all];
        CHECK(r.location == NSNotFound);
        r = [hay rangeOfData:D("zz") options:0 range:all];
        CHECK(r.location == NSNotFound && r.length == 0);
        r = [hay rangeOfData:[NSData data] options:0 range:all];
        CHECK(r.location == NSNotFound);
        r = [hay rangeOfData:D("abcabcabc") options:0 range:all];
        CHECK(r.location == NSNotFound);
        r = [hay rangeOfData:D("cab") options:0 range:NSMakeRange(2, 3)];
        CHECK(r.location == 2 && r.length == 3);
        r = [hay rangeOfData:D("cab") options:0 range:NSMakeRange(2, 2)];
        CHECK(r.location == NSNotFound);
    }
    printf("datasearch ok\n");
    return 0;
}
