/* bitten SDK: compiler and linkage macros shared by the C headers. */
#ifndef BITTEN_SYS_CDEFS_H
#define BITTEN_SYS_CDEFS_H

#ifdef __cplusplus
#define __BEGIN_DECLS extern "C" {
#define __END_DECLS }
#else
#define __BEGIN_DECLS
#define __END_DECLS
#endif

#define __dead2 __attribute__((__noreturn__))
#define __pure2 __attribute__((__const__))
#define __unused __attribute__((__unused__))
#define __printflike(f, a) __attribute__((__format__(__printf__, f, a)))
#define __scanflike(f, a) __attribute__((__format__(__scanf__, f, a)))
#ifndef __has_feature
#define __has_feature(x) 0
#endif
#if !__has_feature(nullability)
#define _Nullable
#define _Nonnull
#define _Null_unspecified
#endif

/* Symbol variants of the 64-bit inode ABI and of the UNIX 2003 / extended
 * behaviours: on x86-64 macOS some functions are linked under a suffixed
 * name. */
#define __DARWIN_INODE64(sym) __asm("_" #sym "$INODE64")
#define __DARWIN_EXTSN(sym) __asm("_" #sym "$DARWIN_EXTSN")
#define __DARWIN_ALIAS(sym)
#define __DARWIN_ALIAS_C(sym)

/* Swift naming helpers (ignored by compilers without the attributes). */
#if defined(__has_attribute) && __has_attribute(swift_name)
#define __SWIFT_NAME(n) __attribute__((swift_name(n)))
#else
#define __SWIFT_NAME(n)
#endif
#endif
