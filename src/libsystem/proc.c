/* Processes: ids, fork/exec, posix_spawn, wait, limits, users. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <limits.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "darwin_abi.h"
#include "dx.h"

/* ---- identity ----------------------------------------------------------- */

static int d_getpid(void) { return getpid(); }
DX_FN(getpid);
static int d_getppid(void) { return getppid(); }
DX_FN(getppid);
static unsigned d_getuid(void) { return getuid(); }
DX_FN(getuid);
static unsigned d_geteuid(void) { return geteuid(); }
DX_FN(geteuid);
static unsigned d_getgid(void) { return getgid(); }
DX_FN(getgid);
static unsigned d_getegid(void) { return getegid(); }
DX_FN(getegid);
static int d_setuid(unsigned u) { return DX_RET(setuid(u)); }
DX_FN(setuid);
static int d_setgid(unsigned g) { return DX_RET(setgid(g)); }
DX_FN(setgid);
static int d_seteuid(unsigned u) { return DX_RET(seteuid(u)); }
DX_FN(seteuid);
static int d_setegid(unsigned g) { return DX_RET(setegid(g)); }
DX_FN(setegid);
static int d_setreuid(unsigned r, unsigned e) { return DX_RET(setreuid(r, e)); }
DX_FN(setreuid);
static int d_setregid(unsigned r, unsigned e) { return DX_RET(setregid(r, e)); }
DX_FN(setregid);
static int d_setsid(void) { return DX_RET(setsid()); }
DX_FN(setsid);
static int d_getsid(int pid) { return DX_RET(getsid(pid)); }
DX_FN(getsid);
static int d_setpgid(int pid, int pgid) { return DX_RET(setpgid(pid, pgid)); }
DX_FN(setpgid);
static int d_getpgid(int pid) { return DX_RET(getpgid(pid)); }
DX_FN(getpgid);
static int d_getpgrp(void) { return getpgrp(); }
DX_FN(getpgrp);
static int d_getgroups(int n, gid_t *list) { return DX_RET(getgroups(n, list)); }
DX_FN(getgroups);
static int d_setgroups(int n, const gid_t *list) { return DX_RET(setgroups(n, list)); }
DX_FN(setgroups);
static int d_getgrouplist(const char *name, int basegid, int *groups, int *ngroups) {
    return getgrouplist(name, basegid, (gid_t *)groups, ngroups);
}
DX_FN(getgrouplist);
static int d_getpriority(int which, unsigned who) { return DX_RET(getpriority(which, who)); }
DX_FN(getpriority);
static int d_setpriority(int which, unsigned who, int prio) { return DX_RET(setpriority(which, who, prio)); }
DX_FN(setpriority);
static int d_nice(int n) { return DX_RET(nice(n)); }
DX_FN(nice);
static char *d_getlogin(void) {
    struct passwd *pw = getpwuid(getuid());
    return pw ? pw->pw_name : "root";
}
DX_FN(getlogin);
static int d_gethostname(char *buf, size_t n) { return DX_RET(gethostname(buf, n)); }
DX_FN(gethostname);
static int d_getpagesize(void) { return 4096; }
DX_FN(getpagesize);
static int d_getdtablesize(void) { return getdtablesize(); }
DX_FN(getdtablesize);

/* ---- passwd / group ------------------------------------------------------ */

struct d_passwd {
    char *pw_name, *pw_passwd;
    uint32_t pw_uid, pw_gid;
    long pw_change;
    char *pw_class, *pw_gecos, *pw_dir, *pw_shell;
    long pw_expire;
};

static void passwd_from_host(const struct passwd *h, struct d_passwd *d) {
    d->pw_name = h->pw_name;
    d->pw_passwd = h->pw_passwd;
    d->pw_uid = h->pw_uid;
    d->pw_gid = h->pw_gid;
    d->pw_change = 0;
    d->pw_class = (char *)"";
    d->pw_gecos = h->pw_gecos;
    d->pw_dir = h->pw_dir;
    d->pw_shell = h->pw_shell;
    d->pw_expire = 0;
}

