/* bitten SDK: <sys/utsname.h>. */
#ifndef BITTEN_SYS_UTSNAME_H
#define BITTEN_SYS_UTSNAME_H
#include <sys/cdefs.h>
struct utsname {
    char sysname[256];
    char nodename[256];
    char release[256];
    char version[256];
    char machine[256];
};
__BEGIN_DECLS
int uname(struct utsname *);
__END_DECLS
#endif
