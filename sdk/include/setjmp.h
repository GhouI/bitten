/* bitten SDK: <setjmp.h>, Darwin's x86-64 buffer sizes. */
#ifndef BITTEN_SETJMP_H
#define BITTEN_SETJMP_H
#include <sys/cdefs.h>
#define _JBLEN ((9 * 2) + 3 + 16)
typedef int jmp_buf[_JBLEN];
typedef int sigjmp_buf[_JBLEN + 1];
__BEGIN_DECLS
int setjmp(jmp_buf) __attribute__((returns_twice));
void longjmp(jmp_buf, int) __dead2;
int _setjmp(jmp_buf) __attribute__((returns_twice));
void _longjmp(jmp_buf, int) __dead2;
int sigsetjmp(sigjmp_buf, int) __attribute__((returns_twice));
void siglongjmp(sigjmp_buf, int) __dead2;
__END_DECLS
#endif
