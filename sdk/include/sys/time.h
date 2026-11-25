/* bitten SDK: <sys/time.h>. */
#ifndef BITTEN_SYS_TIME_H
#define BITTEN_SYS_TIME_H
#include <sys/types.h>
#include <sys/select.h>
#include <time.h>

struct timezone {
    int tz_minuteswest;
    int tz_dsttime;
};
struct itimerval {
    struct timeval it_interval;
    struct timeval it_value;
};
#define ITIMER_REAL 0
#define ITIMER_VIRTUAL 1
#define ITIMER_PROF 2

__BEGIN_DECLS
int gettimeofday(struct timeval *restrict, void *restrict);
int getitimer(int, struct itimerval *);
int setitimer(int, const struct itimerval *restrict, struct itimerval *restrict);
int utimes(const char *, const struct timeval[2]);
int futimes(int, const struct timeval[2]);
int lutimes(const char *, const struct timeval[2]);
__END_DECLS
#endif
