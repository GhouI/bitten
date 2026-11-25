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

/* ---- layout ----------------------------------------------------------------------- */

/* Enum metadata: the descriptor gives the number of payload cases (low 24
 * bits) and the word offset of the payload size the runtime stores for
 * multi-payload enums (high 8 bits). */
static const sw_enum_descriptor *enum_desc(const sw_metadata *m) {
    return (const sw_enum_descriptor *)((const sw_value_metadata *)m)->description;
}
static unsigned num_payload_cases(const sw_metadata *m) {
    return enum_desc(m)->num_payload_cases_and_payload_size_offset & 0xFFFFFF;
}
static size_t *payload_size_slot(const sw_metadata *m) {
    unsigned off = enum_desc(m)->num_payload_cases_and_payload_size_offset >> 24;
    return off ? (size_t *)m + off : NULL;
}

/* void swift_initEnumMetadataSingleCase(EnumMetadata *, EnumLayoutFlags,
 *     const TypeLayout *payload): the enum is laid out as its payload. */
static void d_swift_initEnumMetadataSingleCase(sw_metadata *self, uintptr_t flags,
                                               const sw_type_layout *payload) {
    sw_vwt *w = sw_mutable_vwt(self, flags);
    sw_type_layout l = *payload;
    l.flags = (payload->flags & ~SW_VW_INCOMPLETE) | SW_VW_HAS_ENUM_WITNESSES;
    sw_publish_layout(w, &l);
}
DX_FN(swift_initEnumMetadataSingleCase);

/* void swift_initEnumMetadataSinglePayload(EnumMetadata *, EnumLayoutFlags,
 *     const TypeLayout *payload, unsigned emptyCases) */
static void d_swift_initEnumMetadataSinglePayload(sw_metadata *self, uintptr_t flags,
                                                  const sw_type_layout *payload, unsigned empty) {
    size_t psize = payload->size, size = psize;
    unsigned pxi = payload->extraInhabitantCount, xi = 0;
    if (pxi >= empty)
        xi = pxi - empty;
    else
        size += enum_tag_counts(psize, empty - pxi, 1).num_tag_bytes;
    size_t am = payload->flags & SW_VW_ALIGNMENT_MASK;
    int bt = !(payload->flags & SW_VW_IS_NON_BITWISE_TAKABLE);
    sw_type_layout l;
    l.size = size;
    l.stride = (size + am) & ~am;
    if (!l.stride) l.stride = 1;
    l.flags = (payload->flags & ~(SW_VW_INCOMPLETE | SW_VW_IS_NON_INLINE)) |
              SW_VW_HAS_ENUM_WITNESSES | (sw_is_inline(bt, size, am) ? 0 : SW_VW_IS_NON_INLINE);
    l.extraInhabitantCount = xi;
    sw_publish_layout(sw_mutable_vwt(self, flags), &l);
}
DX_FN(swift_initEnumMetadataSinglePayload);

/* ---- multi-payload enums ------------------------------------------------------------
 * Laid out by the runtime, they use no spare bits: the payload area is as
 * large as the largest payload, followed by tag bytes. Tags 0..n-1 select a
 * payload case; empty cases use the following tags with the case index
 * spread over the payload area (as for single-payload enums). Tag values
 * past the used ones are the extra inhabitants, counted down from all ones:
 * inhabitant i is the tag ~i. */
struct mp_layout {
    size_t payload_size, tag_bytes;
};
static struct mp_layout mp_layout(const sw_metadata *m) {
    size_t *slot = payload_size_slot(m);
    size_t ps = slot ? *slot : 0;
    return (struct mp_layout){ps, sw_vwt_of(m)->size - ps};
}

static unsigned mp_xi_get(const sw_opaque *v, unsigned n, const sw_metadata *m) {
    struct mp_layout l = mp_layout(m);
    uint32_t mask = l.tag_bytes >= 4 ? 0xFFFFFFFFu : (1u << (8 * l.tag_bytes)) - 1;
    uint32_t index = ~load_elem((const char *)v + l.payload_size, l.tag_bytes) & mask;
    return index < sw_vwt_of(m)->extraInhabitantCount ? index + 1 : 0;
}
static void mp_xi_store(sw_opaque *v, unsigned which, unsigned n, const sw_metadata *m) {
    struct mp_layout l = mp_layout(m);
    store_elem((char *)v + l.payload_size, ~(which - 1), l.tag_bytes);
}
/* The witnesses compiled multi-payload enums leave to the runtime (their
 * own getEnumTagSinglePayload calls through the VWT). */
