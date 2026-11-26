/* Files and directories: Darwin layouts and flag values over Linux calls. */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/sendfile.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <sys/xattr.h>
#include <unistd.h>

#include "darwin_abi.h"
#include "dx.h"

#define P(path) dx_path(path, pbuf, sizeof pbuf)
#define PBUF char pbuf[PATH_MAX]

int dx_open_flags_to_host(int d) {
    int h = d & D_O_ACCMODE;
    if (d & D_O_NONBLOCK) h |= O_NONBLOCK;
    if (d & D_O_APPEND) h |= O_APPEND;
    if (d & D_O_ASYNC) h |= O_ASYNC;
    if (d & D_O_SYNC) h |= O_SYNC;
    if (d & D_O_NOFOLLOW) h |= O_NOFOLLOW;
    if (d & D_O_CREAT) h |= O_CREAT;
    if (d & D_O_TRUNC) h |= O_TRUNC;
    if (d & D_O_EXCL) h |= O_EXCL;
    if (d & D_O_NOCTTY) h |= O_NOCTTY;
    if (d & D_O_DIRECTORY) h |= O_DIRECTORY;
    if (d & D_O_SYMLINK) h |= O_PATH | O_NOFOLLOW;
    if (d & D_O_DSYNC) h |= O_DSYNC;
    if (d & D_O_CLOEXEC) h |= O_CLOEXEC;
    return h;
}

int dx_open_flags_from_host(int h) {
    int d = h & O_ACCMODE;
    if (h & O_NONBLOCK) d |= D_O_NONBLOCK;
    if (h & O_APPEND) d |= D_O_APPEND;
    if (h & O_ASYNC) d |= D_O_ASYNC;
    if ((h & O_SYNC) == O_SYNC) d |= D_O_SYNC;
    else if (h & O_DSYNC) d |= D_O_DSYNC;
    if (h & O_NOFOLLOW) d |= D_O_NOFOLLOW;
    if (h & O_CREAT) d |= D_O_CREAT;
    if (h & O_TRUNC) d |= D_O_TRUNC;
    if (h & O_EXCL) d |= D_O_EXCL;
    if (h & O_NOCTTY) d |= D_O_NOCTTY;
    if (h & O_DIRECTORY) d |= D_O_DIRECTORY;
    if (h & O_CLOEXEC) d |= D_O_CLOEXEC;
    return d;
}

int dx_at_fd(int d) { return d == D_AT_FDCWD ? AT_FDCWD : d; }

int dx_at_flags_to_host(int d) {
    int h = 0;
    if (d & D_AT_EACCESS) h |= AT_EACCESS;
    if (d & D_AT_SYMLINK_NOFOLLOW) h |= AT_SYMLINK_NOFOLLOW;
    if (d & D_AT_SYMLINK_FOLLOW) h |= AT_SYMLINK_FOLLOW;
    if (d & D_AT_REMOVEDIR) h |= AT_REMOVEDIR;
    return h;
}

/* ---- open / close / io -------------------------------------------------- */

static int d_open(const char *path, int flags, int mode) {
    PBUF;
    int hf = dx_open_flags_to_host(flags);
    int fd = open(P(path), hf, mode);
    if (fd >= 0 && (flags & (D_O_SHLOCK | D_O_EXLOCK)))
        flock(fd, (flags & D_O_EXLOCK) ? LOCK_EX : LOCK_SH);
    return DX_RET(fd);
}
DX_FN(open);
DX_EXPORT("_open$NOCANCEL", d_open);
DX_EXPORT("___open", d_open);

static int d_openat(int dirfd, const char *path, int flags, int mode) {
    PBUF;
    return DX_RET(openat(dx_at_fd(dirfd), P(path), dx_open_flags_to_host(flags), mode));
}
DX_FN(openat);
DX_EXPORT("_openat$NOCANCEL", d_openat);

static int d_creat(const char *path, int mode) {
    PBUF;
    return DX_RET(creat(P(path), mode));
}
DX_FN(creat);

__attribute__((weak)) void dx_fd_closed(int fd) { (void)fd; }

