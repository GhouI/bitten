// Singleton metadata initialisation of structs with resilient fields
// (tests/swift/singleton.swift, singleton.lib.swift).
#include "darwin.h"

typedef struct md md;
struct vwt { void *fn[8]; unsigned long size, stride; unsigned flags, xi; };
struct md { unsigned long kind; const void *desc; const void *rest[]; };
typedef struct { const md *m; unsigned long state; } resp;
#define VWT(m) (((const struct vwt *const *)(m))[-1])

extern resp s_ma(unsigned long) __asm__("_$s9singleton1SVMa");
extern resp s2_ma(unsigned long) __asm__("_$s9singleton2S2VMa");
extern resp g_ma(unsigned long, const md *) __asm__("_$s9singleton1GVMa");
extern const struct { const void *vwt; md m; } i8_md __asm__("_$sBi8_N"), i32_md __asm__("_$sBi32_N");
extern const int s_desc[] __asm__("_$s9singleton1SVMn");
extern void single_make(void *out, long a, long y);
extern long single_y(const void *p);
extern long single_ra(const void *p);

static const unsigned *offsets(const md *m, int word) {
    return (const unsigned *)((const unsigned long *)m + word);
}

int main(void) {
    /* S { x: Int8, r: R (9 bytes, align 8), y: Int64, z: RB (Int1) } */
    resp r = s_ma(0);
    const md *s = r.m;
    CHECK(r.state == 0 && s->kind == 0x200);
    const unsigned *o = offsets(s, 2);
    CHECK(o[0] == 0 && o[1] == 8 && o[2] == 24 && o[3] == 32);
    CHECK(VWT(s)->size == 33 && VWT(s)->stride == 40 && (VWT(s)->flags & 0xff) == 7);
    CHECK(VWT(s)->xi == 254 && !(VWT(s)->flags & 0x400000));
    /* The descriptor's singleton initialisation follows {flags, parent, name,
     * accessor, fields, nfields, field offsets}; its cache, which the
     * accessor reads directly, is published once complete. */
    CHECK((s_desc[0] >> 16 & 3) == 1);
    const md *const *cache = (const md *const *)((const char *)&s_desc[7] + s_desc[7]);
    CHECK(s->desc == s_desc && cache[0] == s);
    CHECK(s_ma(0).m == s);

    /* S2 { s: S, b: Int8 }: its completion needs S's layout first. */
    const md *s2 = s2_ma(0).m;
    CHECK(offsets(s2, 2)[0] == 0 && offsets(s2, 2)[1] == 33 && VWT(s2)->size == 34);

    /* G<Int32> { t: Int32, r: R } */
    const md *g = g_ma(0, &i32_md.m).m;
    CHECK(offsets(g, 3)[0] == 0 && offsets(g, 3)[1] == 8 && VWT(g)->size == 17);
    CHECK(g_ma(0, &i32_md.m).m == g && g_ma(0, &i8_md.m).m != g);

    /* Compiled code using the runtime's field offsets. */
    unsigned long buf[6];
    memset(buf, 0, sizeof buf);
    single_make(buf, 11, 22);
    CHECK(buf[1] == 11 && buf[3] == 22);
    CHECK(single_y(buf) == 22);
    CHECK(single_ra(buf) == 11);
    puts("swift singleton ok");
    return 0;
}
