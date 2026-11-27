/* File-system ABI: Darwin stat/dirent layouts and open flags. */
#include "darwin.h"

struct timespec { long tv_sec, tv_nsec; };
struct stat {
    int32_t st_dev; uint16_t st_mode, st_nlink; uint64_t st_ino; uint32_t st_uid, st_gid;
    int32_t st_rdev; struct timespec at, mt, ct, bt; int64_t st_size, st_blocks;
    int32_t st_blksize; uint32_t st_flags, st_gen; int32_t st_lspare; int64_t st_qspare[2];
};
struct dirent { uint64_t d_ino, d_seekoff; uint16_t d_reclen, d_namlen; uint8_t d_type; char d_name[1024]; };

int open(const char *, int, ...);
int close(int);
ssize_t write(int, const void *, size_t);
ssize_t read(int, void *, size_t);
off_t lseek(int, off_t, int);
int fstat(int, struct stat *) __asm("_fstat$INODE64");
int stat(const char *, struct stat *) __asm("_stat$INODE64");
int unlink(const char *);
int mkdir(const char *, int);
int rmdir(const char *);
void *opendir(const char *) __asm("_opendir$INODE64");
struct dirent *readdir(void *) __asm("_readdir$INODE64");
int closedir(void *);
int fcntl(int, int, ...);
int getpid(void);
long pathconf(const char *, int);
long fpathconf(int, int);
void *fdopen_ext(int, const char *) __asm("_fdopen$DARWIN_EXTSN");
int fclose(void *);
int fgetc(void *);

#define O_RDWR 2
#define O_NONBLOCK 4
#define O_CREAT 0x200
#define O_TRUNC 0x400
#define O_EXCL 0x800
#define O_CLOEXEC 0x1000000
#define ENOENT 2
#define EEXIST 17
#define EBADF 9
#define EINVAL 22

int main(void) {
    char dir[128], path[192];
    snprintf(dir, sizeof dir, "/tmp/bitten-files-%d", getpid());
    snprintf(path, sizeof path, "%s/data.txt", dir);
    CHECK(mkdir(dir, 0755) == 0);

    int fd = open(path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0640);
    CHECK(fd >= 0);
    CHECK(write(fd, "0123456789", 10) == 10);
    struct stat st;
    CHECK(fstat(fd, &st) == 0);
    CHECK(st.st_size == 10);
    CHECK((st.st_mode & 0170000) == 0100000);
    CHECK((st.st_mode & 0777) == 0640);
    CHECK(fcntl(fd, 1 /* F_GETFD */) == 1);
    CHECK((fcntl(fd, 3 /* F_GETFL */) & 3) == O_RDWR);
    CHECK(fcntl(fd, 4 /* F_SETFL */, O_NONBLOCK) == 0);
    CHECK(fcntl(fd, 3) & O_NONBLOCK);
    char buf[16] = {0};
    CHECK(lseek(fd, 4, 0) == 4);
    CHECK(read(fd, buf, 3) == 3 && memcmp(buf, "456", 3) == 0);
    /* Darwin's 4 and 5 are not glibc's selectors; path and fd agree. */
    long maxname = pathconf(path, 4);
    CHECK(maxname >= 14 && fpathconf(fd, 4) == maxname);
    long maxpath = pathconf(path, 5);
    CHECK(maxpath > maxname && fpathconf(fd, 5) == maxpath);
    errno = 0;
    CHECK(pathconf(path, -1) == -1 && errno == EINVAL);
    errno = 0;
    CHECK(fpathconf(-1, 4) == -1 && errno == EBADF);
    errno = 0;
    CHECK(pathconf("/definitely/not/here", 4) == -1 && errno == ENOENT);
    errno = 0;
    CHECK(fdopen_ext(-1, "r") == NULL && errno == EBADF);
    CHECK(lseek(fd, 0, 0) == 0);
    void *stream = fdopen_ext(fd, "r");
    CHECK(stream != NULL && fgetc(stream) == '0');
    CHECK(fclose(stream) == 0);

    CHECK(open(path, O_RDWR | O_CREAT | O_EXCL, 0600) == -1 && errno == EEXIST);
    CHECK(stat("/definitely/not/here", &st) == -1 && errno == ENOENT);

    void *d = opendir(dir);
    CHECK(d != NULL);
    int seen = 0;
    for (struct dirent *e; (e = readdir(d));)
        if (strcmp(e->d_name, "data.txt") == 0) {
            CHECK(e->d_namlen == 8 && e->d_type == 8 /* DT_REG */);
            seen = 1;
        }
    CHECK(seen);
    CHECK(closedir(d) == 0);
    CHECK(unlink(path) == 0 && rmdir(dir) == 0);
    puts("files ok");
    return 0;
}
