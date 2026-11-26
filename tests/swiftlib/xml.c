// Driver for xml.swift.
#include "darwin.h"

long swl_xml_parser(void);
long swl_xml_document(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("parser", swl_xml_parser());
    ok &= check("document", swl_xml_document());
    CHECK(ok);
    puts("xml ok");
    return 0;
}
