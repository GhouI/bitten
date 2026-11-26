/* SystemConfiguration: the dynamic-store queries programs make for the
 * machine's names and the console user. The computer name is the host's
 * name (a container's hostname), the local host name the same up to the
 * first dot, and the console user the user the program runs as. Written
 * from Apple's public documentation. */
#include <pwd.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

#include "../corefoundation/cf.h"

enum { UTF8 = 0x08000100 };

static struct cf_string *hostname_string(bool local) {
    char name[256] = "localhost";
    if (gethostname(name, sizeof name - 1) != 0) strcpy(name, "localhost");
    name[sizeof name - 1] = 0;
    if (local) {
        char *dot = strchr(name, '.');
        if (dot) *dot = 0;
    }
    return d_CFStringCreateWithCString(NULL, name, UTF8);
}

static struct cf_string *d_SCDynamicStoreCopyComputerName(const void *store, uint32_t *encoding) {
    if (encoding) *encoding = UTF8;
    return hostname_string(false);
}
DX_FN(SCDynamicStoreCopyComputerName);

static struct cf_string *d_SCDynamicStoreCopyLocalHostName(const void *store) { return hostname_string(true); }
DX_FN(SCDynamicStoreCopyLocalHostName);

static struct cf_string *d_SCDynamicStoreCopyConsoleUser(const void *store, uint32_t *uid, uint32_t *gid) {
    uid_t u = getuid();
    struct passwd *pw = getpwuid(u);
    if (uid) *uid = u;
    if (gid) *gid = pw ? pw->pw_gid : getgid();
    return d_CFStringCreateWithCString(NULL, pw ? pw->pw_name : "mac", UTF8);
}
DX_FN(SCDynamicStoreCopyConsoleUser);
