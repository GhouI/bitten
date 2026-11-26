/* Public-key primitives behind CryptoKit (frameworks/CryptoKit): ECDSA and
 * ECDH on P-256, P-384 and P-521, X25519 and Ed25519, and reading EC private
 * keys from PEM. Written for this project from the published standards
 * (SEC 1, FIPS 186-4, RFC 7748, RFC 8032).
 *
 * Arithmetic: fixed-size integers of 32-bit limbs, Montgomery multiplication
 * for every odd modulus (field primes and group orders alike), Jacobian
 * coordinates for the NIST curves and extended coordinates for Ed25519.
 * Correct, small and readable; not constant-time. Constants that can be
 * derived (Ed25519's d, base point and sqrt(-1)) are computed at first use
 * rather than typed in, and the NIST parameters are checked at first use
 * (G on the curve, n*G = infinity).
 *
 * The interface is private to bitten: plain pointers and integers, called
 * from Swift through @_silgen_name. Every function returns 0 on success. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>

#include "dx.h"

#define MAXL 18                    /* limbs: 576 bits, enough for P-521 */

typedef struct {
    int n;                         /* limbs in use */
    uint32_t m[MAXL];              /* the modulus */
    uint32_t minv;                 /* -m^-1 mod 2^32 */
    uint32_t r2[MAXL];             /* R^2 mod m, R = 2^(32n) */
    uint32_t one[MAXL];            /* R mod m: 1 in Montgomery form */
} mod_t;

typedef uint32_t bn[MAXL];

/* ---- plain multi-limb arithmetic ------------------------------------- */

static int bn_cmp(const uint32_t *a, const uint32_t *b, int n) {
    for (int i = n - 1; i >= 0; i--)
        if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    return 0;
}

static int bn_is_zero(const uint32_t *a, int n) {
    uint32_t x = 0;
    for (int i = 0; i < n; i++) x |= a[i];
    return x == 0;
}

static uint32_t bn_add(uint32_t *r, const uint32_t *a, const uint32_t *b, int n) {
    uint64_t c = 0;
    for (int i = 0; i < n; i++) { c += (uint64_t)a[i] + b[i]; r[i] = (uint32_t)c; c >>= 32; }
    return (uint32_t)c;
}

static uint32_t bn_sub(uint32_t *r, const uint32_t *a, const uint32_t *b, int n) {
    int64_t c = 0;
    for (int i = 0; i < n; i++) { c += (int64_t)a[i] - b[i]; r[i] = (uint32_t)c; c >>= 32; }
    return (uint32_t)(c & 1);
}

static void bn_copy(uint32_t *r, const uint32_t *a, int n) { memcpy(r, a, (size_t)n * 4); }
static void bn_zero(uint32_t *r, int n) { memset(r, 0, (size_t)n * 4); }
static int bn_bit(const uint32_t *a, int i) { return (a[i / 32] >> (i % 32)) & 1; }

static int bn_bits(const uint32_t *a, int n) {
    for (int i = n * 32 - 1; i >= 0; i--) if (bn_bit(a, i)) return i + 1;
    return 0;
}

/* Big-endian bytes <-> limbs. */
static void bn_from_be(uint32_t *r, int n, const uint8_t *p, size_t len) {
    bn_zero(r, n);
    for (size_t i = 0; i < len && i < (size_t)n * 4; i++)
        r[i / 4] |= (uint32_t)p[len - 1 - i] << (8 * (i % 4));
}

static void bn_to_be(uint8_t *p, size_t len, const uint32_t *a, int n) {
    for (size_t i = 0; i < len; i++)
        p[len - 1 - i] = i < (size_t)n * 4 ? (uint8_t)(a[i / 4] >> (8 * (i % 4))) : 0;
}

static void bn_from_le(uint32_t *r, int n, const uint8_t *p, size_t len) {
    bn_zero(r, n);
    for (size_t i = 0; i < len && i < (size_t)n * 4; i++) r[i / 4] |= (uint32_t)p[i] << (8 * (i % 4));
}

static void bn_to_le(uint8_t *p, size_t len, const uint32_t *a, int n) {
    for (size_t i = 0; i < len; i++) p[i] = i < (size_t)n * 4 ? (uint8_t)(a[i / 4] >> (8 * (i % 4))) : 0;
}

static void bn_from_hex(uint32_t *r, int n, const char *hex) {
    uint8_t buf[MAXL * 4];
    size_t len = strlen(hex) / 2;
    for (size_t i = 0; i < len; i++) {
        unsigned v;
        char t[3] = {hex[2 * i], hex[2 * i + 1], 0};
        v = (unsigned)strtoul(t, NULL, 16);
        buf[i] = (uint8_t)v;
    }
    bn_from_be(r, n, buf, len);
}

/* ---- modular arithmetic ------------------------------------------------ */

static void mod_add(uint32_t *r, const uint32_t *a, const uint32_t *b, const mod_t *M) {
    uint32_t c = bn_add(r, a, b, M->n);
    if (c || bn_cmp(r, M->m, M->n) >= 0) bn_sub(r, r, M->m, M->n);
}

static void mod_sub(uint32_t *r, const uint32_t *a, const uint32_t *b, const mod_t *M) {
    if (bn_sub(r, a, b, M->n)) bn_add(r, r, M->m, M->n);
}

