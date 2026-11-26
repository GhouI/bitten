/* `#available` checks see macOS 15.0.0 exactly: point releases and later
 * versions are not available (programs would call their weak imports of
 * newer API). */
#include "darwin.h"

int __isOSVersionAtLeast(int, int, int);
int __isPlatformVersionAtLeast(unsigned, unsigned, unsigned, unsigned);
int _availability_version_check(unsigned, void *);

int main(void) {
    CHECK(__isOSVersionAtLeast(14, 5, 0));
    CHECK(__isOSVersionAtLeast(15, 0, 0));
    CHECK(!__isOSVersionAtLeast(15, 4, 0));
    CHECK(!__isOSVersionAtLeast(15, 0, 1));
    CHECK(!__isOSVersionAtLeast(26, 0, 0));
    CHECK(__isPlatformVersionAtLeast(1, 15, 0, 0));
    CHECK(!__isPlatformVersionAtLeast(1, 15, 2, 0));
    unsigned ok[2] = {1, 15u << 16}, newer[2] = {1, 15u << 16 | 4 << 8};
    CHECK(_availability_version_check(1, ok));
    CHECK(!_availability_version_check(1, newer));
    puts("osversion ok");
    return 0;
}
