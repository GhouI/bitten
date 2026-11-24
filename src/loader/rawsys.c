/* Raw Darwin system calls.
 *
 * Most macOS code reaches the kernel through libSystem, which we replace.
 * Some code executes the `syscall` instruction itself with a Darwin
 * syscall number in %rax (0x2000000 | n for the BSD class). Linux would
 * read that as a nonsense Linux syscall, so we use Syscall User Dispatch:
 * the kernel raises SIGSYS for any syscall instruction outside the address
 * range that holds host code (this loader, glibc, the vDSO). Mach-O images
 * are always mapped below that range. The SIGSYS handler decodes the
 * Darwin call, runs our implementation of it, and writes the result back
 * in Darwin's convention: carry flag clear and the value in %rax on
 * success, carry flag set and a Darwin errno in %rax on failure. */
#define _GNU_SOURCE
#include <asm/prctl.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <ucontext.h>
#include <unistd.h>

#include "dx.h"

#ifndef PR_SET_SYSCALL_USER_DISPATCH
#define PR_SET_SYSCALL_USER_DISPATCH 59
#define PR_SYS_DISPATCH_OFF 0
#define PR_SYS_DISPATCH_ON 1
#endif
#ifndef SYS_USER_DISPATCH
#define SYS_USER_DISPATCH 2
#endif

/* Host code lives in [HOST_LO, HOST_LO + HOST_LEN); everything the loader
 * maps for Mach-O images is placed below HOST_LO. */
#define HOST_LO 0x400000000000UL
#define HOST_LEN 0x400000000000UL

static __thread char selector = 1; /* SYSCALL_DISPATCH_FILTER_BLOCK */
static int available = -1;

int dx_rawsys_enable_thread(void) {
    if (available == 0) return -1;
    int r = prctl(PR_SET_SYSCALL_USER_DISPATCH, PR_SYS_DISPATCH_ON, HOST_LO, HOST_LEN, &selector);
    if (r < 0) {
        if (available < 0)
            dx_log(1, "syscall user dispatch unavailable (%s): raw Darwin syscalls will fail",
                   strerror(errno));
        available = 0;
        return -1;
    }
    available = 1;
    return 0;
}

static void atfork_child(void) { dx_rawsys_enable_thread(); }

void dx_rawsys_init(void) {
    if ((uintptr_t)dx_rawsys_init < HOST_LO) {
        dx_log(1, "loader is mapped below the host range; raw Darwin syscalls disabled");
        available = 0;
        return;
    }
    if (dx_rawsys_enable_thread() == 0) pthread_atfork(NULL, NULL, atfork_child);
}

/* Darwin BSD syscall numbers -> the libSystem entry that implements them.
 * 'i' = int result, 'l' = 64-bit result. */
