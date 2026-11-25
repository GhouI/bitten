/* Mangled type names -> type metadata.
 *
 * The compiler embeds type names in binaries in its mangling (field types,
 * associated type witnesses, generic requirements, the arguments of
 * __swift_instantiateConcreteTypeFromMangledName), with "symbolic
 * references" in place of names wherever it can: a byte 0x01-0x17 followed
 * by a 32-bit offset, relative to the offset's own address, to a context
 * descriptor or accessor function. Turning such a name into metadata is the
 * runtime's job (swift_getTypeByMangledNameInContext and friends).
 *
 * The mangling is postfix: operands come first, so parsing pushes nodes on
 * a stack and each operator pops its operands, the same shape as the
 * grammar in the Swift repository's docs/ABI/Mangling.rst. Parsing builds a
 * small tree (in an arena freed after each lookup), which is then either
 * resolved to metadata against a generic environment or printed. Only the
 * type grammar is handled; names of functions and other entities are not
 * needed by the runtime.
 *
 * Backreferences ("substitutions", `A` + index) refer to earlier nodes; which
 * nodes count is part of the mangling and is reproduced exactly: identifiers,
 * nominal types, context symbolic references, bound generic types, `Sg` and
 * dependent member types. */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#include "sw_map.h"
#include "swift_internal.h"

/* ---- runtime entry points reached through the registry -------------------
 * Public Swift and Objective-C runtime functions implemented elsewhere in
 * bitten are looked up by their exported names, so this file does not
 * depend on how (or whether yet) they are implemented. Loaded images come
 * first, as with dyld: a Mach-O image may define standard-library types
 * itself (tests compiled as the module Swift do). */
static void *rt(const char *name) {
    return dx_global_lookup(name);
}
#define RT(type, var, sym)          \
    static __typeof__(type) var;    \
    if (!var) var = (type)rt(sym);

/* ---- arena ------------------------------------------------------------------ */
struct chunk {
    struct chunk *next;
    size_t used, cap;
    _Alignas(16) char data[];
};
struct arena {
    struct chunk *head;
};
static void *arena_alloc(struct arena *a, size_t n) {
    n = (n + 15) & ~(size_t)15;
    if (!a->head || a->head->used + n > a->head->cap) {
        size_t cap = n > 8192 ? n : 8192;
        struct chunk *c = malloc(sizeof *c + cap);
        c->next = a->head;
        c->used = 0;
        c->cap = cap;
        a->head = c;
    }
    void *p = a->head->data + a->head->used;
    a->head->used += n;
    memset(p, 0, n);
    return p;
}
static void arena_free(struct arena *a) {
    while (a->head) {
        struct chunk *n = a->head->next;
        free(a->head);
        a->head = n;
    }
}

/* ---- the tree --------------------------------------------------------------- */
enum {
    NK_IDENT,      /* text */
    NK_MODULE,     /* text */
    NK_NOMINAL,    /* by name: sub = V C O P a; kids: context, identifier */
    NK_CTX,        /* symbolic reference to a context descriptor: ptr */
    NK_OBJC_PROTO, /* ptr = Objective-C protocol object */
    NK_ACCESSOR,   /* ptr = function returning metadata from generic args */
    NK_STD,        /* standard library type/protocol: sub = letter, a = 1 for Sc* */
    NK_BOUND,      /* kids[0] = nominal, then one NK_LIST of arguments per level, outermost first */
    NK_TUPLE,      /* kids: NK_ELEM */
    NK_ELEM,       /* text = label or NULL, a = variadic; kids[0] = type */
    NK_FUNC,       /* sub = kind (see FN_*), a = flags; kids[0] = result, kids[1] = params */
    NK_PARAMFLAG,  /* a = parameter flags (ownership etc.); kids[0] = type */
    NK_METATYPE,
    NK_EXIST_METATYPE,
    NK_EXIST,      /* a = class bound, b = has superclass (kids[0]); then protocols */
    NK_GPARAM,     /* a = depth, b = index */
    NK_DEPMEMBER,  /* kids: base, identifier, protocol (optional) */
    NK_BUILTIN,    /* text = mangling after 'B' (e.g. "i64_") */
    NK_OPAQUE,     /* a = ordinal; kids[0] = opaque descriptor, then arguments */
    NK_STORAGE,    /* sub = w (weak) o (unowned) u (unowned(unsafe)); kids[0] */
    NK_EMPTY,      /* 'y' */
    NK_FIRST,      /* '_' */
    NK_VARIADIC,   /* 'd' */
    NK_FLAG,       /* function annotation: a = FL_*, kids[0] = global actor/thrown type */
    NK_EXT,        /* extension context: kids: module, extended type */
    NK_LIST,       /* generic arguments of one level */
    NK_PRIVATE,    /* private declaration name: text = name, kids[0] = discriminator */
};
enum { FL_THROWS = 1, FL_ASYNC = 2, FL_SENDABLE = 4, FL_GLOBAL_ACTOR = 8, FL_TYPED_THROWS = 16,
       FL_OTHER = 32 };
enum { FN_SWIFT, FN_NOESCAPE, FN_BLOCK, FN_C, FN_THIN, FN_AUTOCLOSURE, FN_AUTOCLOSURE_NOESCAPE };

struct node {
    uint8_t kind;
    char sub;
    uint16_t nkids, capkids;
    uint32_t a, b;
    const void *ptr;
    const char *text;
    struct node **kids;
};

struct parser {
    const char *p, *end;
    struct arena *ar;
    struct node **stack;
    unsigned nstack, capstack;
    struct node **subs;
    unsigned nsubs, capsubs;
    const char *words[26];
    unsigned wordlen[26], nwords;
    const char *err;
};

static struct node *mk(struct parser *P, int kind) {
    struct node *n = arena_alloc(P->ar, sizeof *n);
    n->kind = kind;
    return n;
}
static void add_kid(struct parser *P, struct node *n, struct node *k) {
    if (n->nkids == n->capkids) {
        unsigned cap = n->capkids ? n->capkids * 2 : 4;
        struct node **nk = arena_alloc(P->ar, cap * sizeof *nk);
        if (n->nkids) memcpy(nk, n->kids, n->nkids * sizeof *nk);
        n->kids = nk;
        n->capkids = cap;
    }
    n->kids[n->nkids++] = k;
}
static void reverse_kids(struct node *n, unsigned from) {
    for (unsigned i = from, j = n->nkids; i + 1 < j; i++, j--) {
        struct node *t = n->kids[i];
        n->kids[i] = n->kids[j - 1];
        n->kids[j - 1] = t;
    }
}
static char *astrndup(struct parser *P, const char *s, size_t n) {
    char *d = arena_alloc(P->ar, n + 1);
    memcpy(d, s, n);
    return d;
}

static void push(struct parser *P, struct node *n) {
    if (P->nstack == P->capstack) {
        unsigned cap = P->capstack ? P->capstack * 2 : 32;
        struct node **s = arena_alloc(P->ar, cap * sizeof *s);
        if (P->nstack) memcpy(s, P->stack, P->nstack * sizeof *s);
        P->stack = s;
        P->capstack = cap;
    }
    P->stack[P->nstack++] = n;
}
static void add_sub(struct parser *P, struct node *n) {
    if (P->nsubs == P->capsubs) {
        unsigned cap = P->capsubs ? P->capsubs * 2 : 16;
        struct node **s = arena_alloc(P->ar, cap * sizeof *s);
        if (P->nsubs) memcpy(s, P->subs, P->nsubs * sizeof *s);
        P->subs = s;
        P->capsubs = cap;
    }
    P->subs[P->nsubs++] = n;
}
static struct node *top(struct parser *P) { return P->nstack ? P->stack[P->nstack - 1] : NULL; }
static struct node *pop(struct parser *P) { return P->nstack ? P->stack[--P->nstack] : NULL; }
static struct node *pop_kind(struct parser *P, int kind) {
    struct node *t = top(P);
    return t && t->kind == kind ? pop(P) : NULL;
}

static int ctx_kind_of(const struct node *n) {
    return n->kind == NK_CTX ? (int)sw_ctx_kind(((const sw_context_descriptor *)n->ptr)->flags) : -1;
}
/* Standard substitutions: letter -> (kind, name). Concurrency types follow
 * "Sc". Resolution goes through the exported symbols of the standard
 * library ($sSiN, $sSqMn, $sSQMp...), so these resolve as soon as a
 * standard library provides them. */
struct stdtype {
    char letter, kind;
    const char *name;
};
static const struct stdtype std_types[] = {
    {'A', 'V', "AutoreleasingUnsafeMutablePointer"}, {'a', 'V', "Array"},
    {'B', 'P', "BinaryFloatingPoint"}, {'b', 'V', "Bool"}, {'D', 'V', "Dictionary"},
    {'d', 'V', "Double"}, {'E', 'P', "Encodable"}, {'e', 'P', "Decodable"},
    {'F', 'P', "FloatingPoint"}, {'f', 'V', "Float"}, {'G', 'P', "RandomNumberGenerator"},
    {'H', 'P', "Hashable"}, {'h', 'V', "Set"}, {'I', 'V', "DefaultIndices"}, {'i', 'V', "Int"},
    {'J', 'V', "Character"}, {'j', 'P', "Numeric"}, {'K', 'P', "BidirectionalCollection"},
    {'k', 'P', "RandomAccessCollection"}, {'L', 'P', "Comparable"}, {'l', 'P', "Collection"},
    {'M', 'P', "MutableCollection"}, {'m', 'P', "RangeReplaceableCollection"},
    {'N', 'V', "ClosedRange"}, {'n', 'V', "Range"}, {'O', 'V', "ObjectIdentifier"},
    {'P', 'V', "UnsafePointer"}, {'p', 'V', "UnsafeMutablePointer"}, {'Q', 'P', "Equatable"},
    {'q', 'O', "Optional"}, {'R', 'V', "UnsafeBufferPointer"}, {'r', 'V', "UnsafeMutableBufferPointer"},
    {'S', 'V', "String"}, {'s', 'V', "Substring"}, {'T', 'P', "Sequence"}, {'t', 'P', "IteratorProtocol"},
    {'U', 'P', "UnsignedInteger"}, {'u', 'V', "UInt"}, {'V', 'V', "UnsafeRawPointer"},
    {'v', 'V', "UnsafeMutableRawPointer"}, {'W', 'V', "UnsafeRawBufferPointer"},
    {'w', 'V', "UnsafeMutableRawBufferPointer"}, {'X', 'P', "RangeExpression"}, {'x', 'P', "Strideable"},
    {'Y', 'P', "RawRepresentable"}, {'y', 'P', "StringProtocol"}, {'Z', 'P', "SignedInteger"},
    {'z', 'P', "BinaryInteger"}, {0, 0, 0}};
static const struct stdtype std_concurrency[] = {
    {'A', 'P', "Actor"}, {'C', 'V', "CheckedContinuation"}, {'c', 'V', "UnsafeContinuation"},
    {'E', 'V', "CancellationError"}, {'e', 'V', "UnownedSerialExecutor"}, {'F', 'P', "Executor"},
    {'f', 'P', "SerialExecutor"}, {'G', 'V', "TaskGroup"}, {'g', 'V', "ThrowingTaskGroup"},
    {'h', 'P', "TaskExecutor"}, {'I', 'P', "AsyncIteratorProtocol"}, {'i', 'P', "AsyncSequence"},
    {'J', 'V', "UnownedJob"}, {'M', 'C', "MainActor"}, {'P', 'V', "TaskPriority"},
    {'S', 'V', "AsyncStream"}, {'s', 'V', "AsyncThrowingStream"}, {'T', 'V', "Task"},
    {'t', 'V', "UnsafeCurrentTask"}, {0, 0, 0}};
static const struct stdtype *std_lookup(const struct node *n) {
    for (const struct stdtype *s = n->a ? std_concurrency : std_types; s->letter; s++)
        if (s->letter == n->sub) return s;
    return NULL;
}

static int is_proto(const struct node *n) {
    if (!n) return 0;
    switch (n->kind) {
    case NK_CTX: return ctx_kind_of(n) == SW_CTX_PROTOCOL;
    case NK_NOMINAL: return n->sub == 'P';
    case NK_STD: return std_lookup(n) && std_lookup(n)->kind == 'P';
    case NK_OBJC_PROTO: return 1;
    default: return 0;
    }
}
static int is_type(const struct node *n) {
    if (!n) return 0;
    switch (n->kind) {
    case NK_CTX: {
        int k = ctx_kind_of(n);
        return k == SW_CTX_CLASS || k == SW_CTX_STRUCT || k == SW_CTX_ENUM;
    }
    case NK_NOMINAL: return n->sub != 'P';
    case NK_STD: return std_lookup(n) && std_lookup(n)->kind != 'P';
    case NK_ACCESSOR: case NK_BOUND: case NK_TUPLE: case NK_FUNC: case NK_PARAMFLAG:
    case NK_METATYPE: case NK_EXIST_METATYPE: case NK_EXIST: case NK_GPARAM: case NK_DEPMEMBER:
    case NK_BUILTIN: case NK_OPAQUE: case NK_STORAGE:
        return 1;
    default: return 0;
    }
}
static struct node *pop_type(struct parser *P) { return is_type(top(P)) ? pop(P) : NULL; }
static struct node *pop_proto(struct parser *P) { return is_proto(top(P)) ? pop(P) : NULL; }

