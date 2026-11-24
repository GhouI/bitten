/* Sockets: BSD sockaddr (length byte, AF numbers), option numbers, msghdr
 * and control messages, getaddrinfo. */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <unistd.h>

#include "darwin_abi.h"
#include "dx.h"

#define D_AF_UNIX 1
#define D_AF_INET 2
#define D_AF_INET6 30

static int af_to_host(int d) {
    switch (d) {
    case 0: return AF_UNSPEC;
    case D_AF_UNIX: return AF_UNIX;
    case D_AF_INET: return AF_INET;
    case D_AF_INET6: return AF_INET6;
    }
    return -1;
}
static int af_from_host(int h) {
    switch (h) {
    case AF_UNSPEC: return 0;
    case AF_UNIX: return D_AF_UNIX;
    case AF_INET: return D_AF_INET;
    case AF_INET6: return D_AF_INET6;
    }
    return 0;
}

/* Darwin sockaddr: uint8 sa_len; uint8 sa_family; then the same payload. */
int dx_sockaddr_to_host(const void *dv, uint32_t dlen, struct sockaddr *out) {
    const uint8_t *d = dv;
    if (!d || dlen < 2) {
        errno = EINVAL;
        return -1;
    }
    int fam = af_to_host(d[1]);
    memset(out, 0, 128);
    switch (fam) {
    case AF_INET: {
        if (dlen < 16) { errno = EINVAL; return -1; }
        struct sockaddr_in *s = (void *)out;
        s->sin_family = AF_INET;
        memcpy(&s->sin_port, d + 2, 2);
        memcpy(&s->sin_addr, d + 4, 4);
        return sizeof *s;
    }
    case AF_INET6: {
        if (dlen < 28) { errno = EINVAL; return -1; }
        struct sockaddr_in6 *s = (void *)out;
        s->sin6_family = AF_INET6;
        memcpy(&s->sin6_port, d + 2, 2);
        memcpy(&s->sin6_flowinfo, d + 4, 4);
        memcpy(&s->sin6_addr, d + 8, 16);
        memcpy(&s->sin6_scope_id, d + 24, 4);
        return sizeof *s;
    }
    case AF_UNIX: {
        struct sockaddr_un *s = (void *)out;
        s->sun_family = AF_UNIX;
        size_t n = dlen - 2;
        if (n > sizeof s->sun_path - 1) n = sizeof s->sun_path - 1;
        memcpy(s->sun_path, d + 2, n);
        s->sun_path[n] = 0;
        size_t plen = strnlen(s->sun_path, n);
        char pbuf[4096];
        const char *mapped = dx_path(s->sun_path, pbuf, sizeof pbuf);
        if (mapped != s->sun_path && strlen(mapped) < sizeof s->sun_path) {
            strcpy(s->sun_path, mapped);
            plen = strlen(mapped);
        }
        return (int)(offsetof(struct sockaddr_un, sun_path) + plen + 1);
    }
    case AF_UNSPEC: {
        out->sa_family = AF_UNSPEC;
        return sizeof(struct sockaddr);
    }
    }
    errno = EAFNOSUPPORT;
    return -1;
}

void dx_sockaddr_from_host(const struct sockaddr *h, uint32_t hlen, void *dv, uint32_t *dlen) {
    uint8_t tmp[128];
    uint32_t full = 0;
    memset(tmp, 0, sizeof tmp);
    switch (h->sa_family) {
    case AF_INET: {
        const struct sockaddr_in *s = (const void *)h;
        full = 16;
        memcpy(tmp + 2, &s->sin_port, 2);
        memcpy(tmp + 4, &s->sin_addr, 4);
        break;
    }
    case AF_INET6: {
        const struct sockaddr_in6 *s = (const void *)h;
        full = 28;
        memcpy(tmp + 2, &s->sin6_port, 2);
        memcpy(tmp + 4, &s->sin6_flowinfo, 4);
        memcpy(tmp + 8, &s->sin6_addr, 16);
        memcpy(tmp + 24, &s->sin6_scope_id, 4);
        break;
    }
    case AF_UNIX: {
        const struct sockaddr_un *s = (const void *)h;
        size_t plen = hlen > offsetof(struct sockaddr_un, sun_path)
                          ? strnlen(s->sun_path, hlen - offsetof(struct sockaddr_un, sun_path))
                          : 0;
        if (plen > 103) plen = 103;
        memcpy(tmp + 2, s->sun_path, plen);
        full = (uint32_t)(2 + plen + 1);
        if (full < 16) full = 16;
        break;
    }
    default:
        full = 16;
        break;
    }
    tmp[0] = (uint8_t)full;
    tmp[1] = (uint8_t)af_from_host(h->sa_family);
    if (dv && dlen) {
        uint32_t n = *dlen < full ? *dlen : full;
        memcpy(dv, tmp, n);
    }
    if (dlen) *dlen = full;
}

