#include <string.h>

#include "zlib_internal.h"

enum { BLOCK = 32768, HASH = 32768 };
enum { DEFAULT, FILTERED, HUFFMAN_ONLY, RLE, FIXED };

struct deflater {
    dz_stream *owner;
    enum wrapper wrap;
    unsigned window_bits, level, strategy;
    unsigned history, filled, begin, end;
    unsigned bits, nbits;
    int started, finishing, last_flush;
    uint32_t checksum;
    unsigned long flush_at;
    uint8_t input[2*BLOCK], pending[2*BLOCK];
    int heads[HASH], previous[2*BLOCK];
};

static void reset(dz_stream *s, struct deflater *d) {
    d->history = d->filled = d->begin = d->end = 0;
    d->bits = d->nbits = 0;
    d->started = d->finishing = 0;
    d->last_flush = Z_NO_FLUSH;
    d->flush_at = 0;
    d->checksum = d->wrap == GZIP ? 0 : 1;
    s->adler = d->checksum;
    s->total_in = s->total_out = 0;
    s->msg = NULL;
    s->data_type = Z_UNKNOWN;
}

int dz_deflate_init(dz_stream *s, int level, int method, int bits, int memory, int strategy,
                    const char *version, int size) {
    int status = dz_allocators(s, version, size);
    if (status != Z_OK) return status;
    if (level == -1) level = 6;
    if (level < 0 || level > 9 || method != Z_DEFLATED || memory < 1 || memory > 9 ||
        strategy < DEFAULT || strategy > FIXED) return Z_STREAM_ERROR;
    enum wrapper wrap;
    if (bits >= -15 && bits <= -9) {
        wrap = RAW;
        bits = -bits;
    } else if (bits >= 8 && bits <= 15) {
        wrap = ZLIB;
        if (bits == 8) bits = 9;
    } else if (bits >= 25 && bits <= 31) {
        wrap = GZIP;
        bits -= 16;
    } else {
        return Z_STREAM_ERROR;
    }
    struct deflater *d = s->zalloc(s->opaque, 1, sizeof *d);
    if (!d) return Z_MEM_ERROR;
    d->owner = s;
    d->wrap = wrap;
    d->window_bits = bits;
    d->level = level;
    d->strategy = strategy;
    s->state = d;
    reset(s, d);
    return Z_OK;
}
DX_EXPORT("_deflateInit2_", dz_deflate_init);

static int d_deflateInit_(dz_stream *s, int level, const char *version, int size) {
    return dz_deflate_init(s, level, Z_DEFLATED, 15, 8, DEFAULT, version, size);
}
DX_FN(deflateInit_);

static struct deflater *state(dz_stream *s) {
    struct deflater *d = s && s->zalloc && s->zfree ? s->state : NULL;
    return d && d->owner == s ? d : NULL;
}

static int d_deflateReset(dz_stream *s) {
    struct deflater *d = state(s);
    if (!d) return Z_STREAM_ERROR;
    reset(s, d);
    return Z_OK;
}
DX_FN(deflateReset);

int dz_deflate_end(dz_stream *s) {
    struct deflater *d = state(s);
    if (!d) return Z_STREAM_ERROR;
    int status = d->started && (!d->finishing || d->end != d->begin) ? Z_DATA_ERROR : Z_OK;
    s->zfree(s->opaque, d);
    s->state = NULL;
    return status;
}
DX_EXPORT("_deflateEnd", dz_deflate_end);

static unsigned long d_deflateBound(dz_stream *s, unsigned long len) {
    struct deflater *d = state(s);
    return dz_bound(len, d ? d->wrap : GZIP);
}
DX_FN(deflateBound);

static void bytes(struct deflater *d, uint32_t v, unsigned n) {
    while (n--) {
        d->pending[d->end++] = v;
        v >>= 8;
    }
}

static void bits(struct deflater *d, unsigned v, unsigned n) {
    d->bits |= v << d->nbits;
    d->nbits += n;
    while (d->nbits >= 8) {
        bytes(d, d->bits, 1);
        d->bits >>= 8;
        d->nbits -= 8;
    }
}

static void align_byte(struct deflater *d) {
    if (d->nbits) bits(d, 0, 8 - d->nbits);
}

