/* Protocol conformances, witness tables and associated types.
 *
 * Every image lists its conformances in __swift5_proto (32-bit relative
 * references to conformance descriptors). They are indexed by the type
 * they are about: its nominal type descriptor, or for Objective-C classes
 * the class (by name or by reference). A lookup of (type, protocol) walks
 * the type and, for classes, its superclasses, checks the conformance's
 * conditional requirements against the type's generic arguments and asks
 * swift_getWitnessTable for the table. Answers are cached per (type,
 * protocol); negative answers only until another image with conformances
 * is loaded.
 *
 * Witness tables of generic or resilient conformances are instantiated per
 * conforming type from the pattern the compiler emits: copied, completed
 * with default and resilient witnesses, conditional conformances stored in
 * the private area in front of the table (where compiled accessors read
 * them, table[-1 - i]), then handed to the conformance's instantiator.
 *
 * Associated type and associated conformance slots start out as tagged
 * pointers (low bit set) to a mangled name or a symbolic reference to an
 * accessor function and are resolved on first use. Resolved values are
 * kept in a side table rather than written back, because a pattern table
 * may live in read-only memory. */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "sw_map.h"
#include "swift_internal.h"

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static struct sw_map by_type;  /* (descriptor | class | name hash, key kind) -> struct conf* */
static struct sw_map cache;    /* (type, protocol) -> witness table, or generation<<1|1 if none */
static struct sw_map tables;   /* (conformance, type) -> instantiated witness table */
static struct sw_map resolved; /* (witness table, slot) -> resolved associated type/conformance */
static uintptr_t generation;

enum { KEY_DESC = 0, KEY_NAME = 1, KEY_CLASS = 2 };

struct conf {
    struct conf *next;
    const sw_conformance_descriptor *c;
    const char *name; /* for KEY_NAME */
};

static void *rt(const char *name) { return dx_registry_lookup(name); }
static const char *objc_class_name(const void *cls) {
    static const char *(*getname)(const void *);
    if (!getname) getname = (const char *(*)(const void *))rt("_class_getName");
    return getname && cls ? getname(cls) : NULL;
}

/* Descriptors of imported C types are emitted by every module that uses
 * them ("non-unique"), so they are matched by qualified name. */
static char *descriptor_key_name(const sw_type_context_descriptor *d) {
    char *buf = malloc(512);
    sw_context_name((const sw_context_descriptor *)d, buf, 512);
    return buf;
}

static void index_conformance(const sw_conformance_descriptor *c) {
    unsigned kind = (c->flags & SW_CONF_TYPE_REF_KIND_MASK) >> SW_CONF_TYPE_REF_KIND_SHIFT;
    const void *ref = sw_rel(&c->type_ref);
    if (!ref) return;
    struct conf *e = calloc(1, sizeof *e);
    e->c = c;
    uintptr_t a, b;
    switch (kind) {
    case 0: case 1: {
        const sw_type_context_descriptor *d = kind ? *(const void *const *)ref : ref;
        if (!d) goto drop;
        if (sw_ctx_is_unique(d->flags)) {
            a = (uintptr_t)d;
            b = KEY_DESC;
        } else {
            e->name = descriptor_key_name(d);
            a = sw_hash_bytes(e->name, strlen(e->name));
            b = KEY_NAME;
        }
        break;
    }
    case 2: /* Objective-C class by name */
        e->name = ref;
        a = sw_hash_bytes(e->name, strlen(e->name));
        b = KEY_NAME;
        break;
    case 3: /* Objective-C class by reference (a bound class reference) */
        a = (uintptr_t)*(const void *const *)ref;
        b = KEY_CLASS;
        if (!a) goto drop;
        break;
    default:
        goto drop;
    }
    e->next = sw_map_get(&by_type, a, b, NULL);
    sw_map_put(&by_type, a, b, e);
    return;
drop:
    free(e);
}

static void add_section(const struct sw_section *s, void *ctx) {
    const int32_t *refs = s->start;
    pthread_mutex_lock(&lock);
    for (size_t i = 0; i < s->size / 4; i++) {
        const sw_conformance_descriptor *c = sw_rel(&refs[i]);
        if (c) index_conformance(c);
    }
    generation++; /* negative answers may have changed */
    pthread_mutex_unlock(&lock);
}

static pthread_once_t once = PTHREAD_ONCE_INIT;
static void init_index(void) { sw_each_section(SW_SECT_PROTO, add_section, NULL, 1); }

