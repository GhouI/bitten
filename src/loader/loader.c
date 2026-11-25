/* Mach-O image loader: maps x86-64 Mach-O executables and dylibs into a
 * Linux process, applies their fixups and binds their imports either to
 * other loaded Mach-O images or to the built-in Darwin shim registry. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "dx.h"
#include "macho.h"

#define MAX_SEGS 48
#define MAX_DEPS 512
#define MAX_RPATHS 32
#define MAX_IMAGES 1024

struct seg {
    char name[17];
    uint64_t vmaddr, vmsize, fileoff, filesize;
    int prot;
};

struct dep {
    char *name;
    struct dx_image *img; /* NULL: provided by the shim registry */
    int weak, reexport;
};

struct dx_image {
    char *path;
    char *install_name;
    uint8_t *cmds; /* private copy of header + load commands */
    struct mach_header_64 *mh; /* mapped header */
    uintptr_t slide;
    uint64_t lo, hi; /* unslid address range */
    struct seg segs[MAX_SEGS];
    int nsegs;
    struct dep deps[MAX_DEPS];
    int ndeps;
    char *rpaths[MAX_RPATHS];
    int nrpaths;
    struct symtab_command symtab;
    struct dyld_info_command dyld_info;
    int has_dyld_info;
    uint32_t trie_off, trie_size;
    uint32_t chained_off, chained_size;
    uint64_t entryoff;
    int has_entry;
    uint64_t thread_rip; /* LC_UNIXTHREAD entry (unslid), jumped to kernel-style */
    int has_thread;
    uint32_t filetype, flags;
    int bound, inited, visiting;
    /* thread-local variables */
    uintptr_t tlv_start;
    size_t tlv_size;
    unsigned long tlv_key;
    int has_tlv;
};

static struct dx_image *images[MAX_IMAGES];
static int nimages;
static struct dx_image *main_image;
static char loader_path[PATH_MAX];

int dx_argc;
char **dx_argv;
char **dx_envp;
static const char *apple_strings[4];

/* provided by thread.c / tlv.S */
unsigned long dx_tsd_key_alloc(void (*destructor)(void *));
void *dx_tlv_get_addr(struct tlv_descriptor *);
void dx_jump_entry(void *pc, void *sp) __attribute__((noreturn));
extern char **d_NXArgv;

const char *dx_loader_path(void) {
    if (!loader_path[0]) {
        ssize_t n = readlink("/proc/self/exe", loader_path, sizeof loader_path - 1);
        if (n < 0) n = 0;
        loader_path[n] = 0;
    }
    return loader_path;
}

const char *dx_main_path(void) { return main_image ? main_image->path : ""; }

/* ---- unimplemented-symbol stubs -------------------------------------- */

struct stub {
    struct stub *next;
    const char *name;
    void *code;
};
static struct stub *stubs;
static uint8_t *stub_arena;
static size_t stub_used, stub_cap;
int dx_stub_mode; /* 0 = abort on call, 1 = log and return 0 */

static uint64_t unimplemented_called(const char *name) {
    if (dx_stub_mode == 1) {
        dx_log(0, "unimplemented Darwin symbol called (returning 0): %s", name);
        return 0;
    }
    dx_fatal("unimplemented Darwin symbol called: %s\n"
             "  (set BITTEN_STUBS=zero to return 0 instead of aborting)",
             name);
}

