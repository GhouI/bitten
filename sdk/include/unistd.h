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
unsigned int geteuid(void);
long sysconf(int);
#define _SC_NPROCESSORS_ONLN 58
#define _SC_PHYS_PAGES 200
ssize_t readlink(const char *, char *, size_t);
int symlink(const char *, const char *);
int fsync(int);
off_t lseek(int, off_t, int);
int ftruncate(int, off_t);
int isatty(int);
int pipe(int[2]);
int dup2(int, int);
#define R_OK 4
#define W_OK 2
#define X_OK 1
#define F_OK 0
int *_NSGetArgc(void);
char ***_NSGetArgv(void);
char ***_NSGetEnviron(void);
int gethostname(char *, size_t);
#endif
