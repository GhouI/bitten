#include "darwin.h"

#define OFFSET(type, member) __builtin_offsetof(type, member)

struct bsdinfo {
    uint32_t flags, status, xstatus, pid, ppid;
    uint32_t uid, gid, ruid, rgid, svuid, svgid, reserved;
    char comm[16], name[32];
    uint32_t nfiles, pgid, jobc, tdev, tpgid;
    int32_t nice;
    uint64_t start_sec, start_usec;
};
struct shortbsdinfo {
    uint32_t pid, ppid, pgid, status;
    char comm[16];
    uint32_t flags, uid, gid, ruid, rgid, svuid, svgid, reserved;
};
struct taskinfo {
    uint64_t virtual_size, resident_size, user, system, thread_user, thread_system;
    int32_t policy, faults, pageins, cow_faults, messages_sent, messages_received;
    int32_t syscalls_mach, syscalls_unix, csw, thread_count, running, priority;
};
struct vnode_path {
    uint64_t vnode_metadata[19];
    char path[1024];
};
struct vnodepathinfo {
    struct vnode_path cwd, root;
};
struct fdinfo {
    int32_t fd;
    uint32_t type;
};
struct vnodefdinfo {
    uint64_t file_metadata[3];
    struct vnode_path vnode;
};

_Static_assert(sizeof(struct bsdinfo) == 136 && sizeof(struct shortbsdinfo) == 64, "BSD proc ABI");
_Static_assert(sizeof(struct vnodepathinfo) == 2352 && sizeof(struct vnodefdinfo) == 1200, "vnode proc ABI");
_Static_assert(OFFSET(struct vnode_path, path) == 152, "vnode path offset");
_Static_assert(sizeof(struct taskinfo) == 96, "task proc ABI");

enum {
    PROC_ALL_PIDS = 1, PROC_UID_ONLY = 4, PROC_PIDLISTFDS = 1, PROC_PIDTBSDINFO = 3,
    PROC_PIDTASKINFO = 4, PROC_PIDVNODEPATHINFO = 9, PROC_PIDT_SHORTBSDINFO = 13,
    PROC_PIDFDVNODEPATHINFO = 2,
};

int proc_listpids(uint32_t, uint32_t, void *, int), proc_listallpids(void *, int);
int proc_listchildpids(int, void *, int), proc_pidpath(int, void *, uint32_t), proc_name(int, void *, uint32_t);
int proc_pidinfo(int, int, uint64_t, void *, int), proc_pidfdinfo(int, int, int, void *, int);
int proc_regionfilename(int, uint64_t, void *, uint32_t), proc_pid_rusage(int, int, void *);
int sysctl(const int *, unsigned, void *, size_t *, const void *, size_t);
pid_t getpid(void), getppid(void), fork(void), waitpid(pid_t, int *, int);
unsigned getuid(void), geteuid(void), sleep(unsigned);
int kill(pid_t, int), open(const char *, int, ...), close(int), pipe(int *);
void _exit(int) __attribute__((noreturn));
char *getcwd(char *, size_t);

static int has_pid(const pid_t *pids, int count, pid_t pid) {
    for (int i = 0; i < count; i++)
        if (pids[i] == pid) return 1;
    return 0;
}

static int32_t read_int(const char *p) {
    int32_t value;
    memcpy(&value, p, sizeof value);
    return value;
}

static void pid_lists(pid_t self) {
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    CHECK(bytes >= (int)sizeof(pid_t) && bytes % sizeof(pid_t) == 0);
    bytes += 64 * sizeof(pid_t);
    pid_t *pids = malloc(bytes);
    CHECK(pids);
    int listed = proc_listpids(PROC_ALL_PIDS, 0, pids, bytes);
    CHECK(listed > 0 && has_pid(pids, listed / sizeof(pid_t), self));
    int count = proc_listallpids(pids, bytes);
    CHECK(count > 0 && has_pid(pids, count, self));
    listed = proc_listpids(PROC_UID_ONLY, geteuid(), pids, bytes);
    CHECK(listed > 0 && has_pid(pids, listed / sizeof(pid_t), self));

    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) {
        sleep(20);
        _exit(0);
    }
    count = proc_listchildpids(self, pids, bytes);
    int found = has_pid(pids, count, child), status = 0;
    int killed = kill(child, 9);
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(!killed && (status & 0x7f) == 9 && found);
    free(pids);
}