static int d_close(int fd) {
    dx_fd_closed(fd);
    return DX_RET(close(fd));
}
DX_FN(close);
DX_EXPORT("_close$NOCANCEL", d_close);

static ssize_t d_read(int fd, void *buf, size_t n) { return DX_RET(read(fd, buf, n)); }
DX_FN(read);
DX_EXPORT("_read$NOCANCEL", d_read);
static ssize_t d_write(int fd, const void *buf, size_t n) { return DX_RET(write(fd, buf, n)); }
DX_FN(write);
DX_EXPORT("_write$NOCANCEL", d_write);
static ssize_t d_pread(int fd, void *buf, size_t n, off_t off) { return DX_RET(pread(fd, buf, n, off)); }
DX_FN(pread);
DX_EXPORT("_pread$NOCANCEL", d_pread);
static ssize_t d_pwrite(int fd, const void *buf, size_t n, off_t off) { return DX_RET(pwrite(fd, buf, n, off)); }
DX_FN(pwrite);
DX_EXPORT("_pwrite$NOCANCEL", d_pwrite);
static ssize_t d_readv(int fd, const struct iovec *iov, int n) { return DX_RET(readv(fd, iov, n)); }
DX_FN(readv);
static ssize_t d_writev(int fd, const struct iovec *iov, int n) { return DX_RET(writev(fd, iov, n)); }
DX_FN(writev);
static ssize_t d_preadv(int fd, const struct iovec *iov, int n, off_t off) { return DX_RET(preadv(fd, iov, n, off)); }
DX_FN(preadv);
static ssize_t d_pwritev(int fd, const struct iovec *iov, int n, off_t off) { return DX_RET(pwritev(fd, iov, n, off)); }
DX_FN(pwritev);
static off_t d_lseek(int fd, off_t off, int whence) { return DX_RET(lseek(fd, off, whence)); }
DX_FN(lseek);
static int d_fsync(int fd) { return DX_RET(fsync(fd)); }
DX_FN(fsync);
DX_EXPORT("_fsync$NOCANCEL", d_fsync);
static int d_fdatasync(int fd) { return DX_RET(fdatasync(fd)); }
DX_FN(fdatasync);
static int d_ftruncate(int fd, off_t len) { return DX_RET(ftruncate(fd, len)); }
DX_FN(ftruncate);
static int d_truncate(const char *path, off_t len) {
    PBUF;
    return DX_RET(truncate(P(path), len));
}
DX_FN(truncate);
static int d_dup(int fd) { return DX_RET(dup(fd)); }
DX_FN(dup);
static int d_dup2(int a, int b) { return DX_RET(dup2(a, b)); }
DX_FN(dup2);
static int d_pipe(int fds[2]) { return DX_RET(pipe(fds)); }
DX_FN(pipe);
static int d_flock(int fd, int op) { return DX_RET(flock(fd, op)); }
DX_FN(flock);
static void d_sync(void) { sync(); }
DX_FN(sync);
static int d_isatty(int fd) {
    int r = isatty(fd);
    if (!r) dx_set_errno(dx_errno_to_darwin(errno));
    return r;
}
DX_FN(isatty);

/* ---- fcntl -------------------------------------------------------------- */

struct d_flock {
    off_t l_start, l_len;
    pid_t l_pid;
    short l_type, l_whence;
};

static short lock_type_to_host(short d) { return d == 1 ? F_RDLCK : d == 3 ? F_WRLCK : F_UNLCK; }
static short lock_type_from_host(short h) { return h == F_RDLCK ? 1 : h == F_WRLCK ? 3 : 2; }

