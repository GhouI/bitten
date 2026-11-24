#include <errno.h>
#include <string.h>
#include <sys/random.h>

#include "dx.h"

struct md5 { uint32_t h[4], count[2]; uint8_t block[64]; };
struct sha1 { uint32_t h[5], count[2]; uint8_t block[64]; };
struct sha256 { uint32_t h[8], count[2]; uint8_t block[64]; };
struct sha512 { uint64_t h[8], count[2]; uint8_t block[128]; };

_Static_assert(sizeof(struct md5) <= 92, "CC_MD5_CTX");
_Static_assert(sizeof(struct sha1) <= 96, "CC_SHA1_CTX");
_Static_assert(sizeof(struct sha256) <= 104, "CC_SHA256_CTX");
_Static_assert(sizeof(struct sha512) <= 208 && _Alignof(struct sha512) == 8, "CC_SHA512_CTX");

static uint32_t rol32(uint32_t x, unsigned n) { return (x << n) | (x >> (32 - n)); }
static uint32_t ror32(uint32_t x, unsigned n) { return rol32(x, 32 - n); }
static uint64_t ror64(uint64_t x, unsigned n) { return (x >> n) | (x << (64 - n)); }

static uint32_t load32(const uint8_t *p, int little) {
    uint32_t v;
    memcpy(&v, p, sizeof v);
    return little ? v : __builtin_bswap32(v);
}

