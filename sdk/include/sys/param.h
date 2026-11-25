/* bitten SDK: <sys/param.h>. */
#ifndef BITTEN_SYS_PARAM_H
#define BITTEN_SYS_PARAM_H
#include <sys/types.h>
#include <sys/syslimits.h>
#define MAXPATHLEN PATH_MAX
#define MAXHOSTNAMELEN 256
#define MAXLOGNAME 255
#define NGROUPS NGROUPS_MAX
#define NOFILE 256
#ifndef MIN
#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) (((a) > (b)) ? (a) : (b))
#endif
#define howmany(x, y) ((((x) % (y)) == 0) ? ((x) / (y)) : (((x) / (y)) + 1))
#define roundup(x, y) ((((x) % (y)) == 0) ? (x) : ((x) + ((y) - ((x) % (y)))))
#endif
