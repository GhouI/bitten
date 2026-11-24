#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "zlib_internal.h"

enum { GZ_BUFFER = 8192 };
enum input_mode { LOOK, COPY, MEMBER, NO_MORE };

struct mode {
    char access;
    int level, strategy, direct, exclusive, cloexec;
};

struct gzfile {
    /* Public gzFile prefix used by the gzgetc macro. */
    unsigned have;
    uint8_t *next;
    uint64_t pos;
    int fd, file_eof, past_eof, seen_member, error, host_error;
    struct mode mode;
    enum input_mode input_mode;
    char message[160];
    dz_stream stream;
    uint8_t input[GZ_BUFFER], output[GZ_BUFFER];
};

static int parse_mode(const char *p, struct mode *m) {
    if (!p) return 0;
    *m = (struct mode){.level = -1};
    for (; *p; p++) {
        switch (*p) {
        case 'r': case 'w': case 'a': m->access = *p; break;
        case '+': return 0;
        case 'T': m->direct = 1; break;
        case 'x': m->exclusive = 1; break;
        case 'e': m->cloexec = 1; break;
        case 'f': m->strategy = 1; break;
        case 'h': m->strategy = 2; break;
        case 'R': m->strategy = 3; break;
        case 'F': m->strategy = 4; break;
        default:
            if (*p >= '0' && *p <= '9') m->level = *p - '0';
            break;
        }
    }
    return m->access && !(m->access == 'r' && m->direct);
}

static int gz_fail(struct gzfile *f, int error, const char *message) {
    f->error = error;
    if (error == Z_ERRNO) {
        f->host_error = errno;
        dx_set_errno(dx_errno_to_darwin(errno));
        message = strerror(errno);
    }
    snprintf(f->message, sizeof f->message, "%s", message ? message : "gzip operation failed");
    return -1;
}

static struct gzfile *open_fd(int fd, const struct mode *m) {
    struct gzfile *f = calloc(1, sizeof *f);
    if (!f) {
        dx_set_errno(dx_errno_to_darwin(ENOMEM));
        return NULL;
    }
    f->fd = fd;
    f->mode = *m;
    if (m->cloexec && fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) {
        dx_set_errno(dx_errno_to_darwin(errno));
        free(f);
        return NULL;
    }
    if (m->access == 'a') lseek(fd, 0, SEEK_END);
    return f;
}

static struct gzfile *d_gzopen(const char *path, const char *mode) {
    struct mode m;
    if (!path || !parse_mode(mode, &m)) {
        dx_set_errno(22);
        return NULL;
    }
    int flags = m.access == 'r' ? O_RDONLY : O_WRONLY | O_CREAT;
    if (m.access == 'a') flags |= O_APPEND;
    if (m.access == 'w') flags |= O_TRUNC;
    if (m.exclusive && m.access != 'r') flags |= O_EXCL;
    if (m.cloexec) flags |= O_CLOEXEC;
    char mapped[PATH_MAX];
    int fd = DX_RET(open(dx_path(path, mapped, sizeof mapped), flags, 0666));
    if (fd < 0) return NULL;
    /* open() already applied O_CLOEXEC atomically. */
    m.cloexec = 0;
    struct gzfile *f = open_fd(fd, &m);
    if (!f) close(fd);
    return f;
}
DX_FN(gzopen);

static struct gzfile *d_gzdopen(int fd, const char *mode) {
    struct mode m;
    if (fd < 0 || !parse_mode(mode, &m)) {
        dx_set_errno(22);
        return NULL;
    }
    return open_fd(fd, &m);
}
DX_FN(gzdopen);

static int load_input(struct gzfile *f, unsigned needed) {
    dz_stream *s = &f->stream;
    if (s->avail_in >= needed || f->file_eof) return 0;
    if (s->avail_in) memmove(f->input, s->next_in, s->avail_in);
    s->next_in = f->input;
    while (s->avail_in < needed) {
        ssize_t n = read(f->fd, f->input + s->avail_in, sizeof f->input - s->avail_in);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) return gz_fail(f, Z_ERRNO, NULL);
        if (!n) {
            f->file_eof = 1;
            break;
        }
        s->avail_in += n;
    }
    return 0;
}

static int load_output(struct gzfile *f) {
    dz_stream *s = &f->stream;
    while (!f->error && !f->have && f->input_mode != NO_MORE) {
        switch (f->input_mode) {
        case LOOK:
            if (load_input(f, 2) < 0) return -1;
            if (s->avail_in >= 2 && s->next_in[0] == 0x1f && s->next_in[1] == 0x8b) {
                const uint8_t *input = s->next_in;
                unsigned n = s->avail_in;
                int status = dz_inflate_init(s, 31, DZ_VERSION, sizeof *s);
                if (status != Z_OK) return gz_fail(f, status, "could not initialize gzip decoder");
                s->next_in = input;
                s->avail_in = n;
                f->seen_member = 1;
                f->input_mode = MEMBER;
            } else {
                f->input_mode = f->seen_member ? NO_MORE : COPY;
            }
            break;
        case COPY:
            if (load_input(f, 1) < 0) return -1;
            if (!s->avail_in) {
                f->input_mode = NO_MORE;
                break;
            }
            f->have = s->avail_in;
            memcpy(f->output, s->next_in, f->have);
            s->avail_in = 0;
            break;
        case MEMBER: {
            s->next_out = f->output;
            s->avail_out = sizeof f->output;
            int status = dz_inflate(s, Z_NO_FLUSH);
            f->have = sizeof f->output - s->avail_out;
            if (status == Z_STREAM_END) {
                dz_inflate_end(s);
                f->input_mode = LOOK;
            } else if (status == Z_BUF_ERROR && !s->avail_in) {
                if (f->file_eof) gz_fail(f, Z_BUF_ERROR, "unexpected end of gzip file");
                else if (load_input(f, 1) < 0) return -1;
            } else if (status != Z_OK) {
                gz_fail(f, status, s->msg);
            }
            break;
        }
        case NO_MORE:
            break;
        }
    }
    f->next = f->output;
    if (f->have) return 1;
    if (f->error && f->error != Z_BUF_ERROR) return -1;
    f->past_eof = 1;
    return 0;
}

