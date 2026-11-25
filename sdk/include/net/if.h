/* bitten SDK: <net/if.h>, interface names. */
#ifndef BITTEN_NET_IF_H
#define BITTEN_NET_IF_H
#include <sys/_types.h>
#define IF_NAMESIZE 16
#define IFNAMSIZ IF_NAMESIZE
__BEGIN_DECLS
unsigned int if_nametoindex(const char *);
char *if_indextoname(unsigned int, char *);
__END_DECLS
#endif
