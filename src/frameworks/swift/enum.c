/* Enum layout and tags. Compiled code computes the same encodings inline
 * for enums whose layout it knows, so every bit here is ABI:
 *
 * Single payload: empty cases first use the payload's extra inhabitants
 * (case k <-> inhabitant k-1); the rest go in extra tag bytes after the
 * payload (1, 2 or 4 bytes, little-endian) with the case index spread over
 * the payload bytes (at most 4 used, the rest zeroed) and the tag. */
#define _GNU_SOURCE
#include <string.h>

#include "swift_internal.h"

/* Little-endian loads and stores of 0..4 significant bytes; wider areas
 * keep the value in their first four bytes and zeros after. */
static uint32_t load_elem(const void *p, size_t size) {
    uint32_t v = 0;
    memcpy(&v, p, size < 4 ? size : 4);
    return v;
}
static void store_elem(void *p, uint32_t v, size_t size) {
    memcpy(p, &v, size < 4 ? size : 4);
    if (size > 4) memset((char *)p + 4, 0, size - 4);
}

struct tag_counts {
    unsigned num_tags, num_tag_bytes;
};
/* How many tag values, and bytes for them, an enum with `payload_cases`
 * payloads and `empty_cases` empty cases (that did not fit in extra
 * inhabitants) needs when its payload area is `size` bytes. */
static struct tag_counts enum_tag_counts(size_t size, unsigned empty_cases, unsigned payload_cases) {
    unsigned tags = payload_cases;
    if (empty_cases > 0) {
        if (size >= 4) {
            tags += 1; /* one tag value spans 2^32 cases of the payload area */
        } else {
            unsigned bits = (unsigned)size * 8;
            tags += (empty_cases + (1U << bits) - 1) >> bits;
        }
    }
    unsigned bytes = tags <= 1 ? 0 : tags < 256 ? 1 : tags < 65536 ? 2 : 4;
    return (struct tag_counts){tags, bytes};
}

unsigned sw_get_enum_tag_single_payload(const sw_opaque *v, unsigned empty_cases,
                                        const sw_metadata *payload, sw_xi_get_fn get) {
    const sw_vwt *w = sw_vwt_of(payload);
    size_t psize = w->size;
    unsigned pxi = w->extraInhabitantCount;
    if (empty_cases > pxi) {
        const uint8_t *bytes = (const uint8_t *)v;
        unsigned ntb = enum_tag_counts(psize, empty_cases - pxi, 1).num_tag_bytes;
        unsigned extra = load_elem(bytes + psize, ntb);
        if (extra > 0) {
            unsigned from_tag = psize >= 4 ? 0 : (extra - 1) << (psize * 8);
            unsigned from_value = load_elem(bytes, psize);
            return (from_tag | from_value) + pxi + 1;
        }
    }
    if (pxi > 0) return get ? get(v, pxi, payload) : w->getEnumTagSinglePayload(v, pxi, payload);
    return 0;
}

void sw_store_enum_tag_single_payload(sw_opaque *v, unsigned which, unsigned empty_cases,
                                      const sw_metadata *payload, sw_xi_store_fn store) {
    const sw_vwt *w = sw_vwt_of(payload);
    size_t psize = w->size;
    unsigned pxi = w->extraInhabitantCount;
    uint8_t *bytes = (uint8_t *)v;
    unsigned ntb = empty_cases > pxi ? enum_tag_counts(psize, empty_cases - pxi, 1).num_tag_bytes : 0;
    if (which <= pxi) {
        if (ntb) store_elem(bytes + psize, 0, ntb);
        if (which == 0) return;
        if (store) store(v, which, pxi, payload);
        else w->storeEnumTagSinglePayload(v, which, pxi, payload);
        return;
    }
    unsigned index = which - 1 - pxi, payload_index, tag_index;
    if (psize >= 4) {
        tag_index = 1;
        payload_index = index;
    } else {
        unsigned bits = (unsigned)psize * 8;
        tag_index = 1 + (index >> bits);
        payload_index = index & ((1U << bits) - 1);
    }
    if (psize) store_elem(bytes, payload_index, psize);
    if (ntb) store_elem(bytes + psize, tag_index, ntb);
}

/* unsigned swift_getEnumTagSinglePayloadGeneric(const OpaqueValue *value,
 *     unsigned emptyCases, const Metadata *payloadType, getExtraInhabitantTag_t *) */
static unsigned d_swift_getEnumTagSinglePayloadGeneric(const sw_opaque *v, unsigned empty,
                                                       const sw_metadata *payload,
                                                       sw_xi_get_fn get) {
    return sw_get_enum_tag_single_payload(v, empty, payload, get);
}
DX_FN(swift_getEnumTagSinglePayloadGeneric);

static void d_swift_storeEnumTagSinglePayloadGeneric(sw_opaque *v, unsigned which, unsigned empty,
                                                     const sw_metadata *payload,
                                                     sw_xi_store_fn store) {
    sw_store_enum_tag_single_payload(v, which, empty, payload, store);
}
DX_FN(swift_storeEnumTagSinglePayloadGeneric);
