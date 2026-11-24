/* kqueue/kevent on top of epoll.
 *
 * A kqueue is an epoll descriptor plus bookkeeping. Read/write filters map
 * to one epoll registration per descriptor; user events use an eventfd,
 * timers a timerfd each, process-exit filters a pidfd, vnode filters an
 * inotify instance. epoll's `data` word carries a tag naming the source. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <unistd.h>

#include "darwin_abi.h"
#include "dx.h"

struct d_kevent {
    uintptr_t ident;
    int16_t filter;
    uint16_t flags;
    uint32_t fflags;
    intptr_t data;
    void *udata;
};

#define EVFILT_READ (-1)
#define EVFILT_WRITE (-2)
#define EVFILT_VNODE (-4)
#define EVFILT_PROC (-5)
#define EVFILT_SIGNAL (-6)
#define EVFILT_TIMER (-7)
#define EVFILT_USER (-10)

#define EV_ADD 0x0001
#define EV_DELETE 0x0002
#define EV_ENABLE 0x0004
#define EV_DISABLE 0x0008
#define EV_ONESHOT 0x0010
#define EV_CLEAR 0x0020
#define EV_RECEIPT 0x0040
#define EV_DISPATCH 0x0080
#define EV_ERROR 0x4000
#define EV_EOF 0x8000

#define NOTE_TRIGGER 0x01000000u
#define NOTE_FFAND 0x40000000u
#define NOTE_FFOR 0x80000000u
#define NOTE_FFCOPY 0xc0000000u
#define NOTE_FFCTRLMASK 0xc0000000u
#define NOTE_FFLAGSMASK 0x00ffffffu
#define NOTE_SECONDS 0x1
#define NOTE_USECONDS 0x2
#define NOTE_NSECONDS 0x4
#define NOTE_ABSOLUTE 0x8
#define NOTE_EXIT 0x80000000u
#define NOTE_EXITSTATUS 0x04000000u
#define NOTE_DELETE 0x1
#define NOTE_WRITE 0x2
#define NOTE_EXTEND 0x4
#define NOTE_ATTRIB 0x8
#define NOTE_LINK 0x10
#define NOTE_RENAME 0x20

enum { TAG_FD = 0, TAG_USER = 1, TAG_TIMER = 2, TAG_PROC = 3, TAG_VNODE = 4 };
#define TAG(t, id) (((uint64_t)(t) << 56) | (uint32_t)(id))

struct half { /* one of the read/write filters on a descriptor */
    unsigned registered : 1, disabled : 1;
    uint16_t flags;
    void *udata;
};
struct fdent {
    struct half r, w;
    uint32_t host_events;
    unsigned in_epoll : 1;
};
struct aux { /* user, timer, proc and vnode knotes */
    struct aux *next;
    int kind;
    uintptr_t ident;
    uint16_t flags;
    uint32_t fflags;
    void *udata;
    int fd;        /* timerfd / pidfd / inotify watch descriptor */
    int triggered; /* user events */
    int id;
    unsigned disabled : 1;
};
struct kq {
    int epfd, userfd, inofd;
    pthread_mutex_t lock;
    struct fdent *fds;
    int nfds;
    struct aux *aux;
    int next_id;
    struct d_kevent *pending;
    int npending, cap_pending;
};

#define MAX_FDS 1048576
static struct kq **kqs; /* indexed by the kqueue's descriptor */
static int kqs_cap;
static pthread_mutex_t kqs_lock = PTHREAD_MUTEX_INITIALIZER;

static struct kq *kq_get(int fd) {
    struct kq *k = NULL;
    pthread_mutex_lock(&kqs_lock);
    if (fd >= 0 && fd < kqs_cap) k = kqs[fd];
    pthread_mutex_unlock(&kqs_lock);
    return k;
}

