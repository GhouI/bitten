/* Raw Darwin system calls: the `syscall` instruction with a BSD-class
 * number, results in rax and the carry flag. */
#include "darwin.h"

int getpid(void);
int close(int);
ssize_t read(int, void *, size_t);
int pthread_create(void **, void *, void *(*)(void *), void *);
int pthread_join(void *, void **);

struct result { long value; long rdx; int carry; };

static struct result raw(long nr, long a, long b, long c) {
    struct result r;
    unsigned char cf;
    register long r10 __asm__("r10") = 0;
    __asm__ volatile("syscall\n\tsetc %3"
                     : "=a"(r.value), "=d"(r.rdx), "+r"(r10), "=qm"(cf)
                     : "a"(nr | 0x2000000), "D"(a), "S"(b), "d"(c)
                     : "rcx", "r11", "memory", "cc");
    r.carry = cf;
    return r;
}

static void *in_thread(void *arg) {
    struct result r = raw(20 /* getpid */, 0, 0, 0);
    return (void *)(long)(r.carry == 0 && r.value == (long)arg);
}

int main(void) {
    struct result r = raw(20 /* getpid */, 0, 0, 0);
    CHECK(r.carry == 0 && r.value == getpid());

    r = raw(42 /* pipe */, 0, 0, 0);
    CHECK(r.carry == 0);
    int rd = (int)r.value, wr = (int)r.rdx;
    CHECK(rd >= 0 && wr >= 0 && rd != wr);

    r = raw(4 /* write */, wr, (long)"raw!", 4);
    CHECK(r.carry == 0 && r.value == 4);
    char buf[8] = {0};
    CHECK(read(rd, buf, 8) == 4 && memcmp(buf, "raw!", 4) == 0);

    /* errors: carry set, Darwin errno in rax */
    r = raw(6 /* close */, 9999, 0, 0);
    CHECK(r.carry == 1 && r.value == 9 /* EBADF */);
    r = raw(5 /* open */, (long)"/definitely/not/here", 0, 0);
    CHECK(r.carry == 1 && r.value == 2 /* ENOENT */);

    /* dispatch is armed per thread */
    void *t, *ok;
    CHECK(pthread_create(&t, NULL, in_thread, (void *)(long)getpid()) == 0);
    CHECK(pthread_join(t, &ok) == 0 && ok == (void *)1);

    close(rd);
    close(wr);
    puts("rawsyscall ok");
    return 0;
}
