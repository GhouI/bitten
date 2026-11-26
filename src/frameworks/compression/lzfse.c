/* LZFSE and LZVN decoding (and LZFSE/LZVN encoding as stored blocks) for
 * libcompression's COMPRESSION_LZFSE and COMPRESSION_LZVN.
 *
 * A stream is a sequence of blocks, each starting with a four-byte magic:
 *   bvx$  end of stream
 *   bvx-  stored: raw size, then the bytes
 *   bvx1  LZFSE with plain frequency tables
 *   bvx2  LZFSE with packed header and frequency tables
 *   bvxn  LZVN: raw size, payload size, then the LZVN payload
 * An LZFSE block holds literals (four interleaved FSE streams) and
 * L/M/D triples (literal count, match length, match distance; three FSE
 * value streams), both read backwards from the end of their payloads. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lzfse.h"

enum {
    MAGIC_END = 0x24787662,      /* bvx$ */
    MAGIC_RAW = 0x2d787662,      /* bvx- */
    MAGIC_V1 = 0x31787662,       /* bvx1 */
    MAGIC_V2 = 0x32787662,       /* bvx2 */
    MAGIC_LZVN = 0x6e787662,     /* bvxn */
};
enum {
    L_STATES = 64, M_STATES = 64, D_STATES = 256, LIT_STATES = 1024,
    L_SYMBOLS = 20, M_SYMBOLS = 20, D_SYMBOLS = 64, LIT_SYMBOLS = 256,
};

static const uint8_t l_bits[L_SYMBOLS] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 5, 8};
static const int32_t l_base[L_SYMBOLS] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 28, 60};
static const uint8_t m_bits[M_SYMBOLS] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 5, 8, 11};
static const int32_t m_base[M_SYMBOLS] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 24, 56, 312};
static const uint8_t d_bits[D_SYMBOLS] = {0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5,
                                          5, 5, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10,
                                          11, 11, 11, 11, 12, 12, 12, 12, 13, 13, 13, 13, 14, 14, 14, 14, 15, 15, 15, 15};
static const int32_t d_base[D_SYMBOLS] = {
    0,     1,     2,     3,     4,     6,     8,     10,    12,    16,    20,    24,    28,    36,    44,    52,
    60,    76,    92,    108,   124,   156,   188,   220,   252,   316,   380,   444,   508,   636,   764,   892,
    1020,  1276,  1532,  1788,  2044,  2556,  3068,  3580,  4092,  5116,  6140,  7164,  8188,  10236, 12284, 14332,
    16380, 20476, 24572, 28668, 32764, 40956, 49148, 57340, 65532, 81916, 98300, 114684, 131068, 163836, 196604, 229372};

static uint32_t rd32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint64_t rd64(const uint8_t *p) {
    uint64_t v;
    memcpy(&v, p, 8);
    return v;
}
static uint64_t mask64(uint64_t x, int n) { return n >= 64 ? x : n <= 0 ? 0 : x & ((1ULL << n) - 1); }
static uint32_t field(uint64_t v, int off, int n) { return (uint32_t)((v >> off) & ((1ULL << n) - 1)); }
static void wr32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

/* ---- the block header, as in format 1 ---- */

struct header {
    uint32_t n_raw, n_payload, n_literals, n_matches, n_literal_payload, n_lmd_payload;
    int32_t literal_bits, lmd_bits;
    uint16_t literal_state[4], l_state, m_state, d_state;
    uint16_t freq[L_SYMBOLS + M_SYMBOLS + D_SYMBOLS + LIT_SYMBOLS]; /* l, m, d, literal */
};

static uint16_t freq_value(uint32_t bits, int *nbits) {
    static const int8_t nbits_table[32] = {2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14,
                                           2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14};
    static const int8_t value_table[32] = {0, 2, 1, 4, 0, 3, 1, -1, 0, 2, 1, 5, 0, 3, 1, -1,
                                           0, 2, 1, 6, 0, 3, 1, -1, 0, 2, 1, 7, 0, 3, 1, -1};
    uint32_t b = bits & 31;
    int n = nbits_table[b];
    *nbits = n;
    if (n == 8) return (uint16_t)(8 + ((bits >> 4) & 0xf));
    if (n == 14) return (uint16_t)(24 + ((bits >> 4) & 0x3ff));
    return (uint16_t)value_table[b];
}

