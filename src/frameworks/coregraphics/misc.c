/* CoreGraphics: the window-server side programs query (window lists, event
 * sources) and CGEvent objects. There is no window server: the window list
 * is empty, no button is pressed and no input has arrived. CGEvents are
 * value holders, so programs that read and write their fields work. */
#include <string.h>
#include <time.h>

#include "cg.h"

struct cf_string *d___CFStringMakeConstantString(const char *bytes);
typedef const void *CFArrayRef;

#define KEY(name)                                                                \
    static const void *d_##name;                                                 \
    DX_EXPORT("_" #name, &d_##name)
KEY(kCGWindowNumber);
KEY(kCGWindowStoreType);
KEY(kCGWindowLayer);
KEY(kCGWindowBounds);
KEY(kCGWindowSharingState);
KEY(kCGWindowAlpha);
KEY(kCGWindowOwnerPID);
KEY(kCGWindowMemoryUsage);
KEY(kCGWindowOwnerName);
KEY(kCGWindowName);
KEY(kCGWindowIsOnscreen);
KEY(kCGWindowBackingLocationVideoMemory);

__attribute__((constructor)) static void window_keys(void) {
#define SET(n, v) d_##n = d___CFStringMakeConstantString(v)
    SET(kCGWindowNumber, "kCGWindowNumber");
    SET(kCGWindowStoreType, "kCGWindowStoreType");
    SET(kCGWindowLayer, "kCGWindowLayer");
    SET(kCGWindowBounds, "kCGWindowBounds");
    SET(kCGWindowSharingState, "kCGWindowSharingState");
    SET(kCGWindowAlpha, "kCGWindowAlpha");
    SET(kCGWindowOwnerPID, "kCGWindowOwnerPID");
    SET(kCGWindowMemoryUsage, "kCGWindowMemoryUsage");
    SET(kCGWindowOwnerName, "kCGWindowOwnerName");
    SET(kCGWindowName, "kCGWindowName");
    SET(kCGWindowIsOnscreen, "kCGWindowIsOnscreen");
    SET(kCGWindowBackingLocationVideoMemory, "kCGWindowBackingLocationVideoMemory");
#undef SET
}

static CFArrayRef d_CGWindowListCopyWindowInfo(uint32_t option, uint32_t relativeTo) {
    return d_CFArrayCreate(NULL, NULL, 0, dx_registry_lookup("_kCFTypeArrayCallBacks"));
}
DX_FN(CGWindowListCopyWindowInfo);

static CFArrayRef d_CGWindowListCreate(uint32_t option, uint32_t relativeTo) {
    return d_CFArrayCreate(NULL, NULL, 0, NULL);
}
DX_FN(CGWindowListCreate);

/* ---- event sources ----------------------------------------------------------------- */

static bool d_CGEventSourceButtonState(int stateID, uint32_t button) { return false; }
DX_FN(CGEventSourceButtonState);
static bool d_CGEventSourceKeyState(int stateID, uint16_t key) { return false; }
DX_FN(CGEventSourceKeyState);
static uint64_t d_CGEventSourceFlagsState(int stateID) { return 0; }
DX_FN(CGEventSourceFlagsState);

/* No input ever arrives: the time since the last event is the time since
 * the process started. */
static double d_CGEventSourceSecondsSinceLastEventType(int stateID, uint32_t type) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    static double start = -1;
    double now = t.tv_sec + t.tv_nsec / 1e9;
    if (start < 0) start = now;
    return now - start;
}
DX_FN(CGEventSourceSecondsSinceLastEventType);

/* ---- events ---------------------------------------------------------------------------- */

struct cg_event {
    struct cf_object base;
    uint32_t type;
    uint64_t flags, timestamp;
    CGPoint location;
    int64_t integers[256];
    double doubles[256];
};
static const struct cf_ops event_ops = {NULL, NULL, NULL, NULL};

static struct cg_event *event_new(void) { return cf_alloc(NULL, sizeof(struct cg_event), CF_CG_EVENT, &event_ops); }

static struct cg_event *d_CGEventCreate(const void *source) { return event_new(); }
DX_FN(CGEventCreate);

static struct cg_event *d_CGEventCreateCopy(const struct cg_event *e) {
    if (!e) return NULL;
    struct cg_event *c = event_new();
    if (!c) return NULL;
    struct cf_object base = c->base;
    memcpy(c, e, sizeof *c);
    c->base = base;
    return c;
}
DX_FN(CGEventCreateCopy);

static struct cg_event *d_CGEventCreateKeyboardEvent(const void *source, uint16_t key, bool down) {
    struct cg_event *e = event_new();
    if (e) {
        e->type = down ? 10 : 11;                     /* kCGEventKeyDown / KeyUp */
        e->integers[9] = key;                         /* kCGKeyboardEventKeycode */
    }
    return e;
}
DX_FN(CGEventCreateKeyboardEvent);

static struct cg_event *d_CGEventCreateMouseEvent(const void *source, uint32_t type, CGPoint at, uint32_t button) {
    struct cg_event *e = event_new();
    if (e) {
        e->type = type;
        e->location = at;
        e->integers[3] = button;                      /* kCGMouseEventButtonNumber */
    }
    return e;
}
DX_FN(CGEventCreateMouseEvent);

static uint32_t d_CGEventGetType(const struct cg_event *e) { return e ? e->type : 0; }
DX_FN(CGEventGetType);
static void d_CGEventSetType(struct cg_event *e, uint32_t t) { if (e) e->type = t; }
DX_FN(CGEventSetType);
static uint64_t d_CGEventGetFlags(const struct cg_event *e) { return e ? e->flags : 0; }
DX_FN(CGEventGetFlags);
static void d_CGEventSetFlags(struct cg_event *e, uint64_t f) { if (e) e->flags = f; }
DX_FN(CGEventSetFlags);
static uint64_t d_CGEventGetTimestamp(const struct cg_event *e) { return e ? e->timestamp : 0; }
DX_FN(CGEventGetTimestamp);
static void d_CGEventSetTimestamp(struct cg_event *e, uint64_t t) { if (e) e->timestamp = t; }
DX_FN(CGEventSetTimestamp);
static CGPoint d_CGEventGetLocation(const struct cg_event *e) { return e ? e->location : (CGPoint){0, 0}; }
DX_FN(CGEventGetLocation);
static void d_CGEventSetLocation(struct cg_event *e, CGPoint p) { if (e) e->location = p; }
DX_FN(CGEventSetLocation);
static int64_t d_CGEventGetIntegerValueField(const struct cg_event *e, uint32_t f) { return e && f < 256 ? e->integers[f] : 0; }
DX_FN(CGEventGetIntegerValueField);
static void d_CGEventSetIntegerValueField(struct cg_event *e, uint32_t f, int64_t v) { if (e && f < 256) e->integers[f] = v; }
DX_FN(CGEventSetIntegerValueField);
static double d_CGEventGetDoubleValueField(const struct cg_event *e, uint32_t f) { return e && f < 256 ? e->doubles[f] : 0; }
DX_FN(CGEventGetDoubleValueField);
static void d_CGEventSetDoubleValueField(struct cg_event *e, uint32_t f, double v) { if (e && f < 256) e->doubles[f] = v; }
DX_FN(CGEventSetDoubleValueField);
/* No window server takes events. */
static void d_CGEventPost(int tap, const struct cg_event *e) {}
DX_FN(CGEventPost);
CF_TYPE_ID(CGEvent, CF_CG_EVENT);