/* ---- witness tables -------------------------------------------------------- */
struct generic_wt {
    uint16_t size_in_words;
    uint16_t private_and_flag; /* private size in words << 1 | requires instantiation */
    int32_t instantiator;
    int32_t private_data;
};

/* Trailing objects of a conformance descriptor, in order. */
struct conf_tail {
    const sw_generic_requirement *cond;
    unsigned ncond;
    const uint32_t *resilient; /* count, then {req, witness} pairs */
    const struct generic_wt *gwt;
};
static void conf_tail(const sw_conformance_descriptor *c, struct conf_tail *t) {
    const char *p = (const char *)(c + 1);
    if (c->flags & SW_CONF_IS_RETROACTIVE) p += 4;
    t->ncond = (c->flags >> SW_CONF_NUM_CONDITIONAL_REQUIREMENTS_SHIFT) & 0xFF;
    t->cond = (const void *)p;
    p += t->ncond * sizeof(sw_generic_requirement);
    /* Conditional pack requirements: one pack shape descriptor each
     * (flags bits 24-31), with no header. */
    p += ((c->flags >> 24) & 0xFF) * sizeof(sw_pack_shape_descriptor);
    t->resilient = NULL;
    if (c->flags & SW_CONF_HAS_RESILIENT_WITNESSES) {
        t->resilient = (const void *)p;
        p += 4 + 8 * t->resilient[0];
    }
    t->gwt = (c->flags & SW_CONF_HAS_GENERIC_WITNESS_TABLE) ? (const void *)p : NULL;
}

typedef void (*wt_instantiator)(void **table, const sw_metadata *type, const void *const *args);
typedef const sw_witness_table *(*assoc_conf_accessor)(const sw_metadata *assoc, const sw_metadata *self,
                                                       const sw_witness_table *wt);

