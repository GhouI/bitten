// Driver for heap.swift: Swift objects' lifetimes, observed through the
// deinit callback note() and the runtime's counters.
#include "darwin.h"

typedef _Bool bool;
long heap_held(void), heap_owner(void), heap_owner_read(void), heap_lazy(void);
void *heap_static(void);
void heap_hold(long id), heap_pair(long p, long a, long b), heap_drop_closure(void), heap_lazy_add(long d);
bool heap_unique(long id), heap_shared_unique(void);
long heap_closure(long start, long step, long id), heap_local(long id);

void *swift_retain(void *);
void swift_release(void *);
void *swift_retain_n(void *, unsigned);
void swift_release_n(void *, unsigned);
unsigned long swift_retainCount(void *);
unsigned long swift_unownedRetainCount(void *);
void *swift_unownedRetain(void *);
bool swift_tryRetain(void *);
bool swift_isDeallocating(void *);
bool swift_isUniquelyReferenced_native(void *);
void *swift_allocObject(void *, unsigned long, unsigned long);
void swift_once(long *, void (*)(void *), void *);
struct box_pair { void *box; void **value; };
struct box_pair swift_allocBox(const void *type);
struct box_pair swift_makeBoxUnique(void **buffer, const void *type, unsigned long align_mask);
void **swift_projectBox(void *box);
void *swift_allocEmptyBox(void);
void *swift_weakInit(void **, void *);
void *swift_weakAssign(void **, void *);
void *swift_weakLoadStrong(void **);
void *swift_weakTakeStrong(void **);
void swift_weakDestroy(void **);
void *swift_weakCopyInit(void **, void **);
void *swift_weakTakeInit(void **, void **);
void *swift_weakCopyAssign(void **, void **);
void *swift_weakTakeAssign(void **, void **);
void *swift_unownedRetainStrong(void *);
void swift_unownedRelease(void *);
extern const char $sBoWV[];
struct vwt {
    void *(*init_buffer)(void *, void *, const void *);
    void (*destroy)(void *, const void *);
    void *(*init_copy)(void *, void *, const void *);
    void *(*assign_copy)(void *, void *, const void *);
    void *(*init_take)(void *, void *, const void *);
    void *(*assign_take)(void *, void *, const void *);
    unsigned (*get_tag)(const void *, unsigned, const void *);
    void (*store_tag)(void *, unsigned, unsigned, const void *);
    unsigned long size, stride;
    unsigned flags, xi;
};
extern const struct vwt $syycWV;

// Metadata for "some class type": a value witness table and a kind. Boxes
// made for it hold one strong reference.
static const struct { const void *vwt; unsigned long kind; } ref_type = {$sBoWV, 0x200};

static long notes[64];
static int nnotes;
void note(long x) {
    if (nnotes < 64) notes[nnotes++] = x;
}
static int noted(int n, long a, long b, long c, long d) {
    if (nnotes != n) return 0;
    long want[4] = {a, b, c, d};
    for (int i = 0; i < n && i < 4; i++)
        if (notes[i] != want[i]) return 0;
    return 1;
}

static int once_runs;
static void once_fn(void *ctx) { once_runs += (int)(long)ctx; }

