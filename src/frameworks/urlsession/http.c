/* HTTP, HTTPS and WebSockets for Foundation's URLSession (the interface is
 * frameworks/Foundation/bn_http.h), over the host's libcurl, loaded when
 * first needed. libcurl does the connections, TLS, HTTP/1.1 and HTTP/2,
 * compressed bodies and proxies; redirects, cookies and caching are left
 * to Foundation. For WebSockets libcurl only connects (and does TLS); the
 * opening handshake and the framing (RFC 6455) are here.
 *
 * libcurl's headers are not needed: the few functions are looked up by
 * name and the option and info numbers, which are part of libcurl's stable
 * ABI, are written out below. */
#include <dlfcn.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/random.h>
#include <time.h>

#include "dx.h"
#include "../../../frameworks/Foundation/bn_http.h"

/* ---- libcurl ---- */

typedef void CURL;
typedef int CURLcode;
struct curl_slist;

enum {
    OPT_WRITEDATA = 10001, OPT_URL = 10002, OPT_READDATA = 10009, OPT_ERRORBUFFER = 10010,
    OPT_WRITEFUNCTION = 20011, OPT_READFUNCTION = 20012, OPT_POSTFIELDS = 10015, OPT_USERAGENT = 10018,
    OPT_LOW_SPEED_LIMIT = 19, OPT_LOW_SPEED_TIME = 20, OPT_HTTPHEADER = 10023, OPT_HEADERDATA = 10029,
    OPT_SSLVERSION = 32, OPT_CUSTOMREQUEST = 10036, OPT_NOPROGRESS = 43, OPT_NOBODY = 44, OPT_UPLOAD = 46,
    OPT_POST = 47, OPT_FOLLOWLOCATION = 52, OPT_XFERINFODATA = 10057, OPT_HEADERFUNCTION = 20079,
    OPT_HTTP_VERSION = 84, OPT_NOSIGNAL = 99, OPT_ACCEPT_ENCODING = 10102, OPT_INFILESIZE_LARGE = 30115,
    OPT_POSTFIELDSIZE_LARGE = 30120, OPT_CONNECT_ONLY = 141, OPT_TIMEOUT_MS = 155, OPT_CONNECTTIMEOUT_MS = 156,
    OPT_XFERINFOFUNCTION = 20219,
};
enum {
    INFO_STRING = 0x100000, INFO_LONG = 0x200000, INFO_DOUBLE = 0x300000, INFO_PTR = 0x400000,
    INFO_SOCKET = 0x500000, INFO_OFF_T = 0x600000,
    INFO_RESPONSE_CODE = INFO_LONG + 2, INFO_TOTAL_TIME = INFO_DOUBLE + 3, INFO_NAMELOOKUP_TIME = INFO_DOUBLE + 4,
    INFO_CONNECT_TIME = INFO_DOUBLE + 5, INFO_PRETRANSFER_TIME = INFO_DOUBLE + 6, INFO_SIZE_UPLOAD_T = INFO_OFF_T + 7,
    INFO_SIZE_DOWNLOAD_T = INFO_OFF_T + 8, INFO_HEADER_SIZE = INFO_LONG + 11, INFO_REQUEST_SIZE = INFO_LONG + 12,
    INFO_STARTTRANSFER_TIME = INFO_DOUBLE + 17, INFO_REDIRECT_URL = INFO_STRING + 31, INFO_PRIMARY_IP = INFO_STRING + 32,
    INFO_APPCONNECT_TIME = INFO_DOUBLE + 33, INFO_PRIMARY_PORT = INFO_LONG + 40, INFO_LOCAL_IP = INFO_STRING + 41,
    INFO_LOCAL_PORT = INFO_LONG + 42, INFO_ACTIVESOCKET = INFO_SOCKET + 44, INFO_TLS_SSL_PTR = INFO_PTR + 45,
    INFO_HTTP_VERSION = INFO_LONG + 46,
};
enum {
    E_OK = 0, E_UNSUPPORTED_PROTOCOL = 1, E_URL_MALFORMAT = 3, E_COULDNT_RESOLVE_PROXY = 5,
    E_COULDNT_RESOLVE_HOST = 6, E_COULDNT_CONNECT = 7, E_WRITE_ERROR = 23, E_READ_ERROR = 26,
    E_OPERATION_TIMEDOUT = 28, E_SSL_CONNECT_ERROR = 35, E_FILE_COULDNT_READ_FILE = 37,
    E_ABORTED_BY_CALLBACK = 42, E_TOO_MANY_REDIRECTS = 47, E_GOT_NOTHING = 52, E_SEND_ERROR = 55,
    E_RECV_ERROR = 56, E_PEER_FAILED_VERIFICATION = 60, E_BAD_CONTENT_ENCODING = 61, E_AGAIN = 81,
    E_SSL_CERTPROBLEM = 58, E_SSL_CIPHER = 59, E_SSL_CACERT_BADFILE = 77, E_HTTP2 = 16, E_HTTP2_STREAM = 92,
    E_PARTIAL_FILE = 18,
};

