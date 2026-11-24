/* Toll-free bridging: CF objects are Objective-C objects.
 *
 * Each CF type has a class whose storage is cf_classes[type]; cf_alloc()
 * stores that address as the object's isa. The public abstract classes
 * (NSString, NSArray, ...) are created here so that the concrete CF-backed
 * classes can inherit from them; their Objective-C methods are added by
 * Foundation as categories. Only memory management, equality and hashing
 * are implemented here, because CF itself needs them. */
#include <pthread.h>
#include <stdlib.h>

#include "../objc/objc_internal.h"
#include "cf.h"

struct cf_class_slot cf_classes[CF_TYPE_MAX];
static struct objc_class cf_metas[CF_TYPE_MAX];

/* the class of compiler-emitted constant strings: binaries reference this
 * symbol as the isa of every @"..." and CFSTR("...") */
static struct objc_class constant_string_class, constant_string_meta;
DX_EXPORT("___CFConstantStringClassReference", &constant_string_class);
DX_EXPORT("_OBJC_CLASS_$___NSCFConstantString", &constant_string_class);

int cf_is_constant_string(const void *object) {
    return object && *(void *const *)object == (void *)&constant_string_class;
}

int cf_is_cf(const void *object) {
    if (!object || ((uintptr_t)object & 1)) return 0;
    const void *isa = *(void *const *)object;
    return (isa >= (const void *)&cf_classes[0] && isa < (const void *)&cf_classes[CF_TYPE_MAX]) ||
           isa == (const void *)&constant_string_class;
}

/* constant string -> immortal CF string */
struct shadow {
    const void *constant;
    struct cf_string *string;
};
static struct shadow *shadows;
static size_t shadow_cap, shadow_count;
static pthread_mutex_t shadow_lock = PTHREAD_MUTEX_INITIALIZER;

const void *cf_resolve(const void *object) {
    if (!cf_is_constant_string(object)) return object;
    pthread_mutex_lock(&shadow_lock);
    if (shadow_count * 2 >= shadow_cap) {
        size_t ncap = shadow_cap ? shadow_cap * 2 : 256;
        struct shadow *nt = calloc(ncap, sizeof *nt);
        for (size_t i = 0; i < shadow_cap; i++) {
            if (!shadows[i].constant) continue;
            size_t j = ((uintptr_t)shadows[i].constant >> 4) & (ncap - 1);
            while (nt[j].constant) j = (j + 1) & (ncap - 1);
            nt[j] = shadows[i];
        }
        free(shadows);
        shadows = nt;
        shadow_cap = ncap;
    }
    size_t i = ((uintptr_t)object >> 4) & (shadow_cap - 1);
    while (shadows[i].constant && shadows[i].constant != object) i = (i + 1) & (shadow_cap - 1);
    if (!shadows[i].constant) {
        shadows[i].constant = object;
        shadows[i].string = cf_string_from_constant(object);
        shadow_count++;
    }
    struct cf_string *s = shadows[i].string;
    pthread_mutex_unlock(&shadow_lock);
    return s;
}

/* foreign Objective-C objects inside CF collections */
static SEL SEL_hash, SEL_isEqual;
unsigned long cf_objc_hash(const void *object) {
    return MSG(unsigned long, id, SEL)((id)object, SEL_hash);
}
Boolean cf_objc_equal(const void *left, const void *right) {
    /* ask whichever side is a plain Objective-C object */
    const void *asker = cf_is_cf(left) ? right : left, *other = asker == left ? right : left;
    return MSG(char, id, SEL, id)((id)asker, SEL_isEqual, (id)other) != 0;
}

/* ---- methods every CF-backed class has ---- */
static id cfm_retain(id self, SEL _cmd) { (void)_cmd; return (id)d_CFRetain(self); }
static void cfm_release(id self, SEL _cmd) { (void)_cmd; d_CFRelease(self); }
static unsigned long cfm_retainCount(id self, SEL _cmd) {
    (void)_cmd;
    CFIndex (*count)(const void *) = dx_registry_lookup("_CFGetRetainCount");
    return (unsigned long)count(self);
}
static void cfm_dealloc(id self, SEL _cmd) { (void)self; (void)_cmd; /* CFRelease frees */ }
static unsigned long cfm_hash(id self, SEL _cmd) { (void)_cmd; return d_CFHash(self); }
static char cfm_isEqual(id self, SEL _cmd, id other) {
    (void)_cmd;
    if (self == other) return 1;
    if (!other || !cf_is_cf(other)) return 0;
    return d_CFEqual(self, other);
}
static unsigned long cfm_typeID(id self, SEL _cmd) { (void)_cmd; return d_CFGetTypeID(self); }