static unsigned mp_get_tag(const sw_opaque *v, unsigned empty, const sw_metadata *m) {
    return sw_get_enum_tag_single_payload(v, empty, m, mp_xi_get);
}
static void mp_store_tag(sw_opaque *v, unsigned which, unsigned empty, const sw_metadata *m) {
    sw_store_enum_tag_single_payload(v, which, empty, m, mp_xi_store);
}

/* void swift_initEnumMetadataMultiPayload(EnumMetadata *, EnumLayoutFlags,
 *     unsigned numPayloads, const TypeLayout *const *payloadLayouts) */
static void d_swift_initEnumMetadataMultiPayload(sw_metadata *self, uintptr_t flags, unsigned n,
                                                 const sw_type_layout *const *payloads) {
    size_t psize = 0, am = 0;
    uint32_t inherited = 0;
    for (unsigned i = 0; i < n; i++) {
        if (payloads[i]->size > psize) psize = payloads[i]->size;
        am |= payloads[i]->flags & SW_VW_ALIGNMENT_MASK;
        inherited |= payloads[i]->flags & (SW_VW_IS_NON_POD | SW_VW_IS_NON_BITWISE_TAKABLE |
                                           SW_VW_IS_NON_COPYABLE | SW_VW_IS_NON_BITWISE_BORROWABLE);
    }
    size_t *slot = payload_size_slot(self);
    if (slot) *slot = psize;
    struct tag_counts tc = enum_tag_counts(psize, enum_desc(self)->num_empty_cases, n);
    size_t size = psize + tc.num_tag_bytes;
    unsigned xi = tc.num_tag_bytes == 4 ? SW_VW_MAX_NUM_EXTRA_INHABITANTS
                                        : (1u << (tc.num_tag_bytes * 8)) - tc.num_tags;
    if (xi > SW_VW_MAX_NUM_EXTRA_INHABITANTS) xi = SW_VW_MAX_NUM_EXTRA_INHABITANTS;
    sw_type_layout l;
    l.size = size;
    l.stride = (size + am) & ~am;
    if (!l.stride) l.stride = 1;
    l.flags = (uint32_t)am | inherited | SW_VW_HAS_ENUM_WITNESSES |
              (sw_is_inline(!(inherited & SW_VW_IS_NON_BITWISE_TAKABLE), size, am)
                   ? 0 : SW_VW_IS_NON_INLINE);
    l.extraInhabitantCount = xi;
    sw_vwt *w = sw_mutable_vwt(self, flags);
    w->getEnumTagSinglePayload = mp_get_tag;
    w->storeEnumTagSinglePayload = mp_store_tag;
    sw_publish_layout(w, &l);
}
DX_FN(swift_initEnumMetadataMultiPayload);

/* unsigned swift_getEnumCaseMultiPayload(const OpaqueValue *, const EnumMetadata *) */
static unsigned d_swift_getEnumCaseMultiPayload(const sw_opaque *v, const sw_metadata *m) {
    struct mp_layout l = mp_layout(m);
    unsigned np = num_payload_cases(m);
    unsigned tag = load_elem((const char *)v + l.payload_size, l.tag_bytes);
    if (tag < np) return tag;
    unsigned value = load_elem(v, l.payload_size);
    if (l.payload_size >= 4) return np + value;
    return (value | (tag - np) << (l.payload_size * 8)) + np;
}
DX_FN(swift_getEnumCaseMultiPayload);

/* void swift_storeEnumTagMultiPayload(OpaqueValue *, const EnumMetadata *, unsigned whichCase) */
static void d_swift_storeEnumTagMultiPayload(sw_opaque *v, const sw_metadata *m, unsigned which) {
    struct mp_layout l = mp_layout(m);
    unsigned np = num_payload_cases(m);
    char *tagp = (char *)v + l.payload_size;
    if (which < np) {
        store_elem(tagp, which, l.tag_bytes);
        return;
    }
    unsigned empty = which - np, tag, value;
    if (l.payload_size >= 4) {
        tag = np;
        value = empty;
    } else {
        unsigned bits = (unsigned)l.payload_size * 8;
        tag = np + (empty >> bits);
        value = empty & ((1u << bits) - 1);
    }
    store_elem(tagp, tag, l.tag_bytes);
    store_elem(v, value, l.payload_size);
}
DX_FN(swift_storeEnumTagMultiPayload);