static void *make_stub(const char *name) {
    for (struct stub *s = stubs; s; s = s->next)
        if (!strcmp(s->name, name)) return s->code;
    if (!stub_arena || stub_used + 32 > stub_cap) {
        stub_cap = 1 << 20;
        stub_arena = mmap(NULL, stub_cap, PROT_READ | PROT_WRITE | PROT_EXEC,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (stub_arena == MAP_FAILED) dx_fatal("cannot allocate stub arena");
        stub_used = 0;
    }
    struct stub *s = malloc(sizeof *s);
    s->name = strdup(name);
    uint8_t *c = stub_arena + stub_used;
    stub_used += 32;
    /* A frame of its own with the stack aligned: callers may reach the stub
     * by a tail call (Swift async and tail-calling code), leaving the stack
     * misaligned for the C handler. leave/ret keeps the return path intact
     * for BITTEN_STUBS=zero. */
    uint64_t n = (uint64_t)s->name, h = (uint64_t)unimplemented_called;
    c[0] = 0x55;                                             /* push %rbp */
    c[1] = 0x48; c[2] = 0x89; c[3] = 0xe5;                   /* mov %rsp, %rbp */
    c[4] = 0x48; c[5] = 0x83; c[6] = 0xe4; c[7] = 0xf0;      /* and $-16, %rsp */
    c[8] = 0x48; c[9] = 0xbf; memcpy(c + 10, &n, 8);         /* movabs $name, %rdi */
    c[18] = 0x48; c[19] = 0xb8; memcpy(c + 20, &h, 8);       /* movabs $handler, %rax */
    c[28] = 0xff; c[29] = 0xd0;                              /* call *%rax */
    c[30] = 0xc9;                                            /* leave */
    c[31] = 0xc3;                                            /* ret */
    s->code = c;
    s->next = stubs;
    stubs = s;
    return c;
}

/* ---- missing-import accounting --------------------------------------- */
struct missing {
    struct missing *next;
    char *sym, *lib, *image;
};
static struct missing *missing_head;
static int missing_count;

static void note_missing(struct dx_image *img, const char *lib, const char *sym) {
    for (struct missing *m = missing_head; m; m = m->next)
        if (!strcmp(m->sym, sym) && !strcmp(m->image, img->path)) return;
    struct missing *m = malloc(sizeof *m);
    m->sym = strdup(sym);
    m->lib = strdup(lib ? lib : "?");
    m->image = img->path;
    m->next = missing_head;
    missing_head = m;
    missing_count++;
}

int dx_missing_count(void) { return missing_count; }
void dx_missing_each(void (*cb)(const char *image, const char *lib, const char *sym, void *ctx),
                     void *ctx) {
    for (struct missing *m = missing_head; m; m = m->next) cb(m->image, m->lib, m->sym, ctx);
}

/* ---- helpers ---------------------------------------------------------- */

static uint64_t read_uleb(const uint8_t **p, const uint8_t *end) {
    uint64_t r = 0;
    int shift = 0;
    while (*p < end) {
        uint8_t b = *(*p)++;
        if (shift < 64) r |= (uint64_t)(b & 0x7f) << shift;
        shift += 7;
        if (!(b & 0x80)) break;
    }
    return r;
}

static int64_t read_sleb(const uint8_t **p, const uint8_t *end) {
    int64_t r = 0;
    int shift = 0;
    uint8_t b = 0;
    while (*p < end) {
        b = *(*p)++;
        r |= (int64_t)(b & 0x7f) << shift;
        shift += 7;
        if (!(b & 0x80)) break;
    }
    if (shift < 64 && (b & 0x40)) r |= -((int64_t)1 << shift);
    return r;
}

/* File offset inside the image -> mapped address. */
static void *img_off(struct dx_image *img, uint64_t off) {
    for (int i = 0; i < img->nsegs; i++) {
        struct seg *s = &img->segs[i];
        if (s->filesize && off >= s->fileoff && off < s->fileoff + s->filesize)
            return (void *)(img->slide + s->vmaddr + (off - s->fileoff));
    }
    return NULL;
}

int dx_is_macho_file(const char *path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    uint32_t magic = 0;
    ssize_t n = read(fd, &magic, 4);
    close(fd);
    if (n != 4) return 0;
    return magic == MH_MAGIC_64 || __builtin_bswap32(magic) == FAT_MAGIC ||
           __builtin_bswap32(magic) == FAT_MAGIC_64;
}

/* Locate the x86-64 slice. Returns 0 on success. */
static int find_slice(int fd, uint64_t *off, uint64_t *size) {
    struct stat st;
    if (fstat(fd, &st) < 0) return -1;
    uint8_t buf[4096];
    ssize_t n = pread(fd, buf, sizeof buf, 0);
    if (n < 8) return -1;
    uint32_t magic;
    memcpy(&magic, buf, 4);
    if (magic == MH_MAGIC_64) {
        struct mach_header_64 *mh = (void *)buf;
        if (mh->cputype != CPU_TYPE_X86_64) return -2;
        *off = 0;
        *size = st.st_size;
        return 0;
    }
    uint32_t be = __builtin_bswap32(magic);
    if (be != FAT_MAGIC && be != FAT_MAGIC_64) return -1;
    uint32_t narch = __builtin_bswap32(((struct fat_header *)buf)->nfat_arch);
    const uint8_t *p = buf + sizeof(struct fat_header);
    for (uint32_t i = 0; i < narch; i++) {
        if (be == FAT_MAGIC) {
            if (p + sizeof(struct fat_arch) > buf + n) break;
            const struct fat_arch *a = (const void *)p;
            if (__builtin_bswap32(a->cputype) == CPU_TYPE_X86_64) {
                *off = __builtin_bswap32(a->offset);
                *size = __builtin_bswap32(a->size);
                return 0;
            }
            p += sizeof *a;
        } else {
            if (p + sizeof(struct fat_arch_64) > buf + n) break;
            const struct fat_arch_64 *a = (const void *)p;
            if (__builtin_bswap32(a->cputype) == CPU_TYPE_X86_64) {
                *off = __builtin_bswap64(a->offset);
                *size = __builtin_bswap64(a->size);
                return 0;
            }
            p += sizeof *a;
        }
    }
    return -2; /* no x86-64 slice */
}

/* ---- export lookup ---------------------------------------------------- */

static void *lookup_in_image(struct dx_image *img, const char *name, int depth);

static void *trie_lookup(struct dx_image *img, const char *name, int depth) {
    if (!img->trie_size) return NULL;
    const uint8_t *start = img_off(img, img->trie_off);
    if (!start) return NULL;
    const uint8_t *end = start + img->trie_size;
    const uint8_t *p = start;
    const char *s = name;
    for (int guard = 0; guard < 4096; guard++) {
        if (p >= end) return NULL;
        uint64_t term = read_uleb(&p, end);
        const uint8_t *children = p + term;
        if (*s == 0) {
            if (!term) return NULL;
            uint64_t flags = read_uleb(&p, end);
            if (flags & EXPORT_SYMBOL_FLAGS_REEXPORT) {
                uint64_t ord = read_uleb(&p, end);
                const char *imp = (const char *)p;
                if (!*imp) imp = name;
                if (ord == 0 || ord > (uint64_t)img->ndeps || depth > 8) return NULL;
                struct dep *d = &img->deps[ord - 1];
                if (d->img) return lookup_in_image(d->img, imp, depth + 1);
                return dx_registry_lookup(imp);
            }
            uint64_t value = read_uleb(&p, end);
            if (flags & EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER) {
                uint64_t resolver = read_uleb(&p, end);
                void *(*fn)(void) = (void *)((uintptr_t)img->mh + resolver);
                return fn();
            }
            if ((flags & EXPORT_SYMBOL_FLAGS_KIND_MASK) == EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE)
                return (void *)value;
            return (void *)((uintptr_t)img->mh + value);
        }
        if (children >= end) return NULL;
        p = children;
        unsigned n = *p++;
        int found = 0;
        for (unsigned i = 0; i < n && p < end; i++) {
            const char *edge = (const char *)p;
            size_t len = strnlen(edge, end - p);
            p += len + 1;
            uint64_t off = read_uleb(&p, end);
            if (!found && len && !strncmp(s, edge, len)) {
                s += len;
                p = start + off;
                found = 1;
                break;
            }
        }
        if (!found) return NULL;
    }
    return NULL;
}

static void *symtab_lookup(struct dx_image *img, const char *name) {
    if (!img->symtab.nsyms) return NULL;
    struct nlist_64 *syms = img_off(img, img->symtab.symoff);
    const char *strs = img_off(img, img->symtab.stroff);
    if (!syms || !strs) return NULL;
    for (uint32_t i = 0; i < img->symtab.nsyms; i++) {
        struct nlist_64 *n = &syms[i];
        if (n->n_type & N_STAB) continue;
        if (!(n->n_type & N_EXT)) continue;
        if ((n->n_type & N_TYPE) != N_SECT) continue;
        if (n->n_strx >= img->symtab.strsize) continue;
        if (!strcmp(strs + n->n_strx, name)) return (void *)(n->n_value + img->slide);
    }
    return NULL;
}

static void *lookup_in_image(struct dx_image *img, const char *name, int depth) {
    void *r = trie_lookup(img, name, depth);
    if (r) return r;
    if (!img->trie_size) {
        r = symtab_lookup(img, name);
        if (r) return r;
    }
    if (depth > 8) return NULL;
    for (int i = 0; i < img->ndeps; i++) {
        if (!img->deps[i].reexport || !img->deps[i].img) continue;
        r = lookup_in_image(img->deps[i].img, name, depth + 1);
        if (r) return r;
    }
    return NULL;
}

void *dx_image_lookup(struct dx_image *img, const char *name) {
    void *r = lookup_in_image(img, name, 0);
    if (!r && img == main_image) r = symtab_lookup(img, name);
    return r;
}

void *dx_global_lookup(const char *name) {
    for (int i = 0; i < nimages; i++) {
        void *r = lookup_in_image(images[i], name, 0);
        if (r) return r;
    }
    return dx_registry_lookup(name);
}

/* Symbols the loader itself provides. */
static void *loader_symbol(const char *name);

static void *resolve(struct dx_image *img, int64_t ordinal, const char *name, int weak) {
    void *r = NULL;
    const char *lib = NULL;
    if (ordinal > 0 && ordinal <= img->ndeps) {
        struct dep *d = &img->deps[ordinal - 1];
        lib = d->name;
        if (d->img) r = lookup_in_image(d->img, name, 0);
        if (!r) r = loader_symbol(name);
        if (!r) r = dx_registry_lookup(name);
    } else if (ordinal == BIND_SPECIAL_DYLIB_SELF) {
        lib = "(self)";
        r = lookup_in_image(img, name, 0);
        if (!r) r = symtab_lookup(img, name);
    } else if (ordinal == BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE) {
        lib = "(main)";
        if (main_image) r = dx_image_lookup(main_image, name);
    } else {
        lib = "(flat)";
        r = dx_global_lookup(name);
        if (!r) r = loader_symbol(name);
    }
    if (!r) r = loader_symbol(name);
    if (!r) r = dx_registry_lookup(name);
    if (r) return r;
    if (weak) return NULL;
    note_missing(img, lib, name);
    return make_stub(name);
}

/* ---- fixups: classic dyld info --------------------------------------- */

static void do_rebase(struct dx_image *img, uint32_t off, uint32_t size) {
    const uint8_t *p = img_off(img, off);
    if (!p || !size) return;
    const uint8_t *end = p + size;
    uint64_t seg_addr = 0, addr = 0;
    while (p < end) {
        uint8_t byte = *p++;
        uint8_t imm = byte & REBASE_IMMEDIATE_MASK;
        switch (byte & REBASE_OPCODE_MASK) {
        case REBASE_OPCODE_DONE:
            return;
        case REBASE_OPCODE_SET_TYPE_IMM:
            break;
        case REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            if (imm >= img->nsegs) dx_fatal("%s: bad rebase segment", img->path);
            seg_addr = img->segs[imm].vmaddr + img->slide;
            addr = seg_addr + read_uleb(&p, end);
            break;
        case REBASE_OPCODE_ADD_ADDR_ULEB:
            addr += read_uleb(&p, end);
            break;
        case REBASE_OPCODE_ADD_ADDR_IMM_SCALED:
            addr += imm * 8;
            break;
        case REBASE_OPCODE_DO_REBASE_IMM_TIMES:
            for (int i = 0; i < imm; i++, addr += 8) *(uint64_t *)addr += img->slide;
            break;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES: {
            uint64_t n = read_uleb(&p, end);
            for (uint64_t i = 0; i < n; i++, addr += 8) *(uint64_t *)addr += img->slide;
            break;
        }
        case REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB:
            *(uint64_t *)addr += img->slide;
            addr += 8 + read_uleb(&p, end);
            break;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB: {
            uint64_t n = read_uleb(&p, end), skip = read_uleb(&p, end);
            for (uint64_t i = 0; i < n; i++, addr += 8 + skip) *(uint64_t *)addr += img->slide;
            break;
        }
        default:
            dx_fatal("%s: unknown rebase opcode 0x%x", img->path, byte);
        }
    }
}

enum bind_kind { BIND_NORMAL, BIND_LAZY, BIND_WEAK };

static void bind_one(struct dx_image *img, enum bind_kind kind, uint64_t addr, int64_t ordinal,
                     const char *name, int flags, int64_t addend) {
    if (!name) return;
    if (kind == BIND_WEAK) {
        /* Coalesce weak definitions: use the first definition found in load
         * order; leave the slot alone when nobody else defines it. */
        void *r = NULL;
        for (int i = 0; i < nimages && !r; i++) r = lookup_in_image(images[i], name, 0);
        if (!r) r = dx_registry_lookup(name);
        if (r) *(uint64_t *)addr = (uint64_t)r + addend;
        return;
    }
    void *r = resolve(img, ordinal, name, flags & BIND_SYMBOL_FLAGS_WEAK_IMPORT);
    *(uint64_t *)addr = r ? (uint64_t)r + addend : 0;
}

static void do_bind(struct dx_image *img, uint32_t off, uint32_t size, enum bind_kind kind) {
    const uint8_t *p = img_off(img, off);
    if (!p || !size) return;
    const uint8_t *end = p + size;
    uint64_t addr = 0;
    int64_t ordinal = 0, addend = 0;
    const char *name = NULL;
    int flags = 0;
    while (p < end) {
        uint8_t byte = *p++;
        uint8_t imm = byte & BIND_IMMEDIATE_MASK;
        switch (byte & BIND_OPCODE_MASK) {
        case BIND_OPCODE_DONE:
            if (kind != BIND_LAZY) return;
            break; /* lazy stream: entries are separated by DONE */
        case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
            ordinal = imm;
            break;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
            ordinal = read_uleb(&p, end);
            break;
        case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
            ordinal = imm ? (int8_t)(0xf0 | imm) : 0;
            break;
        case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM:
            flags = imm;
            name = (const char *)p;
            p += strnlen(name, end - p) + 1;
            break;
        case BIND_OPCODE_SET_TYPE_IMM:
            break;
        case BIND_OPCODE_SET_ADDEND_SLEB:
            addend = read_sleb(&p, end);
            break;
        case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            if (imm >= img->nsegs) dx_fatal("%s: bad bind segment", img->path);
            addr = img->segs[imm].vmaddr + img->slide + read_uleb(&p, end);
            break;
        case BIND_OPCODE_ADD_ADDR_ULEB:
            addr += read_uleb(&p, end);
            break;
        case BIND_OPCODE_DO_BIND:
            bind_one(img, kind, addr, ordinal, name, flags, addend);
            addr += 8;
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB:
            bind_one(img, kind, addr, ordinal, name, flags, addend);
            addr += 8 + read_uleb(&p, end);
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
            bind_one(img, kind, addr, ordinal, name, flags, addend);
            addr += 8 + imm * 8;
            break;
        case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: {
            uint64_t n = read_uleb(&p, end), skip = read_uleb(&p, end);
            for (uint64_t i = 0; i < n; i++, addr += 8 + skip)
                bind_one(img, kind, addr, ordinal, name, flags, addend);
            break;
        }
        default:
            dx_fatal("%s: unknown bind opcode 0x%x", img->path, byte);
        }
    }
}

/* ---- fixups: chained -------------------------------------------------- */

static void do_chained(struct dx_image *img) {
    const uint8_t *base = img_off(img, img->chained_off);
    if (!base) return;
    const struct dyld_chained_fixups_header *h = (const void *)base;
    const char *symbols = (const char *)base + h->symbols_offset;
    const uint8_t *imports = base + h->imports_offset;

    void **targets = calloc(h->imports_count ? h->imports_count : 1, sizeof(void *));
    int64_t *addends = calloc(h->imports_count ? h->imports_count : 1, sizeof(int64_t));
    for (uint32_t i = 0; i < h->imports_count; i++) {
        int64_t ord;
        int weak;
        uint64_t name_off;
        int64_t addend = 0;
        if (h->imports_format == DYLD_CHAINED_IMPORT) {
            uint32_t v;
            memcpy(&v, imports + 4 * i, 4);
            ord = (int8_t)(v & 0xff);
            weak = (v >> 8) & 1;
            name_off = v >> 9;
        } else if (h->imports_format == DYLD_CHAINED_IMPORT_ADDEND) {
            uint32_t v;
            int32_t a;
            memcpy(&v, imports + 8 * i, 4);
            memcpy(&a, imports + 8 * i + 4, 4);
            ord = (int8_t)(v & 0xff);
            weak = (v >> 8) & 1;
            name_off = v >> 9;
            addend = a;
        } else if (h->imports_format == DYLD_CHAINED_IMPORT_ADDEND64) {
            uint64_t v, a;
            memcpy(&v, imports + 16 * i, 8);
            memcpy(&a, imports + 16 * i + 8, 8);
            ord = (int16_t)(v & 0xffff);
            weak = (v >> 16) & 1;
            name_off = v >> 32;
            addend = (int64_t)a;
        } else {
            dx_fatal("%s: unsupported chained import format %u", img->path, h->imports_format);
        }
        targets[i] = resolve(img, ord, symbols + name_off, weak);
        addends[i] = addend;
    }

    const struct dyld_chained_starts_in_image *starts = (const void *)(base + h->starts_offset);
    for (uint32_t s = 0; s < starts->seg_count; s++) {
        if (!starts->seg_info_offset[s]) continue;
        const struct dyld_chained_starts_in_segment *ss =
            (const void *)((const uint8_t *)starts + starts->seg_info_offset[s]);
        if (ss->pointer_format != DYLD_CHAINED_PTR_64 &&
            ss->pointer_format != DYLD_CHAINED_PTR_64_OFFSET)
            dx_fatal("%s: unsupported chained pointer format %u", img->path, ss->pointer_format);
        for (uint32_t pg = 0; pg < ss->page_count; pg++) {
            uint16_t st = ss->page_start[pg];
            if (st == DYLD_CHAINED_PTR_START_NONE) continue;
            uint64_t *loc = (uint64_t *)((uintptr_t)img->mh + ss->segment_offset +
                                         (uint64_t)pg * ss->page_size + st);
            for (;;) {
                uint64_t raw = *loc;
                uint64_t next = (raw >> 51) & 0xfff;
                if (raw >> 63) {
                    uint32_t ord = raw & 0xffffff;
                    uint8_t addend = (raw >> 24) & 0xff;
                    if (ord >= h->imports_count)
                        dx_fatal("%s: chained bind ordinal out of range", img->path);
                    *loc = targets[ord] ? (uint64_t)targets[ord] + addends[ord] + addend : 0;
                } else {
                    uint64_t target = raw & 0xfffffffffULL;
                    uint64_t high8 = (raw >> 36) & 0xff;
                    if (ss->pointer_format == DYLD_CHAINED_PTR_64)
                        *loc = (target + img->slide) | (high8 << 56);
                    else
                        *loc = ((uintptr_t)img->mh + target) | (high8 << 56);
                }
                if (!next) break;
                loc = (uint64_t *)((uint8_t *)loc + next * 4);
            }
        }
    }
    free(targets);
    free(addends);
}

/* ---- sections: TLV, initializers ------------------------------------- */

typedef void (*section_cb)(struct dx_image *, struct section_64 *, void *);

static void each_section(struct dx_image *img, section_cb cb, void *ctx) {
    struct mach_header_64 *mh = (void *)img->cmds;
    uint8_t *p = img->cmds + sizeof *mh;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        struct load_command *lc = (void *)p;
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *sc = (void *)p;
            struct section_64 *sec = (void *)(sc + 1);
            for (uint32_t j = 0; j < sc->nsects; j++) cb(img, &sec[j], ctx);
        }
        p += lc->cmdsize;
    }
}

