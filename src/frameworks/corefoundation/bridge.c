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

/* The classes of compiler-emitted constant collections and numbers
 * (`@[...]`, `@{...}`, `@42` in newer clang). Their storage is the
 * compiler's: arrays {isa, count, objects}, dictionaries {isa, options,
 * count, keys, objects}, integers {isa, encoding, value}, floats and
 * doubles {isa, value}. Like constant strings, CF functions resolve them to
 * an immortal CF object made on first use. */
static struct objc_class constant_array_class, constant_array_meta, constant_dict_class, constant_dict_meta,
    constant_int_class, constant_int_meta, constant_float_class, constant_float_meta, constant_double_class,
    constant_double_meta;
DX_EXPORT("_OBJC_CLASS_$_NSConstantArray", &constant_array_class);
DX_EXPORT("_OBJC_CLASS_$_NSConstantDictionary", &constant_dict_class);
DX_EXPORT("_OBJC_CLASS_$_NSConstantIntegerNumber", &constant_int_class);
DX_EXPORT("_OBJC_CLASS_$_NSConstantFloatNumber", &constant_float_class);
DX_EXPORT("_OBJC_CLASS_$_NSConstantDoubleNumber", &constant_double_class);

static int is_constant_literal(const void *object) {
    if (!object || ((uintptr_t)object & 1)) return 0;
    const void *isa = *(void *const *)object;
    return isa == &constant_array_class || isa == &constant_dict_class || isa == &constant_int_class ||
           isa == &constant_float_class || isa == &constant_double_class;
}
int cf_is_constant(const void *object) { return cf_is_constant_string(object) || is_constant_literal(object); }

struct const_array { void *isa; unsigned long count; const void *const *objects; };
struct const_dict { void *isa; unsigned long options, count; const void *const *keys, *const *objects; };
struct const_int { void *isa; const char *encoding; long long value; };
struct const_float { void *isa; float value; };
struct const_double { void *isa; double value; };

static const void *make_literal(const void *object) {
    const void *isa = *(void *const *)object;
    if (isa == &constant_array_class) {
        const struct const_array *a = object;
        const void *(*create)(const void *, const void *const *, CFIndex, const void *) =
            dx_registry_lookup("_CFArrayCreate");
        return create(NULL, a->objects, (CFIndex)a->count, dx_registry_lookup("_kCFTypeArrayCallBacks"));
    }
    if (isa == &constant_dict_class) {
        const struct const_dict *d = object;
        const void *(*create)(const void *, const void *const *, const void *const *, CFIndex, const void *,
                              const void *) = dx_registry_lookup("_CFDictionaryCreate");
        return create(NULL, d->keys, d->objects, (CFIndex)d->count, dx_registry_lookup("_kCFTypeDictionaryKeyCallBacks"),
                      dx_registry_lookup("_kCFTypeDictionaryValueCallBacks"));
    }
    const void *(*number)(const void *, CFIndex, const void *) = dx_registry_lookup("_CFNumberCreate");
    if (isa == &constant_int_class) {
        const struct const_int *n = object;
        if (n->encoding && (n->encoding[0] == 'c' || n->encoding[0] == 'B')) {
            const void *const *b = dx_registry_lookup(n->value ? "_kCFBooleanTrue" : "_kCFBooleanFalse");
            return *b;
        }
        return number(NULL, 11 /* kCFNumberLongLongType */, &n->value);
    }
    if (isa == &constant_float_class) return number(NULL, 12 /* kCFNumberFloatType */, &((const struct const_float *)object)->value);
    return number(NULL, 13 /* kCFNumberDoubleType */, &((const struct const_double *)object)->value);
}

int cf_is_cf(const void *object) {
    if (!object || ((uintptr_t)object & 1)) return 0;
    const void *isa = *(void *const *)object;
    return (isa >= (const void *)&cf_classes[0] && isa < (const void *)&cf_classes[CF_TYPE_MAX]) ||
           isa == (const void *)&constant_string_class || is_constant_literal(object);
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
    if (!cf_is_constant(object)) return object;
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
        shadows[i].string = cf_is_constant_string(object) ? cf_string_from_constant(object)
                                                          : (struct cf_string *)make_literal(object);
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
    Class cfarray = cf_class(CF_ARRAY, marray, "__NSCFArray");
    Class cfdict = cf_class(CF_DICTIONARY, mdict, "__NSCFDictionary");
    dx_objc_register_class(make_class(&constant_array_class, &constant_array_meta, cfarray, "NSConstantArray", 0));
    dx_objc_register_class(make_class(&constant_dict_class, &constant_dict_meta, cfdict, "NSConstantDictionary", 0));
    cf_class(CF_SET, mset, "__NSCFSet");
    cf_class(CF_DATA, mdata, "__NSCFData");
    Class cfnumber = cf_class(CF_NUMBER, number, "__NSCFNumber");
    dx_objc_register_class(make_class(&constant_int_class, &constant_int_meta, cfnumber, "NSConstantIntegerNumber", 0));
    dx_objc_register_class(make_class(&constant_float_class, &constant_float_meta, cfnumber, "NSConstantFloatNumber", 0));
    dx_objc_register_class(make_class(&constant_double_class, &constant_double_meta, cfnumber, "NSConstantDoubleNumber", 0));
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
    cf_class(CF_CG_COLORSPACE, generic, "__NSCFCGColorSpace");
    cf_class(CF_CG_COLOR, generic, "__NSCFCGColor");
    cf_class(CF_CG_PATH, generic, "__NSCFCGPath");
    cf_class(CF_CG_CONTEXT, generic, "__NSCFCGContext");
    cf_class(CF_CG_IMAGE, generic, "__NSCFCGImage");
    cf_class(CF_CG_GRADIENT, generic, "__NSCFCGGradient");
    cf_class(CF_CG_PROVIDER, generic, "__NSCFCGDataProvider");
    cf_class(CF_CG_EVENT, generic, "__NSCFCGEvent");
    cf_class(CF_ATTRIBUTED_STRING, generic, "__NSCFAttributedString");
    cf_class(CF_CT_FONT, generic, "__NSCFCTFont");
    cf_class(CF_CT_DESCRIPTOR, generic, "__NSCFCTFontDescriptor");
    cf_class(CF_CT_LINE, generic, "__NSCFCTLine");
    cf_class(CF_CT_RUN, generic, "__NSCFCTRun");
    cf_class(CF_CT_COLLECTION, generic, "__NSCFCTFontCollection");
    cf_class(CF_SEC_CODE, generic, "__NSCFSecCode");
    cf_class(CF_SEC_TRANSFORM, generic, "__NSCFSecTransform");
    cf_class(CF_SEC_ACCESS_CONTROL, generic, "__NSCFSecAccessControl");
    cf_class(CF_CG_IMAGE_SOURCE, generic, "__NSCFCGImageSource");
}
