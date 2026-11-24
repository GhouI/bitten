/* Signals: Darwin numbering, sigaction layout, siginfo and ucontext.
 *
 * A Darwin handler expects Darwin's siginfo and ucontext/mcontext layouts
 * and may edit the saved registers (the Go runtime does this for
 * preemption and panics). The host handler below builds those structures
 * from the Linux ones, calls the Darwin handler, and copies register
 * changes back so the kernel resumes with them. */
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <string.h>
#include <ucontext.h>
#include <unistd.h>

#include "darwin_abi.h"
#include "dx.h"

#define D_SA_ONSTACK 0x01
#define D_SA_RESTART 0x02
#define D_SA_RESETHAND 0x04
#define D_SA_NOCLDSTOP 0x08
#define D_SA_NODEFER 0x10
#define D_SA_NOCLDWAIT 0x20
#define D_SA_SIGINFO 0x40

struct d_sigaction {
    void *handler;
    uint32_t mask;
    int flags;
};

struct d_stack {
    void *ss_sp;
    size_t ss_size;
    int ss_flags;
};

struct d_siginfo {
    int signo, err, code, pid;
    uint32_t uid;
    int status;
    void *addr;
    void *value;
    long band;
    unsigned long pad[7];
};
_Static_assert(sizeof(struct d_siginfo) == 104, "Darwin siginfo_t is 104 bytes");

struct d_mcontext64 {
    struct {
        uint16_t trapno, cpu;
        uint32_t err;
        uint64_t faultvaddr;
    } es;
    struct {
        uint64_t rax, rbx, rcx, rdx, rdi, rsi, rbp, rsp;
        uint64_t r8, r9, r10, r11, r12, r13, r14, r15;
        uint64_t rip, rflags, cs, fs, gs;
    } ss;
    struct {
        int reserved[2];
        uint8_t fxsave[512];
        int reserved1;
    } fs;
};

struct d_ucontext {
    int uc_onstack;
    uint32_t uc_sigmask;
    struct d_stack uc_stack;
    struct d_ucontext *uc_link;
    size_t uc_mcsize;
    struct d_mcontext64 *uc_mcontext;
};

void dx_sigset_to_host(uint32_t d, void *host) {
    sigset_t *h = host;
    sigemptyset(h);
    for (int s = 1; s < 32; s++)
        if (d & (1u << (s - 1))) sigaddset(h, dx_sig_to_host(s));
    /* SIGSYS carries raw-syscall emulation and must never be blocked */
    sigdelset(h, SIGSYS);
}

/* Install the SIGSYS handler used for raw Darwin syscalls. */
static void host_handler(int hsig, siginfo_t *hi, void *hctx);
void dx_signal_init(void) {
    struct sigaction ha;
    memset(&ha, 0, sizeof ha);
    ha.sa_sigaction = host_handler;
    ha.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_NODEFER | SA_RESTART;
    sigemptyset(&ha.sa_mask);
    sigaction(SIGSYS, &ha, NULL);
}

uint32_t dx_sigset_from_host(const void *host) {
    const sigset_t *h = host;
    uint32_t d = 0;
    for (int s = 1; s < 32; s++)
        if (sigismember(h, dx_sig_to_host(s)) == 1) d |= 1u << (s - 1);
    return d;
}

static struct d_sigaction actions[65];

static int code_from_host(int hsig, int code) {
    if (code <= 0) return 0x10001; /* SI_USER */
    if (hsig == SIGFPE) {
        static const int map[] = {0, 7, 8, 1, 2, 3, 4, 5, 6}; /* Linux -> Darwin FPE_* */
        if (code <= 8) return map[code];
    }
    return code;
}

void dx_rawsys_dispatch(void *ucontext);
int dx_rawsys_is_dispatch(const siginfo_t *si);

