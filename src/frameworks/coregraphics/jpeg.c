/* JPEG decoding: baseline and extended sequential Huffman DCT (SOF0/SOF1),
 * 8-bit samples, grey or YCbCr with any chroma subsampling, restart
 * intervals, Adobe APP14 RGB. Progressive (SOF2), arithmetic and lossless
 * files are not decoded. The result is opaque RGBA, rows top to bottom. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "cg.h"

struct huff {
    uint8_t bits[17];          /* codes per length */
    uint8_t vals[256];
    int mincode[17], maxcode[18], valptr[17];
};

struct comp {
    int id, h, v, tq, td, ta;
    int bw, bh;                /* blocks across and down (padded to the MCU) */
    uint8_t *pixels;           /* bw*8 x bh*8 samples */
    int dc;
};

struct jpeg {
    const uint8_t *d;
    size_t n, pos;
    uint16_t q[4][64];
    struct huff dc[4], ac[4];
    struct comp c[4];
    int nc, w, h, hmax, vmax, restart;
    bool adobe_rgb, ok;
    /* bit reader */
    uint32_t bitbuf;
    int bitcnt;
    bool marker;
};

static const uint8_t zigzag[64] = {
    0,  1,  8,  16, 9,  2,  3,  10, 17, 24, 32, 25, 18, 11, 4,  5,  12, 19, 26, 33, 40, 48,
    41, 34, 27, 20, 13, 6,  7,  14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23,
    30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63};

static int u16(struct jpeg *j) {
    if (j->pos + 2 > j->n) { j->ok = false; return 0; }
    int v = j->d[j->pos] << 8 | j->d[j->pos + 1];
    j->pos += 2;
    return v;
}

static void build_huff(struct huff *h) {
    int code = 0, k = 0;
    for (int l = 1; l <= 16; l++) {
        h->valptr[l] = k;
        h->mincode[l] = code;
        code += h->bits[l];
        k += h->bits[l];
        h->maxcode[l] = h->bits[l] ? code - 1 : -1;
        code <<= 1;
    }
    h->maxcode[17] = 0x7fffffff;
}

/* ---- the entropy-coded segment ---- */

static int bit(struct jpeg *j) {
    if (!j->bitcnt) {
        uint8_t b = 0;
        if (!j->marker && j->pos < j->n) {
            b = j->d[j->pos++];
            if (b == 0xff) {
                uint8_t next = j->pos < j->n ? j->d[j->pos] : 0;
                if (next == 0) j->pos++;
                else { j->marker = true; j->pos--; b = 0; }
            }
        }
        j->bitbuf = b;
        j->bitcnt = 8;
    }
    j->bitcnt--;
    return (j->bitbuf >> j->bitcnt) & 1;
}

static int bits(struct jpeg *j, int n) {
    int v = 0;
    while (n--) v = v << 1 | bit(j);
    return v;
}

static int decode(struct jpeg *j, const struct huff *h) {
    int code = 0;
    for (int l = 1; l <= 16; l++) {
        code = code << 1 | bit(j);
        if (h->maxcode[l] >= 0 && code <= h->maxcode[l]) return h->vals[h->valptr[l] + code - h->mincode[l]];
    }
    j->ok = false;
    return 0;
}

static int extend(int v, int t) { return t && v < (1 << (t - 1)) ? v - (1 << t) + 1 : v; }

