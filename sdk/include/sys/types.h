/* bitten SDK: <sys/types.h>. */
#ifndef BITTEN_SYS_TYPES_H
#define BITTEN_SYS_TYPES_H
#include <sys/_types.h>

typedef unsigned char u_char;
typedef unsigned short u_short;
typedef unsigned int u_int;
typedef unsigned long u_long;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned char u_int8_t;
typedef unsigned short u_int16_t;
typedef unsigned int u_int32_t;
typedef unsigned long long u_int64_t;
typedef long long quad_t;
typedef unsigned long long u_quad_t;
typedef long long register_t;
typedef char *caddr_t;
typedef int daddr_t;
typedef int segsz_t;
typedef int swblk_t;
typedef unsigned int fixpt_t;
typedef unsigned long long user_addr_t;
typedef long long user_ssize_t;
typedef unsigned long long user_size_t;

#define major(x) ((int32_t)(((uint32_t)(x) >> 24) & 0xff))
#define minor(x) ((int32_t)((x) & 0xffffff))
#define makedev(x, y) ((dev_t)(((x) << 24) | (y)))

#define NBBY 8
#define FD_SETSIZE 1024
#define __DARWIN_NFDBITS (sizeof(int32_t) * 8)
typedef struct fd_set {
    int32_t fds_bits[FD_SETSIZE / __DARWIN_NFDBITS];
} fd_set;
#define FD_SET(n, p) ((p)->fds_bits[(unsigned long)(n) / __DARWIN_NFDBITS] |= \
                      (int32_t)(1U << ((unsigned long)(n) % __DARWIN_NFDBITS)))
#define FD_CLR(n, p) ((p)->fds_bits[(unsigned long)(n) / __DARWIN_NFDBITS] &= \
                      ~(int32_t)(1U << ((unsigned long)(n) % __DARWIN_NFDBITS)))
#define FD_ISSET(n, p) (((p)->fds_bits[(unsigned long)(n) / __DARWIN_NFDBITS] & \
                         (int32_t)(1U << ((unsigned long)(n) % __DARWIN_NFDBITS))) != 0)
#define FD_ZERO(p) __builtin_memset((p), 0, sizeof(*(p)))
#endif
