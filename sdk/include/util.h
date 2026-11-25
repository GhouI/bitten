/* bitten SDK: <util.h>, pseudo-terminal helpers. */
#ifndef BITTEN_UTIL_H
#define BITTEN_UTIL_H
#include <termios.h>
#include <sys/ioctl.h>
__BEGIN_DECLS
int openpty(int *, int *, char *, struct termios *, struct winsize *);
pid_t forkpty(int *, char *, struct termios *, struct winsize *);
int login_tty(int);
__END_DECLS
#endif
