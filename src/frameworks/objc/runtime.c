/* Objective-C runtime: selectors, class realisation, method lookup and
 * caching, categories, protocols, +load/+initialize, and the runtime API.
 * Written against the documented modern Objective-C ABI. */
#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>

#include "objc_internal.h"

pthread_mutex_t dx_objc_lock;
static pthread_cond_t init_cond = PTHREAD_COND_INITIALIZER;

/* ---- selectors ---------------------------------------------------------- */

static const char **sel_table;
static size_t sel_cap, sel_count;
static pthread_mutex_t sel_lock = PTHREAD_MUTEX_INITIALIZER;

static uint64_t str_hash(const char *s) {
    uint64_t h = 1469598103934665603ULL;
    for (; *s; s++) h = (h ^ (uint8_t)*s) * 1099511628211ULL;
    return h;
}

/* Returns the canonical pointer for a selector name. `name` itself becomes
 * canonical when `adopt` is set and the name is new (it must then live for
 * the life of the process and be 16-byte... any alignment; the dispatch
 * hash only needs distinct pointers). */
static SEL sel_intern_impl(const char *name, int adopt) {
    if (!name) return NULL;
    pthread_mutex_lock(&sel_lock);
    if (sel_count * 2 >= sel_cap) {
        size_t ncap = sel_cap ? sel_cap * 2 : 4096;
        const char **nt = calloc(ncap, sizeof *nt);
        for (size_t i = 0; i < sel_cap; i++) {
            if (!sel_table[i]) continue;
            size_t j = str_hash(sel_table[i]) & (ncap - 1);
            while (nt[j]) j = (j + 1) & (ncap - 1);
            nt[j] = sel_table[i];
        }
        free(sel_table);
        sel_table = nt;
        sel_cap = ncap;
    }
    size_t i = str_hash(name) & (sel_cap - 1);
    while (sel_table[i]) {
        if (!strcmp(sel_table[i], name)) {
            SEL r = sel_table[i];
            pthread_mutex_unlock(&sel_lock);
            return r;
        }
        i = (i + 1) & (sel_cap - 1);
    }
    const char *canon;
    if (adopt) canon = name;
    else {
        /* 16-byte aligned so the cache hash (pointer >> 4) spreads well */
        size_t n = strlen(name) + 1;
        char *copy = aligned_alloc(16, (n + 15) & ~(size_t)15);
        memcpy(copy, name, n);
        canon = copy;
    }
    sel_table[i] = canon;
    sel_count++;
    pthread_mutex_unlock(&sel_lock);
    return canon;
}

SEL sel_intern(const char *name) { return sel_intern_impl(name, 0); }
dx_sel dx_sel_register(const char *name) { return sel_intern(name); }

SEL SEL_retain, SEL_release, SEL_autorelease, SEL_dealloc, SEL_alloc, SEL_init, SEL_new, SEL_class,
    SEL_copyWithZone, SEL_mutableCopyWithZone, SEL_initialize, SEL_load, SEL_cxx_destruct,
    SEL_cxx_construct, SEL_resolveInstanceMethod, SEL_resolveClassMethod,
    SEL_forwardingTargetForSelector, SEL_respondsToSelector, SEL_isKindOfClass, SEL_self,
    SEL_allocWithZone, SEL_retainCount, SEL_copy, SEL_allowsWeakReference, SEL_retainWeakReference;

/* ---- class table -------------------------------------------------------- */

struct named_class {
    const char *name;
    Class cls;
};
static struct named_class *class_table;
static size_t class_cap, class_count;
static Class realized_list;

static void class_table_put(const char *name, Class cls) {
    if (class_count * 2 >= class_cap) {
        size_t ncap = class_cap ? class_cap * 2 : 1024;
        struct named_class *nt = calloc(ncap, sizeof *nt);
        for (size_t i = 0; i < class_cap; i++) {
            if (!class_table[i].name) continue;
            size_t j = str_hash(class_table[i].name) & (ncap - 1);
            while (nt[j].name) j = (j + 1) & (ncap - 1);
            nt[j] = class_table[i];
        }
        free(class_table);
        class_table = nt;
        class_cap = ncap;
    }
    size_t i = str_hash(name) & (class_cap - 1);
    while (class_table[i].name) {
        if (!strcmp(class_table[i].name, name)) {
            if (class_table[i].cls != cls)
                dx_log(1, "objc: class %s is defined more than once; using the first", name);
            return;
        }
        i = (i + 1) & (class_cap - 1);
    }
    class_table[i].name = name;
    class_table[i].cls = cls;
    class_count++;
}

static Class class_table_get(const char *name) {
    if (!class_cap) return NULL;
    size_t i = str_hash(name) & (class_cap - 1);
    while (class_table[i].name) {
        if (!strcmp(class_table[i].name, name)) return class_table[i].cls;
        i = (i + 1) & (class_cap - 1);
    }
    return NULL;
}

/* ---- method caches ------------------------------------------------------ */

static struct {
    struct cache c;
    struct cache_entry e[2];
} empty_cache_storage = {{0, 0}, {{0, 0}, {(SEL)1, (IMP)&empty_cache_storage}}};
#define EMPTY_CACHE (&empty_cache_storage.c)
DX_EXPORT("__objc_empty_cache", &empty_cache_storage);
static void *empty_vtable[2];
DX_EXPORT("__objc_empty_vtable", empty_vtable);

static struct cache *cache_new(size_t slots) {
    struct cache *c = calloc(1, sizeof *c + (slots + 1) * sizeof(struct cache_entry));
    c->mask = slots - 1;
    c->e[slots].sel = (SEL)1;
    c->e[slots].imp = (IMP)c;
    return c;
}

/* lock held */
static void cache_fill(Class cls, SEL sel, IMP imp) {
    struct cache *c = cls->cache;
    if (!c || c == EMPTY_CACHE || c->mask == 0 || (c->count + 1) * 4 > (c->mask + 1) * 3) {
        size_t slots = (!c || c == EMPTY_CACHE || c->mask == 0) ? 8 : (c->mask + 1) * 2;
        /* the old table may still be read by another thread: never freed */
        c = cache_new(slots);
        __atomic_store_n(&cls->cache, c, __ATOMIC_RELEASE);
    }
    size_t i = ((uintptr_t)sel >> 4) & c->mask;
    while (c->e[i].sel) {
        if (c->e[i].sel == sel) return;
        i = (i + 1) & c->mask;
    }
    c->e[i].imp = imp;
    __atomic_store_n(&c->e[i].sel, sel, __ATOMIC_RELEASE);
    c->count++;
}

void flush_caches(void) {
    pthread_mutex_lock(&dx_objc_lock);
    for (Class c = realized_list; c; c = RW(c)->next_realized) {
        __atomic_store_n(&c->cache, EMPTY_CACHE, __ATOMIC_RELEASE);
        RW(c)->rr_state = 0;
    }
    pthread_mutex_unlock(&dx_objc_lock);
}

/* ---- method lists ------------------------------------------------------- */

