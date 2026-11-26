// Driver for async.swift: start the tests' task, then run the main queue.
#include "darwin.h"

void swl_handoff_start(void);
void dispatch_main(void) __attribute__((noreturn));
void *dispatch_get_global_queue(long, unsigned long);
void dispatch_async_f(void *, void *, void (*)(void *));
int pthread_main_np(void);

void swl_check(int ok, long line) {
    if (!ok) {
        printf("check failed: async.swift:%ld\n", line);
        exit(1);
    }
}

int swl_on_main_thread(void) { return pthread_main_np(); }

void swl_call_later(void *ctx, void (*fn)(void *)) {
    dispatch_async_f(dispatch_get_global_queue(0, 0), ctx, fn);
}

void swl_done(void) {
    puts("swift concurrency: handoff ok");
    exit(0);
}

int main(void) {
    swl_handoff_start();
    dispatch_main();
}
