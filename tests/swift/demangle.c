// Driver for demangle.swift: mangled type names (the printer, symbolic
// references, lookups by name), conformance lookup, associated types and
// conformances, and opaque result types.
#include "darwin.h"

typedef _Bool bool;
struct response { const void *value; unsigned long state; };
struct name_pair { const char *data; unsigned long length; };

char *swift_demangle(const char *, size_t, char *, size_t *, unsigned);
const void *swift_getTypeByMangledNameInContext(const char *, size_t, const void *, const void *const *);
const void *swift_getTypeByMangledNameInContext2(const char *, size_t, const void *, const void *const *);
const void *swift_getTypeByMangledNameInContextInMetadataState(size_t, const char *, size_t, const void *,
                                                               const void *const *);
struct name_pair swift_getTypeName(const void *, bool);
const void *swift_conformsToProtocol(const void *, const void *);
const void *swift_conformsToProtocol2(const void *, const void *);
struct response swift_getOpaqueTypeMetadata2(unsigned long, const void *const *, const void *, unsigned);
const void *swift_getOpaqueTypeConformance2(const void *const *, const void *, unsigned);

extern const char $s8demangle1SVN[], $s8demangle2QQVN[], $s8demangle6HolderVN[];
extern const char $s8demangle1SVMn[], $s8demangle6HolderVMn[];
extern const char $s8demangle1PMp[], $s8demangle1QMp[], $s8demangle6UnusedMp[];
extern const char $s8demangle1SVAA1PAAWP[], $s8demangle2QQVAA1QAAWP[], $s8demangle4BaseCAA1QAAWP[];
extern const char $s8demangle6opaqueQryFQOMQ[];
struct response $s8demangle4BaseCMa(unsigned long);
struct response $s8demangle7DerivedCMa(unsigned long);
const void *demangle_assoc_a_of_s(void);
const void *demangle_pair_s_qq(void), *demangle_box_s(void), *demangle_inner(void);
const void *demangle_assoc_a_of_pair(void);
long demangle_id_of_b_of_pair(long);
extern const char $s8demangle4PairVMn[], $s8demangle3BoxVMn[], $s8demangle2QQVMn[];
long demangle_id_of_b_of_s(long);

static const struct { const char *in, *out; } names[] = {
    {"$sSiD", "Swift.Int"},
    {"$sSaySiGSgD", "[Swift.Int]?"},
    {"$sSDySSSiGD", "[Swift.String : Swift.Int]"},
    {"$sSi1a_Sd1btD", "(a: Swift.Int, b: Swift.Double)"},
    {"$sSiSSYaKcD", "(Swift.String) async throws -> Swift.Int"},
    {"$sSiSSScMYccD", "@Swift.MainActor (Swift.String) -> Swift.Int"},
    {"$sytSizcD", "(inout Swift.Int) -> ()"},
    {"$sSiSi_SddtcD", "(Swift.Int, Swift.Double...) -> Swift.Int"},
    {"$sSiSSXBD", "@convention(block) (Swift.String) -> Swift.Int"},
    {"$sSQ_SHpD", "Swift.Equatable & Swift.Hashable"},
    {"$s4main1PP_4main1QPXlD", "main.P & main.Q & Swift.AnyObject"},
    {"$s4main1P_4main1QpD", "main.P & main.Q"},
    {"$syXlD", "Swift.AnyObject"},
    {"$sypXpD", "Any.Type"},
    {"$sSiXMTD", "@thick Swift.Int.Type"},
    {"$sBi64_D", "Builtin.Int64"},
    {"$sq_D", "B"},
    {"$sqd__D", "A1"},
    {"$s4main6FooBarV0B3QuxVD", "main.FooBar.FooQux"},       /* word substitutions */
    {"$s4main4PairVyAA1SVAEGD", "main.Pair<main.S, main.S>"}, /* back references */
    {"$s4main5OuterV5InnerVySi_SSGD", "main.Outer<Swift.Int>.Inner<Swift.String>"},
    {"$sSD4KeysVySSSi_GD", "[Swift.String : Swift.Int].Keys"},
    {"$s4main3Foo33_0123456789ABCDEF0123456789ABCDEFLLVD", "main.(Foo in _0123456789ABCDEF0123456789ABCDEF)"},
    {"$sSo8NSObjectCSgXwD", "weak __C.NSObject?"},
    {"$sScTySiSSGD", "Swift.Task<Swift.Int, Swift.String>"},
    {"$s8demangle1SVMn", "nominal type descriptor for demangle.S"},
    {"$s8demangle1PMp", "protocol descriptor for demangle.P"},
    {"$sSiSi", NULL},
    {"$sxyz", NULL},
};

/* Mangled names with symbolic references are relative to their own
 * address, so they are built in place, next to the descriptors. */
static char symref[32];
static const void *s_descriptor_slot = $s8demangle1SVMn;
static size_t make_ref(int kind, const void *target) {
    symref[0] = (char)kind;
    int off = (int)((const char *)target - (symref + 1));
    memcpy(symref + 1, &off, 4);
    symref[5] = 0;
    return 5;
}

