#include <string.h>

#include "zlib_internal.h"

enum phase {
    I_HEADER, I_G_FLAGS, I_G_TIME, I_G_OS, I_G_OPTION, I_G_XLEN, I_G_EXTRA, I_G_STRING, I_G_HCRC,
    I_DICT_ID, I_DICTIONARY, I_BLOCK, I_STORED_LEN, I_STORED,
    I_DYNAMIC, I_CODE_LENGTHS, I_TREE_LENGTHS, I_REPEAT,
    I_SYMBOL, I_LITERAL, I_LENGTH, I_DISTANCE, I_DIST_EXTRA, I_MATCH,
    I_TRAILER, I_G_SIZE, I_DONE, I_BAD,
};

/* Counts and symbols in canonical order (RFC 1951 section 3.2.2). */
struct tree {
    unsigned count[16];
    uint16_t symbol[288];
    unsigned max;
};

struct inflater {
    dz_stream *owner;
    enum wrapper requested, wrap;
    enum phase phase;
    unsigned requested_bits, window, head, history;
    uint64_t bits;
    unsigned nbits, last;
    uint32_t checksum, header_crc;
    unsigned flags, left, dist, length, extra;
    unsigned nlit, ndist, ncode, index, repeat, repeat_value;
    struct tree lit, distances, codes;
    uint8_t lengths[288 + 32];
    uint8_t ring[32768];
};

static int get_window(int bits, enum wrapper *wrap, unsigned *width) {
    if (bits >= -15 && bits <= -8) {
        *wrap = RAW;
        *width = -bits;
    } else if (bits == 0 || (bits >= 8 && bits <= 15)) {
        *wrap = ZLIB;
        *width = bits;
    } else if (bits == 16 || (bits >= 24 && bits <= 31)) {
        *wrap = GZIP;
        *width = bits - 16;
    } else if (bits == 32 || (bits >= 40 && bits <= 47)) {
        *wrap = AUTO;
        *width = bits - 32;
    } else {
        return 0;
    }
    return 1;
}

static void reset(dz_stream *s, struct inflater *i, enum wrapper wrap, unsigned bits) {
    memset(i, 0, offsetof(struct inflater, ring));
    i->owner = s;
    i->requested = i->wrap = wrap;
    i->requested_bits = bits;
    i->window = 1u << (bits ? bits : 15);
    i->phase = wrap == RAW ? I_BLOCK : I_HEADER;
    i->checksum = wrap == GZIP ? UINT32_MAX : 1;
    s->adler = wrap == GZIP ? 0 : 1;
    s->total_in = s->total_out = 0;
    s->msg = NULL;
    s->data_type = Z_UNKNOWN;
}

int dz_inflate_init(dz_stream *s, int bits, const char *version, int size) {
    int status = dz_allocators(s, version, size);
    if (status != Z_OK) return status;
    enum wrapper wrap;
    unsigned width;
    if (!get_window(bits, &wrap, &width)) return Z_STREAM_ERROR;
    struct inflater *i = s->zalloc(s->opaque, 1, sizeof *i);
    if (!i) return Z_MEM_ERROR;
    dz_crc32(0, (const uint8_t *)"", 0);
    s->state = i;
    reset(s, i, wrap, width);
    return Z_OK;
}
DX_EXPORT("_inflateInit2_", dz_inflate_init);

static int d_inflateInit_(dz_stream *s, const char *version, int size) {
    return dz_inflate_init(s, 15, version, size);
}
DX_FN(inflateInit_);

static struct inflater *state(dz_stream *s) {
    struct inflater *i = s && s->zalloc && s->zfree ? s->state : NULL;
    return i && i->owner == s ? i : NULL;
}

static int d_inflateReset(dz_stream *s) {
    struct inflater *i = state(s);
    if (!i) return Z_STREAM_ERROR;
    reset(s, i, i->requested, i->requested_bits);
    return Z_OK;
}
DX_FN(inflateReset);