static int d_kqueue(void) {
    int ep = epoll_create1(EPOLL_CLOEXEC);
    if (ep < 0) return DX_RET(-1);
    struct kq *k = calloc(1, sizeof *k);
    k->epfd = ep;
    k->userfd = k->inofd = -1;
    pthread_mutex_init(&k->lock, NULL);
    pthread_mutex_lock(&kqs_lock);
    if (ep >= kqs_cap) {
        int ncap = kqs_cap ? kqs_cap : 256;
        while (ncap <= ep) ncap *= 2;
        kqs = realloc(kqs, ncap * sizeof *kqs);
        memset(kqs + kqs_cap, 0, (ncap - kqs_cap) * sizeof *kqs);
        kqs_cap = ncap;
    }
    kqs[ep] = k;
    pthread_mutex_unlock(&kqs_lock);
    return ep;
}
DX_FN(kqueue);

static void aux_free(struct kq *k, struct aux *a) {
    if (a->kind == EVFILT_TIMER || a->kind == EVFILT_PROC) {
        if (a->fd >= 0) close(a->fd);
    } else if (a->kind == EVFILT_VNODE && k->inofd >= 0 && a->fd >= 0) {
        inotify_rm_watch(k->inofd, a->fd);
    }
    free(a);
}

/* close() hook: drop a closed kqueue, and forget closed descriptors. */
void dx_fd_closed(int fd) {
    if (fd < 0) return;
    pthread_mutex_lock(&kqs_lock);
    struct kq *dead = NULL;
    if (fd < kqs_cap && kqs[fd]) {
        dead = kqs[fd];
        kqs[fd] = NULL;
    }
    for (int i = 0; i < kqs_cap; i++) {
        struct kq *k = kqs[i];
        if (!k) continue;
        pthread_mutex_lock(&k->lock);
        if (fd < k->nfds) memset(&k->fds[fd], 0, sizeof k->fds[fd]);
        for (struct aux **pp = &k->aux; *pp;) {
            struct aux *a = *pp;
            if (a->kind == EVFILT_VNODE && a->ident == (uintptr_t)fd) {
                *pp = a->next;
                aux_free(k, a);
            } else pp = &a->next;
        }
        pthread_mutex_unlock(&k->lock);
    }
    pthread_mutex_unlock(&kqs_lock);
    if (dead) {
        while (dead->aux) {
            struct aux *a = dead->aux;
            dead->aux = a->next;
            aux_free(dead, a);
        }
        if (dead->userfd >= 0) close(dead->userfd);
        if (dead->inofd >= 0) close(dead->inofd);
        free(dead->fds);
        free(dead->pending);
        pthread_mutex_destroy(&dead->lock);
        free(dead);
    }
}

static struct fdent *fd_entry(struct kq *k, int fd) {
    if (fd < 0 || fd >= MAX_FDS) return NULL;
    if (fd >= k->nfds) {
        int n = k->nfds ? k->nfds : 64;
        while (n <= fd) n *= 2;
        k->fds = realloc(k->fds, n * sizeof *k->fds);
        memset(k->fds + k->nfds, 0, (n - k->nfds) * sizeof *k->fds);
        k->nfds = n;
    }
    return &k->fds[fd];
}

/* Bring the epoll registration in line with the active filters. Returns a
 * host errno. */
static int fd_sync(struct kq *k, int fd, struct fdent *e) {
    uint32_t ev = 0;
    int edge = 1, active = 0;
    if (e->r.registered && !e->r.disabled) {
        ev |= EPOLLIN | EPOLLRDHUP;
        active++;
        if (!(e->r.flags & EV_CLEAR)) edge = 0;
    }
    if (e->w.registered && !e->w.disabled) {
        ev |= EPOLLOUT;
        active++;
        if (!(e->w.flags & EV_CLEAR)) edge = 0;
    }
    if (active && edge) ev |= EPOLLET;
    struct epoll_event ee = {.events = ev, .data.u64 = TAG(TAG_FD, fd)};
    if (!active) {
        if (e->in_epoll) epoll_ctl(k->epfd, EPOLL_CTL_DEL, fd, NULL);
        e->in_epoll = 0;
        e->host_events = 0;
        return 0;
    }
    int r = epoll_ctl(k->epfd, e->in_epoll ? EPOLL_CTL_MOD : EPOLL_CTL_ADD, fd, &ee);
    if (r < 0 && errno == EEXIST) r = epoll_ctl(k->epfd, EPOLL_CTL_MOD, fd, &ee);
    if (r < 0 && errno == ENOENT) r = epoll_ctl(k->epfd, EPOLL_CTL_ADD, fd, &ee);
    if (r < 0) return errno;
    e->in_epoll = 1;
    e->host_events = ev;
    return 0;
}

