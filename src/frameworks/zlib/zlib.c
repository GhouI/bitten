#include <limits.h>
#include <pthread.h>
#include <stdlib.h>

#include "zlib_internal.h"

const uint16_t dz_length_base[29] = {
    3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258
};
const uint8_t dz_length_extra[29] = {
    0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0
};
const uint16_t dz_dist_base[30] = {
    1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,
    1025,1537,2049,3073,4097,6145,8193,12289,16385,24577
};
const uint8_t dz_dist_extra[30] = {
    0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13
};

static const char *d_zlibVersion(void) { return DZ_VERSION; }
DX_FN(zlibVersion);

static const char *d_zError(int error) {
    switch (error) {
    case Z_NEED_DICT: return "need dictionary";
    case Z_STREAM_END: return "stream end";
    case Z_ERRNO: return "file error";
    case Z_STREAM_ERROR: return "stream error";
    case Z_DATA_ERROR: return "data error";
    case Z_MEM_ERROR: return "insufficient memory";
    case Z_BUF_ERROR: return "buffer error";
    case Z_VERSION_ERROR: return "incompatible version";
    default: return "";
    }
}
DX_FN(zError);

static void *allocate(void *opaque, unsigned n, unsigned size) {
    (void)opaque;
    return calloc(n, size);
}

static void deallocate(void *opaque, void *p) {
    (void)opaque;
    free(p);
}

int dz_allocators(dz_stream *s, const char *ver, int size) {
    if (!ver || ver[0] != DZ_VERSION[0] || size != sizeof *s) return Z_VERSION_ERROR;
    if (!s) return Z_STREAM_ERROR;
    s->msg = NULL;
    s->state = NULL;
    if (!s->zalloc) {
        s->zalloc = allocate;
        s->opaque = NULL;
    }
    if (!s->zfree) s->zfree = deallocate;
    return Z_OK;
}

static uint32_t crc_table[256];
static pthread_once_t crc_once = PTHREAD_ONCE_INIT;

static void make_crc_table(void) {
    for (unsigned i = 0; i < 256; i++) {
        uint32_t crc = i;
        for (unsigned j = 0; j < 8; j++)
            crc = (crc >> 1) ^ (0xedb88320 & (0u - (crc & 1)));
        crc_table[i] = crc;
    }
}

static const uint32_t *d_get_crc_table(void) {
    pthread_once(&crc_once, make_crc_table);
    return crc_table;
}
DX_FN(get_crc_table);

uint32_t dz_crc_byte(uint32_t crc, uint8_t byte) {
    return crc_table[(crc ^ byte) & 255] ^ (crc >> 8);
}

unsigned long dz_crc32(unsigned long crc, const uint8_t *p, size_t size) {
    if (!p) return 0;
    d_get_crc_table();
    uint32_t c = ~(uint32_t)crc;
    while (size--) c = dz_crc_byte(c, *p++);
    return ~c;
}
DX_EXPORT("_crc32_z", dz_crc32);

static unsigned long d_crc32(unsigned long crc, const uint8_t *p, unsigned size) {
    return dz_crc32(crc, p, size);
}
DX_FN(crc32);

static uint32_t crc_product(uint32_t a, uint32_t b) {
    uint32_t product = 0;
    for (unsigned i = 0; i < 32; i++) {
        if (a & (UINT32_C(1) << (31-i))) product ^= b;
        b = (b >> 1) ^ (0xedb88320 & (0u - (b & 1)));
    }
    return product;
}

static unsigned long d_crc32_combine(unsigned long first, unsigned long second, long length) {
    if (length < 0) return (uint32_t)first;
    uint32_t power = UINT32_C(1) << 23;
    while (length) {
        if (length & 1) first = crc_product((uint32_t)first, power);
        length >>= 1;
        if (length) power = crc_product(power, power);
    }
    return (uint32_t)first ^ (uint32_t)second;
}
DX_FN(crc32_combine);

unsigned long dz_adler32(unsigned long adler, const uint8_t *p, size_t size) {
    if (!p) return 1;
    uint32_t a = adler & 65535, b = (adler >> 16) & 65535;
    while (size) {
        size_t n = size > 5552 ? 5552 : size;
        size -= n;
        while (n--) {
            a += *p++;
            b += a;
        }
        a %= 65521;
        b %= 65521;
    }
    return (uint32_t)(b << 16 | a);
}
DX_EXPORT("_adler32_z", dz_adler32);

