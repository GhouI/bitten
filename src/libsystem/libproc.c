#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#include "darwin_abi.h"
#include "dx.h"

enum {
    PROC_ALL_PIDS = 1, PROC_PGRP_ONLY, PROC_TTY_ONLY, PROC_UID_ONLY, PROC_RUID_ONLY, PROC_PPID_ONLY,
    PROC_PIDLISTFDS = 1, PROC_PIDTBSDINFO = 3, PROC_PIDTASKINFO = 4, PROC_PIDVNODEPATHINFO = 9,
    PROC_PIDT_SHORTBSDINFO = 13, PROC_PIDFDVNODEPATHINFO = 2,
    PROX_FDTYPE_VNODE = 1, PROX_FDTYPE_SOCKET = 2, PROX_FDTYPE_KQUEUE = 5, PROX_FDTYPE_PIPE = 6,
    KERN_PROC = 14, KERN_PROCARGS = 38, KERN_PROCARGS2 = 49, KERN_PROC_ALL = 0, KERN_PROC_PID = 1,
    D_MAXPATHLEN = 1024, D_MAXCOMLEN = 16,
};

struct d_proc_bsdinfo {
    uint32_t pbi_flags, pbi_status, pbi_xstatus, pbi_pid, pbi_ppid;
    uint32_t pbi_uid, pbi_gid, pbi_ruid, pbi_rgid, pbi_svuid, pbi_svgid, reserved;
    char pbi_comm[D_MAXCOMLEN], pbi_name[2 * D_MAXCOMLEN];
    uint32_t pbi_nfiles, pbi_pgid, pbi_pjobc, e_tdev, e_tpgid;
    int32_t pbi_nice;
    uint64_t pbi_start_tvsec, pbi_start_tvusec;
};
struct d_proc_bsdshortinfo {
    uint32_t pbsi_pid, pbsi_ppid, pbsi_pgid, pbsi_status;
    char pbsi_comm[D_MAXCOMLEN];
    uint32_t pbsi_flags, pbsi_uid, pbsi_gid, pbsi_ruid, pbsi_rgid, pbsi_svuid, pbsi_svgid, reserved;
};
struct d_proc_taskinfo {
    uint64_t pti_virtual_size, pti_resident_size, pti_total_user, pti_total_system;
    uint64_t pti_threads_user, pti_threads_system;
    int32_t pti_policy, pti_faults, pti_pageins, pti_cow_faults;
    int32_t pti_messages_sent, pti_messages_received, pti_syscalls_mach, pti_syscalls_unix;
    int32_t pti_csw, pti_threadnum, pti_numrunning, pti_priority;
};
struct d_vinfo_stat {
    uint32_t dev;
    uint16_t mode, nlink;
    uint64_t ino;
    uint32_t uid, gid;
    struct timespec atime, mtime, ctime, birthtime;
    int64_t size, blocks;
    int32_t blksize;
    uint32_t flags, gen, rdev;
    int64_t reserved[2];
};
struct d_vnode_info {
    struct d_vinfo_stat vi_stat;
    int32_t vi_type, reserved;
    int32_t vi_fsid[2];
};
struct d_vnode_info_path {
    struct d_vnode_info vip_vi;
    char vip_path[D_MAXPATHLEN];
};
struct d_proc_vnodepathinfo {
    struct d_vnode_info_path pvi_cdir, pvi_rdir;
};
struct d_proc_fileinfo {
    uint32_t fi_openflags, fi_status;
    int64_t fi_offset;
    int32_t fi_type;
    uint32_t fi_guardflags;
};
struct d_vnode_fdinfowithpath {
    struct d_proc_fileinfo pfi;
    struct d_vnode_info_path pvip;
};
struct d_proc_fdinfo {
    int32_t proc_fd;
    uint32_t proc_fdtype;
};

_Static_assert(sizeof(struct d_proc_bsdinfo) == 136, "proc_bsdinfo layout");
_Static_assert(sizeof(struct d_proc_bsdshortinfo) == 64, "proc_bsdshortinfo layout");
_Static_assert(sizeof(struct d_proc_taskinfo) == 96, "proc_taskinfo layout");
_Static_assert(sizeof(struct d_proc_vnodepathinfo) == 2352, "proc_vnodepathinfo layout");
_Static_assert(sizeof(struct d_vnode_fdinfowithpath) == 1200, "vnode_fdinfowithpath layout");
_Static_assert(sizeof(struct d_proc_fdinfo) == 8, "proc_fdinfo layout");