static struct mlist *convert_methods(void *raw) {
    struct method_list_hdr *h = raw;
    if (!h || !h->count) return NULL;
    struct mlist *l = malloc(sizeof *l + h->count * sizeof(struct method));
    l->next = NULL;
    l->count = (int)h->count;
    uint32_t entsize = h->entsize_flags & 0xfffc;
    uint8_t *p = (uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->count; i++, p += entsize) {
        struct method *m = &l->m[i];
        if (h->entsize_flags & METHOD_LIST_SMALL) {
            struct small_method *s = (void *)p;
            const char *nameref = (const char *)&s->name + s->name;
            if (h->entsize_flags & METHOD_LIST_DIRECT_SEL) m->name = sel_intern_impl(nameref, 1);
            else m->name = sel_intern_impl(*(const char **)nameref, 1);
            m->types = (const char *)&s->types + s->types;
            m->imp = s->imp ? (IMP)((uintptr_t)&s->imp + s->imp) : NULL;
        } else {
            struct big_method *b = (void *)p;
            m->name = sel_intern_impl(b->name, 1);
            m->types = b->types;
            m->imp = (IMP)b->imp;
        }
    }
    return l;
}

static struct method *find_in_class(Class cls, SEL sel) {
    for (struct mlist *l = RW(cls)->methods; l; l = l->next)
        for (int i = 0; i < l->count; i++)
            if (l->m[i].name == sel) return &l->m[i];
    return NULL;
}

static struct method *find_method(Class cls, SEL sel) {
    for (Class c = cls; c; c = c->superclass) {
        if (!class_realized(c)) realize_class(c);
        struct method *m = find_in_class(c, sel);
        if (m) return m;
    }
    return NULL;
}

IMP class_lookup_imp(Class cls, SEL sel) {
    pthread_mutex_lock(&dx_objc_lock);
    if (!class_realized(cls)) realize_class(cls);
    struct method *m = find_method(cls, sel);
    pthread_mutex_unlock(&dx_objc_lock);
    return m ? m->imp : NULL;
}

/* ---- categories ---------------------------------------------------------- */

struct pending_category {
    struct pending_category *next;
    struct category *cat;
};
static struct pending_category *pending_categories;

static void rw_add_protocols(struct class_rw *rw, struct protocol_list *pl) {
    if (!pl) return;
    rw->protocols = realloc(rw->protocols, (rw->nprotocols + pl->count) * sizeof *rw->protocols);
    for (uintptr_t i = 0; i < pl->count; i++) rw->protocols[rw->nprotocols++] = pl->list[i];
}
static void rw_add_properties(struct class_rw *rw, struct property_list *pl) {
    if (!pl) return;
    rw->properties = realloc(rw->properties, (rw->nproperties + 1) * sizeof *rw->properties);
    rw->properties[rw->nproperties++] = pl;
}

/* lock held; cls is realized */
static void attach_category(Class cls, struct category *cat) {
    struct mlist *im = convert_methods(cat->instance_methods);
    if (im) {
        im->next = RW(cls)->methods;
        RW(cls)->methods = im;
    }
    struct mlist *cm = convert_methods(cat->class_methods);
    if (cm) {
        if (!class_realized(cls->isa)) realize_class(cls->isa);
        cm->next = RW(cls->isa)->methods;
        RW(cls->isa)->methods = cm;
    }
    rw_add_protocols(RW(cls), cat->protocols);
    rw_add_properties(RW(cls), cat->instance_properties);
}

/* ---- realisation --------------------------------------------------------- */

static struct class_rw *rw_new(const struct class_ro *ro) {
    struct class_rw *rw = aligned_alloc(16, (sizeof *rw + 15) & ~(size_t)15);
    memset(rw, 0, sizeof *rw);
    rw->flags = RW_REALIZED | ((ro->flags & RO_META) ? RW_META : 0);
    rw->instance_size = ro->instance_size;
    rw->ro = ro;
    return rw;
}

/* lock held */
void realize_class(Class cls) {
    if (!cls || class_realized(cls)) return;
    const struct class_ro *ro = (const struct class_ro *)(cls->bits & CLASS_DATA_MASK);
    if (!ro) dx_fatal("objc: class at %p has no metadata", (void *)cls);
    struct class_rw *rw = rw_new(ro);
    cls->bits = (cls->bits & ~CLASS_DATA_MASK) | (uintptr_t)rw;
    if (!cls->cache) cls->cache = EMPTY_CACHE;
    rw->next_realized = realized_list;
    realized_list = cls;

    if (cls->superclass) realize_class(cls->superclass);
    if (cls->isa && cls->isa != cls) realize_class(cls->isa);

    if (!(ro->flags & RO_META)) {
        /* Non-fragile instance variables: if the superclass grew past where
         * this class expected to start, slide this class's ivars up. */
        if (cls->superclass) {
            uint32_t super_size = RW(cls->superclass)->instance_size;
            if (ro->instance_start < super_size) {
                uint32_t align = 8;
                if (ro->ivars)
                    for (uint32_t i = 0; i < ro->ivars->count; i++) {
                        struct ivar *iv = (struct ivar *)((char *)&ro->ivars->first + i * ro->ivars->entsize);
                        uint32_t a = iv->alignment_raw == ~0u ? 8 : 1u << iv->alignment_raw;
                        if (a > align) align = a;
                    }
                uint32_t diff = (super_size - ro->instance_start + align - 1) & ~(align - 1);
                if (ro->ivars)
                    for (uint32_t i = 0; i < ro->ivars->count; i++) {
                        struct ivar *iv = (struct ivar *)((char *)&ro->ivars->first + i * ro->ivars->entsize);
                        if (iv->offset) *iv->offset += (int32_t)diff;
                    }
                rw->instance_size = ro->instance_size + diff;
            }
        }
        if (cls->isa && cls->isa != cls) RW(cls->isa)->nonmeta = cls;
        if (ro->name) class_table_put(ro->name, cls);
    } else if (cls->isa == cls) {
        /* root metaclass */
    }

    rw->methods = convert_methods(ro->base_methods);
    rw_add_protocols(rw, ro->base_protocols);
    rw_add_properties(rw, ro->base_properties);

    if (!(ro->flags & RO_META)) {
        for (struct pending_category **pp = &pending_categories; *pp;) {
            struct pending_category *pc = *pp;
            if (pc->cat->cls == cls) {
                attach_category(cls, pc->cat);
                *pp = pc->next;
                free(pc);
            } else pp = &pc->next;
        }
    }
}

const char *class_name(Class cls) {
    if (!cls) return "nil";
    if (!class_realized(cls)) {
        const struct class_ro *ro = (const struct class_ro *)(cls->bits & CLASS_DATA_MASK);
        return ro && ro->name ? ro->name : "?";
    }
    return RW(cls)->ro->name ? RW(cls)->ro->name : "?";
}