/* ---- socket options ------------------------------------------------------- */

#define D_SOL_SOCKET 0xffff

static int sockopt_to_host(int level, int name, int *hlevel, int *hname) {
    if (level == D_SOL_SOCKET) {
        *hlevel = SOL_SOCKET;
        switch (name) {
        case 0x0001: *hname = SO_DEBUG; return 0;
        case 0x0002: *hname = SO_ACCEPTCONN; return 0;
        case 0x0004: *hname = SO_REUSEADDR; return 0;
        case 0x0008: *hname = SO_KEEPALIVE; return 0;
        case 0x0010: *hname = SO_DONTROUTE; return 0;
        case 0x0020: *hname = SO_BROADCAST; return 0;
        case 0x0080: *hname = SO_LINGER; return 0;
        case 0x0100: *hname = SO_OOBINLINE; return 0;
        case 0x0200: *hname = SO_REUSEPORT; return 0;
        case 0x0400: *hname = SO_TIMESTAMP; return 0;
        case 0x1001: *hname = SO_SNDBUF; return 0;
        case 0x1002: *hname = SO_RCVBUF; return 0;
        case 0x1003: *hname = SO_SNDLOWAT; return 0;
        case 0x1004: *hname = SO_RCVLOWAT; return 0;
        case 0x1005: *hname = SO_SNDTIMEO; return 0;
        case 0x1006: *hname = SO_RCVTIMEO; return 0;
        case 0x1007: *hname = SO_ERROR; return 0;
        case 0x1008: *hname = SO_TYPE; return 0;
        case 0x1022: return 1; /* SO_NOSIGPIPE: handled by the caller */
        case 0x1080: *hname = SO_LINGER; return 0; /* SO_LINGER_SEC */
        }
        return -1;
    }
    if (level == IPPROTO_TCP) {
        *hlevel = IPPROTO_TCP;
        switch (name) {
        case 0x01: *hname = TCP_NODELAY; return 0;
        case 0x02: *hname = TCP_MAXSEG; return 0;
        case 0x10: *hname = TCP_KEEPIDLE; return 0; /* TCP_KEEPALIVE */
        case 0x101: *hname = TCP_KEEPINTVL; return 0;
        case 0x102: *hname = TCP_KEEPCNT; return 0;
        case 0x105: *hname = TCP_FASTOPEN; return 0;
        case 0x201: *hname = TCP_NOTSENT_LOWAT; return 0;
        }
        return -1;
    }
    if (level == IPPROTO_IP) {
        *hlevel = IPPROTO_IP;
        switch (name) {
        case 1: *hname = IP_OPTIONS; return 0;
        case 2: *hname = IP_HDRINCL; return 0;
        case 3: *hname = IP_TOS; return 0;
        case 4: *hname = IP_TTL; return 0;
        case 9: *hname = IP_MULTICAST_IF; return 0;
        case 10: *hname = IP_MULTICAST_TTL; return 0;
        case 11: *hname = IP_MULTICAST_LOOP; return 0;
        case 12: *hname = IP_ADD_MEMBERSHIP; return 0;
        case 13: *hname = IP_DROP_MEMBERSHIP; return 0;
        case 24: *hname = IP_RECVTTL; return 0;
        case 26: *hname = IP_PKTINFO; return 0;
        case 27: *hname = IP_RECVTOS; return 0;
        }
        return -1;
    }
    if (level == IPPROTO_IPV6) {
        *hlevel = IPPROTO_IPV6;
        switch (name) {
        case 4: *hname = IPV6_UNICAST_HOPS; return 0;
        case 9: *hname = IPV6_MULTICAST_IF; return 0;
        case 10: *hname = IPV6_MULTICAST_HOPS; return 0;
        case 11: *hname = IPV6_MULTICAST_LOOP; return 0;
        case 12: *hname = IPV6_JOIN_GROUP; return 0;
        case 13: *hname = IPV6_LEAVE_GROUP; return 0;
        case 27: *hname = IPV6_V6ONLY; return 0;
        case 36: *hname = IPV6_TCLASS; return 0;
        case 35: *hname = IPV6_RECVTCLASS; return 0;
        case 61: *hname = IPV6_RECVPKTINFO; return 0;
        case 46: *hname = IPV6_PKTINFO; return 0;
        }
        return -1;
    }
    if (level == IPPROTO_UDP) {
        *hlevel = IPPROTO_UDP;
        *hname = name;
        return 0;
    }
    return -1;
}

