/* bitten SDK: <unistd.h>. */
#ifndef BITTEN_UNISTD_H
#define BITTEN_UNISTD_H
#include <sys/_types.h>

#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define R_OK 4
#define W_OK 2
#define X_OK 1
#define F_OK 0
#ifndef SEEK_SET
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#endif

#define _SC_ARG_MAX 1
#define _SC_CHILD_MAX 2
#define _SC_CLK_TCK 3
#define _SC_NGROUPS_MAX 4
#define _SC_OPEN_MAX 5
#define _SC_PAGESIZE 29
#define _SC_PAGE_SIZE _SC_PAGESIZE
#define _SC_NPROCESSORS_CONF 57
#define _SC_NPROCESSORS_ONLN 58
#define _SC_PHYS_PAGES 200
#define _CS_PATH 1
#define _CS_DARWIN_USER_DIR 65536
#define _CS_DARWIN_USER_TEMP_DIR 65537
#define _CS_DARWIN_USER_CACHE_DIR 65538

__BEGIN_DECLS
ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
ssize_t pread(int, void *, size_t, off_t);
ssize_t pwrite(int, const void *, size_t, off_t);
int close(int);
off_t lseek(int, off_t, int);
int dup(int);
int dup2(int, int);
int pipe(int[2]);
int fsync(int);
int fdatasync(int);
int ftruncate(int, off_t);
int truncate(const char *, off_t);
int isatty(int);
char *ttyname(int);
int ttyname_r(int, char *, size_t);
int access(const char *, int);
int faccessat(int, const char *, int, int);
int chdir(const char *);
int fchdir(int);
char *getcwd(char *, size_t);
int chown(const char *, uid_t, gid_t);
int fchown(int, uid_t, gid_t);
int lchown(const char *, uid_t, gid_t);
int fchownat(int, const char *, uid_t, gid_t, int);
int link(const char *, const char *);
int linkat(int, const char *, int, const char *, int);
int symlink(const char *, const char *);
int symlinkat(const char *, int, const char *);
ssize_t readlink(const char *restrict, char *restrict, size_t);
ssize_t readlinkat(int, const char *restrict, char *restrict, size_t);
int unlink(const char *);
int unlinkat(int, const char *, int);
int rmdir(const char *);
int chroot(const char *);
void sync(void);
pid_t getpid(void);
pid_t getppid(void);
pid_t getpgrp(void);
pid_t getpgid(pid_t);
pid_t getsid(pid_t);
int setpgid(pid_t, pid_t);
pid_t setsid(void);
pid_t tcgetpgrp(int);
int tcsetpgrp(int, pid_t);
uid_t getuid(void);
uid_t geteuid(void);
gid_t getgid(void);
gid_t getegid(void);
int setuid(uid_t);
int seteuid(uid_t);
int setgid(gid_t);
int setegid(gid_t);
int setreuid(uid_t, uid_t);
int setregid(gid_t, gid_t);
int getgroups(int, gid_t[]);
int setgroups(int, const gid_t *);
int getgrouplist(const char *, int, int *, int *);
char *getlogin(void);
int issetugid(void);
pid_t fork(void);
pid_t vfork(void);
int execv(const char *, char *const[]);
int execve(const char *, char *const[], char *const[]);
int execvp(const char *, char *const[]);
int execl(const char *, const char *, ...);
int execlp(const char *, const char *, ...);
void _exit(int) __dead2;
unsigned int sleep(unsigned int);
int usleep(useconds_t);
int nice(int);
long sysconf(int);
size_t confstr(int, char *, size_t);
int getpagesize(void) __pure2;
int getdtablesize(void);
int gethostname(char *, size_t);
int gethostuuid(unsigned char[16], const struct timespec *);
int getentropy(void *, size_t);
int getopt(int, char *const[], const char *);
extern char *optarg;
extern int optind, opterr, optopt;
int *_NSGetArgc(void);
char ***_NSGetArgv(void);
char ***_NSGetEnviron(void);
__END_DECLS
#endif
