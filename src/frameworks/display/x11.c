/* The display as X11 windows: each Mac window becomes a window on
 * $DISPLAY, drawn from the frames AppKit presents, with mouse, scroll and
 * keyboard input sent back as the browser page sends it. Chosen with
 * BITTEN_DISPLAY=x11. libX11 is loaded at run time, so mrun does not need
 * it unless this is used; the decision is in docs/DECISIONS.md.
 *
 * Keys are mapped by position (as the page maps KeyboardEvent.code) to Mac
 * virtual key codes; Super is Command, Alt is Option. */
#include "display.h"
#include "dx.h"

#if __has_include(<X11/Xlib.h>)
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <dlfcn.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <unistd.h>

#define X_FUNCS(F)                                                                                      \
    F(XOpenDisplay) F(XInternAtom) F(XMatchVisualInfo) F(XCreateColormap) F(XCreateWindow)             \
    F(XDestroyWindow) F(XChangeProperty) F(XSetWMProtocols) F(XSetWMNormalHints) F(XStoreName)          \
    F(XMapRaised) F(XRaiseWindow) F(XResizeWindow) F(XCreateGC) F(XFreeGC) F(XCreateImage) F(XPutImage) \
    F(XPending) F(XNextEvent) F(XFlush) F(XLookupString) F(XTranslateCoordinates)
#define DECLARE(f) static __typeof__(&f) p##f;
X_FUNCS(DECLARE)

static Display *dpy;
static Window root;
static Visual *visual24, *visual32;
static Colormap colormap32;
static Atom wm_delete, wm_protocols, net_wm_name, utf8_string, motif_hints, net_wm_state, net_wm_state_above,
    net_wm_type, net_wm_type_menu;

struct xwin {
    uint32_t id;
    Window xw;
    GC gc;
    XImage *image;
    uint32_t width, height;                /* the last frame's size */
    uint32_t flags, front;
    int32_t level;
    int x, y;                              /* where the window is on the screen, as last known */
    char title[256];
    struct xwin *next;
};
static struct xwin *xwins;

static struct xwin *by_window(Window xw) {
    for (struct xwin *x = xwins; x; x = x->next)
        if (x->xw == xw) return x;
    return NULL;
}

static void destroy(struct xwin *x) {
    if (x->image) {
        free(x->image->data);
        x->image->data = NULL;
        XDestroyImage(x->image);
    }
    if (x->gc) pXFreeGC(dpy, x->gc);
    if (x->xw) pXDestroyWindow(dpy, x->xw);
    x->image = NULL;
    x->gc = NULL;
    x->xw = 0;
}

static bool popup(int32_t level) { return level >= 101; }       /* NSPopUpMenuWindowLevel and up */
static bool see_through(uint32_t flags) { return (flags & 2) && visual32; }

static void create(struct xwin *x, const struct window *w) {
    bool argb = see_through(w->flags);
    XSetWindowAttributes a = {0};
    a.colormap = argb ? colormap32 : DefaultColormap(dpy, DefaultScreen(dpy));
    a.border_pixel = 0;
    a.background_pixel = argb ? 0 : 0xececec;
    a.override_redirect = popup(w->level);
    a.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask | KeyPressMask |
                   KeyReleaseMask | StructureNotifyMask;
    x->xw = pXCreateWindow(dpy, root, w->x, w->y, w->width, w->height, 0, argb ? 32 : DefaultDepth(dpy, DefaultScreen(dpy)),
                           InputOutput, argb ? visual32 : visual24,
                           CWColormap | CWBorderPixel | CWBackPixel | CWOverrideRedirect | CWEventMask, &a);
    x->gc = pXCreateGC(dpy, x->xw, 0, NULL);
    x->x = w->x;
    x->y = w->y;
    x->flags = w->flags;
    x->level = w->level;
    x->front = w->front;
    x->title[0] = 0;
    pXSetWMProtocols(dpy, x->xw, &wm_delete, 1);
    XSizeHints hints = {.flags = USPosition | PPosition, .x = w->x, .y = w->y};
    pXSetWMNormalHints(dpy, x->xw, &hints);
    pXChangeProperty(dpy, x->xw, XA_WM_CLASS, XA_STRING, 8, PropModeReplace, (const unsigned char *)"bitten\0Bitten", 14);
    if (popup(w->level)) {
        pXChangeProperty(dpy, x->xw, net_wm_type, XA_ATOM, 32, PropModeReplace, (unsigned char *)&net_wm_type_menu, 1);
    } else {
        if (w->flags & 1) {
            long motif[5] = {2, 0, 0, 0, 0};                /* MWM_HINTS_DECORATIONS: none */
            pXChangeProperty(dpy, x->xw, motif_hints, motif_hints, 32, PropModeReplace, (unsigned char *)motif, 5);
        }
        if (w->level > 0)
            pXChangeProperty(dpy, x->xw, net_wm_state, XA_ATOM, 32, PropModeReplace, (unsigned char *)&net_wm_state_above, 1);
    }
    pXMapRaised(dpy, x->xw);
}