static int d_getpwuid_r(unsigned uid, struct d_passwd *pwd, char *buf, size_t n, struct d_passwd **res) {
    struct passwd h, *hr = NULL;
    int r = getpwuid_r(uid, &h, buf, n, &hr);
    *res = NULL;
    if (r) return dx_errno_to_darwin(r);
    if (hr) { passwd_from_host(&h, pwd); *res = pwd; }
    return 0;
}
DX_FN(getpwuid_r);
static int d_getpwnam_r(const char *name, struct d_passwd *pwd, char *buf, size_t n, struct d_passwd **res) {
    struct passwd h, *hr = NULL;
    int r = getpwnam_r(name, &h, buf, n, &hr);
    *res = NULL;
    if (r) return dx_errno_to_darwin(r);
    if (hr) { passwd_from_host(&h, pwd); *res = pwd; }
    return 0;
}
DX_FN(getpwnam_r);
static struct d_passwd *d_getpwuid(unsigned uid) {
    static __thread struct d_passwd d;
    struct passwd *h = getpwuid(uid);
    if (!h) return NULL;
    passwd_from_host(h, &d);
    return &d;
}
DX_FN(getpwuid);
static struct d_passwd *d_getpwnam(const char *name) {
    static __thread struct d_passwd d;
    struct passwd *h = getpwnam(name);
    if (!h) return NULL;
    passwd_from_host(h, &d);
    return &d;
}
DX_FN(getpwnam);
/* struct group has the same layout on both systems. */
static int d_getgrgid_r(unsigned gid, struct group *grp, char *buf, size_t n, struct group **res) {
    return dx_errno_to_darwin(getgrgid_r(gid, grp, buf, n, res));
}
DX_FN(getgrgid_r);
static int d_getgrnam_r(const char *name, struct group *grp, char *buf, size_t n, struct group **res) {
    return dx_errno_to_darwin(getgrnam_r(name, grp, buf, n, res));
}
DX_FN(getgrnam_r);
DX_PASS(getgrgid);
DX_PASS(getgrnam);

/* ---- limits / usage ------------------------------------------------------ */

#define D_RLIM_INFINITY 0x7fffffffffffffffULL
static int rlimit_to_host(int d) {
    switch (d) {
    case 0: return RLIMIT_CPU;
    case 1: return RLIMIT_FSIZE;
    case 2: return RLIMIT_DATA;
    case 3: return RLIMIT_STACK;
    case 4: return RLIMIT_CORE;
    case 5: return RLIMIT_AS;
    case 6: return RLIMIT_MEMLOCK;
    case 7: return RLIMIT_NPROC;
    case 8: return RLIMIT_NOFILE;
    }
    return -1;
}
struct d_rlimit {
    uint64_t cur, max;
};
static int d_getrlimit(int res, struct d_rlimit *out) {
    int hr = rlimit_to_host(res & 0xff);
    if (hr < 0) { dx_set_errno(22); return -1; }
    struct rlimit l;
    int r = getrlimit(hr, &l);
    if (r == 0) {
        out->cur = l.rlim_cur == RLIM_INFINITY ? D_RLIM_INFINITY : l.rlim_cur;
        out->max = l.rlim_max == RLIM_INFINITY ? D_RLIM_INFINITY : l.rlim_max;
    }
    return DX_RET(r);
}
DX_FN(getrlimit);
static int d_setrlimit(int res, const struct d_rlimit *in) {
    int hr = rlimit_to_host(res & 0xff);
    if (hr < 0) { dx_set_errno(22); return -1; }
    struct rlimit l;
    l.rlim_cur = in->cur >= D_RLIM_INFINITY ? RLIM_INFINITY : in->cur;
    l.rlim_max = in->max >= D_RLIM_INFINITY ? RLIM_INFINITY : in->max;
    return DX_RET(setrlimit(hr, &l));
}
DX_FN(setrlimit);

/* struct rusage shares its layout; ru_maxrss is bytes on Darwin, KiB on Linux. */
static int d_getrusage(int who, struct rusage *ru) {
    int r = getrusage(who, ru);
    if (r == 0) ru->ru_maxrss *= 1024;
    return DX_RET(r);
}
DX_FN(getrusage);

/* ---- wait ---------------------------------------------------------------- */

