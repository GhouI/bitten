/* Virtual memory, time, Mach basics, sysctl, sysconf. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

#include "darwin_abi.h"
#include "dx.h"

/* ---- mmap ---------------------------------------------------------------- */

#define D_MAP_SHARED 0x0001
#define D_MAP_PRIVATE 0x0002
#define D_MAP_FIXED 0x0010
#define D_MAP_NORESERVE 0x0040
#define D_MAP_JIT 0x0800
#define D_MAP_ANON 0x1000

static void *d_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off) {
    int hf = 0;
    if (flags & D_MAP_SHARED) hf |= MAP_SHARED;
    if (flags & D_MAP_PRIVATE) hf |= MAP_PRIVATE;
    if (flags & D_MAP_FIXED) hf |= MAP_FIXED;
    if (flags & D_MAP_NORESERVE) hf |= MAP_NORESERVE;
    if (flags & D_MAP_ANON) {
        hf |= MAP_ANONYMOUS;
        fd = -1; /* Darwin passes a VM tag here */
        off = 0;
    }
    if (!(hf & (MAP_SHARED | MAP_PRIVATE))) hf |= MAP_PRIVATE;
    void *r = mmap(addr, len, prot & 7, hf, fd, off);
    if (r == MAP_FAILED) dx_set_errno(dx_errno_to_darwin(errno));
    return r;
}
DX_FN(mmap);
static int d_munmap(void *addr, size_t len) { return DX_RET(munmap(addr, len)); }
DX_FN(munmap);
static int d_mprotect(void *addr, size_t len, int prot) { return DX_RET(mprotect(addr, len, prot & 7)); }
DX_FN(mprotect);
static int d_msync(void *addr, size_t len, int flags) {
    /* Darwin: MS_ASYNC 1, MS_INVALIDATE 2, MS_SYNC 0x10 */
    int hf = 0;
    if (flags & 1) hf |= MS_ASYNC;
    if (flags & 2) hf |= MS_INVALIDATE;
    if (flags & 0x10) hf |= MS_SYNC;
    return DX_RET(msync(addr, len, hf));
}
DX_FN(msync);
static int d_mlock(const void *addr, size_t len) { return DX_RET(mlock(addr, len)); }
DX_FN(mlock);
static int d_munlock(const void *addr, size_t len) { return DX_RET(munlock(addr, len)); }
DX_FN(munlock);
static int d_madvise(void *addr, size_t len, int advice) {
    int h;
    switch (advice) {
    case 0: h = MADV_NORMAL; break;
    case 1: h = MADV_RANDOM; break;
    case 2: h = MADV_SEQUENTIAL; break;
    case 3: h = MADV_WILLNEED; break;
    case 4: h = MADV_DONTNEED; break;
    case 5: h = MADV_FREE; break;
    case 7: h = MADV_DONTNEED; break; /* MADV_FREE_REUSABLE: contents may be dropped */
    default: return 0;                /* FREE_REUSE, CAN_REUSE, ZERO_WIRED_PAGES, PAGEOUT */
    }
    return DX_RET(madvise(addr, len, h));
}
DX_FN(madvise);
DX_EXPORT("_posix_madvise", d_madvise);
static int d_mincore(const void *addr, size_t len, char *vec) {
    return DX_RET(mincore((void *)addr, len, (unsigned char *)vec));
}
DX_FN(mincore);

/* ---- Mach basics --------------------------------------------------------- */

