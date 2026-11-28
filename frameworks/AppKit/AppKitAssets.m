/* Compiled asset catalogs (Assets.car): the images NSImage(named:) and
 * SwiftUI's Image("name") find in a bundle.
 *
 * The file is a BOM store (big-endian block table and named variables).
 * FACETKEYS maps asset names to attributes (element, part, identifier);
 * KEYFORMAT lists the attributes making up each rendition key; RENDITIONS
 * maps keys to CSI headers ("CTSI", little-endian) followed by TLV records
 * and the rendition's data. A rendition is either a bitmap ("MLEC" with a
 * compression type) or a link (layout 1003) to a rectangle of a packed
 * atlas rendition, named by a key in its KLNI record.
 *
 * Bitmaps are LZFSE-compressed raw pixels or Apple's "deepmap2": an LZFSE
 * band of an alpha plane, one predictor per row and 16-bit sign-magnitude
 * residuals (high bytes, then low bytes) in YCoCg, decoded as described
 * by the public carfile-go reader. Vector renditions (PDF, SVG) are not
 * drawn. */
#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <string.h>

size_t compression_decode_buffer(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, void *scratch,
                                 int algorithm);
enum { COMPRESSION_LZFSE = 0x801, COMPRESSION_LZVN = 0x900 };

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }

/* ---- the BOM store ---- */

@interface BNAssetCatalog : NSObject {
  @public
    NSData *_data;
    const uint8_t *_b;
    size_t _len;
    uint32_t _nblocks;
    const uint8_t *_index;
    uint32_t _keyformat[32];
    int _nkeys;
    NSMutableDictionary<NSString *, NSData *> *_facets;   /* name -> attribute pairs */
    NSMutableArray<NSData *> *_renditionKeys, *_renditionValues;
    NSMutableDictionary *_decoded;                          /* rendition index -> CGImage */
}
@end

