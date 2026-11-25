/* bitten SDK: <sys/sysctl.h>. */
#ifndef BITTEN_SYS_SYSCTL_H
#define BITTEN_SYS_SYSCTL_H
#include <sys/types.h>
#define CTL_MAXNAME 12
#define CTL_KERN 1
#define CTL_HW 6
#define KERN_OSTYPE 1
#define KERN_OSRELEASE 2
#define KERN_VERSION 4
#define KERN_HOSTNAME 10
#define KERN_PROC 14
#define KERN_BOOTTIME 21
#define KERN_OSVERSION 65
#define KERN_PROC_ALL 0
#define KERN_PROC_PID 1
#define HW_MACHINE 1
#define HW_MODEL 2
#define HW_NCPU 3
#define HW_PAGESIZE 7
#define HW_MEMSIZE 24
__BEGIN_DECLS
int sysctl(int *, u_int, void *, size_t *, void *, size_t);
int sysctlbyname(const char *, void *, size_t *, void *, size_t);
int sysctlnametomib(const char *, int *, size_t *);
__END_DECLS
#endif
