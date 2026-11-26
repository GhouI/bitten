// Driver for foundation.swift.
#include "darwin.h"

long swl_foundation_uuid(void);
long swl_foundation_charset(void);
long swl_foundation_strings(void);
long swl_foundation_format(void);
long swl_foundation_misc(void);
long swl_foundation_data(void);
long swl_foundation_json(void);
long swl_foundation_decimal(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("uuid", swl_foundation_uuid());
    ok &= check("charset", swl_foundation_charset());
    ok &= check("strings", swl_foundation_strings());
    ok &= check("format", swl_foundation_format());
    ok &= check("misc", swl_foundation_misc());
    ok &= check("data", swl_foundation_data());
    ok &= check("json", swl_foundation_json());
    ok &= check("decimal", swl_foundation_decimal());
    CHECK(ok);
    puts("swift foundation ok");
    return 0;
}
