// Enum layouts and tags from the runtime against the compiler's own
// (tests/swift/enums.swift): g_* go through generic code and the runtime,
// c_* are the compiler's fixed layouts for the same types.
#include "darwin.h"

typedef struct md md;
struct vwt {
    void *fn[6];
    unsigned (*get_tag)(const void *, unsigned, const md *);
    void (*store_tag)(void *, unsigned, unsigned, const md *);
    unsigned long size, stride;
    unsigned flags, xi;
};
struct md { unsigned long kind; const void *desc; const void *rest[]; };
typedef struct { const md *m; unsigned long state; } resp;
#define VWT(m) (((const struct vwt *const *)(m))[-1])
#define ENUM_WITNESSES 0x200000u

extern resp mp_ma(unsigned long, const md *, const md *) __asm__("_$ss2MPOMa");
extern resp e3_ma(unsigned long, const md *) __asm__("_$ss2E3OMa");
extern resp one_ma(unsigned long, const md *) __asm__("_$ss3OneOMa");
extern resp big_ma(unsigned long, const md *) __asm__("_$ss3BigOMa");
extern resp opt_ma(unsigned long, const md *) __asm__("_$sSqMa");
extern const struct { const void *vwt; md m; } i1_md __asm__("_$sBi1_N"), i8_md __asm__("_$sBi8_N"),
    i32_md __asm__("_$sBi32_N"), i64_md __asm__("_$sBi64_N"), ptr_md __asm__("_$sBpN");
extern unsigned swift_getEnumCaseMultiPayload(const void *, const md *);
extern void swift_storeEnumTagMultiPayload(void *, const md *, unsigned);

#define I1 (&i1_md.m)
#define I8 (&i8_md.m)
#define I32 (&i32_md.m)
#define I64 (&i64_md.m)
#define PTR (&ptr_md.m)

extern void g_mp_b(void *, char), c_mp_b(void *, char);
extern void g_mp_d(void *), c_mp_d(void *), g_mp_d8(void *), c_mp_d8(void *);
extern void g_e3z8(void *), c_e3z8(void *), g_e3z1(void *), c_e3z1(void *);
extern void g_e3zp(void *), c_e3zp(void *), g_e3p8(void *, char), g_big(void *), c_big(void *);
extern void g_opt_mp_none(void *), c_opt_mp_none(void *);
extern void g_opt_opt1_none(void *), c_opt_opt1_none(void *);
extern void g_opt_opt1_some_none(void *), c_opt_opt1_some_none(void *);
extern long g_mp_case(const void *, long, long, long, long);
extern long g_opt_case(const void *, long, long);

static unsigned char g[32], c[32];
static void fill(void) { memset(g, 0xAA, sizeof g); memset(c, 0x55, sizeof c); }
#define SAME(n) (!memcmp(g, c, n))