struct d_extern_proc {
    union {
        struct { uint64_t forward, back; } links;
        struct d_timeval start;
    } p_un;
    uint64_t p_vmspace, p_sigacts;
    int32_t p_flag;
    uint8_t p_stat;
    int32_t p_pid, p_oppid, p_dupfd;
    uint64_t user_stack, exit_thread;
    int32_t p_debugger, sigwait;
    uint32_t p_estcpu;
    int32_t p_cpticks;
    uint32_t p_pctcpu;
    uint64_t p_wchan, p_wmesg;
    uint32_t p_swtime, p_slptime;
    struct { struct d_timeval interval, value; } p_realtimer;
    struct d_timeval p_rtime;
    uint64_t p_uticks, p_sticks, p_iticks;
    int32_t p_traceflag;
    uint64_t p_tracep;
    int32_t p_siglist;
    uint64_t p_textvp;
    int32_t p_holdcnt;
    uint32_t p_sigmask, p_sigignore, p_sigcatch;
    uint8_t p_priority, p_usrpri;
    int8_t p_nice;
    char p_comm[D_MAXCOMLEN + 1];
    uint64_t p_pgrp, p_addr;
    uint16_t p_xstat, p_acflag;
    uint64_t p_ru;
};

struct d_pcred {
    uint8_t pc_lock[72];
    uint64_t pc_ucred;
    uint32_t p_ruid, p_svuid, p_rgid, p_svgid;
    int32_t p_refcnt;
};
struct d_ucred {
    int32_t cr_ref;
    uint32_t cr_uid;
    int16_t cr_ngroups;
    uint32_t cr_groups[16];
};
struct d_vmspace {
    int32_t vm_refcnt;
    uint64_t vm_shm;
    int32_t vm_rssize, vm_swrss, vm_tsize, vm_dsize, vm_ssize;
    uint64_t vm_taddr, vm_daddr, vm_maxsaddr;
};
struct d_eproc {
    uint64_t e_paddr, e_sess;
    struct d_pcred e_pcred;
    struct d_ucred e_ucred;
    struct d_vmspace e_vm;
    int32_t e_ppid, e_pgid;
    int16_t e_jobc;
    int32_t e_tdev, e_tpgid;
    uint64_t e_tsess;
    char e_wmesg[8];
    int32_t e_xsize;
    int16_t e_xrssize, e_xccount, e_xswrss;
    int32_t e_flag;
    char e_login[12];
    int32_t e_spare[4];
};
struct d_kinfo_proc {
    struct d_extern_proc kp_proc;
    struct d_eproc kp_eproc;
};

_Static_assert(sizeof(struct d_kinfo_proc) == 648, "kinfo_proc layout");
_Static_assert(offsetof(struct d_kinfo_proc, kp_proc.p_stat) == 36, "kinfo_proc status");
_Static_assert(offsetof(struct d_kinfo_proc, kp_proc.p_pid) == 40, "kinfo_proc pid");
_Static_assert(offsetof(struct d_kinfo_proc, kp_proc.p_comm) == 243, "kinfo_proc command");
_Static_assert(offsetof(struct d_kinfo_proc, kp_eproc.e_pcred.p_ruid) == 392, "kinfo_proc ruid");
_Static_assert(offsetof(struct d_kinfo_proc, kp_eproc.e_pcred.p_rgid) == 400, "kinfo_proc rgid");
_Static_assert(offsetof(struct d_kinfo_proc, kp_eproc.e_ucred.cr_uid) == 420, "kinfo_proc uid");
_Static_assert(offsetof(struct d_kinfo_proc, kp_eproc.e_ppid) == 560, "kinfo_proc ppid");
_Static_assert(offsetof(struct d_kinfo_proc, kp_eproc.e_pgid) == 564, "kinfo_proc pgid");
_Static_assert(offsetof(struct d_kinfo_proc, kp_eproc.e_tdev) == 572, "kinfo_proc tty");

struct proc_stat {
    char comm[D_MAXCOMLEN + 1], state;
    int pid, ppid, pgid, session, tty, tpgid, priority, nice, threads, exit_status;
    uint64_t minflt, majflt, utime, stime, start, vsize;
    int64_t rss;
};
struct proc_creds {
    unsigned ruid, uid, svuid, rgid, gid, svgid, tracer;
    uint32_t sig_pending, sig_mask, sig_ignore, sig_catch;
};

static int proc_error(int error, int result) {
    dx_set_errno(dx_errno_to_darwin(error));
    return result;
}

static FILE *proc_open(int pid, const char *entry) {
    if (pid <= 0) { errno = ESRCH; return NULL; }
    char path[64];
    snprintf(path, sizeof path, "/proc/%d/%s", pid, entry);
    FILE *f = fopen(path, "re");
    if (!f && errno == ENOENT) errno = ESRCH;
    return f;
}

static int proc_link(int pid, const char *entry, char *buffer, size_t capacity) {
    if (pid <= 0) { errno = ESRCH; return -1; }
    if (!buffer || !capacity) { errno = EINVAL; return -1; }
    char path[64];
    snprintf(path, sizeof path, "/proc/%d/%s", pid, entry);
    ssize_t size = readlink(path, buffer, capacity);
    if (size < 0) {
        if (errno == ENOENT) errno = ESRCH;
        return -1;
    }
    if ((size_t)size == capacity) { errno = ENOMEM; return -1; }
    buffer[size] = 0;
    return size;
}

