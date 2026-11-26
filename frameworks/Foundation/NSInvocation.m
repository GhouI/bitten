/* NSMethodSignature (an Objective-C type encoding, split into the
 * argument and return types with their System V x86-64 classes) and
 * NSInvocation (arguments stored by value, invoked through dx_objc_invoke,
 * which loads registers and stack as the signature says). */

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

extern void dx_objc_invoke(void (*fn)(void), const uint64_t gp[6], const double fp[8], const uint64_t *stack,
                           size_t nstack, uint64_t out[4]);

/* How a value travels: in integer registers, vector registers, or memory. */
enum { K_VOID, K_INT, K_SSE, K_MEMORY, K_MIXED };
typedef struct {
    char *type;      /* the encoding of this value alone */
    size_t size, align;
    int kind;        /* for a struct <= 16 bytes: per eightbyte below */
    int eight[2];    /* K_INT or K_SSE per eightbyte */
} bn_arg;

static const char *skip_qualifiers(const char *t) {
    while (*t && strchr("rnNoORVA", *t)) t++;
    return t;
}
static const char *skip_digits(const char *t) {
    while (*t == '-' || (*t >= '0' && *t <= '9')) t++;
    return t;
}
/* The end of one type in an encoding. */
static const char *type_end(const char *t) {
    t = skip_qualifiers(t);
    switch (*t) {
    case '{': case '(': {
        char open = *t, close = open == '{' ? '}' : ')';
        int depth = 0;
        for (; *t; t++) {
            if (*t == open) depth++;
            else if (*t == close && --depth == 0) return t + 1;
        }
        return t;
    }
    case '[': {
        int depth = 0;
        for (; *t; t++) {
            if (*t == '[') depth++;
            else if (*t == ']' && --depth == 0) return t + 1;
        }
        return t;
    }
    case '^': return type_end(t + 1);
    case '@':
        if (t[1] == '?') return t + 2;
        if (t[1] == '"') {
            const char *q = strchr(t + 2, '"');
            return q ? q + 1 : t + 1;
        }
        return t + 1;
    case 'b': return skip_digits(t + 1);
    case 0: return t;
    default: return t + 1;
    }
}

/* Size, alignment and per-eightbyte classes of a type. */
static void layout(const char *t, size_t *size, size_t *align, int cls[2], size_t base) {
    t = skip_qualifiers(t);
    size_t s = 0, a = 1;
    int c = K_INT;
    switch (*t) {
    case 'c': case 'C': case 'B': s = a = 1; break;
    case 's': case 'S': s = a = 2; break;
    case 'i': case 'I': s = a = 4; break;
    case 'l': case 'L': case 'q': case 'Q': case '@': case '#': case ':': case '*': case '^': case '?': s = a = 8; break;
    case 'f': s = a = 4; c = K_SSE; break;
    case 'd': s = a = 8; c = K_SSE; break;
    case 'D': s = a = 16; c = K_MEMORY; break;
    case 'v': s = 0; a = 1; c = K_VOID; break;
    case '[': {
        const char *p = t + 1;
        size_t n = strtoul(p, NULL, 10);
        p = skip_digits(p);
        size_t es, ea;
        int ec[2] = {K_INT, K_INT};
        layout(p, &es, &ea, ec, base);
        for (size_t i = 0; i < n; i++) {
            size_t off = base + i * es;
            int sub[2] = {K_INT, K_INT};
            layout(p, &es, &ea, sub, off);
        }
        s = es * n;
        a = ea;
        if (cls) {
            for (size_t i = 0; i < n; i++) {
                size_t off = i * es;
                if (off < 16) cls[off / 8] = ec[0];
            }
        }
        *size = s;
        *align = a;
        return;
    }
    case '{': case '(': {
        BOOL uni = *t == '(';
        const char *p = strchr(t, '=');
        const char *end = type_end(t) - 1;
        size_t off = 0, maxa = 1, maxs = 0;
        if (p && p < end) {
            p++;
            while (p < end) {
                if (*p == '"') {  /* a field name */
                    const char *q = strchr(p + 1, '"');
                    p = q ? q + 1 : end;
                    continue;
                }
                size_t fs, fa;
                int fc[2] = {K_INT, K_INT};
                layout(p, &fs, &fa, fc, 0);
                if (!uni) off = (off + fa - 1) / fa * fa;
                if (cls && fs) {
                    /* Each eightbyte is SSE only if every field in it is. */
                    for (size_t b = (uni ? 0 : off) / 8; b <= ((uni ? 0 : off) + fs - 1) / 8 && b < 2; b++) {
                        int fcls = fc[b - (uni ? 0 : off) / 8 < 2 ? b - (uni ? 0 : off) / 8 : 0];
                        if (cls[b] == -1) cls[b] = fcls;
                        else if (fcls == K_INT) cls[b] = K_INT;
                    }
                }
                if (uni) maxs = fs > maxs ? fs : maxs;
                else off += fs;
                if (fa > maxa) maxa = fa;
                p = type_end(p);
            }
        }
        s = uni ? maxs : off;
        a = maxa;
        s = (s + a - 1) / a * a;
        *size = s;
        *align = a;
        return;
    }
    default: s = a = 8; break;
    }
    if (cls) {
        cls[0] = c == K_SSE ? K_SSE : (c == K_VOID ? K_VOID : K_INT);
        cls[1] = cls[0];
    }
    *size = s;
    *align = a;
}