static struct aux *aux_find(struct kq *k, int kind, uintptr_t ident) {
    for (struct aux *a = k->aux; a; a = a->next)
        if (a->kind == kind && a->ident == ident) return a;
    return NULL;
}
static struct aux *aux_by_id(struct kq *k, int kind, int id) {
    for (struct aux *a = k->aux; a; a = a->next)
        if (a->kind == kind && a->id == id) return a;
    return NULL;
}
static void aux_remove(struct kq *k, struct aux *a) {
    for (struct aux **pp = &k->aux; *pp; pp = &(*pp)->next)
        if (*pp == a) {
            *pp = a->next;
            break;
        }
    aux_free(k, a);
}
static struct aux *aux_new(struct kq *k, const struct d_kevent *c) {
    struct aux *a = calloc(1, sizeof *a);
    a->kind = c->filter;
    a->ident = c->ident;
    a->flags = c->flags & (EV_ONESHOT | EV_CLEAR | EV_DISPATCH);
    a->udata = c->udata;
    a->fd = -1;
    a->id = ++k->next_id;
    a->next = k->aux;
    k->aux = a;
    return a;
}

static int timer_arm(struct aux *a, const struct d_kevent *c) {
    int64_t v = c->data;
    struct timespec ts;
    if (c->fflags & NOTE_SECONDS) { ts.tv_sec = v; ts.tv_nsec = 0; }
    else if (c->fflags & NOTE_USECONDS) { ts.tv_sec = v / 1000000; ts.tv_nsec = (v % 1000000) * 1000; }
    else if (c->fflags & NOTE_NSECONDS) { ts.tv_sec = v / 1000000000; ts.tv_nsec = v % 1000000000; }
    else { ts.tv_sec = v / 1000; ts.tv_nsec = (v % 1000) * 1000000; }
    if (ts.tv_sec == 0 && ts.tv_nsec == 0) ts.tv_nsec = 1;
    struct itimerspec its = {.it_value = ts};
    int abs = (c->fflags & NOTE_ABSOLUTE) != 0;
    if (!(a->flags & EV_ONESHOT) && !abs) its.it_interval = ts;
    return timerfd_settime(a->fd, abs ? TFD_TIMER_ABSTIME : 0, &its, NULL) < 0 ? errno : 0;
}