/* Reads a bvx1 or bvx2 header; returns its size, or 0 if malformed. */
static size_t read_header(const uint8_t *p, size_t avail, struct header *h) {
    memset(h, 0, sizeof *h);
    uint32_t magic = rd32(p);
    if (magic == MAGIC_V1) {
        if (avail < 772) return 0;
        h->n_raw = rd32(p + 4);
        h->n_payload = rd32(p + 8);
        h->n_literals = rd32(p + 12);
        h->n_matches = rd32(p + 16);
        h->n_literal_payload = rd32(p + 20);
        h->n_lmd_payload = rd32(p + 24);
        h->literal_bits = (int32_t)rd32(p + 28);
        for (int i = 0; i < 4; i++) h->literal_state[i] = rd16(p + 32 + 2 * i);
        h->lmd_bits = (int32_t)rd32(p + 40);
        h->l_state = rd16(p + 44);
        h->m_state = rd16(p + 46);
        h->d_state = rd16(p + 48);
        for (int i = 0; i < L_SYMBOLS + M_SYMBOLS + D_SYMBOLS + LIT_SYMBOLS; i++) h->freq[i] = rd16(p + 50 + 2 * i);
        return 772;
    }
    if (avail < 32) return 0;
    uint64_t v0 = rd64(p + 8), v1 = rd64(p + 16), v2 = rd64(p + 24);
    h->n_raw = rd32(p + 4);
    h->n_literals = field(v0, 0, 20);
    h->n_literal_payload = field(v0, 20, 20);
    h->n_matches = field(v0, 40, 20);
    h->literal_bits = (int32_t)field(v0, 60, 3) - 7;
    for (int i = 0; i < 4; i++) h->literal_state[i] = (uint16_t)field(v1, 10 * i, 10);
    h->n_lmd_payload = field(v1, 40, 20);
    h->lmd_bits = (int32_t)field(v1, 60, 3) - 7;
    h->l_state = (uint16_t)field(v2, 32, 10);
    h->m_state = (uint16_t)field(v2, 42, 10);
    h->d_state = (uint16_t)field(v2, 52, 10);
    h->n_payload = h->n_literal_payload + h->n_lmd_payload;
    uint32_t header_size = field(v2, 0, 32);
    if (header_size < 32 || header_size > avail) return 0;
    const uint8_t *src = p + 32, *end = p + header_size;
    if (src == end) return header_size;
    uint32_t accum = 0;
    int accum_bits = 0;
    for (int i = 0; i < L_SYMBOLS + M_SYMBOLS + D_SYMBOLS + LIT_SYMBOLS; i++) {
        while (src < end && accum_bits + 8 <= 32) {
            accum |= (uint32_t)*src++ << accum_bits;
            accum_bits += 8;
        }
        int n = 0;
        h->freq[i] = freq_value(accum, &n);
        if (n > accum_bits) return 0;
        accum >>= n;
        accum_bits -= n;
    }
    if (accum_bits >= 8 || src != end) return 0;
    return header_size;
}

/* ---- FSE ---- */

typedef struct { uint64_t accum; int bits; } instream;

static int in_init(instream *s, int n, const uint8_t **pbuf, const uint8_t *start) {
    if (n) {
        if (*pbuf < start + 8) return -1;
        *pbuf -= 8;
        s->accum = rd64(*pbuf);
        s->bits = n + 64;
    } else {
        if (*pbuf < start + 7) return -1;
        *pbuf -= 7;
        s->accum = 0;
        memcpy(&s->accum, *pbuf, 7);
        s->bits = n + 56;
    }
    if (s->bits < 56 || s->bits >= 64 || (s->accum >> s->bits) != 0) return -1;
    return 0;
}
static int in_flush(instream *s, const uint8_t **pbuf, const uint8_t *start) {
    int nbits = (63 - s->bits) & -8;
    const uint8_t *buf = *pbuf - (nbits >> 3);
    if (buf < start) return -1;
    if (nbits) {
        uint64_t incoming = rd64(buf);
        s->accum = (s->accum << nbits) | mask64(incoming, nbits);
        s->bits += nbits;
    }
    *pbuf = buf;
    return 0;
}
static uint64_t in_pull(instream *s, int n) {
    s->bits -= n;
    uint64_t r = s->accum >> s->bits;
    s->accum = mask64(s->accum, s->bits);
    return r;
}

