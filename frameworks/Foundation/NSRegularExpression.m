/* NSRegularExpression, NSTextCheckingResult and NSDataDetector.
 *
 * The patterns are ICU's syntax (as documented for NSRegularExpression),
 * matched by a backtracking engine over UTF-16 written here:
 *   literals and escapes (\t \n \r \f \a \e \0oo \xhh \x{h..} \uhhhh \Uhhhhhhhh \cX \Q..\E),
 *   . [...] (ranges, negation, nested sets, [:posix:], \d \w \s \h \p{..} inside),
 *   \d \D \w \W \s \S \h \H \R \p{..} \P{..},
 *   ^ $ \A \z \Z \b \B \G,
 *   groups ( ), (?: ), (?<name> ), (?P<name> ), (?'name' ), (?> ), (?= ), (?! ), (?<= ), (?<! ),
 *   inline flags (?imsx-imsx) and (?imsx-imsx: ),
 *   * + ? {n} {n,} {n,m}, lazy (?) and possessive (+) forms,
 *   back references \1.. and \k<name>, and the NSRegularExpression options.
 * Unicode categories follow the same approximations as NSCharacterSet.m.
 * A match that backtracks past a step budget fails, as ICU's time limit
 * would stop it. */
#import "FoundationInternal.h"
#include <stdlib.h>
#include <string.h>

/* ---- character classification ---------------------------------------------------- */

static int u_is_letter(uint32_t c) {
    if (c < 0x80) return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
    if (c < 0xc0) return c == 0xaa || c == 0xb5 || c == 0xba;
    if (c == 0xd7 || c == 0xf7) return 0;
    if (c >= 0x2000 && c <= 0x2bff) return 0;
    if (c >= 0x3000 && c <= 0x303f) return 0;
    if (c >= 0xd800 && c <= 0xf8ff) return 0;
    if (c >= 0xfe00 && c < 0x10000) return c >= 0xff21 && c <= 0xffdc;
    if (c >= 0x1f000 && c <= 0x1faff) return 0; /* emoji and symbols */
    return 1;
}
static int u_is_digit(uint32_t c) {
    return (c >= '0' && c <= '9') || (c >= 0x660 && c <= 0x669) || (c >= 0x6f0 && c <= 0x6f9) ||
           (c >= 0x966 && c <= 0x96f) || (c >= 0xff10 && c <= 0xff19);
}
static int u_is_space(uint32_t c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == 0x0b || c == 0x85 || c == 0xa0 ||
           c == 0x1680 || (c >= 0x2000 && c <= 0x200a) || c == 0x2028 || c == 0x2029 || c == 0x202f || c == 0x205f ||
           c == 0x3000;
}
static int u_is_hspace(uint32_t c) {
    return c == ' ' || c == '\t' || c == 0xa0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200a) || c == 0x202f ||
           c == 0x205f || c == 0x3000;
}
static int u_is_upper(uint32_t c) {
    return (c >= 'A' && c <= 'Z') || (c >= 0xc0 && c <= 0xde && c != 0xd7) || (c >= 0x391 && c <= 0x3a9) ||
           (c >= 0x400 && c <= 0x42f) || (c >= 0x100 && c <= 0x17f && !(c & 1));
}
static int u_is_lower(uint32_t c) {
    return (c >= 'a' && c <= 'z') || (c >= 0xdf && c <= 0xff && c != 0xf7) || (c >= 0x3b1 && c <= 0x3c9) ||
           (c >= 0x430 && c <= 0x45f) || (c >= 0x100 && c <= 0x17f && (c & 1));
}
static int u_is_punct(uint32_t c) {
    return (c >= 0x21 && c <= 0x2f && c != '$' && c != '+') || (c >= 0x3a && c <= 0x40 && c != '<' && c != '=' && c != '>') ||
           (c >= 0x5b && c <= 0x60 && c != '^' && c != '`') || c == '{' || c == '}' || c == 0xa1 || c == 0xa7 ||
           c == 0xab || c == 0xb6 || c == 0xb7 || c == 0xbb || c == 0xbf || (c >= 0x2010 && c <= 0x2027) ||
           (c >= 0x2030 && c <= 0x205e) || (c >= 0x3001 && c <= 0x3003);
}
static int u_is_symbol(uint32_t c) {
    return c == '$' || c == '+' || c == '<' || c == '=' || c == '>' || c == '^' || c == '`' || c == '|' || c == '~' ||
           (c >= 0xa2 && c <= 0xa9 && c != 0xa7) || c == 0xac || (c >= 0xae && c <= 0xb1) || c == 0xb4 || c == 0xd7 ||
           c == 0xf7 || (c >= 0x2100 && c <= 0x2bff) || (c >= 0x1f000 && c <= 0x1faff);
}
static int u_is_mark(uint32_t c) { return (c >= 0x300 && c <= 0x36f) || (c >= 0x1ab0 && c <= 0x1aff) || (c >= 0x20d0 && c <= 0x20ff) || (c >= 0xfe20 && c <= 0xfe2f); }
static int u_is_word(uint32_t c) { return u_is_letter(c) || u_is_digit(c) || u_is_mark(c) || c == '_' || c == 0x200c || c == 0x200d; }
static int u_is_lineterm(uint32_t c, int unix_only) {
    return c == '\n' || (!unix_only && (c == '\r' || c == 0x0b || c == '\f' || c == 0x85 || c == 0x2028 || c == 0x2029));
}
static uint32_t u_fold(uint32_t c) {
    if (c < 0x80) return (c >= 'A' && c <= 'Z') ? c + 32 : c;
    if (c >= 0xc0 && c <= 0xde && c != 0xd7) return c + 32;
    if (c >= 0x391 && c <= 0x3a9 && c != 0x3a2) return c + 32;
    if (c == 0x3c2) return 0x3c3; /* final sigma */
    if (c >= 0x410 && c <= 0x42f) return c + 32;
    if (c >= 0x400 && c <= 0x40f) return c + 80;
    if (c >= 0x100 && c <= 0x17f && c != 0x130 && c != 0x131 && c != 0x138 && c != 0x149 && c != 0x17f) {
        /* Latin Extended-A pairs: even upper, odd lower (shifted after 0x138) */
        if ((c >= 0x139 && c <= 0x148) || (c >= 0x179 && c <= 0x17e)) return (c & 1) ? c + 1 : c;
        return (c & 1) ? c : c + 1;
    }
    if (c >= 0xff21 && c <= 0xff3a) return c + 32;
    return c;
}

/* ---- the program ------------------------------------------------------------------------ */

enum {
    OP_CHAR, OP_ANY, OP_CLASS, OP_ASSERT, OP_SPLIT, OP_JMP, OP_SAVE, OP_BACKREF, OP_LOOK, OP_ATOMIC,
    OP_SUBEND, OP_MARK, OP_PROGRESS, OP_MATCH,
};
enum { A_BOL, A_EOL, A_MBOL, A_MEOL, A_STRBEG, A_STREND, A_STRENDNL, A_WORDB, A_NWORDB, A_SEARCHSTART };
enum { L_AHEAD, L_NAHEAD, L_BEHIND, L_NBEHIND };

typedef struct {
    uint8_t op, flag;     /* flag: case-insensitive, dot-all, look kind, ... */
    int32_t a, b;         /* operands */
} Inst;

/* character sets */
enum { CI_RANGE, CI_DIGIT, CI_WORD, CI_SPACE, CI_HSPACE, CI_LETTER, CI_UPPER, CI_LOWER, CI_PUNCT, CI_SYMBOL,
       CI_MARK, CI_ANY, CI_ASCII, CI_ALNUM, CI_CNTRL, CI_XDIGIT, CI_GRAPH, CI_PRINT, CI_SET };
typedef struct {
    uint8_t kind, neg;
    uint32_t lo, hi;      /* CI_RANGE; CI_SET: lo is a nested set's index */
} ClassItem;
typedef struct {
    ClassItem *items;
    int n, cap;
    int neg, icase;
} CharClass;

/* syntax tree */
enum { N_EMPTY, N_CHAR, N_ANY, N_CLASS, N_ASSERT, N_GROUP, N_CAT, N_ALT, N_REPEAT, N_BACKREF, N_LOOK, N_ATOMIC };
typedef struct Node Node;
struct Node {
    int type;
    uint32_t c;           /* N_CHAR; N_CLASS index; N_ASSERT kind; N_BACKREF group; N_LOOK kind */
    int flag;             /* icase / dotall / unix lines */
    int group;            /* N_GROUP: capture index, or -1 */
    int min, max, greedy, possessive;
    Node **kids;
    int nkids, capkids;
};

typedef struct {
    Inst *code;
    int ncode, capcode;
    CharClass *classes;
    int nclasses, capclasses;
    int ngroups;          /* capture groups, not counting group 0 */
    int ncounters;
    NSMutableArray<NSString *> *names; /* names[i] names group i+1, or @"" */
    int anchored;         /* starts with \A (or ^ outside multi-line mode) */
    int unix_lines;
} Program;

typedef struct {
    const unichar *p;
    int n, i;
    int flags;            /* current i, m, s, x, w flags */
    Program *prog;
    NSString *error;
    Node **all;           /* every node, freed at the end */
    int nall, capall;
} Parser;

#define F_I 1
#define F_M 2
#define F_S 4
#define F_X 8
#define F_UNIX 16

