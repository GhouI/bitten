#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "internal.h"

enum destructor_kind { DATA_FREE, DATA_MUNMAP, DATA_BLOCK };

struct data_storage {
    atomic_size_t refs;
    const unsigned char *bytes;
    size_t size;
    struct dispatch_queue *queue;
    void *block;
    enum destructor_kind kind;
};

struct data_region {
    struct data_storage *storage;
    size_t offset, length;
};

struct dispatch_data {
    struct dispatch_object object;
    size_t size, count;
    struct data_region regions[];
};

static struct dispatch_data empty_data = { .object = DISPATCH_STATIC_OBJECT(DISPATCH_DATA) };

static void destructor_marker(void *block, ...) { (void)block; }

static const unsigned long destructor_descriptor[] = { 0, sizeof(struct dx_block) };
static struct dx_block free_block = {
    .flags = 1 << 28, .invoke = destructor_marker, .descriptor = (void *)destructor_descriptor,
};
static struct dx_block munmap_block = {
    .flags = 1 << 28, .invoke = destructor_marker, .descriptor = (void *)destructor_descriptor,
};
static struct dx_block *const destructor_free = &free_block;
static struct dx_block *const destructor_munmap = &munmap_block;

DX_EXPORT("__dispatch_data_destructor_free", &destructor_free);
DX_EXPORT("__dispatch_data_destructor_munmap", &destructor_munmap);
DX_EXPORT("__dispatch_data_empty", &empty_data);

__attribute__((constructor(103))) static void init_data_constants(void) {
    free_block.isa = munmap_block.isa = dx_registry_lookup("__NSConcreteGlobalBlock");
    empty_data.object.isa = dispatch_object_class("OS_dispatch_data", "OS_dispatch_object");
}

static void invoke_destructor(void *block) {
    dispatch_invoke_block(block);
    dx_block_release(block);
}

static void storage_release(struct data_storage *storage) {
    if (atomic_fetch_sub_explicit(&storage->refs, 1, memory_order_acq_rel) != 1) return;
    switch (storage->kind) {
    case DATA_FREE:
        free((void *)storage->bytes);
        break;
    case DATA_MUNMAP:
        if (storage->bytes && storage->size) munmap((void *)storage->bytes, storage->size);
        break;
    case DATA_BLOCK:
        dispatch_submit(storage->queue, storage->block, invoke_destructor);
        dispatch_object_release(storage->queue);
        break;
    }
    free(storage);
}

static void data_dispose(struct dispatch_object *object) {
    struct dispatch_data *data = (struct dispatch_data *)object;
    for (size_t i = 0; i < data->count; ++i) storage_release(data->regions[i].storage);
}

static struct dispatch_data *new_data(size_t count, size_t size) {
    if (count > (SIZE_MAX - sizeof(struct dispatch_data)) / sizeof(struct data_region))
        return NULL;
    struct dispatch_data *data = dispatch_alloc(sizeof *data + count * sizeof *data->regions);
    dispatch_object_init(&data->object, DISPATCH_DATA, "OS_dispatch_data", "OS_dispatch_object", data_dispose);
    data->count = count;
    data->size = size;
    return data;
}

static struct data_region make_region(const void *buffer, size_t size,
        struct dispatch_queue *queue, const void *destructor) {
    struct data_storage *storage = dispatch_alloc(sizeof *storage);
    atomic_init(&storage->refs, 1);
    storage->size = size;
    storage->bytes = buffer;
    if (destructor == destructor_munmap) {
        storage->kind = DATA_MUNMAP;
    } else if (destructor && destructor != destructor_free) {
        storage->kind = DATA_BLOCK;
        storage->queue = queue ? queue : dispatch_default_queue();
        storage->block = dispatch_copy_block(destructor);
        dispatch_object_retain(storage->queue);
    } else if (!destructor && buffer && size) {
        void *copy = dispatch_alloc(size);
        memcpy(copy, buffer, size);
        storage->bytes = copy;
    }
    return (struct data_region){ .storage = storage, .length = size };
}

static struct dispatch_data *d_dispatch_data_create(const void *buffer, size_t size,
        struct dispatch_queue *queue, const void *destructor) {
    if (!buffer || !size) {
        if (destructor) {
            struct data_region region = make_region(buffer, size, queue, destructor);
            storage_release(region.storage);
        }
        return &empty_data;
    }
    struct dispatch_data *data = new_data(1, size);
    data->regions[0] = make_region(buffer, size, queue, destructor);
    return data;
}
DX_FN(dispatch_data_create);

