#ifndef BITTEN_TIME_H
#define BITTEN_TIME_H
#include <stddef.h>
typedef long time_t;
struct timespec { time_t tv_sec; long tv_nsec; };
struct tm { int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst; long tm_gmtoff; char *tm_zone; };
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 6
time_t time(time_t *);
int clock_gettime(int, struct timespec *);
struct tm *localtime_r(const time_t *, struct tm *);
struct tm *gmtime_r(const time_t *, struct tm *);
size_t strftime(char *, size_t, const char *, const struct tm *);
#endif