static Node *node_new(Parser *ps, int type) {
    Node *n = calloc(1, sizeof *n);
    n->type = type;
    n->group = -1;
    if (ps->nall == ps->capall) {
        ps->capall = ps->capall ? ps->capall * 2 : 64;
        ps->all = realloc(ps->all, (size_t)ps->capall * sizeof *ps->all);
    }
    ps->all[ps->nall++] = n;
    return n;
}
static void node_add(Node *n, Node *k) {
    if (n->nkids == n->capkids) {
        n->capkids = n->capkids ? n->capkids * 2 : 4;
        n->kids = realloc(n->kids, (size_t)n->capkids * sizeof *n->kids);
    }
    n->kids[n->nkids++] = k;
}
static void parse_free(Parser *ps) {
    for (int i = 0; i < ps->nall; i++) {
        free(ps->all[i]->kids);
        free(ps->all[i]);
    }
    free(ps->all);
}

static int class_new(Program *pg) {
    if (pg->nclasses == pg->capclasses) {
        pg->capclasses = pg->capclasses ? pg->capclasses * 2 : 8;
        pg->classes = realloc(pg->classes, (size_t)pg->capclasses * sizeof *pg->classes);
    }
    memset(&pg->classes[pg->nclasses], 0, sizeof *pg->classes);
    return pg->nclasses++;
}
static void class_add(Program *pg, int ci, int kind, int neg, uint32_t lo, uint32_t hi) {
    CharClass *c = &pg->classes[ci];
    if (c->n == c->cap) {
        c->cap = c->cap ? c->cap * 2 : 8;
        c->items = realloc(c->items, (size_t)c->cap * sizeof *c->items);
    }
    c->items[c->n++] = (ClassItem){(uint8_t)kind, (uint8_t)neg, lo, hi};
}

static int item_matches(const Program *pg, const ClassItem *it, uint32_t c, int icase);
static int class_matches(const Program *pg, int ci, uint32_t c) {
    const CharClass *cl = &pg->classes[ci];
    int in = 0;
    for (int i = 0; i < cl->n && !in; i++) in = item_matches(pg, &cl->items[i], c, cl->icase);
    return in != cl->neg;
}
static int item_matches(const Program *pg, const ClassItem *it, uint32_t c, int icase) {
    int r;
    switch (it->kind) {
    case CI_RANGE:
        r = c >= it->lo && c <= it->hi;
        if (!r && icase) {
            uint32_t f = u_fold(c);
            r = f >= it->lo && f <= it->hi;
            if (!r) /* an upper-case range against a lower-case letter */
                for (uint32_t u = it->lo; u <= it->hi && u - it->lo < 512; u++)
                    if (u_fold(u) == f) { r = 1; break; }
        }
        break;
    case CI_DIGIT: r = u_is_digit(c); break;
    case CI_WORD: r = u_is_word(c); break;
    case CI_SPACE: r = u_is_space(c); break;
    case CI_HSPACE: r = u_is_hspace(c); break;
    case CI_LETTER: r = u_is_letter(c); break;
    case CI_UPPER: r = icase ? u_is_upper(c) || u_is_lower(c) : u_is_upper(c); break;
    case CI_LOWER: r = icase ? u_is_upper(c) || u_is_lower(c) : u_is_lower(c); break;
    case CI_PUNCT: r = u_is_punct(c); break;
    case CI_SYMBOL: r = u_is_symbol(c); break;
    case CI_MARK: r = u_is_mark(c); break;
    case CI_ANY: r = 1; break;
    case CI_ASCII: r = c < 0x80; break;
    case CI_ALNUM: r = u_is_letter(c) || u_is_digit(c); break;
    case CI_CNTRL: r = c < 0x20 || (c >= 0x7f && c <= 0x9f); break;
    case CI_XDIGIT: r = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); break;
    case CI_GRAPH: r = c > 0x20 && c != 0x7f && !u_is_space(c) && !(c >= 0x80 && c <= 0x9f); break;
    case CI_PRINT: r = (c >= 0x20 && c != 0x7f && !(c >= 0x80 && c <= 0x9f)) && (c == ' ' || !u_is_space(c) || u_is_hspace(c)); break;
    case CI_SET: r = class_matches(pg, (int)it->lo, c); break;
    default: r = 0;
    }
    return r != it->neg;
}

/* ---- parsing ------------------------------------------------------------------------------ */

