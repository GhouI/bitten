/* Number formatting for the standard library's descriptions: the runtime
 * entry points Apple's libswiftCore exports for the same job.
 *
 *   uint64_t swift_float32ToString(char *buf, size_t len, float v, bool debug)
 *   uint64_t swift_float64ToString(char *buf, size_t len, double v, bool debug)
 *   uint64_t swift_float80ToString(char *buf, size_t len, long double v, bool debug)
 *   uint64_t swift_int64ToString(char *buf, size_t len, int64_t v, int64_t radix, bool upper)
 *   uint64_t swift_uint64ToString(char *buf, size_t len, uint64_t v, int64_t radix, bool upper)
 *
 * Each writes the text (no NUL needed) and returns its length, 0 if it does
 * not fit.
 *
 * Floating point follows Swift's rules: the shortest digit string that
 * reads back as the same value (the nearest one among the shortest), in
 * decimal form ("100.0", "0.001") when the value is at least 1e-4 and at
 * most 2^(significand bits + 1), otherwise exponential with a signed
 * exponent of at least two digits ("1e+16", "5e-324", "1.5e-05");
 * "inf", "-inf", "nan" ("-nan", "snan" and payloads "nan(0x1)" in debug
 * form), "0.0", "-0.0". The shortest digits are found by asking printf for
 * 1, 2, ... significant digits and keeping the first that round-trips:
 * printf rounds correctly, so that string is the nearest of its length. */
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dx.h"

enum fkind { F32, F64, F80 };

/* Shortest round-trip digits of a finite, nonzero, positive value: the
 * digits (no point) into `digits`, and the decimal exponent e such that the
 * value is 0.d1d2... x 10^e. Returns the number of digits. */
static int shortest_digits(enum fkind k, long double v, char *digits, int *exp10) {
    int maxp = k == F32 ? 9 : k == F64 ? 17 : 21;
    char tmp[64];
    for (int p = 1; p <= maxp; p++) {
        int ok;
        if (k == F32) {
            snprintf(tmp, sizeof tmp, "%.*e", p - 1, (double)(float)v);
            ok = strtof(tmp, NULL) == (float)v;
        } else if (k == F64) {
            snprintf(tmp, sizeof tmp, "%.*e", p - 1, (double)v);
            ok = strtod(tmp, NULL) == (double)v;
        } else {
            snprintf(tmp, sizeof tmp, "%.*Le", p - 1, v);
            ok = strtold(tmp, NULL) == v;
        }
        if (ok || p == maxp) {
            /* tmp is d[.ddd]e[+-]XX */
            int n = 0;
            const char *s = tmp;
            for (; *s && *s != 'e'; s++)
                if (*s >= '0' && *s <= '9') digits[n++] = *s;
            int e = atoi(s + 1);
            while (n > 1 && digits[n - 1] == '0') n--;
            digits[n] = 0;
            *exp10 = e + 1;
            return n;
        }
    }
    return 0; /* not reached */
}

static uint64_t emit(char *buf, size_t len, const char *s, size_t n) {
    if (n > len) return 0;
    memcpy(buf, s, n);
    if (n < len) buf[n] = 0;
    return n;
}

static uint64_t format_float(char *buf, size_t len, enum fkind k, long double v, bool neg,
                             bool isnan_, bool signaling, uint64_t payload, bool debug) {
    char out[128];
    size_t n = 0;
    if (isnan_) {
        if (debug) {
            if (neg) out[n++] = '-';
            if (signaling) out[n++] = 's';
            memcpy(out + n, "nan", 3), n += 3;
            if (payload) n += (size_t)snprintf(out + n, sizeof out - n, "(0x%llx)", (unsigned long long)payload);
        } else {
            memcpy(out, "nan", 3), n = 3;
        }
        return emit(buf, len, out, n);
    }
    if (neg) out[n++] = '-', v = -v;
    if (isinf(v)) {
        memcpy(out + n, "inf", 3), n += 3;
        return emit(buf, len, out, n);
    }
    if (v == 0) {
        memcpy(out + n, "0.0", 3), n += 3;
        return emit(buf, len, out, n);
    }
    char d[32];
    int e;
    int nd = shortest_digits(k, v, d, &e);
    long double limit = k == F32 ? 0x1p24L : k == F64 ? 0x1p53L : 0x1p64L;
    if (e < -3 || v > limit) {
        out[n++] = d[0];
        if (nd > 1) {
            out[n++] = '.';
            memcpy(out + n, d + 1, (size_t)nd - 1), n += (size_t)nd - 1;
        }
        int x = e - 1;
        out[n++] = 'e';
        out[n++] = x < 0 ? '-' : '+';
        if (x < 0) x = -x;
        n += (size_t)snprintf(out + n, sizeof out - n, "%02d", x);
    } else if (e <= 0) {
        out[n++] = '0', out[n++] = '.';
        for (int i = 0; i < -e; i++) out[n++] = '0';
        memcpy(out + n, d, (size_t)nd), n += (size_t)nd;
    } else {
        for (int i = 0; i < e; i++) out[n++] = i < nd ? d[i] : '0';
        out[n++] = '.';
        if (nd > e) {
            memcpy(out + n, d + e, (size_t)(nd - e)), n += (size_t)(nd - e);
        } else {
            out[n++] = '0';
        }
    }
    return emit(buf, len, out, n);
}