static int proc_read_stat(int pid, struct proc_stat *s) {
    FILE *f = proc_open(pid, "stat");
    if (!f) return -1;
    char line[4096];
    /* comm can contain spaces, parentheses and newlines. Read the whole record. */
    size_t n = fread(line, 1, sizeof line - 1, f);
    int error = ferror(f) ? errno : 0;
    fclose(f);
    if (error) { errno = error; return -1; }
    if (!n) { errno = ESRCH; return -1; }
    line[n] = 0;
    char *start = strchr(line, '('), *end = strrchr(line, ')');
    if (!start || !end || start >= end || !end[1] || !end[2] || end[3] != ' ') {
        errno = EIO;
        return -1;
    }

    *s = (struct proc_stat){.pid = pid, .state = end[2]};
    size_t len = end - start - 1;
    if (len > D_MAXCOMLEN) len = D_MAXCOMLEN;
    memcpy(s->comm, start + 1, len);
    char *p = end + 4;
    /* Field numbers follow proc_pid_stat(5). The fields after rss are optional here. */
    for (int field = 4; field <= 52; field++) {
        char *next;
        uint64_t value = strtoull(p, &next, 10);
        if (next == p) {
            if (field > 24) break;
            errno = EIO;
            return -1;
        }
        p = next;
        switch (field) {
        case 4: s->ppid = (int)value; break;
        case 5: s->pgid = (int)value; break;
        case 6: s->session = (int)value; break;
        case 7: s->tty = (int)value; break;
        case 8: s->tpgid = (int)value; break;
        case 10: s->minflt = value; break;
        case 12: s->majflt = value; break;
        case 14: s->utime = value; break;
        case 15: s->stime = value; break;
        case 18: s->priority = (int)value; break;
        case 19: s->nice = (int)value; break;
        case 20: s->threads = (int)value; break;
        case 22: s->start = value; break;
        case 23: s->vsize = value; break;
        case 24: s->rss = (int64_t)value; break;
        case 52: s->exit_status = (int)value; break;
        }
    }
    return 0;
}

static uint32_t darwin_sigmask(uint64_t mask) {
    uint32_t result = 0;
    for (int signal = 1; signal <= 31; signal++)
        if (mask & (UINT64_C(1) << (signal - 1)))
            result |= UINT32_C(1) << (dx_sig_from_host(signal) - 1);
    return result;
}

static int proc_read_creds(int pid, struct proc_creds *c) {
    FILE *f = proc_open(pid, "status");
    if (!f) return -1;
    *c = (struct proc_creds){0};
    char line[512];
    unsigned long long mask;
    int uid = 0, gid = 0;
    while (fgets(line, sizeof line, f)) {
        if (!strncmp(line, "Uid:", 4)) uid = sscanf(line + 4, "%u %u %u", &c->ruid, &c->uid, &c->svuid);
        else if (!strncmp(line, "Gid:", 4)) gid = sscanf(line + 4, "%u %u %u", &c->rgid, &c->gid, &c->svgid);
        else if (sscanf(line, "TracerPid: %u", &c->tracer) == 1) {}
        else if (sscanf(line, "SigPnd: %llx", &mask) == 1) c->sig_pending = darwin_sigmask(mask);
        else if (sscanf(line, "SigBlk: %llx", &mask) == 1) c->sig_mask = darwin_sigmask(mask);
        else if (sscanf(line, "SigIgn: %llx", &mask) == 1) c->sig_ignore = darwin_sigmask(mask);
        else if (sscanf(line, "SigCgt: %llx", &mask) == 1) c->sig_catch = darwin_sigmask(mask);
    }
    int error = ferror(f) ? errno : 0;
    fclose(f);
    if (uid == 3 && gid == 3 && !error) return 0;
    errno = error ? error : EIO;
    return -1;
}

static unsigned proc_status(char state) {
    switch (state) {
    case 'R': return 2;
    case 'T': case 't': return 4;
    case 'Z': case 'X': case 'x': return 5;
    case 'I': return 1;
    default: return 3;
    }
}

static uint32_t darwin_device(unsigned major_number, unsigned minor_number) {
    return ((major_number & 0xff) << 24) | (minor_number & 0xffffff);
}

static uint32_t proc_tty(int tty) {
    uint32_t n = (uint32_t)tty;
    if (!n) return UINT32_MAX; /* Darwin NODEV */
    return darwin_device((n >> 8) & 0xfff, (n & 0xff) | ((n >> 12) & 0xfff00));
}

static uint32_t proc_flags(const struct proc_stat *s, const struct proc_creds *c) {
    return 0x10 | (s->session == s->pid ? 0x20 : 0) | (s->tty ? 0xc0 : 0) | (c->tracer ? 2 : 0);
}