/* r = a*b/R mod m (CIOS). r may alias a or b. */
static void mont_mul(uint32_t *r, const uint32_t *a, const uint32_t *b, const mod_t *M) {
    int n = M->n;
    uint32_t t[MAXL + 2] = {0};
    for (int i = 0; i < n; i++) {
        uint64_t c = 0;
        for (int j = 0; j < n; j++) {
            c += (uint64_t)t[j] + (uint64_t)a[j] * b[i];
            t[j] = (uint32_t)c; c >>= 32;
        }
        c += t[n]; t[n] = (uint32_t)c; t[n + 1] = (uint32_t)(c >> 32);
        uint32_t m = t[0] * M->minv;
        c = (uint64_t)t[0] + (uint64_t)m * M->m[0];
        c >>= 32;
        for (int j = 1; j < n; j++) {
            c += (uint64_t)t[j] + (uint64_t)m * M->m[j];
            t[j - 1] = (uint32_t)c; c >>= 32;
        }
        c += t[n]; t[n - 1] = (uint32_t)c; c >>= 32;
        t[n] = t[n + 1] + (uint32_t)c;
    }
    if (t[n] || bn_cmp(t, M->m, n) >= 0) bn_sub(t, t, M->m, n);
    bn_copy(r, t, n);
}

static void mod_init(mod_t *M, int n, const uint32_t *m) {
    M->n = n;
    bn_zero(M->m, MAXL);
    bn_copy(M->m, m, n);
    uint32_t inv = 1;                                  /* Newton: m^-1 mod 2^32 */
    for (int i = 0; i < 5; i++) inv *= 2 - M->m[0] * inv;
    M->minv = (uint32_t)-inv;
    bn x = {0};
    x[0] = 1;
    if (bn_cmp(x, M->m, n) >= 0) bn_sub(x, x, M->m, n);
    for (int i = 0; i < 32 * n; i++) mod_add(x, x, x, M);   /* R mod m */
    bn_copy(M->one, x, n);
    for (int i = 0; i < 32 * n; i++) mod_add(x, x, x, M);   /* R^2 mod m */
    bn_copy(M->r2, x, n);
}

static void to_mont(uint32_t *r, const uint32_t *a, const mod_t *M) { mont_mul(r, a, M->r2, M); }

static void from_mont(uint32_t *r, const uint32_t *a, const mod_t *M) {
    bn one = {0};
    one[0] = 1;
    mont_mul(r, a, one, M);
}

/* r = a^e (a in Montgomery form, e plain). */
static void mod_pow(uint32_t *r, const uint32_t *a, const uint32_t *e, const mod_t *M) {
    bn acc, base;
    bn_copy(acc, M->one, M->n);
    bn_copy(base, a, M->n);
    for (int i = bn_bits(e, M->n) - 1; i >= 0; i--) {
        mont_mul(acc, acc, acc, M);
        if (bn_bit(e, i)) mont_mul(acc, acc, base, M);
    }
    bn_copy(r, acc, M->n);
}

/* r = a^-1 for prime m (Fermat). */
static void mod_inv(uint32_t *r, const uint32_t *a, const mod_t *M) {
    bn e, two = {0};
    two[0] = 2;
    bn_sub(e, M->m, two, M->n);
    mod_pow(r, a, e, M);
}

/* r = (big-endian byte string) mod m, plain form. */
static void mod_reduce_be(uint32_t *r, const uint8_t *p, size_t len, const mod_t *M) {
    bn acc = {0}, b = {0};
    for (size_t i = 0; i < len; i++) {
        for (int k = 0; k < 8; k++) mod_add(acc, acc, acc, M);
        b[0] = p[i];
        mod_add(acc, acc, b, M);
    }
    bn_copy(r, acc, M->n);
}

static void mod_reduce_le(uint32_t *r, const uint8_t *p, size_t len, const mod_t *M) {
    uint8_t be[128];
    for (size_t i = 0; i < len; i++) be[i] = p[len - 1 - i];
    mod_reduce_be(r, be, len, M);
}

static int random_bytes(void *p, size_t n) {
    uint8_t *q = p;
    while (n) {
        ssize_t got = getrandom(q, n, 0);
        if (got <= 0) return -1;
        q += got; n -= (size_t)got;
    }
    return 0;
}

/* ---- NIST prime curves (a = -3) --------------------------------------- */

typedef struct {
    int bytes;                     /* field and scalar size in bytes */
    mod_t p, q;                    /* field, group order */
    bn b, gx, gy;                  /* Montgomery form (field) */
} curve_t;

typedef struct { bn x, y, z; } jpt;       /* Jacobian, z = 0 is infinity */

static const struct { int bytes, limbs; const char *p, *b, *gx, *gy, *n; } NIST[3] = {
    {32, 8,
     "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff",
     "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b",
     "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296",
     "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5",
     "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"},
    {48, 12,
     "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff",
     "b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef",
     "aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7",
     "3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f",
     "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973"},
    {66, 17,
     "01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
     "0051953eb9618e1c9a1f929a21a0b68540eea2da725b99b315f3b8b489918ef109e156193951ec7e937b1652c0bd3bb1bf073573df883d2c34f1ef451fd46b503f00",
     "00c6858e06b70404e9cd9e3ecb662395b4429c648139053fb521f828af606b4d3dbaa14b5e77efe75928fe1dc127a2ffa8de3348b3c1856a429bf97e7e31c2e5bd66",
     "011839296a789a3bc0045c8a5fb42c7d1bd998f54449579b446817afbd17273e662c97ee72995ef42640c550b9013fad0761353c7086a272c24088be94769fd16650",
     "01fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffa51868783bf2f966b7fcc0148f709a5d03bb5c9b8899c47aebb6fb71e91386409"},
};

static curve_t curves[3];
static int curve_state[3];         /* 0 unset, 1 ok, -1 failed self-check */

