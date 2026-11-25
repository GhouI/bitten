/* bitten SDK: <sched.h>. */
#ifndef BITTEN_SCHED_H
#define BITTEN_SCHED_H
#include <sys/_types.h>
struct sched_param {
    int sched_priority;
    char __opaque[4];
};
__BEGIN_DECLS
int sched_yield(void);
__END_DECLS
#endif
