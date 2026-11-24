/* bitten SDK: minimal C library declarations (the functions bitten's libSystem implements). */
#ifndef BITTEN_STDLIB_H
#define BITTEN_STDLIB_H
#include <stddef.h>
void *malloc(size_t);
void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void free(void *);
void abort(void) __attribute__((noreturn));
void exit(int) __attribute__((noreturn));
int atexit(void (*)(void));
char *getenv(const char *);
int setenv(const char *, const char *, int);
long strtol(const char *, char **, int);
long long strtoll(const char *, char **, int);
unsigned long strtoul(const char *, char **, int);
unsigned long long strtoull(const char *, char **, int);
double strtod(const char *, char **);
int atoi(const char *);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *));
void qsort_r(void *, size_t, size_t, void *, int (*)(void *, const void *, const void *));
unsigned int arc4random(void);
void arc4random_buf(void *, size_t);
unsigned int arc4random_uniform(unsigned int);
char *realpath(const char *, char *);
#endif