int dx_wait_status_from_host(int s) {
    if (WIFEXITED(s)) return s;
    if (WIFSIGNALED(s)) return (s & ~0x7f) | dx_sig_from_host(WTERMSIG(s));
    if (WIFSTOPPED(s)) return (dx_sig_from_host(WSTOPSIG(s)) << 8) | 0x7f;
    if (WIFCONTINUED(s)) return (19 << 8) | 0x7f; /* Darwin: stopped with SIGCONT */
    return s;
}

static int wait_options_to_host(int d) {
    int h = 0;
    if (d & 1) h |= WNOHANG;
    if (d & 2) h |= WUNTRACED;
    if (d & 0x10) h |= WCONTINUED;
    return h;
}

static int d_wait4(int pid, int *status, int options, struct rusage *ru) {
    int st = 0;
    int r = wait4(pid, &st, wait_options_to_host(options), ru);
    if (r > 0) {
        if (status) *status = dx_wait_status_from_host(st);
        if (ru) ru->ru_maxrss *= 1024;
    }
    return DX_RET(r);
}
DX_FN(wait4);
static int d_waitpid(int pid, int *status, int options) { return d_wait4(pid, status, options, NULL); }
DX_FN(waitpid);
DX_EXPORT("_waitpid$NOCANCEL", d_waitpid);
static int d_wait(int *status) { return d_wait4(-1, status, 0, NULL); }
DX_FN(wait);

/* ---- fork / exec --------------------------------------------------------- */

static int d_fork(void) { return DX_RET(fork()); }
DX_FN(fork);
DX_EXPORT("_vfork", d_fork);

static int count_args(char *const argv[]) {
    int n = 0;
    while (argv && argv[n]) n++;
    return n;
}

/* execve that understands Mach-O targets: they are re-entered through the
 * loader, everything else (ELF programs, scripts) is run by the kernel. */
static int exec_any(const char *path, char *const argv[], char *const envp[]) {
    char pbuf[PATH_MAX];
    const char *p = dx_path(path, pbuf, sizeof pbuf);
    if (!dx_is_macho_file(p)) return execve(p, argv, envp);
    int n = count_args(argv);
    char **nargv = alloca((n + 6) * sizeof(char *));
    int k = 0;
    nargv[k++] = (char *)dx_loader_path();
    if (n > 0) {
        nargv[k++] = (char *)"--argv0";
        nargv[k++] = argv[0];
    }
    nargv[k++] = (char *)"--";
    nargv[k++] = (char *)p;
    for (int i = 1; i < n; i++) nargv[k++] = argv[i];
    nargv[k] = NULL;
    return execve(dx_loader_path(), nargv, envp);
}

static int d_execve(const char *path, char *const argv[], char *const envp[]) {
    return DX_RET(exec_any(path, argv, envp));
}
DX_FN(execve);
static int d_execv(const char *path, char *const argv[]) { return DX_RET(exec_any(path, argv, environ)); }
DX_FN(execv);

static int search_path(const char *file, char *out) {
    if (strchr(file, '/')) {
        snprintf(out, PATH_MAX, "%s", file);
        return 0;
    }
    const char *path = getenv("PATH");
    if (!path) path = "/usr/local/bin:/usr/bin:/bin";
    while (*path) {
        const char *colon = strchrnul(path, ':');
        int len = (int)(colon - path);
        if (len == 0) snprintf(out, PATH_MAX, "./%s", file);
        else snprintf(out, PATH_MAX, "%.*s/%s", len, path, file);
        if (access(out, X_OK) == 0) return 0;
        path = *colon ? colon + 1 : colon;
    }
    errno = ENOENT;
    return -1;
}

static int d_execvp(const char *file, char *const argv[]) {
    char path[PATH_MAX];
    if (search_path(file, path) < 0) return DX_RET(-1);
    return DX_RET(exec_any(path, argv, environ));
}
DX_FN(execvp);

static int d_execl(const char *path, const char *arg0, ...) {
    char *argv[256];
    int n = 0;
    va_list ap;
    va_start(ap, arg0);
    for (const char *a = arg0; a && n < 255; a = va_arg(ap, const char *)) argv[n++] = (char *)a;
    va_end(ap);
    argv[n] = NULL;
    return DX_RET(exec_any(path, argv, environ));
}
DX_FN(execl);
static int d_execlp(const char *file, const char *arg0, ...) {
    char *argv[256];
    int n = 0;
    va_list ap;
    va_start(ap, arg0);
    for (const char *a = arg0; a && n < 255; a = va_arg(ap, const char *)) argv[n++] = (char *)a;
    va_end(ap);
    argv[n] = NULL;
    return d_execvp(file, argv);
}
DX_FN(execlp);

