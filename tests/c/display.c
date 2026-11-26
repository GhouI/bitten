/* The display server end to end: draw a window with CoreGraphics, present
 * it, fetch the page, open the WebSocket, receive the frame and send an
 * input event back. */
#include "darwin.h"

typedef double CGFloat;
typedef struct { CGFloat x, y, w, h; } CGRect;
typedef void *Ref;
Ref CGColorSpaceCreateDeviceRGB(void);
Ref CGBitmapContextCreate(void *, unsigned long, unsigned long, unsigned long, unsigned long, Ref, unsigned int);
unsigned char *CGBitmapContextGetData(Ref);
unsigned long CGBitmapContextGetBytesPerRow(Ref);
void CGContextSetRGBFillColor(Ref, CGFloat, CGFloat, CGFloat, CGFloat);
void CGContextFillRect(Ref, CGRect);

struct event {
    unsigned int type, window;
    double x, y, dx, dy;
    unsigned int button, modifiers, key_code;
    char characters[32];
    double width, height;
};
int bitten_display_listen(int port);
int bitten_display_present(unsigned int id, const void *pixels, unsigned long w, unsigned long h,
                           unsigned long row_bytes, unsigned int info, double x, double y, const char *title);
int bitten_display_next_event(struct event *out);
void bitten_display_close(unsigned int id);
int bitten_display_set_style(unsigned int id, unsigned int flags, int level);
void bitten_display_order_front(unsigned int id);

struct sockaddr_in_d { unsigned char len, family; unsigned short port; unsigned int addr; char zero[8]; };
int socket(int, int, int);
int connect(int, const void *, unsigned int);
long send(int, const void *, unsigned long, int);
long recv(int, void *, unsigned long, int);
int close(int);
int usleep(unsigned int);
char *strstr(const char *, const char *);

static int dial(int port) {
    int fd = socket(2, 1, 0);
    struct sockaddr_in_d a = {16, 2, (unsigned short)((port >> 8) | (port << 8)), 0x0100007f, {0}};
    return fd >= 0 && connect(fd, &a, sizeof a) == 0 ? fd : -1;
}

static long read_some(int fd, unsigned char *buf, long want) {
    long n = 0;
    while (n < want) {
        long k = recv(fd, buf + n, (unsigned long)(want - n), 0);
        if (k <= 0) break;
        n += k;
    }
    return n;
}

int main(void) {
    int port = bitten_display_listen(0);
    CHECK(port > 0);
    /* a 4x3 window, red, drawn premultiplied BGRA as AppKit's backing stores */
    Ref ctx = CGBitmapContextCreate(NULL, 4, 3, 8, 0, CGColorSpaceCreateDeviceRGB(), 2 | 0x2000);
    CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
    CGRect all = {0, 0, 4, 3};
    CGContextFillRect(ctx, all);
    /* a style may come before the first frame; a styled window with no
     * frame yet is not sent */
    CHECK(bitten_display_set_style(7, 1 | 2, 3) == 0);
    CHECK(bitten_display_set_style(9, 1, 101) == 0);
    CHECK(bitten_display_present(7, CGBitmapContextGetData(ctx), 4, 3, CGBitmapContextGetBytesPerRow(ctx),
                                 2 | 0x2000, 40, 30, "Test") == 0);

    /* the page */
    int fd = dial(port);
    CHECK(fd >= 0);
    const char *get = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    CHECK(send(fd, get, strlen(get), 0) > 0);
    static unsigned char page[65536];
    long n = read_some(fd, page, sizeof page - 1);
    page[n > 0 ? n : 0] = 0;
    CHECK(strstr((char *)page, "200 OK") && strstr((char *)page, "<canvas") == 0 && strstr((char *)page, "WebSocket"));
    close(fd);

    /* the WebSocket: handshake (RFC 6455's sample key), then the frame */
    fd = dial(port);
    CHECK(fd >= 0);
    const char *hs = "GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                     "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n";
    CHECK(send(fd, hs, strlen(hs), 0) > 0);
    unsigned char resp[512];
    n = 0;
    while (n < (long)sizeof resp - 1) {                      /* headers up to the blank line */
        if (recv(fd, resp + n, 1, 0) != 1) break;
        n++;
        if (n >= 4 && !memcmp(resp + n - 4, "\r\n\r\n", 4)) break;
    }
    resp[n] = 0;
    CHECK(strstr((char *)resp, "101") && strstr((char *)resp, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="));
    unsigned char hdr[4];
    CHECK(read_some(fd, hdr, 2) == 2 && hdr[0] == 0x82);    /* a short binary message */
    long len = hdr[1];
    CHECK(len == 35 + 4 + 4 * 3 * 4);
    unsigned char msg[128];
    CHECK(read_some(fd, msg, len) == len);
    CHECK(msg[0] == 1 && msg[1] == 7 && msg[5] == 40 && msg[9] == 30 && msg[13] == 4 && msg[17] == 3);
    CHECK(msg[21] == 3 && msg[25] == 3 && msg[29] == 0);   /* borderless|transparent, floating, never ordered front */
    CHECK(msg[33] == 4 && !memcmp(msg + 35, "Test", 4));
    unsigned char *px = msg + 39;
    CHECK(px[0] == 255 && px[1] == 0 && px[2] == 0 && px[3] == 255);   /* straight RGBA */

    /* an event from the page (clients mask their messages) */
    const char *json = "{\"t\":\"down\",\"w\":7,\"x\":2.5,\"y\":1,\"b\":0,\"m\":131072,\"c\":\"a\\u00e9\"}";
    unsigned long jl = strlen(json);
    unsigned char out[200] = {0x81, (unsigned char)(0x80 | jl), 1, 2, 3, 4};
    for (unsigned long i = 0; i < jl; i++) out[6 + i] = (unsigned char)json[i] ^ out[2 + i % 4];
    CHECK(send(fd, out, 6 + jl, 0) == (long)(6 + jl));
    struct event e;
    int got = 0;
    for (int i = 0; i < 200 && !got; i++) { got = bitten_display_next_event(&e); if (!got) usleep(10000); }
    CHECK(got && e.type == 1 && e.window == 7 && e.x == 2.5 && e.y == 1 && e.modifiers == 131072);
    CHECK(!strcmp(e.characters, "a\xc3\xa9"));
    CHECK(!bitten_display_next_event(&e));

    /* ordering it front resends it, raised */
    bitten_display_order_front(7);
    CHECK(read_some(fd, hdr, 2) == 2 && hdr[0] == 0x82 && hdr[1] == len);
    CHECK(read_some(fd, msg, len) == len && msg[1] == 7 && msg[29] == 1);

    /* closing the window sends a close message */
    bitten_display_close(7);
    CHECK(read_some(fd, hdr, 2) == 2 && hdr[0] == 0x82 && hdr[1] == 5);
    CHECK(read_some(fd, msg, 5) == 5 && msg[0] == 2 && msg[1] == 7);
    close(fd);
    puts("display ok");
    return 0;
}