int main(void) {
    /* MP<Int64, Int8> { a(T), b(U), c, d }: 8-byte payload area, one tag
     * byte; tags 0, 1 for the payloads, 2 for the empty cases; 253 spare. */
    const md *mp = mp_ma(0, I64, I8).m;
    CHECK(mp->kind == 0x201 && mp_ma(0, I64, I8).m == mp);
    CHECK(VWT(mp)->size == 9 && VWT(mp)->stride == 16 && (VWT(mp)->flags & 0xff) == 7);
    CHECK(VWT(mp)->xi == 253 && (VWT(mp)->flags & ENUM_WITNESSES));
    CHECK((unsigned long)mp->rest[2] == 8); /* payload size, after the generic arguments */
    fill();
    g_mp_d(g);
    c_mp_d(c);
    CHECK(SAME(9) && g[0] == 1 && g[8] == 2);
    CHECK(swift_getEnumCaseMultiPayload(g, mp) == 3);
    CHECK(g_mp_case(g, 10, 11, 12, 13) == 13);
    fill();
    g_mp_b(g, 5);
    c_mp_b(c, 5);
    CHECK(g[0] == 5 && c[0] == 5 && g[8] == 1 && c[8] == 1);
    CHECK(swift_getEnumCaseMultiPayload(g, mp) == 1 && g_mp_case(g, 10, 11, 12, 13) == 11);
    swift_storeEnumTagMultiPayload(g, mp, 2);
    CHECK(g[0] == 0 && g[8] == 2 && g_mp_case(g, 10, 11, 12, 13) == 12);
    swift_storeEnumTagMultiPayload(g, mp, 0);
    CHECK(g[8] == 0 && g_mp_case(g, 10, 11, 12, 13) == 10);

    /* MP<Int8, Int8>: one payload byte, so empty cases spread over it. */
    const md *mp8 = mp_ma(0, I8, I8).m;
    CHECK(VWT(mp8)->size == 2 && VWT(mp8)->xi == 253);
    fill();
    g_mp_d8(g);
    c_mp_d8(c);
    CHECK(SAME(2) && g[0] == 1 && g[1] == 2);

    /* Big<Int8> { p(T), q(T), c0...c299 }: 300 empty cases need two tags. */
    const md *big = big_ma(0, I8).m;
    CHECK(VWT(big)->size == 2 && VWT(big)->xi == 252);
    fill();
    g_big(g);
    c_big(c);
    CHECK(SAME(2) && g[0] == 43 && g[1] == 3);
    CHECK(swift_getEnumCaseMultiPayload(g, big) == 301);

    /* Optional<MP<Int64, Int8>>: none is MP's first extra inhabitant, the
     * tag byte ~0. */
    const md *omp = opt_ma(0, mp).m;
    CHECK(VWT(omp)->size == 9 && VWT(omp)->xi == 252);
    fill();
    g_opt_mp_none(g);
    c_opt_mp_none(c);
    CHECK(g[8] == 0xFF && c[8] == 0xFF);
    CHECK(VWT(mp)->get_tag(g, 1, mp) == 1 && g_opt_case(g, 20, 21) == 20);
    g_mp_d(g);
    CHECK(VWT(mp)->get_tag(g, 1, mp) == 0 && g_opt_case(g, 20, 21) == 21);
    VWT(mp)->store_tag(g, 2, 3, mp);
    CHECK(g[8] == 0xFE && VWT(mp)->get_tag(g, 3, mp) == 2);

    /* E3<T> { p(T), x, y, z }: single payload. */
    const md *e8 = e3_ma(0, I8).m, *e1 = e3_ma(0, I1).m, *ep = e3_ma(0, PTR).m;
    CHECK(VWT(e8)->size == 2 && VWT(e8)->stride == 2 && VWT(e8)->xi == 0);
    CHECK(VWT(e1)->size == 1 && VWT(e1)->xi == 251);
    CHECK(VWT(ep)->size == 9 && VWT(ep)->stride == 16 && VWT(ep)->xi == 0);
    fill();
    g_e3z8(g);
    c_e3z8(c);
    CHECK(SAME(2) && g[0] == 2 && g[1] == 1);
    fill();
    g_e3p8(g, 9);
    CHECK(g[0] == 9 && g[1] == 0);
    fill();
    g_e3z1(g);
    c_e3z1(c);
    CHECK(SAME(1) && g[0] == 4);
    fill();
    g_e3zp(g);
    c_e3zp(c);
    CHECK(SAME(9) && g[0] == 1 && g[8] == 1);

    /* Optional<Optional<Int1>>: 254, then 253 extra inhabitants. */
    fill();
    g_opt_opt1_none(g);
    c_opt_opt1_none(c);
    CHECK(SAME(1) && g[0] == 3);
    fill();
    g_opt_opt1_some_none(g);
    c_opt_opt1_some_none(c);
    CHECK(SAME(1) && g[0] == 2);
    CHECK(VWT(opt_ma(0, opt_ma(0, I1).m).m)->xi == 252);

    /* One<T> { only(T) }: laid out as its payload. */
    const md *o32 = one_ma(0, I32).m, *o1 = one_ma(0, I1).m;
    CHECK(VWT(o32)->size == 4 && VWT(o32)->xi == 0 && (VWT(o32)->flags & ENUM_WITNESSES));
    CHECK(VWT(o1)->size == 1 && VWT(o1)->xi == 254);
    puts("swift enums ok");
    return 0;
}