@implementation BNAssetCatalog
- (BOOL)_block:(uint32_t)i data:(const uint8_t **)p length:(uint32_t *)n {
    if (i >= _nblocks) return NO;
    uint32_t addr = be32(_index + 4 + 8 * i), len = be32(_index + 8 + 8 * i);
    if ((size_t)addr + len > _len) return NO;
    *p = _b + addr;
    *n = len;
    return YES;
}
/* Calls `each(key, value)` for every entry of the named B+ tree. */
- (void)_tree:(uint32_t)block each:(void (^)(const uint8_t *, uint32_t, const uint8_t *, uint32_t))each {
    const uint8_t *t;
    uint32_t tl;
    if (![self _block:block data:&t length:&tl] || tl < 21 || memcmp(t, "tree", 4)) return;
    const uint8_t *p;
    uint32_t pl;
    if (![self _block:be32(t + 8) data:&p length:&pl]) return;
    for (int guard = 0; pl >= 12 && !be16(p) && guard < 64; guard++) /* down the leftmost branch */
        if (![self _block:be32(p + 12) data:&p length:&pl]) return;
    for (int guard = 0; guard < 1 << 20; guard++) {
        uint16_t count = be16(p + 2);
        uint32_t forward = be32(p + 4);
        for (uint16_t i = 0; i < count && 12 + 8u * (i + 1) <= pl; i++) {
            const uint8_t *k, *v;
            uint32_t kl, vl;
            if ([self _block:be32(p + 16 + 8 * i) data:&k length:&kl] &&
                [self _block:be32(p + 12 + 8 * i) data:&v length:&vl])
                each(k, kl, v, vl);
        }
        if (!forward || ![self _block:forward data:&p length:&pl]) break;
    }
}
- (instancetype)initWithPath:(NSString *)path {
    if (!(self = [super init])) return nil;
    /* mapped, as CoreUI maps catalogs: they are megabytes, and the values
     * below point into the mapping (the catalog lives as long as they do) */
    _data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    _b = _data.bytes;
    _len = _data.length;
    if (_len < 32 || memcmp(_b, "BOMStore", 8)) return nil;
    _nblocks = be32(_b + 12);
    uint32_t io = be32(_b + 16), vo = be32(_b + 24);
    if (io + 4 > _len || vo + 4 > _len) return nil;
    _index = _b + io;
    _nblocks = be32(_index);
    if (io + 4 + 8ull * _nblocks > _len) return nil;
    /* named variables */
    uint32_t nvars = be32(_b + vo);
    const uint8_t *v = _b + vo + 4;
    uint32_t facets = 0, renditions = 0, keyformat = 0;
    for (uint32_t i = 0; i < nvars && v + 5 <= _b + _len; i++) {
        uint32_t block = be32(v);
        uint8_t nl = v[4];
        NSString *name = [[NSString alloc] initWithBytes:v + 5 length:nl encoding:NSASCIIStringEncoding];
        if ([name isEqualToString:@"FACETKEYS"]) facets = block;
        else if ([name isEqualToString:@"RENDITIONS"]) renditions = block;
        else if ([name isEqualToString:@"KEYFORMAT"]) keyformat = block;
        v += 5 + nl;
    }
    const uint8_t *kf;
    uint32_t kfl;
    if (![self _block:keyformat data:&kf length:&kfl] || kfl < 12) return nil;
    _nkeys = (int)MIN(le32(kf + 8), 32u);
    for (int i = 0; i < _nkeys && 12 + 4u * (i + 1) <= kfl; i++) _keyformat[i] = le32(kf + 12 + 4 * i);
    _facets = [NSMutableDictionary dictionary];
    [self _tree:facets each:^(const uint8_t *k, uint32_t kl, const uint8_t *val, uint32_t vl) {
        NSString *name = [[NSString alloc] initWithBytes:k length:strnlen((const char *)k, kl) encoding:NSUTF8StringEncoding];
        if (name && vl >= 6) _facets[name] = [NSData dataWithBytesNoCopy:(void *)val length:vl freeWhenDone:NO];
    }];
    _renditionKeys = [NSMutableArray array];
    _renditionValues = [NSMutableArray array];
    [self _tree:renditions each:^(const uint8_t *k, uint32_t kl, const uint8_t *val, uint32_t vl) {
        [_renditionKeys addObject:[NSData dataWithBytesNoCopy:(void *)k length:kl freeWhenDone:NO]];
        [_renditionValues addObject:[NSData dataWithBytesNoCopy:(void *)val length:vl freeWhenDone:NO]];
    }];
    _decoded = [NSMutableDictionary dictionary];
    return self;
}

/* The value of attribute `attr` in a rendition key (0 when absent). */
- (uint16_t)_key:(NSData *)key attribute:(uint32_t)attr {
    const uint8_t *k = key.bytes;
    for (int i = 0; i < _nkeys && 2u * (i + 1) <= key.length; i++)
        if (_keyformat[i] == attr) return le16(k + 2 * i);
    return 0;
}
@end

/* ---- deepmap2 ---- */

static uint8_t *lz_decode(const uint8_t *src, size_t n, size_t cap, size_t *out) {
    uint8_t *dst = malloc(cap ? cap : 1);
    if (!dst) return NULL;
    size_t m = 0;
    if (n >= 4 && !memcmp(src, "bvx", 3)) m = compression_decode_buffer(dst, cap, src, n, NULL, COMPRESSION_LZFSE);
    else m = compression_decode_buffer(dst, cap, src, n, NULL, COMPRESSION_LZVN);
    if (!m) {
        free(dst);
        return NULL;
    }
    *out = m;
    return dst;
}

/* Decodes one dmp2 blob (starting at "dmp2") into straight RGBA rows
 * appended to `rgba` (width w); returns the number of rows, 0 on failure. */
