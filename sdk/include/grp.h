/* bitten SDK: <grp.h>. */
#ifndef BITTEN_GRP_H
#define BITTEN_GRP_H
#include <sys/_types.h>
struct group {
    char *gr_name;
    char *gr_passwd;
    gid_t gr_gid;
    char **gr_mem;
};
__BEGIN_DECLS
struct group *getgrgid(gid_t);
struct group *getgrnam(const char *);
int getgrgid_r(gid_t, struct group *, char *, size_t, struct group **);
int getgrnam_r(const char *, struct group *, char *, size_t, struct group **);
__END_DECLS
#endif
