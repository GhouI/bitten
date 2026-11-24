#include "darwin.h"

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
} z_stream;

_Static_assert(sizeof(z_stream) == 112, "z_stream");
const char *zlibVersion(void);
const char *zError(int);
int inflateInit_(z_stream *, const char *, int);
int inflateInit2_(z_stream *, int, const char *, int);
int inflate(z_stream *, int);
int inflateEnd(z_stream *);
int inflateReset(z_stream *);
int inflateReset2(z_stream *, int);
int inflateSetDictionary(z_stream *, const uint8_t *, unsigned);
int deflateInit_(z_stream *, int, const char *, int);
int deflateInit2_(z_stream *, int, int, int, int, int, const char *, int);
int deflate(z_stream *, int);
int deflateEnd(z_stream *);
int deflateReset(z_stream *);
unsigned long deflateBound(z_stream *, unsigned long);
int compress(uint8_t *, unsigned long *, const uint8_t *, unsigned long);
int compress2(uint8_t *, unsigned long *, const uint8_t *, unsigned long, int);
unsigned long compressBound(unsigned long);
int uncompress(uint8_t *, unsigned long *, const uint8_t *, unsigned long);
int uncompress2(uint8_t *, unsigned long *, const uint8_t *, unsigned long *);
unsigned long crc32(unsigned long, const uint8_t *, unsigned);
unsigned long crc32_z(unsigned long, const uint8_t *, size_t);
unsigned long crc32_combine(unsigned long, unsigned long, long);
unsigned long adler32(unsigned long, const uint8_t *, unsigned);
unsigned long adler32_z(unsigned long, const uint8_t *, size_t);
const uint32_t *get_crc_table(void);

typedef struct gzfile *gz_file;
gz_file gzopen(const char *, const char *);
gz_file gzdopen(int, const char *);
int gzread(gz_file, void *, unsigned);
int gzwrite(gz_file, const void *, unsigned);
int gzclose(gz_file);
char *gzgets(gz_file, char *, int);
int gzputs(gz_file, const char *);
int gzeof(gz_file);
const char *gzerror(gz_file, int *);
int open(const char *, int, ...);
ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
int close(int);
int unlink(const char *);
int getpid(void);

enum { NO_FLUSH, PARTIAL_FLUSH, SYNC_FLUSH, FULL_FLUSH, FINISH };
enum { OK = 0, END = 1, NEED_DICT = 2, STREAM_ERROR = -2, DATA_ERROR = -3, BUF_ERROR = -5 };

typedef struct {
    uint8_t *dst_ptr;
    size_t dst_size;
    const uint8_t *src_ptr;
    size_t src_size;
    void *state;
} compression_stream;

int compression_stream_init(compression_stream *, int, int);
int compression_stream_process(compression_stream *, int);
int compression_stream_destroy(compression_stream *);
size_t compression_encode_buffer(uint8_t *, size_t, const uint8_t *, size_t, void *, int);
size_t compression_decode_buffer(uint8_t *, size_t, const uint8_t *, size_t, void *, int);
size_t compression_encode_scratch_buffer_size(int);
size_t compression_decode_scratch_buffer_size(int);