static unsigned long d_adler32(unsigned long adler, const uint8_t *p, unsigned size) {
    return dz_adler32(adler, p, size);
}
DX_FN(adler32);

static unsigned long d_compressBound(unsigned long len) {
    /* The encoder falls back to stored blocks whenever fixed codes are larger. */
    unsigned long extra = (len >> 12) + (len >> 14) + (len >> 25) + 13;
    return len <= ULONG_MAX - extra ? len + extra : ULONG_MAX;
}
DX_FN(compressBound);

unsigned long dz_bound(unsigned long len, enum wrapper wrap) {
    unsigned long extra = (len >> 12) + (len >> 14) + (len >> 25) + (wrap == GZIP ? 25 : 13);
    return len <= ULONG_MAX - extra ? len + extra : ULONG_MAX;
}

static int d_compress2(uint8_t *out, unsigned long *outlen, const uint8_t *in, unsigned long inlen,
                       int level) {
    if (!outlen || (!out && *outlen) || (!in && inlen)) return Z_STREAM_ERROR;
    dz_stream s = {0};
    int status = dz_deflate_init(&s, level, Z_DEFLATED, 15, 8, 0, DZ_VERSION, sizeof s);
    if (status != Z_OK) return status;
    s.next_in = in;
    s.next_out = out;
    unsigned long remaining = *outlen;
    do {
        if (!s.avail_in) {
            s.avail_in = inlen > UINT_MAX ? UINT_MAX : inlen;
            inlen -= s.avail_in;
        }
        if (!s.avail_out) {
            s.avail_out = remaining > UINT_MAX ? UINT_MAX : remaining;
            remaining -= s.avail_out;
            if (!s.avail_out) { status = Z_BUF_ERROR; break; }
        }
        status = dz_deflate(&s, inlen ? Z_NO_FLUSH : Z_FINISH);
    } while (status == Z_OK);
    *outlen = s.total_out;
    dz_deflate_end(&s);
    return status == Z_STREAM_END ? Z_OK : status;
}
DX_FN(compress2);

static int d_compress(uint8_t *out, unsigned long *outlen, const uint8_t *in, unsigned long inlen) {
    return d_compress2(out, outlen, in, inlen, -1);
}
DX_FN(compress);

static int d_uncompress2(uint8_t *out, unsigned long *outlen, const uint8_t *in, unsigned long *inlen) {
    if (!outlen || !inlen || (!out && *outlen) || (!in && *inlen)) return Z_STREAM_ERROR;
    dz_stream s = {0};
    int status = dz_inflate_init(&s, 15, DZ_VERSION, sizeof s);
    if (status != Z_OK) return status;
    uint8_t sink;
    int sink_only = *outlen == 0;
    s.next_in = in;
    s.next_out = sink_only ? &sink : out;
    unsigned long input = *inlen, output = sink_only ? 1 : *outlen;
    do {
        if (!s.avail_in) {
            s.avail_in = input > UINT_MAX ? UINT_MAX : input;
            input -= s.avail_in;
        }
        if (!s.avail_out) {
            s.avail_out = output > UINT_MAX ? UINT_MAX : output;
            output -= s.avail_out;
        }
        status = dz_inflate(&s, Z_NO_FLUSH);
    } while (status == Z_OK);
    *inlen = s.total_in;
    *outlen = sink_only ? 0 : s.total_out;
    int exhausted = !output && !s.avail_out && !(sink_only && s.total_out);
    dz_inflate_end(&s);
    if (status == Z_STREAM_END) return Z_OK;
    if (status == Z_NEED_DICT || (status == Z_BUF_ERROR && !exhausted)) return Z_DATA_ERROR;
    return status;
}
DX_FN(uncompress2);

static int d_uncompress(uint8_t *out, unsigned long *outlen, const uint8_t *in, unsigned long inlen) {
    return d_uncompress2(out, outlen, in, &inlen);
}
DX_FN(uncompress);