static uint64_t proc_ticks_ns(uint64_t ticks) {
    long hz = sysconf(_SC_CLK_TCK);
    if (hz <= 0) return 0;
    return (ticks / hz) * 1000000000 + (ticks % hz) * 1000000000 / hz;
}

/* A process's start as wall time. Its start is kept in clock ticks since
 * boot (CLOCK_BOOTTIME); /proc/stat's btime is whole seconds, which made
 * the start up to a second early: now minus how long ago it started, by
 * the boot clock, instead. */
static void proc_start_time(uint64_t ticks, uint64_t *seconds, uint64_t *micros) {
    struct timespec now, boot;
    if (clock_gettime(CLOCK_REALTIME, &now) || clock_gettime(CLOCK_BOOTTIME, &boot)) return;
    uint64_t started = proc_ticks_ns(ticks);
    uint64_t since_boot = (uint64_t)boot.tv_sec * 1000000000ull + (uint64_t)boot.tv_nsec;
    uint64_t ago = since_boot > started ? since_boot - started : 0;
    uint64_t wall = (uint64_t)now.tv_sec * 1000000000ull + (uint64_t)now.tv_nsec - ago;
    *seconds = wall / 1000000000;
    *micros = wall % 1000000000 / 1000;
}

static int next_numeric(DIR *dir) {
    struct dirent *entry;
    errno = 0;
    while ((entry = readdir(dir))) {
        const char *name = entry->d_name;
        if (*name < '0' || *name > '9') continue;
        char *end;
        long n = strtol(name, &end, 10);
        if (!*end && n <= INT_MAX) return n;
        errno = 0;
    }
    return -1;
}

static int finish_dir(DIR *dir, int result) {
    int error = errno;
    closedir(dir);
    errno = error;
    return error ? -1 : result;
}

static int keep_pid(int pid, uint32_t type, uint32_t filter) {
    if (type == PROC_ALL_PIDS) return 1;
    if (type == PROC_UID_ONLY || type == PROC_RUID_ONLY) {
        struct proc_creds c;
        return !proc_read_creds(pid, &c) && (type == PROC_UID_ONLY ? c.uid : c.ruid) == filter;
    }
    struct proc_stat s;
    if (proc_read_stat(pid, &s)) return 0;
    switch (type) {
    case PROC_PGRP_ONLY: return (uint32_t)s.pgid == filter;
    case PROC_TTY_ONLY:
        /* Accept the Darwin dev_t as well as Linux's /proc tty_nr spelling. */
        return proc_tty(s.tty) == filter || (uint32_t)s.tty == filter;
    case PROC_PPID_ONLY: return (uint32_t)s.ppid == filter;
    default: return 0;
    }
}

static int d_proc_listpids(uint32_t type, uint32_t filter, void *buffer, int bytes) {
    if (type < PROC_ALL_PIDS || type > PROC_PPID_ONLY || bytes < 0) return proc_error(EINVAL, 0);
    DIR *dir = opendir("/proc");
    if (!dir) return proc_error(errno, 0);
    int32_t *pids = buffer;
    int count = 0, pid, limit = (buffer ? bytes : INT_MAX) / (int)sizeof *pids;
    errno = 0;
    while (count < limit && (pid = next_numeric(dir)) >= 0) {
        if (!pid || !keep_pid(pid, type, filter)) continue;
        if (pids) memcpy(pids + count, &pid, sizeof *pids);
        count++;
        errno = 0;
    }
    int result = finish_dir(dir, count * (int)sizeof *pids);
    return result < 0 ? proc_error(errno, 0) : result;
}
DX_FN(proc_listpids);

static int d_proc_listallpids(void *buffer, int bytes) {
    return d_proc_listpids(PROC_ALL_PIDS, 0, buffer, bytes) / (int)sizeof(int32_t);
}
DX_FN(proc_listallpids);

static int d_proc_listchildpids(int ppid, void *buffer, int bytes) {
    /* This wrapper returns a PID count, including when buffer is NULL. */
    return d_proc_listpids(PROC_PPID_ONLY, (uint32_t)ppid, buffer, bytes) / (int)sizeof(int32_t);
}
DX_FN(proc_listchildpids);

static int d_proc_pidpath(int pid, void *buffer, uint32_t bytes) {
    int n = proc_link(pid, "exe", buffer, bytes);
    return n < 0 ? proc_error(errno, 0) : n;
}
DX_FN(proc_pidpath);

static int d_proc_name(int pid, void *buffer, uint32_t bytes) {
    struct proc_stat s;
    if (proc_read_stat(pid, &s)) return proc_error(errno, 0);
    size_t n = strlen(s.comm);
    if (!buffer || n >= bytes) return proc_error(ENOMEM, 0);
    memcpy(buffer, s.comm, n + 1);
    return n;
}
DX_FN(proc_name);