static const uint8_t short_text[] = "abc abc abc abc abc abc abc abc!\nabc abc abc abc abc abc abc abc!\n";
static const uint8_t long_text[] = "aaaabbbbccccddddeeeeffffgggghhhh12345\n";
static const uint8_t stored[] = {
    0x78, 0x01, 0x01, 0x42, 0x00, 0xbd, 0xff, 0x61, 0x62, 0x63, 0x20, 0x61,
    0x62, 0x63, 0x20, 0x61, 0x62, 0x63, 0x20, 0x61, 0x62, 0x63, 0x20, 0x61,
    0x62, 0x63, 0x20, 0x61, 0x62, 0x63, 0x20, 0x61, 0x62, 0x63, 0x20, 0x61,
    0x62, 0x63, 0x21, 0x0a, 0x61, 0x62, 0x63, 0x20, 0x61, 0x62, 0x63, 0x20,
    0x61, 0x62, 0x63, 0x20, 0x61, 0x62, 0x63, 0x20, 0x61, 0x62, 0x63, 0x20,
    0x61, 0x62, 0x63, 0x20, 0x61, 0x62, 0x63, 0x20, 0x61, 0x62, 0x63, 0x21,
    0x0a, 0xbc, 0xb3, 0x14, 0x77,
};
static const uint8_t fixed[] = {
    0x4b, 0x4c, 0x4a, 0x56, 0x48, 0xc4, 0x8d, 0x15, 0xb9, 0xf0, 0x48, 0x42,
    0x14, 0x00, 0x00,
};
static const uint8_t dynamic[] = {
    0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xed, 0xca,
    0x47, 0x01, 0x80, 0x40, 0x00, 0x03, 0xb0, 0x3f, 0x6e, 0x58, 0x82, 0x7a,
    0x4c, 0xff, 0x0a, 0xa8, 0x0f, 0x92, 0x77, 0x92, 0x64, 0xd4, 0x51, 0x67,
    0x5d, 0x75, 0xd7, 0x53, 0x6f, 0xcd, 0xcb, 0xba, 0xed, 0x53, 0x2c, 0xcb,
    0xb2, 0x2c, 0xcb, 0xb2, 0x2c, 0xcb, 0xb2, 0x2c, 0xcb, 0xb2, 0x2c, 0xcb,
    0xb2, 0xac, 0x1f, 0xae, 0x0f, 0xfc, 0x92, 0x78, 0x38, 0x44, 0x16, 0x00,
    0x00,
};
static const uint8_t dynamic_zlib[] = {
    0x78, 0x9c, 0xed, 0xca, 0x47, 0x01, 0x80, 0x40, 0x00, 0x03, 0xb0, 0x3f,
    0x6e, 0x58, 0x82, 0x7a, 0x4c, 0xff, 0x0a, 0xa8, 0x0f, 0x92, 0x77, 0x92,
    0x64, 0xd4, 0x51, 0x67, 0x5d, 0x75, 0xd7, 0x53, 0x6f, 0xcd, 0xcb, 0xba,
    0xed, 0x53, 0x2c, 0xcb, 0xb2, 0x2c, 0xcb, 0xb2, 0x2c, 0xcb, 0xb2, 0x2c,
    0xcb, 0xb2, 0x2c, 0xcb, 0xb2, 0xac, 0x1f, 0xae, 0x0f, 0x58, 0xff, 0xf8,
    0x10,
};
static const uint8_t gzip_options[] = {
    0x1f, 0x8b, 0x08, 0x1e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x03, 0x00,
    0x58, 0x59, 0x5a, 0x6e, 0x61, 0x6d, 0x65, 0x00, 0x63, 0x6f, 0x6d, 0x6d,
    0x65, 0x6e, 0x74, 0x00, 0x9f, 0x86, 0xed, 0xca, 0x47, 0x01, 0x80, 0x40,
    0x00, 0x03, 0xb0, 0x3f, 0x6e, 0x58, 0x82, 0x7a, 0x4c, 0xff, 0x0a, 0xa8,
    0x0f, 0x92, 0x77, 0x92, 0x64, 0xd4, 0x51, 0x67, 0x5d, 0x75, 0xd7, 0x53,
    0x6f, 0xcd, 0xcb, 0xba, 0xed, 0x53, 0x2c, 0xcb, 0xb2, 0x2c, 0xcb, 0xb2,
    0x2c, 0xcb, 0xb2, 0x2c, 0xcb, 0xb2, 0x2c, 0xcb, 0xb2, 0xac, 0x1f, 0xae,
    0x0f, 0xfc, 0x92, 0x78, 0x38, 0x44, 0x16, 0x00, 0x00,
};
static const uint8_t dictionary[] = {
    0x78, 0xbb, 0xf0, 0x78, 0x12, 0xd0, 0xc3, 0x25, 0x0e, 0x00, 0x71, 0x6d,
    0x08, 0xd8,
};

static size_t decode(z_stream *s, const uint8_t *in, size_t ilen, uint8_t *out, size_t olen,
                     unsigned in_chunk, unsigned out_chunk) {
    unsigned calls_without_progress = 0;
    size_t given = 0;
    int rc;
    do {
        if (!s->avail_in && given < ilen) {
            unsigned n = ilen - given < in_chunk ? ilen - given : in_chunk;
            s->next_in = in + given;
            s->avail_in = n;
            given += n;
        }
        size_t space = olen - s->total_out;
        s->next_out = out + s->total_out;
        s->avail_out = space < out_chunk ? space : out_chunk;
        unsigned long before_in = s->total_in, before_out = s->total_out;
        rc = inflate(s, SYNC_FLUSH);
        CHECK(rc == OK || rc == END || rc == BUF_ERROR);
        if (s->total_in == before_in && s->total_out == before_out && rc != END)
            CHECK(++calls_without_progress < 2);
        else
            calls_without_progress = 0;
    } while (rc != END);
    return s->total_in;
}

