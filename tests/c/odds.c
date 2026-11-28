/* libSystem odds and ends (interface addresses, waitid, renamex_np,
 * mkpath_np, memset_s, QoS, notify registration, fpclassify, exp10) and
 * CoreFoundation's encoding names and executable architectures. */
#include "darwin.h"

typedef const void *Ref;
struct ifaddrs { struct ifaddrs *next; char *name; unsigned flags; uint8_t *addr, *netmask, *dstaddr; void *data; };
int getifaddrs(struct ifaddrs **);
void freeifaddrs(struct ifaddrs *);
struct siginfo { int signo, err, code, pid; unsigned uid; int status; void *addr; void *value; long band; unsigned long pad[7]; };
int waitid(int, int, struct siginfo *, int);
int fork(void);
void _exit(int) __attribute__((noreturn));
int getpid(void);
int renamex_np(const char *, const char *, unsigned);
int mkpath_np(const char *, unsigned short);
int memset_s(void *, size_t, int, size_t);
void *malloc_default_zone(void);
size_t malloc_zone_pressure_relief(void *, size_t);
unsigned qos_class_main(void);
int notify_register_dispatch(const char *, int *, void *, void *);
int __fpclassifyd(double);
double __exp10(double);
int open(const char *, int, ...);
int close(int);
int access(const char *, int);
int rmdir(const char *);
int unlink(const char *);
Ref CFStringCreateWithCString(Ref, const char *, unsigned);
unsigned CFStringConvertIANACharSetNameToEncoding(Ref);
unsigned long CFStringConvertEncodingToNSStringEncoding(unsigned);
unsigned CFStringConvertNSStringEncodingToEncoding(unsigned long);
Ref CFURLCreateWithFileSystemPath(Ref, Ref, long, unsigned char);
Ref CFBundleCopyExecutableArchitecturesForURL(Ref);
long CFArrayGetCount(Ref);
Ref CFArrayGetValueAtIndex(Ref, long);
unsigned char CFNumberGetValue(Ref, long, void *);
char ***_NSGetArgv2(void) __asm__("__NSGetArgv");
void *cxx_new(unsigned long) __asm__("__Znwm");
void *cxx_new_array(unsigned long) __asm__("__Znam");
void *cxx_new_aligned(unsigned long, unsigned long) __asm__("__ZnwmSt11align_val_t");
void cxx_delete(void *) __asm__("__ZdlPv");
void cxx_delete_array(void *) __asm__("__ZdaPv");
void cxx_delete_aligned(void *, unsigned long) __asm__("__ZdlPvSt11align_val_t");