static int d_fcntl(int fd, int cmd, long arg) {
    switch (cmd) {
    case 0: return DX_RET(fcntl(fd, F_DUPFD, (int)arg));
    case 67: return DX_RET(fcntl(fd, F_DUPFD_CLOEXEC, (int)arg));
    case 1: return DX_RET(fcntl(fd, F_GETFD));
    case 2: return DX_RET(fcntl(fd, F_SETFD, (int)arg));
    case 3: {
        int r = fcntl(fd, F_GETFL);
        if (r < 0) return DX_RET(r);
        return dx_open_flags_from_host(r);
    }
    case 4: return DX_RET(fcntl(fd, F_SETFL, dx_open_flags_to_host((int)arg)));
    case 5: return DX_RET(fcntl(fd, F_GETOWN));
    case 6: return DX_RET(fcntl(fd, F_SETOWN, (int)arg));
    case 7: case 8: case 9: case 90: case 91: case 92: {
        struct d_flock *dl = (void *)arg;
        struct flock hl = {.l_type = lock_type_to_host(dl->l_type), .l_whence = dl->l_whence,
                           .l_start = dl->l_start, .l_len = dl->l_len, .l_pid = dl->l_pid};
        int hc = cmd == 7 ? F_GETLK : cmd == 8 ? F_SETLK : cmd == 9 ? F_SETLKW
               : cmd == 90 ? F_OFD_SETLK : cmd == 91 ? F_OFD_SETLKW : F_OFD_GETLK;
        if (hc == F_OFD_SETLK || hc == F_OFD_SETLKW || hc == F_OFD_GETLK) hl.l_pid = 0;
        int r = fcntl(fd, hc, &hl);
        if (r == 0 && (cmd == 7 || cmd == 92)) {
            dl->l_type = lock_type_from_host(hl.l_type);
            dl->l_whence = hl.l_whence;
            dl->l_start = hl.l_start;
            dl->l_len = hl.l_len;
            dl->l_pid = hl.l_pid;
        }
        return DX_RET(r);
    }
    case 50: { /* F_GETPATH */
        char link[64];
        snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
        ssize_t n = readlink(link, (char *)arg, 1023);
        if (n < 0) return DX_RET(-1);
        ((char *)arg)[n] = 0;
        return 0;
    }
    case 51: /* F_FULLFSYNC */
    case 85: /* F_BARRIERFSYNC */
        return DX_RET(fsync(fd));
    case 42: { /* F_PREALLOCATE: best effort */
        return 0;
    }
    case 44: case 45: case 48: case 62: case 73: /* read-ahead / cache / NOSIGPIPE hints */
        return 0;
    case 74: return 0;
    default:
        dx_log(1, "fcntl: unsupported Darwin command %d", cmd);
        dx_set_errno(22);
        return -1;
    }
}
DX_FN(fcntl);
DX_EXPORT("_fcntl$NOCANCEL", d_fcntl);

/* ---- stat --------------------------------------------------------------- */

static void stat_from_host(const struct stat *h, struct d_stat *d) {
    memset(d, 0, sizeof *d);
    d->st_dev = (int32_t)h->st_dev;
    d->st_mode = h->st_mode;
    d->st_nlink = h->st_nlink > 0xffff ? 0xffff : h->st_nlink;
    d->st_ino = h->st_ino;
    d->st_uid = h->st_uid;
    d->st_gid = h->st_gid;
    d->st_rdev = (int32_t)h->st_rdev;
    d->st_atimespec = h->st_atim;
    d->st_mtimespec = h->st_mtim;
    d->st_ctimespec = h->st_ctim;
    d->st_birthtimespec = h->st_ctim;
    d->st_size = h->st_size;
    d->st_blocks = h->st_blocks;
    d->st_blksize = h->st_blksize;
}

static int d_stat(const char *path, struct d_stat *out) {
    PBUF;
    struct stat st;
    int r = stat(P(path), &st);
    if (r == 0) stat_from_host(&st, out);
    return DX_RET(r);
}
DX_EXPORT("_stat", d_stat);
DX_EXPORT("_stat$INODE64", d_stat);
DX_EXPORT("_stat64", d_stat);

static int d_lstat(const char *path, struct d_stat *out) {
    PBUF;
    struct stat st;
    int r = lstat(P(path), &st);
    if (r == 0) stat_from_host(&st, out);
    return DX_RET(r);
}
DX_EXPORT("_lstat", d_lstat);
DX_EXPORT("_lstat$INODE64", d_lstat);
DX_EXPORT("_lstat64", d_lstat);

