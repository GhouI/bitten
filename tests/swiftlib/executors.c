// Driver for executors.swift: start the test's task, then run the main queue.
#include "darwin.h"

void swl_executors_start(void);
void dispatch_main(void) __attribute__((noreturn));

void swl_check(int ok, long line) {
    if (!ok) {
        printf("check failed: executors.swift:%ld\n", line);
        exit(1);
    }
}

void swl_done(void) {
    puts("swift concurrency: executors ok");
    exit(0);
}

int main(void) {
    swl_executors_start();
    dispatch_main();
}
