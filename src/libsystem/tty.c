/* Terminals: Darwin termios layout, ioctl request codes, pseudo-terminals. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pty.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <linux/sockios.h>
#include <termios.h>
#include <unistd.h>
#include <utmp.h>

#include "darwin_abi.h"
#include "dx.h"

struct d_termios {
    unsigned long c_iflag, c_oflag, c_cflag, c_lflag;
    unsigned char c_cc[20];
    unsigned long c_ispeed, c_ospeed;
};
_Static_assert(sizeof(struct d_termios) == 72, "Darwin termios is 72 bytes");

struct flagmap {
    unsigned long d;
    tcflag_t h;
};
static const struct flagmap iflags[] = {
    {0x1, IGNBRK}, {0x2, BRKINT}, {0x4, IGNPAR}, {0x8, PARMRK}, {0x10, INPCK}, {0x20, ISTRIP},
    {0x40, INLCR}, {0x80, IGNCR}, {0x100, ICRNL}, {0x200, IXON}, {0x400, IXOFF}, {0x800, IXANY},
    {0x2000, IMAXBEL}, {0x4000, IUTF8}, {0, 0}};
static const struct flagmap oflags[] = {
    {0x1, OPOST}, {0x2, ONLCR}, {0x4, XTABS}, {0x10, OCRNL}, {0x20, ONOCR}, {0x40, ONLRET}, {0, 0}};
static const struct flagmap cflags[] = {
    {0x400, CSTOPB}, {0x800, CREAD}, {0x1000, PARENB}, {0x2000, PARODD}, {0x4000, HUPCL},
    {0x8000, CLOCAL}, {0x30000, CRTSCTS}, {0, 0}};
static const struct flagmap lflags[] = {
    {0x1, ECHOKE}, {0x2, ECHOE}, {0x4, ECHOK}, {0x8, ECHO}, {0x10, ECHONL}, {0x20, ECHOPRT},
    {0x40, ECHOCTL}, {0x80, ISIG}, {0x100, ICANON}, {0x400, IEXTEN}, {0x800, EXTPROC},
    {0x400000, TOSTOP}, {0x800000, FLUSHO}, {0x20000000, PENDIN}, {0x80000000, NOFLSH}, {0, 0}};

static tcflag_t flags_to_host(const struct flagmap *m, unsigned long d) {
    tcflag_t h = 0;
    for (; m->d; m++)
        if ((d & m->d) == m->d) h |= m->h;
    return h;
}
static unsigned long flags_from_host(const struct flagmap *m, tcflag_t h) {
    unsigned long d = 0;
    for (; m->d; m++)
        if ((h & m->h) == m->h && m->h) d |= m->d;
    return d;
}

/* c_cc index: Darwin -> Linux (-1: no equivalent) */
static const int cc_map[20] = {VEOF, VEOL, VEOL2, VERASE, VWERASE, VKILL, VREPRINT, -1,
                               VINTR, VQUIT, VSUSP, -1, VSTART, VSTOP, VLNEXT, VDISCARD,
                               VMIN, VTIME, -1, -1};

static speed_t speed_to_host(unsigned long s) {
    static const struct { unsigned long baud; speed_t code; } t[] = {
        {0, B0}, {50, B50}, {75, B75}, {110, B110}, {134, B134}, {150, B150}, {200, B200},
        {300, B300}, {600, B600}, {1200, B1200}, {1800, B1800}, {2400, B2400}, {4800, B4800},
        {9600, B9600}, {19200, B19200}, {38400, B38400}, {57600, B57600}, {115200, B115200},
        {230400, B230400}};
    for (size_t i = 0; i < sizeof t / sizeof t[0]; i++)
        if (t[i].baud == s) return t[i].code;
    return B38400;
}
static unsigned long speed_from_host(speed_t s) {
    switch (s) {
    case B0: return 0; case B50: return 50; case B75: return 75; case B110: return 110;
    case B134: return 134; case B150: return 150; case B200: return 200; case B300: return 300;
    case B600: return 600; case B1200: return 1200; case B1800: return 1800; case B2400: return 2400;
    case B4800: return 4800; case B9600: return 9600; case B19200: return 19200;
    case B38400: return 38400; case B57600: return 57600; case B115200: return 115200;
    case B230400: return 230400;
    }
    return 38400;
}

