/* The display: windows shown in a browser.
 *
 * AppKit draws each window into a bitmap (a CGBitmapContext) and hands it
 * here with bitten_display_present(). A small HTTP server in mrun (port
 * BITTEN_DISPLAY_PORT, 7681 by default; 0 picks a free port) serves a page
 * that draws every window on a canvas, over a WebSocket, and sends mouse,
 * scroll and keyboard input back; AppKit takes that input with
 * bitten_display_next_event() (or waits on bitten_display_event_fd()).
 * The decision is recorded in docs/DECISIONS.md.
 *
 * Coordinates are pixels with the origin at the top left: a window's
 * position on the page, and event locations within a window. Mac screen
 * coordinates (origin bottom left) are AppKit's to convert.
 *
 * Protocol, server to page, binary messages:
 *   1 (frame): u8 1, u32 window, i32 x, i32 y, u32 width, u32 height,
 *     u16 title length, title (UTF-8), then width*height RGBA bytes
 *     (straight alpha, as canvas ImageData wants)
 *   2 (close): u8 2, u32 window
 *   3 (part of a frame): as 1 up to the title, then u32 x, u32 y, u32
 *     width, u32 height of a rect in the window, and its RGBA bytes; the
 *     rest of the window is as the last frame left it
 * page to server, text messages, one JSON object each:
 *   {"t":"down"|"up"|"move"|"drag"|"scroll"|"key"|"keyup"|"close"|"resize"|
 *        "miniaturize"|"zoom"|"deminiaturize",
 *    "w":window, "x":..., "y":..., "b":button, "m":modifier flags,
 *    "k":virtual key code, "c":"characters", "dx":..., "dy":..., "cw":..., "ch":...}
 * Integers are little-endian. */
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <unistd.h>

#include "dx.h"
#include "../coregraphics/cg.h"

#include "display.h"
#include "page.h"                          /* the page: DISPLAY_PAGE */

/* ---- windows ------------------------------------------------------------------ */

pthread_mutex_t display_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
struct window *display_windows;
uint64_t display_version;                  /* bumped by every change */
int display_x11_wake_fd = -1;

void display_changed(void) {
    pthread_cond_broadcast(&changed);
    uint64_t one = 1;
    if (display_x11_wake_fd >= 0) (void)!write(display_x11_wake_fd, &one, sizeof one);
}

static struct window *find(uint32_t id) {
    for (struct window *w = display_windows; w; w = w->next)
        if (w->id == id) return w;
    return NULL;
}
static struct window *find_or_add(uint32_t id) {
    struct window *w = find(id);
    if (w) return w;
    w = calloc(1, sizeof *w);
    if (!w) return NULL;
    w->id = id;
    w->next = display_windows;
    display_windows = w;
    return w;
}

/* ---- events ---------------------------------------------------------------------- */

#define QUEUE 1024
static struct bitten_display_event queue[QUEUE];
static size_t q_head, q_count;
static int event_fd = -1;

void display_push_event(const struct bitten_display_event *e) {
    pthread_mutex_lock(&display_lock);
    if (q_count == QUEUE) {                /* drop the oldest */
        q_head = (q_head + 1) % QUEUE;
        q_count--;
    }
    queue[(q_head + q_count) % QUEUE] = *e;
    q_count++;
    pthread_mutex_unlock(&display_lock);
    uint64_t one = 1;
    if (event_fd >= 0) (void)!write(event_fd, &one, sizeof one);
}

/* ---- the server ------------------------------------------------------------------------ */

static int listen_fd = -1, server_port, requested_port = -1;
static pthread_once_t started = PTHREAD_ONCE_INIT;

static bool send_all(int fd, const void *p, size_t n) {
    const uint8_t *b = p;
    while (n) {
        ssize_t k = send(fd, b, n, MSG_NOSIGNAL);
        if (k < 0 && errno == EINTR) continue;
        if (k <= 0) return false;
        b += k;
        n -= (size_t)k;
    }
    return true;
}

static void base64(const uint8_t *in, size_t n, char *out) {
    static const char t[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t o = 0;
    for (size_t i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)in[i] << 16 | (i + 1 < n ? (uint32_t)in[i + 1] << 8 : 0) | (i + 2 < n ? in[i + 2] : 0);
        out[o++] = t[v >> 18 & 63];
        out[o++] = t[v >> 12 & 63];
        out[o++] = i + 1 < n ? t[v >> 6 & 63] : '=';
        out[o++] = i + 2 < n ? t[v & 63] : '=';
    }
    out[o] = 0;
}