static void jdouble(jpt *r, const jpt *a, const curve_t *C) {
    const mod_t *M = &C->p;
    if (bn_is_zero(a->z, M->n)) { *r = *a; return; }
    bn delta, gamma, beta, alpha, t1, t2, x3, y3, z3;
    mont_mul(delta, a->z, a->z, M);
    mont_mul(gamma, a->y, a->y, M);
    mont_mul(beta, a->x, gamma, M);
    mod_sub(t1, a->x, delta, M);
    mod_add(t2, a->x, delta, M);
    mont_mul(alpha, t1, t2, M);
    mod_add(t1, alpha, alpha, M);
    mod_add(alpha, t1, alpha, M);                        /* 3(x-d)(x+d) */
    mont_mul(x3, alpha, alpha, M);
    mod_add(t1, beta, beta, M);                          /* 2b */
    mod_add(t1, t1, t1, M);                              /* 4b */
    mod_add(t2, t1, t1, M);                              /* 8b */
    mod_sub(x3, x3, t2, M);
    mod_add(z3, a->y, a->z, M);
    mont_mul(z3, z3, z3, M);
    mod_sub(z3, z3, gamma, M);
    mod_sub(z3, z3, delta, M);
    mod_sub(t1, t1, x3, M);
    mont_mul(y3, alpha, t1, M);
    mont_mul(t2, gamma, gamma, M);
    mod_add(t2, t2, t2, M);
    mod_add(t2, t2, t2, M);
    mod_add(t2, t2, t2, M);                              /* 8 gamma^2 */
    mod_sub(y3, y3, t2, M);
    bn_copy(r->x, x3, M->n); bn_copy(r->y, y3, M->n); bn_copy(r->z, z3, M->n);
}

static void jadd(jpt *r, const jpt *a, const jpt *b, const curve_t *C) {
    const mod_t *M = &C->p;
    int n = M->n;
    if (bn_is_zero(a->z, n)) { *r = *b; return; }
    if (bn_is_zero(b->z, n)) { *r = *a; return; }
    bn z1z1, z2z2, u1, u2, s1, s2, h, i, j, rr, v, t, x3, y3, z3;
    mont_mul(z1z1, a->z, a->z, M);
    mont_mul(z2z2, b->z, b->z, M);
    mont_mul(u1, a->x, z2z2, M);
    mont_mul(u2, b->x, z1z1, M);
    mont_mul(s1, a->y, b->z, M); mont_mul(s1, s1, z2z2, M);
    mont_mul(s2, b->y, a->z, M); mont_mul(s2, s2, z1z1, M);
    mod_sub(h, u2, u1, M);
    mod_sub(rr, s2, s1, M);
    if (bn_is_zero(h, n)) {
        if (bn_is_zero(rr, n)) { jdouble(r, a, C); return; }
        bn_zero(r->x, n); bn_zero(r->y, n); bn_zero(r->z, n);
        return;
    }
    mod_add(i, h, h, M); mont_mul(i, i, i, M);
    mont_mul(j, h, i, M);
    mod_add(rr, rr, rr, M);
    mont_mul(v, u1, i, M);
    mont_mul(x3, rr, rr, M);
    mod_sub(x3, x3, j, M);
    mod_sub(x3, x3, v, M);
    mod_sub(x3, x3, v, M);
    mod_sub(t, v, x3, M);
    mont_mul(y3, rr, t, M);
    mont_mul(t, s1, j, M);
    mod_add(t, t, t, M);
    mod_sub(y3, y3, t, M);
    mod_add(z3, a->z, b->z, M);
    mont_mul(z3, z3, z3, M);
    mod_sub(z3, z3, z1z1, M);
    mod_sub(z3, z3, z2z2, M);
    mont_mul(z3, z3, h, M);
    bn_copy(r->x, x3, n); bn_copy(r->y, y3, n); bn_copy(r->z, z3, n);
}

/* r = k*P, k plain (n limbs of the order). */
static void jmul(jpt *r, const jpt *P, const uint32_t *k, int kn, const curve_t *C) {
    jpt acc;
    int n = C->p.n;
    bn_zero(acc.x, n); bn_zero(acc.y, n); bn_zero(acc.z, n);
    for (int i = bn_bits(k, kn) - 1; i >= 0; i--) {
        jdouble(&acc, &acc, C);
        if (bn_bit(k, i)) jadd(&acc, &acc, P, C);
    }
    *r = acc;
}

/* Affine coordinates (plain form). Returns -1 for infinity. */
static int jaffine(uint32_t *x, uint32_t *y, const jpt *P, const curve_t *C) {
    const mod_t *M = &C->p;
    if (bn_is_zero(P->z, M->n)) return -1;
    bn zi, zi2, t;
    mod_inv(zi, P->z, M);
    mont_mul(zi2, zi, zi, M);
    mont_mul(t, P->x, zi2, M); from_mont(x, t, M);
    mont_mul(t, P->y, zi2, M); mont_mul(t, t, zi, M); from_mont(y, t, M);
    return 0;
}

/* Is the affine point (Montgomery x, y) on the curve? */
static int on_curve(const uint32_t *x, const uint32_t *y, const curve_t *C) {
    const mod_t *M = &C->p;
    bn l, r, t;
    mont_mul(l, y, y, M);
    mont_mul(r, x, x, M);
    mont_mul(r, r, x, M);
    mod_add(t, x, x, M);
    mod_add(t, t, x, M);
    mod_sub(r, r, t, M);
    mod_add(r, r, C->b, M);
    return bn_cmp(l, r, M->n) == 0;
}