/* Apply one change. Returns a host errno (0 on success). */
static int apply(struct kq *k, const struct d_kevent *c) {
    switch (c->filter) {
    case EVFILT_READ:
    case EVFILT_WRITE: {
        int fd = (int)c->ident;
        struct fdent *e = fd_entry(k, fd);
        if (!e) return EBADF;
        struct half *h = c->filter == EVFILT_READ ? &e->r : &e->w;
        struct half saved = *h;
        if (c->flags & EV_DELETE) {
            if (!h->registered) return ENOENT;
            memset(h, 0, sizeof *h);
        } else {
            if (c->flags & EV_ADD) {
                h->registered = 1;
                h->flags = c->flags & (EV_ONESHOT | EV_CLEAR | EV_DISPATCH);
                h->udata = c->udata;
                h->disabled = 0;
            } else if (!h->registered) return ENOENT;
            if (c->flags & EV_ENABLE) h->disabled = 0;
            if (c->flags & EV_DISABLE) h->disabled = 1;
        }
        int err = fd_sync(k, fd, e);
        if (err) {
            *h = saved;
            if (err == EPERM) {
                dx_log(1, "kevent: descriptor %d cannot be polled on Linux (regular file?)", fd);
                err = EOPNOTSUPP;
            }
        }
        return err;
    }
    case EVFILT_USER: {
        struct aux *a = aux_find(k, EVFILT_USER, c->ident);
        if (c->flags & EV_DELETE) {
            if (!a) return ENOENT;
            aux_remove(k, a);
            return 0;
        }
        if (k->userfd < 0) {
            k->userfd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
            if (k->userfd < 0) return errno;
            struct epoll_event ee = {.events = EPOLLIN, .data.u64 = TAG(TAG_USER, 0)};
            epoll_ctl(k->epfd, EPOLL_CTL_ADD, k->userfd, &ee);
        }
        if (!a) {
            if (!(c->flags & EV_ADD)) return ENOENT;
            a = aux_new(k, c);
        } else if (c->flags & EV_ADD) {
            a->flags = c->flags & (EV_ONESHOT | EV_CLEAR | EV_DISPATCH);
            a->udata = c->udata;
        }
        if (c->flags & EV_ENABLE) a->disabled = 0;
        if (c->flags & EV_DISABLE) a->disabled = 1;
        uint32_t ff = c->fflags & NOTE_FFLAGSMASK;
        switch (c->fflags & NOTE_FFCTRLMASK) {
        case NOTE_FFAND: a->fflags &= ff; break;
        case NOTE_FFOR: a->fflags |= ff; break;
        case NOTE_FFCOPY: a->fflags = ff; break;
        }
        if (c->fflags & NOTE_TRIGGER) {
            a->triggered = 1;
            uint64_t one = 1;
            ssize_t w = write(k->userfd, &one, sizeof one);
            (void)w;
        }
        return 0;
    }
    case EVFILT_TIMER: {
        struct aux *a = aux_find(k, EVFILT_TIMER, c->ident);
        if (c->flags & EV_DELETE) {
            if (!a) return ENOENT;
            aux_remove(k, a);
            return 0;
        }
        if (!a) {
            if (!(c->flags & EV_ADD)) return ENOENT;
            a = aux_new(k, c);
            a->fd = timerfd_create((c->fflags & NOTE_ABSOLUTE) ? CLOCK_REALTIME : CLOCK_MONOTONIC,
                                   TFD_CLOEXEC | TFD_NONBLOCK);
            if (a->fd < 0) {
                int e = errno;
                aux_remove(k, a);
                return e;
            }
            struct epoll_event ee = {.events = EPOLLIN, .data.u64 = TAG(TAG_TIMER, a->id)};
            epoll_ctl(k->epfd, EPOLL_CTL_ADD, a->fd, &ee);
        } else if (c->flags & EV_ADD) {
            a->flags = c->flags & (EV_ONESHOT | EV_CLEAR | EV_DISPATCH);
            a->udata = c->udata;
        }
        if (c->flags & EV_ADD) return timer_arm(a, c);
        return 0;
    }
    case EVFILT_PROC: {
        struct aux *a = aux_find(k, EVFILT_PROC, c->ident);
        if (c->flags & EV_DELETE) {
            if (!a) return ENOENT;
            aux_remove(k, a);
            return 0;
        }
        if (a) {
            a->udata = c->udata;
            a->fflags = c->fflags;
            return 0;
        }
        if (!(c->flags & EV_ADD)) return ENOENT;
        if (!(c->fflags & NOTE_EXIT)) return 0; /* fork/exec notes are not observable here */
        int pfd = (int)syscall(SYS_pidfd_open, (pid_t)c->ident, 0);
        if (pfd < 0) return errno;
        fcntl(pfd, F_SETFD, FD_CLOEXEC);
        a = aux_new(k, c);
        a->fd = pfd;
        a->fflags = c->fflags;
        struct epoll_event ee = {.events = EPOLLIN, .data.u64 = TAG(TAG_PROC, a->id)};
        epoll_ctl(k->epfd, EPOLL_CTL_ADD, pfd, &ee);
        return 0;
    }
    case EVFILT_VNODE: {
        struct aux *a = aux_find(k, EVFILT_VNODE, c->ident);
        if (c->flags & EV_DELETE) {
            if (!a) return ENOENT;
            aux_remove(k, a);
            return 0;
        }
        if (!(c->flags & EV_ADD) && !a) return ENOENT;
        if (k->inofd < 0) {
            k->inofd = inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
            if (k->inofd < 0) return errno;
            struct epoll_event ee = {.events = EPOLLIN, .data.u64 = TAG(TAG_VNODE, 0)};
            epoll_ctl(k->epfd, EPOLL_CTL_ADD, k->inofd, &ee);
        }
        char path[64];
        snprintf(path, sizeof path, "/proc/self/fd/%d", (int)c->ident);
        uint32_t mask = IN_DELETE_SELF | IN_MOVE_SELF | IN_ATTRIB | IN_MODIFY | IN_CREATE | IN_DELETE |
                        IN_MOVED_FROM | IN_MOVED_TO;
        int wd = inotify_add_watch(k->inofd, path, mask);
        if (wd < 0) return errno;
        if (!a) a = aux_new(k, c);
        a->fd = wd;
        a->fflags = c->fflags;
        a->udata = c->udata;
        a->flags = c->flags & (EV_ONESHOT | EV_CLEAR | EV_DISPATCH);
        return 0;
    }
    }
    dx_log(1, "kevent: unsupported filter %d", c->filter);
    return EINVAL;
}