static struct {
    int ok;
    CURLcode (*global_init)(long);
    CURL *(*init)(void);
    CURLcode (*setopt)(CURL *, int, ...);
    CURLcode (*perform)(CURL *);
    CURLcode (*getinfo)(CURL *, int, ...);
    void (*cleanup)(CURL *);
    struct curl_slist *(*slist_append)(struct curl_slist *, const char *);
    void (*slist_free_all)(struct curl_slist *);
    CURLcode (*send)(CURL *, const void *, size_t, size_t *);
    CURLcode (*recv)(CURL *, void *, size_t, size_t *);
    int (*ssl_version)(const void *ssl);
    const void *(*ssl_cipher)(const void *ssl);
    uint32_t (*cipher_id)(const void *cipher);
} C;
static pthread_once_t loaded = PTHREAD_ONCE_INIT;

static void load(void) {
    void *h = dlopen("libcurl.so.4", RTLD_NOW | RTLD_GLOBAL);
    if (!h) {
        dx_log(1, "urlsession: no libcurl (%s): URLSession cannot reach the network", dlerror());
        return;
    }
#define SYM(field, name) C.field = dlsym(h, name)
    SYM(global_init, "curl_global_init");
    SYM(init, "curl_easy_init");
    SYM(setopt, "curl_easy_setopt");
    SYM(perform, "curl_easy_perform");
    SYM(getinfo, "curl_easy_getinfo");
    SYM(cleanup, "curl_easy_cleanup");
    SYM(slist_append, "curl_slist_append");
    SYM(slist_free_all, "curl_slist_free_all");
    SYM(send, "curl_easy_send");
    SYM(recv, "curl_easy_recv");
#undef SYM
    if (!C.global_init || !C.init || !C.setopt || !C.perform || !C.getinfo) return;
    C.global_init(3); /* CURL_GLOBAL_ALL */
    void *ssl = dlopen("libssl.so.3", RTLD_NOW | RTLD_NOLOAD);
    if (ssl) {
        C.ssl_version = dlsym(ssl, "SSL_version");
        C.ssl_cipher = dlsym(ssl, "SSL_get_current_cipher");
        C.cipher_id = dlsym(ssl, "SSL_CIPHER_get_id");
    }
    C.ok = 1;
}

/* ---- errors ---- */

static int url_error(CURLcode c) {
    switch (c) {
    case E_OK: return 0;
    case E_UNSUPPORTED_PROTOCOL: return -1002;
    case E_URL_MALFORMAT: return -1000;
    case E_COULDNT_RESOLVE_HOST: case E_COULDNT_RESOLVE_PROXY: return -1003;
    case E_COULDNT_CONNECT: return -1004;
    case E_OPERATION_TIMEDOUT: return -1001;
    case E_SSL_CONNECT_ERROR: case E_SSL_CIPHER: return -1200;
    case E_PEER_FAILED_VERIFICATION: case E_SSL_CACERT_BADFILE: return -1202;
    case E_SSL_CERTPROBLEM: return -1206;
    case E_ABORTED_BY_CALLBACK: case E_WRITE_ERROR: return -999;
    case E_TOO_MANY_REDIRECTS: return -1007;
    case E_GOT_NOTHING: case E_SEND_ERROR: case E_RECV_ERROR: case E_PARTIAL_FILE: case E_HTTP2: case E_HTTP2_STREAM:
        return -1005;
    case E_BAD_CONTENT_ENCODING: return -1016;
    case E_FILE_COULDNT_READ_FILE: return -1100;
    case E_READ_ERROR: return -3001;
    default: return -1;
    }
}