/* A frame in the window's visual: opaque windows over the page's grey,
 * see-through ones premultiplied. */
static void paint(struct xwin *x, const struct window *w) {
    bool argb = see_through(w->flags);
    if (!x->image || x->width != w->width || x->height != w->height) {
        if (x->image) {
            free(x->image->data);
            x->image->data = NULL;
            XDestroyImage(x->image);
        }
        char *data = malloc((size_t)w->width * w->height * 4 + 4);
        if (!data) { x->image = NULL; return; }
        x->image = pXCreateImage(dpy, argb ? visual32 : visual24, argb ? 32 : DefaultDepth(dpy, DefaultScreen(dpy)),
                                 ZPixmap, 0, data, w->width, w->height, 32, 0);
        if (!x->image) { free(data); return; }
    }
    uint32_t *out = (uint32_t *)x->image->data;
    size_t n = (size_t)w->width * w->height;
    for (size_t i = 0; i < n; i++) {
        const uint8_t *p = w->rgba + i * 4;
        uint32_t a = p[3], r, g, b;
        if (argb) {
            r = p[0] * a / 255; g = p[1] * a / 255; b = p[2] * a / 255;
        } else {
            r = (p[0] * a + 0xec * (255 - a)) / 255;
            g = (p[1] * a + 0xec * (255 - a)) / 255;
            b = (p[2] * a + 0xec * (255 - a)) / 255;
            a = 255;
        }
        out[i] = a << 24 | r << 16 | g << 8 | b;
    }
}

static void put(struct xwin *x) {
    if (x->image) pXPutImage(dpy, x->xw, x->gc, x->image, 0, 0, 0, 0, x->width, x->height);
}

/* Bring the X windows up to date with the display's windows. */
static void sync_windows(void) {
    static uint64_t seen;
    pthread_mutex_lock(&display_lock);
    if (display_version == seen) {
        pthread_mutex_unlock(&display_lock);
        return;
    }
    uint64_t since = seen;
    seen = display_version;
    for (struct window *w = display_windows; w; w = w->next) {
        if (w->version <= since) continue;
        struct xwin *x = xwins;
        while (x && x->id != w->id) x = x->next;
        if (w->closed) {
            if (x) destroy(x);
            continue;
        }
        if (!w->rgba) continue;                          /* a style before the first frame */
        if (!x) {
            x = calloc(1, sizeof *x);
            if (!x) continue;
            x->id = w->id;
            x->next = xwins;
            xwins = x;
        }
        if (x->xw && (see_through(x->flags) != see_through(w->flags) || popup(x->level) != popup(w->level) ||
                      (x->flags & 1) != (w->flags & 1)))
            destroy(x);
        bool fresh = !x->xw;
        if (fresh) create(x, w);
        else if (x->width != w->width || x->height != w->height) pXResizeWindow(dpy, x->xw, w->width, w->height);
        if (strcmp(x->title, w->title)) {
            snprintf(x->title, sizeof x->title, "%s", w->title);
            pXStoreName(dpy, x->xw, x->title);
            pXChangeProperty(dpy, x->xw, net_wm_name, utf8_string, 8, PropModeReplace, (unsigned char *)x->title,
                             (int)strlen(x->title));
        }
        if (!fresh && x->front != w->front) pXRaiseWindow(dpy, x->xw);
        x->front = w->front;
        x->flags = w->flags;
        x->level = w->level;
        paint(x, w);
        x->width = w->width;
        x->height = w->height;
        put(x);
    }
    pthread_mutex_unlock(&display_lock);
    pXFlush(dpy);
}