static int d_setsockopt(int fd, int level, int name, const void *val, uint32_t len) {
    int hl, hn;
    int r = sockopt_to_host(level, name, &hl, &hn);
    if (r == 1) return 0; /* SO_NOSIGPIPE: sends use MSG_NOSIGNAL-free writes; SIGPIPE is the caller's */
    if (r < 0) {
        dx_log(1, "setsockopt: unsupported Darwin option level=0x%x name=0x%x", level, name);
        dx_set_errno(42); /* ENOPROTOOPT */
        return -1;
    }
    if (hl == SOL_SOCKET && (hn == SO_SNDTIMEO || hn == SO_RCVTIMEO) && val && len >= sizeof(struct d_timeval)) {
        const struct d_timeval *d = val;
        struct timeval tv = {d->tv_sec, d->tv_usec};
        return DX_RET(setsockopt(fd, hl, hn, &tv, sizeof tv));
    }
    return DX_RET(setsockopt(fd, hl, hn, val, len));
}
DX_FN(setsockopt);

/* SOL_LOCAL (level 0 on a unix socket): peer credentials. */
struct d_xucred {
    uint32_t cr_version;
    uint32_t cr_uid;
    short cr_ngroups;
    uint32_t cr_groups[16];
};

static int local_getsockopt(int fd, int name, void *val, uint32_t *len) {
    struct ucred uc;
    socklen_t ul = sizeof uc;
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &uc, &ul) < 0) return DX_RET(-1);
    switch (name) {
    case 0x001: { /* LOCAL_PEERCRED */
        struct d_xucred x;
        memset(&x, 0, sizeof x);
        x.cr_uid = uc.uid;
        x.cr_ngroups = 1;
        x.cr_groups[0] = uc.gid;
        if (!val || !len || *len < sizeof x) { dx_set_errno(22); return -1; }
        memcpy(val, &x, sizeof x);
        *len = sizeof x;
        return 0;
    }
    case 0x002: /* LOCAL_PEERPID */
    case 0x003: /* LOCAL_PEEREPID */
        if (!val || !len || *len < 4) { dx_set_errno(22); return -1; }
        *(int *)val = uc.pid;
        *len = 4;
        return 0;
    case 0x006: { /* LOCAL_PEERTOKEN: audit token {auid, euid, egid, ruid, rgid, pid, asid, pidversion} */
        uint32_t tok[8] = {uc.uid, uc.uid, uc.gid, uc.uid, uc.gid, (uint32_t)uc.pid, 0, 0};
        if (!val || !len || *len < sizeof tok) { dx_set_errno(22); return -1; }
        memcpy(val, tok, sizeof tok);
        *len = sizeof tok;
        return 0;
    }
    }
    dx_log(1, "getsockopt: unsupported SOL_LOCAL option 0x%x", name);
    dx_set_errno(42);
    return -1;
}

static int is_unix_socket(int fd) {
    int dom = 0;
    socklen_t dl = sizeof dom;
    return getsockopt(fd, SOL_SOCKET, SO_DOMAIN, &dom, &dl) == 0 && dom == AF_UNIX;
}