static int d_inflateReset2(dz_stream *s, int bits) {
    struct inflater *i = state(s);
    enum wrapper wrap;
    unsigned width;
    if (!i || !get_window(bits, &wrap, &width)) return Z_STREAM_ERROR;
    reset(s, i, wrap, width);
    return Z_OK;
}
DX_FN(inflateReset2);

int dz_inflate_end(dz_stream *s) {
    struct inflater *i = state(s);
    if (!i) return Z_STREAM_ERROR;
    s->zfree(s->opaque, i);
    s->state = NULL;
    return Z_OK;
}
DX_EXPORT("_inflateEnd", dz_inflate_end);

static int d_inflateSetDictionary(dz_stream *s, const uint8_t *p, unsigned n) {
    struct inflater *i = state(s);
    if (!i || (!p && n) || (i->wrap != RAW && i->phase != I_DICTIONARY)) return Z_STREAM_ERROR;
    if (i->phase == I_DICTIONARY) {
        if (dz_adler32(1, p, n) != s->adler) return Z_DATA_ERROR;
        i->phase = I_BLOCK;
        s->adler = i->checksum = 1;
    }
    if (n > i->window) {
        p += n - i->window;
        n = i->window;
    }
    for (unsigned j = 0; j < n; j++) {
        i->ring[i->head] = p[j];
        i->head = (i->head + 1) & (i->window - 1);
    }
    i->history += n;
    if (i->history > i->window) i->history = i->window;
    return Z_OK;
}
DX_FN(inflateSetDictionary);

static int need_bits(dz_stream *s, struct inflater *i, unsigned n) {
    while (i->nbits < n) {
        if (!s->avail_in) return 0;
        i->bits |= (uint64_t)*s->next_in++ << i->nbits;
        i->nbits += 8;
        s->avail_in--;
        s->total_in++;
    }
    return 1;
}

static uint32_t take_bits(struct inflater *i, unsigned n) {
    uint32_t value = i->bits & ((UINT64_C(1) << n) - 1);
    i->bits >>= n;
    i->nbits -= n;
    return value;
}

static int read_bits(dz_stream *s, struct inflater *i, unsigned n, unsigned *out) {
    if (!need_bits(s, i, n)) return 0;
    *out = take_bits(i, n);
    return 1;
}

static int gzip_header(dz_stream *s, struct inflater *i, unsigned n, unsigned *out) {
    if (!read_bits(s, i, n, out)) return 0;
    for (unsigned j = 0; j < n; j += 8)
        i->header_crc = dz_crc_byte(i->header_crc, *out >> j);
    return 1;
}

/* DEFLATE permits an empty distance alphabet if no matches are used, and
 * a one-symbol data alphabet with a single bit. The code-length tree must be complete. */
static int build_tree(struct tree *t, const uint8_t *lengths, unsigned n, int complete) {
    memset(t->count, 0, sizeof t->count);
    for (unsigned j = 0; j < n; j++) t->count[lengths[j]]++;
    t->max = 0;
    if (t->count[0] == n) return !complete;
    unsigned offset[16], next = 0;
    int free_codes = 1;
    for (unsigned len = 1; len <= 15; len++) {
        free_codes = free_codes * 2 - (int)t->count[len];
        if (free_codes < 0) return 0;
        if (t->count[len]) t->max = len;
        offset[len] = next;
        next += t->count[len];
    }
    if (free_codes && (complete || t->max != 1)) return 0;
    for (unsigned j = 0; j < n; j++) {
        if (lengths[j]) t->symbol[offset[lengths[j]]++] = j;
    }
    return 1;
}

/* Peek one bit at a time so an end marker never consumes the next member. */
static int read_symbol(dz_stream *s, struct inflater *i, const struct tree *t) {
    unsigned code = 0, base = 0, offset = 0;
    for (unsigned len = 1; len <= t->max; len++) {
        if (!need_bits(s, i, len)) return -1;
        code = (code << 1) | ((i->bits >> (len - 1)) & 1);
        unsigned n = t->count[len];
        if (code >= base && code - base < n) {
            take_bits(i, len);
            return t->symbol[offset + code - base];
        }
        offset += n;
        base = (base + n) << 1;
    }
    return -2;
}