static int d_system(const char *cmd) {
    int r = system(cmd);
    return r < 0 ? DX_RET(r) : dx_wait_status_from_host(r);
}
DX_FN(system);
static int d_daemon(int nochdir, int noclose) { return DX_RET(daemon(nochdir, noclose)); }
DX_FN(daemon);

/* ---- posix_spawn ---------------------------------------------------------
 * Darwin's posix_spawnattr_t and posix_spawn_file_actions_t are opaque
 * pointers; ours point at these structures. */
#define D_POSIX_SPAWN_RESETIDS 0x0001
#define D_POSIX_SPAWN_SETPGROUP 0x0002
#define D_POSIX_SPAWN_SETSIGDEF 0x0004
#define D_POSIX_SPAWN_SETSIGMASK 0x0008
#define D_POSIX_SPAWN_SETEXEC 0x0040
#define D_POSIX_SPAWN_START_SUSPENDED 0x0080
#define D_POSIX_SPAWN_SETSID 0x0400
#define D_POSIX_SPAWN_CLOEXEC_DEFAULT 0x4000

struct spawn_attr {
    short flags;
    int pgroup;
    uint32_t sigdefault, sigmask;
};

enum { FA_OPEN, FA_DUP2, FA_CLOSE, FA_CHDIR, FA_FCHDIR, FA_INHERIT };
struct file_action {
    int kind, fd, newfd, oflag, mode;
    char *path;
};
struct file_actions {
    int n, cap;
    struct file_action *a;
};

static int d_posix_spawnattr_init(struct spawn_attr **attr) {
    *attr = calloc(1, sizeof **attr);
    return *attr ? 0 : 12;
}
DX_FN(posix_spawnattr_init);
static int d_posix_spawnattr_destroy(struct spawn_attr **attr) {
    free(*attr);
    *attr = NULL;
    return 0;
}
DX_FN(posix_spawnattr_destroy);
static int d_posix_spawnattr_setflags(struct spawn_attr **attr, short flags) { (*attr)->flags = flags; return 0; }
DX_FN(posix_spawnattr_setflags);
static int d_posix_spawnattr_getflags(struct spawn_attr **attr, short *flags) { *flags = (*attr)->flags; return 0; }
DX_FN(posix_spawnattr_getflags);
static int d_posix_spawnattr_setsigdefault(struct spawn_attr **attr, const uint32_t *set) { (*attr)->sigdefault = *set; return 0; }
DX_FN(posix_spawnattr_setsigdefault);
static int d_posix_spawnattr_setsigmask(struct spawn_attr **attr, const uint32_t *set) { (*attr)->sigmask = *set; return 0; }
DX_FN(posix_spawnattr_setsigmask);
static int d_posix_spawnattr_setpgroup(struct spawn_attr **attr, int pgroup) { (*attr)->pgroup = pgroup; return 0; }
DX_FN(posix_spawnattr_setpgroup);
static int d_posix_spawnattr_setbinpref_np(void *attr, size_t n, void *pref, size_t *o) { (void)attr; (void)pref; if (o) *o = n; return 0; }
DX_FN(posix_spawnattr_setbinpref_np);
static int d_posix_spawnattr_set_qos_class_np(void *attr, int qos) { (void)attr; (void)qos; return 0; }
DX_FN(posix_spawnattr_set_qos_class_np);
static int d_responsibility_spawnattrs_setdisclaim(void *attr, int disclaim) { (void)attr; (void)disclaim; return 0; }
DX_FN(responsibility_spawnattrs_setdisclaim);
static int d_responsibility_get_pid_responsible_for_pid(int pid) { return pid; }
DX_FN(responsibility_get_pid_responsible_for_pid);