/* ---- input ------------------------------------------------------------------------ */

/* Linux evdev key codes (X key code - 8) to Mac virtual key codes plus one; 0: none. */
#define K(code) ((code) + 1)
static const uint8_t MAC_KEYS[128] = {
    [1] = K(53), [2] = K(18), [3] = K(19), [4] = K(20), [5] = K(21), [6] = K(23), [7] = K(22), [8] = K(26), [9] = K(28), [10] = K(25),
    [11] = K(29), [12] = K(27), [13] = K(24), [14] = K(51), [15] = K(48), [16] = K(12), [17] = K(13), [18] = K(14), [19] = K(15),
    [20] = K(17), [21] = K(16), [22] = K(32), [23] = K(34), [24] = K(31), [25] = K(35), [26] = K(33), [27] = K(30), [28] = K(36),
    [29] = K(59), [30] = K(0), [31] = K(1), [32] = K(2), [33] = K(3), [34] = K(5), [35] = K(4), [36] = K(38), [37] = K(40), [38] = K(37),
    [39] = K(41), [40] = K(39), [41] = K(50), [42] = K(56), [43] = K(42), [44] = K(6), [45] = K(7), [46] = K(8), [47] = K(9), [48] = K(11),
    [49] = K(45), [50] = K(46), [51] = K(43), [52] = K(47), [53] = K(44), [54] = K(60), [55] = K(67), [56] = K(58), [57] = K(49),
    [58] = K(57), [59] = K(122), [60] = K(120), [61] = K(99), [62] = K(118), [63] = K(96), [64] = K(97), [65] = K(98), [66] = K(100),
    [67] = K(101), [68] = K(109), [69] = K(71), [71] = K(89), [72] = K(91), [73] = K(92), [74] = K(78), [75] = K(86), [76] = K(87),
    [77] = K(88), [78] = K(69), [79] = K(83), [80] = K(84), [81] = K(85), [82] = K(82), [83] = K(65), [86] = K(10), [87] = K(103),
    [88] = K(111), [96] = K(76), [97] = K(62), [98] = K(75), [100] = K(61), [102] = K(115), [103] = K(126), [104] = K(116),
    [105] = K(123), [106] = K(124), [107] = K(119), [108] = K(125), [109] = K(121), [110] = K(114), [111] = K(117), [117] = K(81),
    [125] = K(55), [126] = K(54),
};

enum { CAPS = 1 << 16, SHIFT = 1 << 17, CONTROL = 1 << 18, OPTION = 1 << 19, COMMAND = 1 << 20 };

static uint32_t mac_modifiers(unsigned state) {
    return (state & LockMask ? CAPS : 0) | (state & ShiftMask ? SHIFT : 0) | (state & ControlMask ? CONTROL : 0) |
           (state & Mod1Mask ? OPTION : 0) | (state & Mod4Mask ? COMMAND : 0);
}

/* The flag a modifier key itself changes (X reports the state before the event). */
static uint32_t modifier_key(uint32_t code) {
    switch (code) {
    case 56: case 60: return SHIFT;
    case 59: case 62: return CONTROL;
    case 58: case 61: return OPTION;
    case 54: case 55: return COMMAND;
    case 57: return CAPS;
    }
    return 0;
}