static void fixed_trees(struct inflater *i) {
    uint8_t lengths[288], d[32];
    memset(lengths, 8, 144);
    memset(lengths + 144, 9, 112);
    memset(lengths + 256, 7, 24);
    memset(lengths + 280, 8, 8);
    memset(d, 5, sizeof d);
    build_tree(&i->lit, lengths, sizeof lengths, 1);
    build_tree(&i->distances, d, sizeof d, 1);
}

static void emit(dz_stream *s, struct inflater *i, uint8_t c) {
    *s->next_out++ = c;
    s->avail_out--;
    s->total_out++;
    i->ring[i->head] = c;
    i->head = (i->head + 1) & (i->window - 1);
    if (i->history < i->window) i->history++;
    if (i->wrap == GZIP) {
        i->checksum = dz_crc_byte(i->checksum, c);
        s->adler = ~i->checksum;
    } else if (i->wrap == ZLIB) {
        unsigned a = (i->checksum & 65535) + c, b = i->checksum >> 16;
        if (a >= 65521) a -= 65521;
        b += a;
        if (b >= 65521) b -= 65521;
        s->adler = i->checksum = (b << 16) | a;
    }
}

static int invalid(dz_stream *s, struct inflater *i, const char *message) {
    s->msg = message;
    i->phase = I_BAD;
    return Z_DATA_ERROR;
}

static void end_block(struct inflater *i) {
    i->phase = I_BLOCK;
    if (!i->last) return;
    take_bits(i, i->nbits % 8);
    i->phase = i->wrap == RAW ? I_DONE : I_TRAILER;
}