static void reference_tests(void) {
    static const struct { const uint8_t *data; size_t size; int bits; _Bool long_output; } cases[] = {
        {stored, sizeof stored, 15, 0}, {fixed, sizeof fixed, -15, 0},
        {dynamic, sizeof dynamic, 31, 1}, {dynamic, sizeof dynamic, 47, 1},
        {dynamic, sizeof dynamic, 16, 1}, {dynamic, sizeof dynamic, 32, 1},
        {dynamic_zlib, sizeof dynamic_zlib, 47, 1}, {dynamic_zlib, sizeof dynamic_zlib, 0, 1},
        {gzip_options, sizeof gzip_options, 47, 1},
    };
    uint8_t out[150 * (sizeof long_text - 1)];
    z_stream s = {0};
    CHECK(inflateInit_(&s, zlibVersion(), sizeof s) == OK);
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        CHECK(inflateReset2(&s, cases[i].bits) == OK);
        s.avail_in = 0;
        size_t outlen = cases[i].long_output ? sizeof out : sizeof short_text - 1;
        CHECK(decode(&s, cases[i].data, cases[i].size, out, outlen, 1, 1) == cases[i].size);
        CHECK(s.total_out == outlen);
        if (cases[i].long_output) {
            for (size_t j = 0; j < outlen; j += sizeof long_text - 1)
                CHECK(memcmp(out + j, long_text, sizeof long_text - 1) == 0);
        } else {
            CHECK(memcmp(out, short_text, outlen) == 0);
        }
    }
    CHECK(inflateReset2(&s, 15) == OK);
    static const uint8_t dict[] = "prefix for the dictionary, available to both sides.";
    s.next_in = dictionary;
    s.avail_in = sizeof dictionary;
    s.next_out = out;
    s.avail_out = sizeof out;
    CHECK(inflate(&s, NO_FLUSH) == NEED_DICT);
    CHECK(s.adler == adler32(1, dict, sizeof dict - 1));
    CHECK(inflateSetDictionary(&s, dict + 1, sizeof dict - 2) == DATA_ERROR);
    CHECK(inflateSetDictionary(&s, dict, sizeof dict - 1) == OK);
    CHECK(inflate(&s, FINISH) == END);
    CHECK(s.total_out == 24 && memcmp(out, "available to both sides.", 24) == 0);
    CHECK(inflateEnd(&s) == OK);
}

static int output_byte(z_stream *s, int flush, uint8_t *out, size_t cap) {
    CHECK(s->total_out < cap);
    s->next_out = out + s->total_out;
    s->avail_out = 1;
    return deflate(s, flush);
}

static size_t encode(z_stream *s, const uint8_t *in, size_t len, uint8_t *out, size_t cap) {
    while (len) {
        unsigned n = len < 137 ? len : 137;
        s->next_in = in;
        s->avail_in = n;
        do { CHECK(output_byte(s, NO_FLUSH, out, cap) == OK); } while (s->avail_in);
        len -= n;
        in += n;
    }
    int rc;
    do {
        rc = output_byte(s, FINISH, out, cap);
        CHECK(rc == OK || rc == END);
    } while (rc != END);
    return s->total_out;
}

