/* bitten SDK: <ctype.h>. */
#ifndef BITTEN_CTYPE_H
#define BITTEN_CTYPE_H
#include <sys/cdefs.h>
__BEGIN_DECLS
int isalnum(int);
int isalpha(int);
int isblank(int);
int iscntrl(int);
int isdigit(int);
int isgraph(int);
int islower(int);
int isprint(int);
int ispunct(int);
int isspace(int);
int isupper(int);
int isxdigit(int);
int tolower(int);
int toupper(int);
__END_DECLS
#endif