Class objc_class_of(id obj) {
    if (!obj) return NULL;
    if ((uintptr_t)obj & 1) {
        const char *missing = dx_stub_value_name((uintptr_t)obj);
        if (missing) dx_fatal("objc: object constant %s is not implemented in bitten yet", missing);
        dx_fatal("objc: tagged pointer %p used; tagged objects are not supported", (void *)obj);
    }
    return obj->isa;
}

/* ---- +initialize --------------------------------------------------------- */

void ensure_initialized(Class cls) {
    if (!cls) return;
    if (RW(cls)->flags & RW_PLACEHOLDER) return; /* nothing to initialize; real messages report */
    if (__atomic_load_n(&RW(cls)->flags, __ATOMIC_ACQUIRE) & RW_INITIALIZED) return;
    if (cls->superclass) ensure_initialized(cls->superclass);
    pthread_mutex_lock(&dx_objc_lock);
    struct class_rw *rw = RW(cls);
    for (;;) {
        if (rw->flags & RW_INITIALIZED) {
            pthread_mutex_unlock(&dx_objc_lock);
            return;
        }
        if (!(rw->flags & RW_INITIALIZING)) break;
        if (pthread_equal(rw->init_thread, pthread_self())) {
            pthread_mutex_unlock(&dx_objc_lock);
            return; /* message sent from inside +initialize */
        }
        pthread_cond_wait(&init_cond, &dx_objc_lock);
    }
    rw->flags |= RW_INITIALIZING;
    rw->init_thread = pthread_self();
    pthread_mutex_unlock(&dx_objc_lock);

    MSG(void, id, SEL)((id)cls, SEL_initialize);

    pthread_mutex_lock(&dx_objc_lock);
    __atomic_store_n(&rw->flags, (rw->flags | RW_INITIALIZED) & ~RW_INITIALIZING, __ATOMIC_RELEASE);
    pthread_cond_broadcast(&init_cond);
    pthread_mutex_unlock(&dx_objc_lock);
}

/* ---- slow-path lookup (called from msgsend.S) ---------------------------- */

static void unrecognized(id self, SEL sel) {
    Class cls = objc_class_of(self);
    int meta = class_realized(cls) && class_is_meta(cls);
    Class named = meta ? (Class)self : cls;
    if (class_realized(named) && (RW(named)->flags & RW_PLACEHOLDER))
        dx_fatal("objc: %c[%s %s]: class %s is not implemented in bitten yet", meta ? '+' : '-',
                 class_name(named), sel, class_name(named));
    dx_fatal("objc: %c[%s %s]: unrecognized selector sent to %s %p\n"
             "  (full message forwarding through NSInvocation is not implemented)",
             meta ? '+' : '-', class_name(meta ? (Class)self : cls), sel, meta ? "class" : "instance",
             (void *)self);
}
static void unrecognized_stret(void *out, id self, SEL sel) {
    (void)out;
    unrecognized(self, sel);
}

IMP dx_objc_lookup(id *receiver_slot, SEL sel, Class cls, int stret) {
    id receiver = *receiver_slot;
    if ((uintptr_t)receiver & 1) {
        const char *missing = dx_stub_value_name((uintptr_t)receiver);
        if (missing) dx_fatal("objc: message %s sent to object constant %s, which is not implemented in bitten yet", sel, missing);
        dx_fatal("objc: message %s sent to tagged pointer %p; tagged objects are not supported", sel,
                 (void *)receiver);
    }
    pthread_mutex_lock(&dx_objc_lock);
    if (!class_realized(cls)) realize_class(cls);
    Class inst = cls;
    if (class_is_meta(cls)) {
        /* the receiver is a class object */
        inst = (Class)receiver;
        if (!class_realized(inst)) realize_class(inst);
    }
    pthread_mutex_unlock(&dx_objc_lock);
    ensure_initialized(inst);

    for (int attempt = 0; attempt < 2; attempt++) {
        pthread_mutex_lock(&dx_objc_lock);
        struct method *m = find_method(cls, sel);
        if (m && m->imp) {
            if (RW(inst)->flags & RW_INITIALIZED) cache_fill(cls, sel, m->imp);
            IMP imp = m->imp;
            pthread_mutex_unlock(&dx_objc_lock);
            return imp;
        }
        /* dynamic method resolution, once */
        SEL rsel = class_is_meta(cls) ? SEL_resolveClassMethod : SEL_resolveInstanceMethod;
        struct method *res = attempt == 0 ? find_method(inst->isa, rsel) : NULL;
        pthread_mutex_unlock(&dx_objc_lock);
        if (!res || !res->imp) break;
        if (!((char (*)(id, SEL, SEL))res->imp)((id)inst, rsel, sel)) break;
    }

    if (sel != SEL_forwardingTargetForSelector) {
        IMP fwd = class_lookup_imp(cls, SEL_forwardingTargetForSelector);
        if (fwd) {
            id target = ((id (*)(id, SEL, SEL))fwd)(receiver, SEL_forwardingTargetForSelector, sel);
            if (target && target != receiver) {
                *receiver_slot = target;
                return dx_objc_lookup(receiver_slot, sel, objc_class_of(target), stret);
            }
        }
    }
    return stret ? (IMP)unrecognized_stret : (IMP)unrecognized;
}

/* ---- image loading (called by the loader) -------------------------------- */

struct dx_image;
void *dx_image_section(const struct dx_image *img, const char *sect, size_t *size);

struct pending_load {
    struct pending_load *next;
    Class cls;            /* class +load */
    struct category *cat; /* or category +load */
};
static struct pending_load *load_head, **load_tail = &load_head;
static struct protocol **protocol_table;
static size_t protocol_count, protocol_cap;
static struct objc_class protocol_class, protocol_meta;

static struct protocol *protocol_canonical(struct protocol *p) {
    for (size_t i = 0; i < protocol_count; i++)
        if (!strcmp(protocol_table[i]->name, p->name)) return protocol_table[i];
    if (protocol_count == protocol_cap) {
        protocol_cap = protocol_cap ? protocol_cap * 2 : 64;
        protocol_table = realloc(protocol_table, protocol_cap * sizeof *protocol_table);
    }
    protocol_table[protocol_count++] = p;
    return p;
}

/* Called for each image after its fixups and before its pages are made
 * read-only. */