static int peek(Parser *ps) { return ps->i < ps->n ? ps->p[ps->i] : -1; }
static int at_end(Parser *ps) { return ps->i >= ps->n; }
static uint32_t next_cp(Parser *ps) {
    uint32_t c = ps->p[ps->i++];
    if (c >= 0xd800 && c < 0xdc00 && ps->i < ps->n && ps->p[ps->i] >= 0xdc00 && ps->p[ps->i] < 0xe000)
        c = 0x10000 + ((c - 0xd800) << 10) + (ps->p[ps->i++] - 0xdc00);
    return c;
}
static void fail(Parser *ps, NSString *why) {
    if (!ps->error) ps->error = why;
}
static void skip_space(Parser *ps) {
    if (!(ps->flags & F_X)) return;
    for (;;) {
        int c = peek(ps);
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == 0x0b) ps->i++;
        else if (c == '#') {
            while (!at_end(ps) && peek(ps) != '\n') ps->i++;
        } else break;
    }
}
static int hexval(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
static int read_hex(Parser *ps, int count, uint32_t *out) {
    uint32_t v = 0;
    for (int k = 0; k < count; k++) {
        int h = hexval(peek(ps));
        if (h < 0) return 0;
        v = v * 16 + (uint32_t)h;
        ps->i++;
    }
    *out = v;
    return 1;
}

/* A property name (\p{...} or [:name:]) as a class item kind; -1 if unknown. */
static int property_kind(NSString *name, int *neg) {
    NSString *n = [[name lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@""];
    n = [n stringByReplacingOccurrencesOfString:@" " withString:@""];
    if ([n hasPrefix:@"^"]) { *neg = !*neg; n = [n substringFromIndex:1]; }
    if ([n hasPrefix:@"is"] && n.length > 2 && ![n isEqual:@"isolated"]) n = [n substringFromIndex:2];
    if ([n hasPrefix:@"generalcategory="]) n = [n substringFromIndex:16];
    if ([n hasPrefix:@"gc="]) n = [n substringFromIndex:3];
    static NSDictionary<NSString *, NSNumber *> *map;
    if (!map)
        map = @{
            @"l" : @(CI_LETTER), @"letter" : @(CI_LETTER), @"alpha" : @(CI_LETTER), @"alphabetic" : @(CI_LETTER),
            @"lu" : @(CI_UPPER), @"uppercaseletter" : @(CI_UPPER), @"upper" : @(CI_UPPER), @"uppercase" : @(CI_UPPER),
            @"ll" : @(CI_LOWER), @"lowercaseletter" : @(CI_LOWER), @"lower" : @(CI_LOWER), @"lowercase" : @(CI_LOWER),
            @"lt" : @(CI_UPPER), @"lm" : @(CI_LETTER), @"lo" : @(CI_LETTER),
            @"n" : @(CI_DIGIT), @"nd" : @(CI_DIGIT), @"number" : @(CI_DIGIT), @"digit" : @(CI_DIGIT),
            @"decimalnumber" : @(CI_DIGIT),
            @"p" : @(CI_PUNCT), @"punct" : @(CI_PUNCT), @"punctuation" : @(CI_PUNCT), @"pd" : @(CI_PUNCT),
            @"ps" : @(CI_PUNCT), @"pe" : @(CI_PUNCT), @"po" : @(CI_PUNCT), @"pc" : @(CI_PUNCT),
            @"s" : @(CI_SYMBOL), @"symbol" : @(CI_SYMBOL), @"sm" : @(CI_SYMBOL), @"sc" : @(CI_SYMBOL),
            @"sk" : @(CI_SYMBOL), @"so" : @(CI_SYMBOL),
            @"m" : @(CI_MARK), @"mark" : @(CI_MARK), @"mn" : @(CI_MARK), @"mc" : @(CI_MARK), @"me" : @(CI_MARK),
            @"z" : @(CI_SPACE), @"zs" : @(CI_HSPACE), @"separator" : @(CI_SPACE), @"space" : @(CI_SPACE),
            @"whitespace" : @(CI_SPACE), @"blank" : @(CI_HSPACE),
            @"any" : @(CI_ANY), @"ascii" : @(CI_ASCII), @"alnum" : @(CI_ALNUM), @"cntrl" : @(CI_CNTRL),
            @"cc" : @(CI_CNTRL), @"control" : @(CI_CNTRL), @"xdigit" : @(CI_XDIGIT), @"hexdigit" : @(CI_XDIGIT),
            @"graph" : @(CI_GRAPH), @"print" : @(CI_PRINT), @"word" : @(CI_WORD),
        };
    NSNumber *k = map[n];
    return k ? k.intValue : -1;
}

/* An escape that stands for one character (after the backslash); -1 if it
 * is not one. */
static int64_t escape_char(Parser *ps, int c) {
    uint32_t v;
    switch (c) {
    case 't': return '\t';
    case 'n': return '\n';
    case 'r': return '\r';
    case 'f': return '\f';
    case 'a': return 7;
    case 'e': return 27;
    case 'x':
        if (peek(ps) == '{') {
            ps->i++;
            v = 0;
            int k = 0;
            while (hexval(peek(ps)) >= 0 && k < 8) { v = v * 16 + (uint32_t)hexval(peek(ps)); ps->i++; k++; }
            if (peek(ps) != '}' || !k || v > 0x10ffff) { fail(ps, @"bad \\x{...} escape"); return 0; }
            ps->i++;
            return v;
        }
        if (!read_hex(ps, 2, &v)) { fail(ps, @"bad \\x escape"); return 0; }
        return v;
    case 'u':
        if (!read_hex(ps, 4, &v)) { fail(ps, @"bad \\u escape"); return 0; }
        return v;
    case 'U':
        if (!read_hex(ps, 8, &v) || v > 0x10ffff) { fail(ps, @"bad \\U escape"); return 0; }
        return v;
    case 'c':
        if (at_end(ps)) { fail(ps, @"bad \\c escape"); return 0; }
        return ps->p[ps->i++] & 0x1f;
    case '0': {
        v = 0;
        for (int k = 0; k < 3 && peek(ps) >= '0' && peek(ps) <= '7'; k++) v = v * 8 + (uint32_t)(ps->p[ps->i++] - '0');
        return v;
    }
    }
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return -1;
    return c; /* an escaped symbol stands for itself */
}

/* \d \w \s \h \p{..} and their negations, as a class item; returns 0 if c
 * is not one of them. */
static int escape_class(Parser *ps, int c, int *kind, int *neg) {
    *neg = 0;
    switch (c) {
    case 'd': *kind = CI_DIGIT; return 1;
    case 'D': *kind = CI_DIGIT; *neg = 1; return 1;
    case 'w': *kind = CI_WORD; return 1;
    case 'W': *kind = CI_WORD; *neg = 1; return 1;
    case 's': *kind = CI_SPACE; return 1;
    case 'S': *kind = CI_SPACE; *neg = 1; return 1;
    case 'h': *kind = CI_HSPACE; return 1;
    case 'H': *kind = CI_HSPACE; *neg = 1; return 1;
    case 'p': case 'P': {
        *neg = c == 'P';
        NSString *name;
        if (peek(ps) == '{') {
            int start = ++ps->i;
            while (!at_end(ps) && peek(ps) != '}') ps->i++;
            if (at_end(ps)) { fail(ps, @"unterminated \\p{"); return 1; }
            name = [NSString stringWithCharacters:ps->p + start length:(NSUInteger)(ps->i - start)];
            ps->i++;
        } else if (!at_end(ps)) {
            name = [NSString stringWithCharacters:ps->p + ps->i length:1];
            ps->i++;
        } else {
            fail(ps, @"bad \\p");
            return 1;
        }
        *kind = property_kind(name, neg);
        if (*kind < 0) fail(ps, [NSString stringWithFormat:@"unknown property %@", name]);
        return 1;
    }
    }
    return 0;
}

static int parse_set(Parser *ps); /* returns the class index, after '[' */
static int parse_set(Parser *ps) {
    Program *pg = ps->prog;
    int ci = class_new(pg);
    pg->classes[ci].icase = (ps->flags & F_I) != 0;
    if (peek(ps) == '^') { pg->classes[ci].neg = 1; ps->i++; }
    int first = 1;
    for (;;) {
        if (at_end(ps)) { fail(ps, @"missing ]"); return ci; }
        int c = peek(ps);
        if (c == ']' && !first) { ps->i++; break; }
        first = 0;
        if (c == '[') {
            if (ps->i + 1 < ps->n && ps->p[ps->i + 1] == ':') { /* [:name:] */
                int start = ps->i + 2, j = start;
                while (j + 1 < ps->n && !(ps->p[j] == ':' && ps->p[j + 1] == ']')) j++;
                if (j + 1 < ps->n) {
                    NSString *name = [NSString stringWithCharacters:ps->p + start length:(NSUInteger)(j - start)];
                    int neg = 0, kind = property_kind(name, &neg);
                    if (kind < 0) { fail(ps, @"unknown [:class:]"); return ci; }
                    class_add(pg, ci, kind, neg, 0, 0);
                    ps->i = j + 2;
                    continue;
                }
            }
            ps->i++;
            int sub = parse_set(ps);
            /* parse_set may have moved the array */
            class_add(pg, ci, CI_SET, 0, (uint32_t)sub, 0);
            continue;
        }
        if (c == '&' && ps->i + 1 < ps->n && ps->p[ps->i + 1] == '&') { fail(ps, @"set intersection is not supported"); return ci; }
        uint32_t lo;
        if (c == '\\') {
            ps->i++;
            if (at_end(ps)) { fail(ps, @"trailing \\"); return ci; }
            int e = ps->p[ps->i++], kind, neg;
            if (escape_class(ps, e, &kind, &neg)) {
                class_add(pg, ci, kind, neg, 0, 0);
                continue;
            }
            if (e == 'b') lo = 8;
            else {
                int64_t v = escape_char(ps, e);
                if (v < 0) { fail(ps, [NSString stringWithFormat:@"bad escape \\%C in set", (unichar)e]); return ci; }
                lo = (uint32_t)v;
            }
        } else {
            lo = next_cp(ps);
        }
        /* a range? */
        if (peek(ps) == '-' && ps->i + 1 < ps->n && ps->p[ps->i + 1] != ']') {
            ps->i++;
            uint32_t hi;
            if (peek(ps) == '\\') {
                ps->i++;
                int e = at_end(ps) ? 0 : ps->p[ps->i++];
                int64_t v = escape_char(ps, e);
                if (v < 0) { fail(ps, @"bad range end"); return ci; }
                hi = (uint32_t)v;
            } else if (peek(ps) == '[') {
                fail(ps, @"bad range");
                return ci;
            } else {
                hi = next_cp(ps);
            }
            if (hi < lo) { fail(ps, @"range out of order"); return ci; }
            class_add(pg, ci, CI_RANGE, 0, lo, hi);
            continue;
        }
        class_add(pg, ci, CI_RANGE, 0, lo, lo);
    }
    return ci;
}

static Node *parse_alt(Parser *ps);

static Node *char_node(Parser *ps, uint32_t c) {
    Node *n = node_new(ps, N_CHAR);
    n->c = c;
    n->flag = (ps->flags & F_I) != 0;
    return n;
}
static Node *class_node(Parser *ps, int kind, int neg) {
    int ci = class_new(ps->prog);
    class_add(ps->prog, ci, kind, neg, 0, 0);
    ps->prog->classes[ci].icase = (ps->flags & F_I) != 0;
    Node *n = node_new(ps, N_CLASS);
    n->c = (uint32_t)ci;
    return n;
}
static Node *assert_node(Parser *ps, int kind) {
    Node *n = node_new(ps, N_ASSERT);
    n->c = (uint32_t)kind;
    n->flag = (ps->flags & F_UNIX) != 0;
    return n;
}

/* inline flags: i m s x w; returns 0 at a ')' or ':' after them */
static int parse_flags(Parser *ps, int *flags) {
    int on = 1;
    for (;;) {
        int c = peek(ps), bit = 0;
        if (c == ')' || c == ':') return 1;
        switch (c) {
        case 'i': bit = F_I; break;
        case 'm': bit = F_M; break;
        case 's': bit = F_S; break;
        case 'x': bit = F_X; break;
        case 'w': bit = 0; break;
        case '-': on = 0; ps->i++; continue;
        default: fail(ps, @"bad inline flag"); return 0;
        }
        ps->i++;
        if (on) *flags |= bit;
        else *flags &= ~bit;
    }
}

static int group_named(Parser *ps, NSString *name) {
    NSUInteger i = [ps->prog->names indexOfObject:name];
    return i == NSNotFound ? -1 : (int)i + 1;
}

static Node *parse_atom(Parser *ps) {
    skip_space(ps);
    int c = peek(ps);
    if (c < 0) return NULL;
    switch (c) {
    case '|': case ')': return NULL;
    case '(': {
        ps->i++;
        int saved = ps->flags;
        Node *g;
        if (peek(ps) == '?') {
            ps->i++;
            int k = peek(ps);
            if (k == '#') { /* comment */
                while (!at_end(ps) && peek(ps) != ')') ps->i++;
                if (at_end(ps)) { fail(ps, @"unterminated comment"); return NULL; }
                ps->i++;
                return node_new(ps, N_EMPTY);
            }
            if (k == ':') {
                ps->i++;
                g = node_new(ps, N_GROUP);
            } else if (k == '>') {
                ps->i++;
                g = node_new(ps, N_ATOMIC);
            } else if (k == '=' || k == '!') {
                ps->i++;
                g = node_new(ps, N_LOOK);
                g->c = k == '=' ? L_AHEAD : L_NAHEAD;
            } else if (k == '<' && ps->i + 1 < ps->n && (ps->p[ps->i + 1] == '=' || ps->p[ps->i + 1] == '!')) {
                g = node_new(ps, N_LOOK);
                g->c = ps->p[ps->i + 1] == '=' ? L_BEHIND : L_NBEHIND;
                ps->i += 2;
            } else if (k == '<' || k == '\'' || (k == 'P' && ps->i + 1 < ps->n && ps->p[ps->i + 1] == '<')) {
                if (k == 'P') ps->i++;
                int close = ps->p[ps->i++] == '<' ? '>' : '\'';
                int start = ps->i;
                while (!at_end(ps) && peek(ps) != close) ps->i++;
                if (at_end(ps) || ps->i == start) { fail(ps, @"bad group name"); return NULL; }
                NSString *name = [NSString stringWithCharacters:ps->p + start length:(NSUInteger)(ps->i - start)];
                ps->i++;
                if (group_named(ps, name) > 0) { fail(ps, @"duplicate group name"); return NULL; }
                g = node_new(ps, N_GROUP);
                g->group = ++ps->prog->ngroups;
                [ps->prog->names addObject:name];
            } else {
                int flags = ps->flags;
                if (!parse_flags(ps, &flags)) return NULL;
                if (peek(ps) == ')') { /* (?i) applies to the rest of the enclosing group */
                    ps->i++;
                    ps->flags = flags;
                    return node_new(ps, N_EMPTY);
                }
                ps->i++; /* ':' */
                ps->flags = flags;
                g = node_new(ps, N_GROUP);
            }
        } else {
            g = node_new(ps, N_GROUP);
            g->group = ++ps->prog->ngroups;
            [ps->prog->names addObject:@""];
        }
        Node *body = parse_alt(ps);
        if (ps->error) return NULL;
        if (peek(ps) != ')') { fail(ps, @"missing )"); return NULL; }
        ps->i++;
        ps->flags = saved;
        node_add(g, body);
        return g;
    }
    case '[': {
        ps->i++;
        int ci = parse_set(ps);
        Node *n = node_new(ps, N_CLASS);
        n->c = (uint32_t)ci;
        return n;
    }
    case '.': {
        ps->i++;
        Node *n = node_new(ps, N_ANY);
        n->flag = ((ps->flags & F_S) ? 1 : 0) | ((ps->flags & F_UNIX) ? 2 : 0);
        return n;
    }
    case '^': ps->i++; return assert_node(ps, (ps->flags & F_M) ? A_MBOL : A_BOL);
    case '$': ps->i++; return assert_node(ps, (ps->flags & F_M) ? A_MEOL : A_EOL);
    case '*': case '+': case '?': fail(ps, @"nothing to repeat"); return NULL;
    case '\\': {
        ps->i++;
        if (at_end(ps)) { fail(ps, @"trailing \\"); return NULL; }
        int e = ps->p[ps->i++], kind, neg;
        switch (e) {
        case 'A': return assert_node(ps, A_STRBEG);
        case 'z': return assert_node(ps, A_STREND);
        case 'Z': return assert_node(ps, A_STRENDNL);
        case 'b': return assert_node(ps, A_WORDB);
        case 'B': return assert_node(ps, A_NWORDB);
        case 'G': return assert_node(ps, A_SEARCHSTART);
        case 'Q': {
            Node *cat = node_new(ps, N_CAT);
            while (!at_end(ps)) {
                if (peek(ps) == '\\' && ps->i + 1 < ps->n && ps->p[ps->i + 1] == 'E') { ps->i += 2; break; }
                node_add(cat, char_node(ps, next_cp(ps)));
            }
            return cat;
        }
        case 'E': return node_new(ps, N_EMPTY);
        case 'R': { /* \r\n or one line break */
            Node *alt = node_new(ps, N_ALT), *crlf = node_new(ps, N_CAT);
            node_add(crlf, char_node(ps, '\r'));
            node_add(crlf, char_node(ps, '\n'));
            node_add(alt, crlf);
            int ci = class_new(ps->prog);
            class_add(ps->prog, ci, CI_RANGE, 0, '\n', '\r');
            class_add(ps->prog, ci, CI_RANGE, 0, 0x85, 0x85);
            class_add(ps->prog, ci, CI_RANGE, 0, 0x2028, 0x2029);
            Node *one = node_new(ps, N_CLASS);
            one->c = (uint32_t)ci;
            node_add(alt, one);
            Node *g = node_new(ps, N_ATOMIC);
            node_add(g, alt);
            return g;
        }
        case 'k': {
            if (peek(ps) != '<' && peek(ps) != '{' && peek(ps) != '\'') { fail(ps, @"bad \\k"); return NULL; }
            int close = ps->p[ps->i] == '<' ? '>' : ps->p[ps->i] == '{' ? '}' : '\'';
            int start = ++ps->i;
            while (!at_end(ps) && peek(ps) != close) ps->i++;
            if (at_end(ps)) { fail(ps, @"bad \\k"); return NULL; }
            NSString *name = [NSString stringWithCharacters:ps->p + start length:(NSUInteger)(ps->i - start)];
            ps->i++;
            int gi = group_named(ps, name);
            if (gi < 0) { fail(ps, @"unknown group name"); return NULL; }
            Node *n = node_new(ps, N_BACKREF);
            n->c = (uint32_t)gi;
            n->flag = (ps->flags & F_I) != 0;
            return n;
        }
        }
        if (e >= '1' && e <= '9') {
            int gi = e - '0';
            /* more digits while the group exists */
            while (peek(ps) >= '0' && peek(ps) <= '9' && gi * 10 + (peek(ps) - '0') <= ps->prog->ngroups)
                gi = gi * 10 + (ps->p[ps->i++] - '0');
            Node *n = node_new(ps, N_BACKREF);
            n->c = (uint32_t)gi;
            n->flag = (ps->flags & F_I) != 0;
            return n;
        }
        if (escape_class(ps, e, &kind, &neg)) return class_node(ps, kind, neg);
        int64_t v = escape_char(ps, e);
        if (v < 0) { fail(ps, [NSString stringWithFormat:@"bad escape \\%C", (unichar)e]); return NULL; }
        return char_node(ps, (uint32_t)v);
    }
    }
    return char_node(ps, next_cp(ps));
}

/* {n}, {n,}, {n,m}; returns 0 (and leaves the position) if this is not one */
static int parse_braces(Parser *ps, int *min, int *max) {
    int j = ps->i + 1, lo = 0, hi, digits = 0;
    while (j < ps->n && ps->p[j] >= '0' && ps->p[j] <= '9') { lo = lo * 10 + (ps->p[j++] - '0'); digits++; if (lo > 100000) return 0; }
    if (!digits) return 0;
    hi = lo;
    if (j < ps->n && ps->p[j] == ',') {
        j++;
        hi = -1;
        if (j < ps->n && ps->p[j] >= '0' && ps->p[j] <= '9') {
            hi = 0;
            while (j < ps->n && ps->p[j] >= '0' && ps->p[j] <= '9') { hi = hi * 10 + (ps->p[j++] - '0'); if (hi > 100000) return 0; }
        }
    }
    if (j >= ps->n || ps->p[j] != '}') return 0;
    ps->i = j + 1;
    *min = lo;
    *max = hi;
    return 1;
}

static Node *parse_cat(Parser *ps) {
    Node *cat = node_new(ps, N_CAT);
    for (;;) {
        Node *a = parse_atom(ps);
        if (ps->error) return NULL;
        if (!a) break;
        for (;;) {
            skip_space(ps);
            int c = peek(ps), min, max;
            if (c == '*') { ps->i++; min = 0; max = -1; }
            else if (c == '+') { ps->i++; min = 1; max = -1; }
            else if (c == '?') { ps->i++; min = 0; max = 1; }
            else if (c == '{' && parse_braces(ps, &min, &max)) {
                if (max >= 0 && max < min) { fail(ps, @"bad {m,n}"); return NULL; }
            } else break;
            if (a->type == N_ASSERT || a->type == N_LOOK || a->type == N_EMPTY) {
                /* repeating a zero-width item: once at most */
                if (min > 1) min = 1;
                if (max != 0) max = 1;
            }
            Node *r = node_new(ps, N_REPEAT);
            r->min = min;
            r->max = max;
            r->greedy = 1;
            if (peek(ps) == '?') { ps->i++; r->greedy = 0; }
            else if (peek(ps) == '+') { ps->i++; r->possessive = 1; }
            node_add(r, a);
            a = r;
        }
        node_add(cat, a);
    }
    return cat;
}

static Node *parse_alt(Parser *ps) {
    Node *first = parse_cat(ps);
    if (ps->error || peek(ps) != '|') return first;
    Node *alt = node_new(ps, N_ALT);
    node_add(alt, first);
    while (peek(ps) == '|') {
        ps->i++;
        Node *n = parse_cat(ps);
        if (ps->error) return NULL;
        node_add(alt, n);
    }
    return alt;
}

/* ---- code generation ------------------------------------------------------------------------ */

static int emit(Program *pg, int op, int flag, int a, int b) {
    if (pg->ncode == pg->capcode) {
        pg->capcode = pg->capcode ? pg->capcode * 2 : 64;
        pg->code = realloc(pg->code, (size_t)pg->capcode * sizeof *pg->code);
    }
    pg->code[pg->ncode] = (Inst){(uint8_t)op, (uint8_t)flag, a, b};
    return pg->ncode++;
}

/* minimum and maximum lengths a node matches (max -1 = unbounded) */
static void node_lengths(const Node *n, int *mn, int *mx) {
    int a, b;
    switch (n->type) {
    case N_CHAR: *mn = 1; *mx = n->c > 0xffff ? 2 : 1; return;
    case N_ANY: case N_CLASS: *mn = 1; *mx = 2; return;
    case N_EMPTY: case N_ASSERT: case N_LOOK: *mn = *mx = 0; return;
    case N_BACKREF: *mn = 0; *mx = -1; return;
    case N_GROUP: case N_ATOMIC: node_lengths(n->kids[0], mn, mx); return;
    case N_CAT:
        *mn = *mx = 0;
        for (int i = 0; i < n->nkids; i++) {
            node_lengths(n->kids[i], &a, &b);
            *mn += a;
            *mx = (*mx < 0 || b < 0) ? -1 : *mx + b;
        }
        return;
    case N_ALT:
        *mn = 1 << 30;
        *mx = 0;
        for (int i = 0; i < n->nkids; i++) {
            node_lengths(n->kids[i], &a, &b);
            if (a < *mn) *mn = a;
            *mx = (*mx < 0 || b < 0) ? -1 : (b > *mx ? b : *mx);
        }
        if (!n->nkids) *mn = 0;
        return;
    case N_REPEAT:
        node_lengths(n->kids[0], &a, &b);
        *mn = a * n->min;
        *mx = (n->max < 0 || b < 0) ? (b == 0 ? 0 : -1) : b * n->max;
        return;
    }
    *mn = 0;
    *mx = -1;
}

static int gen(Program *pg, const Node *n);
static int gen_sub(Program *pg, int op, int kind, const Node *body, int behind_max) {
    int at = emit(pg, op, kind, 0, behind_max);
    if (!gen(pg, body)) return 0;
    emit(pg, OP_SUBEND, 0, 0, 0);
    pg->code[at].a = pg->ncode; /* continue here */
    return 1;
}
static int gen(Program *pg, const Node *n) {
    if (pg->ncode > 200000) return 0;
    switch (n->type) {
    case N_EMPTY: return 1;
    case N_CHAR: emit(pg, OP_CHAR, n->flag, (int)(n->flag ? u_fold(n->c) : n->c), 0); return 1;
    case N_ANY: emit(pg, OP_ANY, n->flag, 0, 0); return 1;
    case N_CLASS: emit(pg, OP_CLASS, 0, (int)n->c, 0); return 1;
    case N_ASSERT: emit(pg, OP_ASSERT, n->flag, (int)n->c, 0); return 1;
    case N_BACKREF: emit(pg, OP_BACKREF, n->flag, (int)n->c, 0); return 1;
    case N_CAT:
        for (int i = 0; i < n->nkids; i++)
            if (!gen(pg, n->kids[i])) return 0;
        return 1;
    case N_GROUP:
        if (n->group >= 0) emit(pg, OP_SAVE, 0, 2 * n->group, 0);
        if (!gen(pg, n->kids[0])) return 0;
        if (n->group >= 0) emit(pg, OP_SAVE, 0, 2 * n->group + 1, 0);
        return 1;
    case N_ALT: {
        /* SPLIT next, alt2; body1; JMP end; ... */
        int *jumps = calloc((size_t)n->nkids, sizeof *jumps);
        for (int i = 0; i < n->nkids; i++) {
            int split = -1;
            if (i < n->nkids - 1) split = emit(pg, OP_SPLIT, 0, 0, 0);
            if (split >= 0) pg->code[split].a = pg->ncode;
            if (!gen(pg, n->kids[i])) { free(jumps); return 0; }
            if (i < n->nkids - 1) {
                jumps[i] = emit(pg, OP_JMP, 0, 0, 0);
                pg->code[split].b = pg->ncode;
            }
        }
        for (int i = 0; i < n->nkids - 1; i++) pg->code[jumps[i]].a = pg->ncode;
        free(jumps);
        return 1;
    }
    case N_LOOK: {
        int mn, mx = 0;
        if (n->c == L_BEHIND || n->c == L_NBEHIND) node_lengths(n->kids[0], &mn, &mx);
        return gen_sub(pg, OP_LOOK, (int)n->c, n->kids[0], mx);
    }
    case N_ATOMIC: return gen_sub(pg, OP_ATOMIC, 0, n->kids[0], 0);
    case N_REPEAT: {
        if (n->possessive) {
            Node copy = *n;
            copy.possessive = 0;
            int at = emit(pg, OP_ATOMIC, 0, 0, 0);
            if (!gen(pg, &copy)) return 0;
            emit(pg, OP_SUBEND, 0, 0, 0);
            pg->code[at].a = pg->ncode;
            return 1;
        }
        const Node *k = n->kids[0];
        for (int i = 0; i < n->min; i++)
            if (!gen(pg, k)) return 0;
        if (n->max < 0) {
            /* L1: SPLIT L2, L3; L2: MARK c; k; PROGRESS c; JMP L1; L3: */
            int counter = pg->ncounters++;
            int l1 = emit(pg, OP_SPLIT, 0, 0, 0);
            emit(pg, OP_MARK, 0, counter, 0);
            int body = l1 + 1;
            if (!gen(pg, k)) return 0;
            emit(pg, OP_PROGRESS, 0, counter, 0);
            emit(pg, OP_JMP, 0, l1, 0);
            int l3 = pg->ncode;
            pg->code[l1].a = n->greedy ? body : l3;
            pg->code[l1].b = n->greedy ? l3 : body;
        } else {
            /* (k(k(k)?)?)? for the optional copies */
            int count = n->max - n->min;
            int *splits = calloc((size_t)(count > 0 ? count : 1), sizeof *splits);
            for (int i = 0; i < count; i++) {
                splits[i] = emit(pg, OP_SPLIT, 0, 0, 0);
                if (!gen(pg, k)) { free(splits); return 0; }
            }
            int end = pg->ncode;
            for (int i = 0; i < count; i++) {
                int body = splits[i] + 1;
                pg->code[splits[i]].a = n->greedy ? body : end;
                pg->code[splits[i]].b = n->greedy ? end : body;
            }
            free(splits);
        }
        return 1;
    }
    }
    return 0;
}

static void program_free(Program *pg) {
    if (!pg) return;
    for (int i = 0; i < pg->nclasses; i++) free(pg->classes[i].items);
    free(pg->classes);
    free(pg->code);
    pg->names = nil;
    free(pg);
}

static Program *compile(NSString *pattern, NSRegularExpressionOptions options, NSString **error) {
    Program *pg = calloc(1, sizeof *pg);
    pg->names = [NSMutableArray array];
    NSUInteger len = pattern.length;
    unichar *buf = malloc((len + 1) * sizeof(unichar));
    [pattern getCharacters:buf range:NSMakeRange(0, len)];
    Parser ps = {buf, (int)len, 0, 0, pg, nil, NULL, 0, 0};
    if (options & NSRegularExpressionCaseInsensitive) ps.flags |= F_I;
    if (options & NSRegularExpressionAllowCommentsAndWhitespace) ps.flags |= F_X;
    if (options & NSRegularExpressionDotMatchesLineSeparators) ps.flags |= F_S;
    if (options & NSRegularExpressionAnchorsMatchLines) ps.flags |= F_M;
    if (options & NSRegularExpressionUseUnixLineSeparators) ps.flags |= F_UNIX;
    pg->unix_lines = (options & NSRegularExpressionUseUnixLineSeparators) != 0;
    Node *root;
    if (options & NSRegularExpressionIgnoreMetacharacters) {
        root = node_new(&ps, N_CAT);
        while (!at_end(&ps)) node_add(root, char_node(&ps, next_cp(&ps)));
    } else {
        root = parse_alt(&ps);
        if (!ps.error && !at_end(&ps)) fail(&ps, @"unmatched )");
    }
    if (!ps.error) {
        /* group 0 around everything */
        emit(pg, OP_SAVE, 0, 0, 0);
        if (!gen(pg, root)) fail(&ps, @"pattern too large");
        emit(pg, OP_SAVE, 0, 1, 0);
        emit(pg, OP_MATCH, 0, 0, 0);
        /* anchored if the first real instruction is \A (or ^ without multi-line) */
        if (pg->ncode > 1 && pg->code[1].op == OP_ASSERT && (pg->code[1].a == A_STRBEG || pg->code[1].a == A_BOL))
            pg->anchored = 1;
    }
    parse_free(&ps);
    free(buf);
    if (ps.error) {
        if (error) *error = ps.error;
        program_free(pg);
        return NULL;
    }
    return pg;
}

/* ---- matching ------------------------------------------------------------------------------- */

enum { BT_BRANCH, BT_CAP, BT_CNT };
typedef struct { int kind, a, b; } BT;

typedef struct {
    const Program *pg;
    const unichar *s;
    int n;                 /* the text */
    int search_start;      /* \G */
    int *caps;             /* 2 * (ngroups + 1) */
    int *counters;
    long steps;
    int unix_lines;
} VM;

#define STEP_LIMIT 20000000L

static uint32_t cp_at(const VM *vm, int i, int *len) {
    uint32_t c = vm->s[i];
    *len = 1;
    if (c >= 0xd800 && c < 0xdc00 && i + 1 < vm->n && vm->s[i + 1] >= 0xdc00 && vm->s[i + 1] < 0xe000) {
        c = 0x10000 + ((c - 0xd800) << 10) + (vm->s[i + 1] - 0xdc00);
        *len = 2;
    }
    return c;
}
static uint32_t cp_before(const VM *vm, int i) {
    if (i <= 0) return 0xffffffff;
    uint32_t c = vm->s[i - 1];
    if (c >= 0xdc00 && c < 0xe000 && i >= 2 && vm->s[i - 2] >= 0xd800 && vm->s[i - 2] < 0xdc00)
        c = 0x10000 + ((vm->s[i - 2] - 0xd800) << 10) + (c - 0xdc00);
    return c;
}
static int is_lt(const VM *vm, int i) { return i < vm->n && u_is_lineterm(vm->s[i], vm->unix_lines); }

static int assert_ok(const VM *vm, int kind, int sp) {
    int n = vm->n;
    switch (kind) {
    case A_BOL: case A_STRBEG: return sp == 0;
    case A_STREND: return sp == n;
    case A_EOL: case A_STRENDNL:
        if (sp == n) return 1;
        if (sp == n - 1 && is_lt(vm, sp)) return 1;
        if (sp == n - 2 && !vm->unix_lines && vm->s[sp] == '\r' && vm->s[sp + 1] == '\n') return 1;
        return 0;
    case A_MBOL:
        if (sp == 0) return 1;
        if (sp == n) return 0; /* ICU: ^ does not match after a final line break */
        if (!u_is_lineterm(vm->s[sp - 1], vm->unix_lines)) return 0;
        return !(vm->s[sp - 1] == '\r' && vm->s[sp] == '\n');
    case A_MEOL:
        if (sp == n) return 1;
        if (!is_lt(vm, sp)) return 0;
        return !(sp > 0 && vm->s[sp - 1] == '\r' && vm->s[sp] == '\n');
    case A_WORDB: case A_NWORDB: {
        int l;
        uint32_t b = cp_before(vm, sp);
        int wb = b != 0xffffffff && u_is_word(b);
        int wa = sp < n && u_is_word(cp_at(vm, sp, &l));
        return (wb != wa) == (kind == A_WORDB);
    }
    case A_SEARCHSTART: return sp == vm->search_start;
    }
    return 0;
}

typedef struct {
    BT *st;
    int n, cap;
} Stack;
static void push(Stack *s, int kind, int a, int b) {
    if (s->n == s->cap) {
        s->cap = s->cap ? s->cap * 2 : 256;
        s->st = realloc(s->st, (size_t)s->cap * sizeof *s->st);
    }
    s->st[s->n++] = (BT){kind, a, b};
}

/* Runs from pc at sp until MATCH (or SUBEND when sub; must_end >= 0 means
 * SUBEND only succeeds there). Returns the end position or -1. On success
 * the captures hold the match; the undo log for them is left on *undo if
 * given (so an enclosing run can back out), else discarded. */
static int run(VM *vm, int pc, int sp, int sub, int must_end, Stack *undo) {
    const Inst *code = vm->pg->code;
    Stack bt = {0};
    for (;;) {
        if (++vm->steps > STEP_LIMIT) goto failed;
        const Inst *in = &code[pc];
        int len;
        switch (in->op) {
        case OP_CHAR: {
            if (sp >= vm->n) goto fail;
            uint32_t c = cp_at(vm, sp, &len);
            if (in->flag) c = u_fold(c);
            if (c != (uint32_t)in->a) goto fail;
            sp += len;
            pc++;
            continue;
        }
        case OP_ANY: {
            if (sp >= vm->n) goto fail;
            uint32_t c = cp_at(vm, sp, &len);
            if (!(in->flag & 1) && u_is_lineterm(c, (in->flag & 2) != 0)) goto fail;
            sp += len;
            pc++;
            continue;
        }
        case OP_CLASS: {
            if (sp >= vm->n) goto fail;
            uint32_t c = cp_at(vm, sp, &len);
            if (!class_matches(vm->pg, in->a, c)) goto fail;
            sp += len;
            pc++;
            continue;
        }
        case OP_ASSERT:
            if (!assert_ok(vm, in->a, sp)) goto fail;
            pc++;
            continue;
        case OP_SPLIT:
            push(&bt, BT_BRANCH, in->b, sp);
            pc = in->a;
            continue;
        case OP_JMP:
            pc = in->a;
            continue;
        case OP_SAVE:
            push(&bt, BT_CAP, in->a, vm->caps[in->a]);
            vm->caps[in->a] = sp;
            pc++;
            continue;
        case OP_MARK:
            push(&bt, BT_CNT, in->a, vm->counters[in->a]);
            vm->counters[in->a] = sp;
            pc++;
            continue;
        case OP_PROGRESS:
            if (vm->counters[in->a] == sp) goto fail; /* an empty iteration: stop looping */
            pc++;
            continue;
        case OP_BACKREF: {
            int g = in->a, b = vm->caps[2 * g], e = vm->caps[2 * g + 1];
            if (g > vm->pg->ngroups || b < 0 || e < 0) goto fail; /* an unset group fails, as in ICU */
            int l = e - b;
            if (sp + l > vm->n) goto fail;
            for (int k = 0; k < l; k++) {
                uint32_t x = vm->s[b + k], y = vm->s[sp + k];
                if (x != y && !(in->flag && u_fold(x) == u_fold(y))) goto fail;
            }
            sp += l;
            pc++;
            continue;
        }
        case OP_LOOK: {
            int kind = in->flag, ok = 0;
            Stack inner_undo = {0};
            if (kind == L_AHEAD || kind == L_NAHEAD) {
                ok = run(vm, pc + 1, sp, 1, -1, &inner_undo) >= 0;
            } else {
                int lo = in->b >= 0 ? sp - in->b : 0;
                if (lo < 0) lo = 0;
                for (int start = sp; start >= lo && !ok; start--)
                    ok = run(vm, pc + 1, start, 1, sp, &inner_undo) >= 0;
            }
            if (vm->steps > STEP_LIMIT) { free(inner_undo.st); goto failed; }
            int positive = kind == L_AHEAD || kind == L_BEHIND;
            if (ok && !positive) {
                /* undo what the look-around set, then fail */
                while (inner_undo.n) {
                    BT e = inner_undo.st[--inner_undo.n];
                    if (e.kind == BT_CAP) vm->caps[e.a] = e.b;
                    else if (e.kind == BT_CNT) vm->counters[e.a] = e.b;
                }
                free(inner_undo.st);
                goto fail;
            }
            if (!ok && positive) { free(inner_undo.st); goto fail; }
            /* keep the captures it set, undoable from here */
            for (int k = 0; k < inner_undo.n; k++)
                if (inner_undo.st[k].kind != BT_BRANCH) push(&bt, inner_undo.st[k].kind, inner_undo.st[k].a, inner_undo.st[k].b);
            free(inner_undo.st);
            pc = in->a;
            continue;
        }
        case OP_ATOMIC: {
            Stack inner_undo = {0};
            int e = run(vm, pc + 1, sp, 1, -1, &inner_undo);
            if (vm->steps > STEP_LIMIT) { free(inner_undo.st); goto failed; }
            if (e < 0) { free(inner_undo.st); goto fail; }
            for (int k = 0; k < inner_undo.n; k++)
                if (inner_undo.st[k].kind != BT_BRANCH) push(&bt, inner_undo.st[k].kind, inner_undo.st[k].a, inner_undo.st[k].b);
            free(inner_undo.st);
            sp = e;
            pc = in->a;
            continue;
        }
        case OP_SUBEND:
            if (!sub) goto fail;
            if (must_end >= 0 && sp != must_end) goto fail;
            goto matched;
        case OP_MATCH:
            if (sub) goto fail;
            goto matched;
        }
    fail:
        for (;;) {
            if (!bt.n) goto failed;
            BT e = bt.st[--bt.n];
            if (e.kind == BT_CAP) vm->caps[e.a] = e.b;
            else if (e.kind == BT_CNT) vm->counters[e.a] = e.b;
            else {
                pc = e.a;
                sp = e.b;
                break;
            }
        }
    }
matched:
    if (undo)
        for (int k = 0; k < bt.n; k++)
            if (bt.st[k].kind != BT_BRANCH) push(undo, bt.st[k].kind, bt.st[k].a, bt.st[k].b);
    free(bt.st);
    return sp;
failed:
    free(bt.st);
    return -1;
}

/* The first match at or after start (within [0, n)); fills ranges[0..ngroups]. */
static int search(const Program *pg, const unichar *s, int n, int start, int anchored_only, NSRange *ranges,
                  int *timed_out) {
    int ncap = 2 * (pg->ngroups + 1);
    int *caps = malloc((size_t)ncap * sizeof(int));
    int *counters = calloc((size_t)(pg->ncounters + 1), sizeof(int));
    VM vm = {pg, s, n, start, caps, counters, 0, pg->unix_lines};
    /* a literal first character lets the scan skip ahead */
    int lit = -1;
    if (!anchored_only && pg->ncode > 1 && pg->code[1].op == OP_CHAR && !pg->code[1].flag && pg->code[1].a < 0x10000)
        lit = pg->code[1].a;
    int found = 0;
    for (int at = start; at <= n; at++) {
        if (lit >= 0) {
            while (at < n && s[at] != lit) at++;
            if (at >= n) break;
        }
        for (int k = 0; k < ncap; k++) caps[k] = -1;
        vm.steps = 0; /* the budget is per starting position */
        int e = run(&vm, 0, at, 0, -1, NULL);
        if (vm.steps > STEP_LIMIT) {
            if (timed_out) *timed_out = 1;
            break;
        }
        if (e >= 0) {
            found = 1;
            break;
        }
        if (pg->anchored || anchored_only) break;
        /* do not start inside a surrogate pair */
        if (at < n && s[at] >= 0xd800 && s[at] < 0xdc00 && at + 1 < n && s[at + 1] >= 0xdc00 && s[at + 1] < 0xe000) at++;
    }
    if (found)
        for (int g = 0; g <= pg->ngroups; g++)
            ranges[g] = caps[2 * g] >= 0 && caps[2 * g + 1] >= 0
                            ? NSMakeRange((NSUInteger)caps[2 * g], (NSUInteger)(caps[2 * g + 1] - caps[2 * g]))
                            : NSMakeRange(NSNotFound, 0);
    free(caps);
    free(counters);
    return found;
}

/* ---- NSTextCheckingResult ------------------------------------------------------------- */

@interface NSRegularExpression (BNGroups)
- (NSInteger)_bn_groupNamed:(NSString *)name;
@end

@implementation NSTextCheckingResult {
  @public
    NSTextCheckingType _type;
    NSRange *_ranges;
    NSUInteger _count;
    NSRegularExpression *_regex;
    NSURL *_url;
    NSString *_phone;
    NSDate *_date;
}
+ (NSTextCheckingResult *)regularExpressionCheckingResultWithRanges:(NSRangePointer)ranges
                                                              count:(NSUInteger)count
                                                  regularExpression:(NSRegularExpression *)regex {
    NSTextCheckingResult *r = [self new];
    r->_type = NSTextCheckingTypeRegularExpression;
    r->_count = count;
    r->_ranges = malloc((count ? count : 1) * sizeof(NSRange));
    if (count) memcpy(r->_ranges, ranges, count * sizeof(NSRange));
    r->_regex = regex;
    return r;
}
+ (NSTextCheckingResult *)linkCheckingResultWithRange:(NSRange)range URL:(NSURL *)url {
    NSTextCheckingResult *r = [self regularExpressionCheckingResultWithRanges:&range count:1 regularExpression:nil];
    r->_type = NSTextCheckingTypeLink;
    r->_url = url;
    return r;
}
+ (NSTextCheckingResult *)phoneNumberCheckingResultWithRange:(NSRange)range phoneNumber:(NSString *)phoneNumber {
    NSTextCheckingResult *r = [self regularExpressionCheckingResultWithRanges:&range count:1 regularExpression:nil];
    r->_type = NSTextCheckingTypePhoneNumber;
    r->_phone = [phoneNumber copy];
    return r;
}
- (void)dealloc { free(_ranges); }
- (NSTextCheckingType)resultType { return _type; }
- (NSRange)range { return _count ? _ranges[0] : NSMakeRange(NSNotFound, 0); }
- (NSUInteger)numberOfRanges { return _count; }
- (NSRange)rangeAtIndex:(NSUInteger)idx {
    if (idx >= _count)
        [NSException raise:NSRangeException format:@"-[NSTextCheckingResult rangeAtIndex:]: index %lu out of bounds", (unsigned long)idx];
    return _ranges[idx];
}
- (NSRange)rangeWithName:(NSString *)name {
    NSInteger g = _regex ? [_regex _bn_groupNamed:name] : -1;
    return g > 0 && (NSUInteger)g < _count ? _ranges[g] : NSMakeRange(NSNotFound, 0);
}
- (NSRegularExpression *)regularExpression { return _regex; }
- (NSURL *)URL { return _url; }
- (NSString *)phoneNumber { return _phone; }
- (NSDate *)date { return _date; }
- (NSDictionary *)components { return nil; }
- (NSDictionary *)addressComponents { return nil; }
- (NSString *)replacementString { return nil; }
- (NSArray *)alternativeStrings { return nil; }
- (id)orthography { return nil; }
- (NSArray *)grammarDetails { return nil; }
- (NSTimeZone *)timeZone { return nil; }
- (NSTimeInterval)duration { return 0; }
- (NSTextCheckingResult *)resultByAdjustingRangesWithOffset:(NSInteger)offset {
    NSTextCheckingResult *r = [[self class] regularExpressionCheckingResultWithRanges:_ranges count:_count regularExpression:_regex];
    for (NSUInteger i = 0; i < _count; i++)
        if (r->_ranges[i].location != NSNotFound) r->_ranges[i].location = (NSUInteger)((NSInteger)r->_ranges[i].location + offset);
    r->_type = _type;
    r->_url = _url;
    r->_phone = _phone;
    r->_date = _date;
    return r;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description {
    NSRange r = self.range;
    return [NSString stringWithFormat:@"<NSTextCheckingResult: %p>{%lu, %lu}%@", (void *)self, (unsigned long)r.location,
                                      (unsigned long)r.length, _url ? [@"{" stringByAppendingFormat:@"%@}", _url] : @""];
}
@end

/* ---- NSRegularExpression ------------------------------------------------------------------- */

@implementation NSRegularExpression {
    NSString *_pattern;
    NSRegularExpressionOptions _options;
    Program *_prog;
}
+ (instancetype)regularExpressionWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options error:(NSError **)error {
    return [[self alloc] initWithPattern:pattern options:options error:error];
}
- (instancetype)initWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options error:(NSError **)error {
    if (!(self = [super init])) return nil;
    if (!pattern) pattern = @"";
    NSString *why = nil;
    _prog = compile(pattern, options, &why);
    if (!_prog) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:2048
                                     userInfo:@{@"NSInvalidValue" : pattern,
                                                NSLocalizedDescriptionKey : [NSString stringWithFormat:
                                                    @"The value “%@” is invalid.", pattern],
                                                @"NSDebugDescription" : why ?: @"invalid pattern"}];
        return nil;
    }
    _pattern = [pattern copy];
    _options = options;
    return self;
}
- (instancetype)init { return [self initWithPattern:@"" options:0 error:NULL]; }
- (void)dealloc { program_free(_prog); }
- (NSString *)pattern { return _pattern; }
- (NSRegularExpressionOptions)options { return _options; }
- (NSUInteger)numberOfCaptureGroups { return (NSUInteger)_prog->ngroups; }
- (NSInteger)_bn_groupNamed:(NSString *)name {
    NSUInteger i = name.length ? [_prog->names indexOfObject:name] : NSNotFound;
    return i == NSNotFound ? -1 : (NSInteger)i + 1;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:[NSRegularExpression class]] && [((NSRegularExpression *)other)->_pattern isEqual:_pattern] &&
           ((NSRegularExpression *)other)->_options == _options;
}
- (NSUInteger)hash { return _pattern.hash ^ _options; }
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> %@ 0x%lx", NSStringFromClass([self class]), (void *)self, _pattern, (unsigned long)_options];
}