static void md5_block(uint32_t *h, const uint8_t *p) {
    static const uint32_t k[64] = {
        0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
        0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
        0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
        0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
        0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
        0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
        0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
        0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
    };
    static const uint8_t shifts[4][4] = {{7,12,17,22}, {5,9,14,20}, {4,11,16,23}, {6,10,15,21}};
    uint32_t w[16], a = h[0], b = h[1], c = h[2], d = h[3];
    for (unsigned i = 0; i < 16; i++) w[i] = load32(p + 4*i, 1);
    for (unsigned i = 0; i < 64; i++) {
        unsigned j;
        uint32_t f;
        switch (i / 16) {
        case 0: f = (b & c) | (~b & d); j = i; break;
        case 1: f = (d & b) | (~d & c); j = (5*i + 1) % 16; break;
        case 2: f = b ^ c ^ d; j = (3*i + 5) % 16; break;
        default: f = c ^ (b | ~d); j = (7*i) % 16; break;
        }
        uint32_t next = b + rol32(a + f + k[i] + w[j], shifts[i / 16][i % 4]);
        a = d; d = c; c = b; b = next;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
}

static void sha1_block(uint32_t *h, const uint8_t *p) {
    uint32_t w[80], a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
    for (unsigned i = 0; i < 16; i++) w[i] = load32(p + 4*i, 0);
    for (unsigned i = 16; i < 80; i++)
        w[i] = rol32(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], 1);
    for (unsigned i = 0; i < 80; i++) {
        uint32_t f, k;
        switch (i / 20) {
        case 0: f = (b & c) | (~b & d); k = 0x5a827999; break;
        case 2: f = (b & c) | ((b | c) & d); k = 0x8f1bbcdc; break;
        case 1: f = b ^ c ^ d; k = 0x6ed9eba1; break;
        default: f = b ^ c ^ d; k = 0xca62c1d6; break;
        }
        uint32_t next = rol32(a, 5) + f + e + k + w[i];
        e = d; d = c; c = rol32(b, 30); b = a; a = next;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e;
}

/* Fractional cube roots of the first 80 primes (FIPS 180-4).
 * SHA-256 uses the upper half of each of the first 64 constants. */
static const uint64_t sha_k[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL,
};

static void sha256_block(uint32_t *h, const uint8_t *p) {
    uint32_t w[64];
    for (unsigned i = 0; i < 16; i++) w[i] = load32(p + 4*i, 0);
    for (unsigned i = 16; i < 64; i++) {
        uint32_t x = w[i-15], y = w[i-2];
        w[i] = w[i-16] + (ror32(x, 7) ^ ror32(x, 18) ^ (x >> 3))
             + w[i-7] + (ror32(y, 17) ^ ror32(y, 19) ^ (y >> 10));
    }
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    uint32_t e = h[4], f = h[5], g = h[6], j = h[7];
    for (unsigned i = 0; i < 64; i++) {
        uint32_t t1 = j + (ror32(e, 6) ^ ror32(e, 11) ^ ror32(e, 25))
                       + ((e & f) ^ (~e & g)) + (uint32_t)(sha_k[i] >> 32) + w[i];
        uint32_t t2 = (ror32(a, 2) ^ ror32(a, 13) ^ ror32(a, 22)) + ((a & b) | ((a | b) & c));
        j = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
    h[4] += e; h[5] += f; h[6] += g; h[7] += j;
}

static void sha512_block(uint64_t *h, const uint8_t *p) {
    uint64_t w[80];
    for (unsigned i = 0; i < 16; i++) {
        uint64_t v;
        memcpy(&v, p + 8*i, sizeof v);
        w[i] = __builtin_bswap64(v);
    }
    for (unsigned i = 16; i < 80; i++) {
        uint64_t x = w[i-15], y = w[i-2];
        w[i] = w[i-16] + (ror64(x, 1) ^ ror64(x, 8) ^ (x >> 7))
             + w[i-7] + (ror64(y, 19) ^ ror64(y, 61) ^ (y >> 6));
    }
    uint64_t a = h[0], b = h[1], c = h[2], d = h[3];
    uint64_t e = h[4], f = h[5], g = h[6], j = h[7];
    for (unsigned i = 0; i < 80; i++) {
        uint64_t t1 = j + (ror64(e, 14) ^ ror64(e, 18) ^ ror64(e, 41))
                       + ((e & f) ^ (~e & g)) + sha_k[i] + w[i];
        uint64_t t2 = (ror64(a, 28) ^ ror64(a, 34) ^ ror64(a, 39)) + ((a & b) | ((a | b) & c));
        j = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
    h[4] += e; h[5] += f; h[6] += g; h[7] += j;
}

static const uint32_t md5_iv[] = {0x67452301,0xefcdab89,0x98badcfe,0x10325476};
static const uint32_t sha1_iv[] = {0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0};
static const uint32_t sha224_iv[] = {
    0xc1059ed8,0x367cd507,0x3070dd17,0xf70e5939,0xffc00b31,0x68581511,0x64f98fa7,0xbefa4fa4
};
static const uint32_t sha256_iv[] = {
    0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
};
static const uint64_t sha384_iv[] = {
    0xcbbb9d5dc1059ed8ULL,0x629a292a367cd507ULL,0x9159015a3070dd17ULL,0x152fecd8f70e5939ULL,
    0x67332667ffc00b31ULL,0x8eb44a8768581511ULL,0xdb0c2e0d64f98fa7ULL,0x47b5481dbefa4fa4ULL
};
static const uint64_t sha512_iv[] = {
    0x6a09e667f3bcc908ULL,0xbb67ae8584caa73bULL,0x3c6ef372fe94f82bULL,0xa54ff53a5f1d36f1ULL,
    0x510e527fade682d1ULL,0x9b05688c2b3e6c1fULL,0x1f83d9abfb41bd6bULL,0x5be0cd19137e2179ULL
};

static void update32(uint32_t *h, uint32_t count[2], uint8_t *block,
                     const uint8_t *input, size_t len, void (*transform)(uint32_t *, const uint8_t *)) {
    size_t used = count[0] % 64;
    uint64_t total = ((uint64_t)count[1] << 32 | count[0]) + len;
    count[0] = total;
    count[1] = total >> 32;
    while (len) {
        if (!used && len >= 64) {
            transform(h, input);
            input += 64;
            len -= 64;
            continue;
        }
        size_t n = 64 - used < len ? 64 - used : len;
        memcpy(block + used, input, n);
        used += n;
        input += n;
        len -= n;
        if (used == 64) {
            transform(h, block);
            used = 0;
        }
    }
}

static void update64(struct sha512 *c, const uint8_t *input, size_t len) {
    size_t used = c->count[0] % 128;
    c->count[0] += len;
    c->count[1] += c->count[0] < len;
    while (len) {
        if (!used && len >= 128) {
            sha512_block(c->h, input);
            input += 128;
            len -= 128;
            continue;
        }
        size_t n = 128 - used < len ? 128 - used : len;
        memcpy(c->block + used, input, n);
        used += n;
        input += n;
        len -= n;
        if (used == 128) {
            sha512_block(c->h, c->block);
            used = 0;
        }
    }
}

static void final32(uint8_t *out, size_t size, uint32_t *h, uint32_t count[2], uint8_t *block,
                    int little, void (*transform)(uint32_t *, const uint8_t *)) {
    uint8_t pad[72] = {0x80};
    size_t len = 1 + (119 - count[0] % 64) % 64;
    uint64_t bits = ((uint64_t)count[1] << 32 | count[0]) << 3;
    if (!little) bits = __builtin_bswap64(bits);
    memcpy(pad + len, &bits, 8);
    update32(h, count, block, pad, len + 8, transform);
    for (size_t i = 0; i < size / 4; i++) {
        uint32_t v = little ? h[i] : __builtin_bswap32(h[i]);
        memcpy(out + 4*i, &v, 4);
    }
}

static void final64(uint8_t *out, size_t size, struct sha512 *c) {
    uint8_t pad[144] = {0x80};
    size_t len = 1 + (239 - c->count[0] % 128) % 128;
    uint64_t hi = __builtin_bswap64((c->count[1] << 3) | (c->count[0] >> 61));
    uint64_t lo = __builtin_bswap64(c->count[0] << 3);
    memcpy(pad + len, &hi, 8);
    memcpy(pad + len + 8, &lo, 8);
    update64(c, pad, len + 16);
    for (size_t i = 0; i < size / 8; i++) {
        uint64_t v = __builtin_bswap64(c->h[i]);
        memcpy(out + 8*i, &v, 8);
    }
}

#define DIGEST(name, type, iv, update, final)                                      \
    static int d_##name##_Init(struct type *c) {                                   \
        memset(c, 0, sizeof *c);                                                  \
        memcpy(c->h, iv, sizeof iv);                                              \
        return 1;                                                                \
    }                                                                            \
    static void name##_update(struct type *c, const void *p, size_t n) { update; } \
    static int d_##name##_Update(struct type *c, const void *p, uint32_t n) {       \
        name##_update(c, p, n);                                                   \
        return 1;                                                                \
    }                                                                            \
    static int d_##name##_Final(uint8_t *out, struct type *c) {                    \
        final;                                                                   \
        explicit_bzero(c, sizeof *c);                                             \
        return 1;                                                                \
    }                                                                            \
    static uint8_t *d_##name(const void *p, uint32_t n, uint8_t *out) {             \
        struct type c;                                                           \
        d_##name##_Init(&c);                                                      \
        d_##name##_Update(&c, p, n);                                               \
        d_##name##_Final(out, &c);                                                 \
        return out;                                                              \
    }                                                                            \
    DX_FN(name); DX_FN(name##_Init); DX_FN(name##_Update); DX_FN(name##_Final)

#define DIGEST32(name, type, iv, len, little)                                     \
    DIGEST(name, type, iv, update32(c->h, c->count, c->block, p, n, type##_block),  \
           final32(out, len, c->h, c->count, c->block, little, type##_block))
DIGEST32(CC_MD5, md5, md5_iv, 16, 1);
DIGEST32(CC_SHA1, sha1, sha1_iv, 20, 0);
DIGEST32(CC_SHA224, sha256, sha224_iv, 28, 0);
DIGEST32(CC_SHA256, sha256, sha256_iv, 32, 0);
DIGEST(CC_SHA384, sha512, sha384_iv, update64(c, p, n), final64(out, 48, c));
DIGEST(CC_SHA512, sha512, sha512_iv, update64(c, p, n), final64(out, 64, c));

union digest { struct md5 md5; struct sha1 sha1; struct sha256 sha256; struct sha512 sha512; };
struct hmac { union digest inner; uint8_t outer[128]; uint32_t alg; };
_Static_assert(sizeof(struct hmac) <= 384, "CCHmacContext");

static const uint8_t digest_size[] = {20, 16, 32, 48, 64, 28};

#define BY_ALGORITHM(call, ctx, ...)               \
    switch (alg) {                                 \
    case 0: call(CC_SHA1, &(ctx)->sha1, __VA_ARGS__); break;   \
    case 1: call(CC_MD5, &(ctx)->md5, __VA_ARGS__); break;     \
    case 2: call(CC_SHA256, &(ctx)->sha256, __VA_ARGS__); break; \
    case 3: call(CC_SHA384, &(ctx)->sha512, __VA_ARGS__); break; \
    case 4: call(CC_SHA512, &(ctx)->sha512, __VA_ARGS__); break; \
    case 5: call(CC_SHA224, &(ctx)->sha256, __VA_ARGS__); break; \
    }
#define INIT(name, c, ...) d_##name##_Init(c)
#define UPDATE(name, c, p, n) name##_update(c, p, n)
#define FINAL(name, c, p) d_##name##_Final(p, c)

static void digest_init(union digest *c, uint32_t alg) { BY_ALGORITHM(INIT, c); }
static void digest_update(union digest *c, uint32_t alg, const void *p, size_t n) {
    BY_ALGORITHM(UPDATE, c, p, n);
}
static void digest_final(union digest *c, uint32_t alg, uint8_t *out) {
    BY_ALGORITHM(FINAL, c, out);
}

static size_t hmac_block_size(uint32_t alg) { return alg == 3 || alg == 4 ? 128 : 64; }

static void hmac_init(struct hmac *c, uint32_t alg, const void *key, size_t n) {
    memset(c, 0, sizeof *c);
    c->alg = alg;
    if (alg >= sizeof digest_size) return;
    size_t block = hmac_block_size(alg);
    uint8_t pad[128] = {0};
    if (n > block) {
        digest_init(&c->inner, alg);
        digest_update(&c->inner, alg, key, n);
        digest_final(&c->inner, alg, pad);
    } else if (n) {
        memcpy(pad, key, n);
    }
    for (size_t i = 0; i < block; i++) {
        c->outer[i] = pad[i] ^ 0x5c;
        pad[i] ^= 0x36;
    }
    digest_init(&c->inner, alg);
    digest_update(&c->inner, alg, pad, block);
    explicit_bzero(pad, sizeof pad);
}

static void hmac_final(struct hmac *c, void *out) {
    uint32_t alg = c->alg;
    if (alg >= sizeof digest_size) return;
    uint8_t digest[64];
    digest_final(&c->inner, alg, digest);
    digest_init(&c->inner, alg);
    digest_update(&c->inner, alg, c->outer, hmac_block_size(alg));
    digest_update(&c->inner, alg, digest, digest_size[alg]);
    digest_final(&c->inner, alg, out);
    explicit_bzero(digest, sizeof digest);
    explicit_bzero(c, sizeof *c);
}

/* The caller's CCHmacContext is only uint32_t-aligned. */
static void d_CCHmacInit(void *ctx, uint32_t alg, const void *key, size_t len) {
    struct hmac c;
    hmac_init(&c, alg, key, len);
    memcpy(ctx, &c, sizeof c);
    explicit_bzero(&c, sizeof c);
}
DX_FN(CCHmacInit);

static void d_CCHmacUpdate(void *ctx, const void *data, size_t len) {
    struct hmac c;
    memcpy(&c, ctx, sizeof c);
    digest_update(&c.inner, c.alg, data, len);
    memcpy(ctx, &c, sizeof c);
    explicit_bzero(&c, sizeof c);
}
DX_FN(CCHmacUpdate);

static void d_CCHmacFinal(void *ctx, void *out) {
    struct hmac c;
    memcpy(&c, ctx, sizeof c);
    hmac_final(&c, out);
    explicit_bzero(ctx, sizeof c);
}
DX_FN(CCHmacFinal);

static void d_CCHmac(uint32_t alg, const void *key, size_t keylen,
                     const void *data, size_t len, void *out) {
    struct hmac c;
    hmac_init(&c, alg, key, keylen);
    digest_update(&c.inner, alg, data, len);
    hmac_final(&c, out);
}
DX_FN(CCHmac);

static int d_CCKeyDerivationPBKDF(uint32_t algorithm, const char *password, size_t pwlen,
                                const uint8_t *salt, size_t slen, uint32_t prf,
                                unsigned rounds, uint8_t *out, size_t len) {
    static const uint8_t algs[] = {0, 0, 5, 2, 3, 4};
    if (algorithm != 2 || !rounds || prf < 1 || prf >= sizeof algs ||
        (!password && pwlen) || (!salt && slen) || !out || !len)
        return -4300;
    uint32_t alg = algs[prf];
    size_t size = digest_size[alg];
    if ((len - 1) / size >= UINT32_MAX) return -4300;
    struct hmac base, salted, work;
    uint8_t u[64], block[64];
    hmac_init(&base, alg, password, pwlen);
    salted = base;
    digest_update(&salted.inner, alg, salt, slen);
    for (uint32_t i = 1; len; i++) {
        uint32_t index = __builtin_bswap32(i);
        work = salted;
        digest_update(&work.inner, alg, &index, sizeof index);
        hmac_final(&work, u);
        memcpy(block, u, size);
        for (unsigned j = 1; j < rounds; j++) {
            work = base;
            digest_update(&work.inner, alg, u, size);
            hmac_final(&work, u);
            for (size_t k = 0; k < size; k++) block[k] ^= u[k];
        }
        size_t n = len < size ? len : size;
        memcpy(out, block, n);
        out += n;
        len -= n;
    }
    explicit_bzero(&base, sizeof base);
    explicit_bzero(&salted, sizeof salted);
    explicit_bzero(u, sizeof u);
    explicit_bzero(block, sizeof block);
    return 0;
}
DX_FN(CCKeyDerivationPBKDF);

static unsigned d_CCCalibratePBKDF(uint32_t algorithm, size_t pwlen, size_t saltlen,
                                 uint32_t prf, size_t keylen, uint32_t milliseconds) {
    (void)pwlen; (void)saltlen; (void)keylen; (void)milliseconds;
    return algorithm == 2 && prf >= 1 && prf <= 5 ? 100000 : (unsigned)-1;
}
DX_FN(CCCalibratePBKDF);

static int fill_random(void *bytes, size_t n) {
    if (!bytes && n) { errno = EINVAL; return -1; }
    uint8_t *p = bytes;
    while (n) {
        size_t chunk = n > 256 * 1024 ? 256 * 1024 : n;
        ssize_t got = getrandom(p, chunk, 0);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) {
            if (!got) errno = EIO;
            return -1;
        }
        p += got;
        n -= (size_t)got;
    }
    return 0;
}

static int d_CCRandomGenerateBytes(void *bytes, size_t count) {
    if (!bytes && count) return -4300;
    return fill_random(bytes, count) ? -4307 : 0;
}
DX_FN(CCRandomGenerateBytes);

static const void *const sec_random_default;
DX_EXPORT("_kSecRandomDefault", &sec_random_default);

static int d_SecRandomCopyBytes(const void *rnd, size_t n, void *bytes) {
    if (rnd) { dx_set_errno(22); return -1; }
    return DX_RET(fill_random(bytes, n));
}
DX_FN(SecRandomCopyBytes);
