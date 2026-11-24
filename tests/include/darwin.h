/* Minimal hand-written declarations for the Mach-O test programs. They use
 * Darwin's ABI (struct layouts, constants) and are not Apple headers. */
#ifndef TESTS_DARWIN_H
#define TESTS_DARWIN_H
typedef unsigned long size_t;
typedef long ssize_t;
typedef long off_t;
typedef int pid_t;
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;
typedef int int32_t;
typedef long long int64_t;
#define NULL ((void *)0)

int printf(const char *, ...);
int snprintf(char *, size_t, const char *, ...);
int puts(const char *);
void *malloc(size_t);
void free(void *);
void *memset(void *, int, size_t);
void *memcpy(void *, const void *, size_t);
int memcmp(const void *, const void *, size_t);
size_t strlen(const char *);
int strcmp(const char *, const char *);
char *strerror(int);
char *getenv(const char *);
void exit(int) __attribute__((noreturn));
int *__error(void);
#define errno (*__error())

#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);           \
            exit(1);                                                         \
        }                                                                    \
    } while (0)
#endif
