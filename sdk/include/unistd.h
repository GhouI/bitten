#ifndef BITTEN_UNISTD_H
#define BITTEN_UNISTD_H
#include <stddef.h>
typedef long ssize_t;
typedef long long off_t;
typedef int pid_t;
ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
int close(int);
pid_t getpid(void);
unsigned int getuid(void);
int unlink(const char *);
int rmdir(const char *);
int access(const char *, int);
char *getcwd(char *, size_t);
int chdir(const char *);
unsigned int sleep(unsigned int);
int usleep(unsigned int);
const char *getprogname(void);
int gethostname(char *, size_t);
#endif
