/* bitten SDK: <malloc/malloc.h>. Zones are opaque. */
#ifndef BITTEN_MALLOC_MALLOC_H
#define BITTEN_MALLOC_MALLOC_H
#include <malloc/_malloc.h>
typedef struct _malloc_zone_t malloc_zone_t;
__BEGIN_DECLS
size_t malloc_size(const void *);
size_t malloc_good_size(size_t);
malloc_zone_t *malloc_default_zone(void);
malloc_zone_t *malloc_create_zone(size_t, unsigned);
void malloc_destroy_zone(malloc_zone_t *);
malloc_zone_t *malloc_zone_from_ptr(const void *);
void *malloc_zone_malloc(malloc_zone_t *, size_t);
void *malloc_zone_calloc(malloc_zone_t *, size_t, size_t);
void *malloc_zone_valloc(malloc_zone_t *, size_t);
void *malloc_zone_realloc(malloc_zone_t *, void *, size_t);
void *malloc_zone_memalign(malloc_zone_t *, size_t, size_t);
void malloc_zone_free(malloc_zone_t *, void *);
void malloc_set_zone_name(malloc_zone_t *, const char *);
__END_DECLS
#endif
