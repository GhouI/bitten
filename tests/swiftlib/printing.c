// Driver for printing.swift.
#include "darwin.h"

long swl_printing_integers(void);
long swl_printing_floats(void);
long swl_printing_values(void);
long swl_printing_interpolation(void);
long swl_printing_print(void);
long swl_printing_enums(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("integers", swl_printing_integers());
    ok &= check("floats", swl_printing_floats());
    ok &= check("values", swl_printing_values());
    ok &= check("interpolation", swl_printing_interpolation());
    ok &= check("print", swl_printing_print());
    ok &= check("enums", swl_printing_enums());
    CHECK(ok);
    puts("swift stdlib printing ok");
    return 0;
}