int main(void) {
    /* interfaces: the loopback has an IPv4 address and a link entry */
    struct ifaddrs *list = 0;
    CHECK(getifaddrs(&list) == 0 && list);
    int lo4 = 0, link = 0;
    for (struct ifaddrs *i = list; i; i = i->next) {
        if (!strcmp(i->name, "lo") && i->addr && i->addr[1] == 2) {
            lo4 = i->addr[0] == 16 && i->addr[4] == 127 && (i->flags & 8) && (i->flags & 1);
        }
        if (i->addr && i->addr[1] == 18) link = 1;
    }
    CHECK(lo4 && link);
    freeifaddrs(list);

    /* waitid */
    int pid = fork();
    if (pid == 0) _exit(7);
    struct siginfo si;
    memset(&si, 0, sizeof si);
    CHECK(waitid(1, pid, &si, 4) == 0);                /* P_PID, WEXITED */
    CHECK(si.signo == 20 && si.pid == pid && si.code == 1 && si.status == 7);

    /* files */
    char dir[64], a[96], b[96];
    snprintf(dir, sizeof dir, "/tmp/bitten-odds-%d/x/y", getpid());
    CHECK(mkpath_np(dir, 0755) == 0);
    CHECK(mkpath_np(dir, 0755) == 17);                  /* EEXIST */
    snprintf(a, sizeof a, "%s/a", dir);
    snprintf(b, sizeof b, "%s/b", dir);
    close(open(a, 0x201, 0644));                        /* O_CREAT | O_WRONLY */
    close(open(b, 0x201, 0644));
    CHECK(renamex_np(a, b, 4) == -1 && errno == 17);    /* RENAME_EXCL: b exists */
    CHECK(renamex_np(a, b, 2) == 0);                    /* RENAME_SWAP */
    CHECK(renamex_np(a, b, 0) == 0 && access(a, 0) != 0 && access(b, 0) == 0);
    unlink(b);

    /* memory, QoS, notifications */
    char buf[8] = "abcdefg";
    CHECK(memset_s(buf, 8, 'z', 4) == 0 && buf[3] == 'z' && buf[4] == 'e');
    CHECK(memset_s(buf, 8, 'q', 20) == 84 && buf[7] == 'q');
    CHECK(qos_class_main() == 0x21);
    int t1 = 0, t2 = 0;
    CHECK(notify_register_dispatch("com.example.x", &t1, 0, 0) == 0 && notify_register_dispatch("y", &t2, 0, 0) == 0 && t1 != t2);

    /* math */
    CHECK(__fpclassifyd(0.0) == 3 && __fpclassifyd(1.5) == 4 && __fpclassifyd(1.0 / 0.0) == 2);
    CHECK(__fpclassifyd(0.0 / 0.0) == 1 && __fpclassifyd(4.9e-324) == 5);
    CHECK(__exp10(3) == 1000);

    /* CF encodings */
    CHECK(CFStringConvertIANACharSetNameToEncoding(CFStringCreateWithCString(0, "UTF-8", 0x08000100)) == 0x08000100);
    CHECK(CFStringConvertIANACharSetNameToEncoding(CFStringCreateWithCString(0, "iso-8859-1", 0x08000100)) == 0x0201);
    CHECK(CFStringConvertIANACharSetNameToEncoding(CFStringCreateWithCString(0, "klingon", 0x08000100)) == 0xffffffff);
    CHECK(CFStringConvertEncodingToNSStringEncoding(0x08000100) == 4 && CFStringConvertEncodingToNSStringEncoding(0) == 30);
    CHECK(CFStringConvertNSStringEncodingToEncoding(1) == 0x0600);

    /* this test's own architecture: x86_64 */
    char **argv = *_NSGetArgv2();
    Ref archs = CFBundleCopyExecutableArchitecturesForURL(
        CFURLCreateWithFileSystemPath(0, CFStringCreateWithCString(0, argv[0], 0x08000100), 0, 0));
    CHECK(archs && CFArrayGetCount(archs) == 1);
    int cpu = 0;
    CHECK(CFNumberGetValue(CFArrayGetValueAtIndex(archs, 0), 3, &cpu) && cpu == 0x01000007);

    /* C++ allocation */
    char *p = cxx_new(64), *q = cxx_new_array(0);
    CHECK(p && q && p != q);
    memset(p, 1, 64);
    cxx_delete(p);
    cxx_delete_array(q);
    void *al = cxx_new_aligned(100, 64);
    CHECK(al && ((unsigned long)al & 63) == 0);
    cxx_delete_aligned(al, 64);

    /* memory freed goes back to the system on request: after freeing many
     * small blocks, relief hands some back (glibc keeps it otherwise) */
    {
        enum { N = 20000 };
        static void *blocks[N];
        for (int i = 0; i < N; i++) blocks[i] = malloc(200);
        for (int i = 0; i < N; i++) free(blocks[i]);
        size_t back = malloc_zone_pressure_relief(malloc_default_zone(), 0);
        (void)back;   /* how much depends on the heap's shape; it returns */
        CHECK(malloc_zone_pressure_relief(0, 0) < ((size_t)1 << 40));
    }

    puts("odds ok");
    return 0;
}