static size_t dmp2_decode(const uint8_t *p, size_t n, NSMutableData *rgba, uint32_t *width) {
    if (n < 16 || memcmp(p, "dmp2", 4)) return 0;
    uint8_t method = p[4], format = p[7];
    uint32_t w = le16(p + 8), h = le16(p + 10), desc = le32(p + 12);
    if (!w) return 0;
    *width = w;
    int alpha = format == 2 || format == 4 || format == 20;
    int chans = format == 1 || format == 2 ? 1 : 3;
    size_t rows_total = 0;
    if (method == 1 || method == 3) {
        /* raw / lossless: pixels as stored, R G B A or G A */
        int bpp = (chans == 3 ? 3 : 1) + alpha;
        NSMutableData *raw = [NSMutableData data];
        if (method == 1) [raw appendBytes:p + 12 length:MIN(n - 12, (size_t)w * h * bpp)];
        else {
            size_t off = 16, seg = desc;
            while (off + seg <= n && seg) {
                size_t m;
                uint8_t *d = lz_decode(p + off, seg, (size_t)w * (h + 16) * bpp + 64, &m);
                if (!d) break;
                [raw appendBytes:d length:m];
                free(d);
                off += seg;
                if (off + 4 > n) break;
                seg = le32(p + off);
                off += 4;
            }
        }
        size_t rows = raw.length / ((size_t)w * bpp);
        const uint8_t *s = raw.bytes;
        for (size_t i = 0; i < rows * w; i++, s += bpp) {
            uint8_t px[4];
            if (chans == 3) { px[0] = s[0]; px[1] = s[1]; px[2] = s[2]; px[3] = alpha ? s[3] : 255; }
            else { px[0] = px[1] = px[2] = s[0]; px[3] = alpha ? s[1] : 255; }
            [rgba appendBytes:px length:4];
        }
        return rows;
    }
    if (method == 4) {
        /* palette: entries, then an LZ stream of extra component planes and indices */
        uint32_t count = desc & 0xffff, comps = desc >> 16;
        int bpp = (chans == 3 ? 3 : 1) + alpha;
        if (!count || count > 256 || 16 + (size_t)count * bpp + 4 > n) return 0;
        const uint8_t *pal = p + 16;
        size_t off = 16 + (size_t)count * bpp;
        uint32_t enc = le32(p + off);
        off += 4;
        if (off + enc > n) return 0;
        size_t m, planes = bpp > (int)comps ? bpp - comps : 0;
        uint8_t *d = lz_decode(p + off, enc, (planes + 1) * (size_t)w * h + 64, &m);
        if (!d) return 0;
        const uint8_t *idx = d + planes * (size_t)w * h;
        for (size_t i = 0; i < (size_t)w * h && idx + i < d + m; i++) {
            uint8_t e[4] = {0, 0, 0, 255};
            memcpy(e, pal + (size_t)idx[i] * bpp, bpp);
            for (size_t c = 0; c < planes; c++) e[comps + c] = d[c * (size_t)w * h + i];
            uint8_t px[4];
            if (chans == 3) { px[0] = e[0]; px[1] = e[1]; px[2] = e[2]; px[3] = alpha ? e[3] : 255; }
            else { px[0] = px[1] = px[2] = e[0]; px[3] = alpha ? e[1] : 255; }
            [rgba appendBytes:px length:4];
        }
        free(d);
        return h;
    }
    if (method != 2) return 0;
    /* default: bands of alpha, predictors and residuals */
    size_t per_row = (alpha ? w : 0) + 1 + 2 * 3u * w;
    if (chans == 1) per_row = (alpha ? w : 0) + 1 + 2u * w;
    int res = chans == 3 ? 3 : 1;
    size_t off = 16, seg = desc;
    int16_t *prev = calloc(3 * (size_t)w, sizeof *prev), *cur = calloc(3 * (size_t)w, sizeof *cur);
    while (seg && off + seg <= n) {
        size_t m;
        uint8_t *d = lz_decode(p + off, seg, per_row * (h + 16) + 64, &m);
        if (!d) break;
        size_t rows = m / per_row;
        const uint8_t *ap = d, *pred = d + (alpha ? (size_t)w * rows : 0), *hi = pred + rows,
                      *lo = hi + (size_t)res * w * rows;
        memset(prev, 0, 3 * (size_t)w * sizeof *prev);
        for (size_t r = 0; r < rows; r++) {
            memset(cur, 0, 3 * (size_t)w * sizeof *cur);
            for (size_t x = 0; x < w; x++)
                for (int c = 0; c < res; c++) {
                    size_t i = (r * w + x) * res + c;
                    unsigned e = (unsigned)hi[i] << 8 | lo[i];
                    int v = (int)(e >> 1);
                    cur[3 * x + c] = (int16_t)((e & 1) ? -v : v);
                }
            switch (pred[r]) {
            case 1:
                for (int c = 0; c < 3; c++) cur[c] += prev[c];
                for (size_t x = 1; x < w; x++) {
                    int L = cur[3 * (x - 1)], U = prev[3 * x], UL = prev[3 * (x - 1)];
                    const int16_t *src = abs(U - UL) > abs(L - UL) ? prev + 3 * x : cur + 3 * (x - 1);
                    for (int c = 0; c < 3; c++) cur[3 * x + c] += src[c];
                }
                break;
            case 2:
                for (size_t i = 3; i < 3 * (size_t)w; i++) cur[i] += cur[i - 3];
                break;
            case 3:
                for (size_t i = 0; i < 3 * (size_t)w; i++) cur[i] += prev[i];
                break;
            case 4:
                for (int c = 0; c < 3; c++) cur[c] += prev[c];
                for (size_t i = 3; i < 3 * (size_t)w; i++) {
                    int s = cur[i - 3] + prev[i] + 1;
                    if (s < 0) s++;
                    cur[i] += (int16_t)(s >> 1);
                }
                break;
            default: break;
            }
            for (size_t x = 0; x < w; x++) {
                int R, G, B;
                if (res == 3) {
                    int Y = cur[3 * x], Co = cur[3 * x + 1], Cg = cur[3 * x + 2], t = Y - Cg;
                    R = t + Co;
                    G = Y + Cg;
                    B = t - Co;
                    if (format == 20) { R /= 2; G /= 2; B /= 2; } /* extended range: roughly half scale */
                } else R = G = B = cur[3 * x];
                uint8_t px[4] = {(uint8_t)MAX(0, MIN(255, R)), (uint8_t)MAX(0, MIN(255, G)),
                                 (uint8_t)MAX(0, MIN(255, B)), alpha ? ap[r * w + x] : 255};
                [rgba appendBytes:px length:4];
            }
            int16_t *t = prev;
            prev = cur;
            cur = t;
        }
        free(d);
        rows_total += rows;
        off += seg;
        if (off + 4 > n) break;
        seg = le32(p + off);
        off += 4;
    }
    free(prev);
    free(cur);
    return rows_total;
}

