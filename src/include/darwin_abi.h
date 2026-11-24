/* Darwin x86-64 ABI: struct layouts and constants that differ from Linux.
 * Written from public documentation of the BSD/Darwin interfaces. */
#ifndef DX_DARWIN_ABI_H
#define DX_DARWIN_ABI_H
#include <stdint.h>
#include <time.h>

struct d_timeval {
    int64_t tv_sec;
    int32_t tv_usec;
    int32_t pad_;
};

struct d_stat { /* the $INODE64 / stat64 layout, 144 bytes */
    int32_t st_dev;
    uint16_t st_mode;
    uint16_t st_nlink;
    uint64_t st_ino;
    uint32_t st_uid;
    uint32_t st_gid;
    int32_t st_rdev;
    int32_t pad_;
    struct timespec st_atimespec, st_mtimespec, st_ctimespec, st_birthtimespec;
    int64_t st_size;
    int64_t st_blocks;
    int32_t st_blksize;
    uint32_t st_flags;
    uint32_t st_gen;
    int32_t st_lspare;
    int64_t st_qspare[2];
};
_Static_assert(sizeof(struct d_stat) == 144, "Darwin stat64 is 144 bytes");

struct d_statfs { /* $INODE64 layout, 2168 bytes */
    uint32_t f_bsize;
    int32_t f_iosize;
    uint64_t f_blocks, f_bfree, f_bavail, f_files, f_ffree;
    int32_t f_fsid[2];
    uint32_t f_owner;
    uint32_t f_type;
    uint32_t f_flags;
    uint32_t f_fssubtype;
    char f_fstypename[16];
    char f_mntonname[1024];
    char f_mntfromname[1024];
    uint32_t f_flags_ext;
    uint32_t f_reserved[7];
};
_Static_assert(sizeof(struct d_statfs) == 2168, "Darwin statfs64 is 2168 bytes");

struct d_dirent { /* $INODE64 layout */
    uint64_t d_ino;
    uint64_t d_seekoff;
    uint16_t d_reclen;
    uint16_t d_namlen;
    uint8_t d_type;
    char d_name[1024];
};

/* open(2) flags */
#define D_O_ACCMODE 0x3
#define D_O_NONBLOCK 0x4
#define D_O_APPEND 0x8
#define D_O_SHLOCK 0x10
#define D_O_EXLOCK 0x20
#define D_O_ASYNC 0x40
#define D_O_SYNC 0x80
#define D_O_NOFOLLOW 0x100
#define D_O_CREAT 0x200
#define D_O_TRUNC 0x400
#define D_O_EXCL 0x800
#define D_O_EVTONLY 0x8000
#define D_O_NOCTTY 0x20000
#define D_O_DIRECTORY 0x100000
#define D_O_SYMLINK 0x200000
#define D_O_DSYNC 0x400000
#define D_O_CLOEXEC 0x1000000

/* *at() */
#define D_AT_FDCWD (-2)
#define D_AT_EACCESS 0x10
#define D_AT_SYMLINK_NOFOLLOW 0x20
#define D_AT_SYMLINK_FOLLOW 0x40
#define D_AT_REMOVEDIR 0x80

int dx_open_flags_to_host(int d);
int dx_open_flags_from_host(int h);
int dx_at_fd(int d);
int dx_at_flags_to_host(int d);

/* sockets (net.c) */
struct sockaddr;
/* Convert a Darwin sockaddr to the host layout. Returns the host length or
 * -1 (errno set to a host value). `out` must hold 128 bytes. */
int dx_sockaddr_to_host(const void *d, uint32_t dlen, struct sockaddr *out);
/* Convert a host sockaddr into a Darwin buffer of capacity *dlen; stores the
 * full Darwin length in *dlen like the BSD calls do. */
void dx_sockaddr_from_host(const struct sockaddr *h, uint32_t hlen, void *d, uint32_t *dlen);

/* wait status / signals */
int dx_wait_status_from_host(int status);
/* Darwin sigset_t is a 32-bit mask, bit (n-1) for Darwin signal n. */
struct __sigset_t_tag;
void dx_sigset_to_host(uint32_t d, void *host_sigset);
uint32_t dx_sigset_from_host(const void *host_sigset);

/* Called by close() so emulated objects can drop per-fd state. */
void dx_fd_closed(int fd);

#endif