static void header(struct deflater *d) {
    if (d->wrap == ZLIB) {
        unsigned cmf = ((d->window_bits - 8) << 4) | Z_DEFLATED;
        unsigned flg = (d->level < 2 ? 0 : d->level < 6 ? 1 : d->level == 6 ? 2 : 3) << 6;
        flg += (31 - ((cmf << 8) | flg) % 31) % 31;
        bytes(d, cmf | (flg << 8), 2);
    } else if (d->wrap == GZIP) {
        bytes(d, 0x00088b1f, 4);
        bytes(d, 0, 4);
        bytes(d, 0x300 | (d->level == 9 ? 2 : d->level < 2 ? 4 : 0), 2);
    }
}

static void trailer(dz_stream *s, struct deflater *d) {
    align_byte(d);
    if (d->wrap == ZLIB) bytes(d, __builtin_bswap32(d->checksum), 4);
    if (d->wrap == GZIP) {
        bytes(d, d->checksum, 4);
        bytes(d, s->total_in, 4);
    }
}

static void stored(struct deflater *d, const uint8_t *data, unsigned n, unsigned last) {
    bits(d, last, 3);
    align_byte(d);
    bytes(d, n | ((n ^ 65535) << 16), 4);
    if (n) memcpy(d->pending + d->end, data, n);
    d->end += n;
}

static unsigned reverse(unsigned v, unsigned n) {
    unsigned r = 0;
    while (n--) {
        r = (r << 1) | (v & 1);
        v >>= 1;
    }
    return r;
}

static void literal(struct deflater *d, unsigned symbol) {
    if (symbol < 144) bits(d, reverse(48 + symbol, 8), 8);
    else if (symbol < 256) bits(d, reverse(400 + symbol - 144, 9), 9);
    else if (symbol < 280) bits(d, reverse(symbol - 256, 7), 7);
    else bits(d, reverse(192 + symbol - 280, 8), 8);
}

static unsigned code_for(const uint16_t *base, unsigned n, unsigned value) {
    unsigned lo = 0, hi = n;
    while (hi - lo > 1) {
        unsigned mid = (lo + hi) / 2;
        if (base[mid] <= value) lo = mid;
        else hi = mid;
    }
    return lo;
}

static void match(struct deflater *d, unsigned len, unsigned dist) {
    unsigned i = code_for(dz_length_base, 29, len);
    literal(d, 257 + i);
    bits(d, len - dz_length_base[i], dz_length_extra[i]);
    i = code_for(dz_dist_base, 30, dist);
    bits(d, reverse(i, 5), 5);
    bits(d, dist - dz_dist_base[i], dz_dist_extra[i]);
}

static unsigned hash_at(const uint8_t *p) {
    return ((p[0] * 251u + p[1]) * 251u + p[2]) & (HASH - 1);
}

static void insert(struct deflater *d, unsigned p) {
    unsigned hash = hash_at(d->input + p);
    d->previous[p] = d->heads[hash];
    d->heads[hash] = p;
}

static unsigned find_match(struct deflater *d, unsigned pos, unsigned limit, unsigned *distance) {
    static const unsigned depths[] = {0, 4, 8, 16, 32, 48, 64, 96, 160, 256};
    unsigned depth = depths[d->level], best = d->strategy == FILTERED ? 4 : 2;
    unsigned lowest = pos > (1u << d->window_bits) ? pos - (1u << d->window_bits) : 0;
    int candidate = d->heads[hash_at(d->input + pos)];
    if (limit <= best) return 0;
    const uint8_t *p = d->input + pos;
    while (candidate >= (int)lowest && depth--) {
        const uint8_t *q = d->input + candidate;
        if (q[best] == p[best] && q[0] == p[0] && q[1] == p[1] && q[2] == p[2]) {
            unsigned len = 3;
            while (len < limit && p[len] == q[len]) len++;
            if (len > best) {
                best = len;
                *distance = pos - (unsigned)candidate;
                if (len == limit) break;
            }
        }
        candidate = d->previous[candidate];
    }
    return *distance ? best : 0;
}