static bn_arg parse_arg(const char *start, const char *end) {
    bn_arg a;
    size_t n = (size_t)(end - start);
    a.type = malloc(n + 1);
    memcpy(a.type, start, n);
    a.type[n] = 0;
    char *d = a.type + (skip_digits(a.type) - a.type);  /* unused: offsets follow types */
    (void)d;
    int cls[2] = {-1, -1};
    layout(a.type, &a.size, &a.align, cls, 0);
    const char *t = skip_qualifiers(a.type);
    if (*t == 'v') a.kind = K_VOID;
    else if (*t == '{' || *t == '(' || *t == '[') {
        if (a.size > 16) a.kind = K_MEMORY;
        else {
            a.eight[0] = cls[0] == -1 ? K_INT : cls[0];
            a.eight[1] = cls[1] == -1 ? K_INT : cls[1];
            a.kind = K_MIXED;
        }
    } else {
        a.kind = cls[0] == K_SSE ? K_SSE : (cls[0] == K_MEMORY ? K_MEMORY : K_INT);
        a.eight[0] = a.eight[1] = a.kind;
    }
    return a;
}

@implementation NSMethodSignature {
    char *_types;
    bn_arg _ret;
    bn_arg *_args;
    NSUInteger _count;
}
+ (NSMethodSignature *)signatureWithObjCTypes:(const char *)types {
    if (!types || !*types) return nil;
    NSMethodSignature *s = [[NSMethodSignature alloc] init];
    s->_types = strdup(types);
    const char *p = types;
    const char *e = type_end(p);
    s->_ret = parse_arg(p, e);
    p = skip_digits(e);
    NSUInteger cap = 8;
    s->_args = calloc(cap, sizeof(bn_arg));
    while (*p) {
        e = type_end(p);
        if (e == p) break;
        if (s->_count == cap) s->_args = realloc(s->_args, (cap *= 2) * sizeof(bn_arg));
        s->_args[s->_count++] = parse_arg(p, e);
        p = skip_digits(e);
    }
    return s;
}
- (void)dealloc {
    for (NSUInteger i = 0; i < _count; i++) free(_args[i].type);
    free(_args);
    free(_ret.type);
    free(_types);
}
- (NSUInteger)numberOfArguments { return _count; }
- (const char *)getArgumentTypeAtIndex:(NSUInteger)i {
    if (i >= _count) [NSException raise:NSInvalidArgumentException format:@"index %lu out of bounds", (unsigned long)i];
    return _args[i].type;
}
- (const char *)methodReturnType { return _ret.type; }
- (NSUInteger)methodReturnLength { return _ret.size; }
- (NSUInteger)frameLength {
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < _count; i++) n += (_args[i].size + 7) / 8 * 8;
    return n;
}
- (BOOL)isOneway { return _types[0] == 'V'; }
- (const bn_arg *)_bn_arg:(NSUInteger)i { return &_args[i]; }
- (const bn_arg *)_bn_ret { return &_ret; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSMethodSignature class]] && !strcmp(((NSMethodSignature *)o)->_types, _types); }
- (NSUInteger)hash { return strlen(_types); }
@end

@implementation NSObject (BittenMethodSignature)
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    Method m = class_getInstanceMethod(object_getClass(self), sel);
    return m ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)] : nil;
}
+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)sel {
    Method m = class_getInstanceMethod(self, sel);
    return m ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)] : nil;
}
@end