static uint32_t d_mach_task_self_ = 0x103;
DX_EXPORT("_mach_task_self_", &d_mach_task_self_);
static uint64_t d_vm_page_size = 4096, d_vm_page_mask = 4095;
static int d_vm_page_shift = 12;
DX_EXPORT("_vm_page_size", &d_vm_page_size);
DX_EXPORT("_vm_page_mask", &d_vm_page_mask);
DX_EXPORT("_vm_page_shift", &d_vm_page_shift);
DX_EXPORT("_vm_kernel_page_size", &d_vm_page_size);
static uint32_t d_mach_host_self(void) { return 0x203; }
DX_FN(mach_host_self);
static int d_mach_port_deallocate(uint32_t task, uint32_t name) { (void)task; (void)name; return 0; }
DX_FN(mach_port_deallocate);
static int d_host_page_size(uint32_t host, uint64_t *size) { (void)host; *size = 4096; return 0; }
DX_FN(host_page_size);
static const char *d_mach_error_string(int e) { (void)e; return "(mach error)"; }
DX_FN(mach_error_string);

static uint64_t d_mach_absolute_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}
DX_FN(mach_absolute_time);
DX_EXPORT("_mach_continuous_time", d_mach_absolute_time);
DX_EXPORT("_mach_approximate_time", d_mach_absolute_time);
struct d_timebase {
    uint32_t numer, denom;
};
static int d_mach_timebase_info(struct d_timebase *tb) {
    tb->numer = 1;
    tb->denom = 1;
    return 0;
}
DX_FN(mach_timebase_info);

/* vm_allocate family: anonymous memory. flags bit 0 = VM_FLAGS_ANYWHERE */
static int d_mach_vm_allocate(uint32_t task, uint64_t *addr, uint64_t size, int flags) {
    (void)task;
    void *want = (flags & 1) ? NULL : (void *)*addr;
    void *r = mmap(want, size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | ((flags & 1) ? 0 : MAP_FIXED_NOREPLACE), -1, 0);
    if (r == MAP_FAILED) return 3; /* KERN_NO_SPACE */
    *addr = (uint64_t)r;
    return 0;
}
DX_FN(mach_vm_allocate);
DX_EXPORT("_vm_allocate", d_mach_vm_allocate);
static int d_mach_vm_deallocate(uint32_t task, uint64_t addr, uint64_t size) {
    (void)task;
    return munmap((void *)addr, size) ? 1 : 0;
}
DX_FN(mach_vm_deallocate);
DX_EXPORT("_vm_deallocate", d_mach_vm_deallocate);
static int d_mach_vm_protect(uint32_t task, uint64_t addr, uint64_t size, int setmax, int prot) {
    (void)task; (void)setmax;
    return mprotect((void *)addr, size, prot & 7) ? 2 : 0;
}
DX_FN(mach_vm_protect);
DX_EXPORT("_vm_protect", d_mach_vm_protect);

/* mach_vm_region(VM_REGION_BASIC_INFO_64): answered from /proc/self/maps. */
struct d_vm_region_basic_info_64 {
    int protection, max_protection;
    unsigned inheritance;
    unsigned shared, reserved;
    uint64_t offset;
    int behavior;
    unsigned short user_wired_count;
} __attribute__((packed));

static int d_mach_vm_region(uint32_t task, uint64_t *address, uint64_t *size, int flavor, void *info,
                            uint32_t *count, uint32_t *object_name) {
    (void)task; (void)flavor;
    FILE *f = fopen("/proc/self/maps", "re");
    if (!f) return 5; /* KERN_FAILURE */
    char line[512];
    int found = 0;
    while (fgets(line, sizeof line, f)) {
        unsigned long lo, hi, off;
        char perms[8];
        if (sscanf(line, "%lx-%lx %7s %lx", &lo, &hi, perms, &off) != 4) continue;
        if (hi <= *address) continue;
        *address = lo;
        *size = hi - lo;
        if (info && count && *count >= 9) {
            struct d_vm_region_basic_info_64 bi = {0};
            bi.protection = (perms[0] == 'r' ? 1 : 0) | (perms[1] == 'w' ? 2 : 0) | (perms[2] == 'x' ? 4 : 0);
            bi.max_protection = 7;
            bi.inheritance = 1;
            bi.shared = perms[3] == 's';
            bi.offset = off;
            memcpy(info, &bi, sizeof bi);
            *count = 9;
        }
        if (object_name) *object_name = 0;
        found = 1;
        break;
    }
    fclose(f);
    return found ? 0 : 1; /* KERN_INVALID_ADDRESS */
}
DX_FN(mach_vm_region);