static void push(struct kq *k, const struct d_kevent *ev) {
    if (k->npending == k->cap_pending) {
        k->cap_pending = k->cap_pending ? k->cap_pending * 2 : 32;
        k->pending = realloc(k->pending, k->cap_pending * sizeof *k->pending);
    }
    k->pending[k->npending++] = *ev;
}

static void after_delivery(struct half *h) {
    if (h->flags & EV_ONESHOT) memset(h, 0, sizeof *h);
    else if (h->flags & EV_DISPATCH) h->disabled = 1;
}

/* Translate one epoll event into pending kevents. Caller holds the lock. */
static void translate(struct kq *k, const struct epoll_event *ee) {
    int tag = (int)(ee->data.u64 >> 56);
    int id = (int)(uint32_t)ee->data.u64;
    struct d_kevent out;
    memset(&out, 0, sizeof out);
    switch (tag) {
    case TAG_FD: {
        if (id >= k->nfds) return;
        struct fdent *e = &k->fds[id];
        int changed = 0;
        int eof = (ee->events & (EPOLLHUP | EPOLLRDHUP | EPOLLERR)) != 0;
        if ((ee->events & (EPOLLIN | EPOLLHUP | EPOLLRDHUP | EPOLLERR)) && e->r.registered && !e->r.disabled) {
            int avail = 0;
            if (ioctl(id, FIONREAD, &avail) < 0) avail = 0;
            out.ident = id;
            out.filter = EVFILT_READ;
            out.flags = EV_ADD | e->r.flags | (eof ? EV_EOF : 0);
            out.data = avail ? avail : ((ee->events & EPOLLIN) ? 1 : 0);
            out.udata = e->r.udata;
            if (ee->events & EPOLLERR) {
                int soerr = 0;
                socklen_t sl = sizeof soerr;
                if (getsockopt(id, SOL_SOCKET, SO_ERROR, &soerr, &sl) == 0)
                    out.fflags = dx_errno_to_darwin(soerr);
            }
            push(k, &out);
            if (e->r.flags & (EV_ONESHOT | EV_DISPATCH)) { after_delivery(&e->r); changed = 1; }
        }
        if ((ee->events & (EPOLLOUT | EPOLLHUP | EPOLLERR)) && e->w.registered && !e->w.disabled) {
            memset(&out, 0, sizeof out);
            int weof = (ee->events & (EPOLLHUP | EPOLLERR)) != 0;
            out.ident = id;
            out.filter = EVFILT_WRITE;
            out.flags = EV_ADD | e->w.flags | (weof ? EV_EOF : 0);
            out.data = 65536;
            out.udata = e->w.udata;
            push(k, &out);
            if (e->w.flags & (EV_ONESHOT | EV_DISPATCH)) { after_delivery(&e->w); changed = 1; }
        }
        if (changed) fd_sync(k, id, e);
        break;
    }
    case TAG_USER: {
        int still = 0;
        for (struct aux *a = k->aux, *next; a; a = next) {
            next = a->next;
            if (a->kind != EVFILT_USER || !a->triggered || a->disabled) continue;
            out.ident = a->ident;
            out.filter = EVFILT_USER;
            out.flags = EV_ADD | a->flags;
            out.fflags = a->fflags;
            out.udata = a->udata;
            push(k, &out);
            if (a->flags & EV_ONESHOT) aux_remove(k, a);
            else if (a->flags & (EV_CLEAR | EV_DISPATCH)) {
                a->triggered = 0;
                if (a->flags & EV_DISPATCH) a->disabled = 1;
            } else still = 1;
        }
        if (!still) {
            uint64_t v;
            ssize_t r = read(k->userfd, &v, sizeof v);
            (void)r;
        }
        break;
    }
    case TAG_TIMER: {
        struct aux *a = aux_by_id(k, EVFILT_TIMER, id);
        if (!a) return;
        uint64_t n = 0;
        if (read(a->fd, &n, sizeof n) != sizeof n || !n) return;
        out.ident = a->ident;
        out.filter = EVFILT_TIMER;
        out.flags = EV_ADD | a->flags;
        out.data = (intptr_t)n;
        out.udata = a->udata;
        push(k, &out);
        if (a->flags & EV_ONESHOT) aux_remove(k, a);
        break;
    }
    case TAG_PROC: {
        struct aux *a = aux_by_id(k, EVFILT_PROC, id);
        if (!a) return;
        out.ident = a->ident;
        out.filter = EVFILT_PROC;
        out.flags = EV_ADD | EV_EOF | a->flags;
        out.fflags = NOTE_EXIT;
        if (a->fflags & NOTE_EXITSTATUS) {
            siginfo_t si;
            memset(&si, 0, sizeof si);
            if (waitid(P_PID, (id_t)a->ident, &si, WEXITED | WNOHANG | WNOWAIT) == 0 && si.si_pid) {
                int st = si.si_code == CLD_EXITED ? (si.si_status & 0xff) << 8
                                                  : dx_sig_from_host(si.si_status);
                out.data = st;
                out.fflags |= NOTE_EXITSTATUS;
            }
        }
        out.udata = a->udata;
        push(k, &out);
        aux_remove(k, a);
        break;
    }
    case TAG_VNODE: {
        char buf[4096] __attribute__((aligned(8)));
        ssize_t n;
        while ((n = read(k->inofd, buf, sizeof buf)) > 0) {
            for (char *p = buf; p < buf + n;) {
                struct inotify_event *ie = (void *)p;
                p += sizeof *ie + ie->len;
                struct aux *a = NULL;
                for (struct aux *x = k->aux; x; x = x->next)
                    if (x->kind == EVFILT_VNODE && x->fd == ie->wd) a = x;
                if (!a || a->disabled) continue;
                uint32_t note = 0;
                if (ie->mask & IN_DELETE_SELF) note |= NOTE_DELETE;
                if (ie->mask & IN_MOVE_SELF) note |= NOTE_RENAME;
                if (ie->mask & IN_MODIFY) note |= NOTE_WRITE | NOTE_EXTEND;
                if (ie->mask & (IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO)) {
                    note |= NOTE_WRITE;
                    if (ie->mask & IN_ISDIR) note |= NOTE_LINK;
                }
                if (ie->mask & IN_ATTRIB) {
                    struct stat st;
                    note |= NOTE_ATTRIB;
                    if (fstat((int)a->ident, &st) == 0 && st.st_nlink == 0) note |= NOTE_DELETE;
                }
                note &= a->fflags;
                if (!note) continue;
                memset(&out, 0, sizeof out);
                out.ident = a->ident;
                out.filter = EVFILT_VNODE;
                out.flags = EV_ADD | a->flags;
                out.fflags = note;
                out.udata = a->udata;
                push(k, &out);
                if (a->flags & EV_ONESHOT) aux_remove(k, a);
                else if (a->flags & EV_DISPATCH) a->disabled = 1;
            }
        }
        break;
    }
    }
}

