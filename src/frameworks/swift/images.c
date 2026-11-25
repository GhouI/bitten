/* Swift metadata sections of loaded images. The loader calls
 * dx_swift_image_added for every image once its fixups are applied; the
 * conformance, type and field lookups walk the recorded sections. */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "swift_internal.h"

static const char *const section_names[SW_SECT_COUNT] = {
    [SW_SECT_TYPES] = "__swift5_types",     [SW_SECT_TYPES2] = "__swift5_types2",
    [SW_SECT_PROTO] = "__swift5_proto",     [SW_SECT_PROTOS] = "__swift5_protos",
    [SW_SECT_FIELDMD] = "__swift5_fieldmd", [SW_SECT_ASSOCTY] = "__swift5_assocty",
    [SW_SECT_BUILTIN] = "__swift5_builtin", [SW_SECT_CAPTURE] = "__swift5_capture",
    [SW_SECT_TYPEREF] = "__swift5_typeref", [SW_SECT_REFLSTR] = "__swift5_reflstr",
    [SW_SECT_MPENUM] = "__swift5_mpenum",
};

struct listener {
    struct listener *next;
    int which;
    sw_section_cb cb;
    void *ctx;
};

static pthread_mutex_t lock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;
static struct sw_section *sections[SW_SECT_COUNT];
static size_t counts[SW_SECT_COUNT], caps[SW_SECT_COUNT];
static struct listener *listeners;

void dx_swift_image_added(const struct dx_image *img) {
    sw_array_image_added((struct dx_image *)img);
    pthread_mutex_lock(&lock);
    for (int w = 0; w < SW_SECT_COUNT; w++) {
        size_t size;
        const void *start = dx_image_section(img, section_names[w], &size);
        if (!start || !size) continue;
        if (counts[w] == caps[w]) {
            caps[w] = caps[w] ? caps[w] * 2 : 16;
            sections[w] = realloc(sections[w], caps[w] * sizeof *sections[w]);
        }
        struct sw_section s = {start, size};
        sections[w][counts[w]++] = s;
        for (struct listener *l = listeners; l; l = l->next)
            if (l->which == w) l->cb(&s, l->ctx);
    }
    pthread_mutex_unlock(&lock);
}

void sw_each_section(int which, sw_section_cb cb, void *ctx, int future) {
    if (which < 0 || which >= SW_SECT_COUNT) return;
    pthread_mutex_lock(&lock);
    for (size_t i = 0; i < counts[which]; i++) cb(&sections[which][i], ctx);
    if (future) {
        struct listener *l = malloc(sizeof *l);
        l->which = which;
        l->cb = cb;
        l->ctx = ctx;
        l->next = listeners;
        listeners = l;
    }
    pthread_mutex_unlock(&lock);
}