static int fail(struct parser *P, const char *why) {
    if (!P->err) P->err = why;
    return -1;
}

/* ---- lexical pieces ------------------------------------------------------- */
static int peek(struct parser *P) { return P->p < P->end ? (unsigned char)*P->p : -1; }
static int next(struct parser *P) { return P->p < P->end ? (unsigned char)*P->p++ : -1; }
static int next_if(struct parser *P, char c) {
    if (peek(P) == (unsigned char)c) {
        P->p++;
        return 1;
    }
    return 0;
}
static int is_digit(int c) { return c >= '0' && c <= '9'; }
static int is_lower(int c) { return c >= 'a' && c <= 'z'; }
static int is_upper(int c) { return c >= 'A' && c <= 'Z'; }

/* NATURAL: decimal digits; -1 if none. */
static long natural(struct parser *P) {
    if (!is_digit(peek(P))) return -1;
    long n = 0;
    while (is_digit(peek(P))) {
        n = n * 10 + (next(P) - '0');
        if (n > 1 << 24) return -1;
    }
    return n;
}
/* INDEX ::= '_' (0) | NATURAL '_' (N+1) */
static long mindex(struct parser *P) {
    if (next_if(P, '_')) return 0;
    long n = natural(P);
    if (n < 0 || !next_if(P, '_')) return -1;
    return n + 1;
}

/* Identifiers record their words (runs starting at a letter, split at
 * lower->upper transitions and underscores) so later identifiers can say
 * "0" + word indexes instead of repeating them. */
static int word_start(int c) { return c && !is_digit(c) && c != '_'; }
static int word_end(int c, int prev) { return c == '_' || c == 0 || (!is_upper(prev) && is_upper(c)); }
static void note_words(struct parser *P, const char *s, size_t n) {
    long start = -1;
    for (size_t i = 0; i <= n; i++) {
        int c = i < n ? (unsigned char)s[i] : 0;
        if (start >= 0 && word_end(c, (unsigned char)s[i - 1])) {
            if (i - start >= 2 && P->nwords < 26) {
                P->words[P->nwords] = s + start;
                P->wordlen[P->nwords++] = i - start;
            }
            start = -1;
        }
        if (start < 0 && word_start(c)) start = i;
    }
}
static int identifier(struct parser *P) {
    int words = 0;
    if (next_if(P, '0')) {
        if (peek(P) == '0') return fail(P, "punycode identifiers are not supported");
        words = 1;
    }
    /* With word substitutions: lower-case letters are word indexes, an
     * upper-case one is the last index, digits introduce a literal chunk and
     * '0' ends the identifier. */
    char buf[512];
    size_t len = 0;
    do {
        while (words && (is_lower(peek(P)) || is_upper(peek(P)))) {
            int c = next(P);
            unsigned w = is_lower(c) ? (unsigned)(c - 'a') : (unsigned)(c - 'A');
            if (is_upper(c)) words = 0;
            if (w >= P->nwords || len + P->wordlen[w] >= sizeof buf) return fail(P, "bad word substitution");
            memcpy(buf + len, P->words[w], P->wordlen[w]);
            len += P->wordlen[w];
        }
        if (next_if(P, '0')) break;
        long n = natural(P);
        if (n <= 0 || n > P->end - P->p || len + n >= sizeof buf) return fail(P, "bad identifier");
        memcpy(buf + len, P->p, n);
        len += n;
        note_words(P, P->p, n);
        P->p += n;
    } while (words);
    if (!len) return fail(P, "empty identifier");
    struct node *id = mk(P, NK_IDENT);
    id->text = astrndup(P, buf, len);
    add_sub(P, id);
    push(P, id);
    return 0;
}

/* ---- operators -------------------------------------------------------------- */
static int symbolic(struct parser *P, int kind) {
    if (P->p + 4 > P->end) return fail(P, "truncated symbolic reference");
    int32_t off;
    memcpy(&off, P->p, 4);
    const char *at = P->p;
    P->p += 4;
    const void *target = at + off;
    switch (kind) {
    case 0x01: case 0x02: {
        if (kind == 0x02) target = *(const void *const *)target;
        const sw_context_descriptor *c = target;
        if (!c) return fail(P, "unbound symbolic reference");
        unsigned k = sw_ctx_kind(c->flags);
        /* An import nobody implements is bound to a code stub, which does
         * not look like a descriptor. */
        if (k > SW_CTX_OPAQUE_TYPE && (k < SW_CTX_CLASS || k > SW_CTX_ENUM))
            return fail(P, "symbolic reference to something that is not a descriptor (missing import?)");
        struct node *n = mk(P, NK_CTX);
        n->ptr = c;
        if (k != SW_CTX_OPAQUE_TYPE) add_sub(P, n);
        push(P, n);
        return 0;
    }
    case 0x09: {
        struct node *n = mk(P, NK_ACCESSOR);
        n->ptr = target;
        push(P, n);
        return 0;
    }
    case 0x0c: {
        /* Relative reference to an Objective-C protocol reference slot. */
        struct node *n = mk(P, NK_OBJC_PROTO);
        n->ptr = *(const void *const *)target;
        push(P, n);
        return 0;
    }
    default:
        return fail(P, kind == 0x0a || kind == 0x0b
                           ? "extended existential shapes (any P<T>) are not supported yet"
                           : "unknown symbolic reference kind");
    }
}

static int nominal(struct parser *P, char kind) {
    struct node *name = pop(P);
    if (name && name->kind != NK_IDENT && name->kind != NK_PRIVATE) name = NULL;
    if (!name) return fail(P, "nominal type without a name");
    struct node *ctx = pop(P);
    if (!ctx) return fail(P, "nominal type without a context");
    if (ctx->kind == NK_IDENT) {
        struct node *m = mk(P, NK_MODULE);
        m->text = ctx->text;
        ctx = m;
    }
    if (ctx->kind != NK_MODULE && ctx->kind != NK_CTX && ctx->kind != NK_NOMINAL && ctx->kind != NK_STD &&
        ctx->kind != NK_EXT)
        return fail(P, "bad context for a nominal type");
    struct node *n = mk(P, NK_NOMINAL);
    n->sub = kind;
    add_kid(P, n, ctx);
    add_kid(P, n, name);
    add_sub(P, n);
    push(P, n);
    return 0;
}

/* context module 'E': an extension declared in `module` (not added to
 * the substitutions). */
static int extension(struct parser *P) {
    struct node *mod = pop(P);
    if (mod && mod->kind == NK_IDENT) {
        struct node *m = mk(P, NK_MODULE);
        m->text = mod->text;
        mod = m;
    }
    struct node *ty = pop(P);
    if (!mod || mod->kind != NK_MODULE || !ty ||
        !(ty->kind == NK_CTX || ty->kind == NK_NOMINAL || ty->kind == NK_STD))
        return fail(P, "bad extension context");
    struct node *e = mk(P, NK_EXT);
    add_kid(P, e, mod);
    add_kid(P, e, ty);
    push(P, e);
    return 0;
}

/* `y` list `_` list ... `G`: arguments of each generic level, innermost
 * level last in the text and first off the stack. */
static int bound_generic(struct parser *P) {
    struct node *levels[16];
    unsigned nlev = 0;
    for (;;) {
        if (nlev == 16) return fail(P, "too many generic levels");
        struct node *l = mk(P, NK_TUPLE);
        while (is_type(top(P))) add_kid(P, l, pop(P));
        reverse_kids(l, 0);
        levels[nlev++] = l;
        if (pop_kind(P, NK_EMPTY)) break;
        if (!pop_kind(P, NK_FIRST)) return fail(P, "bad generic argument list");
    }
    struct node *nom = pop(P);
    if (!nom || !(nom->kind == NK_CTX || nom->kind == NK_NOMINAL || nom->kind == NK_STD))
        return fail(P, "generic arguments without a nominal type");
    struct node *b = mk(P, NK_BOUND);
    add_kid(P, b, nom);
    for (unsigned i = nlev; i-- > 0;) {
        levels[i]->kind = NK_LIST;
        add_kid(P, b, levels[i]);
    }
    add_sub(P, b);
    push(P, b);
    return 0;
}

static int tuple(struct parser *P) {
    struct node *t = mk(P, NK_TUPLE);
    if (!pop_kind(P, NK_EMPTY)) {
        int first;
        do {
            first = pop_kind(P, NK_FIRST) != NULL;
            struct node *e = mk(P, NK_ELEM);
            if (pop_kind(P, NK_VARIADIC)) e->a = 1;
            struct node *label = pop_kind(P, NK_IDENT);
            if (label) e->text = label->text;
            struct node *ty = pop_type(P);
            if (!ty) return fail(P, "tuple element is not a type");
            add_kid(P, e, ty);
            add_kid(P, t, e);
        } while (!first);
        reverse_kids(t, 0);
    }
    push(P, t);
    return 0;
}

static int function(struct parser *P, int kind) {
    struct node *f = mk(P, NK_FUNC);
    f->sub = kind;
    struct node *flag;
    while ((flag = pop_kind(P, NK_FLAG))) {
        f->a |= flag->a;
        if (flag->nkids) add_kid(P, f, flag); /* global actor / thrown type, kept after the params */
    }
    /* An empty list stands for () as parameters or result. */
    struct node *params = pop_kind(P, NK_EMPTY) ? mk(P, NK_TUPLE) : pop_type(P);
    struct node *result = pop_kind(P, NK_EMPTY) ? mk(P, NK_TUPLE) : pop_type(P);
    if (!params || !result) return fail(P, "bad function type");
    struct node **extra = f->kids;
    unsigned nextra = f->nkids;
    f->kids = NULL;
    f->nkids = f->capkids = 0;
    add_kid(P, f, result);
    add_kid(P, f, params);
    for (unsigned i = 0; i < nextra; i++) add_kid(P, f, extra[i]);
    push(P, f);
    return 0;
}

/* In protocol lists a protocol may also be written as context + name
 * without its 'P' (and is then not a substitution). */
static struct node *pop_list_proto(struct parser *P) {
    struct node *p = pop_proto(P);
    if (p) return p;
    struct node *name = pop_kind(P, NK_IDENT);
    struct node *ctx = name ? pop(P) : NULL;
    if (!ctx) return NULL;
    if (ctx->kind == NK_IDENT) {
        struct node *m = mk(P, NK_MODULE);
        m->text = ctx->text;
        ctx = m;
    }
    p = mk(P, NK_NOMINAL);
    p->sub = 'P';
    add_kid(P, p, ctx);
    add_kid(P, p, name);
    return p;
}

/* protocol-list ::= protocol '_' protocol* | 'y' */
static int protocol_list(struct parser *P, struct node *ex) {
    unsigned start = ex->nkids;
    if (pop_kind(P, NK_EMPTY)) return 0;
    int first;
    do {
        first = pop_kind(P, NK_FIRST) != NULL;
        struct node *p = pop_list_proto(P);
        if (!p) return fail(P, "bad protocol list");
        add_kid(P, ex, p);
    } while (!first);
    reverse_kids(ex, start);
    return 0;
}

static struct node *gparam(struct parser *P, unsigned depth, unsigned index) {
    struct node *n = mk(P, NK_GPARAM);
    n->a = depth;
    n->b = index;
    return n;
}
/* GENERIC-PARAM-INDEX ::= 'z' (0,0) | INDEX (0, N+1) | 'd' INDEX INDEX (M+1, N) */
static struct node *gparam_index(struct parser *P) {
    if (next_if(P, 'd')) {
        long d = mindex(P), i = d < 0 ? -1 : mindex(P);
        if (i < 0) return NULL;
        return gparam(P, d + 1, i);
    }
    if (next_if(P, 'z')) return gparam(P, 0, 0);
    long i = mindex(P);
    return i < 0 ? NULL : gparam(P, 0, i + 1);
}