/* The inverse DCT of one block into 8x8 samples (separable, in doubles). */
static void idct(const int *in, uint8_t *out, int stride) {
    static double c[8][8];
    static bool init;
    if (!init) {
        for (int x = 0; x < 8; x++)
            for (int u = 0; u < 8; u++) c[x][u] = (u ? 1.0 : M_SQRT1_2) * cos((2 * x + 1) * u * M_PI / 16);
        init = true;
    }
    double tmp[64];
    for (int y = 0; y < 8; y++)
        for (int u = 0; u < 8; u++) {
            double s = 0;
            for (int v = 0; v < 8; v++) s += c[y][v] * in[v * 8 + u];
            tmp[y * 8 + u] = s / 2;
        }
    for (int y = 0; y < 8; y++)
        for (int x = 0; x < 8; x++) {
            double s = 0;
            for (int u = 0; u < 8; u++) s += c[x][u] * tmp[y * 8 + u];
            int v = (int)lround(s / 2 + 128);
            out[y * stride + x] = (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
        }
}

static void block(struct jpeg *j, struct comp *c, int bx, int by) {
    int coef[64] = {0};
    int t = decode(j, &j->dc[c->td]);
    int diff = t ? extend(bits(j, t), t) : 0;
    c->dc += diff;
    coef[0] = c->dc * j->q[c->tq][0];
    for (int k = 1; k < 64 && j->ok;) {
        int rs = decode(j, &j->ac[c->ta]), r = rs >> 4, s = rs & 15;
        if (!s) {
            if (r != 15) break;                       /* end of block */
            k += 16;
            continue;
        }
        k += r;
        if (k > 63) break;
        coef[zigzag[k]] = extend(bits(j, s), s) * j->q[c->tq][k];
        k++;
    }
    idct(coef, c->pixels + (size_t)by * 8 * (size_t)(c->bw * 8) + (size_t)bx * 8, c->bw * 8);
}

static void reset(struct jpeg *j) {
    j->bitcnt = 0;
    j->marker = false;
    for (int i = 0; i < j->nc; i++) j->c[i].dc = 0;
    /* skip to just past the RSTn marker */
    while (j->pos + 1 < j->n && !(j->d[j->pos] == 0xff && j->d[j->pos + 1] >= 0xd0 && j->d[j->pos + 1] <= 0xd7)) j->pos++;
    if (j->pos + 1 < j->n) j->pos += 2;
}

static bool scan(struct jpeg *j) {
    int len = u16(j);
    int ns = j->pos < j->n ? j->d[j->pos++] : 0;
    struct comp *order[4];
    for (int i = 0; i < ns && i < 4; i++) {
        int id = j->d[j->pos++], tables = j->d[j->pos++];
        order[i] = NULL;
        for (int k = 0; k < j->nc; k++)
            if (j->c[k].id == id) order[i] = &j->c[k];
        if (!order[i]) return false;
        order[i]->td = tables >> 4;
        order[i]->ta = tables & 15;
    }
    j->pos += 3;                                       /* Ss, Se, Ah/Al */
    (void)len;
    int mcux = (j->w + 8 * j->hmax - 1) / (8 * j->hmax), mcuy = (j->h + 8 * j->vmax - 1) / (8 * j->vmax);
    j->bitcnt = 0;
    j->marker = false;
    int count = 0;
    if (ns == 1) {
        /* A single component scan covers just its own blocks. */
        struct comp *c = order[0];
        int bw = (j->w * c->h / j->hmax + 7) / 8, bh = (j->h * c->v / j->vmax + 7) / 8;
        for (int by = 0; by < bh && j->ok; by++)
            for (int bx = 0; bx < bw && j->ok; bx++) {
                if (j->restart && count && count % j->restart == 0) reset(j);
                block(j, c, bx, by);
                count++;
            }
    } else {
        for (int my = 0; my < mcuy && j->ok; my++)
            for (int mx = 0; mx < mcux && j->ok; mx++) {
                if (j->restart && count && count % j->restart == 0) reset(j);
                for (int i = 0; i < ns; i++) {
                    struct comp *c = order[i];
                    for (int v = 0; v < c->v; v++)
                        for (int h = 0; h < c->h; h++) block(j, c, mx * c->h + h, my * c->v + v);
                }
                count++;
            }
    }
    /* Move to the next marker. */
    while (j->pos + 1 < j->n && !(j->d[j->pos] == 0xff && j->d[j->pos + 1] != 0 &&
                                   !(j->d[j->pos + 1] >= 0xd0 && j->d[j->pos + 1] <= 0xd7)))
        j->pos++;
    return j->ok;
}

static uint8_t clamp8(double v) { return (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : lround(v)); }

uint8_t *cg_jpeg_decode(const uint8_t *data, size_t n, size_t *out_w, size_t *out_h) {
    if (!data || n < 4 || data[0] != 0xff || data[1] != 0xd8) return NULL;
    struct jpeg *j = calloc(1, sizeof *j);
    if (!j) return NULL;
    j->d = data;
    j->n = n;
    j->pos = 2;
    j->ok = true;
    bool frame = false, scanned = false;
    while (j->ok && j->pos + 4 <= n) {
        if (data[j->pos] != 0xff) { j->pos++; continue; }
        int m = data[j->pos + 1];
        j->pos += 2;
        if (m == 0xd8 || m == 0x01 || (m >= 0xd0 && m <= 0xd7) || m == 0xff) { if (m == 0xff) j->pos--; continue; }
        if (m == 0xd9) break;                          /* EOI */
        size_t start = j->pos;
        int len = u16(j);
        if (len < 2 || start + (size_t)len > n) break;
        if (m == 0xc0 || m == 0xc1) {                  /* SOF0, SOF1 */
            if (data[j->pos] != 8) { j->ok = false; break; }
            j->h = data[j->pos + 1] << 8 | data[j->pos + 2];
            j->w = data[j->pos + 3] << 8 | data[j->pos + 4];
            j->nc = data[j->pos + 5];
            if (j->nc != 1 && j->nc != 3) { j->ok = false; break; }
            for (int i = 0; i < j->nc; i++) {
                const uint8_t *p = data + j->pos + 6 + i * 3;
                j->c[i].id = p[0];
                j->c[i].h = p[1] >> 4 ? p[1] >> 4 : 1;
                j->c[i].v = p[1] & 15 ? p[1] & 15 : 1;
                j->c[i].tq = p[2] & 3;
                if (j->c[i].h > j->hmax) j->hmax = j->c[i].h;
                if (j->c[i].v > j->vmax) j->vmax = j->c[i].v;
            }
            if (!j->w || !j->h || j->w > 16384 || j->h > 16384) { j->ok = false; break; }
            int mcux = (j->w + 8 * j->hmax - 1) / (8 * j->hmax), mcuy = (j->h + 8 * j->vmax - 1) / (8 * j->vmax);
            for (int i = 0; i < j->nc; i++) {
                struct comp *c = &j->c[i];
                c->bw = mcux * c->h;
                c->bh = mcuy * c->v;
                c->pixels = calloc((size_t)c->bw * 8 * (size_t)c->bh * 8, 1);
                if (!c->pixels) { j->ok = false; break; }
            }
            frame = true;
        } else if (m >= 0xc2 && m <= 0xcf && m != 0xc4 && m != 0xc8 && m != 0xcc) {
            j->ok = false;                             /* progressive, lossless, arithmetic */
            break;
        } else if (m == 0xc4) {                        /* DHT */
            size_t end = start + (size_t)len;
            while (j->pos < end) {
                int tc = data[j->pos] >> 4, th = data[j->pos] & 3;
                j->pos++;
                struct huff *h = tc ? &j->ac[th] : &j->dc[th];
                int total = 0;
                h->bits[0] = 0;
                for (int l = 1; l <= 16; l++) { h->bits[l] = data[j->pos++]; total += h->bits[l]; }
                if (total > 256 || j->pos + (size_t)total > end) { j->ok = false; break; }
                memcpy(h->vals, data + j->pos, (size_t)total);
                j->pos += (size_t)total;
                build_huff(h);
            }
        } else if (m == 0xdb) {                        /* DQT */
            size_t end = start + (size_t)len;
            while (j->pos < end) {
                int pq = data[j->pos] >> 4, tq = data[j->pos] & 3;
                j->pos++;
                for (int k = 0; k < 64; k++) {
                    j->q[tq][k] = pq ? (uint16_t)(data[j->pos] << 8 | data[j->pos + 1]) : data[j->pos];
                    j->pos += pq ? 2 : 1;
                }
            }
        } else if (m == 0xdd) {                        /* DRI */
            j->restart = data[j->pos] << 8 | data[j->pos + 1];
        } else if (m == 0xee && len >= 12 && !memcmp(data + j->pos, "Adobe", 5)) {
            j->adobe_rgb = data[j->pos + 11] == 0;     /* transform 0: RGB */
        } else if (m == 0xda) {                        /* SOS */
            if (!frame) { j->ok = false; break; }
            j->pos = start;
            scanned = scan(j) || scanned;
            continue;
        }
        j->pos = start + (size_t)len;
    }
    uint8_t *rgba = NULL;
    if (j->ok && frame && scanned) {
        rgba = malloc((size_t)j->w * (size_t)j->h * 4);
        if (rgba) {
            for (int y = 0; y < j->h; y++)
                for (int x = 0; x < j->w; x++) {
                    double s[3];
                    for (int i = 0; i < j->nc; i++) {
                        struct comp *c = &j->c[i];
                        int sx = x * c->h / j->hmax, sy = y * c->v / j->vmax;
                        s[i] = c->pixels[(size_t)sy * (size_t)(c->bw * 8) + (size_t)sx];
                    }
                    uint8_t *p = rgba + ((size_t)y * (size_t)j->w + (size_t)x) * 4;
                    if (j->nc == 1) {
                        p[0] = p[1] = p[2] = (uint8_t)s[0];
                    } else if (j->adobe_rgb) {
                        p[0] = (uint8_t)s[0]; p[1] = (uint8_t)s[1]; p[2] = (uint8_t)s[2];
                    } else {
                        double Y = s[0], cb = s[1] - 128, cr = s[2] - 128;
                        p[0] = clamp8(Y + 1.402 * cr);
                        p[1] = clamp8(Y - 0.344136 * cb - 0.714136 * cr);
                        p[2] = clamp8(Y + 1.772 * cb);
                    }
                    p[3] = 255;
                }
            *out_w = (size_t)j->w;
            *out_h = (size_t)j->h;
        }
    }
    for (int i = 0; i < 4; i++) free(j->c[i].pixels);
    free(j);
    return rgba;
}