int dz_inflate(dz_stream *s, int flush) {
    struct inflater *i = state(s);
    if (!i || !s->next_out || (s->avail_in && !s->next_in) || flush < 0 || flush > Z_TREES)
        return Z_STREAM_ERROR;
    unsigned long start_in = s->total_in, start_out = s->total_out;
    static const uint8_t code_order[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
    int boundary = 0, tree_ready = 0;
    for (;;) {
        unsigned v;
        int sym;
        switch (i->phase) {
        case I_HEADER:
            if (!read_bits(s, i, 16, &v)) goto pause;
            if ((i->wrap == AUTO || i->wrap == GZIP) && v == 0x8b1f) {
                i->wrap = GZIP;
                i->checksum = i->header_crc = UINT32_MAX;
                i->header_crc = dz_crc_byte(dz_crc_byte(i->header_crc, 0x1f), 0x8b);
                s->adler = 0;
                i->phase = I_G_FLAGS;
                break;
            }
            if (i->wrap == GZIP || (((v << 8 | v >> 8) & 65535) % 31))
                return invalid(s, i, "incorrect header check");
            if ((v & 15) != Z_DEFLATED) return invalid(s, i, "unknown compression method");
            {
                unsigned width = ((v >> 4) & 15) + 8;
                if (width > 15 || (i->requested_bits && width > i->requested_bits))
                    return invalid(s, i, "invalid window size");
                i->window = 1u << width;
            }
            i->wrap = ZLIB;
            i->phase = v & 0x2000 ? I_DICT_ID : I_BLOCK;
            boundary = i->phase == I_BLOCK;
            break;
        case I_G_FLAGS:
            if (!gzip_header(s, i, 16, &v)) goto pause;
            if ((v & 255) != Z_DEFLATED || v & 0xe000)
                return invalid(s, i, "invalid gzip method or flags");
            i->flags = v >> 8;
            i->phase = I_G_TIME;
            break;
        case I_G_TIME:
            if (!gzip_header(s, i, 32, &v)) goto pause;
            i->phase = I_G_OS;
            break;
        case I_G_OS:
            if (!gzip_header(s, i, 16, &v)) goto pause;
            i->phase = I_G_OPTION;
            break;
        case I_G_OPTION:
            if (i->flags & 4) {
                i->flags &= ~4u;
                i->phase = I_G_XLEN;
            } else if (i->flags & (8 | 16)) {
                i->flags &= ~(i->flags & 8 ? 8u : 16u);
                i->phase = I_G_STRING;
            } else if (i->flags & 2) {
                i->flags &= ~2u;
                i->phase = I_G_HCRC;
            } else {
                i->phase = I_BLOCK;
                boundary = 1;
            }
            break;
        case I_G_XLEN:
            if (!gzip_header(s, i, 16, &i->left)) goto pause;
            i->phase = I_G_EXTRA;
            break;
        case I_G_EXTRA:
            while (i->left) {
                if (!gzip_header(s, i, 8, &v)) goto pause;
                i->left--;
            }
            i->phase = I_G_OPTION;
            break;
        case I_G_STRING:
            do {
                if (!gzip_header(s, i, 8, &v)) goto pause;
            } while (v);
            i->phase = I_G_OPTION;
            break;
        case I_G_HCRC:
            if (!read_bits(s, i, 16, &v)) goto pause;
            if (v != (~i->header_crc & 65535)) return invalid(s, i, "gzip header crc mismatch");
            i->phase = I_G_OPTION;
            break;
        case I_DICT_ID:
            if (!read_bits(s, i, 32, &v)) goto pause;
            s->adler = __builtin_bswap32(v);
            i->phase = I_DICTIONARY;
            break;
        case I_DICTIONARY:
            return Z_NEED_DICT;
        case I_BLOCK:
            if (!read_bits(s, i, 3, &v)) goto pause;
            i->last = v & 1;
            switch (v >> 1) {
            case 0:
                take_bits(i, i->nbits % 8);
                i->phase = I_STORED_LEN;
                break;
            case 1:
                fixed_trees(i);
                i->phase = I_SYMBOL;
                tree_ready = 1;
                break;
            case 2:
                i->phase = I_DYNAMIC;
                break;
            default:
                return invalid(s, i, "invalid block type");
            }
            break;
        case I_STORED_LEN:
            if (!read_bits(s, i, 32, &v)) goto pause;
            i->left = v & 65535;
            if ((v >> 16) != (i->left ^ 65535)) return invalid(s, i, "invalid stored block lengths");
            i->phase = I_STORED;
            tree_ready = 1;
            break;
        case I_STORED:
            while (i->left) {
                if (!s->avail_out || !read_bits(s, i, 8, &v)) goto pause;
                emit(s, i, v);
                i->left--;
            }
            end_block(i);
            boundary = 1;
            break;
        case I_DYNAMIC:
            if (!read_bits(s, i, 14, &v)) goto pause;
            i->nlit = (v & 31) + 257;
            i->ndist = ((v >> 5) & 31) + 1;
            i->ncode = (v >> 10) + 4;
            if (i->nlit > 286 || i->ndist > 30) return invalid(s, i, "too many length or distance symbols");
            memset(i->lengths, 0, 19);
            i->index = 0;
            i->phase = I_CODE_LENGTHS;
            break;
        case I_CODE_LENGTHS:
            while (i->index < i->ncode) {
                if (!read_bits(s, i, 3, &v)) goto pause;
                i->lengths[code_order[i->index++]] = v;
            }
            if (!build_tree(&i->codes, i->lengths, 19, 1)) return invalid(s, i, "invalid code length tree");
            i->index = 0;
            i->phase = I_TREE_LENGTHS;
            break;
        case I_TREE_LENGTHS:
            if (i->index == i->nlit + i->ndist) {
                if (!i->lengths[256] || !build_tree(&i->lit, i->lengths, i->nlit, 0) ||
                    !build_tree(&i->distances, i->lengths + i->nlit, i->ndist, 0))
                    return invalid(s, i, "invalid literal or distance tree");
                i->phase = I_SYMBOL;
                tree_ready = 1;
                break;
            }
            sym = read_symbol(s, i, &i->codes);
            if (sym == -1) goto pause;
            if (sym < 0 || (sym == 16 && !i->index)) return invalid(s, i, "invalid code length repeat");
            if (sym < 16) {
                i->lengths[i->index++] = sym;
            } else {
                i->repeat_value = sym == 16 ? i->lengths[i->index - 1] : 0;
                i->repeat = sym == 18 ? 11 : 3;
                i->extra = sym == 16 ? 2 : sym == 17 ? 3 : 7;
                i->phase = I_REPEAT;
            }
            break;
        case I_REPEAT:
            if (!read_bits(s, i, i->extra, &v)) goto pause;
            v += i->repeat;
            if (v > i->nlit + i->ndist - i->index) return invalid(s, i, "code length repeat overruns tree");
            memset(i->lengths + i->index, i->repeat_value, v);
            i->index += v;
            i->phase = I_TREE_LENGTHS;
            break;
        case I_SYMBOL:
            sym = read_symbol(s, i, &i->lit);
            if (sym == -1) goto pause;
            if (sym < 0 || sym > 285) return invalid(s, i, "invalid literal or length code");
            if (sym < 256) {
                i->left = sym;
                i->phase = I_LITERAL;
            } else if (sym == 256) {
                end_block(i);
                boundary = 1;
            } else {
                i->length = dz_length_base[sym - 257];
                i->extra = dz_length_extra[sym - 257];
                i->phase = I_LENGTH;
            }
            break;
        case I_LITERAL:
            if (!s->avail_out) goto pause;
            emit(s, i, i->left);
            i->phase = I_SYMBOL;
            break;
        case I_LENGTH:
            if (!read_bits(s, i, i->extra, &v)) goto pause;
            i->length += v;
            i->phase = I_DISTANCE;
            break;
        case I_DISTANCE:
            sym = read_symbol(s, i, &i->distances);
            if (sym == -1) goto pause;
            if (sym < 0 || sym > 29) return invalid(s, i, "invalid distance code");
            i->dist = dz_dist_base[sym];
            i->extra = dz_dist_extra[sym];
            i->phase = I_DIST_EXTRA;
            break;
        case I_DIST_EXTRA:
            if (!read_bits(s, i, i->extra, &v)) goto pause;
            i->dist += v;
            if (i->dist > i->history) return invalid(s, i, "invalid distance too far back");
            i->phase = I_MATCH;
            break;
        case I_MATCH:
            while (i->length) {
                if (!s->avail_out) goto pause;
                emit(s, i, i->ring[(i->head - i->dist) & (i->window - 1)]);
                i->length--;
            }
            i->phase = I_SYMBOL;
            break;
        case I_TRAILER:
            if (!read_bits(s, i, 32, &v)) goto pause;
            if (i->wrap == GZIP) {
                if (v != ~i->checksum) return invalid(s, i, "incorrect gzip data check");
                i->phase = I_G_SIZE;
            } else {
                if (__builtin_bswap32(v) != i->checksum) return invalid(s, i, "incorrect data check");
                i->phase = I_DONE;
            }
            break;
        case I_G_SIZE:
            if (!read_bits(s, i, 32, &v)) goto pause;
            if (v != (uint32_t)s->total_out) return invalid(s, i, "incorrect gzip length check");
            i->phase = I_DONE;
            break;
        case I_DONE:
            s->data_type = 64;
            return Z_STREAM_END;
        case I_BAD:
            return Z_DATA_ERROR;
        }
        if ((flush == Z_BLOCK || flush == Z_TREES) && (boundary || (flush == Z_TREES && tree_ready)))
            goto pause;
        boundary = tree_ready = 0;
    }
pause:
    s->data_type = i->nbits + 64 * i->last + 128 * boundary + 256 * tree_ready;
    if (flush == Z_FINISH || (s->total_in == start_in && s->total_out == start_out && !boundary && !tree_ready))
        return Z_BUF_ERROR;
    return Z_OK;
}
DX_EXPORT("_inflate", dz_inflate);
