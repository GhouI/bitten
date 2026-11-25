/* bitten SDK: <sys/resource.h>. */
#ifndef BITTEN_SYS_RESOURCE_H
#define BITTEN_SYS_RESOURCE_H
#include <sys/_types.h>
struct rusage {
    struct timeval ru_utime;
    struct timeval ru_stime;
    long ru_maxrss;
    long ru_ixrss;
    long ru_idrss;
    long ru_isrss;
    long ru_minflt;
    long ru_majflt;
    long ru_nswap;
    long ru_inblock;
    long ru_oublock;
    long ru_msgsnd;
    long ru_msgrcv;
    long ru_nsignals;
    long ru_nvcsw;
    long ru_nivcsw;
};
struct rlimit {
    rlim_t rlim_cur;
    rlim_t rlim_max;
};
#define RUSAGE_SELF 0
#define RUSAGE_CHILDREN -1
#define RLIMIT_CPU 0
#define RLIMIT_FSIZE 1
#define RLIMIT_DATA 2
#define RLIMIT_STACK 3
#define RLIMIT_CORE 4
#define RLIMIT_AS 5
#define RLIMIT_RSS RLIMIT_AS
#define RLIMIT_MEMLOCK 6
#define RLIMIT_NPROC 7
#define RLIMIT_NOFILE 8
#define RLIM_INFINITY 0x7fffffffffffffffULL
#define PRIO_PROCESS 0
#define PRIO_PGRP 1
#define PRIO_USER 2
__BEGIN_DECLS
int getrlimit(int, struct rlimit *);
int setrlimit(int, const struct rlimit *);
int getrusage(int, struct rusage *);
int getpriority(int, id_t);
int setpriority(int, id_t, int);
__END_DECLS
#endif