static int take_pending(struct kq *k, struct d_kevent *out, int room) {
    int n = k->npending < room ? k->npending : room;
    if (n > 0) {
        memcpy(out, k->pending, n * sizeof *out);
        memmove(k->pending, k->pending + n, (k->npending - n) * sizeof *out);
        k->npending -= n;
    }
    return n;
}

static int d_kevent(int kqfd, const struct d_kevent *changes, int nchanges, struct d_kevent *events,
                    int nevents, const struct timespec *timeout) {
    struct kq *k = kq_get(kqfd);
    if (!k) {
        dx_set_errno(9); /* EBADF */
        return -1;
    }
    int nout = 0;
    pthread_mutex_lock(&k->lock);
    for (int i = 0; i < nchanges; i++) {
        int err = apply(k, &changes[i]);
        if (err || (changes[i].flags & EV_RECEIPT)) {
            if (nout < nevents) {
                events[nout] = changes[i];
                events[nout].flags = EV_ERROR;
                events[nout].data = dx_errno_to_darwin(err);
                nout++;
            } else if (err) {
                pthread_mutex_unlock(&k->lock);
                dx_set_errno(dx_errno_to_darwin(err));
                return -1;
            }
        }
    }
    if (nout || nevents <= 0) {
        pthread_mutex_unlock(&k->lock);
        return nout;
    }
    nout = take_pending(k, events, nevents);
    pthread_mutex_unlock(&k->lock);
    if (nout) return nout;

    struct timespec deadline;
    if (timeout) {
        clock_gettime(CLOCK_MONOTONIC, &deadline);
        deadline.tv_sec += timeout->tv_sec;
        deadline.tv_nsec += timeout->tv_nsec;
        if (deadline.tv_nsec >= 1000000000L) {
            deadline.tv_sec++;
            deadline.tv_nsec -= 1000000000L;
        }
    }
    for (;;) {
        struct epoll_event evs[64];
        int max = nevents < 64 ? nevents : 64;
        struct timespec left, *lp = NULL;
        if (timeout) {
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            left.tv_sec = deadline.tv_sec - now.tv_sec;
            left.tv_nsec = deadline.tv_nsec - now.tv_nsec;
            if (left.tv_nsec < 0) {
                left.tv_sec--;
                left.tv_nsec += 1000000000L;
            }
            if (left.tv_sec < 0) left.tv_sec = left.tv_nsec = 0;
            lp = &left;
        }
        int n = (int)syscall(SYS_epoll_pwait2, k->epfd, evs, max, lp, NULL, 0);
        if (n < 0 && errno == ENOSYS) {
            int ms = lp ? (int)(lp->tv_sec * 1000 + (lp->tv_nsec + 999999) / 1000000) : -1;
            n = epoll_wait(k->epfd, evs, max, ms);
        }
        if (n < 0) return DX_RET(-1);
        pthread_mutex_lock(&k->lock);
        for (int i = 0; i < n; i++) translate(k, &evs[i]);
        nout = take_pending(k, events, nevents);
        pthread_mutex_unlock(&k->lock);
        if (nout) return nout;
        if (n == 0) return 0; /* timed out */
        /* events were consumed without producing output (stale); wait again */
        if (timeout && left.tv_sec == 0 && left.tv_nsec == 0) return 0;
    }
}
DX_FN(kevent);