/* A WebSocket message (unmasked, as servers send). */
static bool ws_send(int fd, int opcode, const void *data, size_t n) {
    uint8_t h[10];
    size_t hl = 2;
    h[0] = (uint8_t)(0x80 | opcode);
    if (n < 126) h[1] = (uint8_t)n;
    else if (n < 65536) { h[1] = 126; h[2] = (uint8_t)(n >> 8); h[3] = (uint8_t)n; hl = 4; }
    else { h[1] = 127; for (int i = 0; i < 8; i++) h[2 + i] = (uint8_t)(n >> (56 - 8 * i)); hl = 10; }
    return send_all(fd, h, hl) && send_all(fd, data, n);
}

static void put32(uint8_t *p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * i)); }

static bool send_window(int fd, const struct window *w) {
    if (w->closed) {
        uint8_t m[5] = {2};
        put32(m + 1, w->id);
        return ws_send(fd, 2, m, sizeof m);
    }
    size_t tl = strlen(w->title), n = 1 + 4 * 8 + 2 + tl + (size_t)w->width * w->height * 4;
    uint8_t *m = malloc(n);
    if (!m) return false;
    m[0] = 1;
    put32(m + 1, w->id);
    put32(m + 5, (uint32_t)w->x);
    put32(m + 9, (uint32_t)w->y);
    put32(m + 13, w->width);
    put32(m + 17, w->height);
    put32(m + 21, w->flags);
    put32(m + 25, (uint32_t)w->level);
    put32(m + 29, w->front);
    m[33] = (uint8_t)tl;
    m[34] = (uint8_t)(tl >> 8);
    memcpy(m + 35, w->title, tl);
    memcpy(m + 35 + tl, w->rgba, (size_t)w->width * w->height * 4);
    bool ok = ws_send(fd, 2, m, n);
    free(m);
    return ok;
}

/* The rect of `w` changed since version `since`, when only parts of it
 * have (else false: a full frame is needed). */
static bool damage_since(const struct window *w, uint64_t since, uint32_t r[4]) {
    if (!w->rgba || w->closed || since < w->full_version) return false;
    uint32_t x0 = UINT32_MAX, y0 = UINT32_MAX, x1 = 0, y1 = 0;
    for (int i = 0; i < w->ndamage; i++) {
        if (w->damage[i].version <= since) continue;
        if (w->damage[i].x < x0) x0 = w->damage[i].x;
        if (w->damage[i].y < y0) y0 = w->damage[i].y;
        if (w->damage[i].x + w->damage[i].w > x1) x1 = w->damage[i].x + w->damage[i].w;
        if (w->damage[i].y + w->damage[i].h > y1) y1 = w->damage[i].y + w->damage[i].h;
    }
    if (x0 >= x1 || y0 >= y1) x0 = y0 = x1 = y1 = 0;
    r[0] = x0, r[1] = y0, r[2] = x1 - x0, r[3] = y1 - y0;
    return true;
}

/* Part of a window's frame: the header of a frame, the rect, its pixels
 * (copied from w->rgba, with display_lock held: the message is built
 * under the lock and sent without it). */
static uint8_t *part_message(const struct window *w, const uint32_t r[4], size_t *n) {
    size_t tl = strlen(w->title);
    *n = 1 + 4 * 8 + 2 + tl + 16 + (size_t)r[2] * r[3] * 4;
    uint8_t *m = malloc(*n);
    if (!m) return NULL;
    m[0] = 3;
    put32(m + 1, w->id);
    put32(m + 5, (uint32_t)w->x);
    put32(m + 9, (uint32_t)w->y);
    put32(m + 13, w->width);
    put32(m + 17, w->height);
    put32(m + 21, w->flags);
    put32(m + 25, (uint32_t)w->level);
    put32(m + 29, w->front);
    m[33] = (uint8_t)tl;
    m[34] = (uint8_t)(tl >> 8);
    memcpy(m + 35, w->title, tl);
    uint8_t *p = m + 35 + tl;
    for (int i = 0; i < 4; i++) put32(p + 4 * i, r[i]);
    p += 16;
    for (uint32_t row = 0; row < r[3]; row++)
        memcpy(p + (size_t)row * r[2] * 4, w->rgba + ((size_t)(r[1] + row) * w->width + r[0]) * 4, (size_t)r[2] * 4);
    return m;
}

