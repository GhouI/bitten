// Driver for failures.swift. Each fatal path runs in a forked child whose
// stderr goes through a pipe; the parent checks the report and that the
// child died from the trap.
#include "darwin.h"

int fork(void);
int pipe(int *);
int dup2(int, int);
int close(int);
ssize_t read(int, void *, size_t);
int waitpid(int, int *, int);

_Bool swl_debug(void);
long swl_static_count(void);
unsigned swl_static_scalar(void);
unsigned swl_scalar(unsigned);
long swl_unwrap(long);
long swl_overflow(long);
long swl_unimplemented(void);

static int contains(const char *s, const char *needle) {
    size_t n = strlen(needle);
    for (; *s; s++)
        if (!memcmp(s, needle, n)) return 1;
    return 0;
}

// Runs f(arg) in a child; returns its stderr in buf and whether it was
// terminated by a signal.
static int run_child(long (*f)(long), long arg, char *buf, size_t cap) {
    int p[2];
    CHECK(!pipe(p));
    int pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(p[0]);
        dup2(p[1], 2);
        f(arg);
        exit(0);   // not reached when the call traps
    }
    close(p[1]);
    size_t len = 0;
    ssize_t k;
    while (len + 1 < cap && (k = read(p[0], buf + len, cap - 1 - len)) > 0) len += (size_t)k;
    buf[len] = 0;
    close(p[0]);
    int st = 0;
    CHECK(waitpid(pid, &st, 0) == pid);
    return (st & 0x7f) != 0;
}

static long unimplemented(long x) { (void)x; return swl_unimplemented(); }

int main(void) {
    char buf[1024];
    int dbg = swl_debug();

    CHECK(swl_static_count() == 1000 + 600 + 50 + 0);
    unsigned sc = swl_static_scalar();
    CHECK(sc == 0xe9 || sc == 2);
    CHECK(swl_scalar(0x41) == (0x41u | 0x20000000u));
    CHECK(swl_scalar(0x1F600) == (0x1F600u | 0x10000000u));
    CHECK(swl_scalar(0xD800) == 0xFFFFFFFFu);
    CHECK(swl_scalar(0x110000) == 0xFFFFFFFFu);

    CHECK(swl_unwrap(7) == 7);
    CHECK(run_child(swl_unwrap, 0, buf, sizeof buf));
    if (dbg) {
        CHECK(contains(buf, "failures.swift:"));
        CHECK(contains(buf, ": Fatal error: Unexpectedly found nil while unwrapping an Optional value\n"));
    } else {
        CHECK(buf[0] == 0);
    }

    CHECK(swl_overflow(5) == 5);
    CHECK(run_child(swl_overflow, 1000, buf, sizeof buf));
    if (dbg) CHECK(contains(buf, ": Fatal error: Overflow/underflow\n"));

    CHECK(run_child(unimplemented, 0, buf, sizeof buf));
    CHECK(contains(buf, "Fatal error: Use of unimplemented initializer 'unimplemented()' for class 'failures.Widget'\n"));

    printf("swift stdlib failures ok (%s)\n", dbg ? "debug" : "release");
    return 0;
}