static const curve_t *curve(int id) {
    if (id < 0 || id > 2) return NULL;
    if (curve_state[id]) return curve_state[id] > 0 ? &curves[id] : NULL;
    curve_t *C = &curves[id];
    int n = NIST[id].limbs;
    bn t;
    C->bytes = NIST[id].bytes;
    bn_from_hex(t, n, NIST[id].p); mod_init(&C->p, n, t);
    bn_from_hex(t, n, NIST[id].n); mod_init(&C->q, n, t);
    bn_from_hex(t, n, NIST[id].b); to_mont(C->b, t, &C->p);
    bn_from_hex(t, n, NIST[id].gx); to_mont(C->gx, t, &C->p);
    bn_from_hex(t, n, NIST[id].gy); to_mont(C->gy, t, &C->p);
    /* Self-check: G on the curve and n*G = infinity. */
    jpt G, R;
    bn_copy(G.x, C->gx, n); bn_copy(G.y, C->gy, n); bn_copy(G.z, C->p.one, n);
    jmul(&R, &G, C->q.m, n, C);
    curve_state[id] = on_curve(C->gx, C->gy, C) && bn_is_zero(R.z, n) ? 1 : -1;
    if (curve_state[id] < 0) dx_log(0, "cryptokit: curve %d failed its self-check", id);
    return curve_state[id] > 0 ? C : NULL;
}

static void base_point(jpt *G, const curve_t *C) {
    int n = C->p.n;
    bn_copy(G->x, C->gx, n); bn_copy(G->y, C->gy, n); bn_copy(G->z, C->p.one, n);
}

/* Read x||y (2*bytes, big-endian) into a Jacobian point; checks the curve. */
static int load_pub(jpt *P, const uint8_t *pub, const curve_t *C) {
    int n = C->p.n;
    bn x, y;
    bn_from_be(x, n, pub, (size_t)C->bytes);
    bn_from_be(y, n, pub + C->bytes, (size_t)C->bytes);
    if (bn_cmp(x, C->p.m, n) >= 0 || bn_cmp(y, C->p.m, n) >= 0) return -1;
    to_mont(P->x, x, &C->p); to_mont(P->y, y, &C->p);
    bn_copy(P->z, C->p.one, n);
    return on_curve(P->x, P->y, C) ? 0 : -1;
}

static int load_priv(uint32_t *d, const uint8_t *priv, const curve_t *C) {
    int n = C->q.n;
    bn_from_be(d, n, priv, (size_t)C->bytes);
    if (bn_is_zero(d, n) || bn_cmp(d, C->q.m, n) >= 0) return -1;
    return 0;
}

static int store_pub(uint8_t *pub, const jpt *P, const curve_t *C) {
    bn x, y;
    if (jaffine(x, y, P, C)) return -1;
    bn_to_be(pub, (size_t)C->bytes, x, C->p.n);
    bn_to_be(pub + C->bytes, (size_t)C->bytes, y, C->p.n);
    return 0;
}

int bitten_ck_ec_pub(int id, const uint8_t *priv, uint8_t *pub) {
    const curve_t *C = curve(id);
    bn d;
    jpt G, Q;
    if (!C || load_priv(d, priv, C)) return -1;
    base_point(&G, C);
    jmul(&Q, &G, d, C->q.n, C);
    return store_pub(pub, &Q, C);
}
DX_EXPORT("_bitten_ck_ec_pub", bitten_ck_ec_pub);

/* A fresh key. With compact, the public y is the smaller of y and p-y
 * (negating the key when it is not), as CryptoKit's compactRepresentable. */
int bitten_ck_ec_keygen(int id, int compact, uint8_t *priv, uint8_t *pub) {
    const curve_t *C = curve(id);
    if (!C) return -1;
    int n = C->q.n;
    uint8_t buf[MAXL * 4];
    bn d;
    for (;;) {
        if (random_bytes(buf, (size_t)C->bytes)) return -1;
        if (id == 2) buf[0] &= 1;                        /* 521 bits */
        bn_from_be(d, n, buf, (size_t)C->bytes);
        if (!bn_is_zero(d, n) && bn_cmp(d, C->q.m, n) < 0) break;
    }
    bn_to_be(priv, (size_t)C->bytes, d, n);
    if (bitten_ck_ec_pub(id, priv, pub)) return -1;
    if (compact) {
        bn y, py;
        bn_from_be(y, n, pub + C->bytes, (size_t)C->bytes);
        bn_sub(py, C->p.m, y, n);
        if (bn_cmp(py, y, n) < 0) {
            bn_sub(d, C->q.m, d, n);
            bn_to_be(priv, (size_t)C->bytes, d, n);
            bn_to_be(pub + C->bytes, (size_t)C->bytes, py, n);
        }
    }
    return 0;
}
DX_EXPORT("_bitten_ck_ec_keygen", bitten_ck_ec_keygen);

int bitten_ck_ec_check_pub(int id, const uint8_t *pub) {
    const curve_t *C = curve(id);
    jpt P;
    return C && !load_pub(&P, pub, C) ? 0 : -1;
}
DX_EXPORT("_bitten_ck_ec_check_pub", bitten_ck_ec_check_pub);

/* The hash as an integer mod n: its leftmost bits(n) bits (SEC 1, 4.1.3). */
static void hash_to_z(uint32_t *z, const uint8_t *h, size_t hlen, const curve_t *C) {
    int n = C->q.n, nbits = bn_bits(C->q.m, n);
    bn e;
    if (hlen * 8 > (size_t)nbits) {
        bn_from_be(e, n, h, (nbits + 7) / 8);
        int extra = (int)(((nbits + 7) / 8) * 8 - nbits);
        for (int k = 0; k < extra; k++) {                 /* shift right */
            for (int i = 0; i < n; i++) e[i] = (e[i] >> 1) | (i + 1 < n ? e[i + 1] << 31 : 0);
        }
    } else {
        bn_from_be(e, n, h, hlen);
    }
    if (bn_cmp(e, C->q.m, n) >= 0) bn_sub(e, e, C->q.m, n);
    bn_copy(z, e, n);
}

