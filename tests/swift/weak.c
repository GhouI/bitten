// Driver for weak.swift: weak references become nil when their object's
// deinit starts, for Swift and Objective-C objects alike; unowned
// references to either kind.
#include "darwin.h"

typedef void *id;
id objc_getClass(const char *);
void *sel_registerName(const char *);
id objc_msgSend(id, void *);
id objc_retain(id);
void objc_release(id);

void weak_track(long id), weak_link(void), weak_any_set(void *), weak_unowned_set(void *);
long weak_read(long none), weak_pair_copy(long none), weak_pair_read(long none);
_Bool weak_pair_any_nil(void);
void *weak_strong(void), *weak_any_get(void), *weak_unowned_get(void);
unsigned long swift_retainCount(void *);

static long notes[64];
static int nnotes;
void note(long x) {
    if (nnotes < 64) notes[nnotes++] = x;
}

static id new_nsobject(void) {
    id o = objc_msgSend(objc_getClass("NSObject"), sel_registerName("alloc"));
    return objc_msgSend(o, sel_registerName("init"));
}

int main(void) {
    // native weak reference
    weak_track(1);
    CHECK(nnotes == 1 && notes[0] == 0); /* the initial Tracker(0) */
    weak_link();
    CHECK(weak_read(-1) == 1);
    CHECK(swift_retainCount(weak_strong()) == 1); /* weak does not retain */
    nnotes = 0;
    weak_track(2);
    CHECK(nnotes == 1 && notes[0] == 1);
    CHECK(weak_read(-1) == -1);

    // copies of weak references, native and AnyObject
    weak_link();
    CHECK(weak_pair_copy(-1) == 2);
    CHECK(weak_pair_read(-1) == 2 && !weak_pair_any_nil());
    CHECK(weak_read(-1) == 2);
    weak_track(3);
    CHECK(weak_read(-1) == -1 && weak_pair_read(-1) == -1);
    CHECK(weak_pair_any_nil()); /* an AnyObject weak reference to a Swift object */

    // AnyObject weak reference to an Objective-C object
    id ns = new_nsobject();
    weak_any_set(ns);
    CHECK(weak_any_get() == ns);
    objc_release(ns);
    CHECK(weak_any_get() == NULL);

    // ... and to a Swift object
    void *s = weak_strong();
    weak_any_set(s);
    CHECK(weak_any_get() == s);
    nnotes = 0;
    weak_track(4);
    CHECK(nnotes == 1 && notes[0] == 3);
    CHECK(weak_any_get() == NULL);

    // unowned AnyObject references: Objective-C, then Swift
    id ns2 = new_nsobject();
    weak_unowned_set(ns2);
    CHECK(weak_unowned_get() == ns2);
    s = weak_strong();
    weak_unowned_set(s);
    CHECK(weak_unowned_get() == s);
    objc_release(ns2);
    CHECK(swift_retainCount(s) == 1);

    puts("swift weak ok");
    return 0;
}