/* A dmp2 blob behind its 16-byte wrapper, or a stack of KCBC bands. */
static size_t deepmap2_decode(const uint8_t *p, size_t n, NSMutableData *rgba, uint32_t *width) {
    if (n >= 20 && !memcmp(p, "dmp2", 4)) return dmp2_decode(p, n, rgba, width);
    if (n >= 32 && !memcmp(p + 16, "dmp2", 4)) return dmp2_decode(p + 16, n - 16, rgba, width);
    size_t rows = 0;
    while (n >= 20 && !memcmp(p, "KCBC", 4)) {
        uint32_t len = le32(p + 16);
        if (20 + (size_t)len > n) break;
        rows += deepmap2_decode(p + 20, len, rgba, width);
        p += 20 + len;
        n -= 20 + len;
    }
    return rows;
}

static CGImageRef image_from_rgba(NSData *rgba, uint32_t w, size_t h) {
    if (!w || !h || rgba.length < (size_t)w * h * 4) return NULL;
    NSMutableData *pm = [NSMutableData dataWithLength:(size_t)w * h * 4];
    const uint8_t *s = rgba.bytes;
    uint8_t *d = pm.mutableBytes;
    for (size_t i = 0; i < (size_t)w * h; i++) {
        unsigned a = s[4 * i + 3];
        for (int c = 0; c < 3; c++) d[4 * i + c] = (uint8_t)((s[4 * i + c] * a + 127) / 255);
        d[4 * i + 3] = (uint8_t)a;
    }
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef dp = CGDataProviderCreateWithCFData((__bridge CFDataRef)pm);
    CGImageRef img = CGImageCreate(w, h, 8, 32, (size_t)w * 4, rgb, kCGImageAlphaPremultipliedLast, dp, NULL, false,
                                   kCGRenderingIntentDefault);
    CGDataProviderRelease(dp);
    CGColorSpaceRelease(rgb);
    return img;
}