static void host_handler(int hsig, siginfo_t *hi, void *hctx) {
    int saved_errno = errno;
    if (hsig == SIGSYS && dx_rawsys_is_dispatch(hi)) {
        /* a raw Darwin syscall instruction: emulate it and resume */
        dx_rawsys_dispatch(hctx);
        errno = saved_errno;
        return;
    }
    struct d_sigaction act = actions[hsig];
    if ((uintptr_t)act.handler <= 1) {
        if (hsig == SIGSYS && (uintptr_t)act.handler == 0) {
            /* default action for a genuine SIGSYS */
            signal(SIGSYS, SIG_DFL);
            raise(SIGSYS);
        }
        errno = saved_errno;
        return;
    }
    int dsig = dx_sig_from_host(hsig);
    struct dx_thread *t = dx_thread_self();
    int saved_derrno = t->d_errno;

    if (!(act.flags & D_SA_SIGINFO)) {
        ((void (*)(int))act.handler)(dsig);
        t->d_errno = saved_derrno;
        errno = saved_errno;
        return;
    }

    ucontext_t *hu = hctx;
    greg_t *g = hu->uc_mcontext.gregs;
    struct d_siginfo di;
    memset(&di, 0, sizeof di);
    di.signo = dsig;
    di.err = dx_errno_to_darwin(hi->si_errno);
    di.code = code_from_host(hsig, hi->si_code);
    if (hsig == SIGSEGV || hsig == SIGBUS || hsig == SIGILL || hsig == SIGFPE || hsig == SIGTRAP) {
        di.addr = hi->si_addr;
    } else if (hsig == SIGCHLD) {
        di.pid = hi->si_pid;
        di.uid = hi->si_uid;
        di.status = hi->si_status;
        di.code = hi->si_code;
    } else {
        di.pid = hi->si_pid;
        di.uid = hi->si_uid;
        di.value = hi->si_value.sival_ptr;
    }

    struct d_mcontext64 mc;
    memset(&mc, 0, sizeof mc);
    mc.es.trapno = (uint16_t)g[REG_TRAPNO];
    mc.es.err = (uint32_t)g[REG_ERR];
    mc.es.faultvaddr = (uint64_t)g[REG_CR2];
    mc.ss.rax = g[REG_RAX]; mc.ss.rbx = g[REG_RBX]; mc.ss.rcx = g[REG_RCX]; mc.ss.rdx = g[REG_RDX];
    mc.ss.rdi = g[REG_RDI]; mc.ss.rsi = g[REG_RSI]; mc.ss.rbp = g[REG_RBP]; mc.ss.rsp = g[REG_RSP];
    mc.ss.r8 = g[REG_R8]; mc.ss.r9 = g[REG_R9]; mc.ss.r10 = g[REG_R10]; mc.ss.r11 = g[REG_R11];
    mc.ss.r12 = g[REG_R12]; mc.ss.r13 = g[REG_R13]; mc.ss.r14 = g[REG_R14]; mc.ss.r15 = g[REG_R15];
    mc.ss.rip = g[REG_RIP];
    mc.ss.rflags = g[REG_EFL];
    mc.ss.cs = g[REG_CSGSFS] & 0xffff;
    mc.ss.gs = (g[REG_CSGSFS] >> 16) & 0xffff;
    mc.ss.fs = (g[REG_CSGSFS] >> 32) & 0xffff;
    if (hu->uc_mcontext.fpregs) memcpy(mc.fs.fxsave, hu->uc_mcontext.fpregs, 512);

    struct d_ucontext du;
    memset(&du, 0, sizeof du);
    du.uc_onstack = (hu->uc_stack.ss_flags & SS_ONSTACK) ? 1 : 0;
    du.uc_sigmask = dx_sigset_from_host(&hu->uc_sigmask);
    du.uc_stack.ss_sp = hu->uc_stack.ss_sp;
    du.uc_stack.ss_size = hu->uc_stack.ss_size;
    du.uc_stack.ss_flags = (hu->uc_stack.ss_flags & SS_ONSTACK ? 1 : 0) | (hu->uc_stack.ss_flags & SS_DISABLE ? 4 : 0);
    du.uc_mcsize = sizeof mc;
    du.uc_mcontext = &mc;

    ((void (*)(int, struct d_siginfo *, void *))act.handler)(dsig, &di, &du);

    g[REG_RAX] = mc.ss.rax; g[REG_RBX] = mc.ss.rbx; g[REG_RCX] = mc.ss.rcx; g[REG_RDX] = mc.ss.rdx;
    g[REG_RDI] = mc.ss.rdi; g[REG_RSI] = mc.ss.rsi; g[REG_RBP] = mc.ss.rbp; g[REG_RSP] = mc.ss.rsp;
    g[REG_R8] = mc.ss.r8; g[REG_R9] = mc.ss.r9; g[REG_R10] = mc.ss.r10; g[REG_R11] = mc.ss.r11;
    g[REG_R12] = mc.ss.r12; g[REG_R13] = mc.ss.r13; g[REG_R14] = mc.ss.r14; g[REG_R15] = mc.ss.r15;
    g[REG_RIP] = mc.ss.rip;
    g[REG_EFL] = mc.ss.rflags;
    dx_sigset_to_host(du.uc_sigmask, &hu->uc_sigmask);

    t->d_errno = saved_derrno;
    errno = saved_errno;
}

static int d_sigaction(int dsig, const struct d_sigaction *nact, struct d_sigaction *oact) {
    int hsig = dx_sig_to_host(dsig);
    if (hsig <= 0 || hsig > 64) {
        dx_set_errno(22);
        return -1;
    }
    struct d_sigaction old = actions[hsig];
    if (nact) {
        struct sigaction ha;
        memset(&ha, 0, sizeof ha);
        if (hsig == SIGSYS) {
            /* keep our handler in place; it forwards real SIGSYS signals */
            ha.sa_sigaction = host_handler;
            ha.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_NODEFER;
        } else if ((uintptr_t)nact->handler == 0) ha.sa_handler = SIG_DFL;
        else if ((uintptr_t)nact->handler == 1) ha.sa_handler = SIG_IGN;
        else {
            ha.sa_sigaction = host_handler;
            ha.sa_flags = SA_SIGINFO;
        }
        dx_sigset_to_host(nact->mask, &ha.sa_mask);
        if (nact->flags & D_SA_ONSTACK) ha.sa_flags |= SA_ONSTACK;
        if (nact->flags & D_SA_RESTART) ha.sa_flags |= SA_RESTART;
        if (nact->flags & D_SA_RESETHAND) ha.sa_flags |= SA_RESETHAND;
        if (nact->flags & D_SA_NOCLDSTOP) ha.sa_flags |= SA_NOCLDSTOP;
        if (nact->flags & D_SA_NODEFER) ha.sa_flags |= SA_NODEFER;
        if (nact->flags & D_SA_NOCLDWAIT) ha.sa_flags |= SA_NOCLDWAIT;
        /* Publish the Darwin action first: the signal may arrive at once. */
        actions[hsig] = *nact;
        if (sigaction(hsig, &ha, NULL) < 0) {
            actions[hsig] = old;
            return DX_RET(-1);
        }
    }
    if (oact) *oact = old;
    return 0;
}
DX_FN(sigaction);

