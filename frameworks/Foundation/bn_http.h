/* The interface between Foundation's URL loading (NSURLSession.m, Darwin
 * side) and the host's HTTP and TLS (src/frameworks/urlsession/http.c,
 * Linux side, over libcurl). Plain C types, laid out alike on both sides.
 * Every call blocks its caller; the callbacks run on the calling thread. */
#ifndef BITTEN_BN_HTTP_H
#define BITTEN_BN_HTTP_H
#include <stddef.h>
#include <stdint.h>

typedef struct bn_http_request {
    const char *method;
    const char *url;
    const char *const *headers;   /* "Name: value" */
    int nheaders;
    const void *body;             /* or NULL */
    size_t body_len;
    const char *body_file;        /* upload from this file instead, or NULL */
    double timeout;               /* idle timeout in seconds; 0 for none */
    double resource_timeout;      /* whole transfer; 0 for none */
    int decode;                   /* ask for and decode compressed bodies */
    uint16_t tls_min, tls_max;    /* tls_protocol_version_t; 0 for any */
} bn_http_request;

typedef struct bn_http_callbacks {
    void *ctx;
    /* The final response's status and headers ("Name: value\r\n"...),
     * before any of its body. Non-zero cancels. */
    int (*response)(void *ctx, long status, const char *headers, size_t headers_len);
    /* Body bytes. Non-zero cancels. */
    int (*data)(void *ctx, const void *bytes, size_t n);
    /* Progress, now and then. Non-zero cancels. */
    int (*progress)(void *ctx, int64_t down_total, int64_t down_now, int64_t up_total, int64_t up_now);
} bn_http_callbacks;

typedef struct bn_http_result {
    int error;                    /* an NSURLError code, 0 when the transfer worked */
    int cancelled;                /* a callback asked to stop */
    char message[256];
    long status;
    int http_version;             /* 10, 11, 20, 30 */
    uint16_t tls_version;         /* tls_protocol_version_t, 0 without TLS */
    uint16_t tls_cipher;
    double t_lookup, t_connect, t_tls, t_request, t_first_byte, t_total;   /* seconds from the start */
    int64_t header_bytes, request_bytes, upload_bytes, download_bytes;
    char local_ip[64], remote_ip[64];
    long local_port, remote_port;
    char redirect_url[4096];      /* the Location of a redirect, resolved; "" if none */
} bn_http_result;

/* Returns 0 when the transfer ran (result->error says how it ended), -1
 * when HTTP is not available at all (no libcurl). */
int bitten_http_perform(const bn_http_request *req, const bn_http_callbacks *cb, bn_http_result *res);

/* ---- WebSockets: a TCP (and TLS, for wss) connection, the opening
 * handshake, then whole messages in and out. ---- */

typedef struct bn_ws bn_ws;
enum { BN_WS_TEXT = 1, BN_WS_BINARY = 2, BN_WS_CLOSE = 8, BN_WS_PING = 9, BN_WS_PONG = 10 };

/* Connects and upgrades. On failure returns NULL with res->error set; on
 * success res->status is 101, res->tls_version the TLS version, and
 * *protocol (malloc'd, or NULL) the subprotocol the server chose. */
bn_ws *bitten_ws_open(const bn_http_request *req, const char *protocols, bn_http_result *res, char **protocol);
/* Sends one frame (fin set). Returns 0, or an NSURLError code. */
int bitten_ws_send(bn_ws *ws, int opcode, const void *data, size_t len);
/* Waits up to timeout seconds (< 0: forever) for a whole message: a text
 * or binary message (*data malloc'd), a close (*code set, *data its
 * reason), or a pong. Pings are answered here. Returns the opcode, 0 on
 * timeout, or a negative NSURLError code. */
int bitten_ws_receive(bn_ws *ws, double timeout, void **data, size_t *len, int *code);
void bitten_ws_free(bn_ws *ws);

#endif
