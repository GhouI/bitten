#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "../zlib/zlib_internal.h"

enum { COMPRESSION_LZ4 = 0x100, COMPRESSION_LZ4_RAW = 0x101, COMPRESSION_ZLIB = 0x205 };
enum { CMP_ERROR = -1, CMP_OK, CMP_END };
enum { CMP_ENCODE, CMP_DECODE, CMP_FINALIZE = 1 };

struct compression_stream {
    uint8_t *dst_ptr;
    size_t dst_size;
    const uint8_t *src_ptr;
    size_t src_size;
    void *state;
};
_Static_assert(sizeof(struct compression_stream) == 40, "Darwin compression_stream");

struct compression_state {
    dz_stream z;
    int operation;
};

static int d_compression_stream_init(struct compression_stream *s, int operation, int algorithm) {
    if (!s) return CMP_ERROR;
    memset(s, 0, sizeof *s);
    if (algorithm != COMPRESSION_ZLIB || (operation != CMP_ENCODE && operation != CMP_DECODE))
        return CMP_ERROR;
    struct compression_state *c = calloc(1, sizeof *c);
    if (!c) return CMP_ERROR;
    c->operation = operation;
    int status = operation == CMP_ENCODE
        ? dz_deflate_init(&c->z, 5, Z_DEFLATED, -15, 8, 0, DZ_VERSION, sizeof c->z)
        : dz_inflate_init(&c->z, -15, DZ_VERSION, sizeof c->z);
    if (status != Z_OK) {
        free(c);
        return CMP_ERROR;
    }
    s->state = c;
    return CMP_OK;
}
DX_FN(compression_stream_init);

static int d_compression_stream_process(struct compression_stream *s, int flags) {
    if (!s || !s->state || (flags & ~CMP_FINALIZE) ||
        (!s->dst_ptr && s->dst_size) || (!s->src_ptr && s->src_size)) return CMP_ERROR;
    struct compression_state *c = s->state;
    if (!s->dst_size) return CMP_OK;
    dz_stream *z = &c->z;
    for (;;) {
        unsigned in = s->src_size > UINT_MAX ? UINT_MAX : s->src_size;
        unsigned out = s->dst_size > UINT_MAX ? UINT_MAX : s->dst_size;
        z->next_in = s->src_ptr;
        z->next_out = s->dst_ptr;
        z->avail_in = in;
        z->avail_out = out;
        int flush = (flags & CMP_FINALIZE) && s->src_size == in ? Z_FINISH : Z_NO_FLUSH;
        int status = c->operation == CMP_ENCODE ? dz_deflate(z, flush) : dz_inflate(z, flush);
        s->src_ptr = z->next_in;
        s->dst_ptr = z->next_out;
        s->src_size -= in - z->avail_in;
        s->dst_size -= out - z->avail_out;
        if (status == Z_STREAM_END) return CMP_END;
        if (status != Z_OK && status != Z_BUF_ERROR) return CMP_ERROR;
        if (!s->dst_size) return CMP_OK;
        if (c->operation == CMP_DECODE && flush == Z_FINISH && !s->src_size && z->avail_out)
            return CMP_ERROR;
        if ((!s->src_size && z->avail_out) || (z->avail_in == in && z->avail_out == out))
            return CMP_OK;
    }
}
DX_FN(compression_stream_process);

static int d_compression_stream_destroy(struct compression_stream *s) {
    if (!s || !s->state) return CMP_ERROR;
    struct compression_state *c = s->state;
    if (c->operation == CMP_ENCODE) dz_deflate_end(&c->z);
    else dz_inflate_end(&c->z);
    free(c);
    s->state = NULL;
    return CMP_OK;
}
DX_FN(compression_stream_destroy);

static size_t d_compression_encode_scratch_buffer_size(int algorithm) { (void)algorithm; return 0; }
DX_FN(compression_encode_scratch_buffer_size);
static size_t d_compression_decode_scratch_buffer_size(int algorithm) { (void)algorithm; return 0; }
DX_FN(compression_decode_scratch_buffer_size);