static int d_fstat(int fd, struct d_stat *out) {
    struct stat st;
    int r = fstat(fd, &st);
    if (r == 0) stat_from_host(&st, out);
    return DX_RET(r);
}
DX_EXPORT("_fstat", d_fstat);
DX_EXPORT("_fstat$INODE64", d_fstat);
DX_EXPORT("_fstat64", d_fstat);

static int d_fstatat(int dirfd, const char *path, struct d_stat *out, int flags) {
    PBUF;
    struct stat st;
    int r = fstatat(dx_at_fd(dirfd), P(path), &st, dx_at_flags_to_host(flags));
    if (r == 0) stat_from_host(&st, out);
    return DX_RET(r);
}
DX_EXPORT("_fstatat", d_fstatat);
DX_EXPORT("_fstatat$INODE64", d_fstatat);
DX_EXPORT("_fstatat64", d_fstatat);

static void statfs_from_host(const struct statfs *h, const char *path, struct d_statfs *d) {
    memset(d, 0, sizeof *d);
    d->f_bsize = h->f_bsize;
    d->f_iosize = h->f_bsize;
    d->f_blocks = h->f_blocks;
    d->f_bfree = h->f_bfree;
    d->f_bavail = h->f_bavail;
    d->f_files = h->f_files;
    d->f_ffree = h->f_ffree;
    memcpy(d->f_fsid, &h->f_fsid, sizeof d->f_fsid);
    d->f_type = 0x1a; /* reported as APFS-like local storage */
    strcpy(d->f_fstypename, "apfs");
    strncpy(d->f_mntonname, path ? path : "/", sizeof d->f_mntonname - 1);
    strcpy(d->f_mntfromname, "/dev/disk1s1");
}

static int d_statfs(const char *path, struct d_statfs *out) {
    PBUF;
    struct statfs st;
    int r = statfs(P(path), &st);
    if (r == 0) statfs_from_host(&st, "/", out);
    return DX_RET(r);
}
DX_EXPORT("_statfs", d_statfs);
DX_EXPORT("_statfs$INODE64", d_statfs);
DX_EXPORT("_statfs64", d_statfs);

static int d_fstatfs(int fd, struct d_statfs *out) {
    struct statfs st;
    int r = fstatfs(fd, &st);
    if (r == 0) statfs_from_host(&st, "/", out);
    return DX_RET(r);
}
DX_EXPORT("_fstatfs", d_fstatfs);
DX_EXPORT("_fstatfs$INODE64", d_fstatfs);
DX_EXPORT("_fstatfs64", d_fstatfs);

/* ---- names -------------------------------------------------------------- */

static int d_access(const char *path, int mode) {
    PBUF;
    return DX_RET(access(P(path), mode & 7));
}
DX_FN(access);

/* Darwin pathconf selectors are not the glibc enum values. Zero encodes
 * unsupported here; add one because glibc's _PC_LINK_MAX itself is zero. */
static int host_pathconf_name(int name) {
    static const int names[] = {
        [1] = _PC_LINK_MAX + 1, [2] = _PC_MAX_CANON + 1,
        [3] = _PC_MAX_INPUT + 1, [4] = _PC_NAME_MAX + 1,
        [5] = _PC_PATH_MAX + 1, [6] = _PC_PIPE_BUF + 1,
        [7] = _PC_CHOWN_RESTRICTED + 1, [8] = _PC_NO_TRUNC + 1,
        [9] = _PC_VDISABLE + 1, [15] = _PC_2_SYMLINKS + 1,
        [16] = _PC_ALLOC_SIZE_MIN + 1, [17] = _PC_ASYNC_IO + 1,
        [18] = _PC_FILESIZEBITS + 1, [19] = _PC_PRIO_IO + 1,
        [20] = _PC_REC_INCR_XFER_SIZE + 1, [21] = _PC_REC_MAX_XFER_SIZE + 1,
        [22] = _PC_REC_MIN_XFER_SIZE + 1, [23] = _PC_REC_XFER_ALIGN + 1,
        [24] = _PC_SYMLINK_MAX + 1, [25] = _PC_SYNC_IO + 1,
    };
    if (name < 0 || (size_t)name >= sizeof names / sizeof *names) return -1;
    return names[name] - 1;
}

