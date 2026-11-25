// Driver for objc.swift: a Swift object used through the Objective-C
// runtime, and the runtime's bridges between the two worlds.
#include "darwin.h"

typedef void *id;
typedef _Bool bool;
id objc_getClass(const char *);
const char *class_getName(id);
id class_getSuperclass(id);
id object_getClass(id);
void *sel_registerName(const char *);
id objc_retain(id);
void objc_release(id);
id objc_autorelease(id);
void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *);
id objc_storeWeak(id *, id);
id objc_loadWeakRetained(id *);
void objc_destroyWeak(id *);
id objc_msgSend(id, void *);
#define MSG0(obj, sel) objc_msgSend((obj), sel_registerName(sel))
#define MSG1(obj, sel, arg) ((id(*)(id, void *, id))objc_msgSend)((obj), sel_registerName(sel), (arg))
// BOOL results come back in %al only
#define BOOL0(obj, sel) ((char (*)(id, void *))objc_msgSend)((obj), sel_registerName(sel))
#define BOOL1(obj, sel, arg) ((char (*)(id, void *, id))objc_msgSend)((obj), sel_registerName(sel), (arg))

void objc_hold(long id);
id objc_held(void);
long objc_tracker_id(id);

unsigned long swift_retainCount(id);
id swift_unknownObjectRetain(id);
void swift_unknownObjectRelease(id);
id swift_unknownObjectRetain_n(id, unsigned);
void swift_unknownObjectRelease_n(id, unsigned);
void *swift_bridgeObjectRetain(void *);
void swift_bridgeObjectRelease(void *);
bool swift_isUniquelyReferencedNonObjC(id);
id swift_dynamicCastObjCClass(id, id);
id swift_dynamicCastObjCClassUnconditional(id, id, const char *, unsigned, unsigned);
id swift_dynamicCastObjCClassMetatype(id, id);
const unsigned long *swift_getObjCClassMetadata(id);
id swift_getObjCClassFromMetadata(const void *);
id swift_getObjCClassFromObject(id);
extern char OBJC_CLASS_$__TtCs12_SwiftObject[];

static long notes[64];
static int nnotes;
void note(long x) {
    if (nnotes < 64) notes[nnotes++] = x;
}

static unsigned long rc_msg(id o) { return (unsigned long)MSG0(o, "retainCount"); }