static const sw_witness_table *d_swift_getWitnessTable(const sw_conformance_descriptor *c,
                                                       const sw_metadata *type, const void *const *args) {
    const char *missing = dx_stub_name(c);
    if (missing) dx_fatal("swift: protocol conformance %s is not implemented in bitten yet", missing);
    const void *const *pattern = sw_rel(&c->witness_table_pattern);
    if (!(c->flags & (SW_CONF_HAS_GENERIC_WITNESS_TABLE | SW_CONF_HAS_RESILIENT_WITNESSES)))
        return (const sw_witness_table *)pattern;
    pthread_mutex_lock(&lock);
    const sw_witness_table *wt = sw_map_get(&tables, (uintptr_t)c, (uintptr_t)type, NULL);
    pthread_mutex_unlock(&lock);
    if (wt) return wt;

    struct conf_tail t;
    conf_tail(c, &t);
    const sw_protocol_descriptor *proto = sw_rel_indirect(&c->protocol);
    const char *missing_proto = proto ? dx_stub_name(proto) : NULL;
    if (missing_proto) dx_fatal("swift: protocol %s (needed by a conformance) is not implemented in bitten yet", missing_proto);
    unsigned pattern_words = t.gwt ? t.gwt->size_in_words : 1;
    /* The table holds the conformance and one word per requirement of the
     * protocol, whatever the pattern copies in (it can be empty). */
    unsigned size = pattern_words;
    if (size < 1 + proto->num_requirements) size = 1 + proto->num_requirements;
    unsigned priv = t.gwt ? t.gwt->private_and_flag >> 1 : 0;
    void **mem = calloc(priv + size, sizeof *mem), **table = mem + priv;
    if (pattern) memcpy(table, pattern, pattern_words * sizeof *table);
    table[0] = (void *)c;
    const sw_protocol_requirement *reqs = sw_protocol_requirements(proto);
    if (t.resilient) {
        /* Requirements the conformance does not name use the protocol's
         * default implementation. */
        for (uint32_t i = 0; i < proto->num_requirements && 1 + i < size; i++)
            if (!table[1 + i]) table[1 + i] = (void *)sw_rel(&reqs[i].default_implementation);
        const int32_t *w = (const int32_t *)(t.resilient + 1);
        for (uint32_t i = 0; i < t.resilient[0]; i++, w += 2) {
            const sw_protocol_requirement *r = sw_rel_indirect(&w[0]);
            if (!r || r < reqs || r >= reqs + proto->num_requirements) continue;
            uintptr_t v = (uintptr_t)sw_rel(&w[1]);
            unsigned kind = r->flags & 0xF;
            if (kind == 7 || kind == 8) v |= 1; /* a mangled name, resolved on use */
            table[1 + (r - reqs)] = (void *)v;
        }
    }
    /* Conditional conformances go in the private area, last-to-first in
     * front of the table. */
    unsigned nkey = 0;
    for (unsigned i = 0; i < t.ncond; i++)
        if ((t.cond[i].flags & 0x1F) == SW_REQ_PROTOCOL && (t.cond[i].flags & SW_GP_HAS_KEY_ARGUMENT)) nkey++;
    /* A pack requirement's witness tables come as a pack: on the heap, so
     * the table can keep it (its length is the type's first pack length). */
    const void *const *targs = sw_generic_args(type);
    const sw_generic_context_header *th =
        sw_generic_header((const sw_context_descriptor *)sw_type_descriptor(type));
    unsigned tpacks = 0, tshapes = 0;
    if (th) sw_pack_shapes(th, &tpacks, &tshapes);
    for (unsigned i = 0, k = 0; i < t.ncond && k < nkey && k < priv && args; i++) {
        if ((t.cond[i].flags & 0x1F) != SW_REQ_PROTOCOL || !(t.cond[i].flags & SW_GP_HAS_KEY_ARGUMENT)) continue;
        const void *v = args[k];
        if ((t.cond[i].flags & 0x20) && tshapes && targs)
            v = sw_heap_pack((const void *const *)v, (size_t)(uintptr_t)targs[0]);
        table[-1 - (int)k] = (void *)v;
        k++;
    }
    if (t.gwt && t.gwt->instantiator) {
        wt_instantiator fn = (wt_instantiator)sw_rel(&t.gwt->instantiator);
        fn(table, type, args);
    }
    /* Base-protocol entries are read directly by compiled code (wt[n] is
     * the base protocol's witness table), so they cannot stay as the
     * tagged references a resilient conformance carries: resolve them now
     * through the accessor the reference names (\xFF \x07 <rel32>), with
     * Self as the "associated type". */
    if (t.resilient)
        for (uint32_t i = 0; i < proto->num_requirements && 1 + i < size; i++) {
            uintptr_t v = (uintptr_t)table[1 + i];
            if ((reqs[i].flags & 0xF) != 0 || !(v & 1)) continue;
            const unsigned char *name = (const unsigned char *)(v & ~(uintptr_t)1);
            if (name[0] == 0xFF) name++;
            const sw_witness_table *base = NULL;
            if (name[0] == 0x07 || name[0] == 0x09) {
                int32_t off;
                memcpy(&off, name + 1, 4);
                assoc_conf_accessor fn = (assoc_conf_accessor)(name + 1 + off);
                base = fn(type, type, (const sw_witness_table *)table);
            }
            if (!base) dx_fatal("swift: base protocol #%u of a conformance of %s could not be resolved", i,
                                sw_type_name(type, 1));
            table[1 + i] = (void *)base;
        }

    pthread_mutex_lock(&lock);
    const sw_witness_table *again = sw_map_get(&tables, (uintptr_t)c, (uintptr_t)type, NULL);
    if (again) {
        free(mem);
        wt = again;
    } else {
        sw_map_put(&tables, (uintptr_t)c, (uintptr_t)type, table);
        wt = (const sw_witness_table *)table;
    }
    pthread_mutex_unlock(&lock);
    return wt;
}
DX_FN(swift_getWitnessTable);

/* ---- conformance lookup -------------------------------------------------------- */
static const sw_witness_table *try_conformance(const sw_conformance_descriptor *c, const sw_metadata *type) {
    struct conf_tail t;
    conf_tail(c, &t);
    const void **args = alloca((t.ncond + 1) * sizeof *args);
    unsigned nargs = 0;
    if (t.ncond) {
        struct sw_env e;
        sw_env_init(&e, (const sw_context_descriptor *)sw_type_descriptor(type), sw_generic_args(type));
        if (sw_check_requirements(t.cond, t.ncond, &e, args, &nargs)) return NULL;
    }
    return d_swift_getWitnessTable(c, type, args);
}

static struct conf *candidates(uintptr_t a, uintptr_t b) {
    pthread_mutex_lock(&lock);
    struct conf *r = sw_map_get(&by_type, a, b, NULL);
    pthread_mutex_unlock(&lock);
    return r;
}