static void descriptors(pid_t self) {
    int fd = open("/dev/null", 0), ends[2];
    CHECK(fd >= 0 && !pipe(ends));
    int bytes = proc_pidinfo(self, PROC_PIDLISTFDS, 0, NULL, 0);
    CHECK(bytes >= 3 * (int)sizeof(struct fdinfo));
    struct fdinfo *fds = malloc(bytes);
    CHECK(fds);
    int n = proc_pidinfo(self, PROC_PIDLISTFDS, 0, fds, bytes);
    CHECK(n > 0 && n % sizeof *fds == 0);
    int vnode = 0, pipes = 0;
    for (int i = 0; i < n / (int)sizeof *fds; i++) {
        if (fds[i].fd == fd && fds[i].type == 1) vnode++;
        if ((fds[i].fd == ends[0] || fds[i].fd == ends[1]) && fds[i].type == 6) pipes++;
    }
    CHECK(vnode == 1 && pipes == 2);
    free(fds);
    struct vnodefdinfo info;
    CHECK(proc_pidfdinfo(self, fd, PROC_PIDFDVNODEPATHINFO, &info, sizeof info) == sizeof info);
    CHECK(!strcmp(info.vnode.path, "/dev/null"));
    CHECK(!proc_pidfdinfo(self, fd, 999, &info, sizeof info) && errno == 45);
    CHECK(!close(fd) && !close(ends[0]) && !close(ends[1]));
}

static void sysctls(pid_t self, int argc, char **argv) {
    int mib[] = {1, 49, self, 0};
    size_t needed = 0;
    CHECK(!sysctl(mib, 3, NULL, &needed, NULL, 0) && needed > sizeof(int32_t));
    char *args = malloc(needed);
    CHECK(args);
    size_t size = sizeof(int32_t);
    CHECK(sysctl(mib, 3, args, &size, NULL, 0) == -1 && errno == 12 && size == needed);
    CHECK(!sysctl(mib, 3, args, &size, NULL, 0));
    CHECK(read_int(args) == argc && args[4]);
    const char *arg = args + 4 + strlen(args + 4) + 1;
    for (int i = 0; i < argc; i++) {
        CHECK(arg < args + size && !strcmp(arg, argv[i]));
        arg += strlen(arg) + 1;
    }
    mib[1] = 38;
    size = needed;
    CHECK(!sysctl(mib, 3, args, &size, NULL, 0) && args[0] && size + 4 == needed);
    free(args);

    mib[1] = 14;
    mib[2] = 1;
    mib[3] = self;
    size = 0;
    CHECK(!sysctl(mib, 4, NULL, &size, NULL, 0) && size == 648);
    char info[648];
    CHECK(!sysctl(mib, 4, info, &size, NULL, 0));
    CHECK(read_int(info + 40) == self && read_int(info + 560) == getppid() && info[243]);
    CHECK((unsigned)read_int(info + 392) == getuid() && (unsigned)read_int(info + 420) == geteuid());
    mib[3] = -1;
    CHECK(sysctl(mib, 4, info, &size, NULL, 0) == -1 && errno == 3);
    mib[2] = 0;
    size = 0;
    CHECK(!sysctl(mib, 3, NULL, &size, NULL, 0) && size >= 648 && size % 648 == 0);
}

int main(int argc, char **argv) {
    pid_t self = getpid();
    char path[4096], cwd[4096];
    CHECK(proc_pidpath(self, path, sizeof path) > 0 && path[0] == '/');
    CHECK(proc_name(self, path, sizeof path) > 0);
    CHECK(!proc_pidpath(-1, path, sizeof path) && errno == 3);
    struct shortbsdinfo small;
    CHECK(proc_pidinfo(self, PROC_PIDT_SHORTBSDINFO, 0, &small, sizeof small) == sizeof small);
    CHECK(small.pid == (uint32_t)self && small.ppid == (uint32_t)getppid());
    CHECK(small.ruid == getuid() && small.uid == geteuid());
    struct bsdinfo full;
    CHECK(proc_pidinfo(self, PROC_PIDTBSDINFO, 0, &full, sizeof full) == sizeof full);
    CHECK(full.pid == small.pid && full.ppid == small.ppid && full.ruid == small.ruid && full.uid == small.uid);
    /* The start time is exact to a clock tick: just before now, not up to a
     * second early (programs time their launch from it). */
    {
        struct { long sec; int usec; } now;
        int gettimeofday(void *, void *);
        CHECK(gettimeofday(&now, NULL) == 0);
        double start = (double)full.start_sec + full.start_usec / 1e6, at = (double)now.sec + now.usec / 1e6;
        CHECK(start <= at + 0.02 && at - start < 0.5);
    }
    struct vnodepathinfo vnode;
    CHECK(proc_pidinfo(self, PROC_PIDVNODEPATHINFO, 0, &vnode, sizeof vnode) == sizeof vnode);
    CHECK(getcwd(cwd, sizeof cwd) && !strcmp(cwd, vnode.cwd.path) && vnode.root.path[0] == '/');
    struct taskinfo task;
    CHECK(proc_pidinfo(self, PROC_PIDTASKINFO, 0, &task, sizeof task) == sizeof task);
    CHECK(task.virtual_size > 0 && task.thread_count > 0);
    CHECK(proc_regionfilename(self, (uint64_t)&printf, path, sizeof path) > 0);
    uint64_t usage[12];
    CHECK(!proc_pid_rusage(self, 0, usage));
    CHECK(!usage[0] && !usage[1] && !usage[4]);
    pid_lists(self);
    descriptors(self);
    sysctls(self, argc, argv);
    puts("libproc ok");
    return 0;
}