/* Find a section by name in the image's data segments (__DATA,
 * __DATA_CONST, __DATA_DIRTY). Returns its mapped address. */
struct section_query {
    const char *name;
    void *addr;
    size_t size;
};
static void section_query_cb(struct dx_image *img, struct section_64 *s, void *ctx) {
    struct section_query *q = ctx;
    /* Objective-C metadata is in __DATA*, Swift metadata (__swift5_*) in
     * __TEXT; the names queried are unique across both. */
    if (q->addr || (strncmp(s->segname, "__DATA", 6) && strncmp(s->segname, "__TEXT", 16)) ||
        strncmp(s->sectname, q->name, 16))
        return;
    q->addr = (void *)(s->addr + img->slide);
    q->size = s->size;
}
void *dx_image_section(const struct dx_image *img, const char *sect, size_t *size) {
    struct section_query q = {sect, NULL, 0};
    each_section((struct dx_image *)img, section_query_cb, &q);
    if (size) *size = q.size;
    return q.addr;
}

/* Objective-C runtime hooks (src/frameworks/objc). */
void dx_objc_image_fixups(const struct dx_image *img) __attribute__((weak));
void dx_objc_images_ready(void) __attribute__((weak));
/* Swift runtime hook (src/frameworks/swift): records the image's
 * __swift5_* sections (types, conformances, protocols, field metadata). */
