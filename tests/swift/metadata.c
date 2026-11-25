// Generic struct, tuple and metatype metadata built by the runtime, checked
// against the layouts the compiler expects (tests/swift/metadata.swift).
#include "darwin.h"

typedef struct md md;
struct vwt {
    void *(*init_buffer)(void *, void *, const md *);
    void (*destroy)(void *, const md *);
    void *(*init_copy)(void *, void *, const md *);
    void *(*assign_copy)(void *, void *, const md *);
    void *(*init_take)(void *, void *, const md *);
    void *(*assign_take)(void *, void *, const md *);
    unsigned (*get_tag)(const void *, unsigned, const md *);
    void (*store_tag)(void *, unsigned, unsigned, const md *);
    unsigned long size, stride;
    unsigned flags, xi;
};
struct md { unsigned long kind; const void *desc; const void *args[]; };
typedef struct { const md *m; unsigned long state; } resp;

#define VWT(m) (((const struct vwt *const *)(m))[-1])
#define NON_POD 0x10000u
#define NON_INLINE 0x20000u

extern resp pair_ma(unsigned long, const md *, const md *) __asm__("_$s8metadata4PairVMa");
extern resp wrap_ma(unsigned long, const md *) __asm__("_$s8metadata4WrapVMa");
extern resp nest_ma(unsigned long, const md *) __asm__("_$s8metadata4NestVMa");
extern resp tup_ma(unsigned long, const md *, const md *) __asm__("_$s8metadata3TupVMa");
extern resp meta_ma(unsigned long, const md *) __asm__("_$s8metadata4MetaVMa");
extern const char pair_desc[] __asm__("_$s8metadata4PairVMn");
extern const struct { const void *vwt; md m; } i1_md __asm__("_$sBi1_N"), i8_md __asm__("_$sBi8_N"),
    i16_md __asm__("_$sBi16_N"), i32_md __asm__("_$sBi32_N"), i64_md __asm__("_$sBi64_N"),
    ptr_md __asm__("_$sBpN"), f80_md __asm__("_$sBf80_N"), empty_md __asm__("_$sytN");
extern resp swift_getTupleTypeMetadata(unsigned long, unsigned long, const md *const *, const char *, const void *);
extern resp swift_getTupleTypeMetadata2(unsigned long, const md *, const md *, const char *, const void *);
extern resp swift_checkMetadataState(unsigned long, const md *);
extern const md *swift_getMetatypeMetadata(const md *);

extern char meta_nested(long, double, char);
extern long meta_swap(long, char);
extern int meta_wrap(int);

#define I1 (&i1_md.m)
#define I8 (&i8_md.m)
#define I16 (&i16_md.m)
#define I32 (&i32_md.m)
#define I64 (&i64_md.m)

static const unsigned *offsets(const md *m, int word) {
    return (const unsigned *)((const unsigned long *)m + word);
}

/* A non-POD 4-byte type defined here: counts its copies and destroys and
 * has 16 extra inhabitants, 0xFFFFFFF0 + i. */
static int copies, destroys, takes;
static const md tracked;
static void *t_copy(void *d, void *s, const md *m) { copies++; *(unsigned *)d = *(unsigned *)s; return d; }
static void *t_take(void *d, void *s, const md *m) { takes++; *(unsigned *)d = *(unsigned *)s; return d; }
static void t_destroy(void *v, const md *m) { destroys++; }
static void *t_assign(void *d, void *s, const md *m) { destroys++; return t_copy(d, s, m); }
static void *t_buf(void *d, void *s, const md *m) { return t_copy(d, s, m); }
static unsigned t_get_tag(const void *v, unsigned n, const md *m) {
    unsigned x = *(const unsigned *)v;
    return x >= 0xFFFFFFF0u && x - 0xFFFFFFF0u < n ? x - 0xFFFFFFF0u + 1 : 0;
}
static void t_store_tag(void *v, unsigned which, unsigned n, const md *m) {
    if (which) *(unsigned *)v = 0xFFFFFFF0u + which - 1;
}
static const struct vwt tracked_vwt = {t_buf, t_destroy, t_copy, t_assign, t_take, t_assign,
                                       t_get_tag, t_store_tag, 4, 4, 3 | NON_POD, 16};
static const struct { const struct vwt *w; unsigned long kind; } tracked_full = {&tracked_vwt, 0x300};
#define TRACKED ((const md *)&tracked_full.kind)