static long d_pathconf(const char *path, int name) {
    int host = host_pathconf_name(name);
    if (host == -1) { dx_set_errno(dx_errno_to_darwin(EINVAL)); return -1; }
    PBUF;
    const char *translated = P(path);
    int saved = errno;
    errno = 0;
    long r = pathconf(translated, host);
    if (r == -1 && errno) dx_set_errno(dx_errno_to_darwin(errno));
    errno = saved;
    return r;
}
DX_FN(pathconf);

static long d_fpathconf(int fd, int name) {
    int host = host_pathconf_name(name);
    if (host == -1) { dx_set_errno(dx_errno_to_darwin(EINVAL)); return -1; }
    int saved = errno;
    errno = 0;
    long r = fpathconf(fd, host);
    if (r == -1 && errno) dx_set_errno(dx_errno_to_darwin(errno));
    errno = saved;
    return r;
}
DX_FN(fpathconf);

static int d_faccessat(int dirfd, const char *path, int mode, int flags) {
    PBUF;
    return DX_RET(faccessat(dx_at_fd(dirfd), P(path), mode & 7, dx_at_flags_to_host(flags)));
}
DX_FN(faccessat);
static int d_chmod(const char *path, int mode) {
    PBUF;
    return DX_RET(chmod(P(path), mode));
}
DX_FN(chmod);
static int d_fchmod(int fd, int mode) { return DX_RET(fchmod(fd, mode)); }
DX_FN(fchmod);
static int d_fchmodat(int dirfd, const char *path, int mode, int flags) {
    PBUF;
    /* Linux rejects AT_SYMLINK_NOFOLLOW here; mode changes on links are no-ops. */
    return DX_RET(fchmodat(dx_at_fd(dirfd), P(path), mode, 0));
}
DX_FN(fchmodat);
static int d_chown(const char *path, unsigned uid, unsigned gid) {
    PBUF;
    return DX_RET(chown(P(path), uid, gid));
}
DX_FN(chown);
static int d_lchown(const char *path, unsigned uid, unsigned gid) {
    PBUF;
    return DX_RET(lchown(P(path), uid, gid));
}
DX_FN(lchown);
static int d_fchown(int fd, unsigned uid, unsigned gid) { return DX_RET(fchown(fd, uid, gid)); }
DX_FN(fchown);
static int d_fchownat(int dirfd, const char *path, unsigned uid, unsigned gid, int flags) {
    PBUF;
    return DX_RET(fchownat(dx_at_fd(dirfd), P(path), uid, gid, dx_at_flags_to_host(flags)));
}
DX_FN(fchownat);
static int d_link(const char *a, const char *b) {
    char abuf[PATH_MAX], bbuf[PATH_MAX];
    return DX_RET(link(dx_path(a, abuf, sizeof abuf), dx_path(b, bbuf, sizeof bbuf)));
}
DX_FN(link);
static int d_linkat(int fa, const char *a, int fb, const char *b, int flags) {
    char abuf[PATH_MAX], bbuf[PATH_MAX];
    return DX_RET(linkat(dx_at_fd(fa), dx_path(a, abuf, sizeof abuf), dx_at_fd(fb),
                         dx_path(b, bbuf, sizeof bbuf), dx_at_flags_to_host(flags)));
}
DX_FN(linkat);
static int d_symlink(const char *target, const char *path) {
    PBUF;
    return DX_RET(symlink(target, P(path)));
}
DX_FN(symlink);
static int d_symlinkat(const char *target, int dirfd, const char *path) {
    PBUF;
    return DX_RET(symlinkat(target, dx_at_fd(dirfd), P(path)));
}
DX_FN(symlinkat);
static ssize_t d_readlink(const char *path, char *buf, size_t n) {
    PBUF;
    return DX_RET(readlink(P(path), buf, n));
}
DX_FN(readlink);
static ssize_t d_readlinkat(int dirfd, const char *path, char *buf, size_t n) {
    PBUF;
    return DX_RET(readlinkat(dx_at_fd(dirfd), P(path), buf, n));
}
DX_FN(readlinkat);
static int d_unlink(const char *path) {
    PBUF;
    return DX_RET(unlink(P(path)));
}
DX_FN(unlink);
static int d_unlinkat(int dirfd, const char *path, int flags) {
    PBUF;
    return DX_RET(unlinkat(dx_at_fd(dirfd), P(path), dx_at_flags_to_host(flags)));
}
DX_FN(unlinkat);
static int d_remove(const char *path) {
    PBUF;
    return DX_RET(remove(P(path)));
}
DX_FN(remove);
static int d_rename(const char *a, const char *b) {
    char abuf[PATH_MAX], bbuf[PATH_MAX];
    return DX_RET(rename(dx_path(a, abuf, sizeof abuf), dx_path(b, bbuf, sizeof bbuf)));
}
DX_FN(rename);
static int d_renameat(int fa, const char *a, int fb, const char *b) {
    char abuf[PATH_MAX], bbuf[PATH_MAX];
    return DX_RET(renameat(dx_at_fd(fa), dx_path(a, abuf, sizeof abuf), dx_at_fd(fb),
                           dx_path(b, bbuf, sizeof bbuf)));
}
DX_FN(renameat);
static int d_mkdir(const char *path, int mode) {
    PBUF;
    return DX_RET(mkdir(P(path), mode));
}
DX_FN(mkdir);
static int d_mkdirat(int dirfd, const char *path, int mode) {
    PBUF;
    return DX_RET(mkdirat(dx_at_fd(dirfd), P(path), mode));
}
DX_FN(mkdirat);
static int d_rmdir(const char *path) {
    PBUF;
    return DX_RET(rmdir(P(path)));
}
DX_FN(rmdir);
static int d_mkfifo(const char *path, int mode) {
    PBUF;
    return DX_RET(mkfifo(P(path), mode));
}
DX_FN(mkfifo);
static int d_mknod(const char *path, int mode, int dev) {
    PBUF;
    return DX_RET(mknod(P(path), mode, dev));
}
DX_FN(mknod);
static int d_chdir(const char *path) {
    PBUF;
    return DX_RET(chdir(P(path)));
}
DX_FN(chdir);
static int d_fchdir(int fd) { return DX_RET(fchdir(fd)); }
DX_FN(fchdir);
static int d_chroot(const char *path) {
    PBUF;
    return DX_RET(chroot(P(path)));
}
DX_FN(chroot);
static char *d_getcwd(char *buf, size_t n) {
    char *r = getcwd(buf, n);
    if (!r) dx_set_errno(dx_errno_to_darwin(errno));
    return r;
}
DX_FN(getcwd);
static char *d_realpath(const char *path, char *out) {
    PBUF;
    char *r = realpath(P(path), out);
    if (!r) dx_set_errno(dx_errno_to_darwin(errno));
    return r;
}
DX_FN(realpath);
DX_EXPORT("_realpath$DARWIN_EXTSN", d_realpath);
static unsigned d_umask(unsigned m) { return umask(m); }
DX_FN(umask);
static int d_mkstemp(char *tmpl) { return DX_RET(mkstemp(tmpl)); }
DX_FN(mkstemp);
static char *d_mkdtemp(char *tmpl) {
    char *r = mkdtemp(tmpl);
    if (!r) dx_set_errno(dx_errno_to_darwin(errno));
    return r;
}
DX_FN(mkdtemp);
static int d_mkostemp(char *tmpl, int flags) { return DX_RET(mkostemp(tmpl, dx_open_flags_to_host(flags))); }
DX_FN(mkostemp);