void dx_objc_image_fixups(const struct dx_image *img) {
    size_t n;
    const char **selrefs = dx_image_section(img, "__objc_selrefs", &n);
    if (!selrefs && !dx_image_section(img, "__objc_classlist", &n) &&
        !dx_image_section(img, "__objc_catlist", &n) && !dx_image_section(img, "__objc_protolist", &n))
        return;
    pthread_mutex_lock(&dx_objc_lock);
    selrefs = dx_image_section(img, "__objc_selrefs", &n);
    for (size_t i = 0; selrefs && i < n / sizeof(void *); i++)
        selrefs[i] = sel_intern_impl(selrefs[i], 1);

    struct protocol **protos = dx_image_section(img, "__objc_protolist", &n);
    for (size_t i = 0; protos && i < n / sizeof(void *); i++) {
        if (!protos[i]) continue;
        struct protocol *canon = protocol_canonical(protos[i]);
        canon->isa = &protocol_class;
    }
    struct protocol **protorefs = dx_image_section(img, "__objc_protorefs", &n);
    for (size_t i = 0; protorefs && i < n / sizeof(void *); i++)
        if (protorefs[i]) protorefs[i] = protocol_canonical(protorefs[i]);

    /* Classes are realised lazily, but they must be findable by name. */
    Class *classes = dx_image_section(img, "__objc_classlist", &n);
    for (size_t i = 0; classes && i < n / sizeof(void *); i++) {
        Class c = classes[i];
        if (!c || class_realized(c)) continue;
        const struct class_ro *ro = (const struct class_ro *)(c->bits & CLASS_DATA_MASK);
        if (ro && ro->name) class_table_put(ro->name, c);
    }

    struct category **cats = dx_image_section(img, "__objc_catlist", &n);
    for (size_t i = 0; cats && i < n / sizeof(void *); i++) {
        struct category *cat = cats[i];
        if (!cat || !cat->cls) continue; /* category on a missing weak class */
        if (class_realized(cat->cls)) {
            attach_category(cat->cls, cat);
        } else {
            struct pending_category *pc = malloc(sizeof *pc);
            pc->cat = cat;
            pc->next = pending_categories;
            pending_categories = pc;
        }
    }

    Class *nl = dx_image_section(img, "__objc_nlclslist", &n);
    for (size_t i = 0; nl && i < n / sizeof(void *); i++) {
        struct pending_load *pl = calloc(1, sizeof *pl);
        pl->cls = nl[i];
        *load_tail = pl;
        load_tail = &pl->next;
    }
    struct category **nlc = dx_image_section(img, "__objc_nlcatlist", &n);
    for (size_t i = 0; nlc && i < n / sizeof(void *); i++) {
        struct pending_load *pl = calloc(1, sizeof *pl);
        pl->cat = nlc[i];
        *load_tail = pl;
        load_tail = &pl->next;
    }
    pthread_mutex_unlock(&dx_objc_lock);
    flush_caches();
}

struct loaded_class {
    struct loaded_class *next;
    Class cls;
};
static struct loaded_class *loaded_classes;

static int load_was_called(Class cls) {
    for (struct loaded_class *l = loaded_classes; l; l = l->next)
        if (l->cls == cls) return 1;
    return 0;
}

static void call_class_load(Class cls) {
    if (!cls || load_was_called(cls)) return;
    pthread_mutex_lock(&dx_objc_lock);
    if (!class_realized(cls)) realize_class(cls);
    struct loaded_class *l = malloc(sizeof *l);
    l->cls = cls;
    l->next = loaded_classes;
    loaded_classes = l;
    pthread_mutex_unlock(&dx_objc_lock);
    call_class_load(cls->superclass);
    /* +load is not inherited: only the class's own base method list counts */
    struct mlist *own = convert_methods(RW(cls->isa)->ro->base_methods);
    for (int i = 0; own && i < own->count; i++)
        if (own->m[i].name == SEL_load && own->m[i].imp)
            ((void (*)(id, SEL))own->m[i].imp)((id)cls, SEL_load);
    free(own);
}

/* Called once all newly mapped images are bound, before their initialisers. */
void dx_objc_images_ready(void) {
    for (;;) {
        pthread_mutex_lock(&dx_objc_lock);
        struct pending_load *pl = load_head;
        /* classes first, then categories */
        struct pending_load **pp = &load_head;
        while (*pp && !(*pp)->cls) pp = &(*pp)->next;
        if (*pp) pl = *pp;
        else pp = &load_head;
        if (!pl) {
            load_tail = &load_head;
            pthread_mutex_unlock(&dx_objc_lock);
            return;
        }
        *pp = pl->next;
        if (!load_head) load_tail = &load_head;
        else if (load_tail == &pl->next) {
            load_tail = &load_head;
            while (*load_tail) load_tail = &(*load_tail)->next;
        }
        pthread_mutex_unlock(&dx_objc_lock);
        if (pl->cls) call_class_load(pl->cls);
        else if (pl->cat && pl->cat->cls) {
            call_class_load(pl->cat->cls);
            struct mlist *cm = convert_methods(pl->cat->class_methods);
            for (int i = 0; cm && i < cm->count; i++)
                if (cm->m[i].name == SEL_load && cm->m[i].imp)
                    ((void (*)(id, SEL))cm->m[i].imp)((id)pl->cat->cls, SEL_load);
            free(cm);
        }
        free(pl);
    }
}

/* ---- creating classes at run time ----------------------------------------- */

struct dyn_ivar {
    struct ivar iv;
    int32_t offset;
};

/* Build a class pair in the given storage (or freshly allocated storage). */
Class make_class(Class storage, Class meta_storage, Class super, const char *name, size_t extra) {
    pthread_mutex_lock(&dx_objc_lock);
    if (super && !class_realized(super)) realize_class(super);
    Class cls = storage ? storage : calloc(1, sizeof *cls + extra);
    Class meta = meta_storage ? meta_storage : calloc(1, sizeof *meta + extra);
    struct class_ro *ro = calloc(1, sizeof *ro), *mro = calloc(1, sizeof *mro);
    char *nm = strdup(name);
    ro->name = mro->name = nm;
    ro->flags = super ? 0 : RO_ROOT;
    mro->flags = RO_META | (super ? 0 : RO_ROOT);
    ro->instance_start = ro->instance_size = super ? RW(super)->instance_size : (uint32_t)sizeof(void *);
    mro->instance_start = mro->instance_size = sizeof(struct objc_class);

    Class root_meta = super ? super->isa->isa : meta;
    cls->isa = meta;
    cls->superclass = super;
    meta->isa = root_meta;
    meta->superclass = super ? super->isa : cls;
    cls->cache = meta->cache = EMPTY_CACHE;
    struct class_rw *rw = rw_new(ro), *mrw = rw_new(mro);
    rw->flags |= RW_DYNAMIC;
    mrw->flags |= RW_DYNAMIC;
    mrw->nonmeta = cls;
    cls->bits = (uintptr_t)rw;
    meta->bits = (uintptr_t)mrw;
    rw->next_realized = realized_list;
    mrw->next_realized = cls;
    realized_list = meta;
    pthread_mutex_unlock(&dx_objc_lock);
    return cls;
}

/* A class a program imports but bitten does not provide: an empty root
 * class with the right name, so that loading succeeds and the first message
 * to it fails with a clear report instead of jumping into a stub. */
void *dx_objc_placeholder_class(const char *name, int want_meta) {
    Class c = class_table_get(name);
    if (!c) {
        c = make_class(NULL, NULL, NULL, name, 0);
        RW(c)->flags |= RW_PLACEHOLDER;
        RW(c->isa)->flags |= RW_PLACEHOLDER;
        pthread_mutex_lock(&dx_objc_lock);
        class_table_put(name, c);
        pthread_mutex_unlock(&dx_objc_lock);
    }
    return want_meta ? (void *)c->isa : (void *)c;
}

