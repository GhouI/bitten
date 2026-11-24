#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
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
#include <unistd.h>

#include "internal.h"

enum source_kind { SRC_TIMER, SRC_READ, SRC_WRITE, SRC_SIGNAL, SRC_PROC, SRC_ADD, SRC_OR, SRC_VNODE };

struct source_type { enum source_kind kind; };
static const struct source_type timer_type = { SRC_TIMER }, read_type = { SRC_READ },
    write_type = { SRC_WRITE }, signal_type = { SRC_SIGNAL }, proc_type = { SRC_PROC },
    add_type = { SRC_ADD }, or_type = { SRC_OR }, vnode_type = { SRC_VNODE };

#define EXPORT_TYPE(name, type) \
    DX_EXPORT("_dispatch_source_type_" #name, &type); \
    DX_EXPORT("__dispatch_source_type_" #name, &type)

EXPORT_TYPE(timer, timer_type);
EXPORT_TYPE(read, read_type);
EXPORT_TYPE(write, write_type);
EXPORT_TYPE(signal, signal_type);
EXPORT_TYPE(proc, proc_type);
EXPORT_TYPE(data_add, add_type);
EXPORT_TYPE(data_or, or_type);
EXPORT_TYPE(vnode, vnode_type);

enum {
    PROC_EXIT = 0x80000000u,
    VNODE_DELETE = 0x01, VNODE_WRITE = 0x02, VNODE_EXTEND = 0x04, VNODE_ATTRIB = 0x08,
    VNODE_LINK = 0x10, VNODE_RENAME = 0x20, VNODE_REVOKE = 0x40,
};

struct source_handler {
    void *block;
    dispatch_function fn;
};

struct dispatch_source {
    struct dispatch_object object;
    struct dispatch_source *next;
    enum source_kind kind;
    uintptr_t handle;
    unsigned long mask, data;
    struct source_handler event, registration, cancel;
    atomic_uint public_refs;
    uint64_t token;
    int fd, vnode_fd, host_signal;
    clockid_t timer_clock;
    off_t vnode_size;
    nlink_t vnode_links;
    unsigned suspended;
    bool active, canceled, registered, cancel_delivered, pending_data;
    bool submitted, event_running, event_barrier, epoll_added, armed, fallback, exited;
};

struct source_event {
    struct dispatch_source *source;
    unsigned long data;
    struct source_event *previous;
};

static _Thread_local struct source_event *current_event;
static pthread_mutex_t source_lock = PTHREAD_MUTEX_INITIALIZER;
static struct dispatch_source *active_sources;
static int manager_epoll = -1, manager_wake = -1;
static uint64_t next_token = NSIG;

struct signal_observer {
    struct sigaction prior;
    int fd;
    struct signal_observer *retired_next;
};

static _Atomic(struct signal_observer *) signal_observers[NSIG];
static atomic_uint signal_readers[NSIG];
static struct signal_observer *retired_observers[NSIG];
static unsigned signal_users[NSIG];

static bool is_rw(const struct dispatch_source *source) {
    return source->kind == SRC_READ || source->kind == SRC_WRITE;
}

static bool has_handler(struct source_handler handler) {
    return handler.fn || handler.block;
}

static void wake_manager(void) {
    uint64_t one = 1;
    ssize_t n;
    do n = write(manager_wake, &one, sizeof one); while (n < 0 && errno == EINTR);
    if (n != sizeof one && errno != EAGAIN)
        dx_fatal("dispatch: source manager wakeup failed: %s", strerror(errno));
}

static uint64_t read_counter(int fd) {
    uint64_t value;
    ssize_t n;
    do n = read(fd, &value, sizeof value); while (n < 0 && errno == EINTR);
    return n == sizeof value ? value : 0;
}

static void signal_observe(int sig, siginfo_t *info, void *context) {
    int saved_errno = errno;
    atomic_fetch_add(&signal_readers[sig], 1);
    struct signal_observer *observer = atomic_load(&signal_observers[sig]);
    struct sigaction prior = observer->prior;
    int fd = observer->fd;
    atomic_fetch_sub(&signal_readers[sig], 1);

    uint64_t one = 1;
    ssize_t n;
    do n = write(fd, &one, sizeof one); while (n < 0 && errno == EINTR);
    errno = saved_errno;
    if (prior.sa_handler == SIG_IGN) return;
    if (prior.sa_handler != SIG_DFL) {
        if (prior.sa_flags & SA_SIGINFO) prior.sa_sigaction(sig, info, context);
        else prior.sa_handler(sig);
    } else if (sig != SIGCHLD && sig != SIGCONT && sig != SIGURG && sig != SIGWINCH) {
        sigaction(sig, &prior, NULL);
        raise(sig);
    }
}

static void reap_observers(int sig) {
    if (atomic_load(&signal_readers[sig])) return;
    while (retired_observers[sig]) {
        struct signal_observer *old = retired_observers[sig];
        retired_observers[sig] = old->retired_next;
        free(old);
    }
}

static bool is_observer(const struct sigaction *action) {
    return (action->sa_flags & SA_SIGINFO) && action->sa_sigaction == signal_observe;
}

static bool add_signal_observer(int sig) {
    struct sigaction prior = {0};
    if (sigaction(sig, NULL, &prior) < 0) return false;
    if (!is_observer(&prior)) {
        struct signal_observer *old = atomic_load_explicit(&signal_observers[sig], memory_order_relaxed);
        if (!old || old->prior.sa_sigaction != prior.sa_sigaction ||
            old->prior.sa_flags != prior.sa_flags ||
            memcmp(&old->prior.sa_mask, &prior.sa_mask, sizeof prior.sa_mask) != 0) {
            int fd = old ? old->fd : eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
            if (fd < 0) return false;
            if (!old) {
                struct epoll_event ev = { .events = EPOLLIN, .data.u64 = (uint64_t)sig };
                if (epoll_ctl(manager_epoll, EPOLL_CTL_ADD, fd, &ev) < 0) {
                    close(fd);
                    return false;
                }
            }
            /* A signal handler may still be copying the previous disposition. */
            struct signal_observer *observer = dispatch_alloc(sizeof *observer);
            *observer = (struct signal_observer){ .prior = prior, .fd = fd };
            if (!signal_users[sig]) read_counter(fd);
            atomic_store(&signal_observers[sig], observer);
            if (old) {
                old->retired_next = retired_observers[sig];
                retired_observers[sig] = old;
            }
            reap_observers(sig);
        } else if (!signal_users[sig]) {
            read_counter(old->fd);
        }

        /* Preserve the current Darwin handler through the host shim.
         * A later sigaction() replaces the observer until the next registration. */
        struct sigaction action = prior;
        action.sa_sigaction = signal_observe;
        action.sa_flags |= SA_SIGINFO;
        if (sig == SIGCHLD && prior.sa_handler == SIG_IGN) action.sa_flags |= SA_NOCLDWAIT;
        if (sigaction(sig, &action, NULL) < 0) return false;
    }
    ++signal_users[sig];
    return true;
}

static void remove_signal_observer(int sig) {
    if (--signal_users[sig]) return;
    struct sigaction action;
    struct signal_observer *observer = atomic_load_explicit(&signal_observers[sig], memory_order_relaxed);
    if (sigaction(sig, NULL, &action) == 0 && is_observer(&action))
        sigaction(sig, &observer->prior, NULL);
}

static void source_try_submit(struct dispatch_source *source);

static void merge_data(struct dispatch_source *source, unsigned long data) {
    if (source->canceled) return;
    switch (source->kind) {
    case SRC_ADD: case SRC_TIMER: case SRC_SIGNAL:
        source->data += data;
        break;
    case SRC_OR: case SRC_PROC: case SRC_VNODE:
        source->data |= data;
        break;
    case SRC_READ: case SRC_WRITE:
        source->data = data;
        break;
    }
    source->pending_data = source->data || is_rw(source);
    source_try_submit(source);
}

static void detach_fd(struct dispatch_source *source) {
    if (source->epoll_added) epoll_ctl(manager_epoll, EPOLL_CTL_DEL, source->fd, NULL);
    source->epoll_added = source->armed = source->fallback = false;
    source->token = 0;
}

static void arm_fd(struct dispatch_source *source) {
    if (source->fd < 0 || !source->active || source->canceled || source->armed || source->exited)
        return;
    if (is_rw(source) && (source->pending_data || source->event_running)) return;
    if (!source->token) source->token = ++next_token;
    struct epoll_event ev = { .events = EPOLLIN, .data.u64 = source->token };
    if (is_rw(source)) ev.events = EPOLLONESHOT | (source->kind == SRC_READ ? EPOLLIN : EPOLLOUT);
    if (source->kind == SRC_PROC) ev.events |= EPOLLONESHOT;

    if (source->fallback) {
        source->armed = true;
        wake_manager();
        return;
    }

    int operation = source->epoll_added ? EPOLL_CTL_MOD : EPOLL_CTL_ADD;
    if (epoll_ctl(manager_epoll, operation, source->fd, &ev) == 0) {
        source->epoll_added = source->armed = true;
    } else if (errno == EPERM && is_rw(source)) {
        source->fallback = source->armed = true;
        wake_manager();
    } else {
        dx_log(1, "dispatch: source epoll registration failed: %s", strerror(errno));
    }
}

static unsigned long write_space(int fd) {
    int capacity = fcntl(fd, F_GETPIPE_SZ);
    int used;
    if (capacity >= 0 && ioctl(fd, FIONREAD, &used) == 0)
        return used < capacity ? (unsigned long)(capacity - used) : 0;
    socklen_t len = sizeof capacity;
    if (getsockopt(fd, SOL_SOCKET, SO_SNDBUF, &capacity, &len) == 0 &&
        ioctl(fd, TIOCOUTQ, &used) == 0)
        return used < capacity ? (unsigned long)(capacity - used) : 0;
    return 1;
}

static unsigned long vnode_data(struct dispatch_source *source) {
    unsigned long flags = 0;
    union {
        struct inotify_event alignment;
        char bytes[4096];
    } inotify;
    ssize_t n;
    do n = read(source->fd, inotify.bytes, sizeof inotify.bytes); while (n < 0 && errno == EINTR);
    for (size_t offset = 0; n > 0 && offset + sizeof(struct inotify_event) <= (size_t)n;) {
        struct inotify_event *event = (struct inotify_event *)(inotify.bytes + offset);
        if (event->mask & (IN_MODIFY | IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO))
            flags |= VNODE_WRITE;
        if (event->mask & IN_ATTRIB) flags |= VNODE_ATTRIB;
        if (event->mask & IN_MOVE_SELF) flags |= VNODE_RENAME;
        if (event->mask & IN_DELETE_SELF) flags |= VNODE_DELETE;
        if (event->mask & IN_UNMOUNT) flags |= VNODE_REVOKE;
        offset += sizeof *event + event->len;
    }
    struct stat st;
    if (fstat(source->vnode_fd, &st) == 0) {
        if (st.st_size > source->vnode_size) flags |= VNODE_EXTEND;
        if (st.st_nlink != source->vnode_links) flags |= VNODE_LINK;
        if (!st.st_nlink && source->vnode_links) flags |= VNODE_DELETE;
        source->vnode_size = st.st_size;
        source->vnode_links = st.st_nlink;
    }
    return flags & source->mask;
}

static void fd_ready(struct dispatch_source *source) {
    switch (source->kind) {
    case SRC_READ: {
        source->armed = false;
        int available = 0;
        if (ioctl(source->fd, FIONREAD, &available) < 0) {
            struct stat st;
            off_t pos = lseek(source->fd, 0, SEEK_CUR);
            if (pos >= 0 && fstat(source->fd, &st) == 0 && st.st_size > pos)
                return merge_data(source, (unsigned long)(st.st_size - pos));
        }
        merge_data(source, available > 0 ? (unsigned long)available : 0);
        break;
    }
    case SRC_WRITE:
        source->armed = false;
        merge_data(source, write_space(source->fd));
        break;
    case SRC_PROC:
        source->armed = false;
        source->exited = true;
        merge_data(source, PROC_EXIT);
        break;
    case SRC_TIMER:
        merge_data(source, read_counter(source->fd));
        break;
    case SRC_VNODE:
        merge_data(source, vnode_data(source));
        break;
    default:
        break;
    }
}

static void *manager_main(void *unused) {
    (void)unused;
    int timeout = -1;
    for (;;) {
        struct epoll_event events[32];
        int n = epoll_wait(manager_epoll, events, sizeof events / sizeof *events, timeout);
        if (n < 0) {
            if (errno == EINTR) continue;
            dx_fatal("dispatch: epoll_wait failed: %s", strerror(errno));
        }
        pthread_mutex_lock(&source_lock);
        for (int i = 0; i < n; ++i) {
            uint64_t token = events[i].data.u64;
            if (!token) {
                read_counter(manager_wake);
            } else if (token < NSIG) {
                struct signal_observer *observer = atomic_load_explicit(&signal_observers[token],
                                                                         memory_order_relaxed);
                uint64_t count = read_counter(observer->fd);
                reap_observers((int)token);
                if (count)
                    for (struct dispatch_source *s = active_sources; s; s = s->next)
                        if (s->host_signal == (int)token) merge_data(s, count);
            } else {
                for (struct dispatch_source *s = active_sources; s; s = s->next) {
                    if (s->token == token) {
                        fd_ready(s);
                        break;
                    }
                }
            }
        }

        timeout = -1;
        for (struct dispatch_source *s = active_sources; s; s = s->next) {
            if (!s->fallback || !s->armed) continue;
            struct pollfd p = { .fd = s->fd, .events = s->kind == SRC_READ ? POLLIN : POLLOUT };
            if (poll(&p, 1, 0) > 0) fd_ready(s);
            else timeout = 20;
        }
        pthread_mutex_unlock(&source_lock);
    }
}

static void start_manager(void) {
    if (manager_epoll >= 0) return;
    manager_epoll = epoll_create1(EPOLL_CLOEXEC);
    manager_wake = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    struct epoll_event wake = { .events = EPOLLIN, .data.u64 = 0 };
    if (manager_epoll < 0 || manager_wake < 0 ||
        epoll_ctl(manager_epoll, EPOLL_CTL_ADD, manager_wake, &wake) != 0)
        dx_fatal("dispatch: cannot initialize event manager: %s", strerror(errno));
    int error = dispatch_start_thread(manager_main, NULL);
    if (error) dx_fatal("dispatch: cannot start event manager (Darwin errno %d)", error);
}

static void source_deliver(void *arg) {
    struct dispatch_source *source = arg;
    struct source_handler handler = {0};
    struct source_event event = { .source = source, .previous = current_event };
    bool is_event = false;
    pthread_mutex_lock(&source_lock);
    if (!source->suspended) {
        if (source->canceled) {
            if (!source->cancel_delivered) {
                source->cancel_delivered = true;
                handler = source->cancel;
            }
        } else if (!source->registered && has_handler(source->registration)) {
            source->registered = true;
            handler = source->registration;
        } else if (source->pending_data && has_handler(source->event)) {
            source->event_running = is_event = true;
            source->pending_data = false;
            event.data = source->data;
            source->data = 0;
            handler = source->event;
        }
    }
    if (handler.block) handler.block = dispatch_copy_block(handler.block);
    pthread_mutex_unlock(&source_lock);

    if (is_event) current_event = &event;
    if (handler.block) {
        dispatch_invoke_block(handler.block);
        dx_block_release(handler.block);
    } else if (handler.fn) {
        handler.fn(atomic_load_explicit(&source->object.context, memory_order_relaxed));
    }
    if (is_event) current_event = event.previous;

    pthread_mutex_lock(&source_lock);
    source->submitted = source->event_running = false;
    arm_fd(source);
    source_try_submit(source);
    pthread_mutex_unlock(&source_lock);
    dispatch_object_release(source);
}

static void source_try_submit(struct dispatch_source *source) {
    if (!source->active || source->suspended || source->submitted) return;
    bool ready = source->canceled ? !source->cancel_delivered && has_handler(source->cancel)
        : (!source->registered && has_handler(source->registration)) ||
          (source->pending_data && has_handler(source->event));
    if (!ready) return;
    source->submitted = true;
    dispatch_object_retain(source);
    dispatch_submit_batch(source->object.finalizer_queue, source, source_deliver,
                          source->event_barrier, 1);
}

static void source_activate(struct dispatch_source *source) {
    if (source->active) return;
    source->active = true;
    if (!source->canceled) {
        if (source->host_signal || source->fd >= 0 || source->kind == SRC_TIMER) start_manager();
        source->next = active_sources;
        active_sources = source;
        if (source->host_signal && !add_signal_observer(source->host_signal)) {
            dx_log(1, "dispatch: cannot observe signal %d: %s", source->host_signal, strerror(errno));
            source->host_signal = 0;
        }
        arm_fd(source);
    }
}

static void source_cancel(struct dispatch_source *source) {
    if (source->canceled) return;
    source->canceled = true;
    source->pending_data = false;
    if (source->active) {
        struct dispatch_source **slot = &active_sources;
        while (*slot && *slot != source) slot = &(*slot)->next;
        if (*slot) *slot = source->next;
        if (source->host_signal) remove_signal_observer(source->host_signal);
    }
    detach_fd(source);
    if (source->fd >= 0) close(source->fd);
    if (source->vnode_fd >= 0) close(source->vnode_fd);
    source->fd = source->vnode_fd = -1;
}

static void source_dispose(struct dispatch_object *object) {
    struct dispatch_source *source = (struct dispatch_source *)object;
    dx_block_release(source->event.block);
    dx_block_release(source->registration.block);
    dx_block_release(source->cancel.block);
}

static int make_vnode_fd(struct dispatch_source *source) {
    char path[64];
    snprintf(path, sizeof path, "/proc/self/fd/%d", source->vnode_fd);
    int fd = inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
    if (fd >= 0 && inotify_add_watch(fd, path, IN_ATTRIB | IN_MODIFY | IN_DELETE_SELF | IN_MOVE_SELF |
                                            IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static struct dispatch_source *d_dispatch_source_create(const struct source_type *type,
        uintptr_t handle, unsigned long mask, struct dispatch_queue *queue) {
    if (!type) return NULL;
    struct dispatch_source *source = dispatch_alloc(sizeof *source);
    source->kind = type->kind;
    source->handle = handle;
    source->mask = mask;
    source->suspended = 1;
    source->fd = source->vnode_fd = -1;
    switch (source->kind) {
    case SRC_TIMER: case SRC_ADD: case SRC_OR:
        if (handle || (source->kind != SRC_TIMER && mask)) goto invalid;
        break;
    case SRC_READ: case SRC_WRITE:
        if (mask || handle > INT_MAX) goto invalid;
        source->fd = fcntl((int)handle, F_DUPFD_CLOEXEC, 0);
        if (source->fd < 0) goto invalid;
        break;
    case SRC_SIGNAL:
        if (handle > INT_MAX || mask) goto invalid;
        source->host_signal = dx_sig_to_host((int)handle);
        if (source->host_signal <= 0 || source->host_signal >= NSIG ||
            source->host_signal == SIGKILL || source->host_signal == SIGSTOP) goto invalid;
        break;
    case SRC_PROC:
        if (!(mask & PROC_EXIT) || handle > INT_MAX) goto invalid;
        source->fd = syscall(SYS_pidfd_open, (int)handle, 0);
        if (source->fd < 0) goto invalid;
        break;
    case SRC_VNODE: {
        if (handle > INT_MAX || !mask) goto invalid;
        source->vnode_fd = fcntl((int)handle, F_DUPFD_CLOEXEC, 0);
        struct stat st;
        if (source->vnode_fd < 0 || fstat(source->vnode_fd, &st) < 0) goto invalid;
        source->vnode_size = st.st_size;
        source->vnode_links = st.st_nlink;
        source->fd = make_vnode_fd(source);
        if (source->fd < 0) goto invalid;
        break;
    }
    default:
        goto invalid;
    }
    atomic_init(&source->public_refs, 1);
    dispatch_object_init(&source->object, DISPATCH_SOURCE, "OS_dispatch_source",
                         "OS_dispatch_object", source_dispose);
    source->object.finalizer_queue = queue ? queue : dispatch_default_queue();
    dispatch_object_retain(source->object.finalizer_queue);
    return source;

invalid:
    if (source->vnode_fd >= 0) close(source->vnode_fd);
    free(source);
    return NULL;
}
DX_FN(dispatch_source_create);

void dispatch_source_public_retain(struct dispatch_object *object) {
    struct dispatch_source *source = (struct dispatch_source *)object;
    atomic_fetch_add_explicit(&source->public_refs, 1, memory_order_relaxed);
}

void dispatch_source_public_release(struct dispatch_object *object) {
    struct dispatch_source *source = (struct dispatch_source *)object;
    if (atomic_fetch_sub_explicit(&source->public_refs, 1, memory_order_acq_rel) != 1) return;
    pthread_mutex_lock(&source_lock);
    source_cancel(source);
    source->suspended = 0;
    source_activate(source);
    source_try_submit(source);
    pthread_mutex_unlock(&source_lock);
}

void dispatch_source_control(struct dispatch_object *object, int change) {
    struct dispatch_source *source = (struct dispatch_source *)object;
    pthread_mutex_lock(&source_lock);
    if (change == DISPATCH_SUSPEND) {
        ++source->suspended;
    } else if (change == DISPATCH_ACTIVATE) {
        if (!source->active) {
            --source->suspended;
            source_activate(source);
        }
    } else if (source->suspended) {
        if (--source->suspended == 0) source_activate(source);
    } else {
        dx_fatal("dispatch: unbalanced source resume");
    }
    source_try_submit(source);
    pthread_mutex_unlock(&source_lock);
}

void dispatch_source_set_target(struct dispatch_object *object, struct dispatch_queue *queue) {
    if (!queue) queue = dispatch_default_queue();
    dispatch_object_retain(queue);
    pthread_mutex_lock(&source_lock);
    struct dispatch_queue *previous = object->finalizer_queue;
    object->finalizer_queue = queue;
    pthread_mutex_unlock(&source_lock);
    dispatch_object_release(previous);
}

static void set_handler(struct dispatch_source *source, struct source_handler *slot,
                        const void *block, dispatch_function fn) {
    struct source_handler replacement = { .block = dispatch_copy_block(block), .fn = fn };
    pthread_mutex_lock(&source_lock);
    struct source_handler previous = *slot;
    *slot = replacement;
    source_try_submit(source);
    pthread_mutex_unlock(&source_lock);
    dx_block_release(previous.block);
}

#define HANDLER_SETTERS(name) \
    static void d_dispatch_source_set_##name##_handler(struct dispatch_source *s, const void *b) { \
        set_handler(s, &s->name, b, NULL); \
    } \
    DX_FN(dispatch_source_set_##name##_handler); \
    static void d_dispatch_source_set_##name##_handler_f(struct dispatch_source *s, dispatch_function f) { \
        set_handler(s, &s->name, NULL, f); \
    } \
    DX_FN(dispatch_source_set_##name##_handler_f)

HANDLER_SETTERS(event);
HANDLER_SETTERS(cancel);
HANDLER_SETTERS(registration);

static void d_dispatch_source_set_timer(struct dispatch_source *source, uint64_t start,
                                        uint64_t interval, uint64_t leeway) {
    (void)leeway;
    if (source->kind != SRC_TIMER) dx_fatal("dispatch: expected a timer source");
    struct itimerspec setting = {0};
    clockid_t clock = dispatch_deadline(start, &setting.it_value);
    if (start == DISPATCH_FOREVER) setting.it_value = (struct timespec){0};
    else if (start == 0) setting.it_value.tv_nsec = 1;
    if (interval != DISPATCH_FOREVER) setting.it_interval = dispatch_timespec(interval);

    pthread_mutex_lock(&source_lock);
    if (!source->canceled) {
        if (source->fd >= 0 && source->timer_clock != clock) {
            detach_fd(source);
            close(source->fd);
            source->fd = -1;
        }
        if (source->fd < 0) {
            source->fd = timerfd_create(clock, TFD_CLOEXEC | TFD_NONBLOCK);
            if (source->fd < 0) dx_fatal("dispatch: cannot create a timer: %s", strerror(errno));
            source->timer_clock = clock;
        }
        source->pending_data = false;
        source->data = 0;
        if (timerfd_settime(source->fd, TFD_TIMER_ABSTIME, &setting, NULL) < 0)
            dx_fatal("dispatch: cannot set a timer: %s", strerror(errno));
        arm_fd(source);
    }
    pthread_mutex_unlock(&source_lock);
}
DX_FN(dispatch_source_set_timer);

static void d_dispatch_source_cancel(struct dispatch_source *source) {
    pthread_mutex_lock(&source_lock);
    source_cancel(source);
    source_try_submit(source);
    pthread_mutex_unlock(&source_lock);
}
DX_FN(dispatch_source_cancel);

static long d_dispatch_source_testcancel(struct dispatch_source *source) {
    pthread_mutex_lock(&source_lock);
    bool canceled = source->canceled;
    pthread_mutex_unlock(&source_lock);
    return canceled;
}
DX_FN(dispatch_source_testcancel);

static uintptr_t d_dispatch_source_get_handle(struct dispatch_source *source) { return source->handle; }
static unsigned long d_dispatch_source_get_mask(struct dispatch_source *source) { return source->mask; }
DX_FN(dispatch_source_get_handle);
DX_FN(dispatch_source_get_mask);

static unsigned long d_dispatch_source_get_data(struct dispatch_source *source) {
    for (struct source_event *e = current_event; e; e = e->previous)
        if (e->source == source) return e->data;
    return 0;
}
DX_FN(dispatch_source_get_data);

static void d_dispatch_source_merge_data(struct dispatch_source *source, unsigned long data) {
    if (source->kind != SRC_ADD && source->kind != SRC_OR)
        dx_fatal("dispatch: expected a user-data source");
    if (!data) return;
    pthread_mutex_lock(&source_lock);
    merge_data(source, data);
    pthread_mutex_unlock(&source_lock);
}
DX_FN(dispatch_source_merge_data);

struct after_job {
    struct dispatch_source *timer;
    dispatch_function fn;
    void *context;
};

static void after_fire(void *arg) {
    struct after_job *job = arg;
    job->fn(job->context);
    dispatch_source_public_release(&job->timer->object);
    dispatch_object_release(job->timer);
    free(job);
}

static void submit_after(uint64_t start, struct dispatch_queue *queue, void *context,
                         dispatch_function fn, bool barrier) {
    if (start == DISPATCH_FOREVER) return;
    struct after_job *job = dispatch_alloc(sizeof *job);
    struct dispatch_source *timer = d_dispatch_source_create(&timer_type, 0, 0, queue);
    timer->event_barrier = barrier;
    *job = (struct after_job){ .timer = timer, .fn = fn, .context = context };
    atomic_store_explicit(&timer->object.context, job, memory_order_relaxed);
    d_dispatch_source_set_event_handler_f(timer, after_fire);
    d_dispatch_source_set_timer(timer, start, DISPATCH_FOREVER, 0);
    dispatch_source_control(&timer->object, DISPATCH_ACTIVATE);
}

static void d_dispatch_after_f(uint64_t start, struct dispatch_queue *queue, void *context,
                               dispatch_function fn) {
    submit_after(start, queue, context, fn, false);
}
DX_FN(dispatch_after_f);

static void after_block(void *arg) {
    dispatch_invoke_block(arg);
    dx_block_release(arg);
}

static void d_dispatch_after(uint64_t start, struct dispatch_queue *queue, const void *block) {
    if (start != DISPATCH_FOREVER)
        submit_after(start, queue, dispatch_copy_block(block), after_block, dispatch_block_is_barrier(block));
}
DX_FN(dispatch_after);