int main(void) {
    // the global's initialiser made a Tracker(0); replacing it runs its deinit
    void *t = (void *)heap_held();
    CHECK(swift_retainCount(t) == 1);
    CHECK(swift_retain(t) == t && swift_retainCount(t) == 2);
    CHECK(!heap_shared_unique());
    swift_release(t);
    CHECK(heap_shared_unique());
    swift_retain_n(t, 5);
    CHECK(swift_retainCount(t) == 6);
    swift_release_n(t, 5);
    CHECK(swift_retainCount(t) == 1 && !swift_isDeallocating(t));
    nnotes = 0;
    heap_hold(7);
    CHECK(noted(1, 0, 0, 0, 0));
    CHECK(swift_retainCount((void *)heap_held()) == 1);

    // a weak-style load of a live object succeeds
    t = (void *)heap_held();
    CHECK(swift_tryRetain(t) && swift_retainCount(t) == 2);
    swift_release(t);

    // deinit first, then the stored properties
    nnotes = 0;
    heap_pair(100, 1, 2);
    // (the order among the properties is the optimiser's choice)
    CHECK(noted(4, 100, 100, 1, 2) || noted(4, 100, 100, 2, 1));

    CHECK(heap_unique(3));

    // unowned: the object dies with its last strong reference, the memory
    // waits for the unowned one
    nnotes = 0;
    CHECK(heap_owner() == 7);
    t = (void *)heap_held();
    CHECK(swift_unownedRetainCount(t) == 1);
    swift_retain(t); // keep the memory inspectable after the deinit
    heap_hold(8);
    CHECK(nnotes == 0); /* still retained by us */
    swift_release(t);
    CHECK(noted(1, 7, 0, 0, 0));
    CHECK(swift_isDeallocating(t) && !swift_tryRetain(t));
    CHECK(swift_unownedRetainCount(t) == 1);

    // closures: the box holds x, the context holds the tracker
    nnotes = 0;
    CHECK(heap_closure(10, 5, 42) == 20);
    CHECK(noted(2, 42, 42, 0, 0));
    heap_drop_closure();
    CHECK(noted(3, 42, 42, 42, 0));

    // statically initialised objects (at -O) are immortal
    void *s = heap_static();
    CHECK(s == heap_static());
    unsigned long big = swift_retainCount(s);
    if (big > 1000) {
        CHECK(((long *)s)[-1] == -1); /* its once-token */
        swift_release(s);
        swift_release(s);
        CHECK(swift_retainCount(s) == big && !swift_isUniquelyReferenced_native(s));
    }

    // lazily initialised global: the initialiser runs once
    nnotes = 0;
    CHECK(heap_lazy() == 0);
    heap_lazy_add(3);
    heap_lazy_add(4);
    CHECK(heap_lazy() == 7);
    CHECK(noted(1, 0, 0, 0, 0));

    // swift_once directly: ~0 means done
    long pred = 0;
    swift_once(&pred, once_fn, (void *)1);
    swift_once(&pred, once_fn, (void *)1);
    CHECK(once_runs == 1 && pred == -1);

    // stack-promoted object (at -O): deinit runs, nothing is freed
    nnotes = 0;
    CHECK(heap_local(21) == 42);
    CHECK(noted(1, 21, 0, 0, 0));

    // boxes made by the runtime for a type known only at run time
    heap_hold(9);
    t = (void *)heap_held();
    struct box_pair b = swift_allocBox(&ref_type.kind);
    CHECK(b.box && swift_projectBox(b.box) == b.value);
    *b.value = swift_retain(t);
    CHECK(swift_retainCount(t) == 2);
    void *buffer[3] = {b.box};
    struct box_pair u = swift_makeBoxUnique(buffer, &ref_type.kind, 7);
    CHECK(u.box == b.box && u.value == b.value); /* already unique */
    swift_retain(b.box);
    u = swift_makeBoxUnique(buffer, &ref_type.kind, 7);
    CHECK(u.box != b.box && buffer[0] == u.box && *u.value == t);
    CHECK(swift_retainCount(t) == 3 && swift_retainCount(b.box) == 1);
    swift_release(b.box);
    swift_release(u.box);
    CHECK(swift_retainCount(t) == 1);
    nnotes = 0;
    heap_hold(10);
    CHECK(noted(1, 9, 0, 0, 0));
    void *e = swift_allocEmptyBox();
    CHECK(e && e == swift_allocEmptyBox());
    swift_release(e);

    // value witnesses: a class reference and a closure (function + context)
    const struct vwt *ref = (const struct vwt *)$sBoWV;
    t = (void *)heap_held();
    void *slot = NULL;
    CHECK(ref->size == 8 && ref->xi == 0x7fffffff && (ref->flags & 0x10000));
    ref->init_copy(&slot, &t, &ref_type.kind);
    CHECK(slot == t && swift_retainCount(t) == 2);
    CHECK(ref->get_tag(&slot, 1, &ref_type.kind) == 0);
    ref->destroy(&slot, &ref_type.kind);
    CHECK(swift_retainCount(t) == 1);
    ref->store_tag(&slot, 1, 1, &ref_type.kind); /* nil */
    CHECK(slot == NULL && ref->get_tag(&slot, 1, &ref_type.kind) == 1);
    void *clo[2] = {(void *)main, t}, *clo2[2];
    $syycWV.init_copy(clo2, clo, NULL);
    CHECK(clo2[0] == (void *)main && clo2[1] == t && swift_retainCount(t) == 2);
    CHECK($syycWV.get_tag(clo2, 1, NULL) == 0);
    $syycWV.destroy(clo2, NULL);
    CHECK(swift_retainCount(t) == 1 && $syycWV.size == 16);
    $syycWV.store_tag(clo2, 1, 1, NULL);
    CHECK($syycWV.get_tag(clo2, 1, NULL) == 1);

    // native weak references (bitwise-takable: TakeInit is a plain move)
    heap_hold(11);
    t = (void *)heap_held();
    void *w1, *w2, *w3, *w4;
    swift_weakInit(&w1, t);
    CHECK(swift_retainCount(t) == 1);
    void *l = swift_weakLoadStrong(&w1);
    CHECK(l == t && swift_retainCount(t) == 2);
    swift_release(l);
    swift_weakCopyInit(&w2, &w1);
    swift_weakTakeInit(&w3, &w2);
    swift_weakInit(&w4, NULL);
    CHECK(swift_weakLoadStrong(&w4) == NULL);
    swift_weakCopyAssign(&w4, &w3);
    l = swift_weakTakeStrong(&w4);
    CHECK(l == t);
    swift_release(l);
    nnotes = 0;
    heap_hold(12); /* Tracker(11) dies: every weak reference reads nil */
    CHECK(noted(1, 11, 0, 0, 0));
    CHECK(swift_weakLoadStrong(&w1) == NULL && swift_weakLoadStrong(&w3) == NULL);
    t = (void *)heap_held();
    swift_weakAssign(&w1, t);
    swift_weakTakeAssign(&w3, &w1);
    l = swift_weakLoadStrong(&w3);
    CHECK(l == t);
    swift_release(l);
    swift_weakDestroy(&w3);
    // unowned strong loads succeed while the object lives
    swift_unownedRetain(t);
    CHECK(swift_unownedRetainStrong(t) == t && swift_retainCount(t) == 2);
    swift_release(t);
    swift_unownedRelease(t);

    puts("swift heap ok");
    return 0;
}