static unsigned fd_type(const char *link) {
    if (!strncmp(link, "socket:[", 8)) return PROX_FDTYPE_SOCKET;
    if (!strncmp(link, "pipe:[", 6)) return PROX_FDTYPE_PIPE;
    if (!strcmp(link, "anon_inode:[eventpoll]")) return PROX_FDTYPE_KQUEUE;
    return PROX_FDTYPE_VNODE;
}

static int proc_fds(int pid, void *buffer, int bytes) {
    if (pid <= 0) { errno = ESRCH; return -1; }
    char path[64];
    snprintf(path, sizeof path, "/proc/%d/fd", pid);
    DIR *dir = opendir(path);
    if (!dir) {
        if (errno == ENOENT) errno = ESRCH;
        return -1;
    }
    int own_fd = pid == getpid() ? dirfd(dir) : -1;
    int fd, count = 0, limit = (buffer ? bytes : INT_MAX) / (int)sizeof(struct d_proc_fdinfo);
    errno = 0;
    while (count < limit && (fd = next_numeric(dir)) >= 0) {
        if (fd == own_fd) continue;
        if (buffer) {
            char name[16], link[PATH_MAX];
            snprintf(name, sizeof name, "%d", fd);
            ssize_t n = readlinkat(dirfd(dir), name, link, sizeof link - 1);
            if (n < 0 && errno == ENOENT) continue;
            if (n < 0) { count = 0; break; }
            link[n] = 0;
            struct d_proc_fdinfo row = {fd, fd_type(link)};
            memcpy((char *)buffer + count * sizeof row, &row, sizeof row);
        }
        count++;
    }
    return finish_dir(dir, count * (int)sizeof(struct d_proc_fdinfo));
}

static void fill_vnode(int pid, const char *entry, struct d_vnode_info *out) {
    char path[64];
    snprintf(path, sizeof path, "/proc/%d/%s", pid, entry);
    struct stat s;
    if (stat(path, &s) < 0) return;
    out->vi_stat = (struct d_vinfo_stat){
        .dev = darwin_device(major(s.st_dev), minor(s.st_dev)),
        .rdev = darwin_device(major(s.st_rdev), minor(s.st_rdev)),
        .mode = s.st_mode, .nlink = s.st_nlink, .ino = s.st_ino, .uid = s.st_uid, .gid = s.st_gid,
        .atime = s.st_atim, .mtime = s.st_mtim, .ctime = s.st_ctim,
        .size = s.st_size, .blocks = s.st_blocks, .blksize = s.st_blksize,
    };
    switch (s.st_mode & S_IFMT) {
    case S_IFREG: out->vi_type = 1; break;
    case S_IFDIR: out->vi_type = 2; break;
    case S_IFBLK: out->vi_type = 3; break;
    case S_IFCHR: out->vi_type = 4; break;
    case S_IFLNK: out->vi_type = 5; break;
    case S_IFSOCK: out->vi_type = 6; break;
    case S_IFIFO: out->vi_type = 7; break;
    }
}