/* kevent64 uses a wider record; convert through the plain form. */
struct d_kevent64 {
    uint64_t ident;
    int16_t filter;
    uint16_t flags;
    uint32_t fflags;
    int64_t data;
    uint64_t udata;
    uint64_t ext[2];
};
static int d_kevent64(int kqfd, const struct d_kevent64 *changes, int nchanges, struct d_kevent64 *events,
                      int nevents, unsigned flags, const struct timespec *timeout) {
    (void)flags;
    struct d_kevent *ch = nchanges > 0 ? alloca(nchanges * sizeof *ch) : NULL;
    struct d_kevent *ev = nevents > 0 ? alloca(nevents * sizeof *ev) : NULL;
    for (int i = 0; i < nchanges; i++)
        ch[i] = (struct d_kevent){changes[i].ident, changes[i].filter, changes[i].flags,
                                  changes[i].fflags, changes[i].data, (void *)changes[i].udata};
    int n = d_kevent(kqfd, ch, nchanges, ev, nevents, timeout);
    for (int i = 0; i < n; i++)
        events[i] = (struct d_kevent64){ev[i].ident, ev[i].filter, ev[i].flags, ev[i].fflags,
                                        ev[i].data, (uint64_t)ev[i].udata, {0, 0}};
    return n;
}
DX_FN(kevent64);
