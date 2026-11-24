#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "dx.h"

struct selector {
    struct selector *next;
    char name[];
};
static struct selector *selectors;
static pthread_mutex_t selector_lock = PTHREAD_MUTEX_INITIALIZER;

static const char *d_sel_registerName(const char *name) {
    if (!name) return NULL;
    pthread_mutex_lock(&selector_lock);
    struct selector *sel = selectors;
    while (sel && strcmp(sel->name, name)) sel = sel->next;
    if (!sel) {
        size_t n = strlen(name) + 1;
        sel = malloc(sizeof *sel + n);
        if (sel) {
            memcpy(sel->name, name, n);
            sel->next = selectors;
            selectors = sel;
        }
    }
    pthread_mutex_unlock(&selector_lock);
    return sel ? sel->name : NULL;
}
DX_FN(sel_registerName);
DX_EXPORT("_sel_getUid", d_sel_registerName);

static const char *d_sel_getName(const char *sel) { return sel ? sel : "<null selector>"; }
DX_FN(sel_getName);

static void d_objc_msgSend(void *receiver, const char *sel) {
    const char *name = NULL;
    if (sel) {
        pthread_mutex_lock(&selector_lock);
        for (const struct selector *s = selectors; s; s = s->next)
            if (s->name == sel) { name = sel; break; }
        pthread_mutex_unlock(&selector_lock);
    }
    dx_fatal("objc_msgSend called: the Objective-C runtime is not implemented yet (selector %s)",
             name ? name : "<unknown>");
}
DX_FN(objc_msgSend);

static void *d_objc_getClass(const char *name) {
    dx_log(1, "Objective-C class lookup: %s", name ? name : "<null>");
    return NULL;
}
DX_FN(objc_getClass);
DX_EXPORT("_objc_lookUpClass", d_objc_getClass);

static void *d_objc_autoreleasePoolPush(void) {
    static char token;
    return &token;
}
DX_FN(objc_autoreleasePoolPush);

static void d_objc_autoreleasePoolPop(void *token) {}
DX_FN(objc_autoreleasePoolPop);
