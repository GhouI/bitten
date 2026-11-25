/* bitten SDK: the allocation functions <stdlib.h> and <malloc/malloc.h> share. */
#ifndef BITTEN_MALLOC__MALLOC_H
#define BITTEN_MALLOC__MALLOC_H
#include <sys/_types.h>
__BEGIN_DECLS
void *malloc(size_t);
void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void *reallocf(void *, size_t);
void *valloc(size_t);
void *aligned_alloc(size_t, size_t);
int posix_memalign(void **, size_t, size_t);
void free(void *);
__END_DECLS
#endif
