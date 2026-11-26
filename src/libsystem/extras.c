/* Odds and ends of libSystem: interface addresses in Darwin's layout
 * (with AF_LINK entries carrying the hardware address), waitid with
 * Darwin's siginfo, renamex_np, mkpath_np, memset_s, errx, the main
 * thread's QoS class, notification registration (no notifications are
 * posted here, see notify_post in sys.c), and two math entry points. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <linux/if_packet.h>
#include <math.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include "darwin_abi.h"
#include "dx.h"

int dx_sig_from_host(int h);

/* ---- getifaddrs ------------------------------------------------------------ */

struct d_ifaddrs {
    struct d_ifaddrs *next;
    char *name;
    unsigned int flags;
    void *addr, *netmask, *dstaddr;
    void *data;
};

/* Darwin's IFF_ bits (UP, BROADCAST, DEBUG, LOOPBACK, POINTOPOINT and
 * RUNNING agree with Linux; the rest move). */
static unsigned flags_from_host(unsigned h) {
    unsigned d = h & (IFF_UP | IFF_BROADCAST | IFF_DEBUG | IFF_LOOPBACK | IFF_POINTOPOINT | IFF_RUNNING);
    if (h & IFF_NOARP) d |= 0x80;
    if (h & IFF_PROMISC) d |= 0x100;
    if (h & IFF_ALLMULTI) d |= 0x200;
    if (h & IFF_MULTICAST) d |= 0x8000;
    return d;
}

/* struct sockaddr_dl: len, family (AF_LINK), index, type, name and
 * address lengths, then the name followed by the address. */
static void *link_addr(const char *name, const struct sockaddr_ll *ll) {
    size_t nlen = strlen(name), alen = ll ? ll->sll_halen : 0;
    if (nlen > 64) nlen = 64;
    size_t len = 8 + nlen + alen;
    if (len < 20) len = 20;
    uint8_t *d = calloc(1, len);
    if (!d) return NULL;
    d[0] = (uint8_t)len;
    d[1] = 18;                                          /* AF_LINK */
    uint16_t index = (uint16_t)(ll ? (unsigned)ll->sll_ifindex : if_nametoindex(name));
    memcpy(d + 2, &index, 2);
    d[4] = ll && ll->sll_hatype == 772 ? 24 : 6;        /* IFT_LOOP or IFT_ETHER */
    d[5] = (uint8_t)nlen;
    d[6] = (uint8_t)alen;
    memcpy(d + 8, name, nlen);
    if (alen) memcpy(d + 8 + nlen, ll->sll_addr, alen);
    return d;
}

static void *addr_copy(const struct sockaddr *h) {
    if (!h) return NULL;
    if (h->sa_family != AF_INET && h->sa_family != AF_INET6) return NULL;
    uint8_t *d = calloc(1, 128);
    uint32_t len = 128;
    if (!d) return NULL;
    dx_sockaddr_from_host(h, h->sa_family == AF_INET ? sizeof(struct sockaddr_in) : sizeof(struct sockaddr_in6), d, &len);
    return d;
}

static void d_freeifaddrs(struct d_ifaddrs *list) {
    while (list) {
        struct d_ifaddrs *next = list->next;
        free(list->name);
        free(list->addr);
        free(list->netmask);
        free(list->dstaddr);
        free(list);
        list = next;
    }
}
DX_FN(freeifaddrs);

static int d_getifaddrs(struct d_ifaddrs **out) {
    struct ifaddrs *host;
    if (getifaddrs(&host) < 0) return DX_RET(-1);
    struct d_ifaddrs *head = NULL, **tail = &head;
    for (struct ifaddrs *h = host; h; h = h->ifa_next) {
        bool packet = h->ifa_addr && h->ifa_addr->sa_family == AF_PACKET;
        if (h->ifa_addr && !packet && h->ifa_addr->sa_family != AF_INET && h->ifa_addr->sa_family != AF_INET6) continue;
        struct d_ifaddrs *d = calloc(1, sizeof *d);
        if (!d) break;
        d->name = strdup(h->ifa_name ? h->ifa_name : "");
        d->flags = flags_from_host(h->ifa_flags);
        if (packet) {
            d->addr = link_addr(d->name, (const struct sockaddr_ll *)h->ifa_addr);
        } else {
            d->addr = addr_copy(h->ifa_addr);
            d->netmask = addr_copy(h->ifa_netmask);
            d->dstaddr = addr_copy(h->ifa_ifu.ifu_dstaddr);
        }
        *tail = d;
        tail = &d->next;
    }
    freeifaddrs(host);
    *out = head;
    return 0;
}
DX_FN(getifaddrs);

/* ---- waitid ------------------------------------------------------------------ */

struct d_siginfo {
    int signo, err, code;
    int32_t pid;
    uint32_t uid;
    int status;
    void *addr;
    void *value;
    long band;
    unsigned long pad[7];
};

static int d_waitid(int idtype, int id, struct d_siginfo *info, int options) {
    int h_idtype = idtype == 0 ? P_ALL : idtype == 1 ? P_PID : idtype == 2 ? P_PGID : -1;
    if (h_idtype < 0) { dx_set_errno(22); return -1; }
    int h_opts = 0;
    if (options & 0x01) h_opts |= WNOHANG;
    if (options & 0x04) h_opts |= WEXITED;
    if (options & 0x08) h_opts |= WSTOPPED;
    if (options & 0x10) h_opts |= WCONTINUED;
    if (options & 0x20) h_opts |= WNOWAIT;
    siginfo_t si;
    memset(&si, 0, sizeof si);
    int r = waitid((idtype_t)h_idtype, (id_t)id, &si, h_opts);
    if (r < 0) return DX_RET(r);
    if (info) {
        memset(info, 0, sizeof *info);
        if (si.si_pid) {
            info->signo = 20;                             /* SIGCHLD */
            info->code = si.si_code;
            info->pid = si.si_pid;
            info->uid = si.si_uid;
            info->status = si.si_code == CLD_EXITED ? si.si_status : dx_sig_from_host(si.si_status);
        }
    }
    return 0;
}
DX_FN(waitid);

