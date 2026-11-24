#include "darwin.h"

static int counter = 40;
static int *counter_ptr = &counter; /* needs a rebase fixup */
__thread int tls_value = 7;         /* needs a TLV descriptor */

__attribute__((constructor)) static void ctor(void) { counter += 1; }

int main(int argc, char **argv) {
    *counter_ptr += 1;
    CHECK(counter == 42);
    CHECK(tls_value == 7);
    tls_value += argc;
    CHECK(tls_value == 7 + argc);
    char *p = malloc(32);
    snprintf(p, 32, "%s-%d", "hello", counter);
    CHECK(strcmp(p, "hello-42") == 0);
    free(p);
    printf("hello from Mach-O: argc=%d argv0=%s\n", argc, argv[0]);
    return 0;
}