/* Values out of the page's flat JSON objects. */
static double json_number(const char *s, const char *key, double fallback) {
    char k[16];
    snprintf(k, sizeof k, "\"%s\":", key);
    const char *p = strstr(s, k);
    return p ? strtod(p + strlen(k), NULL) : fallback;
}

static void json_string(const char *s, const char *key, char *out, size_t size) {
    char k[16];
    snprintf(k, sizeof k, "\"%s\":\"", key);
    const char *p = strstr(s, k);
    size_t o = 0;
    out[0] = 0;
    if (!p) return;
    for (p += strlen(k); *p && *p != '"' && o + 1 < size; p++) {
        if (*p == '\\' && p[1]) {
            p++;
            if (*p == 'n') out[o++] = '\n';
            else if (*p == 't') out[o++] = '\t';
            else if (*p == 'r') out[o++] = '\r';
            else if (*p == 'u' && p[1] && p[2] && p[3] && p[4]) {
                char hex[5] = {p[1], p[2], p[3], p[4], 0};
                unsigned c = (unsigned)strtoul(hex, NULL, 16);
                p += 4;
                if (c < 0x80) out[o++] = (char)c;
                else if (c < 0x800 && o + 2 < size) { out[o++] = (char)(0xc0 | c >> 6); out[o++] = (char)(0x80 | (c & 63)); }
                else if (o + 3 < size) {
                    out[o++] = (char)(0xe0 | c >> 12);
                    out[o++] = (char)(0x80 | (c >> 6 & 63));
                    out[o++] = (char)(0x80 | (c & 63));
                }
            } else out[o++] = *p;
        } else {
            out[o++] = *p;
        }
    }
    out[o] = 0;
}

static void handle_input(const char *json) {
    static const struct { const char *name; uint32_t type; } kinds[] = {
        {"\"down\"", EV_MOUSE_DOWN}, {"\"up\"", EV_MOUSE_UP}, {"\"move\"", EV_MOUSE_MOVED},
        {"\"drag\"", EV_MOUSE_DRAGGED}, {"\"scroll\"", EV_SCROLL}, {"\"key\"", EV_KEY_DOWN},
        {"\"keyup\"", EV_KEY_UP}, {"\"close\"", EV_CLOSE}, {"\"resize\"", EV_RESIZE},
        {"\"miniaturize\"", EV_MINIATURIZE}, {"\"zoom\"", EV_ZOOM}, {"\"deminiaturize\"", EV_DEMINIATURIZE},
    };
    const char *t = strstr(json, "\"t\":");
    if (!t) return;
    struct bitten_display_event e;
    memset(&e, 0, sizeof e);
    for (size_t i = 0; i < sizeof kinds / sizeof *kinds; i++)
        if (!strncmp(t + 4, kinds[i].name, strlen(kinds[i].name))) e.type = kinds[i].type;
    if (!e.type) return;
    e.window = (uint32_t)json_number(json, "w", 0);
    e.x = json_number(json, "x", 0);
    e.y = json_number(json, "y", 0);
    e.dx = json_number(json, "dx", 0);
    e.dy = json_number(json, "dy", 0);
    e.button = (uint32_t)json_number(json, "b", 0);
    e.modifiers = (uint32_t)json_number(json, "m", 0);
    e.key_code = (uint32_t)json_number(json, "k", 0);
    e.width = json_number(json, "cw", 0);
    e.height = json_number(json, "ch", 0);
    json_string(json, "c", e.characters, sizeof e.characters);
    display_push_event(&e);
}

