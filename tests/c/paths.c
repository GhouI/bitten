/* Paths outside bitten's framework root are never redirected: creating a
 * file under a directory that mirrors a macOS location must create it
 * exactly there. Regression test for a redirect that sent not-yet-existing
 * paths under /Users, /Library and /private into the framework root. */
#include "darwin.h"

int open(const char *, int, ...);
int close(int);
int access(const char *, int);
int unlink(const char *);
int mkdir(const char *, int);
int rmdir(const char *);
int getpid(void);
struct sockaddr_un { unsigned char sun_len, sun_family; char sun_path[104]; };
int socket(int, int, int);
int bind(int, const void *, uint32_t);

#define O_RDWR 2
#define O_CREAT 0x200

int main(void) {
    /* a system framework path that exists only in the framework root resolves */
    CHECK(access("/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation", 4) == 0);
    /* one that exists nowhere does not */
    CHECK(access("/System/Library/Frameworks/NoSuch.framework/NoSuch", 0) == -1 && errno == 2);

    /* creating new files and sockets is never redirected */
    char dir[128], file[192];
    snprintf(dir, sizeof dir, "/tmp/bitten-paths-%d", getpid());
    CHECK(mkdir(dir, 0755) == 0);
    snprintf(file, sizeof file, "%s/new.txt", dir);
    int fd = open(file, O_RDWR | O_CREAT, 0600);
    CHECK(fd >= 0);
    close(fd);
    CHECK(access(file, 0) == 0);
    CHECK(unlink(file) == 0);

    struct sockaddr_un sa;
    memset(&sa, 0, sizeof sa);
    sa.sun_family = 1;
    snprintf(sa.sun_path, sizeof sa.sun_path, "%s/s.sock", dir);
    sa.sun_len = (unsigned char)(2 + strlen(sa.sun_path) + 1);
    int s = socket(1, 1, 0);
    CHECK(s >= 0 && bind(s, &sa, sa.sun_len) == 0);
    CHECK(access(sa.sun_path, 0) == 0);
    close(s);
    CHECK(unlink(sa.sun_path) == 0 && rmdir(dir) == 0);
    puts("paths ok");
    return 0;
}
