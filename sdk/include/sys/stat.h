#ifndef BITTEN_SYS_STAT_H
#define BITTEN_SYS_STAT_H
#include <stdint.h>
#include <time.h>
struct stat {
    int32_t st_dev;
    uint16_t st_mode, st_nlink;
    uint64_t st_ino;
    uint32_t st_uid, st_gid;
    int32_t st_rdev;
    struct timespec st_atimespec, st_mtimespec, st_ctimespec, st_birthtimespec;
    int64_t st_size, st_blocks;
    int32_t st_blksize;
    uint32_t st_flags, st_gen;
    int32_t st_lspare;
    int64_t st_qspare[2];
};
#define S_IFMT 0170000
#define S_IFDIR 0040000
#define S_IFREG 0100000
#define S_IFLNK 0120000
#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#define S_ISLNK(m) (((m) & S_IFMT) == S_IFLNK)
int stat(const char *, struct stat *) __asm("_stat$INODE64");
int lstat(const char *, struct stat *) __asm("_lstat$INODE64");
int fstat(int, struct stat *) __asm("_fstat$INODE64");
int mkdir(const char *, uint16_t);
int chmod(const char *, uint16_t);
#endif
