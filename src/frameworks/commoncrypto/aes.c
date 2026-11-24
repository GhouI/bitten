#include <stdlib.h>
#include <string.h>

#include "dx.h"

enum {
    CC_PARAM = -4300, CC_SMALL = -4301, CC_MEMORY = -4302, CC_ALIGN = -4303,
    CC_DECODE = -4304, CC_UNIMPLEMENTED = -4305, CC_OVERFLOW = -4306, CC_SEQUENCE = -4309,
};
enum { AES_ECB = 1, AES_CBC = 2, AES_CTR = 4 };

struct aes_key { uint8_t bytes[240]; unsigned rounds; };

/* FIPS 197 substitution and inverse substitution, generated in GF(2^8). */
static const uint8_t sbox[256] = {
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
};
static const uint8_t inverse_sbox[256] = {
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
    0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
    0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
    0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
    0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
    0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
    0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
    0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
    0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
    0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
    0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d,
};

static uint8_t twice(uint8_t x) { return (x << 1) ^ (0x1b & (0u - (x >> 7))); }

static int aes_init(struct aes_key *k, const void *key, size_t len) {
    if (!key || (len != 16 && len != 24 && len != 32)) return CC_PARAM;
    k->rounds = len / 4 + 6;
    memcpy(k->bytes, key, len);
    uint8_t rc = 1;
    for (size_t i = len; i < 16 * (k->rounds + 1); i += 4) {
        uint8_t t[4];
        memcpy(t, k->bytes + i - 4, 4);
        if (i % len == 0) {
            uint8_t first = t[0];
            t[0] = sbox[t[1]] ^ rc;
            t[1] = sbox[t[2]];
            t[2] = sbox[t[3]];
            t[3] = sbox[first];
            rc = twice(rc);
        } else if (len == 32 && i % len == 16) {
            for (unsigned j = 0; j < 4; j++) t[j] = sbox[t[j]];
        }
        for (unsigned j = 0; j < 4; j++) k->bytes[i+j] = k->bytes[i+j-len] ^ t[j];
    }
    return 0;
}

static void xor_block(uint8_t *dst, const uint8_t *src) {
    for (unsigned i = 0; i < 16; i++) dst[i] ^= src[i];
}

static void mix(uint8_t *s, int inverse) {
    for (unsigned i = 0; i < 16; i += 4) {
        uint8_t *p = s + i;
        if (inverse) {
            uint8_t ac = twice(twice(p[0] ^ p[2]));
            uint8_t bd = twice(twice(p[1] ^ p[3]));
            p[0] ^= ac; p[2] ^= ac; p[1] ^= bd; p[3] ^= bd;
        }
        uint8_t sum = p[0] ^ p[1] ^ p[2] ^ p[3], first = p[0];
        p[0] ^= sum ^ twice(p[0] ^ p[1]);
        p[1] ^= sum ^ twice(p[1] ^ p[2]);
        p[2] ^= sum ^ twice(p[2] ^ p[3]);
        p[3] ^= sum ^ twice(p[3] ^ first);
    }
}

static void substitute_shift(uint8_t *dst, const uint8_t *src, int inverse) {
    const uint8_t *box = inverse ? inverse_sbox : sbox;
    for (unsigned col = 0; col < 4; col++) {
        for (unsigned row = 0; row < 4; row++) {
            unsigned from = inverse ? col + 4 - row : col + row;
            dst[4*col + row] = box[src[4*(from % 4) + row]];
        }
    }
}

static void aes_encrypt(const struct aes_key *k, const uint8_t *in, uint8_t *out) {
    uint8_t s[16], t[16];
    memcpy(s, in, 16);
    xor_block(s, k->bytes);
    for (unsigned i = 1; i <= k->rounds; i++) {
        substitute_shift(t, s, 0);
        if (i != k->rounds) mix(t, 0);
        xor_block(t, k->bytes + 16*i);
        memcpy(s, t, 16);
    }
    memcpy(out, s, 16);
}

