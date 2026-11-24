#define _GNU_SOURCE
#include <errno.h>
#include <netdb.h>
#include <pthread.h>
#include <resolv.h>
#include <stdlib.h>
#include <string.h>

#include "dx.h"

struct resolver_cookie {
    res_state host;
    uintptr_t magic;
};
_Static_assert(sizeof(struct resolver_cookie) == 16, "Darwin resolver cookie");

struct resolver {
    struct __res_state host;
    const void *owner;
    struct resolver *next;
};

enum { RESOLVER_BUCKETS = 16 };
static struct resolver *resolvers[RESOLVER_BUCKETS];
static pthread_mutex_t resolver_locks[RESOLVER_BUCKETS] = {
    [0 ... RESOLVER_BUCKETS - 1] = PTHREAD_MUTEX_INITIALIZER,
};
static int d_h_errno;
DX_EXPORT("_h_errno", &d_h_errno);

static int resolver_result(int result, int error, int dns_error) {
    __atomic_store_n(&d_h_errno, result < 0 ? dns_error : 0, __ATOMIC_RELAXED);
    if (result < 0) {
        if (!error) {
            switch (dns_error) {
            case HOST_NOT_FOUND: case NO_DATA: error = ENOENT; break;
            case TRY_AGAIN: error = EAGAIN; break;
            default: error = EIO; break;
            }
        }
        dx_set_errno(dx_errno_to_darwin(error));
    }
    return result;
}

static size_t resolver_bucket(const void *state) {
    uintptr_t address = (uintptr_t)state;
    return ((address >> 4) ^ (address >> 12)) % RESOLVER_BUCKETS;
}

static uintptr_t resolver_magic(const void *state) {
    return UINT64_C(0x5245533942495454) ^ (uintptr_t)state;
}

static struct resolver **resolver_find(size_t bucket, const void *state) {
    struct resolver **entry = &resolvers[bucket];
    while (*entry && (*entry)->owner != state) entry = &(*entry)->next;
    return entry;
}

static int resolver_valid(const struct resolver *entry, const void *state) {
    if (!entry) return 0;
    struct resolver_cookie cookie;
    memcpy(&cookie, state, sizeof cookie);
    return cookie.magic == resolver_magic(state) && cookie.host == &entry->host;
}

static void resolver_free(struct resolver **entry) {
    struct resolver *old = *entry;
    *entry = old->next;
    res_nclose(&old->host);
    free(old);
}

static int d_res_9_ninit(void *state) {
    if (!state) return resolver_result(-1, EINVAL, NETDB_INTERNAL);
    size_t bucket = resolver_bucket(state);
    pthread_mutex_lock(&resolver_locks[bucket]);
    struct resolver **old = resolver_find(bucket, state);
    if (*old) resolver_free(old);

    struct resolver_cookie cookie = {0};
    struct resolver *entry = calloc(1, sizeof *entry);
    int result = -1, error = ENOMEM, dns_error = NETDB_INTERNAL;
    if (entry) {
        errno = 0;
        result = res_ninit(&entry->host);
        error = errno;
        if (entry->host.res_h_errno) dns_error = entry->host.res_h_errno;
        if (result < 0) {
            res_nclose(&entry->host);
            free(entry);
        } else {
            entry->owner = state;
            entry->next = resolvers[bucket];
            resolvers[bucket] = entry;
            cookie = (struct resolver_cookie){&entry->host, resolver_magic(state)};
        }
    }
    memcpy(state, &cookie, sizeof cookie);
    pthread_mutex_unlock(&resolver_locks[bucket]);
    return resolver_result(result, error, dns_error);
}
DX_FN(res_9_ninit);

static void d_res_9_nclose(void *state) {
    if (!state) return;
    size_t bucket = resolver_bucket(state);
    pthread_mutex_lock(&resolver_locks[bucket]);
    struct resolver **entry = resolver_find(bucket, state);
    if (resolver_valid(*entry, state)) {
        resolver_free(entry);
        memset(state, 0, sizeof(struct resolver_cookie));
    }
    pthread_mutex_unlock(&resolver_locks[bucket]);
}
DX_FN(res_9_nclose);

static int resolver_query(void *state, const char *name, int cls, int type,
                          unsigned char *answer, int length, int search) {
    if (!state || !name || !answer || length < NS_HFIXEDSZ)
        return resolver_result(-1, EINVAL, NETDB_INTERNAL);
    size_t bucket = resolver_bucket(state);
    pthread_mutex_lock(&resolver_locks[bucket]);
    struct resolver *entry = *resolver_find(bucket, state);
    if (!resolver_valid(entry, state)) {
        pthread_mutex_unlock(&resolver_locks[bucket]);
        return resolver_result(-1, EINVAL, NETDB_INTERNAL);
    }
    res_state host = &entry->host;
    errno = 0;
    int result = search ? res_nsearch(host, name, cls, type, answer, length)
                        : res_nquery(host, name, cls, type, answer, length);
    int error = errno, dns_error = host->res_h_errno;
    pthread_mutex_unlock(&resolver_locks[bucket]);
    return resolver_result(result, error, dns_error);
}

static int d_res_9_nsearch(void *state, const char *name, int cls, int type,
                           unsigned char *answer, int length) {
    return resolver_query(state, name, cls, type, answer, length, 1);
}
DX_FN(res_9_nsearch);

static int d_res_9_nquery(void *state, const char *name, int cls, int type,
                          unsigned char *answer, int length) {
    return resolver_query(state, name, cls, type, answer, length, 0);
}
DX_FN(res_9_nquery);

static int d_res_9_init(void) {
    errno = 0;
    int result = res_init();
    return resolver_result(result, errno, h_errno);
}
DX_FN(res_9_init);

static int d_res_9_search(const char *name, int cls, int type, unsigned char *answer, int length) {
    if (!name || !answer || length < NS_HFIXEDSZ) return resolver_result(-1, EINVAL, NETDB_INTERNAL);
    errno = 0;
    int result = res_search(name, cls, type, answer, length);
    return resolver_result(result, errno, h_errno);
}
DX_FN(res_9_search);

static int d_res_9_query(const char *name, int cls, int type, unsigned char *answer, int length) {
    if (!name || !answer || length < NS_HFIXEDSZ) return resolver_result(-1, EINVAL, NETDB_INTERNAL);
    errno = 0;
    int result = res_query(name, cls, type, answer, length);
    return resolver_result(result, errno, h_errno);
}
DX_FN(res_9_query);

static int d_dn_expand(const unsigned char *start, const unsigned char *end,
                       const unsigned char *src, char *dst, int length) {
    if (!start || !end || !src || !dst || length <= 0 ||
        (uintptr_t)src < (uintptr_t)start || (uintptr_t)src >= (uintptr_t)end)
        return resolver_result(-1, EINVAL, NO_RECOVERY);
    errno = 0;
    int result = dn_expand(start, end, src, dst, length);
    return resolver_result(result, errno, NO_RECOVERY);
}
DX_FN(dn_expand);
DX_EXPORT("_res_9_dn_expand", d_dn_expand);