static void *d_signal(int dsig, void *handler) {
    struct d_sigaction na = {handler, 0, D_SA_RESTART}, oa;
    if (d_sigaction(dsig, &na, &oa) < 0) return (void *)-1;
    return oa.handler;
}
DX_FN(signal);

static int how_to_host(int how) { return how == 1 ? SIG_BLOCK : how == 2 ? SIG_UNBLOCK : SIG_SETMASK; }

static int d_pthread_sigmask(int how, const uint32_t *set, uint32_t *oset) {
    sigset_t hs, ho;
    if (set) dx_sigset_to_host(*set, &hs);
    int r = pthread_sigmask(how_to_host(how), set ? &hs : NULL, &ho);
    if (r) return dx_errno_to_darwin(r);
    if (oset) *oset = dx_sigset_from_host(&ho);
    return 0;
}
DX_FN(pthread_sigmask);

static int d_sigprocmask(int how, const uint32_t *set, uint32_t *oset) {
    int r = d_pthread_sigmask(how, set, oset);
    if (r) {
        dx_set_errno(r);
        return -1;
    }
    return 0;
}
DX_FN(sigprocmask);

static int d_sigaltstack(const struct d_stack *ss, struct d_stack *oss) {
    stack_t hs, ho;
    if (ss) {
        hs.ss_sp = ss->ss_sp;
        hs.ss_size = ss->ss_size;
        hs.ss_flags = (ss->ss_flags & 4) ? SS_DISABLE : 0;
    }
    int r = sigaltstack(ss ? &hs : NULL, &ho);
    if (r == 0 && oss) {
        oss->ss_sp = ho.ss_sp;
        oss->ss_size = ho.ss_size;
        oss->ss_flags = ((ho.ss_flags & SS_ONSTACK) ? 1 : 0) | ((ho.ss_flags & SS_DISABLE) ? 4 : 0);
    }
    return DX_RET(r);
}
DX_FN(sigaltstack);

static int d_kill(int pid, int sig) { return DX_RET(kill(pid, dx_sig_to_host(sig))); }
DX_FN(kill);
static int d_killpg(int pgrp, int sig) { return DX_RET(killpg(pgrp, dx_sig_to_host(sig))); }
DX_FN(killpg);
static int d_raise(int sig) { return DX_RET(raise(dx_sig_to_host(sig))); }
DX_FN(raise);

static int d_sigemptyset(uint32_t *s) { *s = 0; return 0; }
DX_FN(sigemptyset);
static int d_sigfillset(uint32_t *s) { *s = ~0u; return 0; }
DX_FN(sigfillset);
static int d_sigaddset(uint32_t *s, int sig) {
    if (sig < 1 || sig > 32) { dx_set_errno(22); return -1; }
    *s |= 1u << (sig - 1);
    return 0;
}
DX_FN(sigaddset);
static int d_sigdelset(uint32_t *s, int sig) {
    if (sig < 1 || sig > 32) { dx_set_errno(22); return -1; }
    *s &= ~(1u << (sig - 1));
    return 0;
}
DX_FN(sigdelset);
static int d_sigismember(const uint32_t *s, int sig) {
    if (sig < 1 || sig > 32) { dx_set_errno(22); return -1; }
    return (*s >> (sig - 1)) & 1;
}
DX_FN(sigismember);
static int d_sigpending(uint32_t *s) {
    sigset_t h;
    int r = sigpending(&h);
    if (r == 0) *s = dx_sigset_from_host(&h);
    return DX_RET(r);
}
DX_FN(sigpending);
static int d_sigsuspend(const uint32_t *s) {
    sigset_t h;
    dx_sigset_to_host(*s, &h);
    return DX_RET(sigsuspend(&h));
}
DX_FN(sigsuspend);
DX_EXPORT("_sigsuspend$NOCANCEL", d_sigsuspend);
static int d_sigwait(const uint32_t *s, int *sig) {
    sigset_t h;
    int hsig = 0;
    dx_sigset_to_host(*s, &h);
    int r = sigwait(&h, &hsig);
    if (r == 0) *sig = dx_sig_from_host(hsig);
    return dx_errno_to_darwin(r);
}
DX_FN(sigwait);
static char *d_strsignal(int sig) { return strsignal(dx_sig_to_host(sig)); }
DX_FN(strsignal);