void dx_swift_image_added(const struct dx_image *img) __attribute__((weak));

static void tlv_scan_cb(struct dx_image *img, struct section_64 *s, void *ctx) {
    (void)ctx;
    uint32_t type = s->flags & SECTION_TYPE;
    if (type == S_THREAD_LOCAL_REGULAR || type == S_THREAD_LOCAL_ZEROFILL) {
        uintptr_t a = s->addr + img->slide;
        if (!img->tlv_size) {
            img->tlv_start = a;
            img->tlv_size = s->size;
        } else {
            uintptr_t lo = a < img->tlv_start ? a : img->tlv_start;
            uintptr_t hi = a + s->size > img->tlv_start + img->tlv_size
                               ? a + s->size
                               : img->tlv_start + img->tlv_size;
            img->tlv_start = lo;
            img->tlv_size = hi - lo;
        }
        img->has_tlv = 1;
    }
}

static void tlv_free(void *p) { free(p); }

static void tlv_desc_cb(struct dx_image *img, struct section_64 *s, void *ctx) {
    (void)ctx;
    if ((s->flags & SECTION_TYPE) != S_THREAD_LOCAL_VARIABLES) return;
    if (!img->tlv_key) img->tlv_key = dx_tsd_key_alloc(tlv_free);
    struct tlv_descriptor *d = (void *)(s->addr + img->slide);
    size_t n = s->size / sizeof *d;
    for (size_t i = 0; i < n; i++) {
        d[i].thunk = dx_tlv_get_addr;
        d[i].key = img->tlv_key;
    }
}

