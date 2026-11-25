// Class metadata built by the runtime (tests/swift/classes.swift), seen as
// Swift metadata and as Objective-C classes.
#include "darwin.h"

typedef struct cls cls;
struct cls {
    const cls *isa, *super;
    void *cache[2];
    unsigned long data;
    unsigned flags, iap, isize;
    unsigned short amask, res;
    unsigned csize, cap;
    const unsigned *desc;
    void *ivar_destroyer;
};
typedef struct { const cls *m; unsigned long state; } resp;
typedef const void *md;

extern resp base_ma(unsigned long, md) __asm__("_$s7classes4BaseCMa");
extern resp sub_ma(unsigned long, md) __asm__("_$s7classes3SubCMa");
extern resp deep_ma(unsigned long, md) __asm__("_$s7classes4DeepCMa");
extern resp d_ma(unsigned long) __asm__("_$s7classes1DCMa");
extern resp rc_ma(unsigned long) __asm__("_$s7classes2RCCMa");
extern const struct { const void *vwt; unsigned long kind; } i8_md __asm__("_$sBi8_N"), i64_md __asm__("_$sBi64_N");
extern const cls swift_object __asm__("_OBJC_CLASS_$__TtCs12_SwiftObject");
#define I8 ((md)&i8_md.kind)
#define I64 ((md)&i64_md.kind)

extern const cls *objc_getClass(const char *);
extern const char *class_getName(const cls *);
extern unsigned long class_getInstanceSize(const cls *);
extern const cls *class_getSuperclass(const cls *);
extern const cls *object_getClass(const void *);
extern int class_isMetaClass(const cls *);
extern const void *class_getInstanceVariable(const cls *, const char *);
extern long ivar_getOffset(const void *);

extern void *cls_new_base(long), *cls_new_sub(long), *cls_new_deep8(char), *cls_new_d(long), *cls_new_rc(long, long);
extern long cls_pick_i64(void *, long, long, long), cls_pick_i8(void *, long, long, long);
extern long cls_get_i64(void *), cls_rc_y(void *), cls_rc_a(void *);

/* class descriptor: flags, parent, name, accessor, fields, superclass,
 * negative size, positive size, immediate members, fields, field offsets */
static const unsigned long *field_offsets(const cls *c) {
    return (const unsigned long *)c + c->desc[10];
}

int main(void) {
    /* Base<Int64> { t: T, k: Int8 } after the 16-byte object header */
    const cls *b = base_ma(0, I64).m;
    CHECK(b == base_ma(0, I64).m && (b->data & 2));
    CHECK(b->super == &swift_object);
    CHECK(field_offsets(b)[0] == 16 && field_offsets(b)[1] == 24);
    CHECK(b->isize == 25 && b->amask == 7);
    /* Base<Int8>: t at 16, k at 17 */
    const cls *b8 = base_ma(0, I8).m;
    CHECK(b8 != b && field_offsets(b8)[1] == 17 && b8->isize == 18);

    /* Sub<Int64>: Base<Int64>'s members copied, then u */
    const cls *s = sub_ma(0, I64).m;
    CHECK(s->super == b);
    CHECK(field_offsets(s)[0] == 32 && s->isize == 40);
    CHECK(((const unsigned long *)s)[b->desc[10]] == 16); /* inherited field offsets */
    /* Deep<Int8> -> Sub<Int8> -> Base<Int8> */
    const cls *dp = deep_ma(0, I8).m, *s8 = sub_ma(0, I8).m;
    CHECK(dp->super == s8 && s8->super == b8);
    CHECK(field_offsets(s8)[0] == 24 && field_offsets(dp)[0] == 32 && dp->isize == 33);

    /* Objective-C: realised, named, laid out, metaclass chain. */
    CHECK(class_getSuperclass(s) == b && class_getInstanceSize(s) == 40);
    CHECK(class_isMetaClass(s->isa) && class_getSuperclass(s->isa) == b->isa);
    const char *name = class_getName(s);
    CHECK(name && strlen(name) > 3 && objc_getClass(name) == s);
    CHECK(strcmp(class_getName(s), class_getName(s8)) != 0);
    const void *iv = class_getInstanceVariable(s, "u");
    CHECK(iv && ivar_getOffset(iv) == 32);

    /* Objects, generic code and dynamic dispatch through the vtables. */
    void *ob = cls_new_base(41), *os = cls_new_sub(42), *od = cls_new_d(43);
    CHECK(object_getClass(ob) == b && object_getClass(os) == s);
    CHECK(cls_pick_i64(ob, 1, 2, 3) == 1 && cls_pick_i64(os, 1, 2, 3) == 2);
    CHECK(cls_get_i64(os) == 42 && cls_get_i64(od) == 43);
    void *o8 = cls_new_deep8(9);
    CHECK(object_getClass(o8) == dp && cls_pick_i8(o8, 1, 2, 3) == 3);

    /* D: a non-generic subclass of Base<Int64>, singleton initialisation */
    const cls *d = d_ma(0).m;
    CHECK(d->super == b && object_getClass(od) == d);
    CHECK(field_offsets(d)[0] == 28 && d->isize == 32 && cls_pick_i64(od, 1, 2, 3) == 2);
    CHECK(!strcmp(class_getName(d), "_TtC7classes1D") && objc_getClass("_TtC7classes1D") == d);

    /* RC { x: Int8, r: R (resilient, 9 bytes), y: Int64 } */
    const cls *rc = rc_ma(0).m;
    CHECK(field_offsets(rc)[0] == 16 && field_offsets(rc)[1] == 24 && field_offsets(rc)[2] == 40);
    CHECK(rc->isize == 48 && class_getInstanceSize(rc) == 48);
    void *orc = cls_new_rc(7, 8);
    CHECK(cls_rc_y(orc) == 8 && cls_rc_a(orc) == 7);
    puts("swift classes ok");
    return 0;
}