static void termios_to_host(const struct d_termios *d, struct termios *h) {
    memset(h, 0, sizeof *h);
    h->c_iflag = flags_to_host(iflags, d->c_iflag);
    h->c_oflag = flags_to_host(oflags, d->c_oflag);
    h->c_cflag = flags_to_host(cflags, d->c_cflag);
    switch (d->c_cflag & 0x300) {
    case 0x000: h->c_cflag |= CS5; break;
    case 0x100: h->c_cflag |= CS6; break;
    case 0x200: h->c_cflag |= CS7; break;
    default: h->c_cflag |= CS8; break;
    }
    h->c_lflag = flags_to_host(lflags, d->c_lflag);
    for (int i = 0; i < 20; i++) {
        if (cc_map[i] < 0) continue;
        /* Darwin disables a control character with 0xff, Linux with 0 */
        unsigned char c = d->c_cc[i];
        if (i != 16 && i != 17 && c == 0xff) c = _POSIX_VDISABLE;
        h->c_cc[cc_map[i]] = c;
    }
    cfsetispeed(h, speed_to_host(d->c_ispeed));
    cfsetospeed(h, speed_to_host(d->c_ospeed));
}

static void termios_from_host(const struct termios *h, struct d_termios *d) {
    memset(d, 0, sizeof *d);
    d->c_iflag = flags_from_host(iflags, h->c_iflag);
    d->c_oflag = flags_from_host(oflags, h->c_oflag);
    d->c_cflag = flags_from_host(cflags, h->c_cflag);
    switch (h->c_cflag & CSIZE) {
    case CS5: break;
    case CS6: d->c_cflag |= 0x100; break;
    case CS7: d->c_cflag |= 0x200; break;
    default: d->c_cflag |= 0x300; break;
    }
    d->c_lflag = flags_from_host(lflags, h->c_lflag);
    memset(d->c_cc, 0xff, sizeof d->c_cc);
    for (int i = 0; i < 20; i++) {
        if (cc_map[i] < 0) continue;
        unsigned char c = h->c_cc[cc_map[i]];
        if (i != 16 && i != 17 && c == _POSIX_VDISABLE) c = 0xff;
        d->c_cc[i] = c;
    }
    d->c_ispeed = speed_from_host(cfgetispeed(h));
    d->c_ospeed = speed_from_host(cfgetospeed(h));
}

static int d_tcgetattr(int fd, struct d_termios *out) {
    struct termios h;
    int r = tcgetattr(fd, &h);
    if (r == 0) termios_from_host(&h, out);
    return DX_RET(r);
}
DX_FN(tcgetattr);
static int d_tcsetattr(int fd, int action, const struct d_termios *in) {
    struct termios h;
    termios_to_host(in, &h);
    /* TCSANOW 0, TCSADRAIN 1, TCSAFLUSH 2 on both; Darwin's TCSASOFT (0x10) is dropped */
    return DX_RET(tcsetattr(fd, action & 3, &h));
}
DX_FN(tcsetattr);
static void d_cfmakeraw(struct d_termios *t) {
    t->c_iflag &= ~(0x1UL | 0x2 | 0x8 | 0x20 | 0x40 | 0x80 | 0x100 | 0x200 | 0x2000);
    t->c_oflag &= ~0x1UL;
    t->c_lflag &= ~(0x8UL | 0x10 | 0x100 | 0x80 | 0x400);
    t->c_cflag = (t->c_cflag & ~(0x300UL | 0x1000)) | 0x300 | 0x800;
    t->c_cc[16] = 1;
    t->c_cc[17] = 0;
}
DX_FN(cfmakeraw);
static unsigned long d_cfgetispeed(const struct d_termios *t) { return t->c_ispeed; }
DX_FN(cfgetispeed);
static unsigned long d_cfgetospeed(const struct d_termios *t) { return t->c_ospeed; }
DX_FN(cfgetospeed);
static int d_cfsetispeed(struct d_termios *t, unsigned long s) { t->c_ispeed = s; return 0; }
DX_FN(cfsetispeed);
static int d_cfsetospeed(struct d_termios *t, unsigned long s) { t->c_ospeed = s; return 0; }
DX_FN(cfsetospeed);
static int d_cfsetspeed(struct d_termios *t, unsigned long s) { t->c_ispeed = t->c_ospeed = s; return 0; }
DX_FN(cfsetspeed);
static int d_tcflush(int fd, int q) {
    /* Darwin: TCIFLUSH 1, TCOFLUSH 2, TCIOFLUSH 3 */
    int h = q == 1 ? TCIFLUSH : q == 2 ? TCOFLUSH : TCIOFLUSH;
    return DX_RET(tcflush(fd, h));
}
DX_FN(tcflush);
static int d_tcdrain(int fd) { return DX_RET(tcdrain(fd)); }
DX_FN(tcdrain);
static int d_tcsendbreak(int fd, int len) { return DX_RET(tcsendbreak(fd, len)); }
DX_FN(tcsendbreak);
static int d_tcgetpgrp(int fd) { return DX_RET(tcgetpgrp(fd)); }
DX_FN(tcgetpgrp);
static int d_tcsetpgrp(int fd, int pgrp) { return DX_RET(tcsetpgrp(fd, pgrp)); }
DX_FN(tcsetpgrp);
static char *d_ttyname(int fd) {
    char *r = ttyname(fd);
    if (!r) dx_set_errno(dx_errno_to_darwin(errno));
    return r;
}
DX_FN(ttyname);
static int d_ttyname_r(int fd, char *buf, size_t n) { return dx_errno_to_darwin(ttyname_r(fd, buf, n)); }
DX_FN(ttyname_r);
static char *d_ctermid(char *buf) { return ctermid(buf); }
DX_FN(ctermid);