static int d_getsockopt(int fd, int level, int name, void *val, uint32_t *len) {
    int hl, hn;
    if (level == 0 && is_unix_socket(fd)) return local_getsockopt(fd, name, val, len);
    int r = sockopt_to_host(level, name, &hl, &hn);
    if (r == 1) {
        if (val && len && *len >= 4) { *(int *)val = 0; *len = 4; }
        return 0;
    }
    if (r < 0) {
        dx_log(1, "getsockopt: unsupported Darwin option level=0x%x name=0x%x", level, name);
        dx_set_errno(42);
        return -1;
    }
    socklen_t hlen = len ? *len : 0;
    if (hl == SOL_SOCKET && (hn == SO_SNDTIMEO || hn == SO_RCVTIMEO)) {
        struct timeval tv;
        socklen_t tl = sizeof tv;
        int rr = getsockopt(fd, hl, hn, &tv, &tl);
        if (rr == 0 && val && len && *len >= sizeof(struct d_timeval)) {
            struct d_timeval *d = val;
            d->tv_sec = tv.tv_sec;
            d->tv_usec = (int32_t)tv.tv_usec;
            *len = sizeof *d;
        }
        return DX_RET(rr);
    }
    int rr = getsockopt(fd, hl, hn, val, &hlen);
    if (rr == 0) {
        if (len) *len = hlen;
        if (hl == SOL_SOCKET && hn == SO_ERROR && val && hlen >= 4)
            *(int *)val = dx_errno_to_darwin(*(int *)val);
    }
    return DX_RET(rr);
}
DX_FN(getsockopt);

/* ---- basic calls ---------------------------------------------------------- */

static int d_socket(int domain, int type, int proto) {
    int hd = af_to_host(domain);
    if (hd < 0) {
        dx_log(1, "socket: unsupported Darwin address family %d", domain);
        dx_set_errno(47); /* EAFNOSUPPORT */
        return -1;
    }
    return DX_RET(socket(hd, type, proto));
}
DX_FN(socket);

static int d_socketpair(int domain, int type, int proto, int sv[2]) {
    int hd = af_to_host(domain);
    if (hd < 0) { dx_set_errno(47); return -1; }
    return DX_RET(socketpair(hd, type, proto, sv));
}
DX_FN(socketpair);

static int d_bind(int fd, const void *addr, uint32_t len) {
    struct sockaddr_storage ss;
    int hl = dx_sockaddr_to_host(addr, len, (struct sockaddr *)&ss);
    if (hl < 0) return DX_RET(-1);
    return DX_RET(bind(fd, (struct sockaddr *)&ss, hl));
}
DX_FN(bind);

static int d_connect(int fd, const void *addr, uint32_t len) {
    struct sockaddr_storage ss;
    int hl = dx_sockaddr_to_host(addr, len, (struct sockaddr *)&ss);
    if (hl < 0) return DX_RET(-1);
    return DX_RET(connect(fd, (struct sockaddr *)&ss, hl));
}
DX_FN(connect);
DX_EXPORT("_connect$NOCANCEL", d_connect);

static int d_listen(int fd, int backlog) { return DX_RET(listen(fd, backlog)); }
DX_FN(listen);

static int d_accept(int fd, void *addr, uint32_t *len) {
    struct sockaddr_storage ss;
    socklen_t hl = sizeof ss;
    int r = accept(fd, (struct sockaddr *)&ss, &hl);
    if (r >= 0 && addr && len) dx_sockaddr_from_host((struct sockaddr *)&ss, hl, addr, len);
    return DX_RET(r);
}
DX_FN(accept);
DX_EXPORT("_accept$NOCANCEL", d_accept);

static int d_getsockname(int fd, void *addr, uint32_t *len) {
    struct sockaddr_storage ss;
    socklen_t hl = sizeof ss;
    int r = getsockname(fd, (struct sockaddr *)&ss, &hl);
    if (r == 0) dx_sockaddr_from_host((struct sockaddr *)&ss, hl, addr, len);
    return DX_RET(r);
}
DX_FN(getsockname);

static int d_getpeername(int fd, void *addr, uint32_t *len) {
    struct sockaddr_storage ss;
    socklen_t hl = sizeof ss;
    int r = getpeername(fd, (struct sockaddr *)&ss, &hl);
    if (r == 0) dx_sockaddr_from_host((struct sockaddr *)&ss, hl, addr, len);
    return DX_RET(r);
}
DX_FN(getpeername);