static size_t d_dispatch_data_get_size(struct dispatch_data *data) { return data->size; }
DX_FN(dispatch_data_get_size);

static const unsigned char *region_bytes(const struct data_region *region) {
    return region->storage->bytes + region->offset;
}

static struct dispatch_data *d_dispatch_data_create_map(struct dispatch_data *data,
                                                         const void **bytes, size_t *size) {
    if (data->count > 1) {
        unsigned char *buffer = dispatch_alloc(data->size);
        size_t pos = 0;
        for (size_t i = 0; i < data->count; ++i) {
            struct data_region *region = &data->regions[i];
            memcpy(buffer + pos, region_bytes(region), region->length);
            pos += region->length;
        }
        data = d_dispatch_data_create(buffer, pos, NULL, destructor_free);
    } else {
        dispatch_object_retain(data);
    }
    if (bytes) *bytes = data->count ? region_bytes(&data->regions[0]) : NULL;
    if (size) *size = data->size;
    return data;
}
DX_FN(dispatch_data_create_map);

static void set_region(struct data_region *dest, struct data_region value) {
    *dest = value;
    atomic_fetch_add_explicit(&value.storage->refs, 1, memory_order_relaxed);
}

static struct dispatch_data *d_dispatch_data_create_concat(struct dispatch_data *left,
                                                            struct dispatch_data *right) {
    if (!left->size || !right->size) {
        struct dispatch_data *data = left->size ? left : right;
        dispatch_object_retain(data);
        return data;
    }
    if (left->size > SIZE_MAX - right->size || left->count > SIZE_MAX - right->count) return NULL;
    struct dispatch_data *data = new_data(left->count + right->count, left->size + right->size);
    if (data) {
        for (size_t i = 0; i < left->count; ++i) set_region(&data->regions[i], left->regions[i]);
        for (size_t i = 0; i < right->count; ++i) set_region(&data->regions[left->count + i], right->regions[i]);
    }
    return data;
}
DX_FN(dispatch_data_create_concat);

static struct dispatch_data *d_dispatch_data_create_subrange(struct dispatch_data *data,
                                                               size_t offset, size_t length) {
    if (offset >= data->size || !length) return &empty_data;
    if (length > data->size - offset) length = data->size - offset;
    if (length == data->size) {
        dispatch_object_retain(data);
        return data;
    }

    size_t first = 0;
    while (offset >= data->regions[first].length) offset -= data->regions[first++].length;
    size_t last = first;
    size_t remaining = length;
    size_t piece = data->regions[first].length - offset;
    while (remaining > piece) {
        remaining -= piece;
        piece = data->regions[++last].length;
    }
    struct dispatch_data *slice = new_data(last - first + 1, length);
    for (size_t i = first; i <= last; ++i) set_region(&slice->regions[i - first], data->regions[i]);
    slice->regions[0].offset += offset;
    slice->regions[0].length -= offset;
    slice->regions[last - first].length = remaining;
    return slice;
}
DX_FN(dispatch_data_create_subrange);

static bool d_dispatch_data_apply(struct dispatch_data *data, void *arg) {
    struct dx_block *block = arg;
    bool (*invoke)(void *, struct dispatch_data *, size_t, const void *, size_t) = (void *)block->invoke;
    size_t offset = 0;
    for (size_t i = 0; i < data->count; ++i) {
        struct data_region *piece = &data->regions[i];
        struct dispatch_data *region = new_data(1, piece->length);
        set_region(&region->regions[0], *piece);
        bool more = invoke(block, region, offset, region_bytes(piece), piece->length);
        dispatch_object_release(region);
        if (!more) return false;
        offset += piece->length;
    }
    return true;
}
DX_FN(dispatch_data_apply);

static pthread_once_t io_once = PTHREAD_ONCE_INIT;
static struct dispatch_queue *io_queue;

struct io_job {
    int fd, error;
    size_t length;
    struct dispatch_data *data;
    struct dispatch_queue *queue;
    struct dx_block *handler;
    bool writing;
};

static void init_io_queue(void) {
    io_queue = dispatch_private_queue("com.apple.libdispatch.io");
}

static bool poll_io(int fd, short events, int time) {
    struct pollfd pfd = { .fd = fd, .events = events };
    int n;
    do n = poll(&pfd, 1, time); while (n < 0 && errno == EINTR);
    return n > 0;
}