static void register_class(Class cls) {
    pthread_mutex_lock(&dx_objc_lock);
    RW(cls)->flags |= RW_REGISTERED;
    class_table_put(RW(cls)->ro->name, cls);
    pthread_mutex_unlock(&dx_objc_lock);
}

void add_method(Class cls, const char *sel, IMP imp, const char *types) {
    struct mlist *l = malloc(sizeof *l + sizeof(struct method));
    l->count = 1;
    l->m[0].name = sel_intern(sel);
    l->m[0].types = types ? types : "";
    l->m[0].imp = imp;
    pthread_mutex_lock(&dx_objc_lock);
    if (!class_realized(cls)) realize_class(cls);
    l->next = RW(cls)->methods;
    RW(cls)->methods = l;
    pthread_mutex_unlock(&dx_objc_lock);
}

id class_create_instance(Class cls, size_t extra) {
    if (!cls) return NULL;
    if (!class_realized(cls)) {
        pthread_mutex_lock(&dx_objc_lock);
        realize_class(cls);
        pthread_mutex_unlock(&dx_objc_lock);
    }
    size_t size = RW(cls)->instance_size + extra;
    if (size < 16) size = 16;
    id obj = calloc(1, size);
    if (!obj) return NULL;
    obj->isa = cls;
    /* C++ instance variables: constructors run from the root class down */
    Class chain[64];
    int n = 0;
    for (Class c = cls; c && n < 64; c = c->superclass) chain[n++] = c;
    for (int i = n - 1; i >= 0; i--) {
        pthread_mutex_lock(&dx_objc_lock);
        struct method *m = find_in_class(chain[i], SEL_cxx_construct);
        pthread_mutex_unlock(&dx_objc_lock);
        if (m && m->imp) ((id (*)(id, SEL))m->imp)(obj, SEL_cxx_construct);
    }
    return obj;
}

/* ---- public runtime API ---------------------------------------------------- */

static SEL d_sel_registerName(const char *name) { return sel_intern(name); }
DX_FN(sel_registerName);
DX_EXPORT("_sel_getUid", d_sel_registerName);
static const char *d_sel_getName(SEL sel) { return sel ? sel : "<null selector>"; }
DX_FN(sel_getName);
static char d_sel_isEqual(SEL a, SEL b) { return a == b; }
DX_FN(sel_isEqual);
static char d_sel_isMapped(SEL s) { return s != NULL; }
DX_FN(sel_isMapped);

dx_class dx_objc_lookup_class(const char *name) {
    if (!name) return NULL;
    pthread_mutex_lock(&dx_objc_lock);
    Class c = class_table_get(name);
    if (c && !class_realized(c)) realize_class(c);
    pthread_mutex_unlock(&dx_objc_lock);
    return (dx_class)c;
}
static Class d_objc_getClass(const char *name) {
    Class c = (Class)dx_objc_lookup_class(name);
    if (!c) dx_log(2, "objc_getClass(%s): no such class", name ? name : "(null)");
    return c;
}
DX_FN(objc_getClass);
DX_EXPORT("_objc_lookUpClass", d_objc_getClass);
static Class d_objc_getRequiredClass(const char *name) {
    Class c = d_objc_getClass(name);
    if (!c) dx_fatal("objc_getRequiredClass: class %s not found", name);
    return c;
}
DX_FN(objc_getRequiredClass);
static Class d_objc_getMetaClass(const char *name) {
    Class c = d_objc_getClass(name);
    return c ? c->isa : NULL;
}
DX_FN(objc_getMetaClass);

static Class d_object_getClass(id obj) { return obj ? objc_class_of(obj) : NULL; }
DX_FN(object_getClass);
static Class d_object_setClass(id obj, Class cls) {
    if (!obj) return NULL;
    Class old = obj->isa;
    obj->isa = cls;
    return old;
}
DX_FN(object_setClass);
static const char *d_object_getClassName(id obj) { return obj ? class_name(objc_class_of(obj)) : "nil"; }
DX_FN(object_getClassName);
static char d_object_isClass(id obj) {
    if (!obj) return 0;
    Class c = objc_class_of(obj);
    return class_realized(c) && class_is_meta(c);
}
DX_FN(object_isClass);

#define REALIZED(cls)                                  \
    do {                                               \
        if ((cls) && !class_realized(cls)) {           \
            pthread_mutex_lock(&dx_objc_lock);         \
            realize_class(cls);                        \
            pthread_mutex_unlock(&dx_objc_lock);       \
        }                                              \
    } while (0)

static const char *d_class_getName(Class cls) { return cls ? class_name(cls) : "nil"; }
DX_FN(class_getName);
static Class d_class_getSuperclass(Class cls) { return cls ? cls->superclass : NULL; }
DX_FN(class_getSuperclass);
/* Re-parents a class and its metaclass (deprecated, still exported).
 * Toll-free bridging uses it to put a CF type's class under its public
 * class once that class is loaded (CTFont under NSFont). */
static Class d_class_setSuperclass(Class cls, Class super) {
    if (!cls || !super) return NULL;
    pthread_mutex_lock(&dx_objc_lock);
    realize_class(cls);
    realize_class(super);
    Class old = cls->superclass;
    cls->superclass = super;
    if (cls->isa && super->isa) cls->isa->superclass = super->isa;
    pthread_mutex_unlock(&dx_objc_lock);
    flush_caches();
    return old;
}
DX_FN(class_setSuperclass);
static char d_class_isMetaClass(Class cls) {
    if (!cls) return 0;
    REALIZED(cls);
    return class_is_meta(cls);
}
DX_FN(class_isMetaClass);
static size_t d_class_getInstanceSize(Class cls) {
    if (!cls) return 0;
    REALIZED(cls);
    return (RW(cls)->instance_size + 7) & ~(size_t)7;
}
DX_FN(class_getInstanceSize);
static int d_class_getVersion(Class cls) { (void)cls; return 0; }
DX_FN(class_getVersion);
static void d_class_setVersion(Class cls, int v) { (void)cls; (void)v; }
DX_FN(class_setVersion);

static Method d_class_getInstanceMethod(Class cls, SEL sel) {
    if (!cls || !sel) return NULL;
    pthread_mutex_lock(&dx_objc_lock);
    if (!class_realized(cls)) realize_class(cls);
    Method m = find_method(cls, sel);
    pthread_mutex_unlock(&dx_objc_lock);
    return m;
}
DX_FN(class_getInstanceMethod);
static Method d_class_getClassMethod(Class cls, SEL sel) {
    if (!cls) return NULL;
    REALIZED(cls);
    return d_class_getInstanceMethod(class_is_meta(cls) ? cls : cls->isa, sel);
}
DX_FN(class_getClassMethod);