static const char *field_type(const char *desc, int i, size_t *len) {
    const int *fields_ref = (const int *)(desc + 16);
    const char *fd = (const char *)fields_ref + *fields_ref;
    const int *rec = (const int *)(fd + 16 + 12 * i);
    const char *name = (const char *)(rec + 1) + rec[1];
    /* symbolic references span 5 bytes and may contain zeroes */
    size_t n = 0;
    while (name[n]) n += (name[n] >= 1 && name[n] <= 0x17) ? 5 : 1;
    *len = n;
    return name;
}

int main(void) {
    /* The printer, through the public swift_demangle. */
    for (unsigned i = 0; i < sizeof names / sizeof *names; i++) {
        char *r = swift_demangle(names[i].in, strlen(names[i].in), NULL, NULL, 0);
        if (!names[i].out ? r != NULL : (!r || strcmp(r, names[i].out))) {
            printf("swift_demangle(%s) = %s, expected %s\n", names[i].in, r ? r : "NULL",
                   names[i].out ? names[i].out : "NULL");
            CHECK(0);
        }
        free(r);
    }
    char buf[64];
    size_t size = sizeof buf;
    CHECK(swift_demangle("$sSiD", 5, buf, &size, 0) == buf && !strcmp(buf, "Swift.Int") && size == 9);

    /* Field types as the compiler wrote them: symbolic references. */
    const void *S = $s8demangle1SVN, *QQ = $s8demangle2QQVN;
    size_t len;
    const char *ft = field_type($s8demangle6HolderVMn, 0, &len);
    CHECK(ft[0] == 1 && len == 5);
    CHECK(swift_getTypeByMangledNameInContext(ft, len, $s8demangle6HolderVMn, NULL) == S);
    ft = field_type($s8demangle6HolderVMn, 1, &len);
    CHECK(swift_getTypeByMangledNameInContext2(ft, len, $s8demangle6HolderVMn, NULL) == QQ);
    ft = field_type($s8demangle6HolderVMn, 2, &len);
    CHECK(!strcmp(ft, "Bi64_"));
    swift_getTypeByMangledNameInContext(ft, len, NULL, NULL); /* builtin metadata: may be absent */

    /* Direct and indirect symbolic references built here. */
    len = make_ref(1, $s8demangle1SVMn);
    CHECK(swift_getTypeByMangledNameInContext(symref, len, NULL, NULL) == S);
    len = make_ref(2, &s_descriptor_slot);
    CHECK(swift_getTypeByMangledNameInContextInMetadataState(0, symref, len, NULL, NULL) == S);

    /* Types named rather than referenced: found through __swift5_types. */
    CHECK(swift_getTypeByMangledNameInContext("8demangle1SV", 12, NULL, NULL) == S);
    CHECK(swift_getTypeByMangledNameInContext("$s8demangle2QQV", 15, NULL, NULL) == QQ);
    CHECK(swift_getTypeByMangledNameInContext("8demangle7MissingV", 18, NULL, NULL) == NULL);
    /* No standard library, no generic environment: NULL, not a crash. */
    CHECK(swift_getTypeByMangledNameInContext("Si", 2, NULL, NULL) == NULL);
    CHECK(swift_getTypeByMangledNameInContext("8demangle1SVSg", 14, NULL, NULL) == NULL);
    CHECK(swift_getTypeByMangledNameInContext("x", 1, NULL, NULL) == NULL);
    CHECK(swift_getTypeByMangledNameInContext("8demangle1SVG", 13, NULL, NULL) == NULL);

    struct name_pair n = swift_getTypeName(S, 1);
    CHECK(n.length == 10 && !strcmp(n.data, "demangle.S"));
    n = swift_getTypeName(S, 0);
    CHECK(n.length == 1 && !strcmp(n.data, "S"));

    /* Conformances. */
    CHECK(swift_conformsToProtocol(S, $s8demangle1PMp) == $s8demangle1SVAA1PAAWP);
    CHECK(swift_conformsToProtocol(S, $s8demangle1QMp) == NULL);
    CHECK(swift_conformsToProtocol2(QQ, $s8demangle1QMp) == $s8demangle2QQVAA1QAAWP);
    CHECK(swift_conformsToProtocol(QQ, $s8demangle6UnusedMp) == NULL);
    CHECK(swift_conformsToProtocol(S, $s8demangle1PMp) == $s8demangle1SVAA1PAAWP); /* cached */
    const void *base = $s8demangle4BaseCMa(0).value, *derived = $s8demangle7DerivedCMa(0).value;
    CHECK(base && derived && base != derived);
    CHECK(swift_conformsToProtocol(base, $s8demangle1QMp) == $s8demangle4BaseCAA1QAAWP);
    CHECK(swift_conformsToProtocol(derived, $s8demangle1QMp) == $s8demangle4BaseCAA1QAAWP);
    CHECK(swift_conformsToProtocol(derived, $s8demangle1PMp) == NULL);
    n = swift_getTypeName(derived, 1);
    CHECK(!strcmp(n.data, "demangle.Derived"));

    /* Associated type (a mangled name in S's witness table) and associated
     * conformance (an accessor) requested by compiled generic code. */
    CHECK(demangle_assoc_a_of_s() == QQ);
    CHECK(demangle_assoc_a_of_s() == QQ);
    CHECK(demangle_id_of_b_of_s(21) == 42);

    /* some P: underlying type #0 is S, #1 the S: P witness table. */
    CHECK(swift_getOpaqueTypeMetadata2(0, NULL, $s8demangle6opaqueQryFQOMQ, 0).value == S);
    CHECK(swift_getOpaqueTypeConformance2(NULL, $s8demangle6opaqueQryFQOMQ, 1) == $s8demangle1SVAA1PAAWP);

    /* Generic types. Pair<S, QQ> named with symbolic references here is the
     * same (uniqued) metadata compiled code gets. */
    const void *pair = demangle_pair_s_qq();
    make_ref(1, $s8demangle4PairVMn);
    symref[5] = 'y';
    int off = (int)($s8demangle1SVMn - (symref + 7));
    symref[6] = 1;
    memcpy(symref + 7, &off, 4);
    off = (int)($s8demangle2QQVMn - (symref + 12));
    symref[11] = 1;
    memcpy(symref + 12, &off, 4);
    symref[16] = 'G';
    CHECK(swift_getTypeByMangledNameInContext(symref, 17, NULL, NULL) == pair);
    CHECK(swift_getTypeByMangledNameInContext("8demangle4PairVyAA1SVAA2QQVG", 28, NULL, NULL) == pair);
    n = swift_getTypeName(pair, 1);
    CHECK(!strcmp(n.data, "demangle.Pair<demangle.S, demangle.QQ>"));
    n = swift_getTypeName(demangle_inner(), 1);
    CHECK(!strcmp(n.data, "demangle.Outer<demangle.S>.Inner<demangle.QQ>"));
    n = swift_getTypeName(demangle_inner(), 0);
    CHECK(!strcmp(n.data, "Inner<demangle.QQ>") || !strcmp(n.data, "Inner<QQ>"));
    /* Field types in the environment of Pair<S, QQ>'s arguments: x, q_. */
    const void *const *pargs = (const void *const *)pair + 2;
    ft = field_type($s8demangle4PairVMn, 0, &len);
    CHECK(swift_getTypeByMangledNameInContext(ft, len, $s8demangle4PairVMn, pargs) == S);
    ft = field_type($s8demangle4PairVMn, 1, &len);
    CHECK(swift_getTypeByMangledNameInContext(ft, len, $s8demangle4PairVMn, pargs) == QQ);
    /* Box<S>: its key arguments are S and the S: P witness table; fields
     * T.A, (T, Int64) and Pair<T.B, T> need both. */
    const void *box = demangle_box_s();
    const void *const *bargs = (const void *const *)box + 2;
    CHECK(bargs[0] == S && bargs[1] == $s8demangle1SVAA1PAAWP);
    ft = field_type($s8demangle3BoxVMn, 1, &len);
    CHECK(swift_getTypeByMangledNameInContext(ft, len, $s8demangle3BoxVMn, bargs) == QQ);
    ft = field_type($s8demangle3BoxVMn, 2, &len);
    const unsigned long *tuple = swift_getTypeByMangledNameInContext(ft, len, $s8demangle3BoxVMn, bargs);
    CHECK(tuple && tuple[0] == 0x301 && tuple[1] == 2 && (const void *)tuple[3] == S);
    n = swift_getTypeName(tuple, 1);
    CHECK(!strcmp(n.data, "(demangle.S, Builtin.Int64)"));
    ft = field_type($s8demangle3BoxVMn, 3, &len);
    const void *pqs = swift_getTypeByMangledNameInContext(ft, len, $s8demangle3BoxVMn, bargs);
    n = swift_getTypeName(pqs, 1);
    CHECK(!strcmp(n.data, "demangle.Pair<demangle.QQ, demangle.S>"));
    CHECK(swift_getTypeByMangledNameInContext("x", 1, $s8demangle3BoxVMn, bargs) == S);
    /* Requirements are checked: Box<QQ> is not a type (QQ is not P). */
    CHECK(swift_getTypeByMangledNameInContext("8demangle3BoxVyAA2QQVG", 22, NULL, NULL) == NULL);

    /* Conditional conformance Pair: P where T: P, with a generic witness
     * table whose associated types are T.A and T.B. */
    const void *const *wt = swift_conformsToProtocol(pair, $s8demangle1PMp);
    CHECK(wt != NULL && wt != (const void *)$s8demangle1SVAA1PAAWP);
    CHECK(wt[-1] == $s8demangle1SVAA1PAAWP); /* conditional conformance, in the private area */
    CHECK(swift_conformsToProtocol(pair, $s8demangle1PMp) == wt);
    CHECK(swift_conformsToProtocol(pqs, $s8demangle1PMp) == NULL);
    CHECK(demangle_assoc_a_of_pair() == QQ);
    CHECK(demangle_id_of_b_of_pair(5) == 10);

    puts("swift demangle ok");
    return 0;
}