static void read_data(struct io_job *job) {
    enum { IO_CHUNK = 65536 };
    struct data_region *regions = NULL;
    size_t count = 0, capacity = 0, total = 0;
    while (total < job->length && (!total || poll_io(job->fd, POLLIN, 0))) {
        size_t length = job->length - total;
        if (length > IO_CHUNK) length = IO_CHUNK;
        void *buffer = dispatch_alloc(length);
        ssize_t result;
        do {
            result = read(job->fd, buffer, length);
        } while (result < 0 && (errno == EINTR ||
                  (!total && (errno == EAGAIN || errno == EWOULDBLOCK) && poll_io(job->fd, POLLIN, -1))));
        if (result <= 0) {
            if (result < 0 && (errno != EAGAIN || !total)) job->error = dx_errno_to_darwin(errno);
            free(buffer);
            break;
        }
        if (count == capacity) {
            capacity = capacity ? capacity * 2 : 4;
            struct data_region *grown = reallocarray(regions, capacity, sizeof *regions);
            if (!grown) dx_fatal("dispatch: read buffer allocation failed");
            regions = grown;
        }
        regions[count++] = make_region(buffer, (size_t)result, NULL, destructor_free);
        total += (size_t)result;
    }
    job->data = count ? new_data(count, total) : &empty_data;
    if (count) memcpy(job->data->regions, regions, count * sizeof *regions);
    free(regions);
}

static void write_data(struct io_job *job) {
    struct dispatch_data *input = job->data;
    size_t written = 0;
    sigset_t sigpipe, old, pending;
    sigemptyset(&sigpipe);
    sigaddset(&sigpipe, SIGPIPE);
    pthread_sigmask(SIG_BLOCK, &sigpipe, &old);
    sigpending(&pending);
    for (size_t i = 0; !job->error && i < input->count; ++i) {
        struct data_region *region = &input->regions[i];
        size_t offset = 0;
        while (offset < region->length) {
            size_t length = region->length - offset;
            if (length > SSIZE_MAX) length = SSIZE_MAX;
            ssize_t result = write(job->fd, region_bytes(region) + offset, length);
            if (result < 0 && (errno == EINTR ||
                ((errno == EAGAIN || errno == EWOULDBLOCK) && poll_io(job->fd, POLLOUT, -1)))) continue;
            if (result <= 0) {
                if (result < 0 && errno == EPIPE && !sigismember(&pending, SIGPIPE)) {
                    struct timespec zero = {0};
                    while (sigtimedwait(&sigpipe, NULL, &zero) < 0 && errno == EINTR) {}
                    errno = EPIPE;
                }
                job->error = dx_errno_to_darwin(result ? errno : EIO);
                break;
            }
            offset += (size_t)result;
            written += (size_t)result;
        }
    }
    pthread_sigmask(SIG_SETMASK, &old, NULL);
    job->data = job->error ? d_dispatch_data_create_subrange(input, written, input->size - written) : NULL;
    dispatch_object_release(input);
}

static void io_complete(void *arg) {
    struct io_job *job = arg;
    struct dx_block *handler = job->handler;
    handler->invoke(handler, job->data, job->error);
    dx_block_release(handler);
    dispatch_object_release(job->data);
    free(job);
}

static void io_work(void *arg) {
    struct io_job *job = arg;
    if (!job->error) {
        if (job->writing) write_data(job);
        else read_data(job);
        close(job->fd);
    } else if (!job->writing) {
        job->data = &empty_data;
    }
    struct dispatch_queue *queue = job->queue;
    dispatch_submit(queue, job, io_complete);
    dispatch_object_release(queue);
}

static void submit_io(int fd, size_t length, struct dispatch_data *data, struct dispatch_queue *queue,
                       const void *handler, bool writing) {
    pthread_once(&io_once, init_io_queue);
    struct io_job *job = dispatch_alloc(sizeof *job);
    job->fd = fcntl(fd, F_DUPFD_CLOEXEC, 0);
    if (job->fd < 0) job->error = dx_errno_to_darwin(errno);
    job->data = data;
    job->length = length;
    job->queue = queue;
    job->writing = writing;
    job->handler = dispatch_copy_block(handler);
    dispatch_object_retain(queue);
    dispatch_object_retain(data);
    dispatch_submit(io_queue, job, io_work);
}

static void d_dispatch_read(int fd, size_t length, struct dispatch_queue *queue, const void *handler) {
    submit_io(fd, length, NULL, queue, handler, false);
}
DX_FN(dispatch_read);

static void d_dispatch_write(int fd, struct dispatch_data *data, struct dispatch_queue *queue, const void *handler) {
    submit_io(fd, 0, data, queue, handler, true);
}
DX_FN(dispatch_write);