static int d_shutdown(int fd, int how) { return DX_RET(shutdown(fd, how)); }
DX_FN(shutdown);

/* MSG_* flags */
static int msg_flags_to_host(int d) {
    int h = d & 7; /* OOB, PEEK, DONTROUTE */
    if (d & 0x8) h |= MSG_EOR;
    if (d & 0x10) h |= MSG_TRUNC;
    if (d & 0x20) h |= MSG_CTRUNC;
    if (d & 0x40) h |= MSG_WAITALL;
    if (d & 0x80) h |= MSG_DONTWAIT;
    if (d & 0x80000) h |= MSG_NOSIGNAL;
    return h;
}
static int msg_flags_from_host(int h) {
    int d = h & 7;
    if (h & MSG_EOR) d |= 0x8;
    if (h & MSG_TRUNC) d |= 0x10;
    if (h & MSG_CTRUNC) d |= 0x20;
    if (h & MSG_WAITALL) d |= 0x40;
    if (h & MSG_DONTWAIT) d |= 0x80;
    return d;
}

static ssize_t d_sendto(int fd, const void *buf, size_t n, int flags, const void *addr, uint32_t alen) {
    struct sockaddr_storage ss;
    int hl = 0;
    if (addr && alen) {
        hl = dx_sockaddr_to_host(addr, alen, (struct sockaddr *)&ss);
        if (hl < 0) return DX_RET(-1);
    }
    return DX_RET(sendto(fd, buf, n, msg_flags_to_host(flags), hl ? (struct sockaddr *)&ss : NULL, hl));
}
DX_FN(sendto);
DX_EXPORT("_sendto$NOCANCEL", d_sendto);
static ssize_t d_send(int fd, const void *buf, size_t n, int flags) {
    return DX_RET(send(fd, buf, n, msg_flags_to_host(flags)));
}
DX_FN(send);

static ssize_t d_recvfrom(int fd, void *buf, size_t n, int flags, void *addr, uint32_t *alen) {
    struct sockaddr_storage ss;
    socklen_t hl = sizeof ss;
    ss.ss_family = AF_UNSPEC;
    ssize_t r = recvfrom(fd, buf, n, msg_flags_to_host(flags), addr ? (struct sockaddr *)&ss : NULL,
                         addr ? &hl : NULL);
    if (r >= 0 && addr && alen) {
        if (hl == 0) *alen = 0;
        else dx_sockaddr_from_host((struct sockaddr *)&ss, hl, addr, alen);
    }
    return DX_RET(r);
}
DX_FN(recvfrom);
DX_EXPORT("_recvfrom$NOCANCEL", d_recvfrom);
static ssize_t d_recv(int fd, void *buf, size_t n, int flags) {
    return DX_RET(recv(fd, buf, n, msg_flags_to_host(flags)));
}
DX_FN(recv);

/* ---- sendmsg / recvmsg ----------------------------------------------------- */

struct d_msghdr {
    void *msg_name;
    uint32_t msg_namelen;
    struct iovec *msg_iov;
    int msg_iovlen;
    void *msg_control;
    uint32_t msg_controllen;
    int msg_flags;
};
struct d_cmsghdr {
    uint32_t cmsg_len;
    int cmsg_level, cmsg_type;
};
#define D_CMSG_ALIGN(n) (((n) + 3u) & ~3u)

static int cmsg_level_to_host(int l) { return l == D_SOL_SOCKET ? SOL_SOCKET : l; }
static int cmsg_level_from_host(int l) { return l == SOL_SOCKET ? D_SOL_SOCKET : l; }