static const struct {
    short nr;
    char kind;
    const char *name;
} bsd_calls[] = {
    {3, 'l', "_read"}, {4, 'l', "_write"}, {5, 'i', "_open"}, {6, 'i', "_close"},
    {7, 'i', "_wait4"}, {9, 'i', "_link"}, {10, 'i', "_unlink"}, {12, 'i', "_chdir"},
    {13, 'i', "_fchdir"}, {15, 'i', "_chmod"}, {16, 'i', "_chown"}, {20, 'i', "_getpid"},
    {23, 'i', "_setuid"}, {24, 'i', "_getuid"}, {25, 'i', "_geteuid"}, {27, 'l', "_recvmsg"},
    {28, 'l', "_sendmsg"}, {29, 'l', "_recvfrom"}, {30, 'i', "_accept"}, {31, 'i', "_getpeername"},
    {32, 'i', "_getsockname"}, {33, 'i', "_access"}, {37, 'i', "_kill"}, {39, 'i', "_getppid"},
    {41, 'i', "_dup"}, {43, 'i', "_getegid"}, {47, 'i', "_getgid"}, {48, 'i', "_sigprocmask"},
    {53, 'i', "_sigaltstack"}, {54, 'i', "_ioctl"}, {57, 'i', "_symlink"}, {58, 'l', "_readlink"},
    {59, 'i', "_execve"}, {60, 'i', "_umask"}, {61, 'i', "_chroot"}, {65, 'i', "_msync"},
    {73, 'i', "_munmap"}, {74, 'i', "_mprotect"}, {75, 'i', "_madvise"}, {78, 'i', "_mincore"},
    {79, 'i', "_getgroups"}, {80, 'i', "_setgroups"}, {81, 'i', "_getpgrp"}, {82, 'i', "_setpgid"},
    {83, 'i', "_setitimer"}, {86, 'i', "_getitimer"}, {90, 'i', "_dup2"}, {92, 'i', "_fcntl"},
    {93, 'i', "_select"}, {95, 'i', "_fsync"}, {96, 'i', "_setpriority"}, {97, 'i', "_socket"},
    {98, 'i', "_connect"}, {100, 'i', "_getpriority"}, {104, 'i', "_bind"}, {105, 'i', "_setsockopt"},
    {106, 'i', "_listen"}, {116, 'i', "_gettimeofday"}, {117, 'i', "_getrusage"},
    {118, 'i', "_getsockopt"}, {120, 'l', "_readv"}, {121, 'l', "_writev"}, {123, 'i', "_fchown"},
    {124, 'i', "_fchmod"}, {128, 'i', "_rename"}, {131, 'i', "_flock"}, {132, 'i', "_mkfifo"},
    {133, 'l', "_sendto"}, {134, 'i', "_shutdown"}, {135, 'i', "_socketpair"}, {136, 'i', "_mkdir"},
    {137, 'i', "_rmdir"}, {138, 'i', "_utimes"}, {147, 'i', "_setsid"}, {151, 'i', "_getpgid"},
    {153, 'l', "_pread"}, {154, 'l', "_pwrite"}, {181, 'i', "_setgid"}, {182, 'i', "_setegid"},
    {183, 'i', "_seteuid"}, {187, 'i', "_fdatasync"}, {194, 'i', "_getrlimit"},
    {195, 'i', "_setrlimit"}, {197, 'l', "_mmap"}, {199, 'l', "_lseek"}, {200, 'i', "_truncate"},
    {201, 'i', "_ftruncate"}, {202, 'i', "_sysctl"}, {203, 'i', "_mlock"}, {204, 'i', "_munlock"},
    {230, 'i', "_poll"}, {266, 'i', "_shm_open"}, {267, 'i', "_shm_unlink"},
    {274, 'i', "_sysctlbyname"}, {327, 'i', "_issetugid"}, {338, 'i', "_stat$INODE64"},
    {339, 'i', "_fstat$INODE64"}, {340, 'i', "_lstat$INODE64"}, {345, 'i', "_statfs$INODE64"},
    {346, 'i', "_fstatfs$INODE64"}, {362, 'i', "_kqueue"}, {363, 'i', "_kevent"},
    {369, 'i', "_kevent64"}, {396, 'l', "_read"}, {397, 'l', "_write"}, {398, 'i', "_open"},
    {399, 'i', "_close"}, {400, 'i', "_wait4"}, {401, 'l', "_recvmsg"}, {402, 'l', "_sendmsg"},
    {403, 'l', "_recvfrom"}, {404, 'i', "_accept"}, {405, 'i', "_msync"}, {406, 'i', "_fcntl"},
    {407, 'i', "_select"}, {408, 'i', "_fsync"}, {409, 'i', "_connect"}, {411, 'l', "_readv"},
    {412, 'l', "_writev"}, {413, 'l', "_sendto"}, {414, 'l', "_pread"}, {415, 'l', "_pwrite"},
    {417, 'i', "_poll"}, {463, 'i', "_openat"}, {464, 'i', "_openat"}, {465, 'i', "_renameat"},
    {466, 'i', "_faccessat"}, {467, 'i', "_fchmodat"}, {468, 'i', "_fchownat"},
    {470, 'i', "_fstatat$INODE64"}, {471, 'i', "_linkat"}, {472, 'i', "_unlinkat"},
    {473, 'l', "_readlinkat"}, {474, 'i', "_symlinkat"}, {475, 'i', "_mkdirat"},
    {500, 'i', "_getentropy"}, {515, 'i', "___ulock_wait"}, {516, 'i', "___ulock_wake"},
};
#define NBSD (sizeof bsd_calls / sizeof bsd_calls[0])
static void *bsd_fn[NBSD];