static int d_posix_spawn_file_actions_init(struct file_actions **fa) {
    *fa = calloc(1, sizeof **fa);
    return *fa ? 0 : 12;
}
DX_FN(posix_spawn_file_actions_init);
static int d_posix_spawn_file_actions_destroy(struct file_actions **fa) {
    if (*fa) {
        for (int i = 0; i < (*fa)->n; i++) free((*fa)->a[i].path);
        free((*fa)->a);
        free(*fa);
    }
    *fa = NULL;
    return 0;
}
DX_FN(posix_spawn_file_actions_destroy);

static struct file_action *fa_add(struct file_actions **fap) {
    struct file_actions *fa = *fap;
    if (fa->n == fa->cap) {
        fa->cap = fa->cap ? fa->cap * 2 : 8;
        fa->a = realloc(fa->a, fa->cap * sizeof *fa->a);
    }
    struct file_action *a = &fa->a[fa->n++];
    memset(a, 0, sizeof *a);
    return a;
}
static int d_posix_spawn_file_actions_addopen(struct file_actions **fa, int fd, const char *path, int oflag, int mode) {
    struct file_action *a = fa_add(fa);
    a->kind = FA_OPEN; a->fd = fd; a->path = strdup(path); a->oflag = oflag; a->mode = mode;
    return 0;
}
DX_FN(posix_spawn_file_actions_addopen);
static int d_posix_spawn_file_actions_adddup2(struct file_actions **fa, int fd, int newfd) {
    struct file_action *a = fa_add(fa);
    a->kind = FA_DUP2; a->fd = fd; a->newfd = newfd;
    return 0;
}
DX_FN(posix_spawn_file_actions_adddup2);
static int d_posix_spawn_file_actions_addclose(struct file_actions **fa, int fd) {
    struct file_action *a = fa_add(fa);
    a->kind = FA_CLOSE; a->fd = fd;
    return 0;
}
DX_FN(posix_spawn_file_actions_addclose);
static int d_posix_spawn_file_actions_addchdir_np(struct file_actions **fa, const char *path) {
    struct file_action *a = fa_add(fa);
    a->kind = FA_CHDIR; a->path = strdup(path);
    return 0;
}
DX_FN(posix_spawn_file_actions_addchdir_np);
static int d_posix_spawn_file_actions_addfchdir_np(struct file_actions **fa, int fd) {
    struct file_action *a = fa_add(fa);
    a->kind = FA_FCHDIR; a->fd = fd;
    return 0;
}
DX_FN(posix_spawn_file_actions_addfchdir_np);
static int d_posix_spawn_file_actions_addinherit_np(struct file_actions **fa, int fd) {
    struct file_action *a = fa_add(fa);
    a->kind = FA_INHERIT; a->fd = fd;
    return 0;
}
DX_FN(posix_spawn_file_actions_addinherit_np);

/* Runs in the child (or in place for SETEXEC). Returns only on failure,
 * with a host errno. */
