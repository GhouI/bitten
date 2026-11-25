/* bitten SDK: <strings.h>. */
#ifndef BITTEN_STRINGS_H
#define BITTEN_STRINGS_H
#include <sys/_types.h>
__BEGIN_DECLS
int bcmp(const void *, const void *, size_t);
void bcopy(const void *, void *, size_t);
void bzero(void *, size_t);
int ffs(int);
char *index(const char *, int);
char *rindex(const char *, int);
int strcasecmp(const char *, const char *);
int strncasecmp(const char *, const char *, size_t);
__END_DECLS
#endif