/* ---- one transfer ---- */

struct xfer {
    const bn_http_callbacks *cb;
    bn_http_result *res;
    char *hdr;
    size_t hlen, hcap;
    long status;
    int delivered, in_headers, stop;
    FILE *upload;
};

static int deliver(struct xfer *x) {
    if (x->delivered) return 0;
    x->delivered = 1;
    if (x->cb && x->cb->response && x->cb->response(x->cb->ctx, x->status, x->hdr ? x->hdr : "", x->hlen)) {
        x->stop = 1;
        return 1;
    }
    return 0;
}

static size_t on_header(char *b, size_t size, size_t n, void *ud) {
    struct xfer *x = ud;
    size_t len = size * n;
    if (len >= 5 && !memcmp(b, "HTTP/", 5)) {
        /* a status line: a new response (after 1xx, or for each redirect hop) */
        x->hlen = 0;
        x->delivered = 0;
        x->in_headers = 1;
        const char *sp = memchr(b, ' ', len);
        x->status = sp ? strtol(sp + 1, NULL, 10) : 0;
        return len;
    }
    if (len <= 2 && (len == 0 || b[0] == '\r' || b[0] == '\n')) {
        x->in_headers = 0;
        if (x->status >= 100 && x->status < 200 && x->status != 101) return len;   /* informational */
        return deliver(x) ? 0 : len;
    }
    if (x->hlen + len + 1 > x->hcap) {
        x->hcap = (x->hlen + len + 1) * 2;
        x->hdr = realloc(x->hdr, x->hcap);
    }
    memcpy(x->hdr + x->hlen, b, len);
    x->hlen += len;
    x->hdr[x->hlen] = 0;
    return len;
}

static size_t on_body(char *b, size_t size, size_t n, void *ud) {
    struct xfer *x = ud;
    size_t len = size * n;
    if (deliver(x) || x->stop) return 0;
    if (x->cb && x->cb->data && x->cb->data(x->cb->ctx, b, len)) {
        x->stop = 1;
        return 0;
    }
    return len;
}

static int on_progress(void *ud, int64_t dt, int64_t dn, int64_t ut, int64_t un) {
    struct xfer *x = ud;
    if (x->stop) return 1;
    if (x->cb && x->cb->progress && x->cb->progress(x->cb->ctx, dt, dn, ut, un)) {
        x->stop = 1;
        return 1;
    }
    return 0;
}

static size_t on_read(char *b, size_t size, size_t n, void *ud) {
    struct xfer *x = ud;
    return fread(b, size, n, x->upload);
}

static long ssl_version_option(uint16_t min, uint16_t max) {
    long v = 1; /* CURL_SSLVERSION_TLSv1 */
    switch (min) {
    case 0x0301: v = 4; break;
    case 0x0302: v = 5; break;
    case 0x0303: v = 6; break;
    case 0x0304: v = 7; break;
    }
    switch (max) {
    case 0x0301: v |= 4L << 16; break;
    case 0x0302: v |= 5L << 16; break;
    case 0x0303: v |= 6L << 16; break;
    case 0x0304: v |= 7L << 16; break;
    }
    return v;
}

/* Options shared by transfers and WebSocket connections. */
static struct curl_slist *common_setup(CURL *c, const bn_http_request *req, char *errbuf) {
    C.setopt(c, OPT_URL, req->url);
    C.setopt(c, OPT_NOSIGNAL, 1L);
    C.setopt(c, OPT_ERRORBUFFER, errbuf);
    C.setopt(c, OPT_FOLLOWLOCATION, 0L);
    C.setopt(c, OPT_HTTP_VERSION, 4L); /* HTTP/2 over TLS, else 1.1 */
    if (req->timeout > 0) C.setopt(c, OPT_CONNECTTIMEOUT_MS, (long)(req->timeout * 1000));
    if (req->tls_min || req->tls_max) C.setopt(c, OPT_SSLVERSION, ssl_version_option(req->tls_min, req->tls_max));
    struct curl_slist *list = NULL;
    for (int i = 0; i < req->nheaders; i++) list = C.slist_append(list, req->headers[i]);
    return list;
}

