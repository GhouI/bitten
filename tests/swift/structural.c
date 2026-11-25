// Function, existential and existential metatype metadata
// (tests/swift/structural.swift).
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
struct md { unsigned long kind; };
#define VWT(m) (((const struct vwt *const *)(m))[-1])
#define W(m, i) (((const unsigned long *)(m))[i])
#define U32(m, i) (((const unsigned *)(m))[i])

extern const md *md_f1(void), *md_ft(void), *md_fc(void), *md_f2(void), *md_f4(void);
extern const md *md_any(void), *md_anyobject(void), *md_pq(void), *md_cp(void), *md_at(void), *md_pt(void);
extern long fn_call(long, long);
#define PAIR(n) extern void g_nn_##n(void *), c_nn_##n(void *);
PAIR(pq) PAIR(cp) PAIR(f1) PAIR(ft) PAIR(at)
extern const char any_full[] __asm__("_$sypN"), anyobject_full[] __asm__("_$syXlN");
extern const struct vwt closure_vwt __asm__("_$syycWV");
extern const struct { const void *vwt; md m; } i64_md __asm__("_$sBi64_N"), i8_md __asm__("_$sBi8_N");
extern const md *swift_getFunctionTypeMetadata1(unsigned long, const md *, const md *);
extern const md *swift_getExistentialTypeMetadata(unsigned, const md *, unsigned long, const void *const *);

/* A non-POD inline type counting its copies and destroys. */
static int copies, destroys;
static void *t_copy(void *d, void *s, const md *m) { copies++; *(unsigned *)d = *(unsigned *)s; return d; }
static void t_destroy(void *v, const md *m) { destroys++; }
static const struct vwt tracked_vwt = {t_copy, t_destroy, t_copy, t_copy, t_copy, t_copy, 0, 0, 4, 4, 3 | 0x10000, 0};
static const struct { const struct vwt *w; unsigned long kind; } tracked = {&tracked_vwt, 0x300};

static unsigned char g[64], c[64];
#define CMP(n, at, val)                         \
    memset(g, 0xAA, 64), memset(c, 0x55, 64);   \
    g_nn_##n(g), c_nn_##n(c);                   \
    CHECK(W(g + at, 0) == W(c + at, 0) && W(g + at, 0) == (val))

int main(void) {
    const md *i64 = &i64_md.m;
    /* (Int64) -> Int64: escaping Swift closure. */
    const md *f1 = md_f1();
    CHECK(f1 == md_f1() && f1->kind == 0x302 && W(f1, 1) == 0x4000001);
    CHECK(W(f1, 2) == (unsigned long)i64 && W(f1, 3) == (unsigned long)i64);
    CHECK(VWT(f1) == &closure_vwt && VWT(f1)->size == 16);
    CHECK(swift_getFunctionTypeMetadata1(0x4000001, i64, i64) == f1);
    CHECK(swift_getFunctionTypeMetadata1(0x4000001, i64, &i8_md.m) != f1);
    /* thin and C function pointers: one word */
    CHECK(W(md_ft(), 1) == 0x20001 && VWT(md_ft())->size == 8 && VWT(md_ft())->xi == 0x7FFFFFFF);
    CHECK(W(md_fc(), 1) == 0x30001 && VWT(md_fc())->size == 8 && md_fc() != md_ft());
    /* throws, two parameters */
    CHECK(W(md_f2(), 1) == 0x5000002 && W(md_f2(), 4) == (unsigned long)&i8_md.m);
    /* parameter flags (inout, __owned) follow the parameters */
    const md *f4 = md_f4();
    CHECK(W(f4, 1) == 0x6000004 && f4 == md_f4());
    CHECK(U32(f4, 2 * 7) != 0 && U32(f4, 2 * 7 + 1) != 0 && U32(f4, 2 * 7 + 2) == 0);

    /* Any, AnyObject: the runtime's own {witnesses, metadata} */
    CHECK(md_any() == (const md *)(any_full + 8) && md_any()->kind == 0x303);
    CHECK(VWT(md_any())->size == 32 && (VWT(md_any())->flags & 0x20000));
    CHECK(md_anyobject() == (const md *)(anyobject_full + 8) && VWT(md_anyobject())->size == 8);
    /* P & Q: opaque, two witness tables */
    const md *pq = md_pq();
    CHECK(pq == md_pq() && pq->kind == 0x303 && U32(pq, 2) == 0x80000002 && U32(pq, 3) == 2);
    CHECK(VWT(pq)->size == 48 && VWT(pq)->xi == 0x7FFFFFFF);
    CHECK(swift_getExistentialTypeMetadata(1, 0, 2, (const void *const *)&W(pq, 2)) == pq);
    /* CP: class-bound */
    const md *cp = md_cp();
    CHECK(U32(cp, 2) == 1 && U32(cp, 3) == 1 && VWT(cp)->size == 16);
    /* Any.Type, any P.Type */
    const md *at = md_at();
    CHECK(at->kind == 0x306 && W(at, 1) == (unsigned long)md_any() && VWT(at)->size == 8);
    const md *pt = md_pt();
    CHECK(pt->kind == 0x306 && U32(pt, 4) == 0x80000001 && VWT(pt)->size == 16);
    CHECK(((const md *)W(pt, 1))->kind == 0x303);

    /* Extra inhabitants as the compiler encodes them: type words and object
     * references i << 1, function pointers i. */
    CMP(pq, 24, 2);
    CMP(cp, 0, 2);
    CMP(f1, 0, 1);
    CMP(ft, 0, 1);
    CMP(at, 0, 2);

    /* Opaque existential witnesses run the contained type's. */
    unsigned long e[6] = {7, 0, 0, (unsigned long)&tracked.kind, 1, 2}, e2[6] = {0};
    VWT(pq)->init_copy(e2, e, pq);
    CHECK(copies == 1 && e2[0] == 7 && e2[3] == e[3] && e2[5] == 2);
    VWT(pq)->assign_copy(e2, e, pq);
    CHECK(copies == 2 && destroys == 1);
    VWT(pq)->destroy(e2, pq);
    CHECK(destroys == 2);

    CHECK(fn_call(3, 4) == 7);
    puts("swift structural ok");
    return 0;
}