/* ---- pseudo-terminals ----------------------------------------------------- */

static int d_posix_openpt(int flags) { return DX_RET(posix_openpt(dx_open_flags_to_host(flags))); }
DX_FN(posix_openpt);
static int d_grantpt(int fd) { return DX_RET(grantpt(fd)); }
DX_FN(grantpt);
static int d_unlockpt(int fd) { return DX_RET(unlockpt(fd)); }
DX_FN(unlockpt);
static char *d_ptsname(int fd) {
    char *r = ptsname(fd);
    if (!r) dx_set_errno(dx_errno_to_darwin(errno));
    return r;
}
DX_FN(ptsname);
static int d_ptsname_r(int fd, char *buf, size_t n) {
    int r = ptsname_r(fd, buf, n);
    if (r) { dx_set_errno(dx_errno_to_darwin(r)); return -1; }
    return 0;
}
DX_FN(ptsname_r);

static int d_openpty(int *master, int *slave, char *name, const struct d_termios *t, const struct winsize *ws) {
    struct termios h;
    if (t) termios_to_host(t, &h);
    return DX_RET(openpty(master, slave, name, t ? &h : NULL, ws));
}
DX_FN(openpty);
static int d_forkpty(int *master, char *name, const struct d_termios *t, const struct winsize *ws) {
    struct termios h;
    if (t) termios_to_host(t, &h);
    return DX_RET(forkpty(master, name, t ? &h : NULL, ws));
}
DX_FN(forkpty);
static int d_login_tty(int fd) { return DX_RET(login_tty(fd)); }
DX_FN(login_tty);

/* ---- ioctl ---------------------------------------------------------------- */

#define D_TIOCGETA 0x40487413UL
#define D_TIOCSETA 0x80487414UL
#define D_TIOCSETAW 0x80487415UL
#define D_TIOCSETAF 0x80487416UL
#define D_TIOCGWINSZ 0x40087468UL
#define D_TIOCSWINSZ 0x80087467UL
#define D_TIOCSCTTY 0x20007461UL
#define D_TIOCNOTTY 0x20007471UL
#define D_TIOCGPGRP 0x40047477UL
#define D_TIOCSPGRP 0x80047476UL
#define D_TIOCOUTQ 0x40047473UL
#define D_TIOCEXCL 0x2000740dUL
#define D_TIOCNXCL 0x2000740eUL
#define D_TIOCPTYGRANT 0x20007454UL
#define D_TIOCPTYGNAME 0x40807453UL
#define D_TIOCPTYUNLK 0x20007452UL
#define D_TIOCSTI 0x80017472UL
#define D_TIOCGETD 0x4004741aUL
#define D_TIOCSETD 0x8004741bUL
#define D_TIOCFLUSH 0x80047410UL
#define D_TIOCDRAIN 0x2000745eUL
#define D_TIOCMGET 0x4004746aUL
#define D_TIOCSBRK 0x2000747bUL
#define D_TIOCCBRK 0x2000747aUL
#define D_FIONREAD 0x4004667fUL
#define D_FIONBIO 0x8004667eUL
#define D_FIOASYNC 0x8004667dUL
#define D_FIOCLEX 0x20006601UL
#define D_FIONCLEX 0x20006602UL
#define D_SIOCATMARK 0x40047307UL

