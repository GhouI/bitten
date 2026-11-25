/* bitten SDK: <sys/select.h>. */
#ifndef BITTEN_SYS_SELECT_H
#define BITTEN_SYS_SELECT_H
#include <sys/types.h>
__BEGIN_DECLS
int select(int, fd_set *restrict, fd_set *restrict, fd_set *restrict, struct timeval *restrict)
    __asm("_select$1050");
__END_DECLS
#endif