static int d_proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int bytes) {
    if (bytes < 0) return proc_error(EINVAL, 0);
    if (flavor == PROC_PIDLISTFDS) {
        int n = proc_fds(pid, buffer, bytes);
        return n < 0 ? proc_error(errno, 0) : n;
    }
    if (!buffer) return proc_error(EINVAL, 0);
    if (flavor == PROC_PIDVNODEPATHINFO) {
        struct d_proc_vnodepathinfo out = {0};
        if ((size_t)bytes < sizeof out) return proc_error(ENOMEM, 0);
        if (proc_link(pid, "cwd", out.pvi_cdir.vip_path, sizeof out.pvi_cdir.vip_path) < 0)
            return proc_error(errno, 0);
        if (proc_link(pid, "root", out.pvi_rdir.vip_path, sizeof out.pvi_rdir.vip_path) < 0)
            return proc_error(errno, 0);
        fill_vnode(pid, "cwd", &out.pvi_cdir.vip_vi);
        fill_vnode(pid, "root", &out.pvi_rdir.vip_vi);
        memcpy(buffer, &out, sizeof out);
        return sizeof out;
    }
    if (flavor != PROC_PIDTASKINFO && flavor != PROC_PIDTBSDINFO && flavor != PROC_PIDT_SHORTBSDINFO)
        return proc_error(ENOTSUP, 0);
    struct proc_stat s;
    if (proc_read_stat(pid, &s)) return proc_error(errno, 0);
    if (flavor == PROC_PIDTASKINFO) {
        struct d_proc_taskinfo out = {
            .pti_virtual_size = s.vsize,
            .pti_resident_size = s.rss > 0 ? (uint64_t)s.rss * getpagesize() : 0,
            .pti_total_user = proc_ticks_ns(s.utime), .pti_total_system = proc_ticks_ns(s.stime),
            .pti_faults = s.minflt + s.majflt, .pti_pageins = s.majflt, .pti_threadnum = s.threads,
            .pti_numrunning = s.state == 'R', .pti_priority = s.priority,
        };
        if ((size_t)bytes < sizeof out) return proc_error(ENOMEM, 0);
        memcpy(buffer, &out, sizeof out);
        return sizeof out;
    }
    struct proc_creds c;
    if (proc_read_creds(pid, &c)) return proc_error(errno, 0);
    if (flavor == PROC_PIDT_SHORTBSDINFO) {
        struct d_proc_bsdshortinfo out = {
            .pbsi_pid = pid, .pbsi_ppid = s.ppid, .pbsi_pgid = s.pgid, .pbsi_status = proc_status(s.state),
            .pbsi_flags = proc_flags(&s, &c), .pbsi_uid = c.uid, .pbsi_gid = c.gid,
            .pbsi_ruid = c.ruid, .pbsi_rgid = c.rgid, .pbsi_svuid = c.svuid, .pbsi_svgid = c.svgid,
        };
        if ((size_t)bytes < sizeof out) return proc_error(ENOMEM, 0);
        memcpy(out.pbsi_comm, s.comm, sizeof out.pbsi_comm);
        memcpy(buffer, &out, sizeof out);
        return sizeof out;
    }
    struct d_proc_bsdinfo out = {
        .pbi_flags = proc_flags(&s, &c), .pbi_status = proc_status(s.state),
        .pbi_xstatus = dx_wait_status_from_host(s.exit_status), .pbi_pid = pid, .pbi_ppid = s.ppid,
        .pbi_uid = c.uid, .pbi_gid = c.gid, .pbi_ruid = c.ruid, .pbi_rgid = c.rgid,
        .pbi_svuid = c.svuid, .pbi_svgid = c.svgid, .pbi_pgid = s.pgid,
        .e_tdev = proc_tty(s.tty), .e_tpgid = s.tpgid, .pbi_nice = s.nice,
    };
    if ((size_t)bytes < sizeof out) return proc_error(ENOMEM, 0);
    memcpy(out.pbi_comm, s.comm, sizeof out.pbi_comm);
    memcpy(out.pbi_name, s.comm, sizeof s.comm);
    int fdbytes = proc_fds(pid, NULL, 0);
    if (fdbytes >= 0) out.pbi_nfiles = (unsigned)fdbytes / sizeof(struct d_proc_fdinfo);
    proc_start_time(s.start, &out.pbi_start_tvsec, &out.pbi_start_tvusec);
    memcpy(buffer, &out, sizeof out);
    return sizeof out;
}
DX_FN(proc_pidinfo);

static int d_proc_pidfdinfo(int pid, int fd, int flavor, void *buffer, int bytes) {
    if (flavor != PROC_PIDFDVNODEPATHINFO) return proc_error(ENOTSUP, 0);
    struct d_vnode_fdinfowithpath out = {0};
    if (!buffer || bytes < (int)sizeof out) return proc_error(ENOMEM, 0);
    if (fd < 0) return proc_error(EBADF, 0);
    char entry[32];
    snprintf(entry, sizeof entry, "fd/%d", fd);
    if (proc_link(pid, entry, out.pvip.vip_path, sizeof out.pvip.vip_path) < 0) {
        int error = errno;
        struct proc_stat s;
        if (error == ESRCH && !proc_read_stat(pid, &s)) error = EBADF;
        return proc_error(error, 0);
    }
    if (fd_type(out.pvip.vip_path) != PROX_FDTYPE_VNODE) return proc_error(ENOTSUP, 0);
    out.pfi.fi_type = PROX_FDTYPE_VNODE;
    fill_vnode(pid, entry, &out.pvip.vip_vi);
    snprintf(entry, sizeof entry, "fdinfo/%d", fd);
    FILE *f = proc_open(pid, entry);
    if (f) {
        char line[128];
        long long pos;
        unsigned flags;
        while (fgets(line, sizeof line, f)) {
            if (sscanf(line, "pos: %lld", &pos) == 1) out.pfi.fi_offset = pos;
            else if (sscanf(line, "flags: %o", &flags) == 1) {
                out.pfi.fi_openflags = dx_open_flags_from_host(flags) & ~D_O_CLOEXEC;
                if (flags & O_CLOEXEC) out.pfi.fi_status |= 2;
            }
        }
        fclose(f);
    }
    memcpy(buffer, &out, sizeof out);
    return sizeof out;
}
DX_FN(proc_pidfdinfo);

