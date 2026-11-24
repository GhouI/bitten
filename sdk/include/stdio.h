#ifndef BITTEN_STDIO_H
#define BITTEN_STDIO_H
#include <stdarg.h>
#include <stddef.h>
typedef struct __sFILE FILE;
extern FILE *__stdinp, *__stdoutp, *__stderrp;
#define stdin __stdinp
#define stdout __stdoutp
#define stderr __stderrp
#define EOF (-1)
int printf(const char *, ...) __attribute__((format(printf, 1, 2)));
int fprintf(FILE *, const char *, ...) __attribute__((format(printf, 2, 3)));
int snprintf(char *, size_t, const char *, ...) __attribute__((format(printf, 3, 4)));
int vsnprintf(char *, size_t, const char *, va_list);
int vfprintf(FILE *, const char *, va_list);
int dprintf(int, const char *, ...) __attribute__((format(printf, 2, 3)));
int puts(const char *);
int fputs(const char *, FILE *);
int fputc(int, FILE *);
int fflush(FILE *);
FILE *fopen(const char *, const char *);
int fclose(FILE *);
size_t fread(void *, size_t, size_t, FILE *);
size_t fwrite(const void *, size_t, size_t, FILE *);
char *fgets(char *, int, FILE *);
int remove(const char *);
int rename(const char *, const char *);
#endif
