/* Mach-O on-disk format definitions, written from the public format
 * documentation. Only what the loader needs. */
#ifndef SCION_MACHO_H
#define SCION_MACHO_H
#include <stdint.h>

#define MH_MAGIC_64 0xfeedfacfu
#define FAT_MAGIC 0xcafebabeu    /* stored big-endian */
#define FAT_MAGIC_64 0xcafebabfu /* stored big-endian */

#define CPU_TYPE_X86_64 0x01000007

#define MH_EXECUTE 2
#define MH_DYLIB 6
#define MH_BUNDLE 8
#define MH_PIE 0x200000u

struct fat_header {
    uint32_t magic, nfat_arch;
};
struct fat_arch {
    uint32_t cputype, cpusubtype, offset, size, align;
};
struct fat_arch_64 {
    uint32_t cputype, cpusubtype;
    uint64_t offset, size;
    uint32_t align, reserved;
};

struct mach_header_64 {
    uint32_t magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved;
};

struct load_command {
    uint32_t cmd, cmdsize;
};

#define LC_REQ_DYLD 0x80000000u
#define LC_SYMTAB 0x2
#define LC_UNIXTHREAD 0x5
#define LC_DYSYMTAB 0xb
#define LC_LOAD_DYLIB 0xc
#define LC_ID_DYLIB 0xd
#define LC_LOAD_WEAK_DYLIB (0x18 | LC_REQ_DYLD)
#define LC_SEGMENT_64 0x19
#define LC_RPATH (0x1c | LC_REQ_DYLD)
#define LC_REEXPORT_DYLIB (0x1f | LC_REQ_DYLD)
#define LC_LAZY_LOAD_DYLIB 0x20
#define LC_DYLD_INFO 0x22
#define LC_DYLD_INFO_ONLY (0x22 | LC_REQ_DYLD)
#define LC_LOAD_UPWARD_DYLIB (0x23 | LC_REQ_DYLD)
#define LC_MAIN (0x28 | LC_REQ_DYLD)
#define LC_BUILD_VERSION 0x32
#define LC_DYLD_EXPORTS_TRIE (0x33 | LC_REQ_DYLD)
#define LC_DYLD_CHAINED_FIXUPS (0x34 | LC_REQ_DYLD)

struct segment_command_64 {
    uint32_t cmd, cmdsize;
    char segname[16];
    uint64_t vmaddr, vmsize, fileoff, filesize;
    uint32_t maxprot, initprot, nsects, flags;
};

struct section_64 {
    char sectname[16];
    char segname[16];
    uint64_t addr, size;
    uint32_t offset, align, reloff, nreloc, flags, reserved1, reserved2, reserved3;
};

#define SECTION_TYPE 0xffu
#define S_ZEROFILL 0x1
#define S_MOD_INIT_FUNC_POINTERS 0x9
#define S_MOD_TERM_FUNC_POINTERS 0xa
#define S_THREAD_LOCAL_REGULAR 0x11
#define S_THREAD_LOCAL_ZEROFILL 0x12
#define S_THREAD_LOCAL_VARIABLES 0x13
#define S_THREAD_LOCAL_VARIABLE_POINTERS 0x14
#define S_THREAD_LOCAL_INIT_FUNCTION_POINTERS 0x15
#define S_INIT_FUNC_OFFSETS 0x16

struct dylib_command {
    uint32_t cmd, cmdsize;
    uint32_t name_off, timestamp, current_version, compatibility_version;
};

struct rpath_command {
    uint32_t cmd, cmdsize, path_off;
};

struct symtab_command {
    uint32_t cmd, cmdsize, symoff, nsyms, stroff, strsize;
};

struct nlist_64 {
    uint32_t n_strx;
    uint8_t n_type, n_sect;
    uint16_t n_desc;
    uint64_t n_value;
};
#define N_STAB 0xe0
#define N_TYPE 0x0e
#define N_EXT 0x01
#define N_SECT 0x0e
#define N_ABS 0x02