typedef struct { int8_t k; uint8_t symbol; int16_t delta; } decoder_entry;
typedef struct { uint8_t total_bits, value_bits; int16_t delta; int32_t vbase; } value_entry;

static int init_decoder(int nstates, int nsymbols, const uint16_t *freq, decoder_entry *t) {
    int n_clz = __builtin_clz((unsigned)nstates), sum = 0;
    for (int i = 0; i < nsymbols; i++) {
        int f = freq[i];
        if (!f) continue;
        sum += f;
        if (sum > nstates) return -1;
        int k = __builtin_clz((unsigned)f) - n_clz;
        int j0 = ((2 * nstates) >> k) - f;
        for (int j = 0; j < f; j++, t++) {
            t->symbol = (uint8_t)i;
            if (j < j0) {
                t->k = (int8_t)k;
                t->delta = (int16_t)(((f + j) << k) - nstates);
            } else {
                t->k = (int8_t)(k - 1);
                t->delta = (int16_t)((j - j0) << (k - 1));
            }
        }
    }
    return 0;
}
static int init_value_decoder(int nstates, int nsymbols, const uint16_t *freq, const uint8_t *vbits,
                              const int32_t *vbase, value_entry *t) {
    int n_clz = __builtin_clz((unsigned)nstates), sum = 0;
    for (int i = 0; i < nsymbols; i++) {
        int f = freq[i];
        if (!f) continue;
        sum += f;
        if (sum > nstates) return -1;
        int k = __builtin_clz((unsigned)f) - n_clz;
        int j0 = ((2 * nstates) >> k) - f;
        for (int j = 0; j < f; j++, t++) {
            t->value_bits = vbits[i];
            t->vbase = vbase[i];
            if (j < j0) {
                t->total_bits = (uint8_t)(k + vbits[i]);
                t->delta = (int16_t)(((f + j) << k) - nstates);
            } else {
                t->total_bits = (uint8_t)(k - 1 + vbits[i]);
                t->delta = (int16_t)((j - j0) << (k - 1));
            }
        }
    }
    return 0;
}
static uint8_t decode_symbol(uint16_t *state, const decoder_entry *t, instream *in) {
    decoder_entry e = t[*state];
    *state = (uint16_t)(e.delta + (int)in_pull(in, e.k));
    return e.symbol;
}
static int32_t decode_value(uint16_t *state, const value_entry *t, instream *in) {
    value_entry e = t[*state];
    uint32_t sv = (uint32_t)in_pull(in, e.total_bits);
    *state = (uint16_t)(e.delta + (int)(sv >> e.value_bits));
    return e.vbase + (int32_t)mask64(sv, e.value_bits);
}

/* ---- one LZFSE block ---- */

/* bound: where the input begins; a stream's last refills may read bytes
 * before its own payload (whose bits are never used). */