/* ---- time ---------------------------------------------------------------- */

static int clock_to_host(int d) {
    switch (d) {
    case 0: return CLOCK_REALTIME;
    case 4: case 5: return CLOCK_MONOTONIC_RAW;
    case 6: return CLOCK_MONOTONIC;
    case 8: case 9: return CLOCK_MONOTONIC; /* UPTIME_RAW: excludes sleep */
    case 12: return CLOCK_PROCESS_CPUTIME_ID;
    case 16: return CLOCK_THREAD_CPUTIME_ID;
    }
    return -1;
}
static int d_clock_gettime(int id, struct timespec *ts) {
    int h = clock_to_host(id);
    if (h < 0) { dx_set_errno(22); return -1; }
    return DX_RET(clock_gettime(h, ts));
}
DX_FN(clock_gettime);
static int d_clock_getres(int id, struct timespec *ts) {
    int h = clock_to_host(id);
    if (h < 0) { dx_set_errno(22); return -1; }
    return DX_RET(clock_getres(h, ts));
}
DX_FN(clock_getres);
static uint64_t d_clock_gettime_nsec_np(int id) {
    struct timespec ts;
    int h = clock_to_host(id);
    if (h < 0 || clock_gettime(h, &ts) < 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}
DX_FN(clock_gettime_nsec_np);
static int d_gettimeofday(struct d_timeval *tv, void *tz) {
    (void)tz;
    struct timeval h;
    gettimeofday(&h, NULL);
    if (tv) {
        tv->tv_sec = h.tv_sec;
        tv->tv_usec = (int32_t)h.tv_usec;
    }
    return 0;
}
DX_FN(gettimeofday);
static int d_nanosleep(const struct timespec *req, struct timespec *rem) { return DX_RET(nanosleep(req, rem)); }
DX_FN(nanosleep);
DX_EXPORT("_nanosleep$NOCANCEL", d_nanosleep);
static int d_usleep(unsigned us) { return DX_RET(usleep(us)); }
DX_FN(usleep);
DX_EXPORT("_usleep$NOCANCEL", d_usleep);
static unsigned d_sleep(unsigned s) { return sleep(s); }
DX_FN(sleep);
DX_PASS(time); DX_PASS(localtime); DX_PASS(localtime_r); DX_PASS(gmtime); DX_PASS(gmtime_r);
DX_PASS(mktime); DX_PASS(timegm); DX_PASS(strftime); DX_PASS(strptime); DX_PASS(ctime);
DX_PASS(ctime_r); DX_PASS(asctime); DX_PASS(asctime_r); DX_PASS(tzset); DX_PASS(difftime);
DX_PASS(clock);
DX_EXPORT("_tzname", tzname);
DX_EXPORT("_timezone", &timezone);
DX_EXPORT("_daylight", &daylight);

struct d_itimerval {
    struct d_timeval it_interval, it_value;
};
static int d_setitimer(int which, const struct d_itimerval *nv, struct d_itimerval *ov) {
    struct itimerval hn, ho;
    if (nv) {
        hn.it_interval.tv_sec = nv->it_interval.tv_sec;
        hn.it_interval.tv_usec = nv->it_interval.tv_usec;
        hn.it_value.tv_sec = nv->it_value.tv_sec;
        hn.it_value.tv_usec = nv->it_value.tv_usec;
    }
    int r = setitimer(which, nv ? &hn : NULL, ov ? &ho : NULL);
    if (r == 0 && ov) {
        ov->it_interval.tv_sec = ho.it_interval.tv_sec;
        ov->it_interval.tv_usec = (int32_t)ho.it_interval.tv_usec;
        ov->it_value.tv_sec = ho.it_value.tv_sec;
        ov->it_value.tv_usec = (int32_t)ho.it_value.tv_usec;
    }
    return DX_RET(r);
}
DX_FN(setitimer);
static int d_getitimer(int which, struct d_itimerval *ov) {
    struct itimerval ho;
    int r = getitimer(which, &ho);
    if (r == 0) {
        ov->it_interval.tv_sec = ho.it_interval.tv_sec;
        ov->it_interval.tv_usec = (int32_t)ho.it_interval.tv_usec;
        ov->it_value.tv_sec = ho.it_value.tv_sec;
        ov->it_value.tv_usec = (int32_t)ho.it_value.tv_usec;
    }
    return DX_RET(r);
}
DX_FN(getitimer);

/* ---- system identity ------------------------------------------------------
 * The layer presents itself as macOS 15.0 (Darwin 24.0.0) on Intel. */
#define OS_PRODUCT_VERSION "15.0"
#define OS_BUILD "24A335"
#define KERN_RELEASE "24.0.0"
#define KERN_VERSION "Darwin Kernel Version 24.0.0: Mach-O compatibility layer on Linux; root:xnu/RELEASE_X86_64"

struct d_utsname {
    char sysname[256], nodename[256], release[256], version[256], machine[256];
};
static int d_uname(struct d_utsname *u) {
    memset(u, 0, sizeof *u);
    strcpy(u->sysname, "Darwin");
    if (gethostname(u->nodename, 255) < 0) strcpy(u->nodename, "localhost");
    strcpy(u->release, KERN_RELEASE);
    strcpy(u->version, KERN_VERSION);
    strcpy(u->machine, "x86_64");
    return 0;
}
DX_FN(uname);

static int d_gethostuuid(unsigned char uuid[16], const struct timespec *timeout) {
    (void)timeout;
    memset(uuid, 0, 16);
    FILE *f = fopen("/etc/machine-id", "re");
    char hex[40] = {0};
    if (f) {
        if (!fgets(hex, sizeof hex, f)) hex[0] = 0;
        fclose(f);
    }
    for (int i = 0; i < 16; i++) {
        unsigned v = 0x5c + i;
        if (strlen(hex) >= (size_t)(2 * i + 2)) sscanf(hex + 2 * i, "%2x", &v);
        uuid[i] = (unsigned char)v;
    }
    return 0;
}
DX_FN(gethostuuid);

static long d_sysconf(int name) {
    switch (name) {
    case 1: return sysconf(_SC_ARG_MAX);
    case 2: return sysconf(_SC_CHILD_MAX);
    case 3: return sysconf(_SC_CLK_TCK);
    case 4: return sysconf(_SC_NGROUPS_MAX);
    case 5: return sysconf(_SC_OPEN_MAX);
    case 29: return 4096;
    case 57: return sysconf(_SC_NPROCESSORS_CONF);
    case 58: return sysconf(_SC_NPROCESSORS_ONLN);
    case 70: return sysconf(_SC_GETGR_R_SIZE_MAX) > 0 ? sysconf(_SC_GETGR_R_SIZE_MAX) : 4096;
    case 71: return sysconf(_SC_GETPW_R_SIZE_MAX) > 0 ? sysconf(_SC_GETPW_R_SIZE_MAX) : 4096;
    case 72: return 255;
    case 73: return 255;
    case 200: return sysconf(_SC_PHYS_PAGES);
    }
    dx_log(1, "sysconf: unsupported Darwin name %d", name);
    dx_set_errno(22);
    return -1;
}
DX_FN(sysconf);

static size_t d_confstr(int name, char *buf, size_t len) {
    const char *v;
    char tmp[PATH_MAX];
    switch (name) {
    case 1: v = "/usr/bin:/bin:/usr/sbin:/sbin"; break;
    case 65536: v = "/tmp/"; break; /* _CS_DARWIN_USER_DIR */
    case 65537: {                   /* _CS_DARWIN_USER_TEMP_DIR */
        const char *t = getenv("TMPDIR");
        snprintf(tmp, sizeof tmp, "%s/", t && *t ? t : "/tmp");
        size_t n = strlen(tmp);
        if (n > 1 && tmp[n - 2] == '/') tmp[n - 1] = 0;
        v = tmp;
        break;
    }
    case 65538: v = "/tmp/"; break; /* _CS_DARWIN_USER_CACHE_DIR */
    default:
        dx_set_errno(22);
        return 0;
    }
    size_t need = strlen(v) + 1;
    if (buf && len) {
        strncpy(buf, v, len - 1);
        buf[len - 1] = 0;
    }
    return need;
}
DX_FN(confstr);

/* ---- sysctl -------------------------------------------------------------- */

static int out_bytes(void *oldp, size_t *oldlenp, const void *src, size_t n) {
    if (!oldlenp) return 0;
    if (!oldp) {
        *oldlenp = n;
        return 0;
    }
    if (*oldlenp < n) {
        memcpy(oldp, src, *oldlenp);
        dx_set_errno(12); /* ENOMEM */
        return -1;
    }
    memcpy(oldp, src, n);
    *oldlenp = n;
    return 0;
}
static int out_str(void *oldp, size_t *oldlenp, const char *s) { return out_bytes(oldp, oldlenp, s, strlen(s) + 1); }
/* Integer results adapt to the caller's buffer: 4 or 8 bytes. */
static int out_int(void *oldp, size_t *oldlenp, int64_t v, size_t natural) {
    size_t n = natural;
    if (oldp && oldlenp && (*oldlenp == 4 || *oldlenp == 8)) n = *oldlenp;
    if (n == 8) return out_bytes(oldp, oldlenp, &v, 8);
    int32_t w = (int32_t)v;
    return out_bytes(oldp, oldlenp, &w, 4);
}

static const char *cpu_brand(void) {
    static char brand[128];
    if (brand[0]) return brand;
    FILE *f = fopen("/proc/cpuinfo", "re");
    char line[512];
    while (f && fgets(line, sizeof line, f)) {
        if (!strncmp(line, "model name", 10)) {
            char *c = strchr(line, ':');
            if (c) {
                c += 2;
                c[strcspn(c, "\n")] = 0;
                strncpy(brand, c, sizeof brand - 1);
            }
            break;
        }
    }
    if (f) fclose(f);
    if (!brand[0]) strcpy(brand, "x86_64 processor");
    return brand;
}

int dx_sysctl_proc(const int *mib, unsigned miblen, void *oldp, size_t *oldlenp) __attribute__((weak));

static int sysctl_by_name(const char *name, void *oldp, size_t *oldlenp) {
    long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
    if (!strcmp(name, "kern.ostype")) return out_str(oldp, oldlenp, "Darwin");
    if (!strcmp(name, "kern.osrelease")) return out_str(oldp, oldlenp, KERN_RELEASE);
    if (!strcmp(name, "kern.osversion")) return out_str(oldp, oldlenp, OS_BUILD);
    if (!strcmp(name, "kern.osproductversion")) return out_str(oldp, oldlenp, OS_PRODUCT_VERSION);
    if (!strcmp(name, "kern.version")) return out_str(oldp, oldlenp, KERN_VERSION);
    if (!strcmp(name, "kern.osrevision")) return out_int(oldp, oldlenp, 199506, 4);
    if (!strcmp(name, "kern.hostname")) {
        char h[256];
        if (gethostname(h, sizeof h) < 0) strcpy(h, "localhost");
        return out_str(oldp, oldlenp, h);
    }
    if (!strcmp(name, "kern.argmax")) return out_int(oldp, oldlenp, 1048576, 4);
    if (!strcmp(name, "kern.maxproc")) return out_int(oldp, oldlenp, 4096, 4);
    if (!strcmp(name, "kern.maxfiles")) return out_int(oldp, oldlenp, 1048576, 4);
    if (!strcmp(name, "kern.maxfilesperproc")) return out_int(oldp, oldlenp, 1048576, 4);
    if (!strcmp(name, "kern.ngroups")) return out_int(oldp, oldlenp, 16, 4);
    if (!strcmp(name, "kern.ipc.somaxconn")) return out_int(oldp, oldlenp, 4096, 4);
    if (!strcmp(name, "kern.ipc.maxsockbuf")) return out_int(oldp, oldlenp, 8388608, 4);
    if (!strcmp(name, "kern.secure_kernel")) return out_int(oldp, oldlenp, 0, 4);
    if (!strcmp(name, "kern.boottime")) {
        struct sysinfo si;
        sysinfo(&si);
        struct d_timeval tv = {time(NULL) - si.uptime, 0, 0};
        return out_bytes(oldp, oldlenp, &tv, sizeof tv);
    }
    if (!strcmp(name, "kern.uuid") || !strcmp(name, "kern.bootsessionuuid"))
        return out_str(oldp, oldlenp, "5C10A000-0000-4000-8000-000000000001");
    if (!strcmp(name, "hw.machine")) return out_str(oldp, oldlenp, "x86_64");
    if (!strcmp(name, "hw.model")) return out_str(oldp, oldlenp, "MacPro7,1");
    if (!strcmp(name, "hw.ncpu") || !strcmp(name, "hw.activecpu") || !strcmp(name, "hw.logicalcpu") ||
        !strcmp(name, "hw.logicalcpu_max") || !strcmp(name, "hw.physicalcpu") ||
        !strcmp(name, "hw.physicalcpu_max") || !strcmp(name, "hw.availcpu"))
        return out_int(oldp, oldlenp, ncpu, 4);
    if (!strcmp(name, "hw.packages")) return out_int(oldp, oldlenp, 1, 4);
    if (!strcmp(name, "hw.byteorder")) return out_int(oldp, oldlenp, 1234, 4);
    if (!strcmp(name, "hw.pagesize")) return out_int(oldp, oldlenp, 4096, 8);
    if (!strcmp(name, "hw.memsize") || !strcmp(name, "hw.physmem") || !strcmp(name, "hw.usermem"))
        return out_int(oldp, oldlenp, (int64_t)sysconf(_SC_PHYS_PAGES) * 4096, 8);
    if (!strcmp(name, "hw.cachelinesize")) return out_int(oldp, oldlenp, 64, 8);
    if (!strcmp(name, "hw.l1icachesize") || !strcmp(name, "hw.l1dcachesize")) return out_int(oldp, oldlenp, 32768, 8);
    if (!strcmp(name, "hw.l2cachesize")) return out_int(oldp, oldlenp, 262144, 8);
    if (!strcmp(name, "hw.l3cachesize")) return out_int(oldp, oldlenp, 8388608, 8);
    if (!strcmp(name, "hw.cpufrequency") || !strcmp(name, "hw.cpufrequency_max")) return out_int(oldp, oldlenp, 2400000000LL, 8);
    if (!strcmp(name, "hw.tbfrequency")) return out_int(oldp, oldlenp, 1000000000LL, 8);
    if (!strcmp(name, "hw.cputype")) return out_int(oldp, oldlenp, 7, 4);
    if (!strcmp(name, "hw.cpusubtype")) return out_int(oldp, oldlenp, 8, 4);
    if (!strcmp(name, "hw.cpu64bit_capable")) return out_int(oldp, oldlenp, 1, 4);
    if (!strcmp(name, "machdep.cpu.brand_string")) return out_str(oldp, oldlenp, cpu_brand());
    if (!strcmp(name, "machdep.cpu.vendor")) return out_str(oldp, oldlenp, "GenuineIntel");
    if (!strcmp(name, "machdep.cpu.core_count") || !strcmp(name, "machdep.cpu.thread_count"))
        return out_int(oldp, oldlenp, ncpu, 4);
    if (!strcmp(name, "sysctl.proc_translated")) return out_int(oldp, oldlenp, 0, 4);
    if (!strcmp(name, "sysctl.proc_native")) return out_int(oldp, oldlenp, 1, 4);
    if (!strncmp(name, "hw.optional.", 12)) {
        const char *f = name + 12;
        int v = 0;
        if (!strcmp(f, "floatingpoint") || !strcmp(f, "mmx") || !strcmp(f, "sse") || !strcmp(f, "sse2") ||
            !strcmp(f, "x86_64"))
            v = 1;
        else if (!strcmp(f, "sse3")) v = __builtin_cpu_supports("sse3");
        else if (!strcmp(f, "supplementalsse3")) v = __builtin_cpu_supports("ssse3");
        else if (!strcmp(f, "sse4_1")) v = __builtin_cpu_supports("sse4.1");
        else if (!strcmp(f, "sse4_2")) v = __builtin_cpu_supports("sse4.2");
        else if (!strcmp(f, "avx1_0")) v = __builtin_cpu_supports("avx");
        else if (!strcmp(f, "avx2_0")) v = __builtin_cpu_supports("avx2");
        else if (!strcmp(f, "aes")) v = __builtin_cpu_supports("aes");
        else if (!strcmp(f, "bmi1")) v = __builtin_cpu_supports("bmi");
        else if (!strcmp(f, "bmi2")) v = __builtin_cpu_supports("bmi2");
        else if (!strcmp(f, "fma")) v = __builtin_cpu_supports("fma");
        return out_int(oldp, oldlenp, v != 0, 4);
    }
    dx_log(1, "sysctlbyname: unknown name %s", name);
    dx_set_errno(2);
    return -1;
}

static int d_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    (void)newp; (void)newlen;
    return sysctl_by_name(name, oldp, oldlenp);
}
DX_FN(sysctlbyname);

