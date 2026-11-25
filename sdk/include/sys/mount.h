/* bitten SDK: <sys/mount.h>, statfs with the 64-bit inode layout (2168 bytes). */
#ifndef BITTEN_SYS_MOUNT_H
#define BITTEN_SYS_MOUNT_H
#include <sys/_types.h>
#include <sys/syslimits.h>
typedef struct fsid {
    int32_t val[2];
} fsid_t;
#define MFSTYPENAMELEN 16
#define MNAMELEN PATH_MAX
struct statfs {
    uint32_t f_bsize;
    int32_t f_iosize;
    uint64_t f_blocks;
    uint64_t f_bfree;
    uint64_t f_bavail;
    uint64_t f_files;
    uint64_t f_ffree;
    fsid_t f_fsid;
    uid_t f_owner;
    uint32_t f_type;
    uint32_t f_flags;
    uint32_t f_fssubtype;
    char f_fstypename[MFSTYPENAMELEN];
    char f_mntonname[MNAMELEN];
    char f_mntfromname[MNAMELEN];
    uint32_t f_flags_ext;
    uint32_t f_reserved[7];
};
#define MNT_RDONLY 0x00000001
#define MNT_NOSUID 0x00000008
#define MNT_LOCAL 0x00001000
__BEGIN_DECLS
int statfs(const char *, struct statfs *) __DARWIN_INODE64(statfs);
int fstatfs(int, struct statfs *) __DARWIN_INODE64(fstatfs);
__END_DECLS
#endif