+ (NSString *)escapedPatternForString:(NSString *)string {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c < 0x80 && strchr("*?+[(){}^$|\\./", c) && c) [out appendString:@"\\"];
        [out appendFormat:@"%C", c];
    }
    return out;
}
+ (NSString *)escapedTemplateForString:(NSString *)string {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c == '$' || c == '\\') [out appendString:@"\\"];
        [out appendFormat:@"%C", c];
    }
    return out;
}

/* The engine runs over the whole string; ranges outside the search range
 * are invisible, as with ICU's default (non-transparent, anchoring) bounds. */
- (void)enumerateMatchesInString:(NSString *)string
                         options:(NSMatchingOptions)options
                           range:(NSRange)range
                      usingBlock:(void (^)(NSTextCheckingResult *_Nullable, NSMatchingFlags, BOOL *))block {
    if (!string) [NSException raise:NSInvalidArgumentException format:@"-[NSRegularExpression enumerateMatchesInString:...]: nil string"];
    if (NSMaxRange(range) > string.length)
        [NSException raise:NSRangeException format:@"-[NSRegularExpression enumerateMatchesInString:...]: range out of bounds"];
    NSUInteger len = range.length;
    unichar *buf = malloc((len + 1) * sizeof(unichar));
    [string getCharacters:buf range:range];
    int ng = _prog->ngroups;
    NSRange *ranges = malloc((size_t)(ng + 1) * sizeof(NSRange));
    BOOL stop = NO;
    int pos = 0, timed_out = 0;
    int anchored = (options & NSMatchingAnchored) != 0;
    while (pos <= (int)len && !stop) {
        if (!search(_prog, buf, (int)len, pos, anchored, ranges, &timed_out)) break;
        for (int g = 0; g <= ng; g++)
            if (ranges[g].location != NSNotFound) ranges[g].location += range.location;
        NSTextCheckingResult *r = [NSTextCheckingResult regularExpressionCheckingResultWithRanges:ranges
                                                                                            count:(NSUInteger)ng + 1
                                                                                regularExpression:self];
        block(r, 0, &stop);
        int end = (int)(ranges[0].location - range.location + ranges[0].length);
        if (ranges[0].length == 0) {
            if (end >= (int)len) break;
            int l = 1;
            if (buf[end] >= 0xd800 && buf[end] < 0xdc00 && end + 1 < (int)len) l = 2;
            pos = end + l;
        } else {
            pos = end;
        }
        if (anchored) break; /* NSMatchingAnchored: matches must start where the last ended */
    }
    free(ranges);
    free(buf);
    if ((options & NSMatchingReportCompletion) && !stop)
        block(nil, NSMatchingCompleted | (timed_out ? NSMatchingInternalError : 0), &stop);
}