static const sw_witness_table *try_list(struct conf *list, const char *name, const sw_metadata *type,
                                        const sw_protocol_descriptor *proto) {
    for (struct conf *e = list; e; e = e->next) {
        if (sw_rel_indirect(&e->c->protocol) != proto) continue;
        if (name && (!e->name || strcmp(e->name, name))) continue;
        const sw_witness_table *wt = try_conformance(e->c, type);
        if (wt) return wt;
    }
    return NULL;
}

static const sw_witness_table *find(const sw_metadata *type, const sw_protocol_descriptor *proto) {
    for (const sw_metadata *m = type; m;) {
        uintptr_t kind = sw_kind(m);
        const sw_type_context_descriptor *d = sw_type_descriptor(m);
        const sw_witness_table *wt = NULL;
        if (d) {
            if (sw_ctx_is_unique(d->flags)) {
                wt = try_list(candidates((uintptr_t)d, KEY_DESC), NULL, m, proto);
            } else {
                char name[512];
                sw_context_name((const sw_context_descriptor *)d, name, sizeof name);
                wt = try_list(candidates(sw_hash_bytes(name, strlen(name)), KEY_NAME), name, m, proto);
            }
            if (wt) return wt;
        }
        const void *cls = kind == SW_KIND_CLASS || kind == SW_KIND_OBJC_CLASS_WRAPPER ? sw_class_of_metadata(m)
                                                                                      : NULL;
        if (!cls) return NULL;
        if (!d) {
            /* An Objective-C class: conformances declared in Swift for it. */
            if ((wt = try_list(candidates((uintptr_t)cls, KEY_CLASS), NULL, m, proto))) return wt;
            const char *name = objc_class_name(cls);
            if (name && (wt = try_list(candidates(sw_hash_bytes(name, strlen(name)), KEY_NAME), name, m, proto)))
                return wt;
        }
        /* Subclasses inherit their superclasses' conformances. */
        m = (const sw_metadata *)((const sw_class_metadata *)cls)->superclass;
    }
    return NULL;
}

const sw_witness_table *sw_conforms_to(const sw_metadata *type, const sw_protocol_descriptor *proto) {
    if (!type || !proto) return NULL;
    /* `any Error` conforms to Error itself (Result<T, any Error>), through
     * the standard library's self-conformance witness table. */
    if (sw_kind(type) == SW_KIND_EXISTENTIAL &&
        ((((const sw_existential_metadata *)type)->flags >> 24) & 0x3F) == 1) {
        static const sw_protocol_descriptor *error_proto;
        static const sw_witness_table *error_self;
        if (!error_proto) error_proto = dx_global_lookup("_$ss5ErrorMp");
        if (!error_self) error_self = dx_global_lookup("_$ss5ErrorWS");
        if (proto == error_proto && error_self) return error_self;
    }
    pthread_once(&once, init_index);
    pthread_mutex_lock(&lock);
    int found;
    void *v = sw_map_get(&cache, (uintptr_t)type, (uintptr_t)proto, &found);
    uintptr_t gen = generation;
    pthread_mutex_unlock(&lock);
    if (found && !((uintptr_t)v & 1)) return v;
    if (found && (uintptr_t)v >> 1 == gen) return NULL;
    const sw_witness_table *wt = find(type, proto);
    pthread_mutex_lock(&lock);
    sw_map_put(&cache, (uintptr_t)type, (uintptr_t)proto, wt ? (void *)wt : (void *)(gen << 1 | 1));
    pthread_mutex_unlock(&lock);
    if (!wt && dx_verbose >= 2) {
        char pname[256];
        sw_context_name((const sw_context_descriptor *)proto, pname, sizeof pname);
        dx_log(2, "swift: %s does not conform to %s", sw_type_name(type, 1), pname);
    }
    return wt;
}

static const sw_witness_table *d_swift_conformsToProtocol(const sw_metadata *type,
                                                          const sw_protocol_descriptor *proto) {
    return sw_conforms_to(type, proto);
}
DX_FN(swift_conformsToProtocol);
/* Same contract; the newer names exist so that newer compilers can tell
 * runtimes apart (noncopyable types, back deployment). */
DX_EXPORT("_swift_conformsToProtocol2", d_swift_conformsToProtocol);
DX_EXPORT("_swift_conformsToProtocolCommon", d_swift_conformsToProtocol);

/* ---- associated types and conformances ---------------------------------------- */
/* The level of `type`'s class hierarchy that the conformance is about: a
 * subclass uses its superclass's witness table, whose associated types are
 * written in terms of the superclass's generic arguments. */