static void collect(CURL *c, bn_http_result *res) {
    long l = 0;
    double d = 0;
    char *s = NULL;
    int64_t o = 0;
    if (!C.getinfo(c, INFO_RESPONSE_CODE, &l) && l) res->status = l;
    if (!C.getinfo(c, INFO_HTTP_VERSION, &l)) res->http_version = l == 1 ? 10 : l == 2 ? 11 : l == 3 ? 20 : l == 30 ? 30 : 0;
    if (!C.getinfo(c, INFO_NAMELOOKUP_TIME, &d)) res->t_lookup = d;
    if (!C.getinfo(c, INFO_CONNECT_TIME, &d)) res->t_connect = d;
    if (!C.getinfo(c, INFO_APPCONNECT_TIME, &d)) res->t_tls = d;
    if (!C.getinfo(c, INFO_PRETRANSFER_TIME, &d)) res->t_request = d;
    if (!C.getinfo(c, INFO_STARTTRANSFER_TIME, &d)) res->t_first_byte = d;
    if (!C.getinfo(c, INFO_TOTAL_TIME, &d)) res->t_total = d;
    if (!C.getinfo(c, INFO_HEADER_SIZE, &l)) res->header_bytes = l;
    if (!C.getinfo(c, INFO_REQUEST_SIZE, &l)) res->request_bytes = l;
    if (!C.getinfo(c, INFO_SIZE_UPLOAD_T, &o)) res->upload_bytes = o;
    if (!C.getinfo(c, INFO_SIZE_DOWNLOAD_T, &o)) res->download_bytes = o;
    if (!C.getinfo(c, INFO_PRIMARY_IP, &s) && s) snprintf(res->remote_ip, sizeof res->remote_ip, "%s", s);
    if (!C.getinfo(c, INFO_LOCAL_IP, &s) && s) snprintf(res->local_ip, sizeof res->local_ip, "%s", s);
    if (!C.getinfo(c, INFO_PRIMARY_PORT, &l)) res->remote_port = l;
    if (!C.getinfo(c, INFO_LOCAL_PORT, &l)) res->local_port = l;
    s = NULL;
    if (!C.getinfo(c, INFO_REDIRECT_URL, &s) && s) snprintf(res->redirect_url, sizeof res->redirect_url, "%s", s);
    struct { int backend; void *internals; } *tls = NULL;
    if (C.ssl_version && !C.getinfo(c, INFO_TLS_SSL_PTR, &tls) && tls && tls->backend == 1 /* OpenSSL */ &&
        tls->internals) {
        res->tls_version = (uint16_t)C.ssl_version(tls->internals);
        const void *cipher = C.ssl_cipher ? C.ssl_cipher(tls->internals) : NULL;
        if (cipher && C.cipher_id) res->tls_cipher = (uint16_t)(C.cipher_id(cipher) & 0xffff);
    }
}

