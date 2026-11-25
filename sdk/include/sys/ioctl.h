/* bitten SDK: <sys/ioctl.h> and the terminal requests of <sys/ttycom.h>. */
#ifndef BITTEN_SYS_IOCTL_H
#define BITTEN_SYS_IOCTL_H
#include <sys/_types.h>

/* Request encoding: direction, parameter length, group, number. */
#define IOCPARM_MASK 0x1fff
#define IOC_VOID 0x20000000UL
#define IOC_OUT 0x40000000UL
#define IOC_IN 0x80000000UL
#define IOC_INOUT (IOC_IN | IOC_OUT)
#define _IOC(inout, group, num, len) \
    ((unsigned long)((inout) | (((len) & IOCPARM_MASK) << 16) | ((group) << 8) | (num)))
#define _IO(g, n) _IOC(IOC_VOID, (g), (n), 0)
#define _IOR(g, n, t) _IOC(IOC_OUT, (g), (n), sizeof(t))
#define _IOW(g, n, t) _IOC(IOC_IN, (g), (n), sizeof(t))
#define _IOWR(g, n, t) _IOC(IOC_INOUT, (g), (n), sizeof(t))

struct winsize {
    unsigned short ws_row;
    unsigned short ws_col;
    unsigned short ws_xpixel;
    unsigned short ws_ypixel;
};

/* The values are spelled out so that Swift imports them as constants. */
#define TIOCEXCL 0x2000740dUL
#define TIOCNXCL 0x2000740eUL
#define TIOCSCTTY 0x20007461UL
#define TIOCNOTTY 0x20007471UL
#define TIOCPTYGRANT 0x20007454UL
#define TIOCPTYUNLK 0x20007452UL
#define TIOCPTYGNAME 0x40807453UL
#define TIOCGWINSZ 0x40087468UL
#define TIOCSWINSZ 0x80087467UL
#define TIOCGPGRP 0x40047477UL
#define TIOCSPGRP 0x80047476UL
#define TIOCOUTQ 0x40047473UL
#define TIOCSTI 0x80017472UL
#define TIOCGETA 0x40487413UL
#define TIOCSETA 0x80487414UL
#define TIOCSETAW 0x80487415UL
#define TIOCSETAF 0x80487416UL
#define FIOCLEX 0x20006601UL
#define FIONCLEX 0x20006602UL
#define FIONREAD 0x4004667fUL
#define FIONBIO 0x8004667eUL
#define FIOASYNC 0x8004667dUL

__BEGIN_DECLS
int ioctl(int, unsigned long, ...);

/* Fixed-argument forms for Swift; the Darwin overlay wraps them. */
static inline int __bitten_ioctl(int fd, unsigned long request) { return ioctl(fd, request); }
static inline int __bitten_ioctl_int(int fd, unsigned long request, int value) {
    return ioctl(fd, request, value);
}
static inline int __bitten_ioctl_ptr(int fd, unsigned long request, void *ptr) {
    return ioctl(fd, request, ptr);
}
__END_DECLS
#endif
