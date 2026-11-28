/* QR codes for CIQRCodeGenerator (ISO/IEC 18004): the message in byte
 * mode, the smallest version (1-40) that holds it at the error correction
 * level asked for, Reed-Solomon codewords over GF(256), the function
 * patterns, and the mask with the lowest penalty. */

#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>

/* error correction levels, in the tables' order */
enum { ECL_L, ECL_M, ECL_Q, ECL_H };

static const signed char ecc_per_block[4][41] = {
    {-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
     28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30},
    {-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
     26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28},
    {-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30,
     28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30},
    {-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28,
     30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30},
};
static const signed char ecc_blocks[4][41] = {
    {-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8,
     8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25},
    {-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
     17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49},
    {-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20,
     23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68},
    {-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25,
     25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81},
};

static int raw_data_modules(int ver) {
    int r = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
        int n = ver / 7 + 2;
        r -= (25 * n - 10) * n - 55;
        if (ver >= 7) r -= 36;
    }
    return r;
}
static int data_codewords(int ver, int ecl) {
    return raw_data_modules(ver) / 8 - ecc_per_block[ecl][ver] * ecc_blocks[ecl][ver];
}

/* ---- Reed-Solomon over GF(2^8), polynomial 0x11D ---- */

static uint8_t gf_mul(uint8_t x, uint8_t y) {
    int z = 0;
    for (int i = 7; i >= 0; i--) {
        z = (z << 1) ^ ((z >> 7) * 0x11D);
        z ^= ((y >> i) & 1) * x;
    }
    return (uint8_t)z;
}
static void rs_divisor(int degree, uint8_t *out) {
    memset(out, 0, (size_t)degree);
    out[degree - 1] = 1;
    uint8_t root = 1;
    for (int i = 0; i < degree; i++) {
        for (int j = 0; j < degree; j++) {
            out[j] = gf_mul(out[j], root);
            if (j + 1 < degree) out[j] ^= out[j + 1];
        }
        root = gf_mul(root, 0x02);
    }
}
static void rs_remainder(const uint8_t *data, int len, const uint8_t *div, int degree, uint8_t *out) {
    memset(out, 0, (size_t)degree);
    for (int i = 0; i < len; i++) {
        uint8_t factor = data[i] ^ out[0];
        memmove(out, out + 1, (size_t)degree - 1);
        out[degree - 1] = 0;
        for (int j = 0; j < degree; j++) out[j] ^= gf_mul(div[j], factor);
    }
}

/* ---- the symbol ---- */

typedef struct {
    int size;
    uint8_t *dark, *function;   /* size*size, row by row */
} Symbol;

