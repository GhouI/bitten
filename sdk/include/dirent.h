#ifndef BITTEN_DIRENT_H
#define BITTEN_DIRENT_H
#include <stdint.h>
struct dirent {
    uint64_t d_ino, d_seekoff;
    uint16_t d_reclen, d_namlen;
    uint8_t d_type;
    char d_name[1024];
};
typedef struct _dirdesc DIR;
#define DT_DIR 4
#define DT_REG 8
#define DT_LNK 10
DIR *opendir(const char *) __asm("_opendir$INODE64");
struct dirent *readdir(DIR *) __asm("_readdir$INODE64");
int closedir(DIR *);
#endif
