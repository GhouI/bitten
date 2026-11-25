/* bitten SDK: <stdio.h>. FILE has the macOS layout so that it imports the
 * same way, but bitten's streams are its own: no field is meaningful. */
#ifndef BITTEN_STDIO_H
#define BITTEN_STDIO_H
#include <sys/_types.h>
#include <stdarg.h>

typedef long long fpos_t;
struct __sbuf {
    unsigned char *_base;
    int _size;
};
struct __sFILEX;
typedef struct __sFILE {
    unsigned char *_p;
    int _r, _w;
    short _flags, _file;
    struct __sbuf _bf;
    int _lbfsize;
    void *_cookie;
    int (*_close)(void *);
    int (*_read)(void *, char *, int);
    fpos_t (*_seek)(void *, fpos_t, int);
    int (*_write)(void *, const char *, int);
    struct __sbuf _ub;
    struct __sFILEX *_extra;
    int _ur;
    unsigned char _ubuf[3];
    unsigned char _nbuf[1];
    struct __sbuf _lb;
    int _blksize;
    fpos_t _offset;
} FILE;
__BEGIN_DECLS
extern FILE *__stdinp, *__stdoutp, *__stderrp;
__END_DECLS
#define stdin __stdinp
#define stdout __stdoutp
#define stderr __stderrp
#define EOF (-1)
#define BUFSIZ 1024
#define FILENAME_MAX 1024
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2

__BEGIN_DECLS
int printf(const char *restrict, ...) __printflike(1, 2);
int fprintf(FILE *restrict, const char *restrict, ...) __printflike(2, 3);
int sprintf(char *restrict, const char *restrict, ...) __printflike(2, 3);
int snprintf(char *restrict, size_t, const char *restrict, ...) __printflike(3, 4);
int asprintf(char **restrict, const char *restrict, ...) __printflike(2, 3);
int dprintf(int, const char *restrict, ...) __printflike(2, 3);
int vprintf(const char *restrict, va_list) __printflike(1, 0);
int vfprintf(FILE *restrict, const char *restrict, va_list) __printflike(2, 0);
int vsprintf(char *restrict, const char *restrict, va_list) __printflike(2, 0);
int vsnprintf(char *restrict, size_t, const char *restrict, va_list) __printflike(3, 0);
int vasprintf(char **restrict, const char *restrict, va_list) __printflike(2, 0);
int vdprintf(int, const char *restrict, va_list) __printflike(2, 0);
int scanf(const char *restrict, ...) __scanflike(1, 2);
int fscanf(FILE *restrict, const char *restrict, ...) __scanflike(2, 3);
int sscanf(const char *restrict, const char *restrict, ...) __scanflike(2, 3);
int vsscanf(const char *restrict, const char *restrict, va_list) __scanflike(2, 0);
int puts(const char *);
int fputs(const char *restrict, FILE *restrict);
int fputc(int, FILE *);
int putc(int, FILE *);
int putchar(int);
int putc_unlocked(int, FILE *);
int putchar_unlocked(int);
int fgetc(FILE *);
int getc(FILE *);
int getchar(void);
int getc_unlocked(FILE *);
int getchar_unlocked(void);
int ungetc(int, FILE *);
char *fgets(char *restrict, int, FILE *restrict);
ssize_t getline(char **restrict, size_t *restrict, FILE *restrict);
ssize_t getdelim(char **restrict, size_t *restrict, int, FILE *restrict);
FILE *fopen(const char *restrict, const char *restrict) __DARWIN_EXTSN(fopen);
FILE *fdopen(int, const char *);
FILE *freopen(const char *restrict, const char *restrict, FILE *restrict);
FILE *tmpfile(void);
FILE *popen(const char *, const char *);
int pclose(FILE *);
int fclose(FILE *);
int fflush(FILE *);
size_t fread(void *restrict, size_t, size_t, FILE *restrict);
size_t fwrite(const void *restrict, size_t, size_t, FILE *restrict);
int fseek(FILE *, long, int);
int fseeko(FILE *, off_t, int);
long ftell(FILE *);
off_t ftello(FILE *);
void rewind(FILE *);
int feof(FILE *);
int ferror(FILE *);
void clearerr(FILE *);
int fileno(FILE *);
void setbuf(FILE *restrict, char *restrict);
int setvbuf(FILE *restrict, char *restrict, int, size_t);
void setlinebuf(FILE *);
void flockfile(FILE *);
void funlockfile(FILE *);
void perror(const char *);
int remove(const char *);
int rename(const char *, const char *);
int renameat(int, const char *, int, const char *);
char *ctermid(char *);
__END_DECLS
#endif
