/* The display's shared state, for its viewers: the browser page
 * (display.c) and X11 windows (x11.c). Guarded by display_lock; every
 * change bumps display_version and calls display_changed(). */
#pragma once
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>

struct window {
    uint32_t id;
    int32_t x, y;
    uint32_t width, height;
    char title[256];
    uint32_t flags;                        /* BITTEN_DISPLAY_BORDERLESS, _TRANSPARENT */
    int32_t level;                         /* NSWindow level: 0 normal, 3 floating, 101 pop-up menu, ... */
    uint32_t front;                        /* bumped by each order-front */
    uint8_t *rgba;                         /* straight alpha; NULL until the first frame */
    uint64_t version;
    /* Since full_version, only these rects changed (each at its version):
     * a viewer that saw full_version or later needs just their union. */
    uint64_t full_version;
    struct { uint64_t version; uint32_t x, y, w, h; } damage[16];
    int ndamage;
    bool closed;
    struct window *next;
};

struct bitten_display_event {
    uint32_t type;                         /* see enum below */
    uint32_t window;
    double x, y;                           /* in the window, origin top left; EV_MOVE: on the screen */
    double dx, dy;                         /* scroll deltas */
    uint32_t button;
    uint32_t modifiers;                    /* NSEventModifierFlags bits */
    uint32_t key_code;                     /* Mac virtual key code */
    char characters[32];                   /* UTF-8 */
    double width, height;                  /* resize */
};

enum {
    EV_MOUSE_DOWN = 1, EV_MOUSE_UP = 2, EV_MOUSE_MOVED = 3, EV_MOUSE_DRAGGED = 4, EV_SCROLL = 5,
    EV_KEY_DOWN = 6, EV_KEY_UP = 7, EV_CLOSE = 8, EV_RESIZE = 9, EV_MOVE = 10,
};

extern pthread_mutex_t display_lock;
extern struct window *display_windows;
extern uint64_t display_version;

void display_changed(void);                /* with display_lock held */
void display_push_event(const struct bitten_display_event *e);

/* Show the windows as X11 windows on $DISPLAY; false when that is not
 * possible (no libX11, no server), and the browser page is used instead. */
bool display_x11_start(void);
/* Readable when the X11 viewer should look at the windows again; -1 when none. */
extern int display_x11_wake_fd;