static struct dx_image *image_for_tlv_key(unsigned long key) {
    for (int i = 0; i < nimages; i++)
        if (images[i]->tlv_key == key) return images[i];
    return NULL;
}

static void tlv_init_cb(struct dx_image *img, struct section_64 *s, void *ctx) {
    (void)ctx;
    if ((s->flags & SECTION_TYPE) != S_THREAD_LOCAL_INIT_FUNCTION_POINTERS) return;
    void (**fns)(void) = (void *)(s->addr + img->slide);
    for (size_t i = 0; i < s->size / 8; i++) fns[i]();
}

/* Slow path of the TLV thunk: first access on this thread. */
void *dx_tlv_allocate(struct tlv_descriptor *d) {
    struct dx_image *img = image_for_tlv_key(d->key);
    if (!img) dx_fatal("thread-local access with unknown key %lu", d->key);
    void *block = calloc(1, img->tlv_size ? img->tlv_size : 8);
    if (img->tlv_size) memcpy(block, (void *)img->tlv_start, img->tlv_size);
    dx_thread_self()->tsd[d->key] = block;
    each_section(img, tlv_init_cb, NULL);
    return block;
}

struct program_vars {
    const void *mh;
    int *NXArgcPtr;
    char ***NXArgvPtr;
    char ***environPtr;
    const char **__prognamePtr;
};
extern int d_NXArgc;
extern char **d_NXArgv;
extern const char *d___progname;

static void init_cb(struct dx_image *img, struct section_64 *s, void *ctx) {
    (void)ctx;
    uint32_t type = s->flags & SECTION_TYPE;
    struct program_vars vars = {img->mh, &d_NXArgc, &d_NXArgv, &environ, &d___progname};
    typedef void (*init_fn)(int, char **, char **, const char **, struct program_vars *);
    if (type == S_MOD_INIT_FUNC_POINTERS) {
        init_fn *fns = (void *)(s->addr + img->slide);
        for (size_t i = 0; i < s->size / 8; i++) {
            DX_TRACE("init %s: %p", img->path, (void *)fns[i]);
            fns[i](dx_argc, dx_argv, environ, apple_strings, &vars);
        }
    } else if (type == S_INIT_FUNC_OFFSETS) {
        uint32_t *offs = (void *)(s->addr + img->slide);
        for (size_t i = 0; i < s->size / 4; i++) {
            init_fn fn = (init_fn)((uintptr_t)img->mh + offs[i]);
            DX_TRACE("init %s: %p", img->path, (void *)fn);
            fn(dx_argc, dx_argv, environ, apple_strings, &vars);
        }
    }
}

static void run_init(struct dx_image *img) {
    if (img->inited || img->visiting) return;
    img->visiting = 1;
    for (int i = 0; i < img->ndeps; i++)
        if (img->deps[i].img) run_init(img->deps[i].img);
    img->visiting = 0;
    if (img->inited) return;
    img->inited = 1;
    each_section(img, init_cb, NULL);
}

void dx_run_initializers(void) {
    for (int i = 0; i < nimages; i++) run_init(images[i]);
}

/* ---- path resolution -------------------------------------------------- */

static char *dir_of(const char *path) {
    char *d = strdup(path);
    char *slash = strrchr(d, '/');
    if (slash) *slash = 0;
    else strcpy(d, ".");
    return d;
}

static int try_macho(const char *cand, char *out) {
    char buf[PATH_MAX];
    const char *p = dx_path(cand, buf, sizeof buf);
    if (access(p, R_OK) == 0 && dx_is_macho_file(p)) {
        if (!realpath(p, out)) snprintf(out, PATH_MAX, "%s", p);
        return 1;
    }
    return 0;
}

static int expand(const char *name, const char *prefix, const char *with, char *out) {
    size_t n = strlen(prefix);
    if (strncmp(name, prefix, n)) return 0;
    snprintf(out, PATH_MAX, "%s%s", with, name + n);
    return 1;
}