static void aes_decrypt(const struct aes_key *k, const uint8_t *in, uint8_t *out) {
    uint8_t s[16], t[16];
    memcpy(s, in, 16);
    xor_block(s, k->bytes + 16*k->rounds);
    for (unsigned i = k->rounds; i--;) {
        substitute_shift(t, s, 1);
        xor_block(t, k->bytes + 16*i);
        if (i) mix(t, 1);
        memcpy(s, t, 16);
    }
    memcpy(out, s, 16);
}

static void increment(uint8_t *counter, unsigned first) {
    for (unsigned i = 16; i > first;)
        if (++counter[--i]) break;
}

struct cryptor {
    struct aes_key key;
    uint8_t iv[16], pending[32], keystream[16];
    size_t buffered, stream_pos;
    uint32_t mode, decrypt, padding;
    int finished;
};

static void cryptor_reset(struct cryptor *c, const void *iv) {
    memset(c->iv, 0, sizeof c->iv);
    if (iv && c->mode != AES_ECB) memcpy(c->iv, iv, sizeof c->iv);
    explicit_bzero(c->pending, sizeof c->pending);
    explicit_bzero(c->keystream, sizeof c->keystream);
    c->buffered = 0;
    c->stream_pos = 16;
    c->finished = 0;
}

static int cryptor_init(struct cryptor *c, uint32_t op, uint32_t mode, uint32_t alg,
                        uint32_t padding, const void *iv, const void *key, size_t keylen) {
    if (op > 1 || padding > 1 || (mode == AES_CTR && padding)) return CC_PARAM;
    if (alg || (mode != AES_ECB && mode != AES_CBC && mode != AES_CTR))
        return CC_UNIMPLEMENTED;
    int status = aes_init(&c->key, key, keylen);
    if (status) return status;
    c->mode = mode;
    c->decrypt = op;
    c->padding = padding;
    cryptor_reset(c, iv);
    return 0;
}

static int d_CCCryptorCreateWithMode(uint32_t op, uint32_t mode, uint32_t alg, uint32_t padding,
                                   const void *iv, const void *key, size_t keylen,
                                   const void *tweak, size_t tweaklen, int rounds, uint32_t options,
                                   struct cryptor **out) {
    if (!out) return CC_PARAM;
    *out = NULL;
    if (tweak || tweaklen || rounds || (options & ~2u)) return CC_PARAM;
    struct cryptor c;
    int status = cryptor_init(&c, op, mode, alg, padding, iv, key, keylen);
    if (status) return status;
    struct cryptor *allocated = malloc(sizeof c);
    if (allocated) *allocated = c;
    explicit_bzero(&c, sizeof c);
    *out = allocated;
    return allocated ? 0 : CC_MEMORY;
}
DX_FN(CCCryptorCreateWithMode);

static int d_CCCryptorCreate(uint32_t op, uint32_t alg, uint32_t options,
                            const void *key, size_t keylen, const void *iv, struct cryptor **out) {
    if (options & ~3u) return CC_PARAM;
    return d_CCCryptorCreateWithMode(op, options & 2 ? AES_ECB : AES_CBC, alg,
                                     options & 1, iv, key, keylen, NULL, 0, 0, 0, out);
}
DX_FN(CCCryptorCreate);

static size_t update_length(const struct cryptor *c, size_t len) {
    if (c->mode == AES_CTR) return len;
    size_t blocks = (c->buffered + len) / 16;
    if (blocks && c->decrypt && c->padding) blocks--;
    return 16 * blocks;
}

static size_t d_CCCryptorGetOutputLength(const struct cryptor *c, size_t len, _Bool final) {
    if (!c || len > SIZE_MAX - c->buffered) return 0;
    if (!final || c->mode == AES_CTR) return update_length(c, len);
    size_t total = c->buffered + len;
    size_t full = total - total % 16;
    if (c->padding && !c->decrypt) return full <= SIZE_MAX - 16 ? full + 16 : 0;
    return full;
}
DX_FN(CCCryptorGetOutputLength);

