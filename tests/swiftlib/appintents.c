// Driver for appintents.swift.
#include "darwin.h"

long swl_ai_entities(void);
long swl_ai_intents(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("entities", swl_ai_entities());
    ok &= check("intents", swl_ai_intents());
    CHECK(ok);
    puts("appintents ok");
    return 0;
}