static int d_proc_regionfilename(int pid, uint64_t address, void *buffer, uint32_t bytes) {
    if (!buffer || !bytes) return proc_error(EINVAL, 0);
    FILE *f = proc_open(pid, "maps");
    if (!f) return proc_error(errno, 0);
    char *line = NULL;
    size_t capacity = 0;
    int result = 0, error = ENOENT;
    while (getline(&line, &capacity, f) >= 0) {
        unsigned long long start, end;
        int offset = 0;
        if (sscanf(line, "%llx-%llx %*s %*s %*s %*s %n", &start, &end, &offset) < 2 ||
            !offset || address < start || address >= end) continue;
        const char *name = line + offset;
        if (*name != '/') break;
        size_t n = strcspn(name, "\n");
        if (n >= bytes) { error = ENOMEM; break; }
        memcpy(buffer, name, n);
        ((char *)buffer)[n] = 0;
        result = n;
        break;
    }
    if (ferror(f)) error = errno;
    free(line);
    fclose(f);
    return result ? result : proc_error(error, 0);
}
DX_FN(proc_regionfilename);

struct d_rusage_info {
    uint8_t uuid[16];
    uint64_t user_time, system_time;
    uint64_t idle_wakes, interrupt_wakes, pageins, wired, resident, footprint, start, exit;
    uint64_t child_statistics[6], disk_bytes[2], qos_times[7], billed_time, serviced_time;
    uint64_t logical_writes, peak_footprint, instructions, cycles, billed_energy, serviced_energy;
    uint64_t interval_peak_footprint, runnable_time, flags;
    uint64_t user_ptime, system_ptime, pinstructions, pcycles, energy_nj, penergy_nj;
    uint64_t secure_time, secure_ptime, neural_footprint, peak_neural, interval_peak_neural, reserved[9];
};
_Static_assert(offsetof(struct d_rusage_info, child_statistics) == 96, "rusage_info_v0 layout");
_Static_assert(offsetof(struct d_rusage_info, disk_bytes) == 144, "rusage_info_v1 layout");
_Static_assert(offsetof(struct d_rusage_info, qos_times) == 160, "rusage_info_v2 layout");
_Static_assert(offsetof(struct d_rusage_info, logical_writes) == 232, "rusage_info_v3 layout");
_Static_assert(offsetof(struct d_rusage_info, flags) == 296, "rusage_info_v4 layout");
_Static_assert(offsetof(struct d_rusage_info, user_ptime) == 304, "rusage_info_v5 layout");
_Static_assert(sizeof(struct d_rusage_info) == 464, "rusage_info_v6 layout");

static int d_proc_pid_rusage(int pid, int flavor, void *buffer) {
    static const size_t sizes[] = {96, 144, 160, 232, 296, 304, 464};
    if (!buffer || flavor < 0 || (size_t)flavor >= sizeof sizes / sizeof *sizes)
        return proc_error(EINVAL, -1);
    struct proc_stat s;
    if (proc_read_stat(pid, &s)) return proc_error(errno, -1);
    /* Only the process CPU times are translated. Other counters are zero. */
    struct d_rusage_info out = {.user_time = proc_ticks_ns(s.utime), .system_time = proc_ticks_ns(s.stime)};
    memcpy(buffer, &out, sizes[flavor]);
    return 0;
}
DX_FN(proc_pid_rusage);

static int fill_kinfo(int pid, struct d_kinfo_proc *out) {
    struct proc_stat s;
    struct proc_creds c;
    if (proc_read_stat(pid, &s) || proc_read_creds(pid, &c)) return -1;
    *out = (struct d_kinfo_proc){0};
    struct d_extern_proc *p = &out->kp_proc;
    struct d_eproc *e = &out->kp_eproc;
    p->p_pid = pid;
    p->p_stat = proc_status(s.state);
    p->p_flag = 4 | (s.tty ? 2 : 0); /* P_LP64, P_CONTROLT */
    p->p_xstat = dx_wait_status_from_host(s.exit_status);
    p->p_siglist = c.sig_pending;
    p->p_sigmask = c.sig_mask;
    p->p_sigignore = c.sig_ignore;
    p->p_sigcatch = c.sig_catch;
    p->p_nice = s.nice;
    p->p_uticks = s.utime;
    p->p_sticks = s.stime;
    memcpy(p->p_comm, s.comm, sizeof p->p_comm);
    uint64_t seconds = 0, micros = 0;
    proc_start_time(s.start, &seconds, &micros);
    p->p_un.start.tv_sec = seconds;
    p->p_un.start.tv_usec = micros;
    e->e_ppid = s.ppid;
    e->e_pgid = s.pgid;
    e->e_tdev = proc_tty(s.tty);
    e->e_tpgid = s.tpgid;
    e->e_flag = (s.tty ? 1 : 0) | (s.session == pid ? 2 : 0);
    e->e_pcred.p_ruid = c.ruid;
    e->e_pcred.p_rgid = c.rgid;
    e->e_pcred.p_svuid = c.svuid;
    e->e_pcred.p_svgid = c.svgid;
    e->e_ucred.cr_uid = c.uid;
    e->e_ucred.cr_ngroups = 1;
    e->e_ucred.cr_groups[0] = c.gid;
    e->e_vm.vm_rssize = s.rss;
    return 0;
}