/* Find the Mach-O file for an install name; 0 if none (shim-provided). */
static int resolve_dylib_path(struct dx_image *from, const char *name, char *out) {
    char cand[PATH_MAX], tmp[PATH_MAX];
    char *ldir = dir_of(from->path);
    char *edir = dir_of(main_image ? main_image->path : from->path);
    int ok = 0;
    if (expand(name, "@loader_path", ldir, cand)) {
        ok = try_macho(cand, out);
    } else if (expand(name, "@executable_path", edir, cand)) {
        ok = try_macho(cand, out);
    } else if (!strncmp(name, "@rpath", 6)) {
        struct dx_image *srcs[2] = {from, main_image};
        for (int k = 0; k < 2 && !ok; k++) {
            struct dx_image *src = srcs[k];
            if (!src || (k == 1 && src == from)) continue;
            char *sdir = dir_of(src->path);
            for (int i = 0; i < src->nrpaths && !ok; i++) {
                const char *rp = src->rpaths[i];
                if (expand(rp, "@loader_path", sdir, tmp) ||
                    expand(rp, "@executable_path", edir, tmp))
                    rp = tmp;
                snprintf(cand, sizeof cand, "%s%s", rp, name + 6);
                ok = try_macho(cand, out);
            }
            free(sdir);
        }
    } else {
        ok = try_macho(name, out);
    }
    free(ldir);
    free(edir);
    return ok;
}

/* ---- mapping ---------------------------------------------------------- */

#define PAGE 4096ULL
#define PAGE_UP(x) (((x) + PAGE - 1) & ~(PAGE - 1))

static struct dx_image *find_loaded(const char *real) {
    for (int i = 0; i < nimages; i++)
        if (!strcmp(images[i]->path, real)) return images[i];
    return NULL;
}

static struct dx_image *map_image(const char *path, int is_main) {
    char real[PATH_MAX];
    if (!realpath(path, real)) snprintf(real, sizeof real, "%s", path);
    struct dx_image *img = find_loaded(real);
    if (img) return img;

    int fd = open(real, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        dx_log(1, "cannot open %s: %s", real, strerror(errno));
        return NULL;
    }
    uint64_t soff = 0, ssize = 0;
    int rc = find_slice(fd, &soff, &ssize);
    if (rc) {
        dx_log(0, "%s: %s", real,
               rc == -2 ? "no x86-64 slice (arm64-only binaries are not supported)"
                        : "not a Mach-O file");
        close(fd);
        return NULL;
    }
    struct mach_header_64 mh;
    if (pread(fd, &mh, sizeof mh, soff) != sizeof mh || mh.magic != MH_MAGIC_64) {
        close(fd);
        return NULL;
    }
    img = calloc(1, sizeof *img);
    img->path = strdup(real);
    img->filetype = mh.filetype;
    img->flags = mh.flags;
    img->cmds = malloc(sizeof mh + mh.sizeofcmds);
    if (pread(fd, img->cmds, sizeof mh + mh.sizeofcmds, soff) != (ssize_t)(sizeof mh + mh.sizeofcmds))
        dx_fatal("%s: truncated load commands", real);

    /* pass 1: parse load commands */
    img->lo = UINT64_MAX;
    uint8_t *p = img->cmds + sizeof mh;
    for (uint32_t i = 0; i < mh.ncmds; i++) {
        struct load_command *lc = (void *)p;
        switch (lc->cmd) {
        case LC_SEGMENT_64: {
            struct segment_command_64 *sc = (void *)p;
            if (img->nsegs >= MAX_SEGS) dx_fatal("%s: too many segments", real);
            struct seg *s = &img->segs[img->nsegs++];
            memcpy(s->name, sc->segname, 16);
            s->vmaddr = sc->vmaddr;
            s->vmsize = sc->vmsize;
            s->fileoff = sc->fileoff;
            s->filesize = sc->filesize;
            s->prot = sc->initprot;
            if (!strcmp(s->name, "__PAGEZERO") || !sc->vmsize) break;
            if (sc->vmaddr < img->lo) img->lo = sc->vmaddr;
            if (sc->vmaddr + sc->vmsize > img->hi) img->hi = sc->vmaddr + sc->vmsize;
            break;
        }
        case LC_LOAD_DYLIB:
        case LC_LOAD_WEAK_DYLIB:
        case LC_REEXPORT_DYLIB:
        case LC_LAZY_LOAD_DYLIB:
        case LC_LOAD_UPWARD_DYLIB: {
            struct dylib_command *dc = (void *)p;
            if (img->ndeps >= MAX_DEPS) dx_fatal("%s: too many dylibs", real);
            struct dep *d = &img->deps[img->ndeps++];
            d->name = strdup((char *)p + dc->name_off);
            d->weak = lc->cmd == LC_LOAD_WEAK_DYLIB;
            d->reexport = lc->cmd == LC_REEXPORT_DYLIB;
            break;
        }
        case LC_ID_DYLIB: {
            struct dylib_command *dc = (void *)p;
            img->install_name = strdup((char *)p + dc->name_off);
            break;
        }
        case LC_RPATH: {
            struct rpath_command *rc2 = (void *)p;
            if (img->nrpaths < MAX_RPATHS)
                img->rpaths[img->nrpaths++] = strdup((char *)p + rc2->path_off);
            break;
        }
        case LC_SYMTAB:
            memcpy(&img->symtab, p, sizeof img->symtab);
            break;
        case LC_DYLD_INFO:
        case LC_DYLD_INFO_ONLY:
            memcpy(&img->dyld_info, p, sizeof img->dyld_info);
            img->has_dyld_info = 1;
            if (img->dyld_info.export_size) {
                img->trie_off = img->dyld_info.export_off;
                img->trie_size = img->dyld_info.export_size;
            }
            break;
        case LC_DYLD_EXPORTS_TRIE: {
            struct linkedit_data_command *ld = (void *)p;
            img->trie_off = ld->dataoff;
            img->trie_size = ld->datasize;
            break;
        }
        case LC_DYLD_CHAINED_FIXUPS: {
            struct linkedit_data_command *ld = (void *)p;
            img->chained_off = ld->dataoff;
            img->chained_size = ld->datasize;
            break;
        }
        case LC_MAIN: {
            struct entry_point_command *ep = (void *)p;
            img->entryoff = ep->entryoff;
            img->has_entry = 1;
            break;
        }
        case LC_UNIXTHREAD: {
            /* flavor, count, then x86_THREAD_STATE64: rip is register 16 */
            uint32_t *w = (uint32_t *)(p + sizeof *lc);
            if (lc->cmdsize >= sizeof *lc + 8 + 21 * 8 && w[0] == 4) {
                memcpy(&img->thread_rip, (uint8_t *)w + 8 + 16 * 8, 8);
                img->has_thread = 1;
            }
            break;
        }
        }
        p += lc->cmdsize;
    }
    if (img->lo == UINT64_MAX) dx_fatal("%s: no mappable segments", real);

