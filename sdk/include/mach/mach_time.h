/* bitten SDK: <mach/mach_time.h>. */
#ifndef BITTEN_MACH_MACH_TIME_H
#define BITTEN_MACH_MACH_TIME_H
#include <sys/_types.h>
typedef int kern_return_t;
struct mach_timebase_info {
    uint32_t numer;
    uint32_t denom;
};
typedef struct mach_timebase_info *mach_timebase_info_t;
typedef struct mach_timebase_info mach_timebase_info_data_t;
__BEGIN_DECLS
kern_return_t mach_timebase_info(mach_timebase_info_t);
uint64_t mach_absolute_time(void);
uint64_t mach_approximate_time(void);
uint64_t mach_continuous_time(void);
__END_DECLS
#endif