int bitten_http_perform(const bn_http_request *req, const bn_http_callbacks *cb, bn_http_result *res) {
    pthread_once(&loaded, load);
    memset(res, 0, sizeof *res);
    if (!C.ok) {
        res->error = -1009;
        snprintf(res->message, sizeof res->message, "libcurl is not available");
        return -1;
    }
    CURL *c = C.init();
    if (!c) {
        res->error = -1;
        return 0;
    }
    char errbuf[256] = "";
    struct xfer x = {.cb = cb, .res = res};
    struct curl_slist *list = common_setup(c, req, errbuf);
    int has_encoding = 0;
    for (int i = 0; i < req->nheaders; i++)
        if (!strncasecmp(req->headers[i], "Accept-Encoding:", 16)) has_encoding = 1;
    list = C.slist_append(list, "Expect:");
    C.setopt(c, OPT_HTTPHEADER, list);
    if (req->decode && !has_encoding) C.setopt(c, OPT_ACCEPT_ENCODING, "");
    if (req->timeout > 0) {
        C.setopt(c, OPT_LOW_SPEED_LIMIT, 1L);
        C.setopt(c, OPT_LOW_SPEED_TIME, (long)(req->timeout + 0.999));
    }
    if (req->resource_timeout > 0) C.setopt(c, OPT_TIMEOUT_MS, (long)(req->resource_timeout * 1000));
    C.setopt(c, OPT_HEADERFUNCTION, on_header);
    C.setopt(c, OPT_HEADERDATA, &x);
    C.setopt(c, OPT_WRITEFUNCTION, on_body);
    C.setopt(c, OPT_WRITEDATA, &x);
    C.setopt(c, OPT_NOPROGRESS, 0L);
    C.setopt(c, OPT_XFERINFOFUNCTION, on_progress);
    C.setopt(c, OPT_XFERINFODATA, &x);

    const char *m = req->method && *req->method ? req->method : "GET";
    if (req->body_file) {
        x.upload = fopen(req->body_file, "rb");
        if (!x.upload) {
            res->error = -1100;
            snprintf(res->message, sizeof res->message, "cannot read %s", req->body_file);
            C.slist_free_all(list);
            C.cleanup(c);
            return 0;
        }
        fseek(x.upload, 0, SEEK_END);
        int64_t size = ftell(x.upload);
        fseek(x.upload, 0, SEEK_SET);
        C.setopt(c, OPT_UPLOAD, 1L);
        C.setopt(c, OPT_READFUNCTION, on_read);
        C.setopt(c, OPT_READDATA, &x);
        C.setopt(c, OPT_INFILESIZE_LARGE, size);
        C.setopt(c, OPT_CUSTOMREQUEST, m);
    } else if (req->body || !strcmp(m, "POST")) {
        C.setopt(c, OPT_POST, 1L);
        C.setopt(c, OPT_POSTFIELDSIZE_LARGE, (int64_t)(req->body ? req->body_len : 0));
        C.setopt(c, OPT_POSTFIELDS, req->body ? req->body : "");
        if (strcmp(m, "POST")) C.setopt(c, OPT_CUSTOMREQUEST, m);
    } else if (!strcmp(m, "HEAD")) {
        C.setopt(c, OPT_NOBODY, 1L);
    } else if (strcmp(m, "GET")) {
        C.setopt(c, OPT_CUSTOMREQUEST, m);
    }

    CURLcode rc = C.perform(c);
    collect(c, res);
    if (rc == E_OK && !x.delivered) {
        x.status = res->status;
        deliver(&x);
    }
    if (x.stop) {
        res->cancelled = 1;
        res->error = -999;
    } else {
        res->error = url_error(rc);
        if (rc) snprintf(res->message, sizeof res->message, "%s", errbuf[0] ? errbuf : "transfer failed");
    }
    if (x.upload) fclose(x.upload);
    free(x.hdr);
    C.slist_free_all(list);
    C.cleanup(c);
    return 0;
}
DX_EXPORT("_bitten_http_perform", bitten_http_perform);

/* ---- WebSockets ---- */

struct bn_ws {
    CURL *c;
    int fd;
    pthread_mutex_t lock;          /* around libcurl calls: sends and receives come from different threads */
    unsigned char *buf;            /* bytes received, not yet parsed */
    size_t len, cap;
    unsigned char *msg;            /* a fragmented message being put together */
    size_t mlen;
    int mop;
    int closed;
};

static const char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static void base64(const unsigned char *in, size_t n, char *out) {
    size_t o = 0;
    for (size_t i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)in[i] << 16 | (i + 1 < n ? (uint32_t)in[i + 1] << 8 : 0) | (i + 2 < n ? in[i + 2] : 0);
        out[o++] = b64[v >> 18 & 63];
        out[o++] = b64[v >> 12 & 63];
        out[o++] = i + 1 < n ? b64[v >> 6 & 63] : '=';
        out[o++] = i + 2 < n ? b64[v & 63] : '=';
    }
    out[o] = 0;
}