static uint64_t d_swift_float32ToString(char *buf, size_t len, float v, bool debug) {
    uint32_t bits;
    memcpy(&bits, &v, 4);
    bool nan = isnan(v);
    return format_float(buf, len, F32, v, bits >> 31, nan, nan && !(bits & 0x400000),
                        bits & 0x3FFFFF, debug);
}
DX_FN(swift_float32ToString);

static uint64_t d_swift_float64ToString(char *buf, size_t len, double v, bool debug) {
    uint64_t bits;
    memcpy(&bits, &v, 8);
    bool nan = isnan(v);
    return format_float(buf, len, F64, v, bits >> 63, nan, nan && !(bits & 0x8000000000000ULL),
                        bits & 0x7FFFFFFFFFFFFULL, debug);
}
DX_FN(swift_float64ToString);

/* Float80 is passed in memory (on the stack), as C passes long double. */
static uint64_t d_swift_float80ToString(char *buf, size_t len, long double v, bool debug) {
    uint64_t sig;
    uint16_t se;
    memcpy(&sig, &v, 8);
    memcpy(&se, (char *)&v + 8, 2);
    bool nan = isnan(v);
    return format_float(buf, len, F80, v, se >> 15, nan, nan && !(sig & 0x4000000000000000ULL),
                        sig & 0x3FFFFFFFFFFFFFFFULL, debug);
}
DX_FN(swift_float80ToString);

static uint64_t utoa(char *buf, size_t len, uint64_t v, bool neg, int64_t radix, bool upper) {
    if (radix < 2 || radix > 36) return 0;
    const char *dig = upper ? "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" : "0123456789abcdefghijklmnopqrstuvwxyz";
    char tmp[72];
    size_t n = 0;
    do {
        tmp[n++] = dig[v % (uint64_t)radix];
        v /= (uint64_t)radix;
    } while (v);
    if (neg) tmp[n++] = '-';
    if (n > len) return 0;
    for (size_t i = 0; i < n; i++) buf[i] = tmp[n - 1 - i];
    return n;
}

static uint64_t d_swift_int64ToString(char *buf, size_t len, int64_t v, int64_t radix, bool upper) {
    return utoa(buf, len, v < 0 ? 0 - (uint64_t)v : (uint64_t)v, v < 0, radix, upper);
}
DX_FN(swift_int64ToString);

static uint64_t d_swift_uint64ToString(char *buf, size_t len, uint64_t v, int64_t radix, bool upper) {
    return utoa(buf, len, v, false, radix, upper);
}
DX_FN(swift_uint64ToString);

/* const char *_swift_stdlib_strtod_clocale(const char *nptr, double *out),
 * and the float and long double forms: parse a number in the C locale and
 * return the end of what was parsed (NULL if nothing was). Unlike strtod,
 * leading white space is not a number. */
static const char *d__swift_stdlib_strtod_clocale(const char *nptr, double *out) {
    if (!*nptr || (*nptr >= '\t' && *nptr <= '\r') || *nptr == ' ') return NULL;
    char *end;
    *out = strtod(nptr, &end);
    return end == nptr ? NULL : end;
}
DX_EXPORT("__swift_stdlib_strtod_clocale", d__swift_stdlib_strtod_clocale);

static const char *d__swift_stdlib_strtof_clocale(const char *nptr, float *out) {
    if (!*nptr || (*nptr >= '\t' && *nptr <= '\r') || *nptr == ' ') return NULL;
    char *end;
    *out = strtof(nptr, &end);
    return end == nptr ? NULL : end;
}
DX_EXPORT("__swift_stdlib_strtof_clocale", d__swift_stdlib_strtof_clocale);

static const char *d__swift_stdlib_strtold_clocale(const char *nptr, long double *out) {
    if (!*nptr || (*nptr >= '\t' && *nptr <= '\r') || *nptr == ' ') return NULL;
    char *end;
    *out = strtold(nptr, &end);
    return end == nptr ? NULL : end;
}
DX_EXPORT("__swift_stdlib_strtold_clocale", d__swift_stdlib_strtold_clocale);

/* void swift_stdlib_random(void *buf, size_t nbytes): cryptographically
 * random bytes, for SystemRandomNumberGenerator. */
#include <sys/random.h>
static void d_swift_stdlib_random(void *buf, size_t n) {
    unsigned char *p = buf;
    while (n) {
        ssize_t got = getrandom(p, n, 0);
        if (got <= 0) continue;
        p += got;
        n -= (size_t)got;
    }
}
DX_FN(swift_stdlib_random);
