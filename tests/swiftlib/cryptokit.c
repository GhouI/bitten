// Driver for cryptokit.swift.
#include "darwin.h"

long swl_ck_hashes(void);
long swl_ck_aes(void);
long swl_ck_curve25519(void);
long swl_ck_nist(void);

static int check(const char *what, long bad) {
    if (bad) printf("%s: failed checks %#lx\n", what, bad);
    return bad == 0;
}

int main(void) {
    int ok = check("hashes", swl_ck_hashes());
    ok &= check("aes-gcm", swl_ck_aes());
    ok &= check("curve25519", swl_ck_curve25519());
    ok &= check("nist curves", swl_ck_nist());
    CHECK(ok);
    puts("cryptokit ok");
    return 0;
}
