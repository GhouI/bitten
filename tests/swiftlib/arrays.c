// Driver for arrays.swift.
#include "darwin.h"

long swa_layout(void);
long swa_basics(void);
long swa_mutation(void);
long swa_cow(void);
long swa_objects(long step);
long swa_pointers(void);
long swa_generic(void);

extern char _swiftEmptyArrayStorage[];
const void *swa_empty_storage(void) { return _swiftEmptyArrayStorage; }

void swa_fill(long *p, long n) { for (long i = 0; i < n; i++) p[i] = i * 10; }
long swa_sum(const long *p, long n) { long s = 0; for (long i = 0; i < n; i++) s += p[i]; return s; }

static int died[16];
void swa_note_deinit(long v) { if (v >= 0 && v < 16) died[v]++; }

static void expect(const char *what, long got, long want) {
    if (got != want) printf("%s: %#lx, expected %#lx\n", what, got, want);
    CHECK(got == want);
}

int main(void) {
    expect("layout", swa_layout(), 31);
    expect("basics", swa_basics(), 63);
    expect("mutation", swa_mutation(), 2047);
    expect("cow", swa_cow(), 255);
    expect("objects 1", swa_objects(1), 1);
    CHECK(died[1] == 1 && died[2] == 1 && died[3] == 1 && died[4] == 1);
    expect("objects 2", swa_objects(2), 3);
    CHECK(died[5] == 10 && died[6] == 10 && died[7] == 1 && died[8] == 1 && died[9] == 1);
    /* swa_layout's Token(100) is not counted (out of range) */
    expect("pointers", swa_pointers(), 3);
    expect("generic", swa_generic(), 7);
    puts("swift stdlib arrays ok");
    return 0;
}
