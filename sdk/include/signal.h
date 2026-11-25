/* bitten SDK: <signal.h>. */
#ifndef BITTEN_SIGNAL_H
#define BITTEN_SIGNAL_H
#include <sys/signal.h>

__BEGIN_DECLS
void (*signal(int, void (*)(int)))(int);
int raise(int);
int kill(pid_t, int);
int killpg(pid_t, int);
int sigaction(int, const struct sigaction *restrict, struct sigaction *restrict);
int sigprocmask(int, const sigset_t *restrict, sigset_t *restrict);
int sigpending(sigset_t *);
int sigsuspend(const sigset_t *);
int sigwait(const sigset_t *restrict, int *restrict);
int sigaltstack(const stack_t *restrict, stack_t *restrict);
int sigemptyset(sigset_t *);
int sigfillset(sigset_t *);
int sigaddset(sigset_t *, int);
int sigdelset(sigset_t *, int);
int sigismember(const sigset_t *, int);
int pthread_sigmask(int, const sigset_t *, sigset_t *);
int pthread_kill(pthread_t, int);
char *strsignal(int);
__END_DECLS
#endif
