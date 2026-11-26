/* PNG decoding: every colour type and bit depth of the specification,
 * palettes and tRNS transparency, all five filters, Adam7 interlacing.
 * The result is premultiplied RGBA, 8 bits a sample (16-bit samples keep
 * their high byte), rows top to bottom. Gamma and colour profile chunks
 * are ignored: samples are taken as sRGB. */
#include <stdlib.h>
#include <string.h>

#include "cg.h"
#include "../zlib/zlib_internal.h"

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }

struct png {
    uint32_t w, h;
    int depth, type, interlace, channels;
    uint8_t palette[256][4];
    int npalette;
    bool has_key;
    uint16_t key[3];                       /* tRNS for grey and RGB: the transparent sample */
};

static int channels_of(int type) {
    switch (type) {
    case 0: return 1;
    case 2: return 3;
    case 3: return 1;
    case 4: return 2;
    case 6: return 4;
    default: return 0;
    }
}

static bool valid_depth(int type, int depth) {
    switch (type) {
    case 0: return depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16;
    case 3: return depth == 1 || depth == 2 || depth == 4 || depth == 8;
    case 2: case 4: case 6: return depth == 8 || depth == 16;
    default: return false;
    }
}

static uint8_t *inflate_all(const uint8_t *in, size_t n, size_t expect) {
    uint8_t *out = malloc(expect ? expect : 1);
    if (!out) return NULL;
    dz_stream s;
    memset(&s, 0, sizeof s);
    if (dz_inflate_init(&s, 15, DZ_VERSION, sizeof s) != Z_OK) { free(out); return NULL; }
    s.next_in = in;
    s.avail_in = (unsigned)n;
    s.next_out = out;
    s.avail_out = (unsigned)expect;
    int status = dz_inflate(&s, Z_FINISH);
    size_t got = s.total_out;
    dz_inflate_end(&s);
    if ((status != Z_STREAM_END && status != Z_OK && status != Z_BUF_ERROR) || got < expect) { free(out); return NULL; }
    return out;
}