static void crypt_block(struct cryptor *c, const uint8_t *in, uint8_t *out) {
    uint8_t block[16];
    if (c->decrypt) {
        aes_decrypt(&c->key, in, block);
        if (c->mode == AES_CBC) {
            xor_block(block, c->iv);
            memcpy(c->iv, in, 16);
        }
        memcpy(out, block, 16);
    } else {
        memcpy(block, in, 16);
        if (c->mode == AES_CBC) xor_block(block, c->iv);
        aes_encrypt(&c->key, block, out);
        if (c->mode == AES_CBC) memcpy(c->iv, out, 16);
    }
}

static int overlaps(const void *a, size_t alen, const void *b, size_t blen) {
    if (!alen || !blen) return 0;
    uintptr_t x = (uintptr_t)a, y = (uintptr_t)b;
    return x <= y ? y - x < alen : x - y < blen;
}

static int d_CCCryptorUpdate(struct cryptor *c, const void *data, size_t len, void *result,
                            size_t capacity, size_t *moved) {
    if (moved) *moved = 0;
    if (!c || (!data && len)) return CC_PARAM;
    if (c->finished) return CC_SEQUENCE;
    if (len > SIZE_MAX - c->buffered) return CC_OVERFLOW;
    size_t need = update_length(c, len);
    if (capacity < need) return CC_SMALL;
    if (need && !result) return CC_PARAM;
    if (data != result && overlaps(data, len, result, need)) return CC_PARAM;
    const uint8_t *in = data;
    uint8_t *out = result;
    if (c->mode == AES_CTR) {
        for (size_t i = 0; i < len; i++) {
            if (c->stream_pos == 16) {
                aes_encrypt(&c->key, c->iv, c->keystream);
                increment(c->iv, 0);
                c->stream_pos = 0;
            }
            out[i] = in[i] ^ c->keystream[c->stream_pos++];
        }
    } else {
        uint8_t *copy = NULL;
        if (data == result && c->buffered && need) {
            copy = malloc(len);
            if (!copy) return CC_MEMORY;
            memcpy(copy, in, len);
            in = copy;
        }
        for (size_t done = 0; done < need; done += 16) {
            if (c->buffered >= 16) {
                crypt_block(c, c->pending, out + done);
                c->buffered -= 16;
                memmove(c->pending, c->pending + 16, c->buffered);
            } else if (c->buffered) {
                size_t take = 16 - c->buffered;
                memcpy(c->pending + c->buffered, in, take);
                in += take;
                len -= take;
                c->buffered = 0;
                crypt_block(c, c->pending, out + done);
            } else {
                crypt_block(c, in, out + done);
                in += 16;
                len -= 16;
            }
        }
        if (len) memcpy(c->pending + c->buffered, in, len);
        c->buffered += len;
        if (copy) {
            explicit_bzero(copy, (const uint8_t *)in - copy + len);
            free(copy);
        }
    }
    if (moved) *moved = need;
    return 0;
}
DX_FN(CCCryptorUpdate);

static int unpad(const uint8_t block[16], size_t *len) {
    unsigned n = block[15];
    unsigned bad = (n == 0) | (n > 16);
    for (unsigned i = 0; i < 16; i++)
        bad |= (0u - (i < n)) & (block[15-i] ^ n);
    if (bad) return CC_DECODE;
    *len = 16 - n;
    return 0;
}

static int d_CCCryptorFinal(struct cryptor *c, void *result, size_t capacity, size_t *moved) {
    if (moved) *moved = 0;
    if (!c) return CC_PARAM;
    if (c->finished) return CC_SEQUENCE;
    size_t need = 0;
    uint8_t block[16];
    if (!c->padding) {
        if (c->buffered) return CC_ALIGN;
    } else if (!c->decrypt) {
        need = 16;
        if (capacity < need) return CC_SMALL;
        if (!result) return CC_PARAM;
        memcpy(block, c->pending, c->buffered);
        memset(block + c->buffered, 16 - c->buffered, 16 - c->buffered);
        crypt_block(c, block, result);
    } else {
        if (c->buffered != 16) return CC_ALIGN;
        aes_decrypt(&c->key, c->pending, block);
        if (c->mode == AES_CBC) xor_block(block, c->iv);
        int status = unpad(block, &need);
        if (!status && capacity < need) status = CC_SMALL;
        if (!status && need && !result) status = CC_PARAM;
        if (!status && need) memcpy(result, block, need);
        explicit_bzero(block, sizeof block);
        if (status) return status;
    }
    explicit_bzero(block, sizeof block);
    explicit_bzero(c->pending, sizeof c->pending);
    c->finished = 1;
    if (moved) *moved = need;
    return 0;
}
DX_FN(CCCryptorFinal);