static void set_module(Symbol *s, int x, int y, int dark, int function) {
    if (x < 0 || y < 0 || x >= s->size || y >= s->size) return;
    s->dark[y * s->size + x] = (uint8_t)dark;
    if (function) s->function[y * s->size + x] = 1;
}
static void finder(Symbol *s, int x, int y) {
    for (int dy = -4; dy <= 4; dy++)
        for (int dx = -4; dx <= 4; dx++) {
            int d = abs(dx) > abs(dy) ? abs(dx) : abs(dy);
            set_module(s, x + dx, y + dy, d != 2 && d != 4, 1);
        }
}
static void alignment(Symbol *s, int x, int y) {
    for (int dy = -2; dy <= 2; dy++)
        for (int dx = -2; dx <= 2; dx++) {
            int d = abs(dx) > abs(dy) ? abs(dx) : abs(dy);
            set_module(s, x + dx, y + dy, d != 1, 1);
        }
}
static int alignment_positions(int ver, int size, int *out) {
    if (ver == 1) return 0;
    int n = ver / 7 + 2;
    int step = ver == 32 ? 26 : (ver * 4 + n * 2 + 1) / (n * 2 - 2) * 2;
    out[0] = 6;
    for (int i = n - 1, pos = size - 7; i >= 1; i--, pos -= step) out[i] = pos;
    return n;
}
static void format_bits(Symbol *s, int ecl, int mask) {
    static const int ecl_bits[4] = {1, 0, 3, 2};
    int data = ecl_bits[ecl] << 3 | mask, rem = data;
    for (int i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    int bits = (data << 10 | rem) ^ 0x5412;
    int n = s->size;
    for (int i = 0; i <= 5; i++) set_module(s, 8, i, (bits >> i) & 1, 1);
    set_module(s, 8, 7, (bits >> 6) & 1, 1);
    set_module(s, 8, 8, (bits >> 7) & 1, 1);
    set_module(s, 7, 8, (bits >> 8) & 1, 1);
    for (int i = 9; i < 15; i++) set_module(s, 14 - i, 8, (bits >> i) & 1, 1);
    for (int i = 0; i < 8; i++) set_module(s, n - 1 - i, 8, (bits >> i) & 1, 1);
    for (int i = 8; i < 15; i++) set_module(s, 8, n - 15 + i, (bits >> i) & 1, 1);
    set_module(s, 8, n - 8, 1, 1);   /* the dark module */
}
static void version_bits(Symbol *s, int ver) {
    if (ver < 7) return;
    int rem = ver;
    for (int i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
    long bits = (long)ver << 12 | rem;
    for (int i = 0; i < 18; i++) {
        int bit = (bits >> i) & 1, a = s->size - 11 + i % 3, b = i / 3;
        set_module(s, a, b, bit, 1);
        set_module(s, b, a, bit, 1);
    }
}
static void function_patterns(Symbol *s, int ver, int ecl) {
    int n = s->size;
    for (int i = 0; i < n; i++) {
        set_module(s, 6, i, i % 2 == 0, 1);
        set_module(s, i, 6, i % 2 == 0, 1);
    }
    finder(s, 3, 3);
    finder(s, n - 4, 3);
    finder(s, 3, n - 4);
    int pos[7], k = alignment_positions(ver, n, pos);
    for (int i = 0; i < k; i++)
        for (int j = 0; j < k; j++)
            if (!((i == 0 && j == 0) || (i == 0 && j == k - 1) || (i == k - 1 && j == 0))) alignment(s, pos[i], pos[j]);
    format_bits(s, ecl, 0);   /* reserves the areas; written again with the mask */
    version_bits(s, ver);
}
static void place_codewords(Symbol *s, const uint8_t *data, int len) {
    int n = s->size, i = 0;
    for (int right = n - 1; right >= 1; right -= 2) {
        if (right == 6) right = 5;
        for (int vert = 0; vert < n; vert++)
            for (int j = 0; j < 2; j++) {
                int x = right - j, upward = ((right + 1) & 2) == 0, y = upward ? n - 1 - vert : vert;
                if (!s->function[y * n + x] && i < len * 8) {
                    s->dark[y * n + x] = (data[i >> 3] >> (7 - (i & 7))) & 1;
                    i++;
                }
            }
    }
}
static int mask_bit(int mask, int x, int y) {
    switch (mask) {
    case 0: return (x + y) % 2 == 0;
    case 1: return y % 2 == 0;
    case 2: return x % 3 == 0;
    case 3: return (x + y) % 3 == 0;
    case 4: return (x / 3 + y / 2) % 2 == 0;
    case 5: return x * y % 2 + x * y % 3 == 0;
    case 6: return (x * y % 2 + x * y % 3) % 2 == 0;
    default: return ((x + y) % 2 + x * y % 3) % 2 == 0;
    }
}
static void apply_mask(Symbol *s, int mask) {
    int n = s->size;
    for (int y = 0; y < n; y++)
        for (int x = 0; x < n; x++)
            if (!s->function[y * n + x] && mask_bit(mask, x, y)) s->dark[y * n + x] ^= 1;
}

/* The standard's penalty: runs of five or more, 2x2 blocks, finder-like
 * 1:1:3:1:1 runs with four light modules beside, and dark/light balance. */
static long penalty(const Symbol *s) {
    int n = s->size;
    long p = 0;
    for (int pass = 0; pass < 2; pass++)
        for (int a = 0; a < n; a++) {
            int run = 0, prev = -1;
            for (int b = 0; b < n; b++) {
                int v = pass ? s->dark[b * n + a] : s->dark[a * n + b];
                if (v == prev) {
                    run++;
                } else {
                    if (run >= 5) p += 3 + (run - 5);
                    run = 1;
                    prev = v;
                }
                /* 1011101 with 0000 before or after */
                if (b >= 10) {
                    int bits = 0;
                    for (int k = 0; k < 11; k++) bits = bits << 1 | (pass ? s->dark[(b - 10 + k) * n + a] : s->dark[a * n + b - 10 + k]);
                    if (bits == 0x05D || bits == 0x5D0) p += 40;
                }
            }
            if (run >= 5) p += 3 + (run - 5);
        }
    for (int y = 0; y + 1 < n; y++)
        for (int x = 0; x + 1 < n; x++) {
            int c = s->dark[y * n + x];
            if (c == s->dark[y * n + x + 1] && c == s->dark[(y + 1) * n + x] && c == s->dark[(y + 1) * n + x + 1]) p += 3;
        }
    long dark = 0;
    for (int i = 0; i < n * n; i++) dark += s->dark[i];
    long total = (long)n * n;
    long k = (labs(dark * 20 - total * 10) + total - 1) / total - 1;
    if (k > 0) p += k * 10;
    return p;
}

/* The modules (1 dark) of the code for `message`, row by row from the
 * top, and its size; nil when it doesn't fit in version 40. `level` is
 * 'L', 'M', 'Q' or 'H'. */
NSData *bn_qr_modules(NSData *message, char level, int *sizeOut) {
    int ecl = level == 'L' ? ECL_L : level == 'Q' ? ECL_Q : level == 'H' ? ECL_H : ECL_M;
    int len = (int)message.length, ver = 0;
    for (int v = 1; v <= 40; v++) {
        int bits = 4 + (v < 10 ? 8 : 16) + 8 * len;
        if (bits <= data_codewords(v, ecl) * 8) { ver = v; break; }
    }
    if (!ver) return nil;
    /* the bit stream: byte mode, the count, the bytes, a terminator, then
     * padding to the capacity */
    int cap = data_codewords(ver, ecl);
    uint8_t *data = calloc((size_t)cap, 1);
    long bitlen = 0;
#define PUT(v, n)                                                                       \
    do {                                                                                \
        for (int _i = (n)-1; _i >= 0; _i--, bitlen++)                                   \
            if (((v) >> _i) & 1) data[bitlen >> 3] |= (uint8_t)(0x80 >> (bitlen & 7)); \
    } while (0)
    PUT(4u, 4);
    PUT((unsigned)len, ver < 10 ? 8 : 16);
    const uint8_t *msg = message.bytes;
    for (int i = 0; i < len; i++) PUT(msg[i], 8);
    long room = (long)cap * 8 - bitlen;
    bitlen += room < 4 ? room : 4;
    bitlen = (bitlen + 7) / 8 * 8;
    for (int pad = 0xEC; bitlen < (long)cap * 8; pad ^= 0xEC ^ 0x11) PUT((unsigned)pad, 8);
#undef PUT
    /* blocks with their error correction, interleaved */
    int nblocks = ecc_blocks[ecl][ver], eccLen = ecc_per_block[ecl][ver];
    int raw = raw_data_modules(ver) / 8;
    int nshort = nblocks - raw % nblocks, shortLen = raw / nblocks;
    uint8_t *blocks = calloc((size_t)nblocks * (shortLen + 1), 1);
    uint8_t div[30], ecc[30];
    rs_divisor(eccLen, div);
    for (int i = 0, k = 0; i < nblocks; i++) {
        int datLen = shortLen - eccLen + (i < nshort ? 0 : 1);
        uint8_t *b = blocks + (size_t)i * (shortLen + 1);
        memcpy(b, data + k, (size_t)datLen);
        rs_remainder(data + k, datLen, div, eccLen, ecc);
        k += datLen;
        /* short blocks keep a hole where the long ones have a byte more */
        memcpy(b + shortLen + 1 - eccLen, ecc, (size_t)eccLen);
    }
    uint8_t *all = malloc((size_t)raw);
    int out = 0;
    for (int i = 0; i < shortLen + 1; i++)
        for (int j = 0; j < nblocks; j++)
            if (i != shortLen - eccLen || j >= nshort) all[out++] = blocks[(size_t)j * (shortLen + 1) + i];
    free(blocks);
    free(data);

    Symbol s = {ver * 4 + 17, NULL, NULL};
    size_t area = (size_t)s.size * s.size;
    s.dark = calloc(area, 1);
    s.function = calloc(area, 1);
    function_patterns(&s, ver, ecl);
    place_codewords(&s, all, out);
    free(all);
    int best = 0;
    long bestPenalty = -1;
    for (int m = 0; m < 8; m++) {
        apply_mask(&s, m);
        format_bits(&s, ecl, m);
        long p = penalty(&s);
        if (bestPenalty < 0 || p < bestPenalty) { best = m; bestPenalty = p; }
        apply_mask(&s, m);   /* undo */
    }
    apply_mask(&s, best);
    format_bits(&s, ecl, best);
    free(s.function);
    if (sizeOut) *sizeOut = s.size;
    return [NSData dataWithBytesNoCopy:s.dark length:area freeWhenDone:YES];
}