static uint8_t paeth(int a, int b, int c) {
    int p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
    return (uint8_t)(pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
}

/* Undo the filters of one (sub)image in place: rows of 1 + row bytes. */
static bool unfilter(uint8_t *data, size_t rows, size_t row_bytes, size_t bpp) {
    uint8_t *prev = NULL;
    for (size_t y = 0; y < rows; y++) {
        uint8_t *line = data + y * (row_bytes + 1), f = line[0], *cur = line + 1;
        for (size_t i = 0; i < row_bytes; i++) {
            int a = i >= bpp ? cur[i - bpp] : 0, b = prev ? prev[i] : 0, c = prev && i >= bpp ? prev[i - bpp] : 0;
            switch (f) {
            case 0: break;
            case 1: cur[i] = (uint8_t)(cur[i] + a); break;
            case 2: cur[i] = (uint8_t)(cur[i] + b); break;
            case 3: cur[i] = (uint8_t)(cur[i] + ((a + b) >> 1)); break;
            case 4: cur[i] = (uint8_t)(cur[i] + paeth(a, b, c)); break;
            default: return false;
            }
        }
        prev = cur;
    }
    return true;
}

/* Sample i of a row (0..channels*w), widened to 16 bits. */
static uint16_t sample(const struct png *p, const uint8_t *row, size_t i) {
    switch (p->depth) {
    case 16: return (uint16_t)(row[i * 2] << 8 | row[i * 2 + 1]);
    case 8: return row[i];
    default: {
        size_t bit = i * (size_t)p->depth;
        unsigned v = (row[bit / 8] >> (8 - p->depth - bit % 8)) & ((1u << p->depth) - 1);
        return (uint16_t)v;
    }
    }
}

static uint8_t to8(const struct png *p, uint16_t v) {
    switch (p->depth) {
    case 16: return (uint8_t)(v >> 8);
    case 8: return (uint8_t)v;
    default: return (uint8_t)(v * 255 / ((1u << p->depth) - 1));
    }
}

/* One pixel of a row to premultiplied RGBA. */
static void pixel(const struct png *p, const uint8_t *row, size_t x, uint8_t out[4]) {
    size_t c = (size_t)p->channels;
    uint8_t r, g, b, a = 255;
    if (p->type == 3) {
        uint16_t idx = sample(p, row, x);
        const uint8_t *e = idx < p->npalette ? p->palette[idx] : (const uint8_t[4]){0, 0, 0, 255};
        r = e[0]; g = e[1]; b = e[2]; a = e[3];
    } else if (p->type == 0 || p->type == 4) {
        uint16_t v = sample(p, row, x * c);
        r = g = b = to8(p, v);
        if (p->type == 4) a = to8(p, sample(p, row, x * c + 1));
        else if (p->has_key && v == p->key[0]) a = 0;
    } else {
        uint16_t sr = sample(p, row, x * c), sg = sample(p, row, x * c + 1), sb = sample(p, row, x * c + 2);
        r = to8(p, sr); g = to8(p, sg); b = to8(p, sb);
        if (p->type == 6) a = to8(p, sample(p, row, x * c + 3));
        else if (p->has_key && sr == p->key[0] && sg == p->key[1] && sb == p->key[2]) a = 0;
    }
    out[0] = (uint8_t)((r * a + 127) / 255);
    out[1] = (uint8_t)((g * a + 127) / 255);
    out[2] = (uint8_t)((b * a + 127) / 255);
    out[3] = a;
}

static size_t row_bytes_of(const struct png *p, size_t w) { return (w * (size_t)p->channels * (size_t)p->depth + 7) / 8; }

uint8_t *cg_png_decode(const uint8_t *d, size_t n, size_t *out_w, size_t *out_h) {
    static const uint8_t sig[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    if (!d || n < 8 + 25 || memcmp(d, sig, 8)) return NULL;
    struct png p;
    memset(&p, 0, sizeof p);
    uint8_t *idat = NULL;
    size_t idat_n = 0, idat_cap = 0;
    bool header = false;
    for (size_t off = 8; off + 12 <= n;) {
        uint32_t len = be32(d + off);
        const uint8_t *type = d + off + 4, *body = d + off + 8;
        if (len > n - off - 12) break;
        if (!memcmp(type, "IHDR", 4) && len >= 13) {
            p.w = be32(body);
            p.h = be32(body + 4);
            p.depth = body[8];
            p.type = body[9];
            p.interlace = body[12];
            p.channels = channels_of(p.type);
            header = p.w && p.h && p.w < (1u << 15) && p.h < (1u << 15) && p.channels && valid_depth(p.type, p.depth) &&
                     body[10] == 0 && body[11] == 0 && p.interlace <= 1;
            if (!header) break;
        } else if (!memcmp(type, "PLTE", 4)) {
            p.npalette = (int)(len / 3 > 256 ? 256 : len / 3);
            for (int i = 0; i < p.npalette; i++) {
                p.palette[i][0] = body[i * 3];
                p.palette[i][1] = body[i * 3 + 1];
                p.palette[i][2] = body[i * 3 + 2];
                p.palette[i][3] = 255;
            }
        } else if (!memcmp(type, "tRNS", 4)) {
            if (p.type == 3) for (uint32_t i = 0; i < len && i < 256; i++) p.palette[i][3] = body[i];
            else if (p.type == 0 && len >= 2) { p.has_key = true; p.key[0] = (uint16_t)(body[0] << 8 | body[1]); }
            else if (p.type == 2 && len >= 6) {
                p.has_key = true;
                for (int i = 0; i < 3; i++) p.key[i] = (uint16_t)(body[i * 2] << 8 | body[i * 2 + 1]);
            }
        } else if (!memcmp(type, "IDAT", 4)) {
            if (idat_n + len > idat_cap) {
                size_t cap = (idat_n + len) * 2;
                uint8_t *q = realloc(idat, cap);
                if (!q) { free(idat); return NULL; }
                idat = q;
                idat_cap = cap;
            }
            memcpy(idat + idat_n, body, len);
            idat_n += len;
        } else if (!memcmp(type, "IEND", 4)) {
            break;
        }
        off += 12 + (size_t)len;
    }
    if (!header || !idat) { free(idat); return NULL; }

    static const int ax[7] = {0, 4, 0, 2, 0, 1, 0}, ay[7] = {0, 0, 4, 0, 2, 0, 1};
    static const int dx[7] = {8, 8, 4, 4, 2, 2, 1}, dy[7] = {8, 8, 8, 4, 4, 2, 2};
    int passes = p.interlace ? 7 : 1;
    size_t total = 0;
    for (int i = 0; i < passes; i++) {
        size_t pw = p.interlace ? (p.w + (size_t)(dx[i] - ax[i] - 1)) / (size_t)dx[i] : p.w;
        size_t ph = p.interlace ? (p.h + (size_t)(dy[i] - ay[i] - 1)) / (size_t)dy[i] : p.h;
        if (pw && ph) total += ph * (row_bytes_of(&p, pw) + 1);
    }
    uint8_t *raw = inflate_all(idat, idat_n, total);
    free(idat);
    if (!raw) return NULL;
    uint8_t *rgba = calloc((size_t)p.w * p.h, 4);
    if (!rgba) { free(raw); return NULL; }
    size_t bpp = ((size_t)p.channels * (size_t)p.depth + 7) / 8;
    uint8_t *at = raw;
    for (int i = 0; i < passes; i++) {
        size_t pw = p.interlace ? (p.w + (size_t)(dx[i] - ax[i] - 1)) / (size_t)dx[i] : p.w;
        size_t ph = p.interlace ? (p.h + (size_t)(dy[i] - ay[i] - 1)) / (size_t)dy[i] : p.h;
        if (!pw || !ph) continue;
        size_t rb = row_bytes_of(&p, pw);
        if (!unfilter(at, ph, rb, bpp)) { free(raw); free(rgba); return NULL; }
        for (size_t y = 0; y < ph; y++) {
            const uint8_t *row = at + y * (rb + 1) + 1;
            size_t oy = p.interlace ? y * (size_t)dy[i] + (size_t)ay[i] : y;
            for (size_t x = 0; x < pw; x++) {
                size_t ox = p.interlace ? x * (size_t)dx[i] + (size_t)ax[i] : x;
                pixel(&p, row, x, rgba + (oy * p.w + ox) * 4);
            }
        }
        at += ph * (rb + 1);
    }
    free(raw);
    *out_w = p.w;
    *out_h = p.h;
    return rgba;
}