int dx_net_ioctl(int fd, unsigned long req, void *arg, int *result) __attribute__((weak));

static int d_ioctl(int fd, unsigned long req, void *arg) {
    req &= 0xffffffffUL;
    switch (req) {
    case D_TIOCGETA: return d_tcgetattr(fd, arg);
    case D_TIOCSETA: return d_tcsetattr(fd, 0, arg);
    case D_TIOCSETAW: return d_tcsetattr(fd, 1, arg);
    case D_TIOCSETAF: return d_tcsetattr(fd, 2, arg);
    case D_TIOCGWINSZ: return DX_RET(ioctl(fd, TIOCGWINSZ, arg));
    case D_TIOCSWINSZ: return DX_RET(ioctl(fd, TIOCSWINSZ, arg));
    case D_TIOCSCTTY: return DX_RET(ioctl(fd, TIOCSCTTY, 0));
    case D_TIOCNOTTY: return DX_RET(ioctl(fd, TIOCNOTTY, 0));
    case D_TIOCGPGRP: return DX_RET(ioctl(fd, TIOCGPGRP, arg));
    case D_TIOCSPGRP: return DX_RET(ioctl(fd, TIOCSPGRP, arg));
    case D_TIOCOUTQ: return DX_RET(ioctl(fd, TIOCOUTQ, arg));
    case D_TIOCEXCL: return DX_RET(ioctl(fd, TIOCEXCL, 0));
    case D_TIOCNXCL: return DX_RET(ioctl(fd, TIOCNXCL, 0));
    case D_TIOCSTI: return DX_RET(ioctl(fd, TIOCSTI, arg));
    case D_TIOCGETD: return DX_RET(ioctl(fd, TIOCGETD, arg));
    case D_TIOCSETD: return DX_RET(ioctl(fd, TIOCSETD, arg));
    case D_TIOCMGET: return DX_RET(ioctl(fd, TIOCMGET, arg));
    case D_TIOCSBRK: return DX_RET(ioctl(fd, TIOCSBRK, 0));
    case D_TIOCCBRK: return DX_RET(ioctl(fd, TIOCCBRK, 0));
    case D_TIOCDRAIN: return DX_RET(tcdrain(fd));
    case D_TIOCFLUSH: return DX_RET(tcflush(fd, TCIOFLUSH));
    case D_TIOCPTYGRANT: return DX_RET(grantpt(fd));
    case D_TIOCPTYUNLK: return DX_RET(unlockpt(fd));
    case D_TIOCPTYGNAME: {
        int r = ptsname_r(fd, arg, 128);
        if (r) { dx_set_errno(dx_errno_to_darwin(r)); return -1; }
        return 0;
    }
    case D_FIONREAD: return DX_RET(ioctl(fd, FIONREAD, arg));
    case D_FIONBIO: return DX_RET(ioctl(fd, FIONBIO, arg));
    case D_FIOASYNC: return DX_RET(ioctl(fd, FIOASYNC, arg));
    case D_FIOCLEX: return DX_RET(ioctl(fd, FIOCLEX, 0));
    case D_FIONCLEX: return DX_RET(ioctl(fd, FIONCLEX, 0));
    case D_SIOCATMARK: return DX_RET(ioctl(fd, SIOCATMARK, arg));
    }
    if (dx_net_ioctl) {
        int result;
        if (dx_net_ioctl(fd, req, arg, &result)) return result;
    }
    dx_log(1, "ioctl: unsupported Darwin request 0x%lx on fd %d", req, fd);
    dx_set_errno(25); /* ENOTTY */
    return -1;
}
DX_FN(ioctl);