static void add_cf_methods(Class c) {
    add_method(c, "retain", (IMP)cfm_retain, "@16@0:8");
    add_method(c, "release", (IMP)cfm_release, "Vv16@0:8");
    add_method(c, "retainCount", (IMP)cfm_retainCount, "Q16@0:8");
    add_method(c, "dealloc", (IMP)cfm_dealloc, "v16@0:8");
    add_method(c, "hash", (IMP)cfm_hash, "Q16@0:8");
    add_method(c, "isEqual:", (IMP)cfm_isEqual, "c24@0:8@16");
    add_method(c, "_cfTypeID", (IMP)cfm_typeID, "Q16@0:8");
}

void dx_objc_register_class(Class cls);

/* Public classes: exported so that code and Foundation's categories can
 * refer to them. */
#define PUBLIC_CLASS(Name)                                   \
    static struct objc_class cls_##Name, meta_##Name;        \
    DX_EXPORT("_OBJC_CLASS_$_" #Name, &cls_##Name);          \
    DX_EXPORT("_OBJC_METACLASS_$_" #Name, &meta_##Name)
PUBLIC_CLASS(NSString);
PUBLIC_CLASS(NSMutableString);
PUBLIC_CLASS(NSArray);
PUBLIC_CLASS(NSMutableArray);
PUBLIC_CLASS(NSDictionary);
PUBLIC_CLASS(NSMutableDictionary);
PUBLIC_CLASS(NSSet);
PUBLIC_CLASS(NSMutableSet);
PUBLIC_CLASS(NSData);
PUBLIC_CLASS(NSMutableData);
PUBLIC_CLASS(NSValue);
PUBLIC_CLASS(NSNumber);
PUBLIC_CLASS(NSDate);
PUBLIC_CLASS(NSError);
PUBLIC_CLASS(NSNull);
PUBLIC_CLASS(NSLocale);
PUBLIC_CLASS(NSURL);

static Class public_class(Class storage, Class meta, Class super, const char *name) {
    Class c = make_class(storage, meta, super, name, 0);
    dx_objc_register_class(c);
    return c;
}
static Class cf_class(int type, Class super, const char *name) {
    Class c = make_class((Class)&cf_classes[type], &cf_metas[type], super, name, 0);
    add_cf_methods(c);
    dx_objc_register_class(c);
    return c;
}

__attribute__((constructor(102))) static void bridge_init(void) {
    SEL_hash = sel_intern("hash");
    SEL_isEqual = sel_intern("isEqual:");
    Class root = &dx_NSObject_class;
#define PUB(Name, Super) public_class(&cls_##Name, &meta_##Name, Super, #Name)
    Class string = PUB(NSString, root), mstring = PUB(NSMutableString, string);
    Class array = PUB(NSArray, root), marray = PUB(NSMutableArray, array);
    Class dict = PUB(NSDictionary, root), mdict = PUB(NSMutableDictionary, dict);
    Class set = PUB(NSSet, root), mset = PUB(NSMutableSet, set);
    Class data = PUB(NSData, root), mdata = PUB(NSMutableData, data);
    Class value = PUB(NSValue, root), number = PUB(NSNumber, value);
    Class date = PUB(NSDate, root), error = PUB(NSError, root), null = PUB(NSNull, root);
    Class locale = PUB(NSLocale, root), url = PUB(NSURL, root);
#undef PUB
    Class generic = public_class(calloc(1, sizeof(struct objc_class)), calloc(1, sizeof(struct objc_class)),
                                 root, "__NSCFType");
    Class cfstring = cf_class(CF_STRING, mstring, "__NSCFString");
    Class konst = make_class(&constant_string_class, &constant_string_meta, cfstring, "__NSCFConstantString", 0);
    dx_objc_register_class(konst);
    cf_class(CF_ARRAY, marray, "__NSCFArray");
    cf_class(CF_DICTIONARY, mdict, "__NSCFDictionary");
    cf_class(CF_SET, mset, "__NSCFSet");
    cf_class(CF_DATA, mdata, "__NSCFData");
    cf_class(CF_NUMBER, number, "__NSCFNumber");
    cf_class(CF_BOOLEAN, number, "__NSCFBoolean");
    cf_class(CF_DATE, date, "__NSCFDate");
    cf_class(CF_ERROR, error, "__NSCFError");
    cf_class(CF_NULL, null, "__NSCFNull");
    cf_class(CF_LOCALE, locale, "__NSCFLocale");
    cf_class(CF_URL, url, "__NSCFURL");
    cf_class(CF_ALLOCATOR, generic, "__NSCFAllocator");
    cf_class(CF_UUID, generic, "__NSCFUUID");
    cf_class(CF_SEC_CERTIFICATE, generic, "__NSCFSecCertificate");
    cf_class(CF_SEC_POLICY, generic, "__NSCFSecPolicy");
    cf_class(CF_SEC_TRUST, generic, "__NSCFSecTrust");
}