int bitten_ck_ecdsa_sign(int id, const uint8_t *priv, const uint8_t *hash, size_t hlen, uint8_t *sig) {
    const curve_t *C = curve(id);
    if (!C) return -1;
    const mod_t *Q = &C->q;
    int n = Q->n;
    bn d, z, k, r, s, x, y, t, km;
    jpt G, R;
    uint8_t buf[MAXL * 4];
    if (load_priv(d, priv, C)) return -1;
    hash_to_z(z, hash, hlen, C);
    base_point(&G, C);
    for (;;) {
        if (random_bytes(buf, (size_t)C->bytes)) return -1;
        if (id == 2) buf[0] &= 1;
        bn_from_be(k, n, buf, (size_t)C->bytes);
        if (bn_is_zero(k, n) || bn_cmp(k, Q->m, n) >= 0) continue;
        jmul(&R, &G, k, n, C);
        if (jaffine(x, y, &R, C)) continue;
        bn_copy(r, x, n);
        if (bn_cmp(r, Q->m, n) >= 0) bn_sub(r, r, Q->m, n);
        if (bn_is_zero(r, n)) continue;
        /* s = k^-1 (z + r d) mod n */
        bn rm, dm, zm;
        to_mont(rm, r, Q); to_mont(dm, d, Q); to_mont(zm, z, Q);
        mont_mul(t, rm, dm, Q);
        mod_add(t, t, zm, Q);
        to_mont(km, k, Q);
        mod_inv(km, km, Q);
        mont_mul(t, t, km, Q);
        from_mont(s, t, Q);
        if (bn_is_zero(s, n)) continue;
        break;
    }
    bn_to_be(sig, (size_t)C->bytes, r, n);
    bn_to_be(sig + C->bytes, (size_t)C->bytes, s, n);
    return 0;
}
DX_EXPORT("_bitten_ck_ecdsa_sign", bitten_ck_ecdsa_sign);

int bitten_ck_ecdsa_verify(int id, const uint8_t *pub, const uint8_t *hash, size_t hlen, const uint8_t *sig) {
    const curve_t *C = curve(id);
    if (!C) return -1;
    const mod_t *Q = &C->q;
    int n = Q->n;
    bn r, s, z, w, u1, u2, t, x, y;
    jpt G, P, A, B, X;
    if (load_pub(&P, pub, C)) return -1;
    bn_from_be(r, n, sig, (size_t)C->bytes);
    bn_from_be(s, n, sig + C->bytes, (size_t)C->bytes);
    if (bn_is_zero(r, n) || bn_is_zero(s, n) || bn_cmp(r, Q->m, n) >= 0 || bn_cmp(s, Q->m, n) >= 0)
        return -1;
    hash_to_z(z, hash, hlen, C);
    to_mont(w, s, Q); mod_inv(w, w, Q);
    to_mont(t, z, Q); mont_mul(t, t, w, Q); from_mont(u1, t, Q);
    to_mont(t, r, Q); mont_mul(t, t, w, Q); from_mont(u2, t, Q);
    base_point(&G, C);
    jmul(&A, &G, u1, n, C);
    jmul(&B, &P, u2, n, C);
    jadd(&X, &A, &B, C);
    if (jaffine(x, y, &X, C)) return -1;
    if (bn_cmp(x, Q->m, n) >= 0) bn_sub(x, x, Q->m, n);
    return bn_cmp(x, r, n) == 0 ? 0 : -1;
}
DX_EXPORT("_bitten_ck_ecdsa_verify", bitten_ck_ecdsa_verify);

/* ECDH: the x coordinate of d*Q. */
int bitten_ck_ecdh(int id, const uint8_t *priv, const uint8_t *pub, uint8_t *out) {
    const curve_t *C = curve(id);
    bn d, x, y;
    jpt P, S;
    if (!C || load_priv(d, priv, C) || load_pub(&P, pub, C)) return -1;
    jmul(&S, &P, d, C->q.n, C);
    if (jaffine(x, y, &S, C)) return -1;
    bn_to_be(out, (size_t)C->bytes, x, C->p.n);
    return 0;
}
DX_EXPORT("_bitten_ck_ecdh", bitten_ck_ecdh);

/* ---- PEM: EC private keys (SEC 1 "EC PRIVATE KEY", or PKCS #8 "PRIVATE
 * KEY", which wraps the SEC 1 structure) ------------------------------- */