static uint32_t load_word(const uint8_t *p) {
    uint32_t value;
    memcpy(&value, p, 4);
    return value;
}

static size_t extra_bytes(size_t length) {
    return length < 15 ? 0 : 1 + (length - 15) / 255;
}

static void write_extra(uint8_t **out, size_t length) {
    if (length < 15) return;
    length -= 15;
    while (length >= 255) {
        *(*out)++ = 255;
        length -= 255;
    }
    *(*out)++ = length;
}

static int sequence(uint8_t **out, size_t *cap, const uint8_t *literals, size_t count,
                    unsigned distance, size_t match) {
    size_t code = distance ? match - 4 : 0;
    size_t extra = 1 + extra_bytes(count) + (distance ? 2 + extra_bytes(code) : 0);
    if (extra > *cap || count > *cap - extra) return 0;
    *cap -= count + extra;
    *(*out)++ = ((count < 15 ? count : 15) << 4) | (code < 15 ? code : 15);
    write_extra(out, count);
    if (count) memcpy(*out, literals, count);
    *out += count;
    if (distance) {
        *(*out)++ = distance;
        *(*out)++ = distance >> 8;
        write_extra(out, code);
    }
    return 1;
}

static size_t encode_lz4(uint8_t *out, size_t cap, const uint8_t *in, size_t size) {
    size_t offsets[4096] = {0};
    size_t anchor = 0, available = cap;
    for (size_t i = 0; size - i >= 12;) {
        uint32_t word = load_word(in + i);
        unsigned hash = (word * 2654435761u) >> 20;
        size_t prior = offsets[hash];
        offsets[hash] = i + 1;
        if (!prior || i - (prior - 1) > 65535 || load_word(in + prior - 1) != word) {
            i++;
            continue;
        }
        prior--;
        size_t length = 4;
        while (length < size - i - 5 && in[prior + length] == in[i + length]) length++;
        if (!sequence(&out, &available, in + anchor, i - anchor, i - prior, length)) return 0;
        i += length;
        anchor = i;
    }
    if (!sequence(&out, &available, anchor ? in + anchor : in, size - anchor, 0, 0)) return 0;
    return cap - available;
}

static int read_extra(const uint8_t **in, size_t *left, size_t *length) {
    if (*length != 15) return 1;
    unsigned byte;
    do {
        if (!*left) return 0;
        byte = *(*in)++;
        (*left)--;
        if (*length > SIZE_MAX - byte) return 0;
        *length += byte;
    } while (byte == 255);
    return 1;
}

/* The output preceding the block remains available for framed back-references. */
static int decode_lz4(uint8_t *out, size_t *pos, size_t cap, size_t expected,
                      const uint8_t *in, size_t size) {
    if (!size) return CMP_ERROR;
    do {
        unsigned token = *in++;
        size--;
        size_t length = token >> 4;
        if (!read_extra(&in, &size, &length) || length > size || length > expected - *pos)
            return CMP_ERROR;
        size_t n = length < cap - *pos ? length : cap - *pos;
        if (n) memcpy(out + *pos, in, n);
        *pos += n;
        if (n < length) return CMP_OK;
        in += n;
        size -= n;
        if (!size) return CMP_END;
        if (size < 2) return CMP_ERROR;
        size_t distance = in[0] | (in[1] << 8);
        if (!distance || distance > *pos) return CMP_ERROR;
        in += 2;
        size -= 2;
        length = token & 15;
        if (!read_extra(&in, &size, &length) || length > SIZE_MAX - 4) return CMP_ERROR;
        length += 4;
        if (length > expected - *pos) return CMP_ERROR;
        n = length < cap - *pos ? length : cap - *pos;
        size_t from = *pos - distance;
        for (size_t j = 0; j < n; j++) out[*pos + j] = out[from + j];
        *pos += n;
        if (n < length) return CMP_OK;
    } while (size);
    return CMP_ERROR;
}