/* Read one client message; false when the connection ends. */
static bool ws_read(int fd, char **out, size_t *len, int *opcode) {
    uint8_t h[2];
    if (recv(fd, h, 2, MSG_WAITALL) != 2) return false;
    *opcode = h[0] & 15;
    uint64_t n = h[1] & 127;
    if (n == 126) {
        uint8_t b[2];
        if (recv(fd, b, 2, MSG_WAITALL) != 2) return false;
        n = (uint64_t)b[0] << 8 | b[1];
    } else if (n == 127) {
        uint8_t b[8];
        if (recv(fd, b, 8, MSG_WAITALL) != 8) return false;
        n = 0;
        for (int i = 0; i < 8; i++) n = n << 8 | b[i];
    }
    if (n > (1 << 20)) return false;
    uint8_t mask[4] = {0};
    if ((h[1] & 128) && recv(fd, mask, 4, MSG_WAITALL) != 4) return false;
    char *m = malloc(n + 1);
    if (!m) return false;
    if (n && recv(fd, m, n, MSG_WAITALL) != (ssize_t)n) { free(m); return false; }
    for (uint64_t i = 0; i < n; i++) m[i] ^= (char)mask[i % 4];
    m[n] = 0;
    *out = m;
    *len = n;
    return true;
}

struct client { int fd; bool dead; };

static int by_front(const void *a, const void *b) {
    const struct window *x = *(const struct window *const *)a, *y = *(const struct window *const *)b;
    return x->front < y->front ? -1 : x->front > y->front;
}

/* Send every window whenever something changes. */
static void *client_writer(void *arg) {
    struct client *c = arg;
    uint64_t seen = 0;
    pthread_mutex_lock(&display_lock);
    while (!c->dead) {
        if (display_version != seen) {
            uint64_t since = seen;
            seen = display_version;
            /* The page stacks windows in the order they arrive: a viewer
             * that connects gets them back to front (by order-front). */
            size_t nw = 0;
            for (struct window *w = display_windows; w; w = w->next) nw++;
            struct window **order = malloc((nw ? nw : 1) * sizeof *order);
            if (!order) { c->dead = true; break; }
            nw = 0;
            for (struct window *w = display_windows; w; w = w->next) order[nw++] = w;
            if (since == 0) qsort(order, nw, sizeof *order, by_front);
            for (size_t k = 0; k < nw; k++) {
                struct window *w = order[k];
                if (w->version <= since || (!w->closed && !w->rgba)) continue;
                uint32_t r[4];
                if (damage_since(w, since, r)) {
                    size_t n;
                    uint8_t *m = part_message(w, r, &n);
                    pthread_mutex_unlock(&display_lock);
                    bool ok = m && ws_send(c->fd, 2, m, n);
                    free(m);
                    pthread_mutex_lock(&display_lock);
                    if (!ok) c->dead = true;
                    if (c->dead) break;
                    continue;
                }
                /* Copy under the lock, send without it. */
                struct window copy = *w;
                copy.rgba = w->closed ? NULL : malloc((size_t)w->width * w->height * 4 + 1);
                if (copy.rgba) memcpy(copy.rgba, w->rgba, (size_t)w->width * w->height * 4);
                pthread_mutex_unlock(&display_lock);
                bool ok = (w->closed || copy.rgba) && send_window(c->fd, &copy);
                free(copy.rgba);
                pthread_mutex_lock(&display_lock);
                if (!ok) c->dead = true;
                if (c->dead) break;
            }
            free(order);
            continue;
        }
        pthread_cond_wait(&changed, &display_lock);
    }
    pthread_mutex_unlock(&display_lock);
    return NULL;
}

static void serve_websocket(int fd, const char *key) {
    static const char guid[] = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    char joined[128], accept[64], reply[256];
    uint8_t digest[20];
    snprintf(joined, sizeof joined, "%s%s", key, guid);
    unsigned char *(*sha1)(const void *, uint32_t, unsigned char *) = dx_registry_lookup("_CC_SHA1");
    if (!sha1) return;
    sha1(joined, (uint32_t)strlen(joined), digest);
    base64(digest, 20, accept);
    int n = snprintf(reply, sizeof reply,
                     "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                     "Sec-WebSocket-Accept: %s\r\n\r\n", accept);
    if (!send_all(fd, reply, (size_t)n)) return;
    struct client c = {fd, false};
    pthread_t writer;
    if (pthread_create(&writer, NULL, client_writer, &c)) return;
    for (;;) {
        char *m;
        size_t len;
        int op;
        if (!ws_read(fd, &m, &len, &op)) break;
        if (op == 1) handle_input(m);
        else if (op == 9) ws_send(fd, 10, m, len);          /* ping -> pong */
        bool close = op == 8;
        free(m);
        if (close) break;
    }
    pthread_mutex_lock(&display_lock);
    c.dead = true;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&display_lock);
    shutdown(fd, SHUT_RDWR);
    pthread_join(writer, NULL);
}