/* MIB <-> name. Names without a classic numeric MIB get a synthetic one
 * {SYNTH_MIB, index} so name-to-MIB lookups (sysctlnametomib, and the
 * {0,3} "name2oid" request Go uses) round-trip. */
static const struct {
    int a, b;
    const char *name;
} mib_names[] = {
    {1, 1, "kern.ostype"}, {1, 2, "kern.osrelease"}, {1, 3, "kern.osrevision"},
    {1, 4, "kern.version"}, {1, 6, "kern.maxproc"}, {1, 7, "kern.maxfiles"},
    {1, 8, "kern.argmax"}, {1, 10, "kern.hostname"}, {1, 18, "kern.ngroups"},
    {1, 21, "kern.boottime"}, {1, 29, "kern.maxfilesperproc"}, {1, 65, "kern.osversion"},
    {6, 1, "hw.machine"}, {6, 2, "hw.model"}, {6, 3, "hw.ncpu"}, {6, 4, "hw.byteorder"},
    {6, 5, "hw.physmem"}, {6, 6, "hw.usermem"}, {6, 7, "hw.pagesize"},
    {6, 15, "hw.cpufrequency"}, {6, 16, "hw.cachelinesize"}, {6, 17, "hw.l1icachesize"},
    {6, 18, "hw.l1dcachesize"}, {6, 20, "hw.l2cachesize"}, {6, 22, "hw.l3cachesize"},
    {6, 23, "hw.tbfrequency"}, {6, 24, "hw.memsize"}, {6, 25, "hw.availcpu"},
};
#define SYNTH_MIB 0x5cf
static char *synth_names[256];
static int synth_count;