static double now_s(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static int raw_send(bn_ws *ws, const void *p, size_t n) {
    const char *b = p;
    while (n) {
        size_t sent = 0;
        pthread_mutex_lock(&ws->lock);
        CURLcode rc = C.send(ws->c, b, n, &sent);
        pthread_mutex_unlock(&ws->lock);
        if (rc == E_AGAIN) {
            struct pollfd pf = {ws->fd, POLLOUT, 0};
            poll(&pf, 1, 1000);
            continue;
        }
        if (rc) return -1005;
        b += sent;
        n -= sent;
    }
    return 0;
}

/* Reads what is there into ws->buf, waiting until the deadline (< 0:
 * forever). Returns bytes read, 0 at the deadline, or a negative code. */
static long raw_fill(bn_ws *ws, double deadline) {
    for (;;) {
        if (ws->cap - ws->len < 16384) {
            ws->cap = ws->cap * 2 + 32768;
            ws->buf = realloc(ws->buf, ws->cap);
        }
        size_t got = 0;
        pthread_mutex_lock(&ws->lock);
        CURLcode rc = C.recv(ws->c, ws->buf + ws->len, ws->cap - ws->len, &got);
        pthread_mutex_unlock(&ws->lock);
        if (rc == E_OK) {
            if (got == 0) return -1005; /* closed */
            ws->len += got;
            return (long)got;
        }
        if (rc != E_AGAIN) return -1005;
        int wait = 200;
        if (deadline >= 0) {
            double left = deadline - now_s();
            if (left <= 0) return 0;
            if (left * 1000 < wait) wait = (int)(left * 1000) + 1;
        }
        struct pollfd pf = {ws->fd, POLLIN, 0};
        poll(&pf, 1, wait);
    }
}

int bitten_ws_send(bn_ws *ws, int opcode, const void *data, size_t len) {
    if (!ws || ws->closed) return -1005;
    unsigned char head[14];
    size_t h = 0;
    head[h++] = 0x80 | (opcode & 15);
    if (len < 126) {
        head[h++] = 0x80 | (unsigned char)len;
    } else if (len < 65536) {
        head[h++] = 0x80 | 126;
        head[h++] = len >> 8;
        head[h++] = len & 255;
    } else {
        head[h++] = 0x80 | 127;
        for (int i = 7; i >= 0; i--) head[h++] = (uint64_t)len >> (8 * i) & 255;
    }
    unsigned char mask[4];
    if (getrandom(mask, 4, 0) != 4) memset(mask, 0x5a, 4);
    memcpy(head + h, mask, 4);
    h += 4;
    unsigned char *frame = malloc(h + len);
    memcpy(frame, head, h);
    for (size_t i = 0; i < len; i++) frame[h + i] = ((const unsigned char *)data)[i] ^ mask[i & 3];
    int r = raw_send(ws, frame, h + len);
    free(frame);
    if (opcode == BN_WS_CLOSE) ws->closed = 1;
    return r;
}
DX_EXPORT("_bitten_ws_send", bitten_ws_send);

/* Takes one whole frame from the buffer, if there is one. */
static int take_frame(bn_ws *ws, int *fin, int *op, unsigned char **payload, size_t *plen) {
    if (ws->len < 2) return 0;
    unsigned char *b = ws->buf;
    size_t h = 2;
    uint64_t n = b[1] & 127;
    if (n == 126) {
        if (ws->len < 4) return 0;
        n = (uint64_t)b[2] << 8 | b[3];
        h = 4;
    } else if (n == 127) {
        if (ws->len < 10) return 0;
        n = 0;
        for (int i = 0; i < 8; i++) n = n << 8 | b[2 + i];
        h = 10;
    }
    int masked = b[1] & 0x80;
    unsigned char mask[4] = {0};
    if (masked) {
        if (ws->len < h + 4) return 0;
        memcpy(mask, b + h, 4);
        h += 4;
    }
    if (ws->len < h + n) return 0;
    *fin = b[0] & 0x80;
    *op = b[0] & 15;
    *payload = malloc(n + 1);
    for (uint64_t i = 0; i < n; i++) (*payload)[i] = b[h + i] ^ (masked ? mask[i & 3] : 0);
    (*payload)[n] = 0;
    *plen = n;
    memmove(ws->buf, ws->buf + h + n, ws->len - h - n);
    ws->len -= h + n;
    return 1;
}

int bitten_ws_receive(bn_ws *ws, double timeout, void **data, size_t *len, int *code) {
    *data = NULL;
    *len = 0;
    double deadline = timeout < 0 ? -1 : now_s() + timeout;
    for (;;) {
        int fin, op;
        unsigned char *p;
        size_t n;
        while (take_frame(ws, &fin, &op, &p, &n)) {
            switch (op) {
            case BN_WS_PING:
                bitten_ws_send(ws, BN_WS_PONG, p, n);
                free(p);
                continue;
            case BN_WS_PONG:
                *data = p;
                *len = n;
                return BN_WS_PONG;
            case BN_WS_CLOSE:
                *code = n >= 2 ? p[0] << 8 | p[1] : 1005;
                if (!ws->closed) {
                    unsigned char echo[2] = {(unsigned char)(*code >> 8), (unsigned char)(*code & 255)};
                    bitten_ws_send(ws, BN_WS_CLOSE, echo, n >= 2 ? 2 : 0);
                }
                ws->closed = 1;
                if (n > 2) {
                    memmove(p, p + 2, n - 2);
                    *len = n - 2;
                    *data = p;
                } else {
                    free(p);
                }
                return BN_WS_CLOSE;
            case 0: /* continuation */
            case BN_WS_TEXT:
            case BN_WS_BINARY:
                if (op) ws->mop = op;
                ws->msg = realloc(ws->msg, ws->mlen + n + 1);
                memcpy(ws->msg + ws->mlen, p, n);
                ws->mlen += n;
                ws->msg[ws->mlen] = 0;
                free(p);
                if (fin) {
                    *data = ws->msg;
                    *len = ws->mlen;
                    ws->msg = NULL;
                    ws->mlen = 0;
                    return ws->mop;
                }
                continue;
            default:
                free(p);
                continue;
            }
        }
        long r = raw_fill(ws, deadline);
        if (r == 0) return 0;
        if (r < 0) return (int)r;
    }
}
DX_EXPORT("_bitten_ws_receive", bitten_ws_receive);

void bitten_ws_free(bn_ws *ws) {
    if (!ws) return;
    if (ws->c) C.cleanup(ws->c);
    pthread_mutex_destroy(&ws->lock);
    free(ws->buf);
    free(ws->msg);
    free(ws);
}
DX_EXPORT("_bitten_ws_free", bitten_ws_free);

/* "Name: value" of a header in a block of header lines, or NULL. */
static char *header_value(const char *block, const char *name) {
    size_t nl = strlen(name);
    for (const char *line = block; line && *line;) {
        const char *end = strstr(line, "\r\n");
        if (!end) end = line + strlen(line);
        if ((size_t)(end - line) > nl && !strncasecmp(line, name, nl) && line[nl] == ':') {
            const char *v = line + nl + 1;
            while (v < end && (*v == ' ' || *v == '\t')) v++;
            const char *e = end;
            while (e > v && (e[-1] == ' ' || e[-1] == '\t')) e--;
            return strndup(v, (size_t)(e - v));
        }
        line = *end ? end + 2 : end;
    }
    return NULL;
}

bn_ws *bitten_ws_open(const bn_http_request *req, const char *protocols, bn_http_result *res, char **protocol) {
    pthread_once(&loaded, load);
    memset(res, 0, sizeof *res);
    *protocol = NULL;
    if (!C.ok || !C.send || !C.recv) {
        res->error = -1009;
        return NULL;
    }
    /* ws:// and wss:// connect like http:// and https://. */
    const char *u = req->url;
    char *url;
    int secure = !strncasecmp(u, "wss://", 6), plain = !strncasecmp(u, "ws://", 5);
    if (secure) {
        url = malloc(strlen(u) + 3);
        sprintf(url, "https://%s", u + 6);
    } else if (plain) {
        url = malloc(strlen(u) + 3);
        sprintf(url, "http://%s", u + 5);
    } else {
        url = strdup(u);
    }
    const char *auth = strstr(url, "://");
    auth = auth ? auth + 3 : url;
    const char *path = strchr(auth, '/');
    char *host = strndup(auth, path ? (size_t)(path - auth) : strlen(auth));
    char *at = strrchr(host, '@');
    if (at) memmove(host, at + 1, strlen(at));
    if (!path) path = "/";
    char *frag = strchr(path, '#');
    char *target = strndup(path, frag ? (size_t)(frag - path) : strlen(path));

    bn_ws *ws = calloc(1, sizeof *ws);
    pthread_mutex_init(&ws->lock, NULL);
    ws->c = C.init();
    char errbuf[256] = "";
    bn_http_request conn = *req;
    conn.url = url;
    struct curl_slist *list = common_setup(ws->c, &conn, errbuf);
    C.slist_free_all(list);
    C.setopt(ws->c, OPT_HTTP_VERSION, 2L); /* 1.1: the upgrade is an HTTP/1.1 request */
    C.setopt(ws->c, OPT_CONNECT_ONLY, 1L);
    CURLcode rc = C.perform(ws->c);
    collect(ws->c, res);
    res->status = 0;
    int fd = -1; /* curl_socket_t */
    if (rc || C.getinfo(ws->c, INFO_ACTIVESOCKET, &fd) || fd < 0) {
        res->error = rc ? url_error(rc) : -1004;
        snprintf(res->message, sizeof res->message, "%s", errbuf[0] ? errbuf : "cannot connect");
        goto fail;
    }
    ws->fd = fd;

    /* The opening handshake. */
    unsigned char nonce[16];
    if (getrandom(nonce, sizeof nonce, 0) != sizeof nonce) memset(nonce, 7, sizeof nonce);
    char key[32];
    base64(nonce, sizeof nonce, key);
    size_t cap = 1024 + strlen(target) + strlen(host) + (protocols ? strlen(protocols) : 0);
    for (int i = 0; i < req->nheaders; i++) cap += strlen(req->headers[i]) + 2;
    char *hs = malloc(cap);
    int n = snprintf(hs, cap,
                     "GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                     "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n",
                     target, host, key);
    if (protocols && *protocols) n += snprintf(hs + n, cap - n, "Sec-WebSocket-Protocol: %s\r\n", protocols);
    for (int i = 0; i < req->nheaders; i++) n += snprintf(hs + n, cap - n, "%s\r\n", req->headers[i]);
    n += snprintf(hs + n, cap - n, "\r\n");
    int sr = raw_send(ws, hs, (size_t)n);
    free(hs);
    if (sr) {
        res->error = sr;
        goto fail;
    }
    double deadline = req->timeout > 0 ? now_s() + req->timeout : now_s() + 60;
    unsigned char *end = NULL;
    while (!(end = ws->len >= 4 ? memmem(ws->buf, ws->len, "\r\n\r\n", 4) : NULL)) {
        long r = raw_fill(ws, deadline);
        if (r <= 0) {
            res->error = r == 0 ? -1001 : -1005;
            goto fail;
        }
    }
    size_t hlen = (size_t)(end - ws->buf) + 4;
    char *head = strndup((char *)ws->buf, hlen);
    memmove(ws->buf, ws->buf + hlen, ws->len - hlen);
    ws->len -= hlen;
    const char *sp = strchr(head, ' ');
    res->status = sp ? strtol(sp + 1, NULL, 10) : 0;
    char *lines = strstr(head, "\r\n");
    lines = lines ? lines + 2 : head;
    int ok = res->status == 101;
    char *accept = header_value(lines, "Sec-WebSocket-Accept");
    uint8_t *(*sha1)(const void *, uint32_t, uint8_t *) = dx_registry_lookup("_CC_SHA1");
    if (ok && sha1) {
        char cat[96], expect[32];
        uint8_t digest[20];
        snprintf(cat, sizeof cat, "%s258EAFA5-E914-47DA-95CA-C5AB0DC85B11", key);
        sha1(cat, (uint32_t)strlen(cat), digest);
        base64(digest, 20, expect);
        ok = accept && !strcmp(accept, expect);
    }
    free(accept);
    *protocol = header_value(lines, "Sec-WebSocket-Protocol");
    free(head);
    if (!ok) {
        res->error = -1011;
        snprintf(res->message, sizeof res->message, "the server did not accept the WebSocket upgrade (status %ld)",
                 res->status);
        free(*protocol);
        *protocol = NULL;
        goto fail;
    }
    free(url);
    free(host);
    free(target);
    return ws;
fail:
    free(url);
    free(host);
    free(target);
    bitten_ws_free(ws);
    return NULL;
}
DX_EXPORT("_bitten_ws_open", bitten_ws_open);