static void *connection(void *arg) {
    int fd = (int)(intptr_t)arg;
    char req[4096];
    size_t n = 0;
    while (n + 1 < sizeof req) {
        ssize_t k = recv(fd, req + n, sizeof req - 1 - n, 0);
        if (k <= 0) break;
        n += (size_t)k;
        req[n] = 0;
        if (strstr(req, "\r\n\r\n")) break;
    }
    req[n] = 0;
    char *key = strcasestr(req, "Sec-WebSocket-Key:");
    if (key) {
        key += 18;
        while (*key == ' ') key++;
        char *end = strpbrk(key, "\r\n");
        if (end) *end = 0;
        serve_websocket(fd, key);
    } else if (!strncmp(req, "GET ", 4)) {
        char head[160];
        int hl = snprintf(head, sizeof head,
                          "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %zu\r\n"
                          "Cache-Control: no-store\r\nConnection: close\r\n\r\n", strlen(DISPLAY_PAGE));
        if (send_all(fd, head, (size_t)hl)) send_all(fd, DISPLAY_PAGE, strlen(DISPLAY_PAGE));
    }
    close(fd);
    return NULL;
}

static void *acceptor(void *arg) {
    for (;;) {
        int fd = accept(listen_fd, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR) continue;
            return NULL;
        }
        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        pthread_t t;
        if (pthread_create(&t, NULL, connection, (void *)(intptr_t)fd) == 0) pthread_detach(t);
        else close(fd);
    }
}

static void start_server(void) {
    const char *env = getenv("BITTEN_DISPLAY_PORT");
    int port = requested_port >= 0 ? requested_port : env ? atoi(env) : 7681;
    int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons((uint16_t)port)};
    a.sin_addr.s_addr = htonl(getenv("BITTEN_DISPLAY_PUBLIC") ? INADDR_ANY : INADDR_LOOPBACK);
    socklen_t len = sizeof a;
    if (bind(fd, (struct sockaddr *)&a, sizeof a) || listen(fd, 16) || getsockname(fd, (struct sockaddr *)&a, &len)) {
        dx_log(0, "display: cannot listen on port %d: %s", port, strerror(errno));
        close(fd);
        return;
    }
    listen_fd = fd;
    server_port = ntohs(a.sin_port);
    pthread_t t;
    if (pthread_create(&t, NULL, acceptor, NULL) == 0) pthread_detach(t);
    dx_log(0, "display: windows at http://localhost:%d/", server_port);
}

/* The X11 viewer with BITTEN_DISPLAY=x11, the browser page otherwise (and
 * always for bitten_display_listen, which asks for a port). */
static void start_display(void) {
    event_fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    const char *which = getenv("BITTEN_DISPLAY");
    if (requested_port < 0 && which && !strcmp(which, "x11")) {
        if (display_x11_start()) return;
        dx_log(0, "display: no X11 display at %s; using the browser page", getenv("DISPLAY") ?: "(DISPLAY unset)");
    }
    start_server();
}

/* ---- the API (for AppKit) ------------------------------------------------------------- */

/* Start the server (presenting a window starts it too); the port, or 0. */
int bitten_display_start(void) {
    pthread_once(&started, start_display);
    return server_port;
}
DX_EXPORT("_bitten_display_start", bitten_display_start);

/* Start the server on a given port (0: any free one), unless it runs
 * already; the port it listens on, or 0. */
int bitten_display_listen(int port) {
    requested_port = port;
    return bitten_display_start();
}
DX_EXPORT("_bitten_display_listen", bitten_display_listen);

int bitten_display_port(void) { return server_port; }
DX_EXPORT("_bitten_display_port", bitten_display_port);

/* The rect (x0, y0, w, h) of a bitmap as straight-alpha RGBA bytes, into
 * dst (rows of dst_width pixels). 8-bit colour with premultiplied alpha
 * (what windows draw into) is converted with integers. */
