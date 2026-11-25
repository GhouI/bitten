/* os_unfair_lock: a 32-bit lock word, zero when unlocked. */
#ifndef _OS_LOCK_H
#define _OS_LOCK_H
#include <stdbool.h>
#include <stdint.h>

typedef struct os_unfair_lock_s {
    uint32_t _os_unfair_lock_opaque;
} os_unfair_lock, *os_unfair_lock_t;
#define OS_UNFAIR_LOCK_INIT ((os_unfair_lock){0})

void os_unfair_lock_lock(os_unfair_lock_t lock);
bool os_unfair_lock_trylock(os_unfair_lock_t lock);
void os_unfair_lock_unlock(os_unfair_lock_t lock);
void os_unfair_lock_assert_owner(const os_unfair_lock *lock);
void os_unfair_lock_assert_not_owner(const os_unfair_lock *lock);
#endif