/* ---- times -------------------------------------------------------------- */

static void tv_to_host(const struct d_timeval *d, struct timeval *h) {
    h->tv_sec = d->tv_sec;
    h->tv_usec = d->tv_usec;
}

static int d_utimes(const char *path, const struct d_timeval *tv) {
    PBUF;
    struct timeval h[2];
    if (tv) { tv_to_host(&tv[0], &h[0]); tv_to_host(&tv[1], &h[1]); }
    return DX_RET(utimes(P(path), tv ? h : NULL));
}
DX_FN(utimes);
static int d_lutimes(const char *path, const struct d_timeval *tv) {
    PBUF;
    struct timeval h[2];
    if (tv) { tv_to_host(&tv[0], &h[0]); tv_to_host(&tv[1], &h[1]); }
    return DX_RET(lutimes(P(path), tv ? h : NULL));
}
DX_FN(lutimes);
static int d_futimes(int fd, const struct d_timeval *tv) {
    struct timeval h[2];
    if (tv) { tv_to_host(&tv[0], &h[0]); tv_to_host(&tv[1], &h[1]); }
    return DX_RET(futimes(fd, tv ? h : NULL));
}
DX_FN(futimes);

/* Darwin: UTIME_NOW -1, UTIME_OMIT -2 */
static void utimens_to_host(const struct timespec *d, struct timespec *h) {
    for (int i = 0; i < 2; i++) {
        h[i] = d[i];
        if (d[i].tv_nsec == -1) h[i].tv_nsec = UTIME_NOW;
        else if (d[i].tv_nsec == -2) h[i].tv_nsec = UTIME_OMIT;
    }
}
static int d_utimensat(int dirfd, const char *path, const struct timespec *ts, int flags) {
    PBUF;
    struct timespec h[2];
    if (ts) utimens_to_host(ts, h);
    return DX_RET(utimensat(dx_at_fd(dirfd), P(path), ts ? h : NULL, dx_at_flags_to_host(flags)));
}
DX_FN(utimensat);
static int d_futimens(int fd, const struct timespec *ts) {
    struct timespec h[2];
    if (ts) utimens_to_host(ts, h);
    return DX_RET(futimens(fd, ts ? h : NULL));
}
DX_FN(futimens);

