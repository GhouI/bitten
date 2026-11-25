// Driver for strings.swift.
#include "darwin.h"

long swl_strings_layout(unsigned long *literal_address);
long swl_strings_basics(void);
long swl_strings_cstrings(const char *s, const unsigned char *bad);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    unsigned long lit = 0;
    int ok = check("layout", swl_strings_layout(&lit));
    // The immortal literal's address (+32) is its constant UTF-8 bytes.
    ok &= check("literal bytes", lit == 0 || memcmp((const char *)lit, "this literal is longer", 22) != 0);
    ok &= check("basics", swl_strings_basics());
    static const unsigned char bad8[] = { 'a', 0xC3, 'b', 0xE2, 0x82, 0 };
    ok &= check("cstrings", swl_strings_cstrings("from C, a long enough string", bad8));
    CHECK(ok);
    puts("swift stdlib strings ok");
    return 0;
}