static void to_rgba(const struct cg_surface *s, size_t x0, size_t y0, size_t w, size_t h, uint8_t *dst, size_t dst_width) {
    const struct cg_format *f = &s->format;
    bool fast = f->bytes == 4 && !f->gray && !f->alpha_only && f->a >= 0;
    for (size_t r = y0; r < y0 + h; r++) {
        const uint8_t *row = s->data + r * s->row_bytes;
        uint8_t *d = dst + (r * dst_width + x0) * 4;
        if (fast) {
            for (size_t c = x0; c < x0 + w; c++, d += 4) {
                const uint8_t *p = row + c * 4;
                unsigned a = p[f->a], rgb[3] = {p[f->r], p[f->g], p[f->b]};
                for (int k = 0; k < 3; k++) {
                    unsigned v = rgb[k];
                    if (!f->straight && a && a < 255) v = (v * 510 + a) / (2 * a);
                    d[k] = (uint8_t)(v > 255 ? 255 : v);
                }
                d[3] = (uint8_t)a;
            }
            continue;
        }
        for (size_t c = x0; c < x0 + w; c++, d += 4) {
            CGFloat px[4];
            cg_read_pixel(s, c, r, px);
            if (!f->straight && px[3] > 0 && px[3] < 1)
                for (int k = 0; k < 3; k++) px[k] /= px[3];
            for (int k = 0; k < 4; k++) d[k] = (uint8_t)(fmin(fmax(px[k], 0), 1) * 255 + 0.5);
        }
    }
}

/* Show (or update) window `id`: its pixels, as a bitmap context holds
 * them (8-bit RGB with alpha in any CGBitmapInfo layout), its position on
 * the page (origin top left) and its title. Returns 0, or -1 when the
 * layout is not one CoreGraphics draws. */
int bitten_display_present(uint32_t id, const void *pixels, size_t width, size_t height, size_t row_bytes,
                           uint32_t bitmap_info, double x, double y, const char *title) {
    struct cg_format f;
    if (!pixels || !cg_format_for(cg_space_rgb(), 8, 32, bitmap_info, &f)) return -1;
    bitten_display_start();
    uint8_t *rgba = malloc(width * height * 4 + 1);
    if (!rgba) return -1;
    struct cg_surface s = {(uint8_t *)pixels, width, height, row_bytes, f};
    to_rgba(&s, 0, 0, width, height, rgba, width);
    pthread_mutex_lock(&display_lock);
    struct window *w = find_or_add(id);
    if (!w) { pthread_mutex_unlock(&display_lock); free(rgba); return -1; }
    free(w->rgba);
    w->rgba = rgba;
    w->width = (uint32_t)width;
    w->height = (uint32_t)height;
    w->x = (int32_t)x;
    w->y = (int32_t)y;
    w->closed = false;
    snprintf(w->title, sizeof w->title, "%s", title ? title : "");
    w->version = ++display_version;
    w->full_version = w->version;
    w->ndamage = 0;
    display_changed();
    pthread_mutex_unlock(&display_lock);
    return 0;
}
DX_EXPORT("_bitten_display_present", bitten_display_present);

/* Like bitten_display_present, when only the rect (rx, ry, rw, rh: pixels,
 * origin top left) of the bitmap changed since the window's last frame:
 * only that part is converted and sent. A first frame or a new size is
 * presented whole. */
