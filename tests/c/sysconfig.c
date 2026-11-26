/* SystemConfiguration: the machine's names and the console user. */
#include "darwin.h"

typedef const void *CFRef;
CFRef SCDynamicStoreCopyComputerName(CFRef store, unsigned int *encoding);
CFRef SCDynamicStoreCopyLocalHostName(CFRef store);
CFRef SCDynamicStoreCopyConsoleUser(CFRef store, unsigned int *uid, unsigned int *gid);
unsigned char CFStringGetCString(CFRef, char *, long, unsigned int);
long CFStringGetLength(CFRef);
void CFRelease(CFRef);
int gethostname(char *, unsigned long);
unsigned int getuid(void);

int main(void) {
    char host[256], got[256];
    unsigned int enc = 0, uid = 99, gid = 99;
    CHECK(gethostname(host, sizeof host) == 0);
    CFRef name = SCDynamicStoreCopyComputerName(NULL, &enc);
    CHECK(name && enc == 0x08000100 && CFStringGetCString(name, got, sizeof got, 0x08000100));
    CHECK(strcmp(got, host) == 0);
    CFRelease(name);
    CFRef local = SCDynamicStoreCopyLocalHostName(NULL);
    CHECK(local && CFStringGetLength(local) > 0);
    CFRelease(local);
    CFRef user = SCDynamicStoreCopyConsoleUser(NULL, &uid, &gid);
    CHECK(user && CFStringGetLength(user) > 0 && uid == getuid());
    CFRelease(user);
    puts("systemconfiguration ok");
    return 0;
}