static int name_to_mib(const char *name, int *mib, size_t *len) {
    if (*len < 2) return -1;
    for (size_t i = 0; i < sizeof mib_names / sizeof mib_names[0]; i++)
        if (!strcmp(mib_names[i].name, name)) {
            mib[0] = mib_names[i].a;
            mib[1] = mib_names[i].b;
            *len = 2;
            return 0;
        }
    /* only hand out a MIB for names we can actually answer */
    size_t probe = 0;
    int saved = dx_thread_self()->d_errno;
    if (sysctl_by_name(name, NULL, &probe) < 0) return -1;
    dx_thread_self()->d_errno = saved;
    int idx = -1;
    for (int i = 0; i < synth_count; i++)
        if (!strcmp(synth_names[i], name)) idx = i;
    if (idx < 0) {
        if (synth_count >= 256) return -1;
        idx = synth_count;
        synth_names[synth_count++] = strdup(name);
    }
    mib[0] = SYNTH_MIB;
    mib[1] = idx;
    *len = 2;
    return 0;
}

static int d_sysctl(const int *mib, unsigned miblen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    const char *name = NULL;
    if (miblen == 2 && mib[0] == 0 && mib[1] == 3 && newp) { /* name2oid */
        char nm[256];
        size_t n = newlen < sizeof nm - 1 ? newlen : sizeof nm - 1;
        memcpy(nm, newp, n);
        nm[n] = 0;
        size_t cnt = oldlenp ? *oldlenp / sizeof(int) : 0;
        if (name_to_mib(nm, oldp, &cnt) < 0) {
            dx_set_errno(2);
            return -1;
        }
        *oldlenp = cnt * sizeof(int);
        return 0;
    }
    if (miblen >= 2 && mib[0] == SYNTH_MIB && mib[1] >= 0 && mib[1] < synth_count)
        return sysctl_by_name(synth_names[mib[1]], oldp, oldlenp);
    if (miblen >= 2 && mib[0] == 1 && (mib[1] == 14 || mib[1] == 38 || mib[1] == 49)) {
        /* KERN_PROC, KERN_PROCARGS, KERN_PROCARGS2 */
        if (dx_sysctl_proc) return dx_sysctl_proc(mib, miblen, oldp, oldlenp);
    } else if (miblen >= 2) {
        for (size_t i = 0; i < sizeof mib_names / sizeof mib_names[0]; i++)
            if (mib_names[i].a == mib[0] && mib_names[i].b == mib[1]) name = mib_names[i].name;
    }
    if (!name) {
        dx_log(1, "sysctl: unsupported mib {%d, %d, ...} (len %u)", miblen > 0 ? mib[0] : -1,
               miblen > 1 ? mib[1] : -1, miblen);
        dx_set_errno(2);
        return -1;
    }
    return sysctl_by_name(name, oldp, oldlenp);
}
DX_FN(sysctl);

static int d_sysctlnametomib(const char *name, int *mib, size_t *len) {
    if (name_to_mib(name, mib, len) < 0) {
        dx_set_errno(2);
        return -1;
    }
    return 0;
}
DX_FN(sysctlnametomib);

/* ---- small system services ---------------------------------------------- */

static int d_notify_is_valid_token(int token) { (void)token; return 0; }
DX_FN(notify_is_valid_token);
static int d_notify_register_check(const char *name, int *token) { (void)name; *token = 1; return 0; }
DX_FN(notify_register_check);
static int d_notify_cancel(int token) { (void)token; return 0; }
DX_FN(notify_cancel);
static int d_notify_post(const char *name) { (void)name; return 0; }
DX_FN(notify_post);

/* xpc_date_create_from_current: an opaque date object; callers only pass it
 * back to other XPC calls. */
static void *d_xpc_date_create_from_current(void) {
    struct timespec *ts = malloc(sizeof *ts);
    clock_gettime(CLOCK_REALTIME, ts);
    return ts;
}
DX_FN(xpc_date_create_from_current);