- (NSArray<NSTextCheckingResult *> *)matchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range {
    NSMutableArray *out = [NSMutableArray array];
    [self enumerateMatchesInString:string options:options & ~NSMatchingReportCompletion range:range
                        usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags f, BOOL *stop) { if (r) [out addObject:r]; }];
    return out;
}
- (NSUInteger)numberOfMatchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range {
    __block NSUInteger n = 0;
    [self enumerateMatchesInString:string options:options & ~NSMatchingReportCompletion range:range
                        usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags f, BOOL *stop) { if (r) n++; }];
    return n;
}
- (NSTextCheckingResult *)firstMatchInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range {
    __block NSTextCheckingResult *first = nil;
    [self enumerateMatchesInString:string options:options & ~NSMatchingReportCompletion range:range
                        usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags f, BOOL *stop) {
                            if (r) { first = r; *stop = YES; }
                        }];
    return first;
}
- (NSRange)rangeOfFirstMatchInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range {
    NSTextCheckingResult *r = [self firstMatchInString:string options:options range:range];
    return r ? r.range : NSMakeRange(NSNotFound, 0);
}

- (NSString *)replacementStringForResult:(NSTextCheckingResult *)result
                                inString:(NSString *)string
                                  offset:(NSInteger)offset
                                template:(NSString *)templ {
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = templ.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [templ characterAtIndex:i];
        if (c == '\\' && i + 1 < n) {
            [out appendFormat:@"%C", [templ characterAtIndex:++i]];
            continue;
        }
        if (c == '$' && i + 1 < n) {
            unichar d = [templ characterAtIndex:i + 1];
            NSInteger g = -1;
            NSUInteger j = i + 1;
            if (d >= '0' && d <= '9') {
                g = d - '0';
                j = i + 2;
                /* more digits while the group exists */
                while (j < n) {
                    unichar e = [templ characterAtIndex:j];
                    if (e < '0' || e > '9' || g * 10 + (e - '0') > (NSInteger)result.numberOfRanges - 1) break;
                    g = g * 10 + (e - '0');
                    j++;
                }
            } else if (d == '{') {
                NSUInteger close = j + 1;
                while (close < n && [templ characterAtIndex:close] != '}') close++;
                if (close < n) {
                    NSString *name = [templ substringWithRange:NSMakeRange(j + 1, close - j - 1)];
                    g = [self _bn_groupNamed:name];
                    j = close + 1;
                }
            }
            if (g >= 0) {
                if ((NSUInteger)g < result.numberOfRanges) {
                    NSRange r = [result rangeAtIndex:(NSUInteger)g];
                    if (r.location != NSNotFound) {
                        r.location = (NSUInteger)((NSInteger)r.location + offset);
                        [out appendString:[string substringWithRange:r]];
                    }
                }
                i = j - 1;
                continue;
            }
        }
        [out appendFormat:@"%C", c];
    }
    return out;
}