static int sysctl_proc_all(void *out, size_t *size) {
    DIR *dir = opendir("/proc");
    if (!dir) return -1;
    size_t needed = 0, capacity = out ? *size : 0;
    int pid;
    while ((pid = next_numeric(dir)) >= 0) {
        struct d_kinfo_proc row;
        if (!pid || fill_kinfo(pid, &row)) continue;
        if (needed > SIZE_MAX - sizeof row) { errno = EOVERFLOW; break; }
        if (out && needed + sizeof row <= capacity) memcpy((char *)out + needed, &row, sizeof row);
        needed += sizeof row;
    }
    if (finish_dir(dir, 0) < 0) return -1;
    *size = needed;
    if (out && capacity < needed) { errno = ENOMEM; return -1; }
    return 0;
}

struct proc_buffer {
    char *data;
    size_t length, capacity;
};

static int proc_append(struct proc_buffer *b, const void *data, size_t n) {
    if (n > SIZE_MAX - b->length) { errno = EOVERFLOW; return -1; }
    size_t length = b->length + n;
    if (length > b->capacity) {
        size_t capacity = b->capacity <= SIZE_MAX / 2 ? b->capacity * 2 : length;
        if (capacity < length) capacity = length;
        char *p = realloc(b->data, capacity);
        if (!p) return -1;
        b->data = p;
        b->capacity = capacity;
    }
    if (n) memcpy(b->data + b->length, data, n);
    b->length = length;
    return 0;
}

static int proc_append_file(struct proc_buffer *b, int pid, const char *entry) {
    FILE *f = proc_open(pid, entry);
    if (!f) return -1;
    char buffer[4096];
    size_t n;
    while ((n = fread(buffer, 1, sizeof buffer, f)) > 0) {
        if (proc_append(b, buffer, n)) {
            int error = errno;
            fclose(f);
            errno = error;
            return -1;
        }
    }
    int error = ferror(f) ? errno : 0;
    fclose(f);
    errno = error;
    return error ? -1 : 0;
}

static int sysctl_proc_copy(void *out, size_t *size, const void *data, size_t needed) {
    size_t capacity = out ? *size : 0;
    *size = needed;
    if (!out) return 0;
    if (capacity < needed) { errno = ENOMEM; return -1; }
    memcpy(out, data, needed);
    return 0;
}

static int build_proc_args(struct proc_buffer *b, int pid, int with_argc) {
    char exe[PATH_MAX];
    const char *executable = pid == getpid() && dx_argv ? dx_main_path() : NULL;
    int32_t argc = 0;
    if (!executable) {
        if (proc_link(pid, "exe", exe, sizeof exe) < 0) return -1;
        executable = exe;
    }
    if (with_argc && proc_append(b, &argc, sizeof argc)) return -1;
    if (proc_append(b, executable, strlen(executable) + 1)) return -1;
    if (pid == getpid() && dx_argv) {
        /* Linux's argv also contains the loader and its options. */
        argc = dx_argc;
        for (int i = 0; i < argc; i++)
            if (proc_append(b, dx_argv[i], strlen(dx_argv[i]) + 1)) return -1;
    } else {
        size_t start = b->length;
        if (proc_append_file(b, pid, "cmdline")) return -1;
        if (b->length > start && b->data[b->length - 1] && proc_append(b, "", 1)) return -1;
        for (size_t i = start; i < b->length; i++) {
            if (b->data[i]) continue;
            if (argc == INT32_MAX) { errno = EOVERFLOW; return -1; }
            argc++;
        }
    }
    if (with_argc) memcpy(b->data, &argc, sizeof argc);
    return proc_append_file(b, pid, "environ");
}

int dx_sysctl_proc(const int *mib, unsigned miblen, void *oldp, size_t *oldlenp) {
    if (!mib || !oldlenp || miblen < 3 || mib[0] != 1) return proc_error(EINVAL, -1);
    int result;
    switch (mib[1]) {
    case KERN_PROCARGS:
    case KERN_PROCARGS2: {
        if (miblen != 3) return proc_error(EINVAL, -1);
        struct proc_buffer b = {0};
        result = build_proc_args(&b, mib[2], mib[1] == KERN_PROCARGS2);
        if (!result) result = sysctl_proc_copy(oldp, oldlenp, b.data, b.length);
        int error = errno;
        free(b.data);
        errno = error;
        break;
    }
    case KERN_PROC:
        if (mib[2] == KERN_PROC_ALL && (miblen == 3 || (miblen == 4 && mib[3] == 0))) {
            result = sysctl_proc_all(oldp, oldlenp);
        } else if (mib[2] == KERN_PROC_PID && miblen == 4) {
            struct d_kinfo_proc row;
            result = fill_kinfo(mib[3], &row);
            if (!result) result = sysctl_proc_copy(oldp, oldlenp, &row, sizeof row);
        } else return proc_error(EINVAL, -1);
        break;
    default:
        return proc_error(ENOTSUP, -1);
    }
    return result < 0 ? proc_error(errno, -1) : 0;
}