static int b64val(int c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

int bitten_ck_pem_ec_private(int id, const char *pem, size_t len, uint8_t *priv) {
    const curve_t *C = curve(id);
    if (!C) return -1;
    const char *body = memmem(pem, len, "-----BEGIN", 10);
    if (!body) return -1;
    const char *eol = memchr(body, '\n', len - (size_t)(body - pem));
    const char *end = eol ? memmem(eol, len - (size_t)(eol - pem), "-----END", 8) : NULL;
    if (!eol || !end) return -1;
    size_t cap = (size_t)(end - eol), n = 0;
    uint8_t *der = malloc(cap);
    if (!der) return -1;
    unsigned acc = 0;
    int bits = 0;
    for (const char *p = eol; p < end; p++) {
        int v = b64val((unsigned char)*p);
        if (v < 0) continue;
        acc = (acc << 6) | (unsigned)v; bits += 6;
        if (bits >= 8) { bits -= 8; der[n++] = (uint8_t)(acc >> bits); }
    }
    /* ECPrivateKey ::= SEQUENCE { version INTEGER 1, privateKey OCTET
     * STRING, ... }: find "02 01 01 04 <len>" with len = the field size. */
    int rc = -1;
    for (size_t i = 0; i + 5 + (size_t)C->bytes <= n; i++) {
        if (der[i] == 0x02 && der[i + 1] == 0x01 && der[i + 2] == 0x01 && der[i + 3] == 0x04 &&
            der[i + 4] == C->bytes) {
            memcpy(priv, der + i + 5, (size_t)C->bytes);
            bn d;
            rc = load_priv(d, priv, C);
            break;
        }
    }
    explicit_bzero(der, n);
    free(der);
    return rc;
}
DX_EXPORT("_bitten_ck_pem_ec_private", bitten_ck_pem_ec_private);

/* ---- Curve25519: X25519 (RFC 7748) and Ed25519 (RFC 8032) -------------- */

static mod_t F25, L25;             /* p = 2^255 - 19, l = 2^252 + ... */
static bn ED_D, ED_D2, SQRTM1, ED_BX, ED_BY;   /* Montgomery form */
static int c25_state;

typedef struct { bn x, y, z, t; } ept;

static void fe_from_int(uint32_t *r, uint32_t v) {
    bn t = {0};
    t[0] = v;
    to_mont(r, t, &F25);
}

static int ed_decode(ept *P, const uint8_t *s);

static int c25_init(void) {
    if (c25_state) return c25_state > 0 ? 0 : -1;
    bn t, num, den;
    bn_from_hex(t, 8, "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed");
    mod_init(&F25, 8, t);
    bn_from_hex(t, 8, "1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed");
    mod_init(&L25, 8, t);
    /* d = -121665/121666 */
    fe_from_int(num, 121665);
    bn_zero(t, 8);
    mod_sub(num, t, num, &F25);
    fe_from_int(den, 121666);
    mod_inv(den, den, &F25);
    mont_mul(ED_D, num, den, &F25);
    mod_add(ED_D2, ED_D, ED_D, &F25);
    /* sqrt(-1) = 2^((p-1)/4) */
    bn e, two;
    bn_copy(e, F25.m, 8);
    for (int k = 0; k < 2; k++)
        for (int i = 0; i < 8; i++) e[i] = (e[i] >> 1) | (i < 7 ? e[i + 1] << 31 : 0);
    fe_from_int(two, 2);
    mod_pow(SQRTM1, two, e, &F25);
    /* B: y = 4/5, x even */
    uint8_t enc[32];
    fe_from_int(num, 4);
    fe_from_int(den, 5);
    mod_inv(den, den, &F25);
    mont_mul(t, num, den, &F25);
    bn y;
    from_mont(y, t, &F25);
    bn_to_le(enc, 32, y, 8);
    ept B;
    c25_state = 1;                                   /* ed_decode needs it */
    if (ed_decode(&B, enc)) { c25_state = -1; return -1; }
    bn_copy(ED_BX, B.x, 8);
    bn_copy(ED_BY, B.y, 8);
    return 0;
}

/* X25519: Montgomery ladder. u == NULL means the base point 9. */
int bitten_ck_x25519(const uint8_t *scalar, const uint8_t *u, uint8_t *out) {
    if (c25_init()) return -1;
    const mod_t *M = &F25;
    uint8_t k[32], ub[32] = {9};
    memcpy(k, scalar, 32);
    k[0] &= 248; k[31] &= 127; k[31] |= 64;
    if (u) memcpy(ub, u, 32);
    ub[31] &= 127;
    bn x1, x2, z2, x3, z3, a24, A, AA, B, BB, E, Cc, D, DA, CB, t;
    bn_from_le(t, 8, ub, 32);
    if (bn_cmp(t, M->m, 8) >= 0) bn_sub(t, t, M->m, 8);
    to_mont(x1, t, M);
    bn_copy(x2, M->one, 8); bn_zero(z2, 8);
    bn_copy(x3, x1, 8); bn_copy(z3, M->one, 8);
    fe_from_int(a24, 121665);
    int swap = 0;
    for (int i = 254; i >= 0; i--) {
        int bit = (k[i / 8] >> (i % 8)) & 1;
        if (swap ^ bit) {
            bn_copy(t, x2, 8); bn_copy(x2, x3, 8); bn_copy(x3, t, 8);
            bn_copy(t, z2, 8); bn_copy(z2, z3, 8); bn_copy(z3, t, 8);
        }
        swap = bit;
        mod_add(A, x2, z2, M); mont_mul(AA, A, A, M);
        mod_sub(B, x2, z2, M); mont_mul(BB, B, B, M);
        mod_sub(E, AA, BB, M);
        mod_add(Cc, x3, z3, M); mod_sub(D, x3, z3, M);
        mont_mul(DA, D, A, M); mont_mul(CB, Cc, B, M);
        mod_add(t, DA, CB, M); mont_mul(x3, t, t, M);
        mod_sub(t, DA, CB, M); mont_mul(t, t, t, M); mont_mul(z3, x1, t, M);
        mont_mul(x2, AA, BB, M);
        mont_mul(t, a24, E, M); mod_add(t, t, AA, M); mont_mul(z2, E, t, M);
    }
    if (swap) {
        bn_copy(t, x2, 8); bn_copy(x2, x3, 8); bn_copy(x3, t, 8);
        bn_copy(t, z2, 8); bn_copy(z2, z3, 8); bn_copy(z3, t, 8);
    }
    mod_inv(z2, z2, M);
    mont_mul(t, x2, z2, M);
    from_mont(t, t, M);
    bn_to_le(out, 32, t, 8);
    explicit_bzero(k, sizeof k);
    uint8_t zero = 0;
    for (int i = 0; i < 32; i++) zero |= out[i];
    return zero ? 0 : -1;                            /* all-zero: small-order point */
}
DX_EXPORT("_bitten_ck_x25519", bitten_ck_x25519);

static void ed_add(ept *r, const ept *p, const ept *q) {
    const mod_t *M = &F25;
    bn a, b, c, d, e, f, g, h, t;
    mod_sub(a, p->y, p->x, M); mod_sub(t, q->y, q->x, M); mont_mul(a, a, t, M);
    mod_add(b, p->y, p->x, M); mod_add(t, q->y, q->x, M); mont_mul(b, b, t, M);
    mont_mul(c, p->t, ED_D2, M); mont_mul(c, c, q->t, M);
    mont_mul(d, p->z, q->z, M); mod_add(d, d, d, M);
    mod_sub(e, b, a, M); mod_sub(f, d, c, M); mod_add(g, d, c, M); mod_add(h, b, a, M);
    mont_mul(r->x, e, f, M); mont_mul(r->y, g, h, M);
    mont_mul(r->t, e, h, M); mont_mul(r->z, f, g, M);
}

static void ed_mul(ept *r, const ept *P, const uint32_t *k) {
    ept acc;
    bn_zero(acc.x, 8); bn_copy(acc.y, F25.one, 8); bn_copy(acc.z, F25.one, 8); bn_zero(acc.t, 8);
    for (int i = bn_bits(k, 8) - 1; i >= 0; i--) {
        ed_add(&acc, &acc, &acc);
        if (bn_bit(k, i)) ed_add(&acc, &acc, P);
    }
    *r = acc;
}

static void ed_base(ept *B) {
    bn_copy(B->x, ED_BX, 8); bn_copy(B->y, ED_BY, 8); bn_copy(B->z, F25.one, 8);
    mont_mul(B->t, ED_BX, ED_BY, &F25);
}

static void ed_encode(uint8_t *s, const ept *P) {
    bn zi, x, y;
    mod_inv(zi, P->z, &F25);
    mont_mul(x, P->x, zi, &F25); from_mont(x, x, &F25);
    mont_mul(y, P->y, zi, &F25); from_mont(y, y, &F25);
    bn_to_le(s, 32, y, 8);
    s[31] |= (uint8_t)((x[0] & 1) << 7);
}

static int ed_decode(ept *P, const uint8_t *s) {
    const mod_t *M = &F25;
    uint8_t b[32];
    memcpy(b, s, 32);
    int sign = b[31] >> 7;
    b[31] &= 127;
    bn y, yy, u, v, v3, x, t, e;
    bn_from_le(y, 8, b, 32);
    if (bn_cmp(y, M->m, 8) >= 0) return -1;
    to_mont(y, y, M);
    mont_mul(yy, y, y, M);
    mod_sub(u, yy, M->one, M);                       /* y^2 - 1 */
    mont_mul(v, ED_D, yy, M); mod_add(v, v, M->one, M);  /* d y^2 + 1 */
    mont_mul(v3, v, v, M); mont_mul(v3, v3, v, M);
    mont_mul(t, v3, v3, M); mont_mul(t, t, v, M); mont_mul(t, t, u, M);  /* u v^7 */
    bn_copy(e, M->m, 8);                             /* (p-5)/8 */
    bn five = {5};
    bn_sub(e, e, five, 8);
    for (int k = 0; k < 3; k++)
        for (int i = 0; i < 8; i++) e[i] = (e[i] >> 1) | (i < 7 ? e[i + 1] << 31 : 0);
    mod_pow(t, t, e, M);
    mont_mul(x, u, v3, M); mont_mul(x, x, t, M);
    bn vx2, nu;
    mont_mul(vx2, x, x, M); mont_mul(vx2, vx2, v, M);
    bn_zero(nu, 8); mod_sub(nu, nu, u, M);
    if (bn_cmp(vx2, u, 8) != 0) {
        if (bn_cmp(vx2, nu, 8) != 0) return -1;
        mont_mul(x, x, SQRTM1, M);
    }
    bn xp;
    from_mont(xp, x, M);
    if (bn_is_zero(xp, 8) && sign) return -1;
    if ((int)(xp[0] & 1) != sign) { bn z = {0}; mod_sub(x, z, x, M); }
    bn_copy(P->x, x, 8); bn_copy(P->y, y, 8); bn_copy(P->z, M->one, 8);
    mont_mul(P->t, x, y, M);
    return 0;
}

typedef int (*sha512_fn)(const void *, uint32_t, unsigned char *);

static int sha512_parts(uint8_t out[64], const uint8_t *a, size_t alen, const uint8_t *b,
                        size_t blen, const uint8_t *c, size_t clen) {
    static sha512_fn sha512;
    if (!sha512) sha512 = (sha512_fn)dx_registry_lookup("_CC_SHA512");
    if (!sha512) return -1;
    size_t n = alen + blen + clen;
    uint8_t *buf = malloc(n ? n : 1);
    if (!buf) return -1;
    if (alen) memcpy(buf, a, alen);
    if (blen) memcpy(buf + alen, b, blen);
    if (clen) memcpy(buf + alen + blen, c, clen);
    sha512(buf, (uint32_t)n, out);
    free(buf);
    return 0;
}

/* Expand a 32-byte seed: the clamped scalar a (mod l) and the prefix. */
static int ed_expand(const uint8_t *seed, uint32_t *a, uint8_t prefix[32], uint8_t A[32]) {
    uint8_t h[64];
    if (sha512_parts(h, seed, 32, NULL, 0, NULL, 0)) return -1;
    h[0] &= 248; h[31] &= 127; h[31] |= 64;
    bn s;
    bn_from_le(s, 8, h, 32);
    ept B, P;
    ed_base(&B);
    ed_mul(&P, &B, s);
    ed_encode(A, &P);
    mod_reduce_le(a, h, 32, &L25);
    memcpy(prefix, h + 32, 32);
    explicit_bzero(h, sizeof h);
    return 0;
}

int bitten_ck_ed25519_pub(const uint8_t *seed, uint8_t *pub) {
    bn a;
    uint8_t prefix[32];
    if (c25_init() || ed_expand(seed, a, prefix, pub)) return -1;
    return 0;
}
DX_EXPORT("_bitten_ck_ed25519_pub", bitten_ck_ed25519_pub);

int bitten_ck_ed25519_sign(const uint8_t *seed, const uint8_t *msg, size_t len, uint8_t *sig) {
    bn a, r, k, s, am, km, rm;
    uint8_t prefix[32], A[32], h[64];
    ept B, R;
    if (c25_init() || ed_expand(seed, a, prefix, A)) return -1;
    if (sha512_parts(h, prefix, 32, msg, len, NULL, 0)) return -1;
    mod_reduce_le(r, h, 64, &L25);
    ed_base(&B);
    ed_mul(&R, &B, r);
    ed_encode(sig, &R);
    if (sha512_parts(h, sig, 32, A, 32, msg, len)) return -1;
    mod_reduce_le(k, h, 64, &L25);
    to_mont(km, k, &L25); to_mont(am, a, &L25); to_mont(rm, r, &L25);
    mont_mul(s, km, am, &L25);
    mod_add(s, s, rm, &L25);
    from_mont(s, s, &L25);
    bn_to_le(sig + 32, 32, s, 8);
    return 0;
}
DX_EXPORT("_bitten_ck_ed25519_sign", bitten_ck_ed25519_sign);

int bitten_ck_ed25519_verify(const uint8_t *pub, const uint8_t *msg, size_t len, const uint8_t *sig) {
    ept A, R, B, sB, kA, sum;
    bn s, k;
    uint8_t h[64], enc[32];
    if (c25_init() || ed_decode(&A, pub) || ed_decode(&R, sig)) return -1;
    bn_from_le(s, 8, sig + 32, 32);
    if (bn_cmp(s, L25.m, 8) >= 0) return -1;
    if (sha512_parts(h, sig, 32, pub, 32, msg, len)) return -1;
    mod_reduce_le(k, h, 64, &L25);
    ed_base(&B);
    ed_mul(&sB, &B, s);
    ed_mul(&kA, &A, k);
    ed_add(&sum, &R, &kA);
    uint8_t e1[32];
    ed_encode(enc, &sB);
    ed_encode(e1, &sum);
    return memcmp(enc, e1, 32) == 0 ? 0 : -1;
}
DX_EXPORT("_bitten_ck_ed25519_verify", bitten_ck_ed25519_verify);

/* ---- hashing and AES-GCM for the Swift side ---------------------------
 * alg: 0 SHA-256, 1 SHA-384, 2 SHA-512, 3 SHA-1, 4 MD5. ctx is caller
 * storage of at least 256 bytes, so Swift keeps value semantics by copying
 * its bytes. */

static void *cc(const char *name) { return dx_registry_lookup(name); }

static const char *const HASH_NAMES[5][3] = {
    {"_CC_SHA256_Init", "_CC_SHA256_Update", "_CC_SHA256_Final"},
    {"_CC_SHA384_Init", "_CC_SHA384_Update", "_CC_SHA384_Final"},
    {"_CC_SHA512_Init", "_CC_SHA512_Update", "_CC_SHA512_Final"},
    {"_CC_SHA1_Init", "_CC_SHA1_Update", "_CC_SHA1_Final"},
    {"_CC_MD5_Init", "_CC_MD5_Update", "_CC_MD5_Final"},
};

int bitten_ck_hash_init(int alg, void *ctx) {
    int (*f)(void *) = alg >= 0 && alg < 5 ? cc(HASH_NAMES[alg][0]) : NULL;
    return f ? (f(ctx), 0) : -1;
}
DX_EXPORT("_bitten_ck_hash_init", bitten_ck_hash_init);

int bitten_ck_hash_update(int alg, void *ctx, const void *data, size_t len) {
    int (*f)(void *, const void *, uint32_t) = alg >= 0 && alg < 5 ? cc(HASH_NAMES[alg][1]) : NULL;
    if (!f) return -1;
    const uint8_t *p = data;
    while (len) {                                   /* CC_LONG is 32 bits */
        uint32_t chunk = len > 0x40000000u ? 0x40000000u : (uint32_t)len;
        f(ctx, p, chunk);
        p += chunk; len -= chunk;
    }
    return 0;
}
DX_EXPORT("_bitten_ck_hash_update", bitten_ck_hash_update);

int bitten_ck_hash_final(int alg, void *ctx, uint8_t *out) {
    int (*f)(uint8_t *, void *) = alg >= 0 && alg < 5 ? cc(HASH_NAMES[alg][2]) : NULL;
    return f ? (f(out, ctx), 0) : -1;
}
DX_EXPORT("_bitten_ck_hash_final", bitten_ck_hash_final);

/* argv: key, keylen, nonce, noncelen, aad, aadlen, in, inlen, out, tag (16
 * bytes). op 0 seals, 1 opens (and checks the tag). */
int bitten_ck_gcm(int op, const intptr_t *argv) {
    typedef int (*gcm_fn)(uint32_t, const void *, size_t, const void *, size_t, const void *,
                          size_t, const void *, size_t, void *, void *, size_t);
    gcm_fn f = cc(op ? "_CCCryptorGCMOneshotDecrypt" : "_CCCryptorGCMOneshotEncrypt");
    if (!f) return -1;
    return f(0 /* kCCAlgorithmAES */, (const void *)argv[0], (size_t)argv[1],
             (const void *)argv[2], (size_t)argv[3], (const void *)argv[4], (size_t)argv[5],
             (const void *)argv[6], (size_t)argv[7], (void *)argv[8], (void *)argv[9], 16) ? -1 : 0;
}
DX_EXPORT("_bitten_ck_gcm", bitten_ck_gcm);

int bitten_ck_random(void *p, size_t n) { return random_bytes(p, n); }
DX_EXPORT("_bitten_ck_random", bitten_ck_random);
