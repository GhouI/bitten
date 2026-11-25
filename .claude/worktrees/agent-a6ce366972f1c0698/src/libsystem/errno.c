/* errno and signal number translation between Linux and Darwin. */
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <string.h>

#include "dx.h"

/* Darwin errno values, indexed by name. 1..34 are shared with Linux. */
enum {
    D_EDEADLK = 11, D_EAGAIN = 35, D_EINPROGRESS = 36, D_EALREADY = 37, D_ENOTSOCK = 38,
    D_EDESTADDRREQ = 39, D_EMSGSIZE = 40, D_EPROTOTYPE = 41, D_ENOPROTOOPT = 42,
    D_EPROTONOSUPPORT = 43, D_ESOCKTNOSUPPORT = 44, D_ENOTSUP = 45, D_EPFNOSUPPORT = 46,
    D_EAFNOSUPPORT = 47, D_EADDRINUSE = 48, D_EADDRNOTAVAIL = 49, D_ENETDOWN = 50,
    D_ENETUNREACH = 51, D_ENETRESET = 52, D_ECONNABORTED = 53, D_ECONNRESET = 54,
    D_ENOBUFS = 55, D_EISCONN = 56, D_ENOTCONN = 57, D_ESHUTDOWN = 58, D_ETOOMANYREFS = 59,
    D_ETIMEDOUT = 60, D_ECONNREFUSED = 61, D_ELOOP = 62, D_ENAMETOOLONG = 63, D_EHOSTDOWN = 64,
    D_EHOSTUNREACH = 65, D_ENOTEMPTY = 66, D_EUSERS = 68, D_EDQUOT = 69, D_ESTALE = 70,
    D_EREMOTE = 71, D_ENOLCK = 77, D_ENOSYS = 78, D_EOVERFLOW = 84, D_ECANCELED = 89,
    D_EIDRM = 90, D_ENOMSG = 91, D_EILSEQ = 92, D_ENOATTR = 93, D_EBADMSG = 94,
    D_EMULTIHOP = 95, D_ENODATA = 96, D_ENOLINK = 97, D_ENOSR = 98, D_ENOSTR = 99,
    D_EPROTO = 100, D_ETIME = 101, D_EOPNOTSUPP = 102, D_ENOTRECOVERABLE = 104,
    D_EOWNERDEAD = 105, D_EIO = 5,
};

static const struct {
    int host, darwin;
} errno_map[] = {
    {EDEADLK, D_EDEADLK}, {EAGAIN, D_EAGAIN}, {EINPROGRESS, D_EINPROGRESS},
    {EALREADY, D_EALREADY}, {ENOTSOCK, D_ENOTSOCK}, {EDESTADDRREQ, D_EDESTADDRREQ},
    {EMSGSIZE, D_EMSGSIZE}, {EPROTOTYPE, D_EPROTOTYPE}, {ENOPROTOOPT, D_ENOPROTOOPT},
    {EPROTONOSUPPORT, D_EPROTONOSUPPORT}, {ESOCKTNOSUPPORT, D_ESOCKTNOSUPPORT},
    {EOPNOTSUPP, D_ENOTSUP}, {EPFNOSUPPORT, D_EPFNOSUPPORT}, {EAFNOSUPPORT, D_EAFNOSUPPORT},
    {EADDRINUSE, D_EADDRINUSE}, {EADDRNOTAVAIL, D_EADDRNOTAVAIL}, {ENETDOWN, D_ENETDOWN},
    {ENETUNREACH, D_ENETUNREACH}, {ENETRESET, D_ENETRESET}, {ECONNABORTED, D_ECONNABORTED},
    {ECONNRESET, D_ECONNRESET}, {ENOBUFS, D_ENOBUFS}, {EISCONN, D_EISCONN},
    {ENOTCONN, D_ENOTCONN}, {ESHUTDOWN, D_ESHUTDOWN}, {ETOOMANYREFS, D_ETOOMANYREFS},
    {ETIMEDOUT, D_ETIMEDOUT}, {ECONNREFUSED, D_ECONNREFUSED}, {ELOOP, D_ELOOP},
    {ENAMETOOLONG, D_ENAMETOOLONG}, {EHOSTDOWN, D_EHOSTDOWN}, {EHOSTUNREACH, D_EHOSTUNREACH},
    {ENOTEMPTY, D_ENOTEMPTY}, {EUSERS, D_EUSERS}, {EDQUOT, D_EDQUOT}, {ESTALE, D_ESTALE},
    {EREMOTE, D_EREMOTE}, {ENOLCK, D_ENOLCK}, {ENOSYS, D_ENOSYS}, {EOVERFLOW, D_EOVERFLOW},
    {ECANCELED, D_ECANCELED}, {EIDRM, D_EIDRM}, {ENOMSG, D_ENOMSG}, {EILSEQ, D_EILSEQ},
    {ENODATA, D_ENOATTR}, {EBADMSG, D_EBADMSG}, {EMULTIHOP, D_EMULTIHOP},
    {ENOLINK, D_ENOLINK}, {ENOSR, D_ENOSR}, {ENOSTR, D_ENOSTR}, {EPROTO, D_EPROTO},
    {ETIME, D_ETIME}, {ENOTRECOVERABLE, D_ENOTRECOVERABLE}, {EOWNERDEAD, D_EOWNERDEAD},
};