static int decode_lzfse_block(const struct header *h, const uint8_t *bound, const uint8_t *payload, uint8_t *dst_begin,
                              size_t *pos, size_t cap) {
    if (h->n_literals > 4 * 65536 * 4 || (h->n_literals & 3)) return -1;
    if (h->literal_state[0] >= LIT_STATES || h->literal_state[1] >= LIT_STATES || h->literal_state[2] >= LIT_STATES ||
        h->literal_state[3] >= LIT_STATES || h->l_state >= L_STATES || h->m_state >= M_STATES || h->d_state >= D_STATES)
        return -1;
    const uint16_t *lf = h->freq, *mf = lf + L_SYMBOLS, *df = mf + M_SYMBOLS, *litf = df + D_SYMBOLS;
    decoder_entry *lit_table = malloc(sizeof(decoder_entry) * LIT_STATES);
    value_entry *l_table = malloc(sizeof(value_entry) * L_STATES), *m_table = malloc(sizeof(value_entry) * M_STATES),
                *d_table = malloc(sizeof(value_entry) * D_STATES);
    uint8_t *literals = malloc(h->n_literals + 64);
    int rc = -1;
    if (!lit_table || !l_table || !m_table || !d_table || !literals) goto done;
    memset(lit_table, 0, sizeof(decoder_entry) * LIT_STATES);
    memset(l_table, 0, sizeof(value_entry) * L_STATES);
    memset(m_table, 0, sizeof(value_entry) * M_STATES);
    memset(d_table, 0, sizeof(value_entry) * D_STATES);
    if (init_decoder(LIT_STATES, LIT_SYMBOLS, litf, lit_table) || init_value_decoder(L_STATES, L_SYMBOLS, lf, l_bits, l_base, l_table) ||
        init_value_decoder(M_STATES, M_SYMBOLS, mf, m_bits, m_base, m_table) ||
        init_value_decoder(D_STATES, D_SYMBOLS, df, d_bits, d_base, d_table))
        goto done;

    /* literals, four states in turn, read backwards */
    {
        const uint8_t *start = bound, *buf = payload + h->n_literal_payload;
        instream in;
        if (in_init(&in, h->literal_bits, &buf, start)) goto done;
        uint16_t s[4] = {h->literal_state[0], h->literal_state[1], h->literal_state[2], h->literal_state[3]};
        for (uint32_t i = 0; i < h->n_literals; i += 4) {
            if (in_flush(&in, &buf, start)) goto done;
            literals[i + 0] = decode_symbol(&s[0], lit_table, &in);
            literals[i + 1] = decode_symbol(&s[1], lit_table, &in);
            literals[i + 2] = decode_symbol(&s[2], lit_table, &in);
            literals[i + 3] = decode_symbol(&s[3], lit_table, &in);
        }
    }

    /* L, M, D */
    {
        const uint8_t *start = bound, *buf = payload + h->n_literal_payload + h->n_lmd_payload;
        instream in;
        if (in_init(&in, h->lmd_bits, &buf, start)) goto done;
        uint16_t ls = h->l_state, ms = h->m_state, ds = h->d_state;
        const uint8_t *lit = literals, *lit_end = literals + h->n_literals;
        int32_t D = -1;
        size_t out = *pos, end = *pos + h->n_raw;
        if (end > cap) goto done;
        for (uint32_t i = 0; i < h->n_matches; i++) {
            if (in_flush(&in, &buf, start)) goto done;
            int32_t L = decode_value(&ls, l_table, &in);
            int32_t M = decode_value(&ms, m_table, &in);
            int32_t Dn = decode_value(&ds, d_table, &in);
            if (Dn) D = Dn;
            if (L < 0 || M < 0 || lit + L > lit_end || out + (size_t)L + (size_t)M > end) goto done;
            memcpy(dst_begin + out, lit, (size_t)L);
            lit += L;
            out += (size_t)L;
            if (M) {
                if (D <= 0 || (size_t)D > out) goto done;
                for (int32_t k = 0; k < M; k++, out++) dst_begin[out] = dst_begin[out - (size_t)D];
            }
        }
        if (out != end) goto done;
        *pos = out;
    }
    rc = 0;
done:
    free(lit_table);
    free(l_table);
    free(m_table);
    free(d_table);
    free(literals);
    return rc;
}

/* ---- LZVN ---- */

/* Decodes an LZVN payload into dst[*pos..]; stops at the end-of-stream
 * opcode, or when the payload or the expected size runs out. */
static int decode_lzvn(const uint8_t *src, size_t n, uint8_t *dst, size_t *pos, size_t cap, size_t expect) {
    size_t i = 0, out = *pos, end = expect ? *pos + expect : cap;
    if (end > cap) return -1;
    size_t D = 0;
    while (i < n) {
        uint8_t op = src[i];
        size_t L = 0, M = 0, len = 1;
        int has_d = 0;
        if (op == 0x06) {                     /* end of stream */
            *pos = out;
            return expect && out != end ? -1 : 0;
        }
        if (op == 0x0e || op == 0x16) {       /* nop */
            i++;
            continue;
        }
        if (op >= 0xf0) {                     /* matches with the previous distance */
            if (op == 0xf0) {
                if (i + 2 > n) return -1;
                M = (size_t)src[i + 1] + 16;
                len = 2;
            } else {
                M = op & 0xf;
            }
        } else if (op >= 0xe0) {              /* literals */
            if (op == 0xe0) {
                if (i + 2 > n) return -1;
                L = (size_t)src[i + 1] + 16;
                len = 2;
            } else {
                L = op & 0xf;
            }
        } else if (op >= 0xa0 && op < 0xc0) { /* medium distance */
            if (i + 3 > n) return -1;
            L = (op >> 3) & 3;
            M = (((size_t)op & 7) << 2 | (src[i + 1] & 3)) + 3;
            D = (size_t)src[i + 2] << 6 | (src[i + 1] >> 2);
            len = 3;
            has_d = 1;
        } else {
            L = op >> 6;
            M = ((op >> 3) & 7) + 3;
            switch (op & 7) {
            case 6:                           /* previous distance */
                if (L == 0) return -1;        /* undefined */
                break;
            case 7:                           /* large distance */
                if (i + 3 > n) return -1;
                D = (size_t)src[i + 1] | (size_t)src[i + 2] << 8;
                len = 3;
                has_d = 1;
                break;
            default:                          /* small distance */
                if (i + 2 > n) return -1;
                D = ((size_t)op & 7) << 8 | src[i + 1];
                len = 2;
                has_d = 1;
            }
        }
        (void)has_d;
        i += len;
        if (i + L > n || out + L + M > end) return -1;
        memcpy(dst + out, src + i, L);
        i += L;
        out += L;
        if (M) {
            if (D == 0 || D > out) return -1;
            for (size_t k = 0; k < M; k++, out++) dst[out] = dst[out - D];
        }
    }
    *pos = out;
    return expect && out != end ? -1 : 0;
}