static void utf8(uint32_t c, char *out) {
    if (c < 0x80) { out[0] = (char)c; out[1] = 0; }
    else if (c < 0x800) { out[0] = (char)(0xc0 | c >> 6); out[1] = (char)(0x80 | (c & 63)); out[2] = 0; }
    else if (c < 0x10000) {
        out[0] = (char)(0xe0 | c >> 12); out[1] = (char)(0x80 | (c >> 6 & 63)); out[2] = (char)(0x80 | (c & 63)); out[3] = 0;
    } else {
        out[0] = (char)(0xf0 | c >> 18); out[1] = (char)(0x80 | (c >> 12 & 63));
        out[2] = (char)(0x80 | (c >> 6 & 63)); out[3] = (char)(0x80 | (c & 63)); out[4] = 0;
    }
}

/* The characters a key types, ignoring Control (AppKit applies it), as the page sends them. */
static void key_characters(XKeyEvent *k, uint32_t code, char *out) {
    out[0] = 0;
    switch (code) {
    case 36: strcpy(out, "\r"); return;
    case 76: strcpy(out, "\x03"); return;
    case 48: strcpy(out, "\t"); return;
    case 51: strcpy(out, "\x7f"); return;
    case 53: strcpy(out, "\x1b"); return;
    }
    XKeyEvent plain = *k;
    plain.state &= ~(unsigned)ControlMask;
    char buf[16];
    KeySym sym = 0;
    pXLookupString(&plain, buf, sizeof buf, &sym, NULL);
    if ((sym >= 0x20 && sym <= 0x7e) || (sym >= 0xa0 && sym <= 0xff)) utf8((uint32_t)sym, out);
    else if ((sym & 0xff000000) == 0x01000000) utf8((uint32_t)(sym & 0xffffff), out);
}

static void handle(XEvent *ev) {
    struct xwin *x = by_window(ev->xany.window);
    if (!x) return;
    struct bitten_display_event e = {.window = x->id};
    static unsigned held;                                /* mouse buttons down: bit 0 left, 1 middle, 2 right */
    switch (ev->type) {
    case Expose:
        if (ev->xexpose.count == 0) put(x);
        return;
    case ButtonPress:
    case ButtonRelease: {
        unsigned b = ev->xbutton.button;
        e.x = ev->xbutton.x;
        e.y = ev->xbutton.y;
        e.modifiers = mac_modifiers(ev->xbutton.state);
        if (b >= 4 && b <= 7) {                          /* the wheel: 3 lines of 16 points a notch */
            if (ev->type == ButtonRelease) return;
            e.type = EV_SCROLL;
            e.dy = b == 4 ? 48 : b == 5 ? -48 : 0;
            e.dx = b == 6 ? 48 : b == 7 ? -48 : 0;
            break;
        }
        if (b < 1 || b > 3) return;
        e.button = b - 1;
        if (ev->type == ButtonPress) { held |= 1u << e.button; e.type = EV_MOUSE_DOWN; }
        else { held &= ~(1u << e.button); e.type = EV_MOUSE_UP; }
        break;
    }
    case MotionNotify:
        e.type = held ? EV_MOUSE_DRAGGED : EV_MOUSE_MOVED;
        e.x = ev->xmotion.x;
        e.y = ev->xmotion.y;
        e.button = held & 1 ? 0 : held & 4 ? 2 : held & 2 ? 1 : 0;
        e.modifiers = mac_modifiers(ev->xmotion.state);
        break;
    case KeyPress:
    case KeyRelease: {
        unsigned evdev = ev->xkey.keycode - 8;
        if (evdev >= 128 || !MAC_KEYS[evdev]) return;
        e.type = ev->type == KeyPress ? EV_KEY_DOWN : EV_KEY_UP;
        e.key_code = MAC_KEYS[evdev] - 1u;
        e.modifiers = mac_modifiers(ev->xkey.state);
        uint32_t own = modifier_key(e.key_code);
        if (own == CAPS) e.modifiers ^= CAPS;
        else if (ev->type == KeyPress) e.modifiers |= own;
        else e.modifiers &= ~own;
        key_characters(&ev->xkey, e.key_code, e.characters);
        break;
    }
    case ClientMessage:
        if (ev->xclient.message_type != wm_protocols || (Atom)ev->xclient.data.l[0] != wm_delete) return;
        e.type = EV_CLOSE;
        break;
    case ConfigureNotify: {
        if (ev->xconfigure.width != (int)x->width || ev->xconfigure.height != (int)x->height) {
            struct bitten_display_event r = e;
            r.type = EV_RESIZE;
            r.width = ev->xconfigure.width;
            r.height = ev->xconfigure.height;
            display_push_event(&r);
        }
        if (popup(x->level)) return;
        int sx, sy;
        Window child;
        if (!pXTranslateCoordinates(dpy, x->xw, root, 0, 0, &sx, &sy, &child) || (sx == x->x && sy == x->y)) return;
        x->x = sx;
        x->y = sy;
        e.type = EV_MOVE;
        e.x = sx;
        e.y = sy;
        break;
    }
    default:
        return;
    }
    display_push_event(&e);
}

