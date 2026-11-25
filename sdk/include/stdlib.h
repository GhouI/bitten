/* bitten SDK: <stdlib.h>. */
#ifndef BITTEN_STDLIB_H
#define BITTEN_STDLIB_H
#include <sys/_types.h>
#include <malloc/_malloc.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 0x7fffffff
typedef struct { int quot, rem; } div_t;
typedef struct { long quot, rem; } ldiv_t;
typedef struct { long long quot, rem; } lldiv_t;

__BEGIN_DECLS
void abort(void) __dead2;
void exit(int) __dead2;
void _Exit(int) __dead2;
int atexit(void (*)(void));
char *getenv(const char *);
int setenv(const char *, const char *, int);
int unsetenv(const char *);
int putenv(char *);
int system(const char *);
long strtol(const char *restrict, char **restrict, int);
long long strtoll(const char *restrict, char **restrict, int);
unsigned long strtoul(const char *restrict, char **restrict, int);
unsigned long long strtoull(const char *restrict, char **restrict, int);
double strtod(const char *restrict, char **restrict);
float strtof(const char *restrict, char **restrict);
long double strtold(const char *restrict, char **restrict);
double atof(const char *);
int atoi(const char *);
long atol(const char *);
long long atoll(const char *);
int abs(int) __pure2;
long labs(long) __pure2;
long long llabs(long long);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *));
void qsort_r(void *, size_t, size_t, void *, int (*)(void *, const void *, const void *));
void *bsearch(const void *, const void *, size_t, size_t, int (*)(const void *, const void *));
int rand(void);
void srand(unsigned);
int rand_r(unsigned *);
long random(void);
void srandom(unsigned);
void srandomdev(void);
double drand48(void);
long lrand48(void);
void srand48(long);
uint32_t arc4random(void);
void arc4random_buf(void *, size_t);
uint32_t arc4random_uniform(uint32_t);
char *realpath(const char *restrict, char *restrict) __DARWIN_EXTSN(realpath);
char *mkdtemp(char *);
int mkstemp(char *);
int mkostemp(char *, int);
int posix_openpt(int);
int grantpt(int);
int unlockpt(int);
char *ptsname(int);
int ptsname_r(int, char *, size_t);
int mblen(const char *, size_t);
int mbtowc(wchar_t *restrict, const char *restrict, size_t);
int wctomb(char *, wchar_t);
size_t mbstowcs(wchar_t *restrict, const char *restrict, size_t);
size_t wcstombs(char *restrict, const wchar_t *restrict, size_t);
const char *getprogname(void);
void setprogname(const char *);
int daemon(int, int);
__END_DECLS
#endif