/* Darwin control buffer -> host control buffer. Returns host length. */
static size_t control_to_host(const void *dctl, uint32_t dlen, void *hctl, size_t hcap) {
    const uint8_t *p = dctl, *end = p + dlen;
    struct msghdr mh = {.msg_control = hctl, .msg_controllen = hcap};
    struct cmsghdr *hc = CMSG_FIRSTHDR(&mh);
    size_t total = 0;
    memset(hctl, 0, hcap);
    while (p + sizeof(struct d_cmsghdr) <= end && hc) {
        const struct d_cmsghdr *dc = (const void *)p;
        if (dc->cmsg_len < sizeof *dc || p + dc->cmsg_len > end) break;
        size_t dl = dc->cmsg_len - D_CMSG_ALIGN(sizeof *dc);
        if (total + CMSG_SPACE(dl) > hcap) break;
        hc->cmsg_level = cmsg_level_to_host(dc->cmsg_level);
        hc->cmsg_type = dc->cmsg_type; /* SCM_RIGHTS is 1 on both */
        hc->cmsg_len = CMSG_LEN(dl);
        memcpy(CMSG_DATA(hc), p + D_CMSG_ALIGN(sizeof *dc), dl);
        total += CMSG_SPACE(dl);
        hc = (struct cmsghdr *)((uint8_t *)hc + CMSG_SPACE(dl));
        p += D_CMSG_ALIGN(dc->cmsg_len);
    }
    return total;
}

/* Host control buffer -> Darwin. Returns Darwin length; sets *trunc. */
static uint32_t control_from_host(struct msghdr *mh, void *dctl, uint32_t dcap, int *trunc) {
    uint8_t *p = dctl;
    uint32_t used = 0;
    for (struct cmsghdr *hc = CMSG_FIRSTHDR(mh); hc; hc = CMSG_NXTHDR(mh, hc)) {
        size_t dl = hc->cmsg_len - CMSG_LEN(0);
        uint32_t need = D_CMSG_ALIGN(sizeof(struct d_cmsghdr)) + (uint32_t)dl;
        if (used + need > dcap) {
            *trunc = 1;
            break;
        }
        struct d_cmsghdr *dc = (void *)(p + used);
        dc->cmsg_len = need;
        dc->cmsg_level = cmsg_level_from_host(hc->cmsg_level);
        dc->cmsg_type = hc->cmsg_type;
        memcpy(p + used + D_CMSG_ALIGN(sizeof *dc), CMSG_DATA(hc), dl);
        used += D_CMSG_ALIGN(need);
    }
    return used > dcap ? dcap : used;
}

static ssize_t d_sendmsg(int fd, const struct d_msghdr *dm, int flags) {
    struct sockaddr_storage ss;
    struct msghdr hm;
    memset(&hm, 0, sizeof hm);
    if (dm->msg_name && dm->msg_namelen) {
        int hl = dx_sockaddr_to_host(dm->msg_name, dm->msg_namelen, (struct sockaddr *)&ss);
        if (hl < 0) return DX_RET(-1);
        hm.msg_name = &ss;
        hm.msg_namelen = hl;
    }
    hm.msg_iov = dm->msg_iov;
    hm.msg_iovlen = dm->msg_iovlen;
    char *hctl = NULL;
    if (dm->msg_control && dm->msg_controllen) {
        size_t cap = (size_t)dm->msg_controllen * 2 + 64;
        hctl = alloca(cap);
        hm.msg_control = hctl;
        hm.msg_controllen = control_to_host(dm->msg_control, dm->msg_controllen, hctl, cap);
    }
    return DX_RET(sendmsg(fd, &hm, msg_flags_to_host(flags)));
}
DX_FN(sendmsg);
DX_EXPORT("_sendmsg$NOCANCEL", d_sendmsg);

static ssize_t d_recvmsg(int fd, struct d_msghdr *dm, int flags) {
    struct sockaddr_storage ss;
    struct msghdr hm;
    memset(&hm, 0, sizeof hm);
    if (dm->msg_name) {
        hm.msg_name = &ss;
        hm.msg_namelen = sizeof ss;
    }
    hm.msg_iov = dm->msg_iov;
    hm.msg_iovlen = dm->msg_iovlen;
    size_t cap = 0;
    if (dm->msg_control && dm->msg_controllen) {
        cap = (size_t)dm->msg_controllen * 2 + 64;
        hm.msg_control = alloca(cap);
        hm.msg_controllen = cap;
    }
    ssize_t r = recvmsg(fd, &hm, msg_flags_to_host(flags));
    if (r < 0) return DX_RET(r);
    int trunc = 0;
    if (dm->msg_name) {
        if (hm.msg_namelen == 0) dm->msg_namelen = 0;
        else dx_sockaddr_from_host((struct sockaddr *)&ss, hm.msg_namelen, dm->msg_name, &dm->msg_namelen);
    }
    if (dm->msg_control && dm->msg_controllen)
        dm->msg_controllen = control_from_host(&hm, dm->msg_control, dm->msg_controllen, &trunc);
    else
        dm->msg_controllen = 0;
    dm->msg_flags = msg_flags_from_host(hm.msg_flags) | (trunc ? 0x20 : 0);
    return r;
}
DX_FN(recvmsg);
DX_EXPORT("_recvmsg$NOCANCEL", d_recvmsg);