static void roundtrips(void) {
    enum { DATA = 1024 * 1024, RANDOM = 256 * 1024 };
    uint8_t *input = malloc(DATA), *output = malloc(DATA);
    size_t cap = compressBound(DATA) + 1;
    uint8_t *packed = malloc(cap);
    CHECK(input && output && packed);
    const unsigned levels[] = {0, 1, 6, 9};
    const size_t sizes[] = {0, 1, DATA, RANDOM, 17001};
    for (unsigned kind = 0; kind < sizeof sizes / sizeof sizes[0]; kind++) {
        size_t n = sizes[kind];
        uint32_t x = 0x89abcdef;
        for (size_t i = 0; i < n; i++) {
            x ^= x << 13; x ^= x >> 17; x ^= x << 5;
            input[i] = kind == 3 ? x : long_text[i % (sizeof long_text - 1)];
        }
        for (unsigned j = 0; j < sizeof levels / sizeof levels[0]; j++) {
            static const int wrappers[] = {15, -15, 31};
            for (unsigned w = 0; w < sizeof wrappers / sizeof wrappers[0]; w++) {
                z_stream d = {0}, s = {0};
                int bits = wrappers[w];
                CHECK(deflateInit2_(&d, levels[j], 8, bits, 8, 0, zlibVersion(), sizeof d) == OK);
                CHECK(inflateInit2_(&s, bits, zlibVersion(), sizeof s) == OK);
                size_t packed_len = encode(&d, input, n, packed, cap);
                CHECK(packed_len <= deflateBound(&d, n));
                if (bits == 15) CHECK(packed_len <= compressBound(n));
                if (kind == 2 && levels[j]) CHECK(packed_len < n / 20);
                CHECK(decode(&s, packed, packed_len, output, n, 11, 1) == packed_len);
                CHECK(s.total_out == n && memcmp(input, output, n) == 0);
                CHECK(inflateEnd(&s) == OK && deflateEnd(&d) == OK);
            }
        }
    }
    unsigned long zipped = cap;
    CHECK(compress2(packed, &zipped, input, 17001, 9) == OK);
    CHECK(zipped <= compressBound(17001));
    unsigned long plain = DATA, consumed = zipped + 1;
    packed[zipped] = 0xa5;
    CHECK(uncompress2(output, &plain, packed, &consumed) == OK);
    CHECK(consumed == zipped && plain == 17001 && memcmp(input, output, plain) == 0);
    plain = 1;
    CHECK(uncompress(output, &plain, packed, zipped) == BUF_ERROR);
    zipped = cap;
    CHECK(compress(packed, &zipped, NULL, 0) == OK);
    plain = 0;
    CHECK(uncompress(NULL, &plain, packed, zipped) == OK);
    free(packed); free(output); free(input);
}

static void flush_tests(void) {
    const uint8_t *in = short_text;
    size_t n = sizeof short_text - 1;
    uint8_t packed[256], decoded[2 * sizeof short_text];
    z_stream d = {0}, s = {0};
    CHECK(deflateInit_(&d, 6, zlibVersion(), sizeof d) == OK);
    CHECK(inflateInit_(&s, zlibVersion(), sizeof s) == OK);
    for (unsigned pass = 0; pass < 2; pass++) {
        int flush = pass ? FULL_FLUSH : SYNC_FLUSH;
        d.next_in = in;
        d.avail_in = n;
        int rc;
        do { rc = output_byte(&d, flush, packed, sizeof packed); } while (rc == OK && !d.avail_out);
        CHECK((rc == OK || rc == BUF_ERROR) && d.avail_in == 0);
        size_t split = d.total_out;
        CHECK(split > 4 && memcmp(packed + split - 4, "\0\0\xff\xff", 4) == 0);
        s.next_in = packed;
        s.avail_in = split;
        s.next_out = decoded;
        s.avail_out = sizeof decoded;
        CHECK(inflate(&s, SYNC_FLUSH) == OK && s.total_out == n && s.avail_in == 0);
        CHECK(inflate(&s, NO_FLUSH) == BUF_ERROR);
        size_t total = encode(&d, in, n, packed, sizeof packed);
        s.next_in = packed + split;
        s.avail_in = total - split;
        CHECK(inflate(&s, FINISH) == END && s.total_out == 2 * n);
        CHECK(memcmp(decoded, in, n) == 0 && memcmp(decoded + n, in, n) == 0);
        if (pass) {
            z_stream restarted = {0};
            CHECK(inflateInit2_(&restarted, -15, zlibVersion(), sizeof restarted) == OK);
            CHECK(decode(&restarted, packed + split, total - split, decoded, n, 1, 1) == total - split - 4);
            CHECK(restarted.total_out == n && memcmp(decoded, in, n) == 0);
            CHECK(inflateEnd(&restarted) == OK);
        }
        CHECK(deflateReset(&d) == OK && inflateReset(&s) == OK);
    }
    CHECK(inflateEnd(&s) == OK && deflateEnd(&d) == OK);
}