typedef long (*sys6)(long, long, long, long, long, long);

static void set_result(greg_t *g, long value, int failed, int derrno) {
    if (failed) {
        g[REG_RAX] = derrno;
        g[REG_EFL] |= 1;
    } else {
        g[REG_RAX] = value;
        g[REG_EFL] &= ~(greg_t)1;
    }
}

/* Called from the SIGSYS handler with the interrupted context. */
void dx_rawsys_dispatch(void *ucontext) {
    ucontext_t *uc = ucontext;
    greg_t *g = uc->uc_mcontext.gregs;
    unsigned long nr = (unsigned long)g[REG_RAX];
    long a1 = g[REG_RDI], a2 = g[REG_RSI], a3 = g[REG_RDX], a4 = g[REG_R10], a5 = g[REG_R8],
         a6 = g[REG_R9];
    unsigned cls = (nr >> 24) & 0xff;
    unsigned n = nr & 0xffffff;
    struct dx_thread *t = dx_thread_self();

    if (cls == 3) { /* machine-dependent */
        if (n == 3) { /* thread_fast_set_cthread_self: set the %gs base */
            syscall(SYS_arch_prctl, ARCH_SET_GS, (unsigned long)a1);
            set_result(g, 0, 0, 0);
            return;
        }
    } else if (cls == 2 || cls == 0) {
        switch (n) {
        case 1: /* exit */
            _exit((int)a1);
        case 2: { /* fork: pid in rax; rdx is 1 in the child */
            pid_t pid = fork();
            if (pid < 0) {
                set_result(g, 0, 1, dx_errno_to_darwin(errno));
            } else {
                set_result(g, pid ? pid : getppid(), 0, 0);
                g[REG_RDX] = pid ? 0 : 1;
            }
            return;
        }
        case 42: { /* pipe: descriptors in rax and rdx */
            int fds[2];
            if (pipe(fds) < 0) set_result(g, 0, 1, dx_errno_to_darwin(errno));
            else {
                set_result(g, fds[0], 0, 0);
                g[REG_RDX] = fds[1];
            }
            return;
        }
        case 372: { /* thread_selfid */
            set_result(g, (long)t->tid, 0, 0);
            return;
        }
        }
        for (size_t i = 0; i < NBSD; i++) {
            if (bsd_calls[i].nr != (short)n) continue;
            void *fn = __atomic_load_n(&bsd_fn[i], __ATOMIC_RELAXED);
            if (!fn) {
                fn = dx_registry_lookup(bsd_calls[i].name);
                if (!fn) break;
                __atomic_store_n(&bsd_fn[i], fn, __ATOMIC_RELAXED);
            }
            t->d_errno = 0;
            long r = ((sys6)fn)(a1, a2, a3, a4, a5, a6);
            int failed = bsd_calls[i].kind == 'i' ? (int)r == -1 : r == -1;
            if (bsd_calls[i].kind == 'i') r = (int)r;
            /* a legitimate -1 result without an error (rare) stays a value */
            if (failed && t->d_errno == 0) failed = 0;
            set_result(g, r, failed, t->d_errno);
            return;
        }
    }
    dx_log(0, "unsupported raw Darwin syscall 0x%lx (class %u, number %u)", nr, cls, n);
    set_result(g, 0, 1, 78); /* ENOSYS */
}

int dx_rawsys_is_dispatch(const siginfo_t *si) { return si->si_code == SYS_USER_DISPATCH; }