static const sw_metadata *conforming_level(const sw_metadata *type, const sw_witness_table *wt) {
    const sw_conformance_descriptor *c = wt->description;
    unsigned kind = (c->flags & SW_CONF_TYPE_REF_KIND_MASK) >> SW_CONF_TYPE_REF_KIND_SHIFT;
    if (kind > 1 || sw_kind(type) != SW_KIND_CLASS) return type;
    const void *ref = sw_rel(&c->type_ref);
    const sw_type_context_descriptor *d = kind ? *(const void *const *)ref : ref;
    for (const sw_metadata *m = type; m; m = (const sw_metadata *)((const sw_class_metadata *)m)->superclass) {
        if (sw_type_descriptor(m) == d) return m;
        if (sw_kind(m) != SW_KIND_CLASS) break;
    }
    return type;
}

const sw_metadata *sw_get_assoc_type_witness(const sw_witness_table *wt, const sw_metadata *type,
                                             const sw_protocol_requirement *req_base,
                                             const sw_protocol_requirement *req) {
    size_t slot = req - req_base;
    uintptr_t v = (uintptr_t)((const void *const *)wt)[slot];
    if (!(v & 1)) return (const sw_metadata *)v;
    pthread_mutex_lock(&lock);
    const sw_metadata *m = sw_map_get(&resolved, (uintptr_t)wt, slot, NULL);
    pthread_mutex_unlock(&lock);
    if (m) return m;
    const char *name = (const char *)(v & ~(uintptr_t)1);
    struct sw_env e;
    const sw_metadata *level = conforming_level(type, wt);
    if ((unsigned char)name[0] == 0xFF) {
        /* Written in the protocol's terms: Self is the conforming type. */
        sw_env_init(&e, NULL, NULL);
        e.self = level;
        e.self_wt = wt;
    } else {
        /* Written in the conforming type's terms. */
        sw_env_init(&e, (const sw_context_descriptor *)sw_type_descriptor(level), sw_generic_args(level));
    }
    m = sw_type_in_env(name, sw_mangled_name_length(name), &e);
    if (!m) {
        dx_log(1, "swift: associated type witness #%zu of %s could not be resolved", slot,
               sw_type_name(type, 1));
        return NULL;
    }
    pthread_mutex_lock(&lock);
    sw_map_put(&resolved, (uintptr_t)wt, slot, (void *)m);
    pthread_mutex_unlock(&lock);
    return m;
}

static sw_response d_swift_getAssociatedTypeWitness(sw_request req, const sw_witness_table *wt,
                                                    const sw_metadata *type,
                                                    const sw_protocol_requirement *req_base,
                                                    const sw_protocol_requirement *assoc) {
    sw_response r = {sw_get_assoc_type_witness(wt, type, req_base, assoc), SW_STATE_COMPLETE};
    return r;
}
DX_FN(swift_getAssociatedTypeWitness);


static const sw_witness_table *d_swift_getAssociatedConformanceWitness(
    const sw_witness_table *wt, const sw_metadata *type, const sw_metadata *assoc_type,
    const sw_protocol_requirement *req_base, const sw_protocol_requirement *assoc) {
    size_t slot = assoc - req_base;
    uintptr_t v = (uintptr_t)((const void *const *)wt)[slot];
    if (!(v & 1)) return (const sw_witness_table *)v;
    pthread_mutex_lock(&lock);
    const sw_witness_table *r = sw_map_get(&resolved, (uintptr_t)wt, slot, NULL);
    pthread_mutex_unlock(&lock);
    if (r) return r;
    const unsigned char *name = (const unsigned char *)(v & ~(uintptr_t)1);
    if (name[0] == 0xFF) name++;
    /* The compiler emits a symbolic reference to an accessor that computes
     * the conformance: \x07 followed by a relative offset. */
    if (name[0] == 0x07 || name[0] == 0x09) {
        int32_t off;
        memcpy(&off, name + 1, 4);
        assoc_conf_accessor fn = (assoc_conf_accessor)(name + 1 + off);
        r = fn(assoc_type, type, wt);
    }
    if (!r) {
        dx_log(1, "swift: associated conformance #%zu of %s could not be resolved", slot,
               sw_type_name(type, 1));
        return NULL;
    }
    pthread_mutex_lock(&lock);
    sw_map_put(&resolved, (uintptr_t)wt, slot, (void *)r);
    pthread_mutex_unlock(&lock);
    return r;
}
DX_FN(swift_getAssociatedConformanceWitness);
