// Driver for hashing.swift. The seed is chosen on first use, so each mode
// runs in a forked child: with SWIFT_DETERMINISTIC_HASHING=1 the hashes must
// be the ones macOS gives for the same values; without it they must differ
// between processes and stay consistent within one.
#include "darwin.h"

int fork(void);
int pipe(int *);
int close(int);
ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
int waitpid(int, int *, int);
int setenv(const char *, const char *, int);

long swl_hash_int(long);
long swl_hash_mixed(void);
long swl_hash_value(long);
long swl_hash_consistency(void);

// Hashes Apple's standard library produces with deterministic hashing.
static const long expected_value[] = {
    8880661182590738257L,   // 42.hashValue
    -3400736038611009L,     // (7 as UInt8).hashValue
    7541581120933061747L,   // Int?.none.hashValue
    -3445980191031581528L,  // Optional(3).hashValue
    4952851536318644461L,   // true.hashValue
};

static void deterministic(void) {
    setenv("SWIFT_DETERMINISTIC_HASHING", "1", 1);
    CHECK(swl_hash_int(42) == 8880661182590738257L);
    CHECK(swl_hash_mixed() == -161104438756234761L);
    for (long i = 0; i < 5; i++) CHECK(swl_hash_value(i) == expected_value[i]);
    CHECK(swl_hash_consistency() == 0);
}

// Runs in a child without the variable; reports its hash of 42 on fd.
static void seeded(int fd) {
    long h = swl_hash_int(42);
    CHECK(h == swl_hash_int(42));
    CHECK(swl_hash_consistency() == 0);
    CHECK(write(fd, &h, sizeof h) == sizeof h);
}

static void wait_ok(int pid) {
    int st = -1;
    CHECK(waitpid(pid, &st, 0) == pid);
    CHECK(st == 0);
}

int main(void) {
    int pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) { deterministic(); exit(0); }
    wait_ok(pid);

    long seen[2];
    for (int i = 0; i < 2; i++) {
        int p[2];
        CHECK(!pipe(p));
        pid = fork();
        CHECK(pid >= 0);
        if (pid == 0) { close(p[0]); seeded(p[1]); exit(0); }
        close(p[1]);
        CHECK(read(p[0], &seen[i], sizeof seen[i]) == sizeof seen[i]);
        close(p[0]);
        wait_ok(pid);
    }
    CHECK(seen[0] != seen[1]);
    CHECK(seen[0] != 8880661182590738257L);

    puts("swift stdlib hashing ok");
    return 0;
}