/* ---- poll / select --------------------------------------------------------- */

static int d_poll(struct pollfd *fds, unsigned n, int timeout) {
    /* POLLIN/PRI/OUT/ERR/HUP/NVAL share values; Darwin's POLLRDNORM 0x40,
     * POLLWRNORM = POLLOUT, POLLRDBAND 0x80, POLLWRBAND 0x100 */
    for (unsigned i = 0; i < n; i++) {
        short e = fds[i].events, h = e & 0x3f;
        if (e & 0x40) h |= POLLRDNORM;
        if (e & 0x80) h |= POLLRDBAND;
        if (e & 0x100) h |= POLLWRBAND;
        fds[i].events = h;
    }
    int r = poll(fds, n, timeout);
    for (unsigned i = 0; i < n; i++) {
        short h = fds[i].revents, d = h & 0x3f;
        if (h & POLLRDNORM) d |= 0x40;
        if (h & POLLRDBAND) d |= 0x80;
        if (h & POLLWRBAND) d |= 0x100;
        fds[i].revents = d;
    }
    return DX_RET(r);
}
DX_FN(poll);
DX_EXPORT("_poll$NOCANCEL", d_poll);

/* Darwin fd_set is an array of 32-bit words; bit order within little-endian
 * memory matches the host's 64-bit words. */
static int d_select(int n, fd_set *r, fd_set *w, fd_set *e, struct d_timeval *tv) {
    struct timeval h, *hp = NULL;
    if (tv) {
        h.tv_sec = tv->tv_sec;
        h.tv_usec = tv->tv_usec;
        hp = &h;
    }
    return DX_RET(select(n, r, w, e, hp));
}
DX_FN(select);
DX_EXPORT("_select$DARWIN_EXTSN", d_select);
DX_EXPORT("_select$1050", d_select);
DX_EXPORT("_select$NOCANCEL", d_select);

/* ---- names ----------------------------------------------------------------- */

struct d_addrinfo {
    int ai_flags, ai_family, ai_socktype, ai_protocol;
    uint32_t ai_addrlen;
    char *ai_canonname;
    void *ai_addr;
    struct d_addrinfo *ai_next;
};

static int ai_flags_to_host(int d) {
    int h = d & 7; /* PASSIVE, CANONNAME, NUMERICHOST */
    if (d & 0x1000) h |= AI_NUMERICSERV;
    if (d & 0x100) h |= AI_ALL;
    if (d & 0x400) h |= AI_ADDRCONFIG;
    if (d & 0x800) h |= AI_V4MAPPED;
    return h;
}

static int eai_from_host(int h) {
    switch (h) {
    case 0: return 0;
    case EAI_AGAIN: return 2;
    case EAI_BADFLAGS: return 3;
    case EAI_FAIL: return 4;
    case EAI_FAMILY: return 5;
    case EAI_MEMORY: return 6;
    case EAI_NODATA: return 7;
    case EAI_NONAME: return 8;
    case EAI_SERVICE: return 9;
    case EAI_SOCKTYPE: return 10;
    case EAI_SYSTEM: return 11;
    case EAI_OVERFLOW: return 14;
    }
    return 4;
}

