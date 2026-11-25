/* bitten SDK: <sys/wait.h>. */
#ifndef BITTEN_SYS_WAIT_H
#define BITTEN_SYS_WAIT_H
#include <sys/_types.h>
#include <sys/signal.h>
#include <sys/resource.h>
#define WNOHANG 0x00000001
#define WUNTRACED 0x00000002
#define _WSTATUS(x) ((x) & 0177)
#define _WSTOPPED 0177
#define WEXITSTATUS(x) (((x) >> 8) & 0x000000ff)
#define WTERMSIG(x) _WSTATUS(x)
#define WSTOPSIG(x) ((x) >> 8)
#define WIFEXITED(x) (_WSTATUS(x) == 0)
#define WIFSTOPPED(x) (_WSTATUS(x) == _WSTOPPED && WSTOPSIG(x) != 0x13)
#define WIFSIGNALED(x) (_WSTATUS(x) != _WSTOPPED && _WSTATUS(x) != 0)
#define WCOREDUMP(x) ((x) & 0200)
__BEGIN_DECLS
pid_t wait(int *);
pid_t waitpid(pid_t, int *, int);
pid_t wait4(pid_t, int *, int, struct rusage *);
__END_DECLS
#endif
