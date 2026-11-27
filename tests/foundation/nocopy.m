// The no-copy NSData initialisers: NSData borrows the caller's buffer and
// gives it back exactly once (free, a deallocator block, or not at all);
// NSMutableData copies and gives the buffer back at once.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)

static int calls;
static void *seen_bytes;
static NSUInteger seen_length;
static void (^counting)(void *, NSUInteger) = ^(void *bytes, NSUInteger length) {
    calls++;
    seen_bytes = bytes;
    seen_length = length;
};

int main(void) {
    @autoreleasepool {
        char stack[] = "borrowed";
        NSData *d = [NSData dataWithBytesNoCopy:stack length:8 freeWhenDone:NO];
        CHECK(d.bytes == stack && d.length == 8);
        stack[0] = 'B';
        CHECK(((const char *)d.bytes)[0] == 'B');
        CHECK([d isEqual:[NSData dataWithBytes:"Borrowed" length:8]]);
    }

    calls = 0;
    char *heap = strdup("handed over");
    @autoreleasepool {
        NSData *d = [[NSData alloc] initWithBytesNoCopy:heap length:11 deallocator:counting];
        CHECK(d.bytes == heap && d.length == 11);
        NSData *copy = [d copy];
        NSData *sub = [d subdataWithRange:NSMakeRange(7, 4)];
        CHECK(calls == 0);
        d = nil;
        CHECK(calls == 1 && seen_bytes == heap && seen_length == 11);
        memset(heap, '#', 11);
        CHECK(copy.length == 11 && memcmp(copy.bytes, "handed over", 11) == 0);
        CHECK(memcmp(sub.bytes, "over", 4) == 0);
    }
    CHECK(calls == 1);
    free(heap);

    @autoreleasepool {
        char *owned = malloc(4);
        memcpy(owned, "free", 4);
        NSData *a = [NSData dataWithBytesNoCopy:owned length:4];
        NSData *b = [[NSData alloc] initWithBytesNoCopy:strdup("done") length:4 freeWhenDone:YES];
        NSData *c = [[NSData alloc] initWithBytesNoCopy:strdup("also") length:4];
        CHECK(a.bytes == owned && memcmp(b.bytes, "done", 4) == 0 && memcmp(c.bytes, "also", 4) == 0);
        NSMutableData *grown = [a mutableCopy];
        [grown appendBytes:"!" length:1];
        CHECK(grown.length == 5 && a.length == 4);
    }

    @autoreleasepool {
        calls = 0;
        NSData *d = [[NSData alloc] initWithBytesNoCopy:NULL length:0 deallocator:counting];
        CHECK(d.length == 0);
        d = nil;
    }
    CHECK(calls == 1);

    @autoreleasepool {
        NSData *d = [[NSData alloc] initWithBytesNoCopy:(void *)"x" length:1 deallocator:nil];
        CHECK(d.length == 1 && ((const char *)d.bytes)[0] == 'x');
    }

    @autoreleasepool {
        calls = 0;
        char *heap2 = strdup("mutable");
        NSMutableData *m = [[NSMutableData alloc] initWithBytesNoCopy:heap2 length:7 deallocator:counting];
        CHECK(calls == 1 && seen_bytes == heap2);
        free(heap2);
        CHECK([m isKindOfClass:[NSMutableData class]] && m.length == 7);
        CHECK(memcmp(m.bytes, "mutable", 7) == 0);
        [m appendBytes:"!" length:1];
        CHECK(m.length == 8 && memcmp(m.bytes, "mutable!", 8) == 0);

        char keep[] = "kept";
        NSMutableData *k = [NSMutableData dataWithBytesNoCopy:keep length:4 freeWhenDone:NO];
        CHECK([k isKindOfClass:[NSMutableData class]] && k.length == 4);
        ((char *)k.mutableBytes)[0] = 'K';
        CHECK(keep[0] == 'k');
        NSMutableData *f = [NSMutableData dataWithBytesNoCopy:strdup("gone") length:4];
        [f appendBytes:"!" length:1];
        CHECK(f.length == 5 && memcmp(f.bytes, "gone!", 5) == 0);
    }

    CFDataRef cf = CFDataCreateWithBytesNoCopy(NULL, (const uint8_t *)"cf", 2, kCFAllocatorNull);
    CHECK(CFDataGetLength(cf) == 2 && memcmp(CFDataGetBytePtr(cf), "cf", 2) == 0);
    CFRelease(cf);
    cf = CFDataCreateWithBytesNoCopy(NULL, (const uint8_t *)strdup("malloc"), 6, kCFAllocatorMalloc);
    CHECK(CFDataGetLength(cf) == 6);
    CFRelease(cf);

    printf("nocopy ok\n");
    return 0;
}