/* ---- renditions ---- */

@implementation BNAssetCatalog (Renditions)
/* The bitmap of rendition `i` (atlases included), cached. */
- (CGImageRef)_bitmapAt:(NSUInteger)i {
    id cached = _decoded[@(i)];
    if (cached) return cached == [NSNull null] ? NULL : (__bridge CGImageRef)cached;
    CGImageRef img = NULL;
    NSData *v = _renditionValues[i];
    const uint8_t *c = v.bytes;
    if (v.length >= 184 && !memcmp(c, "ISTC", 4)) {
        uint32_t w = le32(c + 12), h = le32(c + 16), tlv = le32(c + 168);
        const uint8_t *data = c + 184 + tlv, *end = c + v.length;
        if (data + 16 <= end && !memcmp(data, "MLEC", 4)) {
            uint32_t comp = le32(data + 8), len = le32(data + 12);
            const uint8_t *payload = data + 16;
            if (payload + len > end) len = (uint32_t)(end - payload);
            NSMutableData *rgba = [NSMutableData data];
            uint32_t width = w;
            size_t rows = 0;
            if (comp == 11 || comp == 10) {
                rows = deepmap2_decode(payload, len, rgba, &width);
            } else if (comp == 4 || comp == 3 || comp == 0) {
                /* LZFSE / LZVN / stored premultiplied BGRA rows */
                size_t m = len;
                uint8_t *px = comp ? lz_decode(payload, len, (size_t)w * h * 4 + 64, &m) : NULL;
                const uint8_t *src = comp ? px : payload;
                if (src && m >= (size_t)w * h * 4) {
                    rows = h;
                    for (size_t k = 0; k < (size_t)w * h; k++) {
                        unsigned a = src[4 * k + 3];
                        uint8_t q[4] = {a ? (uint8_t)MIN(255u, src[4 * k + 2] * 255u / a) : 0,
                                        a ? (uint8_t)MIN(255u, src[4 * k + 1] * 255u / a) : 0,
                                        a ? (uint8_t)MIN(255u, src[4 * k] * 255u / a) : 0, (uint8_t)a};
                        [rgba appendBytes:q length:4];
                    }
                }
                free(px);
            }
            img = image_from_rgba(rgba, width, rows);
        }
    }
    _decoded[@(i)] = img ? (__bridge_transfer id)img : (id)[NSNull null];
    return img;
}

/* The rendition matching all the attribute pairs of a KLNI key. */
- (NSInteger)_renditionMatching:(const uint8_t *)pairs count:(size_t)n {
    for (NSUInteger i = 0; i < _renditionKeys.count; i++) {
        BOOL ok = YES;
        for (int a = 0; a < _nkeys && ok; a++) {
            uint16_t want = 0;
            for (size_t j = 0; j < n; j++)
                if (le16(pairs + 4 * j) == _keyformat[a]) want = le16(pairs + 4 * j + 2);
            if ([self _key:_renditionKeys[i] attribute:_keyformat[a]] != want) ok = NO;
        }
        if (ok) return (NSInteger)i;
    }
    return -1;
}