int dx_errno_to_darwin(int e) {
    if (e <= 0) return e;
    if (e <= 34 && e != EDEADLK && e != EAGAIN) return e;
    for (size_t i = 0; i < sizeof errno_map / sizeof errno_map[0]; i++)
        if (errno_map[i].host == e) return errno_map[i].darwin;
    return D_EIO; /* Linux-only error: no Darwin spelling */
}

int dx_errno_from_darwin(int d) {
    if (d <= 0) return d;
    if (d <= 34 && d != D_EDEADLK) return d;
    for (size_t i = 0; i < sizeof errno_map / sizeof errno_map[0]; i++)
        if (errno_map[i].darwin == d) return errno_map[i].host;
    if (d == D_EOPNOTSUPP) return EOPNOTSUPP;
    if (d == D_ENODATA) return ENODATA;
    return EIO;
}

void dx_set_errno(int darwin_errno) { dx_thread_self()->d_errno = darwin_errno; }

static int *d___error(void) { return &dx_thread_self()->d_errno; }
DX_FN(__error);

/* strerror takes a Darwin errno. */
static char *d_strerror(int e) { return strerror(dx_errno_from_darwin(e)); }
DX_FN(strerror);
static int d_strerror_r(int e, char *buf, size_t len) {
    const char *s = strerror(dx_errno_from_darwin(e));
    if (!len) return 34;
    strncpy(buf, s, len - 1);
    buf[len - 1] = 0;
    return 0;
}
DX_FN(strerror_r);

/* ---- signals ----------------------------------------------------------
 * Darwin: URG16 STOP17 TSTP18 CONT19 CHLD20 IO23 INFO29 USR1=30 USR2=31
 * EMT7 BUS10 SYS12. The mapping below is a bijection on 1..31 so signal
 * sets translate without loss; EMT and INFO borrow STKFLT and PWR. */
static const unsigned char sig_d2h[32] = {
    0, SIGHUP, SIGINT, SIGQUIT, SIGILL, SIGTRAP, SIGABRT, SIGSTKFLT, SIGFPE, SIGKILL,
    SIGBUS, SIGSEGV, SIGSYS, SIGPIPE, SIGALRM, SIGTERM, SIGURG, SIGSTOP, SIGTSTP, SIGCONT,
    SIGCHLD, SIGTTIN, SIGTTOU, SIGIO, SIGXCPU, SIGXFSZ, SIGVTALRM, SIGPROF, SIGWINCH,
    SIGPWR, SIGUSR1, SIGUSR2,
};
static unsigned char sig_h2d[32];

__attribute__((constructor)) static void sig_init(void) {
    for (int d = 1; d < 32; d++) sig_h2d[sig_d2h[d]] = d;
}

int dx_sig_to_host(int d) { return (d > 0 && d < 32) ? sig_d2h[d] : d; }
int dx_sig_from_host(int h) { return (h > 0 && h < 32) ? sig_h2d[h] : h; }
