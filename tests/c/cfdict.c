/* CFDictionary and CFSet at scale: the hash index, removal, and growth. */
#include "darwin.h"

typedef const void *CFTypeRef;
typedef long CFIndex;
CFTypeRef CFDictionaryCreateMutable(void *, CFIndex, const void *, const void *);
void CFDictionarySetValue(CFTypeRef, const void *, const void *);
const void *CFDictionaryGetValue(CFTypeRef, const void *);
void CFDictionaryRemoveValue(CFTypeRef, const void *);
void CFDictionaryRemoveAllValues(CFTypeRef);
CFIndex CFDictionaryGetCount(CFTypeRef);
unsigned char CFDictionaryContainsKey(CFTypeRef, const void *);
CFTypeRef CFDictionaryCreateCopy(void *, CFTypeRef);
unsigned char CFEqual(CFTypeRef, CFTypeRef);
CFTypeRef CFStringCreateWithCString(void *, const char *, unsigned);
CFTypeRef CFNumberCreate(void *, long, const void *);
unsigned char CFNumberGetValue(CFTypeRef, long, void *);
void CFRelease(CFTypeRef);
extern const char kCFTypeDictionaryKeyCallBacks, kCFTypeDictionaryValueCallBacks;
struct timespec { long tv_sec, tv_nsec; };
int clock_gettime(int, struct timespec *);
#define kCFStringEncodingUTF8 0x08000100
#define kCFNumberLongType 10
#define N 20000

static CFTypeRef key_for(long i) {
    char buf[32];
    snprintf(buf, sizeof buf, "key-%ld", i);
    return CFStringCreateWithCString(NULL, buf, kCFStringEncodingUTF8);
}

int main(void) {
    struct timespec t0, t1;
    clock_gettime(6, &t0);
    CFTypeRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    for (long i = 0; i < N; i++) {
        CFTypeRef k = key_for(i), v = CFNumberCreate(NULL, kCFNumberLongType, &i);
        CFDictionarySetValue(d, k, v);
        CFRelease(k);
        CFRelease(v);
    }
    CHECK(CFDictionaryGetCount(d) == N);
    /* every key is found through a fresh, equal string */
    for (long i = 0; i < N; i++) {
        CFTypeRef k = key_for(i);
        long got = -1;
        CFTypeRef v = CFDictionaryGetValue(d, k);
        CHECK(v && CFNumberGetValue(v, kCFNumberLongType, &got) && got == i);
        CFRelease(k);
    }
    /* overwrite does not grow; remove every other key; survivors intact */
    long minus = -1;
    CFTypeRef k0 = key_for(0), neg = CFNumberCreate(NULL, kCFNumberLongType, &minus);
    CFDictionarySetValue(d, k0, neg);
    CHECK(CFDictionaryGetCount(d) == N);
    CFRelease(neg);
    CFRelease(k0);
    for (long i = 0; i < N; i += 2) {
        CFTypeRef k = key_for(i);
        CFDictionaryRemoveValue(d, k);
        CHECK(!CFDictionaryContainsKey(d, k));
        CFRelease(k);
    }
    CHECK(CFDictionaryGetCount(d) == N / 2);
    for (long i = 0; i < N; i++) {
        CFTypeRef k = key_for(i);
        CHECK(CFDictionaryContainsKey(d, k) == (i % 2 == 1));
        CFRelease(k);
    }
    /* reinsert after tombstones, copy, compare */
    for (long i = 0; i < N; i += 2) {
        CFTypeRef k = key_for(i), v = CFNumberCreate(NULL, kCFNumberLongType, &i);
        CFDictionarySetValue(d, k, v);
        CFRelease(k);
        CFRelease(v);
    }
    CHECK(CFDictionaryGetCount(d) == N);
    CFTypeRef copy = CFDictionaryCreateCopy(NULL, d);
    CHECK(CFEqual(copy, d));
    CFDictionaryRemoveAllValues(d);
    CHECK(CFDictionaryGetCount(d) == 0 && CFDictionaryGetCount(copy) == N && !CFEqual(copy, d));
    CFRelease(copy);
    CFRelease(d);
    clock_gettime(6, &t1);
    double secs = (double)(t1.tv_sec - t0.tv_sec) + (double)(t1.tv_nsec - t0.tv_nsec) / 1e9;
    /* a linear table needs on the order of 10^9 comparisons for this */
    CHECK(secs < 5.0);
    puts("cfdict ok");
    return 0;
}