static int d_getaddrinfo(const char *node, const char *service, const struct d_addrinfo *hints,
                         struct d_addrinfo **res) {
    struct addrinfo hh, *hres = NULL;
    memset(&hh, 0, sizeof hh);
    if (hints) {
        hh.ai_flags = ai_flags_to_host(hints->ai_flags);
        hh.ai_family = af_to_host(hints->ai_family);
        if (hh.ai_family < 0) return 5;
        hh.ai_socktype = hints->ai_socktype;
        hh.ai_protocol = hints->ai_protocol;
    }
    int r = getaddrinfo(node, service, hints ? &hh : NULL, &hres);
    if (r) {
        if (r == EAI_SYSTEM) dx_set_errno(dx_errno_to_darwin(errno));
        return eai_from_host(r);
    }
    struct d_addrinfo *head = NULL, **tail = &head;
    for (struct addrinfo *a = hres; a; a = a->ai_next) {
        struct d_addrinfo *d = calloc(1, sizeof *d + 128);
        d->ai_flags = hints ? hints->ai_flags : 0;
        d->ai_family = af_from_host(a->ai_family);
        d->ai_socktype = a->ai_socktype;
        d->ai_protocol = a->ai_protocol;
        d->ai_addr = d + 1;
        uint32_t dl = 128;
        dx_sockaddr_from_host(a->ai_addr, a->ai_addrlen, d->ai_addr, &dl);
        d->ai_addrlen = dl;
        if (a->ai_canonname) d->ai_canonname = strdup(a->ai_canonname);
        *tail = d;
        tail = &d->ai_next;
    }
    freeaddrinfo(hres);
    *res = head;
    return 0;
}
DX_FN(getaddrinfo);

static void d_freeaddrinfo(struct d_addrinfo *a) {
    while (a) {
        struct d_addrinfo *n = a->ai_next;
        free(a->ai_canonname);
        free(a);
        a = n;
    }
}
DX_FN(freeaddrinfo);

static const char *d_gai_strerror(int e) {
    switch (e) {
    case 2: return "Temporary failure in name resolution";
    case 3: return "Invalid value for ai_flags";
    case 4: return "Non-recoverable failure in name resolution";
    case 5: return "ai_family not supported";
    case 6: return "Memory allocation failure";
    case 7: return "No address associated with nodename";
    case 8: return "nodename nor servname provided, or not known";
    case 9: return "servname not supported for ai_socktype";
    case 10: return "ai_socktype not supported";
    case 11: return "System error";
    case 14: return "Argument buffer overflow";
    }
    return "Unknown error";
}
DX_FN(gai_strerror);

static int d_getnameinfo(const void *sa, uint32_t salen, char *host, uint32_t hostlen, char *serv,
                         uint32_t servlen, int flags) {
    struct sockaddr_storage ss;
    int hl = dx_sockaddr_to_host(sa, salen, (struct sockaddr *)&ss);
    if (hl < 0) return 5;
    /* Darwin: NI_NOFQDN 1, NUMERICHOST 2, NAMEREQD 4, NUMERICSERV 8, DGRAM 0x10 */
    int hf = 0;
    if (flags & 1) hf |= NI_NOFQDN;
    if (flags & 2) hf |= NI_NUMERICHOST;
    if (flags & 4) hf |= NI_NAMEREQD;
    if (flags & 8) hf |= NI_NUMERICSERV;
    if (flags & 0x10) hf |= NI_DGRAM;
    return eai_from_host(getnameinfo((struct sockaddr *)&ss, hl, host, hostlen, serv, servlen, hf));
}
DX_FN(getnameinfo);

static const char *d_inet_ntop(int af, const void *src, char *dst, uint32_t size) {
    const char *r = inet_ntop(af_to_host(af), src, dst, size);
    if (!r) dx_set_errno(dx_errno_to_darwin(errno));
    return r;
}
DX_FN(inet_ntop);
static int d_inet_pton(int af, const char *src, void *dst) { return DX_RET(inet_pton(af_to_host(af), src, dst)); }
DX_FN(inet_pton);
DX_PASS(inet_addr); DX_PASS(inet_ntoa); DX_PASS(inet_aton);
DX_PASS(htonl); DX_PASS(htons); DX_PASS(ntohl); DX_PASS(ntohs);
DX_PASS(if_nametoindex); DX_PASS(if_indextoname);
DX_PASS(getservbyname); DX_PASS(getservbyport); DX_PASS(getprotobyname);

/* struct hostent has the same layout; h_addrtype needs AF translation. */
static struct hostent *d_gethostbyname(const char *name) {
    struct hostent *h = gethostbyname(name);
    if (h) h->h_addrtype = af_from_host(h->h_addrtype);
    return h;
}
DX_FN(gethostbyname);
