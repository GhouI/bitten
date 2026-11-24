#ifndef BITTEN_ERRNO_H
#define BITTEN_ERRNO_H
int *__error(void);
#define errno (*__error())
#define ENOENT 2
#define EIO 5
#define EACCES 13
#define EEXIST 17
#define ENOTDIR 20
#define EISDIR 21
#define EINVAL 22
#define ENOSPC 28
#define ENOTEMPTY 66
#define ETIMEDOUT 60
#endif