/* ---- streams ---- */

size_t bn_lzfse_decode(uint8_t *dst, size_t cap, const uint8_t *src, size_t n) {
    size_t i = 0, pos = 0;
    if (n >= 4 && (rd32(src) & 0x00ffffff) != 0x00787662) {
        /* a bare LZVN stream */
        return decode_lzvn(src, n, dst, &pos, cap, 0) ? 0 : pos;
    }
    while (i + 4 <= n) {
        uint32_t magic = rd32(src + i);
        if (magic == MAGIC_END) return pos;
        if (magic == MAGIC_RAW) {
            if (i + 8 > n) return 0;
            uint32_t raw = rd32(src + i + 4);
            if (i + 8 + raw > n || pos + raw > cap) return 0;
            memcpy(dst + pos, src + i + 8, raw);
            pos += raw;
            i += 8 + raw;
        } else if (magic == MAGIC_LZVN) {
            if (i + 12 > n) return 0;
            uint32_t raw = rd32(src + i + 4), payload = rd32(src + i + 8);
            if (i + 12 + payload > n) return 0;
            if (decode_lzvn(src + i + 12, payload, dst, &pos, cap, raw)) return 0;
            i += 12 + payload;
        } else if (magic == MAGIC_V1 || magic == MAGIC_V2) {
            struct header *h = malloc(sizeof *h);
            if (!h) return 0;
            size_t hs = read_header(src + i, n - i, h);
            if (!hs || i + hs + h->n_payload > n ||
                decode_lzfse_block(h, src, src + i + hs, dst, &pos, cap)) {
                free(h);
                return 0;
            }
            i += hs + h->n_payload;
            free(h);
        } else {
            return 0;
        }
    }
    return pos; /* no end marker: what was decoded */
}

/* The size a stream decodes to, from its block headers; 0 if unknown. */
size_t bn_lzfse_decoded_size(const uint8_t *src, size_t n) {
    size_t i = 0, total = 0;
    while (i + 8 <= n) {
        uint32_t magic = rd32(src + i), raw = rd32(src + i + 4);
        if (magic == MAGIC_END) return total;
        total += raw;
        if (magic == MAGIC_RAW) i += 8 + (size_t)raw;
        else if (magic == MAGIC_LZVN && i + 12 <= n) i += 12 + (size_t)rd32(src + i + 8);
        else if (magic == MAGIC_V1 && i + 12 <= n) i += 772 + (size_t)rd32(src + i + 8);
        else if (magic == MAGIC_V2 && i + 32 <= n) {
            struct header h;
            size_t hs = read_header(src + i, n - i, &h);
            if (!hs) return 0;
            i += hs + h.n_payload;
        } else {
            return 0;
        }
    }
    return total;
}

/* Stored blocks: valid for any LZFSE or LZVN decoder. */
size_t bn_lzfse_encode(uint8_t *dst, size_t cap, const uint8_t *src, size_t n) {
    size_t need = 8 + n + 4;
    if (need > cap) return 0;
    wr32(dst, MAGIC_RAW);
    wr32(dst + 4, (uint32_t)n);
    memcpy(dst + 8, src, n);
    wr32(dst + 8 + n, MAGIC_END);
    return need;
}