static void *viewer(void *arg) {
    struct pollfd fds[2] = {{ConnectionNumber(dpy), POLLIN, 0}, {display_x11_wake_fd, POLLIN, 0}};
    for (;;) {
        sync_windows();
        while (pXPending(dpy)) {
            XEvent ev;
            pXNextEvent(dpy, &ev);
            handle(&ev);
        }
        pXFlush(dpy);
        if (poll(fds, 2, -1) < 0) continue;
        if (fds[1].revents & POLLIN) {
            uint64_t drain;
            (void)!read(display_x11_wake_fd, &drain, sizeof drain);
        }
    }
    return arg;
}

bool display_x11_start(void) {
    void *lib = dlopen("libX11.so.6", RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        dx_log(0, "display: cannot load libX11: %s", dlerror());
        return false;
    }
#define LOAD(f) if (!(p##f = (__typeof__(&f))dlsym(lib, #f))) return false;
    X_FUNCS(LOAD)
    dpy = pXOpenDisplay(NULL);
    if (!dpy) return false;
    int screen = DefaultScreen(dpy);
    root = RootWindow(dpy, screen);
    visual24 = DefaultVisual(dpy, screen);
    XVisualInfo vi;
    if (pXMatchVisualInfo(dpy, screen, 32, TrueColor, &vi)) {
        visual32 = vi.visual;
        colormap32 = pXCreateColormap(dpy, root, visual32, AllocNone);
    }
    wm_protocols = pXInternAtom(dpy, "WM_PROTOCOLS", False);
    wm_delete = pXInternAtom(dpy, "WM_DELETE_WINDOW", False);
    net_wm_name = pXInternAtom(dpy, "_NET_WM_NAME", False);
    utf8_string = pXInternAtom(dpy, "UTF8_STRING", False);
    motif_hints = pXInternAtom(dpy, "_MOTIF_WM_HINTS", False);
    net_wm_state = pXInternAtom(dpy, "_NET_WM_STATE", False);
    net_wm_state_above = pXInternAtom(dpy, "_NET_WM_STATE_ABOVE", False);
    net_wm_type = pXInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
    net_wm_type_menu = pXInternAtom(dpy, "_NET_WM_WINDOW_TYPE_POPUP_MENU", False);
    /* AppKit's screen is this one, unless BITTEN_SCREEN says otherwise. */
    if (!getenv("BITTEN_SCREEN")) {
        char size[32];
        snprintf(size, sizeof size, "%dx%d", DisplayWidth(dpy, screen), DisplayHeight(dpy, screen));
        setenv("BITTEN_SCREEN", size, 0);
    }
    display_x11_wake_fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    pthread_t t;
    if (display_x11_wake_fd < 0 || pthread_create(&t, NULL, viewer, NULL)) return false;
    pthread_detach(t);
    dx_log(0, "display: windows on X11 display %s", DisplayString(dpy));
    return true;
}

#else
bool display_x11_start(void) {
    dx_log(0, "display: built without X11 headers (libx11-dev)");
    return false;
}
#endif