static void consume(struct gzfile *f, void *out, unsigned n) {
    memcpy(out, f->next, n);
    f->next += n;
    f->have -= n;
    f->pos += n;
}

static int d_gzread(struct gzfile *f, void *out, unsigned len) {
    if (!f || f->mode.access != 'r') return -1;
    if (len > INT_MAX || (!out && len)) return gz_fail(f, Z_STREAM_ERROR, "invalid gzip read length");
    unsigned done = 0;
    while (done < len) {
        int got = f->have ? 1 : load_output(f);
        if (got <= 0) return got < 0 && !done ? -1 : (int)done;
        unsigned n = len - done < f->have ? len - done : f->have;
        consume(f, (uint8_t *)out + done, n);
        done += n;
    }
    return done;
}
DX_FN(gzread);

static char *d_gzgets(struct gzfile *f, char *out, int len) {
    if (!f || f->mode.access != 'r' || !out || len < 1) return NULL;
    unsigned done = 0;
    while (done < (unsigned)len - 1) {
        if (!f->have && load_output(f) <= 0) break;
        unsigned n = (unsigned)len - 1 - done;
        if (n > f->have) n = f->have;
        const uint8_t *newline = memchr(f->next, '\n', n);
        if (newline) n = newline - f->next + 1;
        consume(f, out + done, n);
        done += n;
        if (newline) break;
    }
    if (!done) return NULL;
    out[done] = '\0';
    return out;
}
DX_FN(gzgets);

static int write_all(struct gzfile *f, const uint8_t *p, unsigned left) {
    while (left) {
        ssize_t n = write(f->fd, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) {
            if (!n) errno = EIO;
            return gz_fail(f, Z_ERRNO, NULL);
        }
        left -= n;
        p += n;
    }
    return 0;
}

static int write_gzip(struct gzfile *f, const uint8_t *data, unsigned size, int flush) {
    dz_stream *s = &f->stream;
    if (!s->state) {
        int status = dz_deflate_init(s, f->mode.level, Z_DEFLATED, 31, 8, f->mode.strategy,
                                     DZ_VERSION, sizeof *s);
        if (status != Z_OK) return gz_fail(f, status, "could not initialize gzip encoder");
    }
    s->next_in = data;
    s->avail_in = size;
    do {
        s->next_out = f->output;
        s->avail_out = sizeof f->output;
        int status = dz_deflate(s, flush);
        if (status != Z_OK && status != Z_STREAM_END) return gz_fail(f, status, s->msg);
        if (write_all(f, f->output, sizeof f->output - s->avail_out)) return -1;
        if (status == Z_STREAM_END) return 0;
    } while (s->avail_in || flush == Z_FINISH);
    return 0;
}

static int d_gzwrite(struct gzfile *f, const void *p, unsigned len) {
    if (!f || f->mode.access == 'r' || f->error || !len) return 0;
    if (len > INT_MAX || !p) {
        gz_fail(f, Z_STREAM_ERROR, "invalid gzip write length");
        return 0;
    }
    int status = f->mode.direct ? write_all(f, p, len) : write_gzip(f, p, len, Z_NO_FLUSH);
    if (status) return 0;
    f->pos += len;
    return len;
}
DX_FN(gzwrite);

static int d_gzputs(struct gzfile *f, const char *str) {
    if (!f || f->mode.access == 'r' || f->error || !str) return -1;
    size_t len = strlen(str);
    if (len > INT_MAX) return gz_fail(f, Z_STREAM_ERROR, "invalid gzip write length");
    return d_gzwrite(f, str, len) == (int)len ? (int)len : -1;
}
DX_FN(gzputs);

static int d_gzeof(struct gzfile *f) { return f && f->mode.access == 'r' && f->past_eof; }
DX_FN(gzeof);

static const char *d_gzerror(struct gzfile *f, int *code) {
    if (code) *code = f ? f->error : Z_STREAM_ERROR;
    if (!f) return NULL;
    if (f->error == Z_ERRNO) dx_set_errno(dx_errno_to_darwin(f->host_error));
    return f->message;
}
DX_FN(gzerror);

static int d_gzclose(struct gzfile *f) {
    if (!f) return Z_STREAM_ERROR;
    dz_stream *s = &f->stream;
    if (f->mode.access == 'r') {
        if (s->state) dz_inflate_end(s);
    } else if (!f->mode.direct) {
        if (!f->error) write_gzip(f, NULL, 0, Z_FINISH);
        if (s->state) dz_deflate_end(s);
    }
    int status = f->error;
    if (close(f->fd) < 0) {
        dx_set_errno(dx_errno_to_darwin(errno));
        status = Z_ERRNO;
    }
    free(f);
    return status;
}
DX_FN(gzclose);