/* The image of rendition `i`, at its point size and scale. */
- (NSImage *)_imageAt:(NSUInteger)i {
    NSData *v = _renditionValues[i];
    const uint8_t *c = v.bytes;
    if (v.length < 184) return nil;
    uint32_t w = le32(c + 12), h = le32(c + 16), scale100 = le32(c + 20), tlvlen = le32(c + 168);
    uint16_t layout = le16(c + 36);
    CGFloat scale = scale100 ? scale100 / 100.0 : 1;
    CGImageRef img = NULL, owned = NULL;
    if (layout == 1003) {
        const uint8_t *t = c + 184, *end = t + tlvlen;
        while (t + 8 <= end && t + 8 <= c + v.length) {
            uint32_t type = le32(t), len = le32(t + 4);
            if (type == 1010 && len >= 34 && !memcmp(t + 8, "KLNI", 4)) {
                const uint8_t *r = t + 8;
                uint32_t x = le32(r + 8), y = le32(r + 12), fw = le32(r + 16), fh = le32(r + 20);
                size_t keybytes = le32(r + 26);
                size_t npairs = MIN(keybytes, (size_t)len - 30) / 4;
                NSInteger atlas = [self _renditionMatching:r + 30 count:npairs];
                CGImageRef full = atlas >= 0 ? [self _bitmapAt:(NSUInteger)atlas] : NULL;
                if (full) {
                    /* the atlas rectangle, measured from the atlas's bottom */
                    CGFloat top = (CGFloat)CGImageGetHeight(full) - y - fh;
                    owned = CGImageCreateWithImageInRect(full, CGRectMake(x, top, fw, fh));
                    img = owned;
                    w = fw;
                    h = fh;
                }
                break;
            }
            t += 8 + len;
        }
    } else {
        img = [self _bitmapAt:i];
    }
    if (!img) return nil;
    NSImage *image = [[NSImage alloc] initWithCGImage:img size:NSMakeSize(w / scale, h / scale)];
    if (owned) CGImageRelease(owned);
    return image;
}

- (NSImage *)imageNamed:(NSString *)name {
    NSData *facet = _facets[name];
    if (!facet) return nil;
    const uint8_t *f = facet.bytes;
    uint16_t count = le16(f + 4);
    uint32_t attrs[16], values[16];
    int na = 0;
    for (uint16_t i = 0; i < count && na < 16 && 6 + 4u * (i + 1) <= facet.length; i++) {
        attrs[na] = le16(f + 6 + 4 * i);
        values[na++] = le16(f + 8 + 4 * i);
    }
    /* The best rendition: the facet's attributes, light appearance, sRGB,
     * not a vector, the highest scale. */
    NSInteger best = -1;
    int bestScore = -1;
    for (NSUInteger i = 0; i < _renditionKeys.count; i++) {
        NSData *k = _renditionKeys[i];
        BOOL ok = YES;
        for (int a = 0; a < na && ok; a++)
            if ([self _key:k attribute:attrs[a]] != values[a]) ok = NO;
        if (!ok) continue;
        NSData *v = _renditionValues[i];
        if (v.length < 184) continue;
        uint16_t layout = le16((const uint8_t *)v.bytes + 36);
        if (!(layout == 12 || layout == 1003 || layout == 10 || layout == 11 || layout == 6)) continue;
        int score = [self _key:k attribute:12] * 4;              /* scale */
        if ([self _key:k attribute:7] == 0) score += 100;        /* appearance: any/light */
        if ([self _key:k attribute:24] == 0) score += 50;        /* sRGB gamut */
        if (score > bestScore) {
            bestScore = score;
            best = (NSInteger)i;
        }
    }
    return best >= 0 ? [self _imageAt:(NSUInteger)best] : nil;
}
@end

/* The image named `name` in the bundle's compiled asset catalog. */
NSImage *bn_asset_catalog_image(NSBundle *bundle, NSString *name) {
    static NSMutableDictionary *catalogs;
    NSString *path = [bundle pathForResource:@"Assets" ofType:@"car"];
    if (!path || !name.length) return nil;
    BNAssetCatalog *cat;
    @synchronized([BNAssetCatalog class]) {
        if (!catalogs) catalogs = [NSMutableDictionary dictionary];
        cat = catalogs[path];
        if (!cat) {
            cat = [[BNAssetCatalog alloc] initWithPath:path] ?: (id)[NSNull null];
            catalogs[path] = cat;
        }
        if ((id)cat == [NSNull null]) return nil;
        return [cat imageNamed:name];
    }
}

/* A deepmap2 blob (or KCBC bands of them) as an image; for tests. */
CGImageRef bn_deepmap2_image(const void *bytes, size_t n) {
    NSMutableData *rgba = [NSMutableData data];
    uint32_t w = 0;
    size_t rows = deepmap2_decode(bytes, n, rgba, &w);
    return image_from_rgba(rgba, w, rows);
}