struct dyld_info_command {
    uint32_t cmd, cmdsize;
    uint32_t rebase_off, rebase_size;
    uint32_t bind_off, bind_size;
    uint32_t weak_bind_off, weak_bind_size;
    uint32_t lazy_bind_off, lazy_bind_size;
    uint32_t export_off, export_size;
};

struct linkedit_data_command {
    uint32_t cmd, cmdsize, dataoff, datasize;
};

struct entry_point_command {
    uint32_t cmd, cmdsize;
    uint64_t entryoff, stacksize;
};

struct build_version_command {
    uint32_t cmd, cmdsize, platform, minos, sdk, ntools;
};

/* dyld info opcodes */
#define REBASE_OPCODE_MASK 0xF0
#define REBASE_IMMEDIATE_MASK 0x0F
#define REBASE_OPCODE_DONE 0x00
#define REBASE_OPCODE_SET_TYPE_IMM 0x10
#define REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB 0x20
#define REBASE_OPCODE_ADD_ADDR_ULEB 0x30
#define REBASE_OPCODE_ADD_ADDR_IMM_SCALED 0x40
#define REBASE_OPCODE_DO_REBASE_IMM_TIMES 0x50
#define REBASE_OPCODE_DO_REBASE_ULEB_TIMES 0x60
#define REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB 0x70
#define REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB 0x80

#define BIND_OPCODE_MASK 0xF0
#define BIND_IMMEDIATE_MASK 0x0F
#define BIND_OPCODE_DONE 0x00
#define BIND_OPCODE_SET_DYLIB_ORDINAL_IMM 0x10
#define BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB 0x20
#define BIND_OPCODE_SET_DYLIB_SPECIAL_IMM 0x30
#define BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM 0x40
#define BIND_OPCODE_SET_TYPE_IMM 0x50
#define BIND_OPCODE_SET_ADDEND_SLEB 0x60
#define BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB 0x70
#define BIND_OPCODE_ADD_ADDR_ULEB 0x80
#define BIND_OPCODE_DO_BIND 0x90
#define BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB 0xA0
#define BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED 0xB0
#define BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB 0xC0
#define BIND_SYMBOL_FLAGS_WEAK_IMPORT 0x1

#define BIND_SPECIAL_DYLIB_SELF 0
#define BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE (-1)
#define BIND_SPECIAL_DYLIB_FLAT_LOOKUP (-2)
#define BIND_SPECIAL_DYLIB_WEAK_LOOKUP (-3)

/* export trie */
#define EXPORT_SYMBOL_FLAGS_KIND_MASK 0x03
#define EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE 0x02
#define EXPORT_SYMBOL_FLAGS_REEXPORT 0x08
#define EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER 0x10

/* chained fixups */
struct dyld_chained_fixups_header {
    uint32_t fixups_version, starts_offset, imports_offset, symbols_offset;
    uint32_t imports_count, imports_format, symbols_format;
};
struct dyld_chained_starts_in_image {
    uint32_t seg_count;
    uint32_t seg_info_offset[];
};
struct dyld_chained_starts_in_segment {
    uint32_t size;
    uint16_t page_size, pointer_format;
    uint64_t segment_offset;
    uint32_t max_valid_pointer;
    uint16_t page_count;
    uint16_t page_start[];
} __attribute__((packed));
#define DYLD_CHAINED_PTR_START_NONE 0xFFFF
#define DYLD_CHAINED_PTR_64 2
#define DYLD_CHAINED_PTR_64_OFFSET 6
#define DYLD_CHAINED_IMPORT 1
#define DYLD_CHAINED_IMPORT_ADDEND 2
#define DYLD_CHAINED_IMPORT_ADDEND64 3

/* thread-local variable descriptor */
struct tlv_descriptor {
    void *(*thunk)(struct tlv_descriptor *);
    unsigned long key;
    unsigned long offset;
};

#endif
