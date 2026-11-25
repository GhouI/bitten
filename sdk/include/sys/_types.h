/* bitten SDK: the scalar types of the Darwin x86-64 ABI, and the few
 * structures every other header needs. Sizes follow macOS (mode_t and
 * nlink_t are 16 bits, ino_t is 64 bits, off_t 64 bits, sigset_t 32). */
#ifndef BITTEN_SYS__TYPES_H
#define BITTEN_SYS__TYPES_H
#include <sys/cdefs.h>
#include <stddef.h>
#include <stdint.h>

typedef long __darwin_time_t;
typedef int __darwin_suseconds_t;
typedef unsigned int __darwin_mach_port_t;

typedef long long blkcnt_t;
typedef int blksize_t;
typedef unsigned long clock_t;
typedef int dev_t;
typedef unsigned int fsblkcnt_t;
typedef unsigned int fsfilcnt_t;
typedef unsigned int gid_t;
typedef unsigned int id_t;
typedef unsigned long long ino_t;
typedef unsigned long long ino64_t;
typedef int key_t;
typedef unsigned short mode_t;
typedef unsigned short nlink_t;
typedef long long off_t;
typedef int pid_t;
typedef unsigned long long rlim_t;
typedef unsigned char sa_family_t;
typedef unsigned int socklen_t;
typedef long ssize_t;
typedef __darwin_time_t time_t;
typedef __darwin_suseconds_t suseconds_t;
typedef unsigned int uid_t;
typedef unsigned int useconds_t;
typedef unsigned int sigset_t;
typedef unsigned int in_addr_t;
typedef unsigned short in_port_t;
typedef __darwin_mach_port_t mach_port_t;

struct timespec {
    __darwin_time_t tv_sec;
    long tv_nsec;
};
struct timeval {
    __darwin_time_t tv_sec;
    __darwin_suseconds_t tv_usec;
};

/* pthread objects: an opaque signature word and storage, as on macOS. */
typedef struct _opaque_pthread_t *pthread_t;
typedef struct _opaque_pthread_attr_t { long __sig; char __opaque[56]; } pthread_attr_t;
typedef struct _opaque_pthread_mutex_t { long __sig; char __opaque[56]; } pthread_mutex_t;
typedef struct _opaque_pthread_mutexattr_t { long __sig; char __opaque[8]; } pthread_mutexattr_t;
typedef struct _opaque_pthread_cond_t { long __sig; char __opaque[40]; } pthread_cond_t;
typedef struct _opaque_pthread_condattr_t { long __sig; char __opaque[8]; } pthread_condattr_t;
typedef struct _opaque_pthread_rwlock_t { long __sig; char __opaque[192]; } pthread_rwlock_t;
typedef struct _opaque_pthread_rwlockattr_t { long __sig; char __opaque[16]; } pthread_rwlockattr_t;
typedef struct _opaque_pthread_once_t { long __sig; char __opaque[8]; } pthread_once_t;
typedef unsigned long pthread_key_t;
#endif