/* assoc-type-name ::= identifier protocol? */
static struct node *assoc_name(struct parser *P, struct node **proto) {
    *proto = pop_proto(P);
    return pop_kind(P, NK_IDENT);
}
static struct node *depmember(struct parser *P, struct node *base, struct node *name, struct node *proto) {
    struct node *d = mk(P, NK_DEPMEMBER);
    add_kid(P, d, base);
    add_kid(P, d, name);
    if (proto) add_kid(P, d, proto);
    return d;
}
static int assoc_simple(struct parser *P, struct node *base) {
    struct node *proto, *name = assoc_name(P, &proto);
    if (!name) return fail(P, "bad associated type name");
    if (!base && !(base = pop_type(P))) return fail(P, "associated type without a base");
    struct node *d = depmember(P, base, name, proto);
    add_sub(P, d);
    push(P, d);
    return 0;
}
static int assoc_compound(struct parser *P, struct node *base) {
    struct node *names[16], *protos[16];
    unsigned n = 0;
    int first;
    do {
        first = pop_kind(P, NK_FIRST) != NULL;
        if (n == 16 || !(names[n] = assoc_name(P, &protos[n]))) return fail(P, "bad associated type path");
        n++;
    } while (!first);
    if (!base && !(base = pop_type(P))) return fail(P, "associated type without a base");
    while (n--) base = depmember(P, base, names[n], protos[n]);
    add_sub(P, base);
    push(P, base);
    return 0;
}

static int archetype(struct parser *P) {
    int c = next(P);
    switch (c) {
    case 'z': return assoc_simple(P, gparam(P, 0, 0));
    case 'Z': return assoc_compound(P, gparam(P, 0, 0));
    case 'y': case 'Y': {
        struct node *g = gparam_index(P);
        if (!g) return fail(P, "bad generic parameter index");
        return c == 'y' ? assoc_simple(P, g) : assoc_compound(P, g);
    }
    case 'x': return assoc_simple(P, NULL);
    case 'X': return assoc_compound(P, NULL);
    case 'o': {
        long ord = mindex(P);
        if (ord < 0) return fail(P, "bad opaque type ordinal");
        /* Generic arguments of the opaque type, as for 'G'. */
        struct node *levels[16];
        unsigned nlev = 0;
        for (;;) {
            if (nlev == 16) return fail(P, "too many generic levels");
            struct node *l = mk(P, NK_TUPLE);
            while (is_type(top(P))) add_kid(P, l, pop(P));
            reverse_kids(l, 0);
            levels[nlev++] = l;
            if (pop_kind(P, NK_EMPTY)) break;
            if (!pop_kind(P, NK_FIRST)) return fail(P, "bad opaque type arguments");
        }
        struct node *decl = pop(P);
        if (!decl || ctx_kind_of(decl) != SW_CTX_OPAQUE_TYPE)
            return fail(P, "opaque type without its descriptor");
        struct node *o = mk(P, NK_OPAQUE);
        o->a = ord;
        add_kid(P, o, decl);
        for (unsigned i = nlev; i-- > 0;)
            for (unsigned j = 0; j < levels[i]->nkids; j++) add_kid(P, o, levels[i]->kids[j]);
        add_sub(P, o);
        push(P, o);
        return 0;
    }
    default:
        return fail(P, "unsupported archetype mangling");
    }
}

static int std_subst(struct parser *P) {
    long count = natural(P);
    if (count < 0) count = 1;
    int c = next(P);
    struct node *n = NULL;
    switch (c) {
    case 'o': case 'C':
        n = mk(P, NK_MODULE);
        n->text = c == 'o' ? "__C" : "__C_Synthesized";
        break;
    case 'g': {
        struct node *t = pop_type(P);
        if (!t) return fail(P, "Sg without a type");
        struct node *opt = mk(P, NK_STD), *l = mk(P, NK_LIST);
        opt->sub = 'q';
        n = mk(P, NK_BOUND);
        add_kid(P, n, opt);
        add_kid(P, l, t);
        add_kid(P, n, l);
        add_sub(P, n);
        break;
    }
    case 'c':
        n = mk(P, NK_STD);
        n->sub = next(P);
        n->a = 1;
        if (!std_lookup(n)) return fail(P, "unknown concurrency substitution");
        break;
    default:
        n = mk(P, NK_STD);
        n->sub = c;
        if (!std_lookup(n)) return fail(P, "unknown standard substitution");
    }
    while (count-- > 0) push(P, n);
    return 0;
}

static int multi_subst(struct parser *P) {
    long rep = -1;
    for (;;) {
        int c = next(P);
        if (is_lower(c) || is_upper(c)) {
            unsigned i = is_lower(c) ? c - 'a' : c - 'A';
            if (i >= P->nsubs) return fail(P, "substitution out of range");
            for (long k = 0; k < (rep < 1 ? 1 : rep); k++) push(P, P->subs[i]);
            if (is_upper(c)) return 0;
            rep = -1;
            continue;
        }
        if (c == '_') {
            unsigned i = (unsigned)rep + 27;
            if (rep < 0 || i >= P->nsubs) return fail(P, "substitution out of range");
            push(P, P->subs[i]);
            return 0;
        }
        P->p--;
        if ((rep = natural(P)) < 0) return fail(P, "bad substitution");
    }
}

static int builtin(struct parser *P) {
    const char *s = P->p;
    int c = next(P);
    switch (c) {
    case 'i': case 'f':
        if (natural(P) < 0 || !next_if(P, '_')) return fail(P, "bad builtin");
        break;
    case 'b': case 'B': case 'c': case 'D': case 'd': case 'e': case 'I': case 'j': case 'o':
    case 'O': case 'p': case 't': case 'w':
        break;
    default:
        return fail(P, "unsupported builtin type");
    }
    struct node *n = mk(P, NK_BUILTIN);
    n->text = astrndup(P, s, P->p - s);
    push(P, n);
    return 0;
}

static int wrap(struct parser *P, int kind, char sub, uint32_t a) {
    struct node *t = pop_type(P);
    if (!t) return fail(P, "type operator without a type");
    struct node *n = mk(P, kind);
    n->sub = sub;
    n->a = a;
    add_kid(P, n, t);
    push(P, n);
    return 0;
}
static int flag(struct parser *P, uint32_t f, int with_type) {
    struct node *n = mk(P, NK_FLAG);
    n->a = f;
    if (with_type) {
        struct node *t = pop_type(P);
        if (!t) return fail(P, "annotation without a type");
        add_kid(P, n, t);
    }
    push(P, n);
    return 0;
}

static int special(struct parser *P) {
    int c = next(P);
    switch (c) {
    case 'p': return wrap(P, NK_EXIST_METATYPE, 0, 0);
    case 'M': return wrap(P, NK_METATYPE, next(P), 0); /* with representation: T thick, t thin, o objc */
    case 'm': return wrap(P, NK_EXIST_METATYPE, next(P), 0);
    case 'l': case 'c': {
        struct node *ex = mk(P, NK_EXIST);
        ex->a = 1;
        if (c == 'c') {
            struct node *sup = pop_type(P);
            if (!sup) return fail(P, "bad superclass constraint");
            ex->b = 1;
            add_kid(P, ex, sup);
        }
        if (protocol_list(P, ex)) return -1;
        push(P, ex);
        return 0;
    }
    case 'B': case 'L': return function(P, FN_BLOCK);
    case 'E': return function(P, FN_NOESCAPE);
    case 'C': return function(P, FN_C);
    case 'f': return function(P, FN_THIN);
    case 'A': return function(P, FN_AUTOCLOSURE);
    case 'K': return function(P, FN_AUTOCLOSURE_NOESCAPE);
    case 'w': case 'o': case 'u': return wrap(P, NK_STORAGE, c, 0);
    case 'S': {
        int s = next(P);
        if (s == 'p') return 0; /* parenthesised type: a no-op */
        struct node *n = mk(P, NK_BOUND), *base = mk(P, NK_STD), *l = mk(P, NK_LIST);
        if (s == 'q' || s == 'a') {
            struct node *t = pop_type(P);
            if (!t) return fail(P, "bad sugared type");
            base->sub = s;
            add_kid(P, l, t);
        } else if (s == 'D') {
            struct node *v = pop_type(P), *k = pop_type(P);
            if (!k || !v) return fail(P, "bad sugared dictionary");
            base->sub = 'D';
            add_kid(P, l, k);
            add_kid(P, l, v);
        } else {
            return fail(P, "unknown sugared type");
        }
        add_kid(P, n, base);
        add_kid(P, n, l);
        push(P, n);
        return 0;
    }
    default:
        return fail(P, "unsupported special type");
    }
}

static int annotation(struct parser *P) {
    int c = next(P);
    switch (c) {
    case 'a': return flag(P, FL_ASYNC, 0);
    case 'b': return flag(P, FL_SENDABLE, 0);
    case 'c': return flag(P, FL_GLOBAL_ACTOR, 1);
    case 'K': return flag(P, FL_TYPED_THROWS, 1);
    case 'T': case 'A': return flag(P, FL_OTHER, 0); /* sending result, @isolated(any) */
    case 'i': return wrap(P, NK_PARAMFLAG, 'i', 0x400);
    case 'u': return wrap(P, NK_PARAMFLAG, 'u', 0x800);
    default: return fail(P, "unsupported annotation");
    }
}

static int op(struct parser *P) {
    int c = next(P);
    if (c >= 0x01 && c <= 0x17) return symbolic(P, c);
    if (c >= 0x18 && c <= 0x1f) return fail(P, "absolute symbolic references are not supported");
    if (is_digit(c)) {
        P->p--;
        return identifier(P);
    }
    switch (c) {
    case 'A': return multi_subst(P);
    case 'B': return builtin(P);
    case 'C': case 'O': case 'V': case 'P': case 'a': return nominal(P, c);
    case 'E': return extension(P);
    case 'G': return bound_generic(P);
    case 'K': return flag(P, FL_THROWS, 0);
    case 'L': {
        /* name discriminator 'LL': a private declaration */
        if (!next_if(P, 'L')) return fail(P, "local declarations are not supported");
        struct node *disc = pop_kind(P, NK_IDENT), *name = pop_kind(P, NK_IDENT);
        if (!disc || !name) return fail(P, "bad private declaration name");
        struct node *n = mk(P, NK_PRIVATE);
        n->text = name->text;
        add_kid(P, n, disc);
        push(P, n);
        return 0;
    }
    case 'Q': return archetype(P);
    case 'S': return std_subst(P);
    case 'X': return special(P);
    case 'Y': return annotation(P);
    case 'c': return function(P, FN_SWIFT);
    case 'd': push(P, mk(P, NK_VARIADIC)); return 0;
    case 'h': return wrap(P, NK_PARAMFLAG, 'h', 2);
    case 'n': return wrap(P, NK_PARAMFLAG, 'n', 3);
    case 'z': return wrap(P, NK_PARAMFLAG, 'z', 1);
    case 'm': return wrap(P, NK_METATYPE, 0, 0);
    case 'p': {
        struct node *ex = mk(P, NK_EXIST);
        if (protocol_list(P, ex)) return -1;
        push(P, ex);
        return 0;
    }
    case 'q': {
        struct node *g = gparam_index(P);
        if (!g) return fail(P, "bad generic parameter index");
        push(P, g);
        return 0;
    }
    case 's': {
        struct node *m = mk(P, NK_MODULE);
        m->text = "Swift";
        push(P, m);
        return 0;
    }
    case 't': return tuple(P);
    case 'x': push(P, gparam(P, 0, 0)); return 0;
    case 'y': push(P, mk(P, NK_EMPTY)); return 0;
    case '_': push(P, mk(P, NK_FIRST)); return 0;
    default: return fail(P, "unsupported mangling operator");
    }
}

/* Parses a whole mangled type name. `$s`/`$S`/`_T0` prefixes (protocol
 * names in requirement signatures carry one) and a leading 0xFF (marks
 * names relative to a protocol, see protocols.c) are skipped. */
static struct node *parse(struct parser *P, struct arena *ar, const char *name, size_t len) {
    memset(P, 0, sizeof *P);
    P->ar = ar;
    P->p = name;
    P->end = name + len;
    if (P->p < P->end && (unsigned char)*P->p == 0xFF) P->p++;
    if (P->end - P->p >= 2 && P->p[0] == '$' && (P->p[1] == 's' || P->p[1] == 'S')) P->p += 2;
    else if (P->end - P->p >= 3 && !memcmp(P->p, "_T0", 3)) P->p += 3;
    while (P->p < P->end)
        if (op(P)) return NULL;
    if (P->nstack != 1) {
        fail(P, P->nstack ? "trailing operands" : "empty name");
        return NULL;
    }
    return P->stack[0];
}

size_t sw_mangled_name_length(const char *name) {
    const unsigned char *p = (const unsigned char *)name;
    while (*p) {
        if (*p >= 0x01 && *p <= 0x17) p += 5;
        else if (*p >= 0x18 && *p <= 0x1f) p += 9;
        else p++;
    }
    return p - (const unsigned char *)name;
}

