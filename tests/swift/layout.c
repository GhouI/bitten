// Metadata layouts emitted by the Swift compiler, read the way the runtime
// reads them (src/frameworks/swift/swift_abi.h).
#include "darwin.h"

struct vwt { void *fn[8]; unsigned long size, stride; unsigned flags, xi; };
struct struct_desc { unsigned flags; int parent, name, access, fields; unsigned nfields, foff; };
struct struct_md { unsigned long kind; const struct struct_desc *desc; unsigned offsets[]; };

extern const struct struct_md $s6layout5PointVN;       /* metadata */
extern const struct struct_desc $s6layout5PointVMn;    /* nominal type descriptor */

static const char *rel(const int *f) { return (const char *)f + *f; }

int main(void) {
    const struct struct_md *m = &$s6layout5PointVN;
    const struct vwt *w = ((const struct vwt *const *)m)[-1];
    CHECK(m->kind == 0x200);
    CHECK(m->desc == &$s6layout5PointVMn);
    CHECK((m->desc->flags & 0x1f) == 17);
    CHECK(!strcmp(rel(&m->desc->name), "Point"));
    CHECK(m->desc->nfields == 3 && m->desc->foff == 2);
    const unsigned *off = (const unsigned *)((const unsigned long *)m + m->desc->foff);
    CHECK(off[0] == 0 && off[1] == 8 && off[2] == 16);
    CHECK(w->size == 24 && w->stride == 24 && (w->flags & 0xff) == 7);
    CHECK(!(w->flags & 0x10000)); /* POD */
    puts("swift layout ok");
    return 0;
}
