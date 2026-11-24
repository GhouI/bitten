/* kqueue filters beyond sockets: user events, timers, process exit, pipes. */
#include "darwin.h"

struct timespec { long tv_sec, tv_nsec; };
struct kevent { unsigned long ident; short filter; unsigned short flags; uint32_t fflags; long data; void *udata; };
int kqueue(void);
int kevent(int, const struct kevent *, int, struct kevent *, int, const struct timespec *);
int pipe(int[2]);
int close(int);
ssize_t write(int, const void *, size_t);
ssize_t read(int, void *, size_t);
int fork(void);
int waitpid(int, int *, int);
void _exit(int);
int usleep(unsigned);

#define EVFILT_READ (-1)
#define EVFILT_PROC (-5)
#define EVFILT_TIMER (-7)
#define EVFILT_USER (-10)
#define EV_ADD 1
#define EV_DELETE 2
#define EV_ONESHOT 0x10
#define EV_CLEAR 0x20
#define EV_EOF 0x8000
#define NOTE_TRIGGER 0x01000000
#define NOTE_EXIT 0x80000000u
#define ENOENT 2

int main(void) {
    int kq = kqueue();
    CHECK(kq >= 0);
    struct kevent ch, ev[4];
    struct timespec zero = {0, 0}, sec = {2, 0};

    /* nothing registered: a zero timeout returns immediately */
    CHECK(kevent(kq, NULL, 0, ev, 4, &zero) == 0);

    /* user event */
    ch = (struct kevent){42, EVFILT_USER, EV_ADD | EV_CLEAR, 0, 0, (void *)0x1234};
    CHECK(kevent(kq, &ch, 1, NULL, 0, NULL) == 0);
    CHECK(kevent(kq, NULL, 0, ev, 4, &zero) == 0);
    ch = (struct kevent){42, EVFILT_USER, 0, NOTE_TRIGGER, 0, NULL};
    CHECK(kevent(kq, &ch, 1, NULL, 0, NULL) == 0);
    CHECK(kevent(kq, NULL, 0, ev, 4, &sec) == 1);
    CHECK(ev[0].ident == 42 && ev[0].filter == EVFILT_USER && ev[0].udata == (void *)0x1234);
    CHECK(kevent(kq, NULL, 0, ev, 4, &zero) == 0); /* EV_CLEAR reset it */

    /* deleting an unknown event reports ENOENT */
    ch = (struct kevent){77, EVFILT_USER, EV_DELETE, 0, 0, NULL};
    CHECK(kevent(kq, &ch, 1, NULL, 0, NULL) == -1 && errno == ENOENT);

    /* pipe readability, level-triggered, then EOF */
    int p[2];
    CHECK(pipe(p) == 0);
    ch = (struct kevent){p[0], EVFILT_READ, EV_ADD, 0, 0, (void *)7};
    CHECK(kevent(kq, &ch, 1, NULL, 0, NULL) == 0);
    CHECK(kevent(kq, NULL, 0, ev, 4, &zero) == 0);
    CHECK(write(p[1], "abc", 3) == 3);
    CHECK(kevent(kq, NULL, 0, ev, 4, &sec) == 1);
    CHECK(ev[0].ident == (unsigned long)p[0] && ev[0].filter == EVFILT_READ && ev[0].data == 3);
    CHECK(kevent(kq, NULL, 0, ev, 4, &sec) == 1); /* still readable */
    char buf[8];
    CHECK(read(p[0], buf, 8) == 3);
    CHECK(kevent(kq, NULL, 0, ev, 4, &zero) == 0);
    close(p[1]);
    CHECK(kevent(kq, NULL, 0, ev, 4, &sec) == 1);
    CHECK(ev[0].flags & EV_EOF);
    close(p[0]);
    CHECK(kevent(kq, NULL, 0, ev, 4, &zero) == 0);

    /* one-shot timer, 20 ms */
    ch = (struct kevent){1, EVFILT_TIMER, EV_ADD | EV_ONESHOT, 0, 20, NULL};
    CHECK(kevent(kq, &ch, 1, NULL, 0, NULL) == 0);
    CHECK(kevent(kq, NULL, 0, ev, 4, &sec) == 1);
    CHECK(ev[0].filter == EVFILT_TIMER && ev[0].ident == 1 && ev[0].data >= 1);

    /* process exit */
    int pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        usleep(30000);
        _exit(5);
    }
    ch = (struct kevent){pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL};
    CHECK(kevent(kq, &ch, 1, NULL, 0, NULL) == 0);
    CHECK(kevent(kq, NULL, 0, ev, 4, &sec) == 1);
    CHECK(ev[0].filter == EVFILT_PROC && ev[0].ident == (unsigned long)pid && (ev[0].fflags & NOTE_EXIT));
    int st;
    CHECK(waitpid(pid, &st, 0) == pid && ((st >> 8) & 0xff) == 5);

    CHECK(close(kq) == 0);
    puts("kqueue ok");
    return 0;
}