@implementation NSInvocation {
    NSMethodSignature *_sig;
    uint8_t **_values;
    uint8_t *_ret;
    BOOL _retained;
    NSMutableArray *_kept;
}
+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig {
    if (!sig) [NSException raise:NSInvalidArgumentException format:@"+[NSInvocation invocationWithMethodSignature:]: nil signature"];
    NSInvocation *inv = [[NSInvocation alloc] init];
    inv->_sig = sig;
    NSUInteger n = sig.numberOfArguments;
    inv->_values = calloc(n ? n : 1, sizeof(uint8_t *));
    for (NSUInteger i = 0; i < n; i++) inv->_values[i] = calloc(1, [sig _bn_arg:i]->size + 16);
    inv->_ret = calloc(1, sig.methodReturnLength + 32);
    return inv;
}
- (void)dealloc {
    NSUInteger n = _sig.numberOfArguments;
    for (NSUInteger i = 0; i < n; i++) free(_values[i]);
    free(_values);
    free(_ret);
}
- (NSMethodSignature *)methodSignature { return _sig; }
- (void)retainArguments {
    if (_retained) return;
    _retained = YES;
    _kept = [NSMutableArray array];
    for (NSUInteger i = 0; i < _sig.numberOfArguments; i++) {
        const char *t = [_sig getArgumentTypeAtIndex:i];
        if (*t == '@') {
            id o = *(__unsafe_unretained id *)(void *)_values[i];
            if (o) [_kept addObject:o];
        }
    }
}
- (BOOL)argumentsRetained { return _retained; }
- (id)target { return _sig.numberOfArguments ? *(__unsafe_unretained id *)(void *)_values[0] : nil; }
- (void)setTarget:(id)t {
    if (!_sig.numberOfArguments) return;
    *(__unsafe_unretained id *)(void *)_values[0] = t;
    if (_retained && t) [_kept addObject:t];
}
- (SEL)selector { return _sig.numberOfArguments > 1 ? *(SEL *)_values[1] : NULL; }
- (void)setSelector:(SEL)s {
    if (_sig.numberOfArguments > 1) *(SEL *)_values[1] = s;
}
- (void)getArgument:(void *)buf atIndex:(NSInteger)i {
    if (i < 0 || (NSUInteger)i >= _sig.numberOfArguments) [NSException raise:NSRangeException format:@"bad argument index"];
    memcpy(buf, _values[i], [_sig _bn_arg:i]->size);
}
- (void)setArgument:(void *)buf atIndex:(NSInteger)i {
    if (i < 0 || (NSUInteger)i >= _sig.numberOfArguments) [NSException raise:NSRangeException format:@"bad argument index"];
    memcpy(_values[i], buf, [_sig _bn_arg:i]->size);
    if (_retained && *[_sig getArgumentTypeAtIndex:i] == '@') {
        id o = *(__unsafe_unretained id *)buf;
        if (o) [_kept addObject:o];
    }
}
- (void)getReturnValue:(void *)buf { memcpy(buf, _ret, _sig.methodReturnLength); }
- (void)setReturnValue:(void *)buf { memcpy(_ret, buf, _sig.methodReturnLength); }
- (void)invokeWithTarget:(id)target {
    [self setTarget:target];
    [self invoke];
}
- (void)invoke {
    id target = self.target;
    if (!target) return;
    const bn_arg *r = [_sig _bn_ret];
    uint64_t gp[6] = {0}, out[4] = {0};
    double fp[8] = {0};
    NSUInteger ngp = 0, nfp = 0, nstack = 0, cap = 16;
    uint64_t *stack = calloc(cap, sizeof(uint64_t));
    BOOL sret = r->kind == K_MEMORY;
    if (sret) gp[ngp++] = (uint64_t)(uintptr_t)_ret;
    for (NSUInteger i = 0; i < _sig.numberOfArguments; i++) {
        const bn_arg *a = [_sig _bn_arg:i];
        size_t words = (a->size + 7) / 8;
        int need_gp = 0, need_fp = 0;
        if (a->kind == K_MIXED)
            for (size_t w = 0; w < words && w < 2; w++) {
                if (a->eight[w] == K_SSE) need_fp++;
                else need_gp++;
            }
        else if (a->kind == K_SSE) need_fp = 1;
        else if (a->kind == K_INT) need_gp = 1;
        BOOL in_regs = a->kind != K_MEMORY && ngp + need_gp <= 6 && nfp + need_fp <= 8;
        if (in_regs) {
            for (size_t w = 0; w < words && w < 2; w++) {
                uint64_t word = 0;
                memcpy(&word, _values[i] + 8 * w, a->size - 8 * w < 8 ? a->size - 8 * w : 8);
                int k = a->kind == K_MIXED ? a->eight[w] : a->kind;
                if (k == K_SSE) {
                    double d;
                    if (a->size - 8 * w == 4 || (a->kind == K_SSE && a->size == 4)) {
                        memcpy(&d, &word, 8);  /* low 32 bits carry the float */
                    } else {
                        memcpy(&d, &word, 8);
                    }
                    fp[nfp++] = d;
                } else {
                    gp[ngp++] = word;
                }
            }
        } else {
            if (nstack + words > cap) stack = realloc(stack, (cap = (nstack + words) * 2) * sizeof(uint64_t));
            memset(stack + nstack, 0, words * 8);
            memcpy(stack + nstack, _values[i], a->size);
            nstack += words;
        }
    }
    /* A struct returned in memory takes its buffer in rdi, ahead of self:
     * the _stret entry point expects that. */
    IMP fn = sret ? (IMP)objc_msgSend_stret : (IMP)objc_msgSend;
    dx_objc_invoke((void (*)(void))fn, gp, fp, stack, nstack, out);
    free(stack);
    if (!sret && r->kind != K_VOID) {
        uint8_t tmp[16];
        int k0 = r->kind == K_MIXED ? r->eight[0] : r->kind, k1 = r->kind == K_MIXED ? r->eight[1] : r->kind;
        int ig = 0, ifp = 0;
        uint64_t w0 = k0 == K_SSE ? out[2 + ifp++] : out[ig++];
        uint64_t w1 = k1 == K_SSE ? out[2 + ifp++] : out[ig++];
        memcpy(tmp, &w0, 8);
        memcpy(tmp + 8, &w1, 8);
        memcpy(_ret, tmp, r->size < 16 ? r->size : 16);
    }
}
@end