static int d_CCCryptorRelease(struct cryptor *c) {
    if (!c) return CC_PARAM;
    explicit_bzero(c, sizeof *c);
    free(c);
    return 0;
}
DX_FN(CCCryptorRelease);

static int d_CCCryptorReset(struct cryptor *c, const void *iv) {
    if (!c) return CC_PARAM;
    cryptor_reset(c, iv);
    return 0;
}
DX_FN(CCCryptorReset);

static int d_CCCrypt(uint32_t op, uint32_t alg, uint32_t options, const void *key, size_t keylen,
                     const void *iv, const void *data, size_t len, void *out, size_t capacity,
                     size_t *moved) {
    if (moved) *moved = 0;
    if (options & ~3u || (!data && len)) return CC_PARAM;
    struct cryptor c;
    int status = cryptor_init(&c, op, options & 2 ? AES_ECB : AES_CBC, alg, options & 1,
                              iv, key, keylen);
    if (status) return status;
    size_t needed = 0, first = 0, last = 0;
    if ((!c.padding || c.decrypt) && len % 16) {
        status = CC_ALIGN;
    } else if (c.padding && c.decrypt) {
        if (!len) {
            status = CC_ALIGN;
        } else {
            const uint8_t *tail = (const uint8_t *)data + len - 16;
            uint8_t block[16];
            aes_decrypt(&c.key, tail, block);
            if (c.mode == AES_CBC) xor_block(block, len == 16 ? c.iv : tail - 16);
            status = unpad(block, &needed);
            explicit_bzero(block, sizeof block);
            if (!status) needed += len - 16;
        }
    } else {
        needed = d_CCCryptorGetOutputLength(&c, len, 1);
        if (c.padding && !needed) status = CC_OVERFLOW;
    }
    if (!status && capacity < needed) {
        status = CC_SMALL;
        if (moved) *moved = needed;
    }
    if (!status) status = d_CCCryptorUpdate(&c, data, len, out, capacity, &first);
    if (!status) status = d_CCCryptorFinal(&c, first ? (uint8_t *)out + first : out,
                                          capacity - first, &last);
    if (!status && moved) *moved = first + last;
    explicit_bzero(&c, sizeof c);
    return status;
}
DX_FN(CCCrypt);

static void ghash_block(uint8_t y[16], const uint8_t h[16], const uint8_t block[16]) {
    uint8_t v[16], z[16] = {0};
    memcpy(v, h, 16);
    xor_block(y, block);
    for (unsigned i = 0; i < 128; i++) {
        unsigned mask = 0u - ((y[i / 8] >> (7 - i % 8)) & 1);
        unsigned reduce = 0u - (v[15] & 1);
        for (unsigned j = 0; j < 16; j++) z[j] ^= v[j] & mask;
        for (unsigned j = 15; j > 0; j--) v[j] = (v[j] >> 1) | (v[j-1] << 7);
        v[0] = (v[0] >> 1) ^ (0xe1 & reduce);
    }
    memcpy(y, z, 16);
}

static void ghash_bytes(uint8_t y[16], const uint8_t h[16], const uint8_t *p, size_t n) {
    while (n >= 16) {
        ghash_block(y, h, p);
        p += 16;
        n -= 16;
    }
    if (n) {
        uint8_t tail[16] = {0};
        memcpy(tail, p, n);
        ghash_block(y, h, tail);
    }
}

static void ghash_lengths(uint8_t y[16], const uint8_t h[16], size_t a, size_t b) {
    uint64_t lengths[] = {__builtin_bswap64((uint64_t)a << 3), __builtin_bswap64((uint64_t)b << 3)};
    ghash_block(y, h, (const uint8_t *)lengths);
}

