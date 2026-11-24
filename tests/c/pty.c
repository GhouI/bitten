/* Pseudo-terminals with Darwin's termios layout and ioctl request codes. */
#include "darwin.h"

struct termios { unsigned long c_iflag, c_oflag, c_cflag, c_lflag; unsigned char c_cc[20]; unsigned long c_ispeed, c_ospeed; };
struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
int posix_openpt(int);
int grantpt(int);
int unlockpt(int);
char *ptsname(int);
int open(const char *, int, ...);
int close(int);
int ioctl(int, unsigned long, ...);
int tcgetattr(int, struct termios *);
int tcsetattr(int, int, const struct termios *);
ssize_t write(int, const void *, size_t);
ssize_t read(int, void *, size_t);
int isatty(int);
int fork(void);
int setsid(void);
int dup2(int, int);
int execve(const char *, char *const[], char *const[]);
int waitpid(int, int *, int);
void _exit(int);
char *strstr(const char *, const char *);

#define O_RDWR 2
#define O_NOCTTY 0x20000
#define TIOCGWINSZ 0x40087468UL
#define TIOCSWINSZ 0x80087467UL
#define TIOCSCTTY 0x20007461UL
#define ICANON 0x100
#define ECHO 0x8
#define ISIG 0x80
#define OPOST 0x1
#define ONLCR 0x2
#define VMIN 16

int main(void) {
    int m = posix_openpt(O_RDWR | O_NOCTTY);
    CHECK(m >= 0);
    CHECK(grantpt(m) == 0 && unlockpt(m) == 0);
    char *name = ptsname(m);
    CHECK(name != NULL);
    int s = open(name, O_RDWR | O_NOCTTY);
    CHECK(s >= 0 && isatty(s));

    struct winsize ws = {40, 132, 0, 0}, got = {0};
    CHECK(ioctl(m, TIOCSWINSZ, &ws) == 0);
    CHECK(ioctl(s, TIOCGWINSZ, &got) == 0);
    CHECK(got.ws_row == 40 && got.ws_col == 132);

    struct termios t;
    CHECK(tcgetattr(s, &t) == 0);
    /* a fresh Linux pty is in cooked mode: Darwin's bits must show that */
    CHECK((t.c_lflag & ICANON) && (t.c_lflag & ECHO) && (t.c_lflag & ISIG));
    CHECK((t.c_oflag & OPOST) && (t.c_oflag & ONLCR));
    CHECK(t.c_cc[8] == 3 /* VINTR = ^C */ && t.c_cc[0] == 4 /* VEOF = ^D */);
    t.c_lflag &= ~(unsigned long)(ICANON | ECHO);
    t.c_cc[VMIN] = 1;
    CHECK(tcsetattr(s, 0, &t) == 0);
    struct termios t2;
    CHECK(tcgetattr(s, &t2) == 0);
    CHECK(!(t2.c_lflag & ICANON) && !(t2.c_lflag & ECHO) && (t2.c_lflag & ISIG));

    /* run a Linux shell on the slave side, as a terminal emulator would */
    int pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        setsid();
        ioctl(s, TIOCSCTTY, 0);
        dup2(s, 0); dup2(s, 1); dup2(s, 2);
        close(m);
        char *argv[] = {"sh", "-c", "stty size; echo done-$((6*7))", NULL};
        char *envp[] = {"PATH=/usr/bin:/bin", NULL};
        execve("/bin/sh", argv, envp);
        _exit(127);
    }
    close(s);
    char out[512];
    size_t len = 0;
    while (len < sizeof out - 1) {
        ssize_t n = read(m, out + len, sizeof out - 1 - len);
        if (n <= 0) break;
        len += (size_t)n;
        out[len] = 0;
        if (strstr(out, "done-42")) break;
    }
    out[len] = 0;
    CHECK(strstr(out, "40 132") != NULL);
    CHECK(strstr(out, "done-42") != NULL);
    int st;
    CHECK(waitpid(pid, &st, 0) == pid && st == 0);
    puts("pty ok");
    return 0;
}