static void errors_and_checksums(void) {
    const uint8_t *digits = (const uint8_t *)"123456789";
    CHECK(strcmp(zlibVersion(), "1.2.12") == 0);
    CHECK(strcmp(zError(DATA_ERROR), "data error") == 0);
    CHECK(crc32(0, digits, 9) == 0xcbf43926);
    CHECK(crc32_z(crc32(0, digits, 4), digits + 4, 5) == 0xcbf43926);
    CHECK(crc32_combine(crc32(0, digits, 4), crc32(0, digits + 4, 5), 5) == 0xcbf43926);
    CHECK(adler32(1, digits, 9) == 0x091e01de);
    CHECK(adler32_z(adler32(1, digits, 4), digits + 4, 5) == 0x091e01de);
    CHECK(get_crc_table()[1] == 0x77073096);
    z_stream s = {0};
    CHECK(inflateInit_(&s, "0.0", sizeof s) == -6);
    CHECK(inflateInit_(&s, zlibVersion(), sizeof s) == OK);
    uint8_t buf[sizeof stored], out[100];
    memcpy(buf, stored, sizeof stored);
    buf[sizeof buf - 1] ^= 1;
    s.next_in = buf; s.avail_in = sizeof buf;
    s.next_out = out; s.avail_out = sizeof out;
    CHECK(inflate(&s, FINISH) == DATA_ERROR && s.msg && s.total_out == sizeof short_text - 1);
    CHECK(inflate(&s, NO_FLUSH) == DATA_ERROR);
    CHECK(inflateReset(&s) == OK);
    buf[2] = 7;
    s.next_in = buf; s.avail_in = sizeof buf;
    s.next_out = out; s.avail_out = sizeof out;
    CHECK(inflate(&s, NO_FLUSH) == DATA_ERROR && s.msg);
    CHECK(inflateReset(&s) == OK);
    s.next_in = stored; s.avail_in = sizeof stored - 2;
    s.next_out = out; s.avail_out = sizeof out;
    CHECK(inflate(&s, FINISH) == BUF_ERROR && s.total_out == sizeof short_text - 1);
    s.next_in = stored + sizeof stored - 2; s.avail_in = 2;
    CHECK(inflate(&s, FINISH) == END);
    CHECK(inflateEnd(&s) == OK);
    CHECK(inflateInit2_(&s, 31, zlibVersion(), sizeof s) == OK);
    uint8_t bad_gzip[sizeof gzip_options];
    memcpy(bad_gzip, gzip_options, sizeof bad_gzip);
    bad_gzip[13] ^= 1;
    s.next_in = bad_gzip; s.avail_in = sizeof bad_gzip;
    s.next_out = out; s.avail_out = sizeof out;
    CHECK(inflate(&s, NO_FLUSH) == DATA_ERROR && s.msg && s.total_out == 0);
    CHECK(inflateEnd(&s) == OK);
}

static void gzip_file_tests(void) {
    enum { RDONLY = 0, WRONLY = 1, APPEND = 8, TRUNC = 0x400 };
    char path[80], out[128];
    snprintf(path, sizeof path, "/tmp/bitten-gzip-%d.gz", getpid());
    gz_file f = gzopen(path, "wb9");
    CHECK(f && gzputs(f, "first\n") == 6 && gzwrite(f, "second\n", 7) == 7);
    CHECK(gzclose(f) == OK);
    f = gzopen(path, "ab1");
    CHECK(f && gzputs(f, "third\n") == 6 && gzclose(f) == OK);
    int fd = open(path, WRONLY | APPEND);
    CHECK(fd >= 0 && write(fd, "trailing", 8) == 8 && close(fd) == 0);

    fd = open(path, RDONLY);
    CHECK(fd >= 0);
    f = gzdopen(fd, "rb");
    CHECK(f && gzgets(f, out, sizeof out) == out && strcmp(out, "first\n") == 0);
    CHECK(gzread(f, out, 13) == 13 && memcmp(out, "second\nthird\n", 13) == 0);
    CHECK(!gzeof(f));
    CHECK(gzread(f, out, 1) == 0 && gzeof(f));
    int status;
    CHECK(strcmp(gzerror(f, &status), "") == 0 && status == OK);
    CHECK(gzclose(f) == OK && read(fd, out, 1) == -1 && errno == 9);

    f = gzopen(path, "wbT");
    CHECK(f && gzwrite(f, short_text, sizeof short_text - 1) == (int)sizeof short_text - 1);
    CHECK(gzclose(f) == OK);
    f = gzopen(path, "rb");
    CHECK(f && gzread(f, out, sizeof out) == (int)sizeof short_text - 1 && gzeof(f));
    CHECK(memcmp(out, short_text, sizeof short_text - 1) == 0 && gzclose(f) == OK);

    fd = open(path, WRONLY | TRUNC);
    CHECK(fd >= 0 && write(fd, dynamic, sizeof dynamic - 2) == (ssize_t)sizeof dynamic - 2);
    CHECK(close(fd) == 0);
    f = gzopen(path, "rb");
    CHECK(f);
    int total = 0, n;
    while ((n = gzread(f, out, sizeof out)) > 0) total += n;
    CHECK(n == 0 && total == 150 * (int)(sizeof long_text - 1));
    CHECK(gzerror(f, &status) && status == BUF_ERROR && gzclose(f) == BUF_ERROR);
    CHECK(unlink(path) == 0);
}

