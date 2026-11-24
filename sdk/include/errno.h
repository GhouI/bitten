#ifndef BITTEN_ERRNO_H
#define BITTEN_ERRNO_H
int *__error(void);
#define errno (*__error())
#define ENOENT 2
#define EIO 5
#define EACCES 13
#define EEXIST 17
#define EINVAL 22
#endif
