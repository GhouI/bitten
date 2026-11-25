/* bitten SDK: <sys/socket.h>, BSD socket addresses (with sa_len) and
 * Darwin's option numbers. */
#ifndef BITTEN_SYS_SOCKET_H
#define BITTEN_SYS_SOCKET_H
#include <sys/_types.h>
#include <sys/uio.h>

#define SOCK_STREAM 1
#define SOCK_DGRAM 2
#define SOCK_RAW 3
#define SOCK_SEQPACKET 5

#define AF_UNSPEC 0
#define AF_UNIX 1
#define AF_LOCAL AF_UNIX
#define AF_INET 2
#define AF_ROUTE 17
#define AF_INET6 30
#define AF_SYSTEM 32
#define PF_UNSPEC AF_UNSPEC
#define PF_UNIX AF_UNIX
#define PF_LOCAL AF_LOCAL
#define PF_INET AF_INET
#define PF_ROUTE AF_ROUTE
#define PF_INET6 AF_INET6
#define PF_SYSTEM AF_SYSTEM

#define SOL_SOCKET 0xffff
#define SO_DEBUG 0x0001
#define SO_ACCEPTCONN 0x0002
#define SO_REUSEADDR 0x0004
#define SO_KEEPALIVE 0x0008
#define SO_DONTROUTE 0x0010
#define SO_BROADCAST 0x0020
#define SO_LINGER 0x0080
#define SO_OOBINLINE 0x0100
#define SO_REUSEPORT 0x0200
#define SO_TIMESTAMP 0x0400
#define SO_SNDBUF 0x1001
#define SO_RCVBUF 0x1002
#define SO_SNDLOWAT 0x1003
#define SO_RCVLOWAT 0x1004
#define SO_SNDTIMEO 0x1005
#define SO_RCVTIMEO 0x1006
#define SO_ERROR 0x1007
#define SO_TYPE 0x1008
#define SO_NREAD 0x1020
#define SO_NOSIGPIPE 0x1022
#define SO_LINGER_SEC 0x1080
#define SOMAXCONN 128

#define MSG_OOB 0x1
#define MSG_PEEK 0x2
#define MSG_DONTROUTE 0x4
#define MSG_EOR 0x8
#define MSG_TRUNC 0x10
#define MSG_CTRUNC 0x20
#define MSG_WAITALL 0x40
#define MSG_DONTWAIT 0x80
#define MSG_NOSIGNAL 0x80000

#define SHUT_RD 0
#define SHUT_WR 1
#define SHUT_RDWR 2

struct sockaddr {
    uint8_t sa_len;
    sa_family_t sa_family;
    char sa_data[14];
};
struct sockaddr_storage {
    uint8_t ss_len;
    sa_family_t ss_family;
    char __ss_pad1[6];
    int64_t __ss_align;
    char __ss_pad2[112];
};
struct linger {
    int l_onoff;
    int l_linger;
};
struct msghdr {
    void *msg_name;
    socklen_t msg_namelen;
    struct iovec *msg_iov;
    int msg_iovlen;
    void *msg_control;
    socklen_t msg_controllen;
    int msg_flags;
};
struct cmsghdr {
    socklen_t cmsg_len;
    int cmsg_level;
    int cmsg_type;
};
#define SCM_RIGHTS 0x01
#define SCM_TIMESTAMP 0x02
#define SCM_CREDS 0x03
#define __DARWIN_ALIGN32(p) (((size_t)(p) + 3) & ~(size_t)3)
#define CMSG_DATA(c) ((unsigned char *)(c) + __DARWIN_ALIGN32(sizeof(struct cmsghdr)))
#define CMSG_FIRSTHDR(m) \
    ((m)->msg_controllen >= sizeof(struct cmsghdr) ? (struct cmsghdr *)(m)->msg_control : (struct cmsghdr *)0)
#define CMSG_NXTHDR(m, c) \
    ((char *)(c) + __DARWIN_ALIGN32((c)->cmsg_len) + __DARWIN_ALIGN32(sizeof(struct cmsghdr)) > \
             (char *)(m)->msg_control + (m)->msg_controllen \
         ? (struct cmsghdr *)0 \
         : (struct cmsghdr *)((char *)(c) + __DARWIN_ALIGN32((c)->cmsg_len)))
#define CMSG_SPACE(l) (__DARWIN_ALIGN32(sizeof(struct cmsghdr)) + __DARWIN_ALIGN32(l))
#define CMSG_LEN(l) (__DARWIN_ALIGN32(sizeof(struct cmsghdr)) + (l))

__BEGIN_DECLS
int socket(int, int, int);
int socketpair(int, int, int, int[2]);
int bind(int, const struct sockaddr *, socklen_t);
int connect(int, const struct sockaddr *, socklen_t);
int listen(int, int);
int accept(int, struct sockaddr *restrict, socklen_t *restrict);
int shutdown(int, int);
int getsockname(int, struct sockaddr *restrict, socklen_t *restrict);
int getpeername(int, struct sockaddr *restrict, socklen_t *restrict);
int getsockopt(int, int, int, void *restrict, socklen_t *restrict);
int setsockopt(int, int, int, const void *, socklen_t);
ssize_t send(int, const void *, size_t, int);
ssize_t sendto(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
ssize_t sendmsg(int, const struct msghdr *, int);
ssize_t recv(int, void *, size_t, int);
ssize_t recvfrom(int, void *restrict, size_t, int, struct sockaddr *restrict, socklen_t *restrict);
ssize_t recvmsg(int, struct msghdr *, int);
int sendfile(int, int, off_t, off_t *, void *, int);
__END_DECLS
#endif