int bitten_display_present_rect(uint32_t id, const void *pixels, size_t width, size_t height, size_t row_bytes,
                                uint32_t bitmap_info, double x, double y, const char *title, size_t rx, size_t ry,
                                size_t rw, size_t rh) {
    struct cg_format f;
    if (!pixels || !cg_format_for(cg_space_rgb(), 8, 32, bitmap_info, &f)) return -1;
    if (rx > width) rx = width;
    if (ry > height) ry = height;
    if (rw > width - rx) rw = width - rx;
    if (rh > height - ry) rh = height - ry;
    pthread_mutex_lock(&display_lock);
    struct window *w = find(id);
    bool whole = !w || !w->rgba || w->closed || w->width != width || w->height != height;
    pthread_mutex_unlock(&display_lock);
    if (whole) return bitten_display_present(id, pixels, width, height, row_bytes, bitmap_info, x, y, title);
    bitten_display_start();
    pthread_mutex_lock(&display_lock);
    w = find(id);
    if (!w || !w->rgba || w->width != width || w->height != height) {
        pthread_mutex_unlock(&display_lock);
        return bitten_display_present(id, pixels, width, height, row_bytes, bitmap_info, x, y, title);
    }
    struct cg_surface s = {(uint8_t *)pixels, width, height, row_bytes, f};
    to_rgba(&s, rx, ry, rw, rh, w->rgba, width);
    w->x = (int32_t)x;
    w->y = (int32_t)y;
    snprintf(w->title, sizeof w->title, "%s", title ? title : "");
    w->version = ++display_version;
    if (w->ndamage == (int)(sizeof w->damage / sizeof *w->damage)) {
        w->full_version = w->version;           /* too many parts: the next viewer gets it whole */
        w->ndamage = 0;
    } else {
        w->damage[w->ndamage].version = w->version;
        w->damage[w->ndamage].x = (uint32_t)rx;
        w->damage[w->ndamage].y = (uint32_t)ry;
        w->damage[w->ndamage].w = (uint32_t)rw;
        w->damage[w->ndamage].h = (uint32_t)rh;
        w->ndamage++;
    }
    display_changed();
    pthread_mutex_unlock(&display_lock);
    return 0;
}
DX_EXPORT("_bitten_display_present_rect", bitten_display_present_rect);

/* A window's look and stacking: flags 1 borderless (no title bar or
 * frame), 2 transparent (the page shows through where alpha < 1), 4 full-size
 * content (the title bar lies over the frame's top instead of above it),
 * 8 title hidden (the bar shows its buttons only), 16 resizable (the page
 * offers a grip), 32 miniaturizable and 64 zoomable (the yellow and green
 * buttons work), 128 miniaturized (the page shows it as a chip in its
 * dock instead), 256 behind-window material (an NSVisualEffectView blending
 * behind the window: the page blurs what shows through a transparent
 * window); level is
 * the NSWindow level, which orders windows before focus does. May come
 * before the window's first frame. */
int bitten_display_set_style(uint32_t id, uint32_t flags, int32_t level) {
    bitten_display_start();
    pthread_mutex_lock(&display_lock);
    struct window *w = find_or_add(id);
    if (w && (w->flags != flags || w->level != level)) {
        w->flags = flags;
        w->level = level;
        w->version = ++display_version;
        w->full_version = w->version;
        display_changed();
    }
    pthread_mutex_unlock(&display_lock);
    return w ? 0 : -1;
}
DX_EXPORT("_bitten_display_set_style", bitten_display_set_style);

/* Brings window `id` to the front of its level without focusing it. */
void bitten_display_order_front(uint32_t id) {
    static uint32_t fronts;
    pthread_mutex_lock(&display_lock);
    struct window *w = find_or_add(id);
    if (w) {
        w->front = ++fronts;
        w->version = ++display_version;
        w->full_version = w->version;
        display_changed();
    }
    pthread_mutex_unlock(&display_lock);
}
DX_EXPORT("_bitten_display_order_front", bitten_display_order_front);

/* Take window `id` off the page. */
void bitten_display_close(uint32_t id) {
    pthread_mutex_lock(&display_lock);
    struct window *w = find(id);
    if (w) {
        free(w->rgba);
        w->rgba = NULL;
        w->closed = true;
        w->version = ++display_version;
        w->full_version = w->version;
        display_changed();
    }
    pthread_mutex_unlock(&display_lock);
}
DX_EXPORT("_bitten_display_close", bitten_display_close);

/* The next input event, if any: 1 with *out filled, 0 when none waits. */
int bitten_display_next_event(struct bitten_display_event *out) {
    pthread_mutex_lock(&display_lock);
    int got = q_count > 0;
    if (got) {
        *out = queue[q_head];
        q_head = (q_head + 1) % QUEUE;
        q_count--;
    }
    pthread_mutex_unlock(&display_lock);
    if (!got && event_fd >= 0) {
        uint64_t drain;
        (void)!read(event_fd, &drain, sizeof drain);
    }
    return got;
}
DX_EXPORT("_bitten_display_next_event", bitten_display_next_event);

/* A file descriptor that is readable while events wait (for run loops);
 * -1 before the server has started. */
int bitten_display_event_fd(void) { return event_fd; }
DX_EXPORT("_bitten_display_event_fd", bitten_display_event_fd);