int main(void) {
    id root = (id)OBJC_CLASS_$__TtCs12_SwiftObject;
    objc_hold(5);
    id t = objc_held();
    id cls = objc_getClass("_TtC4objc7Tracker");
    CHECK(cls != NULL);
    CHECK(!strcmp(class_getName(cls), "_TtC4objc7Tracker"));
    CHECK(class_getSuperclass(cls) == root);
    CHECK(objc_getClass("_TtCs12_SwiftObject") == root);

    // NSObject-protocol basics
    CHECK(MSG0(t, "class") == cls && object_getClass(t) == cls);
    CHECK(MSG0(t, "self") == t);
    CHECK(BOOL1(t, "isKindOfClass:", root) && BOOL1(t, "isKindOfClass:", cls));
    CHECK(!BOOL1(t, "isKindOfClass:", objc_getClass("NSObject")));
    CHECK(BOOL1(t, "respondsToSelector:", sel_registerName("retain")));
    CHECK(!BOOL1(t, "respondsToSelector:", sel_registerName("frobnicate")));
    CHECK(BOOL1(t, "isEqual:", t) && !BOOL1(t, "isEqual:", root));
    CHECK(MSG0(t, "hash") != 0);
    CHECK(MSG0(t, "description") != NULL);

    // retain/release by message and by the ARC entry points: Swift counts
    CHECK(rc_msg(t) == 1 && swift_retainCount(t) == 1);
    CHECK(MSG0(t, "retain") == t && swift_retainCount(t) == 2);
    CHECK(objc_retain(t) == t && rc_msg(t) == 3);
    objc_release(t);
    MSG0(t, "release");
    CHECK(swift_retainCount(t) == 1);
    CHECK(BOOL0(t, "_tryRetain"));
    CHECK(!BOOL0(t, "_isDeallocating") && BOOL0(t, "allowsWeakReference"));
    objc_release(t);

    // autorelease pools release through Swift
    void *pool = objc_autoreleasePoolPush();
    objc_autorelease(objc_retain(t));
    MSG0(objc_retain(t), "autorelease");
    CHECK(swift_retainCount(t) == 3);
    objc_autoreleasePoolPop(pool);
    CHECK(swift_retainCount(t) == 1);

    // a __weak variable holding a Swift object is cleared by its deinit
    id weak = NULL;
    objc_storeWeak(&weak, t);
    id loaded = objc_loadWeakRetained(&weak);
    CHECK(loaded == t && swift_retainCount(t) == 2);
    objc_release(loaded);
    nnotes = 0;
    objc_hold(6);
    CHECK(nnotes == 1 && notes[0] == 5);
    CHECK(objc_loadWeakRetained(&weak) == NULL && weak == NULL);
    objc_destroyWeak(&weak);

    // unknown objects: Swift or Objective-C, chosen per object
    t = objc_held();
    id ns = MSG0(MSG0(objc_getClass("NSObject"), "alloc"), "init");
    CHECK(swift_unknownObjectRetain(t) == t && swift_retainCount(t) == 2);
    swift_unknownObjectRelease(t);
    swift_unknownObjectRetain_n(t, 3);
    CHECK(swift_retainCount(t) == 4);
    swift_unknownObjectRelease_n(t, 3);
    CHECK(swift_unknownObjectRetain(ns) == ns && rc_msg(ns) == 2);
    swift_unknownObjectRelease(ns);
    CHECK(rc_msg(ns) == 1);
    CHECK(swift_isUniquelyReferencedNonObjC(t) && !swift_isUniquelyReferencedNonObjC(ns));
    CHECK(swift_unknownObjectRetain((id)0x11) == (id)0x11); /* tagged pointer: untouched */

    // bridge objects: flags in the spare bits, Objective-C bit, tagged values
    void *b = (void *)((unsigned long)t | 0x0100000000000000ul);
    CHECK(swift_bridgeObjectRetain(b) == b && swift_retainCount(t) == 2);
    swift_bridgeObjectRelease(b);
    CHECK(swift_retainCount(t) == 1);
    void *bo = (void *)((unsigned long)ns | 0x4000000000000000ul);
    swift_bridgeObjectRetain(bo);
    CHECK(rc_msg(ns) == 2);
    swift_bridgeObjectRelease(bo);
    CHECK(rc_msg(ns) == 1);
    void *imm = (void *)((unsigned long)t | 0x8000000000000000ul);
    swift_bridgeObjectRetain(imm);
    swift_bridgeObjectRelease(imm);
    swift_bridgeObjectRelease(imm);
    CHECK(swift_retainCount(t) == 1);

    // casts and class metadata
    CHECK(swift_dynamicCastObjCClass(t, root) == t && swift_dynamicCastObjCClass(t, cls) == t);
    CHECK(swift_dynamicCastObjCClass(ns, cls) == NULL);
    CHECK(swift_dynamicCastObjCClass(ns, objc_getClass("NSObject")) == ns);
    CHECK(swift_dynamicCastObjCClassUnconditional(t, root, 0, 0, 0) == t);
    CHECK(swift_dynamicCastObjCClassMetatype(cls, root) == cls);
    CHECK(swift_dynamicCastObjCClassMetatype(root, cls) == NULL);
    CHECK((id)swift_getObjCClassMetadata(cls) == cls);
    const unsigned long *wrap = swift_getObjCClassMetadata(objc_getClass("NSObject"));
    CHECK(wrap[0] == 0x305 && wrap == swift_getObjCClassMetadata(objc_getClass("NSObject")));
    CHECK(swift_getObjCClassFromMetadata(wrap) == objc_getClass("NSObject"));
    CHECK(swift_getObjCClassFromMetadata(cls) == cls);
    CHECK(swift_getObjCClassFromObject(t) == cls && swift_getObjCClassFromObject(ns) == objc_getClass("NSObject"));
    objc_release(ns);

    // +alloc from Objective-C makes a Swift-counted object; its last release
    // runs the Swift deinit (the stored id is zero: no Swift init ran)
    id a = MSG0(cls, "alloc");
    CHECK(a && object_getClass(a) == cls && swift_retainCount(a) == 1);
    nnotes = 0;
    objc_release(a);
    CHECK(nnotes == 1 && notes[0] == 0);
    CHECK(objc_tracker_id(objc_held()) == 6);

    puts("swift objc ok");
    return 0;
}