static size_t encode_lz4_frame(uint8_t *out, size_t cap, const uint8_t *in, size_t size) {
    size_t total = 0;
    while (size) {
        if (cap - total < 12) return 0;
        uint32_t n = size > 65536 ? 65536 : size;
        uint8_t *block = out + total;
        size_t compressed = encode_lz4(block + 12, cap - total - 12, in, n);
        if (compressed && compressed + 4 < n) {
            memcpy(block, "bv41", 4);
            memcpy(block + 4, &n, 4);
            uint32_t encoded = compressed;
            memcpy(block + 8, &encoded, 4);
            total += 12 + encoded;
        } else {
            if (cap - total - 8 < n) return 0;
            memcpy(block, "bv4-", 4);
            memcpy(block + 4, &n, 4);
            memcpy(block + 8, in, n);
            total += 8 + n;
        }
        in += n;
        size -= n;
    }
    if (cap - total < 4) return 0;
    memcpy(out + total, "bv4$", 4);
    return total + 4;
}

static size_t decode_lz4_frame(uint8_t *out, size_t cap, const uint8_t *in, size_t size) {
    size_t pos = 0;
    while (size >= 4) {
        if (memcmp(in, "bv4", 3)) return 0;
        if (in[3] == '$') return pos;
        int compressed = in[3] == '1';
        if ((!compressed && in[3] != '-') || size < (compressed ? 12u : 8u)) return 0;
        size_t plain = load_word(in + 4);
        size_t encoded = compressed ? load_word(in + 8) : plain;
        unsigned header = compressed ? 12 : 8;
        in += header;
        size -= header;
        if (encoded > size || plain > SIZE_MAX - pos) return 0;
        if (compressed) {
            size_t end = pos + plain;
            int status = decode_lz4(out, &pos, cap, end, in, encoded);
            if (status == CMP_OK) return pos;
            if (status != CMP_END || pos != end) return 0;
        } else {
            size_t n = plain < cap - pos ? plain : cap - pos;
            if (n) memcpy(out + pos, in, n);
            pos += n;
            if (n < plain) return pos;
        }
        in += encoded;
        size -= encoded;
    }
    return 0;
}

static size_t zlib_buffer(int operation, uint8_t *out, size_t cap, const uint8_t *in, size_t len) {
    struct compression_stream s;
    if (d_compression_stream_init(&s, operation, COMPRESSION_ZLIB) != CMP_OK) return 0;
    s.dst_ptr = out;
    s.dst_size = cap;
    s.src_ptr = in;
    s.src_size = len;
    int status = d_compression_stream_process(&s, CMP_FINALIZE);
    d_compression_stream_destroy(&s);
    if (status == CMP_END || (operation == CMP_DECODE && status == CMP_OK && !s.dst_size))
        return cap - s.dst_size;
    return 0;
}

static size_t d_compression_encode_buffer(uint8_t *out, size_t cap, const uint8_t *in, size_t size,
                                         void *scratch, int algorithm) {
    (void)scratch;
    if (!out || !cap || (!in && size)) return 0;
    switch (algorithm) {
    case COMPRESSION_ZLIB: return zlib_buffer(CMP_ENCODE, out, cap, in, size);
    case COMPRESSION_LZ4: return encode_lz4_frame(out, cap, in, size);
    case COMPRESSION_LZ4_RAW: return encode_lz4(out, cap, in, size);
    default: return 0;
    }
}
DX_FN(compression_encode_buffer);

static size_t d_compression_decode_buffer(uint8_t *out, size_t cap, const uint8_t *in, size_t size,
                                         void *scratch, int algorithm) {
    (void)scratch;
    if (!out || !cap || (!in && size)) return 0;
    switch (algorithm) {
    case COMPRESSION_ZLIB: return zlib_buffer(CMP_DECODE, out, cap, in, size);
    case COMPRESSION_LZ4: return decode_lz4_frame(out, cap, in, size);
    case COMPRESSION_LZ4_RAW: {
        size_t written = 0;
        return decode_lz4(out, &written, cap, SIZE_MAX, in, size) == CMP_ERROR ? 0 : written;
    }
    default: return 0;
    }
}
DX_FN(compression_decode_buffer);