static void compression_tests(void) {
    enum { LZ4 = 0x100, LZ4_RAW = 0x101, ZLIB = 0x205, LZFSE = 0x801, LZMA = 0x306 };
    uint8_t packed[256], out[200];
    size_t n = sizeof short_text - 1;
    const int algs[] = {ZLIB, LZ4, LZ4_RAW};
    for (unsigned i = 0; i < sizeof algs / sizeof algs[0]; i++) {
        int alg = algs[i];
        CHECK(compression_encode_scratch_buffer_size(alg) == 0);
        CHECK(compression_decode_scratch_buffer_size(alg) == 0);
        size_t size = compression_encode_buffer(packed, sizeof packed, short_text, n, NULL, alg);
        CHECK(size && size < n);
        CHECK(compression_decode_buffer(out, n, packed, size, NULL, alg) == n);
        CHECK(memcmp(out, short_text, n) == 0);
        CHECK(compression_decode_buffer(out, n - 1, packed, size, NULL, alg) == n - 1);
        CHECK(memcmp(out, short_text, n - 1) == 0);
        CHECK(compression_encode_buffer(packed, size - 1, short_text, n, NULL, alg) == 0);
    }
    CHECK(compression_decode_buffer(out, n, fixed, sizeof fixed, NULL, ZLIB) == n);
    CHECK(memcmp(out, short_text, n) == 0);
    CHECK(compression_encode_buffer(packed, sizeof packed, short_text, n, NULL, LZFSE) == 0);
    CHECK(compression_decode_buffer(out, sizeof out, short_text, n, NULL, LZMA) == 0);
    /* The second block starts with a back-reference whose dictionary is the first block. */
    static const uint8_t lz4_frame[] =
        "bv4-" "\x0c\0\0\0" "abcdefghijkl"
        "bv41" "\x11\0\0\0" "\x09\0\0\0" "\x08\x0c\0\x50" "mnopq" "bv4$";
    CHECK(compression_decode_buffer(out, sizeof out, lz4_frame, sizeof lz4_frame - 1, NULL, LZ4) == 29);
    CHECK(memcmp(out, "abcdefghijklabcdefghijklmnopq", 29) == 0);
    CHECK(compression_decode_buffer(out, sizeof out, lz4_frame, sizeof lz4_frame - 2, NULL, LZ4) == 0);
    compression_stream s;
    CHECK(compression_stream_init(&s, 0, ZLIB) == 0);
    s.src_ptr = short_text; s.src_size = n;
    size_t size = 0;
    int rc;
    do {
        CHECK(size < sizeof packed);
        s.dst_ptr = packed + size; s.dst_size = 1;
        rc = compression_stream_process(&s, 1);
        CHECK(rc == 0 || rc == 1);
        size += 1 - s.dst_size;
    } while (!rc);
    CHECK(s.src_size == 0 && compression_stream_destroy(&s) == 0);
    CHECK(compression_stream_init(&s, 1, ZLIB) == 0);
    size_t given = 0, have = 0;
    do {
        if (!s.src_size && given < size) { s.src_ptr = packed + given++; s.src_size = 1; }
        CHECK(have < sizeof out);
        s.dst_ptr = out + have; s.dst_size = 1;
        rc = compression_stream_process(&s, given == size);
        CHECK(rc == 0 || rc == 1);
        have += 1 - s.dst_size;
    } while (!rc);
    CHECK(have == n && memcmp(out, short_text, n) == 0 && compression_stream_destroy(&s) == 0);
}

int main(void) {
    reference_tests();
    roundtrips();
    flush_tests();
    errors_and_checksums();
    gzip_file_tests();
    compression_tests();
    puts("zlib and compression ok");
    return 0;
}