void dx_objc_msgForward(void);
static IMP d_class_getMethodImplementation(Class cls, SEL sel) {
    if (!cls || !sel) return NULL;
    IMP imp = class_lookup_imp(cls, sel);
    return imp ? imp : (IMP)unrecognized;
}
DX_FN(class_getMethodImplementation);
DX_EXPORT("_class_getMethodImplementation_stret", d_class_getMethodImplementation);
static char d_class_respondsToSelector(Class cls, SEL sel) {
    return cls && sel && class_lookup_imp(cls, sel) != NULL;
}
DX_FN(class_respondsToSelector);

static char d_class_addMethod(Class cls, SEL sel, IMP imp, const char *types) {
    if (!cls || !sel || !imp) return 0;
    pthread_mutex_lock(&dx_objc_lock);
    if (!class_realized(cls)) realize_class(cls);
    int exists = find_in_class(cls, sel) != NULL;
    pthread_mutex_unlock(&dx_objc_lock);
    if (exists) return 0;
    add_method(cls, sel, imp, types);
    flush_caches();
    return 1;
}
DX_FN(class_addMethod);
static IMP d_class_replaceMethod(Class cls, SEL sel, IMP imp, const char *types) {
    if (!cls || !sel || !imp) return NULL;
    pthread_mutex_lock(&dx_objc_lock);
    if (!class_realized(cls)) realize_class(cls);
    struct method *m = find_in_class(cls, sel);
    IMP old = NULL;
    if (m) {
        old = m->imp;
        m->imp = imp;
    }
    pthread_mutex_unlock(&dx_objc_lock);
    if (!m) add_method(cls, sel, imp, types);
    flush_caches();
    return old;
}
DX_FN(class_replaceMethod);

static Method *d_class_copyMethodList(Class cls, unsigned *count) {
    if (count) *count = 0;
    if (!cls) return NULL;
    pthread_mutex_lock(&dx_objc_lock);
    if (!class_realized(cls)) realize_class(cls);
    unsigned n = 0;
    for (struct mlist *l = RW(cls)->methods; l; l = l->next) n += l->count;
    Method *out = n ? malloc((n + 1) * sizeof *out) : NULL;
    unsigned k = 0;
    for (struct mlist *l = RW(cls)->methods; l && out; l = l->next)
        for (int i = 0; i < l->count; i++) out[k++] = &l->m[i];
    if (out) out[k] = NULL;
    pthread_mutex_unlock(&dx_objc_lock);
    if (count) *count = n;
    return out;
}
DX_FN(class_copyMethodList);

static SEL d_method_getName(Method m) { return m ? m->name : NULL; }
DX_FN(method_getName);
static IMP d_method_getImplementation(Method m) { return m ? m->imp : NULL; }
DX_FN(method_getImplementation);
static const char *d_method_getTypeEncoding(Method m) { return m ? m->types : NULL; }
DX_FN(method_getTypeEncoding);
static IMP d_method_setImplementation(Method m, IMP imp) {
    if (!m) return NULL;
    IMP old = m->imp;
    m->imp = imp;
    flush_caches();
    return old;
}
DX_FN(method_setImplementation);
static void d_method_exchangeImplementations(Method a, Method b) {
    if (!a || !b) return;
    IMP t = a->imp;
    a->imp = b->imp;
    b->imp = t;
    flush_caches();
}
DX_FN(method_exchangeImplementations);

/* Skip one type in an Objective-C type encoding. */
static const char *skip_type(const char *t) {
    while (*t && strchr("rnNoORV", *t)) t++; /* qualifiers */
    if (*t == '{' || *t == '(' || *t == '[') {
        char open = *t, close = open == '{' ? '}' : open == '(' ? ')' : ']';
        int depth = 0;
        do {
            if (*t == open) depth++;
            else if (*t == close) depth--;
            t++;
        } while (*t && depth);
    } else if (*t == '^') {
        return skip_type(t + 1);
    } else if (*t == '@' && t[1] == '?') {
        t += 2;
    } else if (*t == '@' && t[1] == '"') {
        t += 2;
        while (*t && *t != '"') t++;
        if (*t) t++;
    } else if (*t == 'b') {
        t++;
    } else if (*t) {
        t++;
    }
    while (*t == '+' || *t == '-' || (*t >= '0' && *t <= '9')) t++; /* frame offset */
    return t;
}
static unsigned d_method_getNumberOfArguments(Method m) {
    if (!m || !m->types) return 0;
    const char *t = skip_type(m->types);
    unsigned n = 0;
    while (*t) {
        t = skip_type(t);
        n++;
    }
    return n;
}
DX_FN(method_getNumberOfArguments);
static char *copy_type_range(const char *a, const char *b) {
    while (b > a && (b[-1] == '+' || b[-1] == '-' || (b[-1] >= '0' && b[-1] <= '9'))) b--;
    char *out = malloc((size_t)(b - a) + 1);
    memcpy(out, a, (size_t)(b - a));
    out[b - a] = 0;
    return out;
}
static char *d_method_copyReturnType(Method m) {
    if (!m || !m->types) return NULL;
    return copy_type_range(m->types, skip_type(m->types));
}
DX_FN(method_copyReturnType);
static char *d_method_copyArgumentType(Method m, unsigned index) {
    if (!m || !m->types) return NULL;
    const char *t = skip_type(m->types);
    for (unsigned i = 0; *t; i++) {
        const char *next = skip_type(t);
        if (i == index) return copy_type_range(t, next);
        t = next;
    }
    return NULL;
}
DX_FN(method_copyArgumentType);
static void d_method_getReturnType(Method m, char *dst, size_t len) {
    char *t = d_method_copyReturnType(m);
    if (len) {
        strncpy(dst, t ? t : "", len - 1);
        dst[len - 1] = 0;
    }
    free(t);
}
DX_FN(method_getReturnType);

