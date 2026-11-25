/* Integer literals converted to floating point at run time.
 *
 * The compiler represents an integer literal of any size as an array of
 * 64-bit words, least significant first, in two's complement, and a flags
 * word: bit 0 set when the value is negative, the bit width from bit 8 up.
 * When it cannot fold `Double(integerLiteral)` it calls these with the two
 * words (swiftcc and C agree here; the result comes back in xmm0). */
#include <math.h>
#include <stddef.h>
#include <stdint.h>

#include "dx.h"

/* The literal's magnitude as a long double carrying its top 64 bits, with
 * any lower nonzero bits folded into the lowest bit (a sticky bit). Every
 * value up to 64 bits is exact; a wider one is rounded once more when
 * narrowed to float or double, and the sticky bit makes that rounding
 * correct because 64 bits leave more than two guard bits for both. */
static long double literal_value(const uint64_t *data, size_t flags) {
    size_t bits = flags >> 8;
    int negative = flags & 1;
    size_t n = bits ? (bits + 63) / 64 : 1;
    if (n == 1)
        return negative ? (long double)(int64_t)data[0] : (long double)data[0];

    /* Magnitude of a multiword two's-complement value, at most 128 words
     * (larger literals are rejected by the compiler long before). */
    uint64_t mag[128];
    if (n > 128) n = 128;
    unsigned carry = 1;
    for (size_t i = 0; i < n; i++) {
        uint64_t w = negative ? ~data[i] : data[i];
        if (negative) {
            uint64_t s = w + carry;
            carry = carry && s == 0;
            w = s;
        }
        mag[i] = w;
    }
    size_t top = n;
    while (top > 0 && mag[top - 1] == 0) top--;
    if (top == 0) return 0.0L;
    int lead = __builtin_clzll(mag[top - 1]);
    /* The 64 bits starting at the leading one. */
    uint64_t hi = mag[top - 1] << lead;
    int sticky = 0;
    if (top >= 2) {
        if (lead) hi |= mag[top - 2] >> (64 - lead);
        if ((lead ? mag[top - 2] << lead : mag[top - 2]) != 0) sticky = 1;
        for (size_t i = 0; i + 2 < top; i++)
            if (mag[i]) sticky = 1;
    }
    if (sticky) hi |= 1;
    /* hi * 2^(position of its low bit) */
    long double v = ldexpl((long double)hi, (int)((top - 1) * 64) - lead);
    return negative ? -v : v;
}

static float d_swift_intToFloat32(const uint64_t *data, size_t flags) {
    return (float)literal_value(data, flags);
}
DX_FN(swift_intToFloat32);

static double d_swift_intToFloat64(const uint64_t *data, size_t flags) {
    return (double)literal_value(data, flags);
}
DX_FN(swift_intToFloat64);
