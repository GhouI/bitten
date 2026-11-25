// Driver for casts.swift: swift_dynamicCast and friends, error boxes, and
// a thrown error seen through swift_getErrorValue.
#include "darwin.h"

typedef _Bool bool;
struct response { const void *value; unsigned long state; };
struct box_pair { void *object; void *value; };
struct error_value { const void *value; const void *type; const void *conformance; };

bool swift_dynamicCast(void *dest, void *src, const void *src_type, const void *target, unsigned long flags);
const void *swift_dynamicCastClass(const void *, const void *);
const void *swift_dynamicCastMetatype(const void *, const void *);
const void *swift_dynamicCastTypeToObjCProtocolConditional(const void *, size_t, const void *const *);
const void *swift_dynamicCastObjCProtocolConditional(const void *, size_t, const void *const *);
struct box_pair swift_allocError(const void *type, const void *conformance, void *value, bool take);
void swift_deallocError(void *, const void *);
void swift_getErrorValue(const void *, void **, struct error_value *);
void *swift_errorRetain(void *);
void swift_errorRelease(void *);
unsigned long swift_retainCount(void *);
void swift_release(void *);
void *objc_getProtocol(const char *);

extern const char $ss5SmallVN[], $ss3BigVN[], $ss5MyErrVN[];
extern const char $ss1PMp[], $ss1QMp[], $ss5ErrorMp[];
extern const char $ss5SmallVs1PsWP[], $ss3BigVs1PsWP[], $ss4BaseCs1QsWP[], $ss5MyErrVs5ErrorsWP[];
struct response $ss4BaseCMa(unsigned long);
struct response $ss7DerivedCMa(unsigned long);
struct response $ss5OtherCMa(unsigned long);
long casts_catch(long);
void *casts_saved_error(void);
void *casts_force_derived(void *);
void *casts_new_base(void), *casts_new_derived(void), *casts_new_other(void);
long casts_value_of(void *);

struct small { long a; int b; };
struct big { long a; int b; long c, d; };
struct myerr { long code; int small; };

/* Existential and metatype metadata as metadata.c will make them (kind,
 * flags, protocols), built by hand until it lands. The value witness
 * pointer in front is unused by these tests. */
struct existential { const void *vwt; unsigned long kind; unsigned flags, nprotos; const void *protos[2]; };
#define EX_ANY 0x80000000u
#define EX_ERROR (1u << 24)
static struct existential any_p = {0, 0x303, 1 | EX_ANY, 1, {$ss1PMp}};
static struct existential any_q = {0, 0x303, 1 | EX_ANY, 1, {$ss1QMp}};
static struct existential class_q = {0, 0x303, 1, 1, {$ss1QMp}}; /* any Q & AnyObject */
static struct existential any_error = {0, 0x303, 1 | EX_ANY | EX_ERROR, 1, {$ss5ErrorMp}};
static struct existential any_objc = {0, 0x303, 0, 1, {0}}; /* any NSCopying-like ObjC protocol */
struct metatype { const void *vwt; unsigned long kind; const void *instance; };