int main(void) {
    /* builtin metadata: {vwt, kind} */
    CHECK(i64_md.m.kind == 0x300 && VWT(I64)->size == 8 && (VWT(I64)->flags & 0xff) == 7);
    CHECK(VWT(I1)->xi == 254 && VWT(&ptr_md.m)->xi == 1 && VWT(I64)->xi == 0);
    CHECK(VWT(&f80_md.m)->size == 16 && (VWT(&f80_md.m)->flags & (NON_INLINE | 0xff)) == (NON_INLINE | 15));
    CHECK(empty_md.m.kind == 0x301 && VWT(&empty_md.m)->size == 0 && VWT(&empty_md.m)->stride == 1);

    /* Pair<Int64, Int8> */
    resp r = pair_ma(0, I64, I8);
    const md *p = r.m;
    CHECK(r.state == 0 && p->kind == 0x200 && p->desc == pair_desc);
    CHECK(p->args[0] == I64 && p->args[1] == I8);
    CHECK(offsets(p, 4)[0] == 0 && offsets(p, 4)[1] == 8);
    CHECK(VWT(p)->size == 9 && VWT(p)->stride == 16 && VWT(p)->flags == 7 && VWT(p)->xi == 0);
    CHECK(pair_ma(0, I64, I8).m == p); /* uniqued */
    CHECK(swift_checkMetadataState(0, p).state == 0);

    const md *q = pair_ma(0, I8, I64).m;
    CHECK(q != p && offsets(q, 4)[1] == 8 && VWT(q)->size == 16);
    CHECK(VWT(pair_ma(0, I1, I64).m)->xi == 254);
    CHECK(VWT(pair_ma(0, I8, &ptr_md.m).m)->xi == 1);
    const md *pf = pair_ma(0, &f80_md.m, I8).m;
    CHECK(VWT(pf)->size == 17 && VWT(pf)->stride == 32 && (VWT(pf)->flags & 0xff) == 15);
    CHECK(VWT(pf)->flags & NON_INLINE);

    /* Wrap<Int32> { x: Int8, p: Pair<Int32, Int8>, t: Int32 } */
    const md *w = wrap_ma(0, I32).m;
    CHECK(offsets(w, 3)[0] == 0 && offsets(w, 3)[1] == 4 && offsets(w, 3)[2] == 12);
    CHECK(VWT(w)->size == 16 && VWT(w)->stride == 16 && VWT(w)->flags == 3);

    /* Nest<Int16> { w: Wrap<Pair<Int16, Int16>>, b: Int1 } */
    const md *n = nest_ma(0, I16).m;
    CHECK(offsets(n, 3)[0] == 0 && offsets(n, 3)[1] == 12);
    CHECK(VWT(n)->size == 13 && VWT(n)->stride == 14 && VWT(n)->xi == 254);
    const md *pi16 = pair_ma(0, I16, I16).m;
    CHECK(wrap_ma(0, pi16).m->args[0] == pi16);

    /* Tup<Int64, Int8> { t: (Int64, Int8, Int8) } */
    const md *t = tup_ma(0, I64, I8).m;
    CHECK(VWT(t)->size == 10 && VWT(t)->stride == 16);

    /* Meta<Int64> { m: Int64.Type } */
    const md *mt = meta_ma(0, I64).m;
    CHECK(VWT(mt)->size == 8 && VWT(mt)->xi == 0x7FFFFFFF);
    const md *mm = swift_getMetatypeMetadata(I64);
    CHECK(mm == swift_getMetatypeMetadata(I64) && mm->kind == 0x304 && mm->desc == (const void *)I64);

    /* Value witnesses of Pair<Tracked, Int64> run the element's. */
    const md *pt = pair_ma(0, TRACKED, I64).m;
    CHECK(VWT(pt)->size == 16 && (VWT(pt)->flags & NON_POD) && VWT(pt)->xi == 16);
    unsigned long a[2] = {5, 77}, b[2] = {0, 0};
    VWT(pt)->init_copy(b, a, pt);
    CHECK(copies == 1 && b[0] == 5 && b[1] == 77);
    VWT(pt)->destroy(b, pt);
    CHECK(destroys == 1);
    VWT(pt)->init_take(b, a, pt);
    CHECK(takes <= 1 && b[1] == 77);
    /* As the payload of an enum with 20 empty cases: 16 fit in Tracked's
     * extra inhabitants, the other 4 need a tag byte after the payload. */
    unsigned char e[17];
    memset(e, 0xAA, sizeof e);
    VWT(pt)->store_tag(e, 3, 20, pt);
    CHECK(*(unsigned *)e == 0xFFFFFFF2u && VWT(pt)->get_tag(e, 20, pt) == 3);
    CHECK(e[16] == 0);
    VWT(pt)->store_tag(e, 18, 20, pt);
    CHECK(e[16] == 1 && *(unsigned *)e == 1 && *(unsigned *)(e + 4) == 0);
    CHECK(VWT(pt)->get_tag(e, 20, pt) == 18);
    VWT(pt)->store_tag(e, 0, 20, pt);
    CHECK(e[16] == 0);
    *(unsigned *)e = 5;
    CHECK(VWT(pt)->get_tag(e, 20, pt) == 0);

    /* Tuples: uniqued, laid out like structs, element witnesses. */
    resp t2 = swift_getTupleTypeMetadata2(0, I8, TRACKED, NULL, NULL);
    const unsigned long *tw = (const unsigned long *)t2.m;
    CHECK(t2.m->kind == 0x301 && tw[1] == 2 && tw[2] == 0);
    CHECK(tw[3] == (unsigned long)I8 && (unsigned)tw[4] == 0);
    CHECK(tw[5] == (unsigned long)TRACKED && (unsigned)tw[6] == 4);
    CHECK(VWT(t2.m)->size == 8 && VWT(t2.m)->xi == 16 && (VWT(t2.m)->flags & NON_POD));
    CHECK(swift_getTupleTypeMetadata2(0, I8, TRACKED, NULL, NULL).m == t2.m);
    CHECK(swift_getTupleTypeMetadata2(0, I8, TRACKED, "a b ", NULL).m != t2.m);
    const md *els[3] = {I8, TRACKED, I64};
    resp t3 = swift_getTupleTypeMetadata(0, 3, els, NULL, NULL);
    CHECK(VWT(t3.m)->size == 16 && swift_getTupleTypeMetadata(0, 3, els, NULL, NULL).m == t3.m);
    copies = destroys = 0;
    unsigned long x[2] = {0x500000001ul, 9}, y[2];
    VWT(t3.m)->init_copy(y, x, t3.m);
    VWT(t3.m)->assign_copy(y, x, t3.m);
    VWT(t3.m)->destroy(y, t3.m);
    CHECK(copies == 2 && destroys == 2 && y[0] == x[0] && y[1] == 9);

    /* The compiler's own generic code going through the runtime. */
    CHECK(meta_nested(5, 1.5, 7) == 7);
    CHECK(meta_swap(9, 3) == 9);
    CHECK(meta_wrap(42) == 42);
    puts("swift metadata ok");
    return 0;
}