- (NSString *)stringByReplacingMatchesInString:(NSString *)string
                                       options:(NSMatchingOptions)options
                                         range:(NSRange)range
                                  withTemplate:(NSString *)templ {
    NSArray<NSTextCheckingResult *> *matches = [self matchesInString:string options:options range:range];
    if (!matches.count) return [string copy];
    NSMutableString *out = [NSMutableString string];
    NSUInteger last = 0;
    for (NSTextCheckingResult *m in matches) {
        NSRange r = m.range;
        [out appendString:[string substringWithRange:NSMakeRange(last, r.location - last)]];
        [out appendString:[self replacementStringForResult:m inString:string offset:0 template:templ]];
        last = NSMaxRange(r);
    }
    [out appendString:[string substringFromIndex:last]];
    return out;
}
- (NSUInteger)replaceMatchesInString:(NSMutableString *)string
                             options:(NSMatchingOptions)options
                               range:(NSRange)range
                        withTemplate:(NSString *)templ {
    NSArray<NSTextCheckingResult *> *matches = [self matchesInString:string options:options range:range];
    NSString *original = [string copy];
    for (NSTextCheckingResult *m in matches.reverseObjectEnumerator)
        [string replaceCharactersInRange:m.range withString:[self replacementStringForResult:m inString:original offset:0 template:templ]];
    return matches.count;
}
@end

