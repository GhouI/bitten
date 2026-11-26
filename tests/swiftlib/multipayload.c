#include "darwin.h"
long swl_multipayload(void);
int main(void) {
    long b = swl_multipayload();
    if (b) printf("multipayload: failed checks %#lx\n", b);
    else puts("swift multipayload enums ok");
    return b != 0;
}