/* ---- instance variables ---- */
static struct ivar *find_ivar(Class cls, const char *name) {
    for (Class c = cls; c; c = c->superclass) {
        REALIZED(c);
        struct ivar_list *l = RW(c)->ro->ivars;
        for (uint32_t i = 0; l && i < l->count; i++) {
            struct ivar *iv = (struct ivar *)((char *)&l->first + i * l->entsize);
            if (iv->name && !strcmp(iv->name, name)) return iv;
        }
    }
    return NULL;
}
static struct ivar *d_class_getInstanceVariable(Class cls, const char *name) {
    return cls && name ? find_ivar(cls, name) : NULL;
}
DX_FN(class_getInstanceVariable);
static const char *d_ivar_getName(struct ivar *iv) { return iv ? iv->name : NULL; }
DX_FN(ivar_getName);
static const char *d_ivar_getTypeEncoding(struct ivar *iv) { return iv ? iv->type : NULL; }
DX_FN(ivar_getTypeEncoding);
static ptrdiff_t d_ivar_getOffset(struct ivar *iv) { return iv && iv->offset ? *iv->offset : 0; }
DX_FN(ivar_getOffset);
static struct ivar **d_class_copyIvarList(Class cls, unsigned *count) {
    if (count) *count = 0;
    if (!cls) return NULL;
    REALIZED(cls);
    struct ivar_list *l = RW(cls)->ro->ivars;
    if (!l || !l->count) return NULL;
    struct ivar **out = malloc((l->count + 1) * sizeof *out);
    for (uint32_t i = 0; i < l->count; i++) out[i] = (struct ivar *)((char *)&l->first + i * l->entsize);
    out[l->count] = NULL;
    if (count) *count = l->count;
    return out;
}
DX_FN(class_copyIvarList);
static id d_object_getIvar(id obj, struct ivar *iv) {
    return obj && iv && iv->offset ? *(id *)((char *)obj + *iv->offset) : NULL;
}
DX_FN(object_getIvar);
static void d_object_setIvar(id obj, struct ivar *iv, id value) {
    if (obj && iv && iv->offset) *(id *)((char *)obj + *iv->offset) = value;
}
DX_FN(object_setIvar);
static void *d_object_getIndexedIvars(id obj) {
    if (!obj) return NULL;
    Class c = objc_class_of(obj);
    return (char *)obj + ((RW(c)->instance_size + 7) & ~7u);
}
DX_FN(object_getIndexedIvars);
static struct ivar *d_object_getInstanceVariable(id obj, const char *name, void **out) {
    if (!obj) return NULL;
    struct ivar *iv = find_ivar(objc_class_of(obj), name);
    if (iv && out && iv->offset) *out = *(void **)((char *)obj + *iv->offset);
    return iv;
}
DX_FN(object_getInstanceVariable);

/* class_addIvar: only before objc_registerClassPair */
static char d_class_addIvar(Class cls, const char *name, size_t size, uint8_t align_log2, const char *types) {
    if (!cls || !name) return 0;
    struct class_rw *rw = RW(cls);
    if (!(rw->flags & RW_DYNAMIC) || (rw->flags & RW_REGISTERED) || find_ivar(cls, name)) return 0;
    struct class_ro *ro = (struct class_ro *)rw->ro;
    uint32_t n = ro->ivars ? ro->ivars->count : 0;
    struct ivar_list *nl = calloc(1, sizeof(uint32_t) * 2 + (n + 1) * sizeof(struct ivar));
    nl->entsize = sizeof(struct ivar);
    nl->count = n + 1;
    if (n) memcpy(&nl->first, &ro->ivars->first, n * sizeof(struct ivar));
    struct ivar *iv = &nl->first + n;
    size_t align = (size_t)1 << align_log2;
    uint32_t off = (uint32_t)((rw->instance_size + align - 1) & ~(align - 1));
    int32_t *slot = malloc(sizeof *slot);
    *slot = (int32_t)off;
    iv->offset = slot;
    iv->name = strdup(name);
    iv->type = strdup(types ? types : "");
    iv->alignment_raw = align_log2;
    iv->size = (uint32_t)size;
    ro->ivars = nl;
    ro->instance_size = rw->instance_size = off + (uint32_t)size;
    return 1;
}
DX_FN(class_addIvar);

/* ---- properties and protocols ---- */
static struct property *d_class_getProperty(Class cls, const char *name) {
    for (Class c = cls; c && name; c = c->superclass) {
        REALIZED(c);
        for (int k = 0; k < RW(c)->nproperties; k++) {
            struct property_list *l = RW(c)->properties[k];
            for (uint32_t i = 0; i < l->count; i++) {
                struct property *p = (struct property *)((char *)&l->first + i * l->entsize);
                if (!strcmp(p->name, name)) return p;
            }
        }
    }
    return NULL;
}
DX_FN(class_getProperty);
static struct property **d_class_copyPropertyList(Class cls, unsigned *count) {
    if (count) *count = 0;
    if (!cls) return NULL;
    REALIZED(cls);
    unsigned n = 0;
    for (int k = 0; k < RW(cls)->nproperties; k++) n += RW(cls)->properties[k]->count;
    if (!n) return NULL;
    struct property **out = malloc((n + 1) * sizeof *out);
    unsigned j = 0;
    for (int k = 0; k < RW(cls)->nproperties; k++) {
        struct property_list *l = RW(cls)->properties[k];
        for (uint32_t i = 0; i < l->count; i++) out[j++] = (struct property *)((char *)&l->first + i * l->entsize);
    }
    out[j] = NULL;
    if (count) *count = n;
    return out;
}
DX_FN(class_copyPropertyList);
static const char *d_property_getName(struct property *p) { return p ? p->name : NULL; }
DX_FN(property_getName);
static const char *d_property_getAttributes(struct property *p) { return p ? p->attributes : NULL; }
DX_FN(property_getAttributes);

static int protocol_conforms(struct protocol *p, struct protocol *other) {
    if (!p || !other) return 0;
    if (p == other || !strcmp(p->name, other->name)) return 1;
    for (uintptr_t i = 0; p->protocols && i < p->protocols->count; i++)
        if (protocol_conforms(p->protocols->list[i], other)) return 1;
    return 0;
}
static char d_protocol_conformsToProtocol(struct protocol *p, struct protocol *other) {
    return protocol_conforms(p, other);
}
DX_FN(protocol_conformsToProtocol);
static char d_protocol_isEqual(struct protocol *a, struct protocol *b) {
    return a == b || (a && b && !strcmp(a->name, b->name));
}
DX_FN(protocol_isEqual);
static const char *d_protocol_getName(struct protocol *p) { return p ? p->name : "nil"; }
DX_FN(protocol_getName);
static struct protocol *d_objc_getProtocol(const char *name) {
    struct protocol *r = NULL;
    pthread_mutex_lock(&dx_objc_lock);
    for (size_t i = 0; name && i < protocol_count; i++)
        if (!strcmp(protocol_table[i]->name, name)) r = protocol_table[i];
    pthread_mutex_unlock(&dx_objc_lock);
    return r;
}
DX_FN(objc_getProtocol);
/* Whether `cls` implements every required method in a protocol method list. */
static int implements_all(Class cls, void *raw) {
    struct mlist *l = convert_methods(raw);
    int ok = 1;
    for (int i = 0; l && i < l->count && ok; i++)
        if (!find_method(cls, l->m[i].name)) ok = 0;
    free(l);
    return ok;
}
static char d_class_conformsToProtocol(Class cls, struct protocol *p) {
    if (!cls || !p) return 0;
    REALIZED(cls);
    for (int i = 0; i < RW(cls)->nprotocols; i++)
        if (protocol_conforms(RW(cls)->protocols[i], p)) return 1;
    /* Classes bitten makes at run time (NSString's toll-free-bridged
     * __NSCFString and the like) carry no protocol lists. For a class that
     * declares none, conforming means implementing the protocol's required
     * methods, so `NSString as NSCopying` holds. */
    if (RW(cls)->nprotocols == 0 && (p->instance_methods || p->class_methods) && cls->isa) {
        REALIZED(cls->isa);
        return implements_all(cls, p->instance_methods) && implements_all(cls->isa, p->class_methods);
    }
    return 0;
}
DX_FN(class_conformsToProtocol);
static char d_class_addProtocol(Class cls, struct protocol *p) {
    if (!cls || !p || d_class_conformsToProtocol(cls, p)) return 0;
    pthread_mutex_lock(&dx_objc_lock);
    struct class_rw *rw = RW(cls);
    rw->protocols = realloc(rw->protocols, (rw->nprotocols + 1) * sizeof *rw->protocols);
    rw->protocols[rw->nprotocols++] = p;
    pthread_mutex_unlock(&dx_objc_lock);
    return 1;
}
DX_FN(class_addProtocol);
static struct protocol **d_class_copyProtocolList(Class cls, unsigned *count) {
    if (count) *count = 0;
    if (!cls) return NULL;
    REALIZED(cls);
    int n = RW(cls)->nprotocols;
    if (!n) return NULL;
    struct protocol **out = malloc((n + 1) * sizeof *out);
    memcpy(out, RW(cls)->protocols, n * sizeof *out);
    out[n] = NULL;
    if (count) *count = (unsigned)n;
    return out;
}
DX_FN(class_copyProtocolList);

