/* The C++ runtime's allocation entry points (libc++abi's operator new and
 * delete, in their Itanium-mangled Darwin names): plain, array, sized,
 * nothrow and aligned forms over malloc. There are no C++ exceptions
 * here, so an allocation that fails aborts with a message where libc++
 * would throw std::bad_alloc. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dx.h"

static void *must(void *p, size_t n) {
    if (!p && n) {
        fprintf(stderr, "bitten: operator new(%zu) failed (std::bad_alloc)\n", n);
        abort();
    }
    return p;
}
static void *aligned(size_t n, size_t align) {
    if (align < sizeof(void *)) align = sizeof(void *);
    void *p = NULL;
    if (posix_memalign(&p, align, n ? n : 1)) p = NULL;
    return p;
}

static void *d_new(size_t n) { return must(malloc(n ? n : 1), n); }
static void *d_new_nothrow(size_t n, const void *tag) { return malloc(n ? n : 1); }
static void *d_new_aligned(size_t n, size_t align) { return must(aligned(n, align), n); }
static void *d_new_aligned_nothrow(size_t n, size_t align, const void *tag) { return aligned(n, align); }
static void d_delete(void *p) { free(p); }
static void d_delete_sized(void *p, size_t n) { free(p); }
static void d_delete_aligned(void *p, size_t align) { free(p); }
static void d_delete_sized_aligned(void *p, size_t n, size_t align) { free(p); }
static void d_delete_nothrow(void *p, const void *tag) { free(p); }

/* operator new / new[] (unsigned long), nothrow, align_val_t */
DX_EXPORT("__Znwm", d_new);
DX_EXPORT("__Znam", d_new);
DX_EXPORT("__ZnwmRKSt9nothrow_t", d_new_nothrow);
DX_EXPORT("__ZnamRKSt9nothrow_t", d_new_nothrow);
DX_EXPORT("__ZnwmSt11align_val_t", d_new_aligned);
DX_EXPORT("__ZnamSt11align_val_t", d_new_aligned);
DX_EXPORT("__ZnwmSt11align_val_tRKSt9nothrow_t", d_new_aligned_nothrow);
DX_EXPORT("__ZnamSt11align_val_tRKSt9nothrow_t", d_new_aligned_nothrow);
/* operator delete / delete[]: plain, sized, aligned, nothrow */
DX_EXPORT("__ZdlPv", d_delete);
DX_EXPORT("__ZdaPv", d_delete);
DX_EXPORT("__ZdlPvm", d_delete_sized);
DX_EXPORT("__ZdaPvm", d_delete_sized);
DX_EXPORT("__ZdlPvSt11align_val_t", d_delete_aligned);
DX_EXPORT("__ZdaPvSt11align_val_t", d_delete_aligned);
DX_EXPORT("__ZdlPvmSt11align_val_t", d_delete_sized_aligned);
DX_EXPORT("__ZdaPvmSt11align_val_t", d_delete_sized_aligned);
DX_EXPORT("__ZdlPvRKSt9nothrow_t", d_delete_nothrow);
DX_EXPORT("__ZdaPvRKSt9nothrow_t", d_delete_nothrow);