/* ---- string building ---------------------------------------------------------- */
struct sbuf {
    char *s;
    size_t n, cap;
    int key; /* printing a lookup key: extensions print as the type they extend */
};
static void sb_putn(struct sbuf *b, const char *s, size_t n) {
    if (b->n + n + 1 > b->cap) {
        b->cap = (b->n + n + 1) * 2;
        b->s = realloc(b->s, b->cap);
    }
    memcpy(b->s + b->n, s, n);
    b->n += n;
    b->s[b->n] = 0;
}
static void sb_puts(struct sbuf *b, const char *s) { sb_putn(b, s, strlen(s)); }
static void sb_printf(struct sbuf *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void sb_printf(struct sbuf *b, const char *fmt, ...) {
    char tmp[256];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(tmp, sizeof tmp, fmt, ap);
    va_end(ap);
    if (n > 0) sb_putn(b, tmp, (size_t)n < sizeof tmp ? (size_t)n : sizeof tmp - 1);
}
static char *sb_take(struct sbuf *b) {
    if (!b->s) sb_putn(b, "", 0);
    return b->s;
}

/* ---- context descriptors ------------------------------------------------------- */
static const sw_context_descriptor *ctx_parent(const sw_context_descriptor *c) {
    return sw_rel_indirect(&c->parent);
}
static const char *ctx_name(const sw_context_descriptor *c) {
    switch (sw_ctx_kind(c->flags)) {
    case SW_CTX_MODULE: return sw_rel((const int32_t *)c + 2);
    case SW_CTX_PROTOCOL: return sw_rel(&((const sw_protocol_descriptor *)c)->name);
    case SW_CTX_CLASS: case SW_CTX_STRUCT: case SW_CTX_ENUM:
        return sw_rel(&((const sw_type_context_descriptor *)c)->name);
    default: return NULL;
    }
}

static void print_node(struct sbuf *b, const struct node *n);

/* "Module.Outer.Name". Extensions print as the type they extend; anonymous
 * contexts (private and local declarations) are left out. */
static void print_ctx(struct sbuf *b, const sw_context_descriptor *c) {
    if (!c) return;
    unsigned k = sw_ctx_kind(c->flags);
    if (k == SW_CTX_ANONYMOUS) {
        print_ctx(b, ctx_parent(c));
        return;
    }
    if (k == SW_CTX_EXTENSION) {
        const int32_t *ext = (const int32_t *)c + 2;
        const char *m = sw_rel(ext);
        struct arena ar = {0};
        struct parser P;
        struct node *n = m ? parse(&P, &ar, m, sw_mangled_name_length(m)) : NULL;
        if (n && n->kind == NK_BOUND) n = n->kids[0];
        if (n) print_node(b, n);
        else print_ctx(b, ctx_parent(c));
        arena_free(&ar);
        return;
    }
    if (k == SW_CTX_OPAQUE_TYPE) {
        sb_puts(b, "<opaque type>");
        return;
    }
    const sw_context_descriptor *parent = ctx_parent(c);
    if (k != SW_CTX_MODULE && parent) {
        size_t before = b->n;
        print_ctx(b, parent);
        if (b->n != before) sb_puts(b, ".");
    }
    const char *name = ctx_name(c);
    sb_puts(b, name ? name : "?");
}

void sw_context_name(const sw_context_descriptor *c, char *buf, size_t len) {
    struct sbuf b = {.key = 1};
    print_ctx(&b, c);
    snprintf(buf, len, "%s", sb_take(&b));
    free(b.s);
}

/* ---- printing ------------------------------------------------------------------- */
static void print_gparam(struct sbuf *b, unsigned depth, unsigned index) {
    char tmp[16];
    int n = 0;
    do {
        tmp[n++] = 'A' + index % 26;
        index /= 26;
    } while (index && n < 8);
    while (n) sb_putn(b, &tmp[--n], 1);
    if (depth) sb_printf(b, "%u", depth);
}
static const char *builtin_name(const char *t, char *buf, size_t len) {
    static const struct { char c; const char *name; } names[] = {
        {'b', "BridgeObject"}, {'B', "UnsafeValueBuffer"}, {'c', "RawUnsafeContinuation"},
        {'D', "DefaultActorStorage"}, {'d', "NonDefaultDistributedActorStorage"}, {'e', "Executor"},
        {'I', "IntLiteral"}, {'j', "Job"}, {'o', "NativeObject"}, {'O', "UnknownObject"},
        {'p', "RawPointer"}, {'t', "SILToken"}, {'w', "Word"}, {0, 0}};
    if (t[0] == 'i' || t[0] == 'f') {
        snprintf(buf, len, "%s%.*s", t[0] == 'i' ? "Int" : "FPIEEE", (int)strlen(t + 1) - 1, t + 1);
        return buf;
    }
    for (int i = 0; names[i].c; i++)
        if (names[i].c == t[0]) return names[i].name;
    return "?";
}
static void print_list(struct sbuf *b, struct node *const *k, unsigned n, const char *sep) {
    for (unsigned i = 0; i < n; i++) {
        if (i) sb_puts(b, sep);
        print_node(b, k[i]);
    }
}
static void print_objc_proto(struct sbuf *b, const void *p) {
    RT(const char *(*)(const void *), getname, "_protocol_getName");
    sb_puts(b, "__C.");
    sb_puts(b, p && getname ? getname(p) : "?");
}

/* A nominal type with one argument list per level: each list belongs to
 * the matching enclosing type, as in Outer<A>.Inner<B>. */
static void print_bound(struct sbuf *b, const struct node *nom, struct node *const *lev, unsigned nlev) {
    const struct node *own = lev[nlev - 1];
    if (nom->kind == NK_STD && !nom->a && nlev == 1 &&
        ((nom->sub == 'a' && own->nkids == 1) || (nom->sub == 'D' && own->nkids == 2))) {
        sb_puts(b, "[");
        print_list(b, own->kids, own->nkids, " : ");
        sb_puts(b, "]");
        return;
    }
    if (nlev > 1 && nom->kind == NK_NOMINAL &&
        (nom->kids[0]->kind == NK_NOMINAL || nom->kids[0]->kind == NK_CTX || nom->kids[0]->kind == NK_STD)) {
        print_bound(b, nom->kids[0], lev, nlev - 1);
        sb_puts(b, ".");
        print_node(b, nom->kids[1]);
    } else {
        print_node(b, nom);
        if (nlev > 1) {
            /* Enclosing levels we cannot attribute: print them all here. */
            unsigned printed = 0;
            for (unsigned i = 0; i < nlev; i++)
                for (unsigned j = 0; j < lev[i]->nkids; j++) {
                    sb_puts(b, printed++ ? ", " : "<");
                    print_node(b, lev[i]->kids[j]);
                }
            if (printed) sb_puts(b, ">");
            return;
        }
    }
    if (own->nkids) {
        sb_puts(b, "<");
        print_node(b, own);
        sb_puts(b, ">");
    }
}

static void print_node(struct sbuf *b, const struct node *n) {
    switch (n->kind) {
    case NK_IDENT: case NK_MODULE: sb_puts(b, n->text); break;
    case NK_PRIVATE:
        if (b->key) sb_puts(b, n->text);
        else sb_printf(b, "(%s in %s)", n->text, n->kids[0]->text);
        break;
    case NK_LIST: print_list(b, n->kids, n->nkids, ", "); break;
    case NK_EXT:
        if (!b->key) sb_printf(b, "(extension in %s):", n->kids[0]->text);
        print_node(b, n->kids[1]);
        break;
    case NK_NOMINAL:
        print_node(b, n->kids[0]);
        sb_puts(b, ".");
        print_node(b, n->kids[1]);
        break;
    case NK_CTX: print_ctx(b, n->ptr); break;
    case NK_OBJC_PROTO: print_objc_proto(b, n->ptr); break;
    case NK_ACCESSOR: sb_puts(b, "<accessor>"); break;
    case NK_STD: sb_puts(b, "Swift."); sb_puts(b, std_lookup(n)->name); break;
    case NK_BOUND: {
        const struct node *base = n->kids[0], *l = n->kids[n->nkids - 1];
        if (base->kind == NK_STD && !base->a && base->sub == 'q' && n->nkids == 2 && l->nkids == 1) {
            const struct node *t = l->kids[0];
            int paren = t->kind == NK_FUNC || (t->kind == NK_EXIST && t->nkids + (t->a && !t->b) > 1);
            if (paren) sb_puts(b, "(");
            print_node(b, t);
            sb_puts(b, paren ? ")?" : "?");
        } else {
            print_bound(b, base, n->kids + 1, n->nkids - 1);
        }
        break;
    }
    case NK_TUPLE:
        sb_puts(b, "(");
        for (unsigned i = 0; i < n->nkids; i++) {
            const struct node *e = n->kids[i];
            if (i) sb_puts(b, ", ");
            if (e->text) sb_printf(b, "%s: ", e->text);
            print_node(b, e->kids[0]);
            if (e->a) sb_puts(b, "...");
        }
        sb_puts(b, ")");
        break;
    case NK_FUNC: {
        static const char *const conv[] = {[FN_BLOCK] = "@convention(block) ", [FN_C] = "@convention(c) ",
                                           [FN_THIN] = "@convention(thin) ", [FN_AUTOCLOSURE] = "@autoclosure ",
                                           [FN_AUTOCLOSURE_NOESCAPE] = "@autoclosure "};
        for (unsigned i = 2; i < n->nkids; i++)
            if (n->kids[i]->a == FL_GLOBAL_ACTOR) {
                sb_puts(b, "@");
                print_node(b, n->kids[i]->kids[0]);
                sb_puts(b, " ");
            }
        if ((unsigned)n->sub < sizeof conv / sizeof *conv && conv[(int)n->sub]) sb_puts(b, conv[(int)n->sub]);
        if (n->a & FL_SENDABLE) sb_puts(b, "@Sendable ");
        const struct node *params = n->kids[1];
        if (params->kind == NK_TUPLE) print_node(b, params);
        else {
            sb_puts(b, "(");
            print_node(b, params);
            sb_puts(b, ")");
        }
        if (n->a & FL_ASYNC) sb_puts(b, " async");
        if (n->a & FL_THROWS) sb_puts(b, " throws");
        for (unsigned i = 2; i < n->nkids; i++)
            if (n->kids[i]->a == FL_TYPED_THROWS) {
                sb_puts(b, " throws(");
                print_node(b, n->kids[i]->kids[0]);
                sb_puts(b, ")");
            }
        sb_puts(b, " -> ");
        print_node(b, n->kids[0]);
        break;
    }
    case NK_PARAMFLAG:
        sb_puts(b, n->sub == 'z' ? "inout " : n->sub == 'h' ? "__shared " : n->sub == 'n' ? "__owned "
                   : n->sub == 'i' ? "isolated " : "sending ");
        print_node(b, n->kids[0]);
        break;
    case NK_METATYPE: case NK_EXIST_METATYPE: {
        const struct node *t = n->kids[0];
        if (n->sub) sb_puts(b, n->sub == 'T' ? "@thick " : n->sub == 't' ? "@thin " : "@objc_metatype ");
        int paren = t->kind == NK_FUNC;
        if (paren) sb_puts(b, "(");
        print_node(b, t);
        sb_puts(b, paren ? ").Type" : ".Type");
        break;
    }
    case NK_EXIST: {
        unsigned first = n->b ? 1 : 0, count = 0;
        if (n->b) {
            print_node(b, n->kids[0]);
            count++;
        }
        for (unsigned i = first; i < n->nkids; i++, count++) {
            if (count) sb_puts(b, " & ");
            print_node(b, n->kids[i]);
        }
        if (n->a && !n->b) {
            if (count) sb_puts(b, " & ");
            sb_puts(b, "Swift.AnyObject");
            count++;
        }
        if (!count) sb_puts(b, "Any");
        break;
    }
    case NK_GPARAM: print_gparam(b, n->a, n->b); break;
    case NK_DEPMEMBER:
        print_node(b, n->kids[0]);
        sb_puts(b, ".");
        print_node(b, n->kids[1]);
        break;
    case NK_BUILTIN: {
        char tmp[32];
        sb_puts(b, "Builtin.");
        sb_puts(b, builtin_name(n->text, tmp, sizeof tmp));
        break;
    }
    case NK_OPAQUE:
        sb_printf(b, "<opaque type #%u of ", n->a);
        print_ctx(b, ctx_parent(n->kids[0]->ptr));
        sb_puts(b, ">");
        break;
    case NK_STORAGE:
        sb_puts(b, n->sub == 'w' ? "weak " : n->sub == 'o' ? "unowned " : "unowned(unsafe) ");
        print_node(b, n->kids[0]);
        break;
    default: sb_puts(b, "?"); break;
    }
}

/* ---- generic signatures and environments ----------------------------------------- */
const sw_generic_context_header *sw_generic_header(const sw_context_descriptor *c) {
    if (!c || !sw_ctx_is_generic(c->flags)) return NULL;
    const char *p = (const char *)c;
    switch (sw_ctx_kind(c->flags)) {
    case SW_CTX_CLASS: return (const void *)(p + sizeof(sw_class_descriptor) + 8);
    case SW_CTX_STRUCT: return (const void *)(p + sizeof(sw_struct_descriptor) + 8);
    case SW_CTX_ENUM: return (const void *)(p + sizeof(sw_enum_descriptor) + 8);
    case SW_CTX_EXTENSION: return (const void *)(p + 12);
    case SW_CTX_ANONYMOUS: case SW_CTX_OPAQUE_TYPE: return (const void *)(p + 8);
    default: return NULL;
    }
}
static const sw_generic_requirement *header_reqs(const sw_generic_context_header *h) {
    const uint8_t *params = (const uint8_t *)(h + 1);
    return (const void *)(params + ((h->num_params + 3) & ~3u));
}

void sw_env_init(struct sw_env *e, const sw_context_descriptor *ctx, const void *const *args) {
    memset(e, 0, sizeof *e);
    e->ctx = ctx;
    e->args = args;
    /* Cumulative parameter counts of the enclosing generic contexts,
     * outermost first: generic parameters are numbered by depth (how many
     * generic contexts out) and index within that depth. */
    unsigned counts[32], n = 0;
    for (const sw_context_descriptor *c = ctx; c && n < 32; c = ctx_parent(c)) {
        const sw_generic_context_header *h = sw_generic_header(c);
        if (h) counts[n++] = h->num_params;
    }
    for (unsigned i = n; i-- > 0;)
        if (!e->nlevels || counts[i] > e->levels[e->nlevels - 1])
            if (e->nlevels < sizeof e->levels / sizeof *e->levels) e->levels[e->nlevels++] = counts[i];
    const sw_generic_context_header *h = sw_generic_header(ctx);
    if (h) {
        e->nparams = h->num_params;
        e->params = (const uint8_t *)(h + 1);
        e->nreqs = h->num_requirements;
        e->reqs = header_reqs(h);
    }
}

/* Flat parameter position of (depth, index), or -1. */
static long param_position(const struct sw_env *e, unsigned depth, unsigned index) {
    if (!e->nlevels) return depth == 0 ? (long)index : -1;
    if (depth >= e->nlevels) return -1;
    unsigned base = depth ? e->levels[depth - 1] : 0;
    if (base + index >= e->levels[depth]) return -1;
    return base + index;
}
static unsigned key_param_count(const struct sw_env *e) {
    unsigned k = 0;
    for (unsigned i = 0; i < e->nparams; i++)
        if (e->params[i] & SW_GP_HAS_KEY_ARGUMENT) k++;
    return k;
}

static const sw_metadata *env_param(const struct sw_env *e, unsigned depth, unsigned index) {
    if (e->self && depth == 0 && index == 0) return e->self;
    long pos = param_position(e, depth, index);
    if (pos < 0) return NULL;
    if (e->flat) return e->flat[pos];
    if (!e->args) return NULL;
    if (!e->params) return e->args[pos];
    if ((unsigned)pos >= e->nparams || !(e->params[pos] & SW_GP_HAS_KEY_ARGUMENT)) return NULL;
    unsigned k = 0;
    for (long i = 0; i < pos; i++)
        if (e->params[i] & SW_GP_HAS_KEY_ARGUMENT) k++;
    return e->args[k];
}

/* ---- protocols -------------------------------------------------------------------- */
/* A resolved protocol: a Swift descriptor, or an Objective-C protocol with
 * the low bit set (the runtime's ProtocolDescriptorRef encoding). */
typedef uintptr_t proto_ref;
#define PROTO_OBJC 1

const sw_protocol_requirement *sw_protocol_requirements(const sw_protocol_descriptor *p) {
    const sw_generic_requirement *sig = (const void *)(p + 1);
    return (const void *)(sig + p->num_requirements_in_signature);
}

/* The requirement of protocol `p` for associated type `name`: associated
 * type names are listed in requirement order. */
const sw_protocol_requirement *sw_assoc_type_requirement(const sw_protocol_descriptor *p,
                                                         const char *name) {
    const char *names = sw_rel(&p->associated_type_names);
    if (!names) return NULL;
    size_t len = strlen(name);
    unsigned which = 0;
    const char *s = names;
    for (;;) {
        const char *sp = strchr(s, ' ');
        size_t n = sp ? (size_t)(sp - s) : strlen(s);
        if (n == len && !memcmp(s, name, n)) break;
        if (!sp) return NULL;
        s = sp + 1;
        which++;
    }
    const sw_protocol_requirement *r = sw_protocol_requirements(p);
    for (uint32_t i = 0; i < p->num_requirements; i++)
        if ((r[i].flags & 0xF) == 7 && which-- == 0) return &r[i];
    return NULL;
}

/* ---- name -> descriptor index ------------------------------------------------------ */
/* Types and protocols named in the mangling (rather than by symbolic
 * reference) are found by their qualified name in every image's
 * __swift5_types and __swift5_protos, indexed once and kept current as
 * images load. */
static pthread_mutex_t index_lock = PTHREAD_MUTEX_INITIALIZER;
static struct sw_map name_index; /* (hash, kind) -> struct named* */
static int index_ready;
struct named {
    struct named *next;
    char *name;
    const sw_context_descriptor *desc;
};

static void index_add(const sw_context_descriptor *d) {
    if (!d) return;
    struct sbuf b = {.key = 1};
    print_ctx(&b, d);
    char *name = sb_take(&b);
    unsigned k = sw_ctx_kind(d->flags);
    uintptr_t h = sw_hash_bytes(name, strlen(name));
    struct named *n = malloc(sizeof *n);
    n->name = name;
    n->desc = d;
    n->next = sw_map_get(&name_index, h, k, NULL);
    sw_map_put(&name_index, h, k, n);
}
static void index_types(const struct sw_section *s, void *ctx) {
    const int32_t *e = s->start;
    for (size_t i = 0; i < s->size / 4; i++) {
        int32_t off = e[i] & ~3;
        if (!off) continue;
        const void *p = (const char *)&e[i] + off;
        /* low bits: 0 direct descriptor, 1 indirect */
        if ((e[i] & 3) == 1) p = *(const void *const *)p;
        else if ((e[i] & 3) != 0) continue;
        pthread_mutex_lock(&index_lock);
        index_add(p);
        pthread_mutex_unlock(&index_lock);
    }
}
static void index_protos(const struct sw_section *s, void *ctx) {
    const int32_t *e = s->start;
    for (size_t i = 0; i < s->size / 4; i++) {
        const void *p = sw_rel_indirect(&e[i]);
        pthread_mutex_lock(&index_lock);
        index_add(p);
        pthread_mutex_unlock(&index_lock);
    }
}
static const sw_context_descriptor *find_by_name(const char *name, unsigned kind) {
    pthread_mutex_lock(&index_lock);
    int ready = index_ready;
    index_ready = 1;
    pthread_mutex_unlock(&index_lock);
    if (!ready) {
        sw_each_section(SW_SECT_TYPES, index_types, NULL, 1);
        sw_each_section(SW_SECT_TYPES2, index_types, NULL, 1);
        sw_each_section(SW_SECT_PROTOS, index_protos, NULL, 1);
    }
    pthread_mutex_lock(&index_lock);
    const sw_context_descriptor *r = NULL;
    for (struct named *n = sw_map_get(&name_index, sw_hash_bytes(name, strlen(name)), kind, NULL); n;
         n = n->next)
        if (!strcmp(n->name, name)) {
            r = n->desc;
            break;
        }
    pthread_mutex_unlock(&index_lock);
    return r;
}

/* ---- resolution ------------------------------------------------------------------------ */
struct resolver {
    const struct sw_env *env;
    const char *why;
    const struct node *what;
};
static const sw_metadata *resolve(struct resolver *R, const struct node *n);
static const sw_metadata *rfail(struct resolver *R, const struct node *n, const char *why) {
    if (!R->why) {
        R->why = why;
        R->what = n;
    }
    return NULL;
}

static int is_class_metadata(const sw_metadata *m) {
    uintptr_t k = sw_kind(m);
    return k == SW_KIND_CLASS || k == SW_KIND_OBJC_CLASS_WRAPPER || k == SW_KIND_FOREIGN_CLASS;
}
/* The class object (Swift metadata or Objective-C class) behind class-like metadata. */
const void *sw_class_of_metadata(const sw_metadata *m) {
    if (sw_kind(m) == SW_KIND_OBJC_CLASS_WRAPPER) return ((const sw_objc_wrapper_metadata *)m)->cls;
    if (sw_kind(m) == SW_KIND_CLASS) return m;
    return NULL;
}
int sw_is_subclass(const sw_metadata *sub, const sw_metadata *sup) {
    const void *s = sw_class_of_metadata(sub), *t = sw_class_of_metadata(sup);
    if (!s || !t) return sub == sup;
    for (const sw_class_metadata *c = s; c; c = c->superclass)
        if ((const void *)c == t) return 1;
    return 0;
}

/* Checks generic requirements against an environment. Witness tables of
 * the key protocol requirements are appended to key_out (if given). */
int sw_check_requirements(const sw_generic_requirement *reqs, unsigned n, const struct sw_env *e,
                          const void **key_out, unsigned *nkey) {
    for (unsigned i = 0; i < n; i++) {
        const sw_generic_requirement *r = &reqs[i];
        unsigned kind = r->flags & 0x1F;
        if (r->flags & 0x60) continue; /* packs and values: not supported, assume satisfied */
        if (kind == SW_REQ_SAME_CONFORMANCE || kind == SW_REQ_SAME_SHAPE || kind == SW_REQ_INVERTED_PROTOCOLS)
            continue;
        const char *pname = sw_rel(&r->param);
        const sw_metadata *subject = pname ? sw_type_in_env(pname, sw_mangled_name_length(pname), e) : NULL;
        if (!subject) return -1;
        switch (kind) {
        case SW_REQ_PROTOCOL: {
            int32_t off = r->content;
            const char *p = (const char *)&r->content + (off & ~3);
            if (off & 1) p = *(const char *const *)p;
            if (off & 2) {
                /* Objective-C protocol: only classes can conform. */
                RT(int (*)(const void *, const void *), conforms, "_class_conformsToProtocol");
                const void *cls = sw_class_of_metadata(subject);
                if (!cls || !conforms || !conforms(cls, p)) return -1;
                break;
            }
            const sw_witness_table *wt = sw_conforms_to(subject, (const sw_protocol_descriptor *)p);
            if (!wt) return -1;
            if ((r->flags & SW_GP_HAS_KEY_ARGUMENT) && key_out) key_out[(*nkey)++] = wt;
            break;
        }
        case SW_REQ_SAME_TYPE: {
            const char *other = sw_rel(&r->content);
            const sw_metadata *o = other ? sw_type_in_env(other, sw_mangled_name_length(other), e) : NULL;
            if (o != subject) return -1;
            break;
        }
        case SW_REQ_BASE_CLASS: {
            const char *other = sw_rel(&r->content);
            const sw_metadata *o = other ? sw_type_in_env(other, sw_mangled_name_length(other), e) : NULL;
            if (!o || !sw_is_subclass(subject, o)) return -1;
            break;
        }
        case SW_REQ_LAYOUT:
            if (r->content == 0 && !is_class_metadata(subject)) return -1; /* 0: class layout */
            break;
        }
    }
    return 0;
}

/* Metadata of a nominal type descriptor applied to its generic arguments
 * (flat: every parameter of every level, outermost first). */
static const sw_metadata *instantiate(struct resolver *R, const struct node *at,
                                      const sw_type_context_descriptor *d, const sw_metadata *const *flat,
                                      unsigned nflat) {
    const void *access = sw_rel(&d->access_function);
    const sw_generic_context_header *h = sw_generic_header((const sw_context_descriptor *)d);
    if (!h) {
        if (nflat) return rfail(R, at, "generic arguments for a non-generic type");
        if (!access) return rfail(R, at, "type has no metadata accessor");
        /* A non-generic type's accessor takes just the request. */
        return ((sw_response(*)(sw_request))access)(0).value;
    }
    if (nflat != h->num_params) return rfail(R, at, "wrong number of generic arguments");
    struct sw_env e;
    sw_env_init(&e, (const sw_context_descriptor *)d, NULL);
    e.flat = flat;
    const void **key = alloca((h->num_key_arguments + 1) * sizeof *key);
    unsigned nk = 0;
    for (unsigned i = 0; i < h->num_params; i++)
        if (e.params[i] & SW_GP_HAS_KEY_ARGUMENT) key[nk++] = flat[i];
    if (sw_check_requirements(e.reqs, e.nreqs, &e, key, &nk))
        return rfail(R, at, "generic arguments do not satisfy the type's requirements");
    if (nk != h->num_key_arguments) return rfail(R, at, "unsupported generic signature");
    const sw_metadata *m = sw_get_generic_metadata(d, key);
    return m ? m : rfail(R, at, "generic metadata could not be instantiated");
}

static const sw_type_context_descriptor *nominal_descriptor(struct resolver *R, const struct node *n,
                                                            const sw_metadata **direct) {
    *direct = NULL;
    if (n->kind == NK_CTX) return n->ptr;
    struct sbuf b = {.key = 1};
    char sym[64];
    if (n->kind == NK_STD) {
        const struct stdtype *s = std_lookup(n);
        snprintf(sym, sizeof sym, "_$sS%s%cN", n->a ? "c" : "", n->sub);
        *direct = rt(sym);
        if (*direct) return NULL;
        snprintf(sym, sizeof sym, "_$sS%s%cMn", n->a ? "c" : "", n->sub);
        const void *d = rt(sym);
        if (!d) rfail(R, n, s->kind == 'P' ? "standard library protocol not available"
                                           : "standard library type not available");
        return d;
    }
    if (n->kind != NK_NOMINAL) return rfail(R, n, "not a nominal type"), NULL;
    const struct node *ctx = n->kids[0];
    if (ctx->kind == NK_MODULE && !strcmp(ctx->text, "__C") && n->sub == 'C') {
        /* An Objective-C class, by name. */
        RT(const void *(*)(const char *), getclass, "_objc_getClass");
        RT(const sw_metadata *(*)(const void *), wrap, "_swift_getObjCClassMetadata");
        const void *cls = getclass ? getclass(n->kids[1]->text) : NULL;
        if (!cls) return rfail(R, n, "no such Objective-C class"), NULL;
        *direct = wrap ? wrap(cls) : cls;
        return NULL;
    }
    print_node(&b, n);
    unsigned kind = n->sub == 'C' ? SW_CTX_CLASS : n->sub == 'O' ? SW_CTX_ENUM : SW_CTX_STRUCT;
    const sw_context_descriptor *d = find_by_name(sb_take(&b), kind);
    free(b.s);
    if (!d) rfail(R, n, n->sub == 'a' ? "type aliases are not supported" : "no type with this name is loaded");
    return (const sw_type_context_descriptor *)d;
}

static proto_ref resolve_proto(struct resolver *R, const struct node *n) {
    switch (n->kind) {
    case NK_CTX: return (proto_ref)n->ptr;
    case NK_OBJC_PROTO: return (proto_ref)n->ptr | PROTO_OBJC;
    case NK_STD: {
        char sym[64];
        snprintf(sym, sizeof sym, "_$sS%s%cMp", n->a ? "c" : "", n->sub);
        const void *p = rt(sym);
        if (!p) rfail(R, n, "standard library protocol not available");
        return (proto_ref)p;
    }
    case NK_NOMINAL: {
        if (n->kids[0]->kind == NK_MODULE && !strcmp(n->kids[0]->text, "__C")) {
            RT(const void *(*)(const char *), getproto, "_objc_getProtocol");
            const void *p = getproto ? getproto(n->kids[1]->text) : NULL;
            if (!p) rfail(R, n, "no such Objective-C protocol");
            return p ? (proto_ref)p | PROTO_OBJC : 0;
        }
        struct sbuf b = {.key = 1};
        print_node(&b, n);
        const void *p = find_by_name(sb_take(&b), SW_CTX_PROTOCOL);
        free(b.s);
        if (!p) rfail(R, n, "no protocol with this name is loaded");
        return (proto_ref)p;
    }
    default: rfail(R, n, "not a protocol"); return 0;
    }
}

/* Witness table for `type` (the value of generic parameter `base`, when it
 * is one) conforming to `proto`: from the environment's own requirements if
 * it has them (they are what the caller passed), else by lookup. */
static const sw_witness_table *env_conformance(const struct sw_env *e, const struct node *base,
                                               const sw_metadata *type, const sw_protocol_descriptor *proto) {
    if (e->self_wt && base->kind == NK_GPARAM && base->a == 0 && base->b == 0 &&
        sw_rel_indirect(&e->self_wt->description->protocol) == proto)
        return e->self_wt;
    if (base->kind == NK_GPARAM && e->args && e->reqs) {
        unsigned k = key_param_count(e);
        for (unsigned i = 0; i < e->nreqs; i++) {
            const sw_generic_requirement *r = &e->reqs[i];
            if ((r->flags & 0x1F) != SW_REQ_PROTOCOL || !(r->flags & SW_GP_HAS_KEY_ARGUMENT)) continue;
            const void *p = (const char *)&r->content + (r->content & ~3);
            if (r->content & 1) p = *(const void *const *)p;
            const char *pn = sw_rel(&r->param);
            if (p == proto && pn && pn[0] == 'x' && pn[1] == 0 && base->a == 0 && base->b == 0) return e->args[k];
            if (p == proto && pn) {
                struct arena ar = {0};
                struct parser P;
                const struct node *g = parse(&P, &ar, pn, sw_mangled_name_length(pn));
                int same = g && g->kind == NK_GPARAM && g->a == base->a && g->b == base->b;
                arena_free(&ar);
                if (same) return e->args[k];
            }
            k++;
        }
    }
    return sw_conforms_to(type, proto);
}

static const sw_metadata *resolve_depmember(struct resolver *R, const struct node *n) {
    const struct node *base = n->kids[0];
    const sw_metadata *bt = resolve(R, base);
    if (!bt) return NULL;
    const char *name = n->kids[1]->text;
    const sw_protocol_descriptor *proto = NULL;
    if (n->nkids > 2) {
        proto_ref p = resolve_proto(R, n->kids[2]);
        if (!p || (p & PROTO_OBJC)) return rfail(R, n, "bad protocol for an associated type");
        proto = (const sw_protocol_descriptor *)p;
    } else if (R->env->reqs) {
        /* No protocol written: the base's requirements say which one has an
         * associated type of this name. */
        for (unsigned i = 0; i < R->env->nreqs && !proto; i++) {
            const sw_generic_requirement *r = &R->env->reqs[i];
            if ((r->flags & 0x1F) != SW_REQ_PROTOCOL || (r->content & 2)) continue;
            const void *p = (const char *)&r->content + (r->content & ~3);
            if (r->content & 1) p = *(const void *const *)p;
            if (sw_assoc_type_requirement(p, name)) proto = p;
        }
    }
    if (!proto) return rfail(R, n, "cannot tell which protocol declares this associated type");
    const sw_protocol_requirement *req = sw_assoc_type_requirement(proto, name);
    if (!req) return rfail(R, n, "protocol has no associated type with this name");
    const sw_witness_table *wt = env_conformance(R->env, base, bt, proto);
    if (!wt) return rfail(R, n, "base type does not conform to the protocol");
    const sw_metadata *m = sw_get_assoc_type_witness(wt, bt, sw_protocol_requirements(proto) - 1, req);
    if (!m) return rfail(R, n, "associated type witness could not be resolved");
    return m;
}

static const sw_metadata *resolve_tuple(struct resolver *R, const struct node *n) {
    if (n->nkids == 1 && !n->kids[0]->text) return resolve(R, n->kids[0]->kids[0]);
    const sw_metadata **el = alloca((n->nkids + 1) * sizeof *el);
    struct sbuf labels = {0};
    int any_label = 0;
    for (unsigned i = 0; i < n->nkids; i++) {
        if (!(el[i] = resolve(R, n->kids[i]->kids[0]))) return NULL;
        if (n->kids[i]->text) {
            sb_puts(&labels, n->kids[i]->text);
            any_label = 1;
        }
        sb_puts(&labels, " ");
    }
    /* The labels string is kept: tuple metadata refers to it forever. */
    const sw_metadata *m = sw_get_tuple_metadata(n->nkids, el, any_label ? sb_take(&labels) : NULL);
    if (!any_label) free(labels.s);
    return m;
}

static const sw_metadata *resolve_function(struct resolver *R, const struct node *n) {
    RT(const sw_metadata *(*)(uintptr_t, const sw_metadata *const *, const uint32_t *, const sw_metadata *),
       getfn, "_swift_getFunctionTypeMetadata");
    RT(const sw_metadata *(*)(uintptr_t, uintptr_t, const sw_metadata *const *, const uint32_t *,
                              const sw_metadata *, const sw_metadata *),
       getfn_actor, "_swift_getFunctionTypeMetadataGlobalActor");
    const sw_metadata *result = resolve(R, n->kids[0]);
    if (!result) return NULL;
    const struct node *params = n->kids[1];
    const struct node *const *ps = &params;
    unsigned np = 1;
    if (params->kind == NK_TUPLE) {
        ps = (const struct node *const *)params->kids;
        np = params->nkids;
    }
    const sw_metadata **pm = alloca((np + 1) * sizeof *pm);
    uint32_t *pf = alloca((np + 1) * sizeof *pf);
    int any_flags = 0;
    for (unsigned i = 0; i < np; i++) {
        const struct node *p = ps[i];
        pf[i] = 0;
        if (p->kind == NK_ELEM) {
            if (p->a) pf[i] |= 0x80; /* variadic */
            p = p->kids[0];
        }
        while (p->kind == NK_PARAMFLAG) {
            pf[i] |= p->a;
            p = p->kids[0];
        }
        if (pf[i]) any_flags = 1;
        if (!(pm[i] = resolve(R, p))) return NULL;
    }
    uintptr_t flags = np;
    switch (n->sub) {
    case FN_BLOCK: flags |= 1u << SW_FN_CONVENTION_SHIFT; break;
    case FN_THIN: flags |= 2u << SW_FN_CONVENTION_SHIFT; break;
    case FN_C: flags |= 3u << SW_FN_CONVENTION_SHIFT; break;
    }
    if (n->sub == FN_SWIFT || n->sub == FN_AUTOCLOSURE || n->sub == FN_BLOCK) flags |= SW_FN_ESCAPING;
    if (n->a & FL_THROWS) flags |= SW_FN_THROWS;
    if (n->a & FL_ASYNC) flags |= SW_FN_ASYNC;
    if (n->a & FL_SENDABLE) flags |= SW_FN_SENDABLE;
    if (any_flags) flags |= SW_FN_PARAM_FLAGS;
    if (n->a & FL_TYPED_THROWS) return rfail(R, n, "typed throws function types are not supported yet");
    if (n->a & FL_GLOBAL_ACTOR) {
        const sw_metadata *actor = NULL;
        for (unsigned i = 2; i < n->nkids; i++)
            if (n->kids[i]->a == FL_GLOBAL_ACTOR && !(actor = resolve(R, n->kids[i]->kids[0]))) return NULL;
        if (!getfn_actor) return rfail(R, n, "function type metadata is not available yet");
        return getfn_actor(flags | SW_FN_GLOBAL_ACTOR, 0, pm, any_flags ? pf : NULL, result, actor);
    }
    if (!getfn) return rfail(R, n, "function type metadata is not available yet");
    return getfn(flags, pm, any_flags ? pf : NULL, result);
}

static const sw_metadata *resolve_existential(struct resolver *R, const struct node *n) {
    RT(const sw_metadata *(*)(uintptr_t, const sw_metadata *, size_t, const proto_ref *), getex,
       "_swift_getExistentialTypeMetadata");
    const sw_metadata *super = NULL;
    unsigned first = n->b ? 1 : 0, np = n->nkids - first;
    int class_bound = n->a;
    if (n->b && !(super = resolve(R, n->kids[0]))) return NULL;
    proto_ref *ps = alloca((np + 1) * sizeof *ps);
    for (unsigned i = 0; i < np; i++) {
        if (!(ps[i] = resolve_proto(R, n->kids[first + i]))) return NULL;
        if (ps[i] & PROTO_OBJC) class_bound = 1;
        /* Protocol flags bit 16: set when any type may conform; clear when
         * the protocol is class-bound. */
        else if (!(((const sw_protocol_descriptor *)ps[i])->flags & 0x10000)) class_bound = 1;
    }
    if (!getex) return rfail(R, n, "existential metadata is not available yet");
    /* ProtocolClassConstraint: 0 = class, 1 = any. */
    return getex(class_bound ? 0 : 1, super, np, ps);
}

static const sw_metadata *resolve_opaque(struct resolver *R, const struct node *n);

static const sw_metadata *resolve(struct resolver *R, const struct node *n) {
    switch (n->kind) {
    case NK_CTX: case NK_NOMINAL: case NK_STD: {
        const sw_metadata *direct;
        const sw_type_context_descriptor *d = nominal_descriptor(R, n, &direct);
        if (direct) return direct;
        return d ? instantiate(R, n, d, NULL, 0) : NULL;
    }
    case NK_BOUND: {
        const sw_metadata *direct;
        const sw_type_context_descriptor *d = nominal_descriptor(R, n->kids[0], &direct);
        if (!d) return direct ? rfail(R, n, "generic arguments for a non-generic type") : NULL;
        unsigned na = 0;
        for (unsigned i = 1; i < n->nkids; i++) na += n->kids[i]->nkids;
        const sw_metadata **args = alloca((na + 1) * sizeof *args);
        na = 0;
        for (unsigned i = 1; i < n->nkids; i++)
            for (unsigned j = 0; j < n->kids[i]->nkids; j++)
                if (!(args[na++] = resolve(R, n->kids[i]->kids[j]))) return NULL;
        return instantiate(R, n, d, args, na);
    }
    case NK_ACCESSOR:
        /* An accessor function stands for types the mangling cannot name
         * (e.g. ones involving local declarations); it takes the context's
         * generic arguments. */
        return ((const sw_metadata *(*)(const void *const *))n->ptr)(R->env->args);
    case NK_TUPLE: return resolve_tuple(R, n);
    case NK_FUNC: return resolve_function(R, n);
    case NK_PARAMFLAG: case NK_STORAGE: return resolve(R, n->kids[0]);
    case NK_METATYPE: {
        const sw_metadata *t = resolve(R, n->kids[0]);
        if (!t) return NULL;
        return sw_get_metatype_metadata(t);
    }
    case NK_EXIST_METATYPE: {
        RT(const sw_metadata *(*)(const sw_metadata *), getexm, "_swift_getExistentialMetatypeMetadata");
        const sw_metadata *t = resolve(R, n->kids[0]);
        if (!t) return NULL;
        if (sw_kind(t) != SW_KIND_EXISTENTIAL && sw_kind(t) != SW_KIND_EXISTENTIAL_METATYPE) {
            /* `T.Type` written with Xp for a concrete type is a plain metatype. */
            return sw_get_metatype_metadata(t);
        }
        if (!getexm) return rfail(R, n, "existential metatype metadata is not available yet");
        return getexm(t);
    }
    case NK_EXIST: return resolve_existential(R, n);
    case NK_GPARAM: {
        const sw_metadata *m = env_param(R->env, n->a, n->b);
        return m ? m : rfail(R, n, "generic parameter has no value in this context");
    }
    case NK_DEPMEMBER: return resolve_depmember(R, n);
    case NK_BUILTIN: {
        char sym[48];
        snprintf(sym, sizeof sym, "_$sB%sN", n->text);
        /* $sB...N names the full metadata {value witnesses, kind}; the
         * metadata itself (address point) is the word after it, which is
         * also how compiled code refers to it. */
        const char *full = rt(sym);
        return full ? (const sw_metadata *)(full + sizeof(void *))
                    : rfail(R, n, "builtin type metadata is not available");
    }
    case NK_OPAQUE: return resolve_opaque(R, n);
    default: return rfail(R, n, "not a type");
    }
}

/* Underlying type #index of an opaque type descriptor ("some P"), resolved
 * in the environment of the opaque type's generic signature. */
static const char *opaque_underlying(const sw_context_descriptor *d, unsigned index) {
    unsigned count = sw_ctx_kind_flags(d->flags);
    if (index >= count) return NULL;
    const sw_generic_context_header *h = sw_generic_header(d);
    const int32_t *names = h ? (const int32_t *)(header_reqs(h) + h->num_requirements)
                             : (const int32_t *)((const char *)d + 8);
    return sw_rel(&names[index]);
}

static const sw_metadata *resolve_opaque(struct resolver *R, const struct node *n) {
    const sw_context_descriptor *d = n->kids[0]->ptr;
    const char *name = opaque_underlying(d, n->a);
    if (!name) return rfail(R, n, "opaque type has no such underlying type");
    unsigned na = n->nkids - 1;
    const sw_metadata **args = alloca((na + 1) * sizeof *args);
    for (unsigned i = 0; i < na; i++)
        if (!(args[i] = resolve(R, n->kids[i + 1]))) return NULL;
    struct sw_env e;
    sw_env_init(&e, d, NULL);
    e.flat = args;
    if (na != e.nparams) return rfail(R, n, "wrong number of arguments for an opaque type");
    const sw_metadata *m = sw_type_in_env(name, sw_mangled_name_length(name), &e);
    return m ? m : rfail(R, n, "underlying type of an opaque type could not be resolved");
}

static void report(const char *name, size_t len, const struct node *root, struct resolver *R,
                   const char *parse_err) {
    if (!dx_verbose) return;
    struct sbuf b = {0};
    if (root) print_node(&b, root);
    else {
        /* Show the raw name with symbolic references elided. */
        for (size_t i = 0; i < len; i++) {
            unsigned char c = name[i];
            if (c >= 1 && c <= 0x17) {
                sb_puts(&b, "<ref>");
                i += 4;
            } else if (c >= 0x20 && c < 0x7f) sb_putn(&b, (const char *)&c, 1);
        }
    }
    struct sbuf w = {0};
    if (R && R->what && R->what != root) print_node(&w, R->what);
    dx_log(1, "swift: cannot resolve type %s: %s%s%s%s", sb_take(&b), parse_err ? parse_err : R->why,
           w.s ? " (" : "", w.s ? w.s : "", w.s ? ")" : "");
    free(b.s);
    free(w.s);
}

const sw_metadata *sw_type_in_env(const char *name, size_t len, const struct sw_env *e) {
    struct arena ar = {0};
    struct parser P;
    const struct node *n = parse(&P, &ar, name, len);
    const sw_metadata *m = NULL;
    struct resolver R = {.env = e};
    if (!n) report(name, len, NULL, NULL, P.err);
    else if (!(m = resolve(&R, n))) report(name, len, n, &R, NULL);
    arena_free(&ar);
    return m;
}

const sw_metadata *sw_type_by_mangled_name(const char *name, size_t len, const sw_context_descriptor *ctx,
                                           const void *const *args) {
    struct sw_env e;
    sw_env_init(&e, ctx, args);
    return sw_type_in_env(name, len, &e);
}

/* ---- metadata helpers ----------------------------------------------------------------- */
const sw_type_context_descriptor *sw_type_descriptor(const sw_metadata *m) {
    if (!m) return NULL;
    switch (sw_kind(m)) {
    case SW_KIND_STRUCT: case SW_KIND_ENUM: case SW_KIND_OPTIONAL: case SW_KIND_FOREIGN_CLASS:
    case SW_KIND_FOREIGN_REFERENCE_TYPE:
        return ((const sw_value_metadata *)m)->description;
    case SW_KIND_CLASS: {
        const sw_class_metadata *c = (const sw_class_metadata *)m;
        return sw_class_is_swift(c) ? (const sw_type_context_descriptor *)c->description : NULL;
    }
    default: return NULL;
    }
}

const void *const *sw_generic_args(const sw_metadata *m) {
    const sw_type_context_descriptor *d = sw_type_descriptor(m);
    if (!d || !sw_ctx_is_generic(d->flags)) return NULL;
    if (sw_kind(m) != SW_KIND_CLASS) return (const void *const *)m + 2;
    const sw_class_descriptor *cd = (const sw_class_descriptor *)d;
    if (sw_ctx_kind_flags(d->flags) & SW_CLASS_HAS_RESILIENT_SUPERCLASS) {
        /* The bounds are computed when the class's metadata is first set up. */
        const intptr_t *bounds = sw_rel((const int32_t *)&cd->metadata_negative_size_in_words);
        if (!bounds || !bounds[0]) return NULL;
        return (const void *const *)((const char *)m + bounds[0]);
    }
    return (const void *const *)m + (cd->metadata_positive_size_in_words - cd->num_immediate_members);
}

/* ---- type names --------------------------------------------------------------------------- */
static void print_metadata(struct sbuf *b, const sw_metadata *m, int qualified);

static void print_desc_name(struct sbuf *b, const sw_context_descriptor *d, int qualified) {
    if (qualified) print_ctx(b, d);
    else {
        const char *n = ctx_name(d);
        sb_puts(b, n ? n : "?");
    }
}
static void print_proto_ref(struct sbuf *b, proto_ref p, int qualified) {
    if (p & PROTO_OBJC) {
        RT(const char *(*)(const void *), getname, "_protocol_getName");
        sb_puts(b, getname ? getname((const void *)(p & ~(proto_ref)1)) : "?");
    } else {
        print_desc_name(b, (const sw_context_descriptor *)p, qualified);
    }
}
/* Generic parameters of a context that are its own (not its parents'). */
static unsigned inherited_params(const sw_context_descriptor *c) {
    for (const sw_context_descriptor *p = ctx_parent(c); p; p = ctx_parent(p)) {
        const sw_generic_context_header *h = sw_generic_header(p);
        if (h) return h->num_params;
    }
    return 0;
}
static void print_metadata(struct sbuf *b, const sw_metadata *m, int qualified);
/* "Outer<A>.Inner<B>": each enclosing type with the arguments of its own
 * generic parameters, taken from the innermost type's key arguments.
 * Unqualified names are just the innermost type with its arguments. */
static void print_generic_ctx(struct sbuf *b, const sw_context_descriptor *c, const void *const *args,
                              int qualified, int innermost) {
    unsigned k = sw_ctx_kind(c->flags);
    const sw_context_descriptor *parent = ctx_parent(c);
    if (k == SW_CTX_ANONYMOUS) {
        if (parent) print_generic_ctx(b, parent, args, qualified, 0);
        return;
    }
    if (k == SW_CTX_MODULE) {
        if (qualified) sb_puts(b, ctx_name(c));
        return;
    }
    if (k == SW_CTX_EXTENSION) {
        print_ctx(b, c); /* the extended type */
    } else {
        if (qualified && parent) {
            size_t before = b->n;
            print_generic_ctx(b, parent, args, qualified, 0);
            if (b->n != before) sb_puts(b, ".");
        }
        const char *name = ctx_name(c);
        sb_puts(b, name ? name : "?");
    }
    const sw_generic_context_header *h = sw_generic_header(c);
    if (!h || !args || (!qualified && !innermost)) return;
    const uint8_t *params = (const uint8_t *)(h + 1);
    unsigned from = inherited_params(c), key = 0, printed = 0;
    for (unsigned i = 0; i < h->num_params; i++) {
        if (!(params[i] & SW_GP_HAS_KEY_ARGUMENT)) continue;
        if (i >= from) {
            sb_puts(b, printed++ ? ", " : "<");
            print_metadata(b, args[key], qualified);
        }
        key++;
    }
    if (printed) sb_puts(b, ">");
}

static const char *const builtin_syms[] = {"i1_", "i8_", "i16_", "i32_", "i64_", "i128_", "i256_", "i512_",
                                           "f16_", "f32_", "f64_", "f80_", "f128_", "o", "O", "b", "p", "w",
                                           "B", "D", "c", "e", "j", "I", NULL};

static void print_metadata(struct sbuf *b, const sw_metadata *m, int qualified) {
    if (!m) {
        sb_puts(b, "<null>");
        return;
    }
    switch (sw_kind(m)) {
    case SW_KIND_CLASS: {
        const sw_class_metadata *c = (const sw_class_metadata *)m;
        if (!sw_class_is_swift(c)) {
            RT(const char *(*)(const void *), cname, "_class_getName");
            sb_puts(b, cname ? cname(c) : "?");
            return;
        }
    } /* fall through */
    case SW_KIND_STRUCT: case SW_KIND_ENUM: case SW_KIND_OPTIONAL: case SW_KIND_FOREIGN_CLASS:
    case SW_KIND_FOREIGN_REFERENCE_TYPE: {
        const sw_type_context_descriptor *d = sw_type_descriptor(m);
        if (!d) {
            sb_puts(b, "<unknown type>");
            return;
        }
        print_generic_ctx(b, (const sw_context_descriptor *)d, sw_generic_args(m), qualified, 1);
        return;
    }
    case SW_KIND_OBJC_CLASS_WRAPPER: {
        RT(const char *(*)(const void *), cname, "_class_getName");
        sb_puts(b, cname ? cname(((const sw_objc_wrapper_metadata *)m)->cls) : "?");
        return;
    }
    case SW_KIND_TUPLE: {
        const sw_tuple_metadata *t = (const sw_tuple_metadata *)m;
        const char *labels = t->labels;
        sb_puts(b, "(");
        for (size_t i = 0; i < t->num_elements; i++) {
            if (i) sb_puts(b, ", ");
            if (labels) {
                const char *sp = strchr(labels, ' ');
                if (sp && sp != labels) {
                    sb_putn(b, labels, sp - labels);
                    sb_puts(b, ": ");
                }
                labels = sp ? sp + 1 : NULL;
            }
            print_metadata(b, t->elements[i].type, qualified);
        }
        sb_puts(b, ")");
        return;
    }
    case SW_KIND_FUNCTION: {
        const sw_function_metadata *f = (const sw_function_metadata *)m;
        unsigned np = f->flags & SW_FN_NUM_PARAMS_MASK;
        unsigned conv = (f->flags & SW_FN_CONVENTION_MASK) >> SW_FN_CONVENTION_SHIFT;
        const uint32_t *pf = (f->flags & SW_FN_PARAM_FLAGS) ? (const uint32_t *)(f->params + np) : NULL;
        if (f->flags & SW_FN_SENDABLE) sb_puts(b, "@Sendable ");
        if (conv == 1) sb_puts(b, "@convention(block) ");
        else if (conv == 2) sb_puts(b, "@convention(thin) ");
        else if (conv == 3) sb_puts(b, "@convention(c) ");
        sb_puts(b, "(");
        for (unsigned i = 0; i < np; i++) {
            if (i) sb_puts(b, ", ");
            if (pf && (pf[i] & 0x7F) == 1) sb_puts(b, "inout ");
            print_metadata(b, f->params[i], qualified);
            if (pf && (pf[i] & 0x80)) sb_puts(b, "...");
        }
        sb_puts(b, ")");
        if (f->flags & SW_FN_ASYNC) sb_puts(b, " async");
        if (f->flags & SW_FN_THROWS) sb_puts(b, " throws");
        sb_puts(b, " -> ");
        print_metadata(b, f->result, qualified);
        return;
    }
    case SW_KIND_EXISTENTIAL: {
        const sw_existential_metadata *e = (const sw_existential_metadata *)m;
        const void *const *tail = (const void *const *)(e + 1);
        int has_super = (e->flags & 0x40000000) != 0;
        int class_bound = !(e->flags & 0x80000000);
        unsigned count = 0;
        if (has_super) {
            print_metadata(b, tail[0], qualified);
            count++;
        }
        const proto_ref *ps = (const proto_ref *)(tail + has_super);
        for (uint32_t i = 0; i < e->num_protocols; i++, count++) {
            if (count) sb_puts(b, " & ");
            print_proto_ref(b, ps[i], qualified);
        }
        if (class_bound && !has_super && !e->num_protocols) {
            sb_puts(b, qualified ? "Swift.AnyObject" : "AnyObject");
            count++;
        }
        if (!count) sb_puts(b, "Any");
        return;
    }
    case SW_KIND_METATYPE: case SW_KIND_EXISTENTIAL_METATYPE: {
        const sw_metadata *inst = ((const sw_metatype_metadata *)m)->instance_type;
        int paren = inst && sw_kind(inst) == SW_KIND_FUNCTION;
        if (paren) sb_puts(b, "(");
        print_metadata(b, inst, qualified);
        sb_puts(b, paren ? ").Type" : ".Type");
        return;
    }
    case SW_KIND_OPAQUE: {
        char sym[32], tmp[32];
        for (int i = 0; builtin_syms[i]; i++) {
            snprintf(sym, sizeof sym, "_$sB%sN", builtin_syms[i]);
            const char *full = rt(sym);
            if (full && full + sizeof(void *) == (const char *)m) {
                sb_puts(b, "Builtin.");
                sb_puts(b, builtin_name(builtin_syms[i], tmp, sizeof tmp));
                return;
            }
        }
        sb_puts(b, "<builtin type>");
        return;
    }
    default:
        sb_printf(b, "<metadata kind 0x%lx>", (unsigned long)sw_kind(m));
    }
}

static pthread_mutex_t names_lock = PTHREAD_MUTEX_INITIALIZER;
static struct sw_map names;

const char *sw_type_name(const sw_metadata *m, int qualified) {
    pthread_mutex_lock(&names_lock);
    const char *s = sw_map_get(&names, (uintptr_t)m, qualified != 0, NULL);
    pthread_mutex_unlock(&names_lock);
    if (s) return s;
    struct sbuf b = {0};
    print_metadata(&b, m, qualified);
    char *name = sb_take(&b);
    pthread_mutex_lock(&names_lock);
    const char *again = sw_map_get(&names, (uintptr_t)m, qualified != 0, NULL);
    if (again) {
        free(name);
        s = again;
    } else {
        sw_map_put(&names, (uintptr_t)m, qualified != 0, name);
        s = name;
    }
    pthread_mutex_unlock(&names_lock);
    return s;
}

/* ---- exported entry points ---------------------------------------------------------------- */
/* All of these are SWIFT_CC(swift) without self/error/context registers,
 * which on x86-64 is the C convention. The metadata request state is
 * ignored: everything this runtime hands out is complete. */
static const sw_metadata *d_swift_getTypeByMangledNameInContext(const char *name, size_t len,
                                                                const sw_context_descriptor *ctx,
                                                                const void *const *args) {
    return sw_type_by_mangled_name(name, len, ctx, args);
}
DX_FN(swift_getTypeByMangledNameInContext);
/* The "2" entry points differ only in that they may return noncopyable
 * types; this runtime does not tell those apart. */
DX_EXPORT("_swift_getTypeByMangledNameInContext2", d_swift_getTypeByMangledNameInContext);

static const sw_metadata *d_swift_getTypeByMangledNameInContextInMetadataState(
    size_t state, const char *name, size_t len, const sw_context_descriptor *ctx, const void *const *args) {
    return sw_type_by_mangled_name(name, len, ctx, args);
}
DX_FN(swift_getTypeByMangledNameInContextInMetadataState);
DX_EXPORT("_swift_getTypeByMangledNameInContextInMetadataState2",
          d_swift_getTypeByMangledNameInContextInMetadataState);

/* A GenericEnvironmentDescriptor (closures, key paths): flags (levels in
 * the low 12 bits, requirements in the next 16), cumulative parameter
 * counts per level, parameter descriptors, requirements. */
static void env_from_environment(struct sw_env *e, const uint32_t *genv, const void *const *args) {
    memset(e, 0, sizeof *e);
    e->args = args;
    if (!genv) return;
    unsigned levels = genv[0] & 0xFFF, nreqs = (genv[0] >> 12) & 0xFFFF;
    const uint16_t *counts = (const uint16_t *)(genv + 1);
    for (unsigned i = 0; i < levels && i < sizeof e->levels / sizeof *e->levels; i++)
        e->levels[e->nlevels++] = counts[i];
    e->nparams = levels ? counts[levels - 1] : 0;
    e->params = (const uint8_t *)(counts + levels);
    uintptr_t r = ((uintptr_t)(e->params + e->nparams) + 3) & ~(uintptr_t)3;
    e->nreqs = nreqs;
    e->reqs = (const sw_generic_requirement *)r;
}
static const sw_metadata *d_swift_getTypeByMangledNameInEnvironment(const char *name, size_t len,
                                                                    const uint32_t *genv,
                                                                    const void *const *args) {
    struct sw_env e;
    env_from_environment(&e, genv, args);
    return sw_type_in_env(name, len, &e);
}
DX_FN(swift_getTypeByMangledNameInEnvironment);
DX_EXPORT("_swift_getTypeByMangledNameInEnvironment2", d_swift_getTypeByMangledNameInEnvironment);
const sw_metadata *sw_type_in_genv(const char *name, const uint32_t *genv, const void *const *args) {
    return d_swift_getTypeByMangledNameInEnvironment(name, sw_mangled_name_length(name), genv, args);
}
unsigned sw_genv_key_count(const uint32_t *genv) {
    struct sw_env e;
    env_from_environment(&e, genv, NULL);
    unsigned n = 0;
    for (unsigned i = 0; i < e.nparams; i++)
        if (e.params[i] & SW_GP_HAS_KEY_ARGUMENT) n++;
    for (unsigned i = 0; i < e.nreqs; i++)
        if (e.reqs[i].flags & 0x80) n++;
    return n;
}
static const sw_metadata *d_swift_getTypeByMangledNameInEnvironmentInMetadataState(
    size_t state, const char *name, size_t len, const uint32_t *genv, const void *const *args) {
    return d_swift_getTypeByMangledNameInEnvironment(name, len, genv, args);
}
DX_FN(swift_getTypeByMangledNameInEnvironmentInMetadataState);
DX_EXPORT("_swift_getTypeByMangledNameInEnvironmentInMetadataState2",
          d_swift_getTypeByMangledNameInEnvironmentInMetadataState);

/* Opaque result types ("some P"): underlying type or conformance #index,
 * given the opaque type's key generic arguments. Conformance entries are
 * mangled as a symbolic reference to a witness table accessor, so both go
 * through the same resolution. */
static sw_response d_swift_getOpaqueTypeMetadata2(sw_request req, const void *const *args,
                                                 const sw_context_descriptor *d, unsigned index) {
    const char *name = opaque_underlying(d, index);
    sw_response r = {NULL, 0};
    if (name) r.value = sw_type_by_mangled_name(name, sw_mangled_name_length(name), d, args);
    return r;
}
DX_FN(swift_getOpaqueTypeMetadata2);
DX_EXPORT("_swift_getOpaqueTypeMetadata", d_swift_getOpaqueTypeMetadata2);
static const sw_witness_table *d_swift_getOpaqueTypeConformance2(const void *const *args,
                                                                const sw_context_descriptor *d,
                                                                unsigned index) {
    return (const sw_witness_table *)d_swift_getOpaqueTypeMetadata2(0, args, d, index).value;
}
DX_FN(swift_getOpaqueTypeConformance2);
DX_EXPORT("_swift_getOpaqueTypeConformance", d_swift_getOpaqueTypeConformance2);

/* TypeNamePair swift_getTypeName(const Metadata *, bool qualified):
 * {data, length}, returned in rax:rdx. The string lives forever. */
struct type_name_pair {
    const char *data;
    uintptr_t length;
};
static struct type_name_pair d_swift_getTypeName(const sw_metadata *m, _Bool qualified) {
    const char *s = sw_type_name(m, qualified);
    return (struct type_name_pair){s, strlen(s)};
}
DX_FN(swift_getTypeName);

/* char *swift_demangle(mangled, length, outputBuffer, outputBufferSize,
 * flags): the public demangling entry point. This runtime only knows the
 * type grammar, so it demangles type manglings ($s...D, $s...N metadata,
 * $s...Mn descriptors) and returns NULL for anything else. */
static char *d_swift_demangle(const char *mangled, size_t len, char *out, size_t *outsize, uint32_t flags) {
    if (!mangled || flags) return NULL;
    if (len >= 2 && mangled[0] == '_' && mangled[1] == '$') {
        mangled++;
        len--;
    }
    /* A protocol descriptor symbol names the protocol without its 'P'. */
    static const struct { const char *suffix, *prefix, *append; } kinds[] = {
        {"Mn", "nominal type descriptor for ", ""}, {"Mp", "protocol descriptor for ", "P"},
        {"Mp", "protocol descriptor for ", ""}, {"MD", "demangling cache variable for type metadata for ", ""},
        {"Ma", "type metadata accessor for ", ""}, {"N", "type metadata for ", ""}, {"D", "", ""}, {0, 0, 0}};
    for (int k = 0; kinds[k].suffix; k++) {
        size_t sl = strlen(kinds[k].suffix);
        if (len <= sl + 2 || memcmp(mangled + len - sl, kinds[k].suffix, sl)) continue;
        struct arena ar = {0};
        struct parser P;
        size_t al = strlen(kinds[k].append);
        char *text = arena_alloc(&ar, len - sl + al + 1);
        memcpy(text, mangled, len - sl);
        memcpy(text + len - sl, kinds[k].append, al);
        const struct node *n = parse(&P, &ar, text, len - sl + al);
        if (!n) {
            arena_free(&ar);
            continue;
        }
        struct sbuf b = {0};
        sb_puts(&b, kinds[k].prefix);
        print_node(&b, n);
        arena_free(&ar);
        if (out && outsize) {
            if (b.n + 1 > *outsize) {
                free(b.s);
                return NULL;
            }
            memcpy(out, b.s, b.n + 1);
            *outsize = b.n;
            free(b.s);
            return out;
        }
        return b.s; /* the program's free() is the host's */
    }
    return NULL;
}
DX_FN(swift_demangle);