static void gcm_ctr(const struct aes_key *k, uint8_t j[16], const uint8_t *in, uint8_t *out, size_t n) {
    uint8_t ctr[16], ks[16];
    memcpy(ctr, j, 16);
    while (n) {
        increment(ctr, 12);
        aes_encrypt(k, ctr, ks);
        size_t take = n < 16 ? n : 16;
        for (size_t i = 0; i < take; i++) out[i] = in[i] ^ ks[i];
        in += take;
        out += take;
        n -= take;
    }
    explicit_bzero(ks, sizeof ks);
}

/* Legacy decrypt returns a tag like encrypt. The newer API verifies it first. */
static int gcm(uint32_t op, uint32_t alg, const void *key, size_t klen, const void *iv, size_t ivlen,
               const void *aad, size_t alen, const void *in, size_t n, void *out,
               const uint8_t *expected, uint8_t *tag, size_t tlen) {
    if (alg) return CC_UNIMPLEMENTED;
    if (op > 1 || !iv || !ivlen || (!aad && alen) || (n && (!in || !out)) ||
        (!expected && !tag) || tlen < 4 || tlen > 16 || ivlen > UINT64_MAX / 8 ||
        alen > UINT64_MAX / 8 || n > (UINT64_C(1) << 36) - 32 ||
        (in != out && overlaps(in, n, out, n))) return CC_PARAM;
    struct aes_key k;
    int status = aes_init(&k, key, klen);
    if (status) return status;
    uint8_t h[16] = {0}, j[16] = {0}, y[16] = {0}, mask[16];
    aes_encrypt(&k, h, h);
    if (ivlen == 12) {
        memcpy(j, iv, ivlen);
        j[15] = 1;
    } else {
        ghash_bytes(j, h, iv, ivlen);
        ghash_lengths(j, h, 0, ivlen);
    }
    ghash_bytes(y, h, aad, alen);
    if (!op) gcm_ctr(&k, j, in, out, n);
    ghash_bytes(y, h, op ? in : out, n);
    ghash_lengths(y, h, alen, n);
    aes_encrypt(&k, j, mask);
    xor_block(y, mask);
    if (expected) {
        unsigned mismatch = 0;
        for (size_t i = 0; i < tlen; i++) mismatch |= y[i] ^ expected[i];
        if (mismatch) status = CC_DECODE;
    } else {
        memcpy(tag, y, tlen);
    }
    if (op && !status) gcm_ctr(&k, j, in, out, n);
    explicit_bzero(&k, sizeof k);
    explicit_bzero(h, sizeof h);
    explicit_bzero(y, sizeof y);
    explicit_bzero(mask, sizeof mask);
    return status;
}

static int d_CCCryptorGCMOneshotEncrypt(uint32_t alg, const void *key, size_t klen,
                                       const void *iv, size_t ivlen, const void *aad, size_t alen,
                                       const void *in, size_t n, void *out, void *tag, size_t tlen) {
    if (ivlen < 12 || tlen < 8) return CC_PARAM;
    return gcm(0, alg, key, klen, iv, ivlen, aad, alen, in, n, out, NULL, tag, tlen);
}
DX_FN(CCCryptorGCMOneshotEncrypt);

static int d_CCCryptorGCMOneshotDecrypt(uint32_t alg, const void *key, size_t klen,
                                       const void *iv, size_t ivlen, const void *aad, size_t alen,
                                       const void *in, size_t n, void *out, const void *tag, size_t tlen) {
    if (ivlen < 12 || tlen < 8) return CC_PARAM;
    return gcm(1, alg, key, klen, iv, ivlen, aad, alen, in, n, out, tag, NULL, tlen);
}
DX_FN(CCCryptorGCMOneshotDecrypt);

static int d_CCCryptorGCM(uint32_t op, uint32_t alg, const void *key, size_t klen,
                         const void *iv, size_t ivlen, const void *aad, size_t alen,
                         const void *in, size_t n, void *out, void *tag, size_t *tlen) {
    if (!tlen) return CC_PARAM;
    return gcm(op, alg, key, klen, iv, ivlen, aad, alen, in, n, out, NULL, tag, *tlen);
}
DX_FN(CCCryptorGCM);