struct method_description {
    SEL name;
    const char *types;
};
static struct method_description d_protocol_getMethodDescription(struct protocol *p, SEL sel, char required,
                                                                 char instance) {
    struct method_description d = {NULL, NULL};
    if (!p) return d;
    void *raw = instance ? (required ? p->instance_methods : p->opt_instance_methods)
                         : (required ? p->class_methods : p->opt_class_methods);
    struct mlist *l = convert_methods(raw);
    for (int i = 0; l && i < l->count; i++)
        if (l->m[i].name == sel) {
            d.name = sel;
            d.types = l->m[i].types;
        }
    free(l);
    for (uintptr_t i = 0; !d.name && p->protocols && i < p->protocols->count; i++)
        d = d_protocol_getMethodDescription(p->protocols->list[i], sel, required, instance);
    return d;
}
DX_FN(protocol_getMethodDescription);

/* ---- class pairs ---- */
static Class d_objc_allocateClassPair(Class super, const char *name, size_t extra) {
    if (!name || dx_objc_lookup_class(name)) return NULL;
    return make_class(NULL, NULL, super, name, extra);
}
DX_FN(objc_allocateClassPair);
static void d_objc_registerClassPair(Class cls) {
    if (cls) register_class(cls);
}
DX_FN(objc_registerClassPair);
static void d_objc_disposeClassPair(Class cls) { (void)cls; /* classes are kept: caches may reference them */ }
DX_FN(objc_disposeClassPair);

static int d_objc_getClassList(Class *buffer, int max) {
    pthread_mutex_lock(&dx_objc_lock);
    int n = 0;
    for (size_t i = 0; i < class_cap; i++) {
        if (!class_table[i].name) continue;
        if (buffer && n < max) buffer[n] = class_table[i].cls;
        n++;
    }
    pthread_mutex_unlock(&dx_objc_lock);
    return n;
}
DX_FN(objc_getClassList);
static Class *d_objc_copyClassList(unsigned *count) {
    int n = d_objc_getClassList(NULL, 0);
    Class *out = malloc((n + 1) * sizeof *out);
    n = d_objc_getClassList(out, n);
    out[n] = NULL;
    if (count) *count = (unsigned)n;
    return out;
}
DX_FN(objc_copyClassList);

/* ---- dispatch entry points ---- */
void dx_objc_msgSend_fpret(void), dx_objc_msgSend_fp2ret(void), dx_objc_msgSend_stret(void),
    dx_objc_msgSendSuper(void), dx_objc_msgSendSuper2(void), dx_objc_msgSendSuper_stret(void),
    dx_objc_msgSendSuper2_stret(void), dx_method_invoke(void), dx_method_invoke_stret(void);
void (*const dx_objc_msgSend_ptr)(void) = dx_objc_msgSend;
DX_EXPORT("_objc_msgSend", dx_objc_msgSend);
DX_EXPORT("_objc_msgSend_fpret", dx_objc_msgSend_fpret);
DX_EXPORT("_objc_msgSend_fp2ret", dx_objc_msgSend_fp2ret);
DX_EXPORT("_objc_msgSend_stret", dx_objc_msgSend_stret);
DX_EXPORT("_objc_msgSendSuper", dx_objc_msgSendSuper);
DX_EXPORT("_objc_msgSendSuper2", dx_objc_msgSendSuper2);
DX_EXPORT("_objc_msgSendSuper_stret", dx_objc_msgSendSuper_stret);
DX_EXPORT("_objc_msgSendSuper2_stret", dx_objc_msgSendSuper2_stret);
DX_EXPORT("_method_invoke", dx_method_invoke);
DX_EXPORT("_method_invoke_stret", dx_method_invoke_stret);
DX_EXPORT("__objc_msgForward", unrecognized);
DX_EXPORT("__objc_msgForward_stret", unrecognized_stret);

/* ---- start-up ---- */
void dx_objc_arc_init(void);

__attribute__((constructor(101))) static void runtime_init(void) {
    pthread_mutexattr_t a;
    pthread_mutexattr_init(&a);
    pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&dx_objc_lock, &a);
    SEL_retain = sel_intern("retain");
    SEL_release = sel_intern("release");
    SEL_autorelease = sel_intern("autorelease");
    SEL_dealloc = sel_intern("dealloc");
    SEL_alloc = sel_intern("alloc");
    SEL_allocWithZone = sel_intern("allocWithZone:");
    SEL_init = sel_intern("init");
    SEL_new = sel_intern("new");
    SEL_class = sel_intern("class");
    SEL_self = sel_intern("self");
    SEL_copy = sel_intern("copy");
    SEL_copyWithZone = sel_intern("copyWithZone:");
    SEL_mutableCopyWithZone = sel_intern("mutableCopyWithZone:");
    SEL_initialize = sel_intern("initialize");
    SEL_load = sel_intern("load");
    SEL_cxx_destruct = sel_intern(".cxx_destruct");
    SEL_cxx_construct = sel_intern(".cxx_construct");
    SEL_resolveInstanceMethod = sel_intern("resolveInstanceMethod:");
    SEL_resolveClassMethod = sel_intern("resolveClassMethod:");
    SEL_forwardingTargetForSelector = sel_intern("forwardingTargetForSelector:");
    SEL_respondsToSelector = sel_intern("respondsToSelector:");
    SEL_isKindOfClass = sel_intern("isKindOfClass:");
    SEL_retainCount = sel_intern("retainCount");
    SEL_allowsWeakReference = sel_intern("allowsWeakReference");
    SEL_retainWeakReference = sel_intern("retainWeakReference");
    dx_objc_arc_init();
    make_class(&protocol_class, &protocol_meta, &dx_NSObject_class, "Protocol", 0);
    register_class(&protocol_class);
}
DX_EXPORT("_OBJC_CLASS_$_Protocol", &protocol_class);
DX_EXPORT("_OBJC_METACLASS_$_Protocol", &protocol_meta);

/* used by arc.c */
void dx_objc_register_class(Class cls) { register_class(cls); }
