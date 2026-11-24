#ifndef BITTEN_ZLIB_INTERNAL_H
#define BITTEN_ZLIB_INTERNAL_H

#include "dx.h"

enum {
    Z_NO_FLUSH = 0, Z_PARTIAL_FLUSH = 1, Z_SYNC_FLUSH = 2, Z_FULL_FLUSH = 3, Z_FINISH = 4,
    Z_BLOCK = 5, Z_TREES = 6,
    Z_OK = 0, Z_STREAM_END = 1, Z_NEED_DICT = 2, Z_ERRNO = -1, Z_STREAM_ERROR = -2,
    Z_DATA_ERROR = -3, Z_MEM_ERROR = -4, Z_BUF_ERROR = -5, Z_VERSION_ERROR = -6,
    Z_DEFLATED = 8, Z_UNKNOWN = 2,
};

enum wrapper { RAW, ZLIB, GZIP, AUTO };

typedef struct {
    const uint8_t *next_in;
    unsigned avail_in;
    unsigned long total_in;
    uint8_t *next_out;
    unsigned avail_out;
    unsigned long total_out;
    const char *msg;
    void *state;
    void *(*zalloc)(void *, unsigned, unsigned);
    void (*zfree)(void *, void *);
    void *opaque;
    int data_type;
    unsigned long adler, reserved;
} dz_stream;
_Static_assert(sizeof(dz_stream) == 112 && offsetof(dz_stream, adler) == 96, "Darwin z_stream");

#define DZ_VERSION "1.2.12"

int dz_allocators(dz_stream *, const char *, int);
int dz_inflate_init(dz_stream *, int, const char *, int);
int dz_inflate(dz_stream *, int);
int dz_inflate_end(dz_stream *);
int dz_deflate_init(dz_stream *, int, int, int, int, int, const char *, int);
int dz_deflate(dz_stream *, int);
int dz_deflate_end(dz_stream *);
unsigned long dz_bound(unsigned long, enum wrapper);

unsigned long dz_crc32(unsigned long, const uint8_t *, size_t);
unsigned long dz_adler32(unsigned long, const uint8_t *, size_t);
uint32_t dz_crc_byte(uint32_t, uint8_t);

extern const uint16_t dz_length_base[29], dz_dist_base[30];
extern const uint8_t dz_length_extra[29], dz_dist_extra[30];

#endif