/* ---- NSDataDetector -------------------------------------------------------------------------- */

@implementation NSDataDetector {
    NSTextCheckingTypes _types;
    NSRegularExpression *_links, *_emails, *_phones;
}
+ (instancetype)dataDetectorWithTypes:(NSTextCheckingTypes)types error:(NSError **)error {
    return [[self alloc] initWithTypes:types error:error];
}
- (instancetype)initWithTypes:(NSTextCheckingTypes)types error:(NSError **)error {
    NSTextCheckingTypes supported = NSTextCheckingTypeLink | NSTextCheckingTypePhoneNumber | NSTextCheckingTypeDate |
                                    NSTextCheckingTypeAddress | NSTextCheckingTypeTransitInformation;
    if (!types || (types & ~supported)) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:2048 userInfo:nil];
        return nil;
    }
    if (!(self = [super initWithPattern:@"" options:0 error:error])) return nil;
    _types = types;
    if (types & NSTextCheckingTypeLink) {
        _links = [[NSRegularExpression alloc]
            initWithPattern:@"(?i)\\b(?:(?:[a-z][a-z0-9+.-]*)://[^\\s<>\"]+|www\\.[a-z0-9-]+(?:\\.[a-z0-9-]+)+[^\\s<>\"]*|"
                            @"(?:mailto|tel|sms|facetime):[^\\s<>\"]+)"
                    options:0 error:NULL];
        _emails = [[NSRegularExpression alloc]
            initWithPattern:@"(?i)\\b[a-z0-9._%+-]+@[a-z0-9-]+(?:\\.[a-z0-9-]+)*\\.[a-z]{2,}\\b" options:0 error:NULL];
    }
    if (types & NSTextCheckingTypePhoneNumber)
        _phones = [[NSRegularExpression alloc]
            initWithPattern:@"(?<![\\w+])(?:\\+\\d{1,3}[ .-]?)?(?:\\(\\d{2,4}\\)[ .-]?|\\d{2,4}[ .-])\\d{3,4}[ .-]?\\d{3,4}(?!\\w)"
                    options:0 error:NULL];
    return self;
}
- (NSTextCheckingTypes)checkingTypes { return _types; }