int main(void) {
    const void *small_t = $ss5SmallVN, *big_t = $ss3BigVN, *err_t = $ss5MyErrVN;
    const void *base_t = $ss4BaseCMa(0).value, *derived_t = $ss7DerivedCMa(0).value;
    const void *other_t = $ss5OtherCMa(0).value;

    /* Classes. */
    void *b = casts_new_base(), *d = casts_new_derived(), *o = casts_new_other();
    CHECK(swift_dynamicCastClass(d, base_t) == d);
    CHECK(swift_dynamicCastClass(d, derived_t) == d);
    CHECK(swift_dynamicCastClass(b, derived_t) == NULL);
    CHECK(swift_dynamicCastClass(o, base_t) == NULL);
    CHECK(swift_dynamicCastClass(NULL, base_t) == NULL);
    CHECK(casts_force_derived(d) == d);
    CHECK(swift_dynamicCastMetatype(derived_t, base_t) == derived_t);
    CHECK(swift_dynamicCastMetatype(base_t, derived_t) == NULL);
    CHECK(swift_dynamicCastMetatype(small_t, small_t) == small_t);
    CHECK(swift_dynamicCastMetatype(small_t, big_t) == NULL);

    /* swift_dynamicCast: class to class, through the object's real class. */
    void *dst = NULL, *src = d;
    CHECK(swift_dynamicCast(&dst, &src, base_t, derived_t, 0) && dst == d);
    swift_release(d); /* the cast made a copy (the objects are static at -O: immortal) */
    src = b;
    CHECK(!swift_dynamicCast(&dst, &src, base_t, derived_t, 0));

    /* Value -> any P: inline buffer, then back out. */
    struct small s = {41, 7}, s2 = {0, 0};
    void *ex[5] = {0};
    CHECK(swift_dynamicCast(ex, &s, small_t, &any_p.kind, 0));
    CHECK(ex[3] == small_t && ex[4] == $ss5SmallVs1PsWP);
    CHECK(((struct small *)ex)->a == 41 && ((struct small *)ex)->b == 7);
    CHECK(casts_value_of(ex) == 41); /* compiled code calls through the container */
    CHECK(swift_dynamicCast(&s2, ex, &any_p.kind, small_t, 0) && s2.a == 41 && s2.b == 7);
    CHECK(!swift_dynamicCast(&s2, ex, &any_p.kind, big_t, 0));
    CHECK(!swift_dynamicCast(ex, &s, small_t, &any_q.kind, 0)); /* Small is not Q */

    /* Too big for the buffer: boxed. */
    struct big g = {1, 2, 3, 4}, g2 = {0};
    void *exb[5] = {0};
    CHECK(swift_dynamicCast(exb, &g, big_t, &any_p.kind, 0));
    CHECK(exb[3] == big_t && exb[4] == $ss3BigVs1PsWP && exb[0] != NULL);
    CHECK(casts_value_of(exb) == 5);
    CHECK(swift_dynamicCast(&g2, exb, &any_p.kind, big_t, 0) && g2.a == 1 && g2.c == 3 && g2.d == 4);

    /* Objects into a class-bound existential, inheriting Base: Q. */
    void *cex[2] = {0};
    src = d;
    CHECK(swift_dynamicCast(cex, &src, derived_t, &class_q.kind, 0));
    CHECK(cex[0] == d && cex[1] == $ss4BaseCs1QsWP);
    src = o;
    CHECK(!swift_dynamicCast(cex, &src, other_t, &class_q.kind, 0));
    CHECK(!swift_dynamicCast(cex, &s, small_t, &class_q.kind, 0)); /* not a class */
    dst = NULL;
    CHECK(swift_dynamicCast(&dst, cex, &class_q.kind, base_t, 0) && dst == d);

    /* Metatypes, and a metatype into `any P.Type`. */
    struct metatype base_mt = {0, 0x304, base_t}, derived_mt = {0, 0x304, derived_t};
    struct metatype small_mt = {0, 0x304, small_t}, p_type = {0, 0x306, &any_p.kind};
    const void *mv = derived_t, *mout = NULL;
    CHECK(swift_dynamicCast(&mout, &mv, &base_mt.kind, &derived_mt.kind, 0) && mout == derived_t);
    mv = base_t;
    CHECK(!swift_dynamicCast(&mout, &mv, &base_mt.kind, &derived_mt.kind, 0));
    const void *pm[2] = {0};
    mv = small_t;
    CHECK(swift_dynamicCast(pm, &mv, &small_mt.kind, &p_type.kind, 0) && pm[0] == small_t && pm[1] == $ss5SmallVs1PsWP);

    /* Errors: a value into `any Error` makes a box; casting back opens it. */
    struct myerr e = {99, 3}, e2 = {0};
    void *errbox = NULL;
    CHECK(swift_dynamicCast(&errbox, &e, err_t, &any_error.kind, 0) && errbox);
    struct error_value ev;
    void *scratch;
    swift_getErrorValue(errbox, &scratch, &ev);
    CHECK(ev.type == err_t && ev.conformance == $ss5MyErrVs5ErrorsWP);
    CHECK(((const struct myerr *)ev.value)->code == 99);
    CHECK(swift_dynamicCast(&e2, &errbox, &any_error.kind, err_t, 0) && e2.code == 99 && e2.small == 3);
    CHECK(swift_errorRetain(errbox) == errbox && swift_retainCount(errbox) == 2);
    swift_errorRelease(errbox);
    swift_errorRelease(errbox);

    struct box_pair bp = swift_allocError(err_t, $ss5MyErrVs5ErrorsWP, &e, 0);
    CHECK(bp.object && ((struct myerr *)bp.value)->code == 99);
    swift_errorRelease(bp.object);
    bp = swift_allocError(err_t, $ss5MyErrVs5ErrorsWP, NULL, 0);
    swift_deallocError(bp.object, err_t);

    /* A thrown and caught error, as compiled code makes it. */
    CHECK(casts_catch(1234) == 0);
    void *thrown = casts_saved_error();
    swift_getErrorValue(thrown, &scratch, &ev);
    CHECK(ev.type == err_t && ((const struct myerr *)ev.value)->code == 1234);

    /* Objective-C protocols: only classes conform. */
    const void *marked = objc_getProtocol("_TtPs6Marked_");
    CHECK(marked != NULL);
    const void *protos[1] = {marked};
    CHECK(swift_dynamicCastObjCProtocolConditional(d, 1, protos) == d);
    CHECK(swift_dynamicCastObjCProtocolConditional(b, 1, protos) == NULL);
    CHECK(swift_dynamicCastTypeToObjCProtocolConditional(derived_t, 1, protos) == derived_t);
    CHECK(swift_dynamicCastTypeToObjCProtocolConditional(small_t, 1, protos) == NULL);
    any_objc.protos[0] = (const char *)marked + 1; /* ProtocolDescriptorRef: low bit = ObjC */
    void *oex[1] = {0};
    src = d;
    CHECK(swift_dynamicCast(oex, &src, base_t, &any_objc.kind, 0) && oex[0] == d);
    src = b;
    CHECK(!swift_dynamicCast(oex, &src, base_t, &any_objc.kind, 0));

    puts("swift casts ok");
    return 0;
}
