/* bitten SDK: <sys/xattr.h>. */
#ifndef BITTEN_SYS_XATTR_H
#define BITTEN_SYS_XATTR_H
#include <sys/_types.h>
#define XATTR_NOFOLLOW 0x0001
#define XATTR_CREATE 0x0002
#define XATTR_REPLACE 0x0004
__BEGIN_DECLS
ssize_t getxattr(const char *, const char *, void *, size_t, uint32_t, int);
ssize_t fgetxattr(int, const char *, void *, size_t, uint32_t, int);
int setxattr(const char *, const char *, const void *, size_t, uint32_t, int);
int removexattr(const char *, const char *, int);
ssize_t listxattr(const char *, char *, size_t, int);
__END_DECLS
#endif