static NSRange trim_link(NSString *s, NSRange r) {
    /* trailing punctuation that ends a sentence is not part of a link */
    while (r.length) {
        unichar c = [s characterAtIndex:NSMaxRange(r) - 1];
        if (c == '.' || c == ',' || c == ';' || c == ':' || c == '!' || c == '?' || c == '\'' || c == '"') r.length--;
        else if (c == ')') {
            NSString *sub = [s substringWithRange:r];
            NSUInteger open = [[sub componentsSeparatedByString:@"("] count], close = [[sub componentsSeparatedByString:@")"] count];
            if (close > open) r.length--;
            else break;
        } else break;
    }
    return r;
}

- (void)enumerateMatchesInString:(NSString *)string
                         options:(NSMatchingOptions)options
                           range:(NSRange)range
                      usingBlock:(void (^)(NSTextCheckingResult *_Nullable, NSMatchingFlags, BOOL *))block {
    NSMutableArray<NSTextCheckingResult *> *found = [NSMutableArray array];
    for (NSTextCheckingResult *m in [_links matchesInString:string options:0 range:range]) {
        NSRange r = trim_link(string, m.range);
        if (!r.length) continue;
        NSString *text = [string substringWithRange:r];
        if ([text.lowercaseString hasPrefix:@"www."]) text = [@"http://" stringByAppendingString:text];
        NSURL *url = [NSURL URLWithString:text];
        if (url) [found addObject:[NSTextCheckingResult linkCheckingResultWithRange:r URL:url]];
    }
    for (NSTextCheckingResult *m in [_emails matchesInString:string options:0 range:range]) {
        NSURL *url = [NSURL URLWithString:[@"mailto:" stringByAppendingString:[string substringWithRange:m.range]]];
        if (url) [found addObject:[NSTextCheckingResult linkCheckingResultWithRange:m.range URL:url]];
    }
    for (NSTextCheckingResult *m in [_phones matchesInString:string options:0 range:range])
        [found addObject:[NSTextCheckingResult phoneNumberCheckingResultWithRange:m.range
                                                                      phoneNumber:[string substringWithRange:m.range]]];
    [found sortUsingComparator:^NSComparisonResult(NSTextCheckingResult *a, NSTextCheckingResult *b) {
        if (a.range.location != b.range.location) return a.range.location < b.range.location ? NSOrderedAscending : NSOrderedDescending;
        return a.range.length > b.range.length ? NSOrderedAscending : a.range.length < b.range.length ? NSOrderedDescending : NSOrderedSame;
    }];
    BOOL stop = NO;
    NSUInteger covered = 0;
    for (NSTextCheckingResult *r in found) {
        if (r.range.location < covered) continue; /* overlaps an earlier result */
        covered = NSMaxRange(r.range);
        block(r, 0, &stop);
        if (stop) return;
    }
    if (options & NSMatchingReportCompletion) block(nil, NSMatchingCompleted, &stop);
}
@end
