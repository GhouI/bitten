/* bitten SDK: <limits.h>. The integer limits come from the compiler's own
 * header; this adds the POSIX ones with Darwin's values. */
#ifndef BITTEN_LIMITS_H
#define BITTEN_LIMITS_H
#if __has_include_next(<limits.h>)
#include_next <limits.h>
#endif
#include <sys/syslimits.h>
#define SSIZE_MAX 0x7fffffffffffffffL
#define _POSIX_PATH_MAX 256
#define IOV_MAX 1024
#endif