    /* pass 2: reserve address space, preferring the linked address for the
     * main executable so addresses match static disassembly */
    size_t span = PAGE_UP(img->hi - img->lo);
    void *base = MAP_FAILED;
    /* Only executables are placed at their linked address (a non-PIE one
     * must be). Libraries always slide, as with dyld: MH_PIE is an
     * executable flag, and a dylib linked at 0 would otherwise land on page
     * zero when the kernel allows it (running as root), making NULL
     * dereferences read the library. */
    if (is_main || (mh.filetype == MH_EXECUTE && !(mh.flags & MH_PIE)))
        base = mmap((void *)img->lo, span, PROT_NONE,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED_NOREPLACE, -1, 0);
    if (base == MAP_FAILED) {
        if (mh.filetype == MH_EXECUTE && !(mh.flags & MH_PIE))
            dx_fatal("%s: cannot map non-PIE executable at 0x%llx", real,
                     (unsigned long long)img->lo);
        /* Mach-O code stays in the low part of the address space so raw
         * syscall instructions inside it can be told apart from host code
         * (see rawsys.c). */
        static uintptr_t low_cursor = 0x200000000UL;
        for (int tries = 0; tries < 4096 && base == MAP_FAILED; tries++) {
            base = mmap((void *)low_cursor, span, PROT_NONE,
                        MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED_NOREPLACE, -1, 0);
            low_cursor += (span + 0xffffffUL) & ~0xffffffUL;
        }
        if (base == MAP_FAILED)
            base = mmap(NULL, span, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    }
    if (base == MAP_FAILED) dx_fatal("%s: cannot reserve %zu bytes", real, span);
    img->slide = (uintptr_t)base - img->lo;

    for (int i = 0; i < img->nsegs; i++) {
        struct seg *s = &img->segs[i];
        if (!strcmp(s->name, "__PAGEZERO") || !s->vmsize) continue;
        uint8_t *addr = (uint8_t *)(s->vmaddr + img->slide);
        if (mprotect(addr, PAGE_UP(s->vmsize), PROT_READ | PROT_WRITE) < 0)
            dx_fatal("%s: mprotect failed: %s", real, strerror(errno));
        if (!s->filesize) continue;
        uint64_t foff = soff + s->fileoff;
        size_t fsz = s->filesize > s->vmsize ? s->vmsize : s->filesize;
        if ((foff & (PAGE - 1)) == 0 && ((uintptr_t)addr & (PAGE - 1)) == 0) {
            void *m = mmap(addr, PAGE_UP(fsz), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_FIXED, fd,
                           foff);
            if (m == MAP_FAILED) dx_fatal("%s: mmap failed: %s", real, strerror(errno));
            /* bytes past the segment's file contents must read as zero */
            if (s->vmsize > fsz && (fsz & (PAGE - 1))) memset(addr + fsz, 0, PAGE_UP(fsz) - fsz);
        } else {
            size_t done = 0;
            while (done < fsz) {
                ssize_t n = pread(fd, addr + done, fsz - done, foff + done);
                if (n <= 0) dx_fatal("%s: short read", real);
                done += n;
            }
        }
    }
    close(fd);

    for (int i = 0; i < img->nsegs; i++) {
        struct seg *s = &img->segs[i];
        if (s->fileoff == 0 && s->filesize) {
            img->mh = (void *)(s->vmaddr + img->slide);
            break;
        }
    }
    if (!img->mh) img->mh = base;

    if (nimages >= MAX_IMAGES) dx_fatal("too many images");
    images[nimages++] = img;
    if (is_main) main_image = img;
    dx_log(1, "mapped %s at %p (slide 0x%lx)", real, base, (unsigned long)img->slide);

    /* pass 3: dependencies */
    for (int i = 0; i < img->ndeps; i++) {
        char dpath[PATH_MAX];
        if (resolve_dylib_path(img, img->deps[i].name, dpath)) {
            img->deps[i].img = map_image(dpath, 0);
            DX_TRACE("  dep %s -> %s", img->deps[i].name, dpath);
        } else {
            DX_TRACE("  dep %s -> built-in shims", img->deps[i].name);
        }
    }
    return img;
}

static void bind_image(struct dx_image *img) {
    if (img->bound) return;
    img->bound = 1;
    if (img->chained_size) {
        do_chained(img);
    } else if (img->has_dyld_info) {
        do_rebase(img, img->dyld_info.rebase_off, img->dyld_info.rebase_size);
        do_bind(img, img->dyld_info.bind_off, img->dyld_info.bind_size, BIND_NORMAL);
        do_bind(img, img->dyld_info.lazy_bind_off, img->dyld_info.lazy_bind_size, BIND_LAZY);
        do_bind(img, img->dyld_info.weak_bind_off, img->dyld_info.weak_bind_size, BIND_WEAK);
    }
    each_section(img, tlv_scan_cb, NULL);
    each_section(img, tlv_desc_cb, NULL);
    if (dx_objc_image_fixups) dx_objc_image_fixups(img);
    if (dx_swift_image_added) dx_swift_image_added(img);
    for (int i = 0; i < img->nsegs; i++) {
        struct seg *s = &img->segs[i];
        if (!strcmp(s->name, "__PAGEZERO") || !s->vmsize) continue;
        int prot = 0;
        if (s->prot & 1) prot |= PROT_READ;
        if (s->prot & 2) prot |= PROT_WRITE;
        if (s->prot & 4) prot |= PROT_EXEC;
        mprotect((void *)(s->vmaddr + img->slide), PAGE_UP(s->vmsize), prot);
    }
}

struct dx_image *dx_load_image(const char *path, int flags) {
    int is_main = flags & 1;
    struct dx_image *img = map_image(path, is_main);
    if (!img) return NULL;
    for (int i = 0; i < nimages; i++) bind_image(images[i]);
    /* +load methods run before any C/C++ initialiser of the new images */
    if (dx_objc_images_ready) dx_objc_images_ready();
    return img;
}

/* ---- introspection ---------------------------------------------------- */

uint32_t dx_image_count(void) { return nimages; }
const char *dx_image_name(uint32_t i) { return i < (uint32_t)nimages ? images[i]->path : NULL; }
const void *dx_image_header(uint32_t i) { return i < (uint32_t)nimages ? images[i]->mh : NULL; }
intptr_t dx_image_slide(uint32_t i) { return i < (uint32_t)nimages ? (intptr_t)images[i]->slide : 0; }

const struct dx_image *dx_image_for_address(const void *addr, const char **name_out,
                                            uintptr_t *base_out) {
    uintptr_t a = (uintptr_t)addr;
    for (int i = 0; i < nimages; i++) {
        struct dx_image *img = images[i];
        if (a >= img->lo + img->slide && a < img->hi + img->slide) {
            if (name_out) *name_out = img->path;
            if (base_out) *base_out = (uintptr_t)img->mh;
            return img;
        }
    }
    return NULL;
}

/* Nearest preceding symbol, for dladdr and crash reports. */
const char *dx_symbol_for_address(const void *addr, uintptr_t *sym_addr) {
    uintptr_t a = (uintptr_t)addr;
    const struct dx_image *cimg = dx_image_for_address(addr, NULL, NULL);
    if (!cimg) return NULL;
    struct dx_image *img = (struct dx_image *)cimg;
    if (!img->symtab.nsyms) return NULL;
    struct nlist_64 *syms = img_off(img, img->symtab.symoff);
    const char *strs = img_off(img, img->symtab.stroff);
    if (!syms || !strs) return NULL;
    const char *best = NULL;
    uintptr_t best_addr = 0;
    for (uint32_t i = 0; i < img->symtab.nsyms; i++) {
        struct nlist_64 *n = &syms[i];
        if ((n->n_type & N_STAB) || (n->n_type & N_TYPE) != N_SECT) continue;
        uintptr_t v = n->n_value + img->slide;
        if (v <= a && v > best_addr && n->n_strx < img->symtab.strsize) {
            best_addr = v;
            best = strs + n->n_strx;
        }
    }
    if (sym_addr) *sym_addr = best_addr;
    return best;
}

/* ---- loader-provided symbols ----------------------------------------- */

static void stub_binder(void) { dx_fatal("dyld_stub_binder called (lazy binding is resolved eagerly)"); }
static void tlv_bootstrap(void) { dx_fatal("__tlv_bootstrap called"); }
static const struct mach_header_64 *mh_execute_header(void) { return main_image ? main_image->mh : NULL; }

static void *loader_symbol(const char *name) {
    if (!strcmp(name, "dyld_stub_binder")) return stub_binder;
    if (!strcmp(name, "__tlv_bootstrap")) return tlv_bootstrap;
    if (!strcmp(name, "__mh_execute_header")) return (void *)mh_execute_header();
    return NULL;
}

/* ---- entry ------------------------------------------------------------ */

int dx_run_main(struct dx_image *img, int argc, char **argv, char **envp) {
    if (!img->has_entry && !img->has_thread) dx_fatal("%s: no entry point", img->path);
    static char exec_path[PATH_MAX + 32];
    snprintf(exec_path, sizeof exec_path, "executable_path=%s", img->path);

    /* Darwin programs (the Go runtime among them) walk past argv and envp
     * to find the "apple" strings, so the three vectors must be contiguous:
     * argv..., NULL, envp..., NULL, apple..., NULL. */
    int envc = 0;
    while (envp && envp[envc]) envc++;
    char **vec = malloc((argc + 1 + envc + 1 + 2) * sizeof(char *));
    int k = 0;
    for (int i = 0; i < argc; i++) vec[k++] = argv[i];
    vec[k++] = NULL;
    char **nenv = &vec[k];
    for (int i = 0; i < envc; i++) vec[k++] = envp[i];
    vec[k++] = NULL;
    char **apple = &vec[k];
    vec[k++] = exec_path;
    vec[k++] = NULL;
    apple_strings[0] = exec_path;
    apple_strings[1] = NULL;
    dx_argv = vec;
    d_NXArgv = vec;
    environ = nenv;

    dx_run_initializers();
    if (!img->has_entry) {
        /* LC_UNIXTHREAD: the program expects the kernel's process-start
         * stack (argc, argv..., NULL, envp..., NULL, apple..., NULL) and is
         * jumped to, not called. Build it on the real stack. */
        int words = 1 + k;
        uintptr_t *stk = __builtin_alloca((words + 2) * sizeof(uintptr_t));
        stk = (uintptr_t *)(((uintptr_t)stk + 15) & ~(uintptr_t)15);
        stk[0] = (uintptr_t)argc;
        memcpy(&stk[1], vec, k * sizeof(char *));
        /* keep environ pointing at the copy the program will see */
        environ = (char **)&stk[1 + argc + 1];
        void *entry_pc = (void *)(img->thread_rip + img->slide);
        dx_log(1, "entering %s at %p (LC_UNIXTHREAD)", img->path, entry_pc);
        dx_jump_entry(entry_pc, stk);
    }
    int (*entry)(int, char **, char **, char **) = (void *)((uintptr_t)img->mh + img->entryoff);
    dx_log(1, "entering %s at %p", img->path, (void *)entry);
    return entry(argc, vec, nenv, apple);
}

struct dx_image *dx_main_image(void) { return main_image; }

/* Report used by `--check`: per-dependency import coverage without running. */
void dx_report_deps(void (*cb)(const char *image, const char *dep, int macho, void *ctx), void *ctx) {
    for (int i = 0; i < nimages; i++)
        for (int j = 0; j < images[i]->ndeps; j++)
            cb(images[i]->path, images[i]->deps[j].name, images[i]->deps[j].img != NULL, ctx);
}