/* ---- directories -------------------------------------------------------- */

static DIR *d_opendir(const char *path) {
    PBUF;
    DIR *d = opendir(P(path));
    if (!d) dx_set_errno(dx_errno_to_darwin(errno));
    return d;
}
DX_EXPORT("_opendir", d_opendir);
DX_EXPORT("_opendir$INODE64", d_opendir);
static DIR *d_fdopendir(int fd) {
    DIR *d = fdopendir(fd);
    if (!d) dx_set_errno(dx_errno_to_darwin(errno));
    return d;
}
DX_EXPORT("_fdopendir", d_fdopendir);
DX_EXPORT("_fdopendir$INODE64", d_fdopendir);
static int d_closedir(DIR *d) { return DX_RET(closedir(d)); }
DX_FN(closedir);
static int d_dirfd(DIR *d) { return dirfd(d); }
DX_FN(dirfd);
static void d_rewinddir(DIR *d) { rewinddir(d); }
DX_EXPORT("_rewinddir", d_rewinddir);
DX_EXPORT("_rewinddir$INODE64", d_rewinddir);
static long d_telldir(DIR *d) { return telldir(d); }
DX_EXPORT("_telldir", d_telldir);
DX_EXPORT("_telldir$INODE64", d_telldir);
static void d_seekdir(DIR *d, long pos) { seekdir(d, pos); }
DX_EXPORT("_seekdir", d_seekdir);
DX_EXPORT("_seekdir$INODE64", d_seekdir);

static void dirent_from_host(const struct dirent *h, struct d_dirent *d) {
    size_t len = strlen(h->d_name);
    if (len > 1023) len = 1023;
    d->d_ino = h->d_ino;
    d->d_seekoff = h->d_off;
    d->d_namlen = len;
    d->d_type = h->d_type;
    memcpy(d->d_name, h->d_name, len);
    d->d_name[len] = 0;
    d->d_reclen = (uint16_t)((offsetof(struct d_dirent, d_name) + len + 1 + 7) & ~7);
}

static int d_readdir_r(DIR *dir, struct d_dirent *entry, struct d_dirent **result) {
    errno = 0;
    struct dirent *h = readdir(dir);
    if (!h) {
        *result = NULL;
        return errno ? dx_errno_to_darwin(errno) : 0;
    }
    dirent_from_host(h, entry);
    *result = entry;
    return 0;
}
DX_EXPORT("_readdir_r", d_readdir_r);
DX_EXPORT("_readdir_r$INODE64", d_readdir_r);