static void fixed(struct deflater *d, unsigned last) {
    unsigned stop = d->history + d->filled;
    int chains = d->strategy != HUFFMAN_ONLY && d->strategy != RLE && d->filled >= 3;
    bits(d, last | 2, 3);
    if (chains) {
        memset(d->heads, 0xff, sizeof d->heads);
        for (unsigned i = 0; i < d->history; i++) insert(d, i);
    }
    for (unsigned i = d->history; i < stop;) {
        unsigned len = 0, distance = 0, limit = stop - i;
        if (limit > 258) limit = 258;
        if (limit >= 3) {
            if (chains) {
                len = find_match(d, i, limit, &distance);
            } else if (d->strategy == RLE && i) {
                while (len < limit && d->input[i+len] == d->input[i-1]) len++;
                distance = 1;
            }
        }
        if (len >= 3) {
            match(d, len, distance);
        } else {
            literal(d, d->input[i]);
            len = 1;
        }
        unsigned next = i + len;
        if (chains) {
            for (; i < next && i + 2 < stop; i++) insert(d, i);
        }
        i = next;
    }
    literal(d, 256);
}

static void block(struct deflater *d, unsigned last) {
    if (!d->level) {
        stored(d, d->input + d->history, d->filled, last);
    } else {
        unsigned saved_end = d->end, saved_bits = d->bits, saved_nbits = d->nbits;
        unsigned align = (saved_nbits + 3 + 7) / 8;
        fixed(d, last);
        if (8 * (d->end - saved_end) + d->nbits > 8 * (align + 4 + d->filled)) {
            d->end = saved_end;
            d->bits = saved_bits;
            d->nbits = saved_nbits;
            stored(d, d->input + d->history, d->filled, last);
        }
    }
    unsigned total = d->history + d->filled;
    unsigned window = 1u << d->window_bits;
    d->history = total < window ? total : window;
    memmove(d->input, d->input + total - d->history, d->history);
    d->filled = 0;
}

static void drain(dz_stream *s, struct deflater *d) {
    unsigned n = d->end - d->begin;
    if (n > s->avail_out) n = s->avail_out;
    if (n) {
        memcpy(s->next_out, d->pending + d->begin, n);
        s->next_out += n;
        s->avail_out -= n;
        s->total_out += n;
    }
    d->begin += n;
    if (d->begin == d->end) d->begin = d->end = 0;
}

static void fill(dz_stream *s, struct deflater *d) {
    unsigned n = BLOCK - d->filled;
    if (n > s->avail_in) n = s->avail_in;
    if (!n) return;
    memcpy(d->input + d->history + d->filled, s->next_in, n);
    if (d->wrap == ZLIB) d->checksum = dz_adler32(d->checksum, s->next_in, n);
    if (d->wrap == GZIP) d->checksum = dz_crc32(d->checksum, s->next_in, n);
    s->adler = d->checksum;
    d->filled += n;
    s->next_in += n;
    s->avail_in -= n;
    s->total_in += n;
}

static int flush_rank(int flush) {
    return flush == Z_BLOCK ? 1 : flush ? flush + 1 : 0;
}

int dz_deflate(dz_stream *s, int flush) {
    struct deflater *d = state(s);
    if (!d || !s->next_out || (s->avail_in && !s->next_in) ||
        flush < Z_NO_FLUSH || flush > Z_BLOCK || (d->finishing && flush != Z_FINISH))
        return Z_STREAM_ERROR;
    if (!s->avail_out || (d->finishing && s->avail_in)) return Z_BUF_ERROR;
    unsigned long start_in = s->total_in, start_out = s->total_out;
    if (!d->started) {
        d->started = 1;
        header(d);
    }
    for (;;) {
        drain(s, d);
        if (d->finishing && !d->end) return Z_STREAM_END;
        if (!s->avail_out) return Z_OK;
        fill(s, d);
        if (flush == Z_FINISH && !s->avail_in) {
            block(d, 1);
            trailer(s, d);
            d->finishing = 1;
        } else if (d->filled == BLOCK) {
            block(d, 0);
        } else if (flush && (d->flush_at != s->total_in ||
                             flush_rank(flush) > flush_rank(d->last_flush))) {
            if (d->filled) block(d, 0);
            if (flush == Z_PARTIAL_FLUSH) {
                bits(d, 2, 3);
                literal(d, 256);
            } else if (flush != Z_BLOCK) {
                stored(d, NULL, 0, 0);
            }
            if (flush == Z_FULL_FLUSH) d->history = 0;
            d->flush_at = s->total_in;
            d->last_flush = flush;
            drain(s, d);
            return Z_OK;
        } else {
            if (flush == Z_NO_FLUSH) d->last_flush = Z_NO_FLUSH;
            return s->total_in != start_in || s->total_out != start_out ? Z_OK : Z_BUF_ERROR;
        }
    }
}
DX_EXPORT("_deflate", dz_deflate);