static int spawn_child(const char *path, struct file_actions *fa, struct spawn_attr *at,
                       char *const argv[], char *const envp[], int use_path) {
    short flags = at ? at->flags : 0;
    if (flags & D_POSIX_SPAWN_SETSID) setsid();
    if (flags & D_POSIX_SPAWN_SETPGROUP) setpgid(0, at->pgroup);
    if (flags & D_POSIX_SPAWN_RESETIDS) {
        if (setgid(getgid()) < 0 || setuid(getuid()) < 0) return errno;
    }
    if (flags & D_POSIX_SPAWN_SETSIGDEF) {
        for (int d = 1; d < 32; d++)
            if (at->sigdefault & (1u << (d - 1))) signal(dx_sig_to_host(d), SIG_DFL);
    }
    sigset_t mask;
    if (flags & D_POSIX_SPAWN_SETSIGMASK) dx_sigset_to_host(at->sigmask, &mask);
    else sigemptyset(&mask);
    if (flags & D_POSIX_SPAWN_SETSIGMASK) sigprocmask(SIG_SETMASK, &mask, NULL);

    unsigned char keep[1024] = {0};
    for (int i = 0; fa && i < fa->n; i++) {
        struct file_action *a = &fa->a[i];
        char pbuf[PATH_MAX];
        switch (a->kind) {
        case FA_OPEN: {
            int fd = open(dx_path(a->path, pbuf, sizeof pbuf), dx_open_flags_to_host(a->oflag), a->mode);
            if (fd < 0) return errno;
            if (fd != a->fd) {
                if (dup2(fd, a->fd) < 0) return errno;
                close(fd);
            }
            if (a->fd >= 0 && a->fd < 1024) keep[a->fd] = 1;
            break;
        }
        case FA_DUP2:
            if (a->fd == a->newfd) {
                int f = fcntl(a->fd, F_GETFD);
                if (f < 0) return errno;
                fcntl(a->fd, F_SETFD, f & ~FD_CLOEXEC);
            } else if (dup2(a->fd, a->newfd) < 0) return errno;
            if (a->newfd >= 0 && a->newfd < 1024) keep[a->newfd] = 1;
            break;
        case FA_CLOSE:
            close(a->fd);
            break;
        case FA_CHDIR:
            if (chdir(dx_path(a->path, pbuf, sizeof pbuf)) < 0) return errno;
            break;
        case FA_FCHDIR:
            if (fchdir(a->fd) < 0) return errno;
            break;
        case FA_INHERIT: {
            int f = fcntl(a->fd, F_GETFD);
            if (f >= 0) fcntl(a->fd, F_SETFD, f & ~FD_CLOEXEC);
            if (a->fd >= 0 && a->fd < 1024) keep[a->fd] = 1;
            break;
        }
        }
    }
    if (flags & D_POSIX_SPAWN_CLOEXEC_DEFAULT) {
        /* only descriptors named by file actions survive (plus the error pipe,
         * which is already close-on-exec) */
        for (int fd = 0; fd < 1024; fd++) {
            if (keep[fd]) continue;
            int f = fcntl(fd, F_GETFD);
            if (f >= 0) fcntl(fd, F_SETFD, f | FD_CLOEXEC);
        }
    }
    char found[PATH_MAX];
    if (use_path) {
        if (search_path(path, found) < 0) return errno;
        path = found;
    }
    exec_any(path, argv, envp ? envp : environ);
    return errno;
}

static int do_spawn(int *pid_out, const char *path, struct file_actions **fap,
                    struct spawn_attr **atp, char *const argv[], char *const envp[], int use_path) {
    struct file_actions *fa = fap ? *fap : NULL;
    struct spawn_attr *at = atp ? *atp : NULL;
    if (at && (at->flags & D_POSIX_SPAWN_SETEXEC))
        return dx_errno_to_darwin(spawn_child(path, fa, at, argv, envp, use_path));
    int pfd[2];
    if (pipe2(pfd, O_CLOEXEC) < 0) return dx_errno_to_darwin(errno);
    pid_t pid = fork();
    if (pid < 0) {
        int e = errno;
        close(pfd[0]);
        close(pfd[1]);
        return dx_errno_to_darwin(e);
    }
    if (pid == 0) {
        close(pfd[0]);
        int e = spawn_child(path, fa, at, argv, envp, use_path);
        ssize_t w = write(pfd[1], &e, sizeof e);
        (void)w;
        _exit(127);
    }
    close(pfd[1]);
    int err = 0;
    ssize_t n;
    do n = read(pfd[0], &err, sizeof err);
    while (n < 0 && errno == EINTR);
    close(pfd[0]);
    if (n == sizeof err) {
        int st;
        waitpid(pid, &st, 0);
        return dx_errno_to_darwin(err);
    }
    if (pid_out) *pid_out = pid;
    return 0;
}

static int d_posix_spawn(int *pid, const char *path, struct file_actions **fa, struct spawn_attr **at,
                         char *const argv[], char *const envp[]) {
    return do_spawn(pid, path, fa, at, argv, envp, 0);
}
DX_FN(posix_spawn);
static int d_posix_spawnp(int *pid, const char *file, struct file_actions **fa, struct spawn_attr **at,
                          char *const argv[], char *const envp[]) {
    return do_spawn(pid, file, fa, at, argv, envp, 1);
}
DX_FN(posix_spawnp);

static int d_ptrace(int req, int pid, void *addr, int data) {
    (void)req; (void)pid; (void)addr; (void)data;
    dx_set_errno(78); /* ENOSYS */
    return -1;
}
DX_FN(ptrace);