static struct d_dirent *d_readdir(DIR *dir) {
    static __thread struct d_dirent entry;
    errno = 0;
    struct dirent *h = readdir(dir);
    if (!h) {
        if (errno) dx_set_errno(dx_errno_to_darwin(errno));
        return NULL;
    }
    dirent_from_host(h, &entry);
    return &entry;
}
DX_EXPORT("_readdir", d_readdir);
DX_EXPORT("_readdir$INODE64", d_readdir);

/* ---- extended attributes, misc ------------------------------------------ */

/* Darwin adds (position, options); options bit 0 = XATTR_NOFOLLOW. */
static ssize_t d_getxattr(const char *path, const char *name, void *value, size_t size,
                          uint32_t position, int options) {
    PBUF;
    (void)position;
    return DX_RET((options & 1) ? lgetxattr(P(path), name, value, size)
                                : getxattr(P(path), name, value, size));
}
DX_FN(getxattr);
static ssize_t d_fgetxattr(int fd, const char *name, void *value, size_t size, uint32_t position,
                           int options) {
    (void)position; (void)options;
    return DX_RET(fgetxattr(fd, name, value, size));
}
DX_FN(fgetxattr);
static int d_setxattr(const char *path, const char *name, const void *value, size_t size,
                      uint32_t position, int options) {
    PBUF;
    (void)position;
    int flags = ((options & 2) ? XATTR_CREATE : 0) | ((options & 4) ? XATTR_REPLACE : 0);
    return DX_RET((options & 1) ? lsetxattr(P(path), name, value, size, flags)
                                : setxattr(P(path), name, value, size, flags));
}
DX_FN(setxattr);
static ssize_t d_listxattr(const char *path, char *list, size_t size, int options) {
    PBUF;
    return DX_RET((options & 1) ? llistxattr(P(path), list, size) : listxattr(P(path), list, size));
}
DX_FN(listxattr);
static int d_removexattr(const char *path, const char *name, int options) {
    PBUF;
    return DX_RET((options & 1) ? lremovexattr(P(path), name) : removexattr(P(path), name));
}
DX_FN(removexattr);

static int d_fsctl(const char *path, unsigned long req, void *data, unsigned opts) {
    (void)path; (void)req; (void)data; (void)opts;
    dx_set_errno(45); /* ENOTSUP */
    return -1;
}
DX_FN(fsctl);
static int d_getattrlist(const char *path, void *attrs, void *buf, size_t size, unsigned opts) {
    (void)path; (void)attrs; (void)buf; (void)size; (void)opts;
    dx_set_errno(45);
    return -1;
}
DX_FN(getattrlist);
static int d_clonefile(const char *src, const char *dst, int flags) {
    (void)src; (void)dst; (void)flags;
    dx_set_errno(45);
    return -1;
}
DX_FN(clonefile);

static int d_shm_open(const char *name, int flags, int mode) {
    return DX_RET(shm_open(name, dx_open_flags_to_host(flags), mode));
}
DX_FN(shm_open);
static int d_shm_unlink(const char *name) { return DX_RET(shm_unlink(name)); }
DX_FN(shm_unlink);

/* Darwin: sendfile(fd, socket, offset, &len, hdtr, flags); len is in/out. */
static int d_sendfile(int fd, int s, off_t offset, off_t *len, void *hdtr, int flags) {
    (void)hdtr; (void)flags;
    off_t want = len ? *len : 0;
    off_t sent = 0;
    int rc = 0;
    if (!want) {
        struct stat st;
        if (fstat(fd, &st) < 0) return DX_RET(-1);
        want = st.st_size > offset ? st.st_size - offset : 0;
    }
    while (sent < want) {
        off_t off = offset + sent;
        ssize_t n = sendfile(s, fd, &off, want - sent);
        if (n < 0) {
            dx_set_errno(dx_errno_to_darwin(errno));
            rc = -1;
            break;
        }
        if (n == 0) break;
        sent += n;
    }
    if (len) *len = sent;
    return rc;
}
DX_FN(sendfile);