/* ---- files ---------------------------------------------------------------------- */

/* RENAME_SWAP (2) and RENAME_EXCL (4) are Linux's RENAME_EXCHANGE and
 * RENAME_NOREPLACE. */
static int d_renamex_np(const char *from, const char *to, unsigned flags) {
    char a[4096], b[4096];
    const char *pa = dx_path(from, a, sizeof a), *pb = dx_path(to, b, sizeof b);
    unsigned h = 0;
    if (flags & 2) h |= 2;
    if (flags & 4) h |= 1;
    if (flags & ~6u) { dx_set_errno(22); return -1; }
    return DX_RET((int)syscall(SYS_renameat2, AT_FDCWD, pa, AT_FDCWD, pb, h));
}
DX_FN(renamex_np);
static int d_renameatx_np(int fromfd, const char *from, int tofd, const char *to, unsigned flags) {
    if (fromfd == -2) fromfd = AT_FDCWD;                  /* Darwin's AT_FDCWD */
    if (tofd == -2) tofd = AT_FDCWD;
    char a[4096], b[4096];
    const char *pa = dx_path(from, a, sizeof a), *pb = dx_path(to, b, sizeof b);
    unsigned h = (flags & 2 ? 2u : 0u) | (flags & 4 ? 1u : 0u);
    return DX_RET((int)syscall(SYS_renameat2, fromfd, pa, tofd, pb, h));
}
DX_FN(renameatx_np);

/* mkdir -p. Returns 0, or an errno (Darwin's) rather than setting it;
 * EEXIST when the whole path already exists as a directory. */
static int d_mkpath_np(const char *path, unsigned short mode) {
    if (!path || !*path) return 2;                        /* ENOENT */
    char buf[4096];
    const char *mapped = dx_path(path, buf, sizeof buf);
    char p[4096];
    snprintf(p, sizeof p, "%s", mapped);
    struct stat st;
    if (!stat(p, &st)) return S_ISDIR(st.st_mode) ? 17 : 20;   /* EEXIST, ENOTDIR */
    for (char *s = p + 1; *s; s++) {
        if (*s != '/') continue;
        *s = 0;
        if (mkdir(p, 0777) < 0 && errno != EEXIST) return dx_errno_to_darwin(errno);
        *s = '/';
    }
    if (mkdir(p, mode) < 0 && errno != EEXIST) return dx_errno_to_darwin(errno);
    return 0;
}
DX_FN(mkpath_np);
static int d_mkpathat_np(int dfd, const char *path, unsigned short mode) { return d_mkpath_np(path, mode); }
DX_FN(mkpathat_np);

/* ---- memory, errors, threads ---------------------------------------------------- */

static int d_memset_s(void *s, size_t smax, int c, size_t n) {
    if (!s) return 22;                                    /* EINVAL */
    int err = 0;
    if (n > smax) { n = smax; err = 84; }                 /* EOVERFLOW */
    volatile unsigned char *p = s;
    while (n--) *p++ = (unsigned char)c;
    return err;
}
DX_FN(memset_s);

static void d_verrx(int eval, const char *fmt, va_list ap) {
    fprintf(stderr, "%s: ", program_invocation_short_name);
    if (fmt) vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    exit(eval);
}
DX_FN(verrx);
static void d_errx(int eval, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    d_verrx(eval, fmt, ap);
}
DX_FN(errx);
static void d_warnx(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "%s: ", program_invocation_short_name);
    if (fmt) vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}
DX_FN(warnx);

/* The main thread runs at user-interactive QoS on macOS. */
static unsigned d_qos_class_main(void) { return 0x21; }
DX_FN(qos_class_main);

/* No notification is ever posted to this process (notify_post goes
 * nowhere), so the handler is kept and never called. */
static int next_token = 100;
static uint32_t d_notify_register_dispatch(const char *name, int *token, void *queue, void *handler) {
    if (!name || !token) return 1000000;                  /* NOTIFY_STATUS_FAILED */
    *token = __atomic_fetch_add(&next_token, 1, __ATOMIC_RELAXED);
    return 0;
}
DX_FN(notify_register_dispatch);

/* ---- math ------------------------------------------------------------------------ */

/* Darwin's FP_ classes: NAN 1, INFINITE 2, ZERO 3, NORMAL 4, SUBNORMAL 5. */
static int d___fpclassifyd(double x) {
    switch (fpclassify(x)) {
    case FP_NAN: return 1;
    case FP_INFINITE: return 2;
    case FP_ZERO: return 3;
    case FP_SUBNORMAL: return 5;
    default: return 4;
    }
}
DX_FN(__fpclassifyd);
static int d___fpclassifyf(float x) { return d___fpclassifyd((double)x); }
DX_FN(__fpclassifyf);
static double d___exp10(double x) { return exp10(x); }
DX_FN(__exp10);
static float d___exp10f(float x) { return exp10f(x); }
DX_FN(__exp10f);
