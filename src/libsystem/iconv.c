#include <errno.h>
#include <iconv.h>
#include <string.h>
#include <strings.h>

#include "dx.h"

static const char *encoding(const char *name, char mapped[64]) {
    static const struct { const char *darwin, *host; } aliases[] = {
        {"UTF-8-MAC", "UTF-8"}, {"UTF8-MAC", "UTF-8"}, {"UTF-8-HFS", "UTF-8"},
        {"MAC", "MACINTOSH"}, {"MACROMAN", "MACINTOSH"},
        {"MAC-ROMAN", "MACINTOSH"}, {"X-MAC-ROMAN", "MACINTOSH"},
        {"MACCYRILLIC", "MAC-CYRILLIC"}, {"X-MAC-CYRILLIC", "MAC-CYRILLIC"},
        {"MACCENTRALEUROPE", "MAC-CENTRALEUROPE"}, {"MACUKRAINE", "MAC-UK"},
        {"MS_KANJI", "CP932"},
        {"ISO-10646-UCS-2", "UCS-2"}, {"UNICODE-1-1-UTF-8", "UTF-8"},
    };
    size_t len = strcspn(name, "/");
    for (size_t i = 0; i < sizeof aliases / sizeof aliases[0]; i++) {
        if (strlen(aliases[i].darwin) != len || strncasecmp(name, aliases[i].darwin, len))
            continue;
        size_t base = strlen(aliases[i].host), suffix = strlen(name + len);
        if (suffix >= 64 - base) return name;
        memcpy(mapped, aliases[i].host, base);
        memcpy(mapped + base, name + len, suffix + 1);
        return mapped;
    }
    return name;
}

static iconv_t d_iconv_open(const char *to, const char *from) {
    if (!to || !from) {
        dx_set_errno(22);
        return (iconv_t)-1;
    }
    char to_name[64], from_name[64];
    return DX_RET(iconv_open(encoding(to, to_name), encoding(from, from_name)));
}
DX_FN(iconv_open);
DX_EXPORT("_libiconv_open", d_iconv_open);

static size_t d_iconv(iconv_t cd, char **in, size_t *inleft, char **out, size_t *outleft) {
    return DX_RET(iconv(cd, in, inleft, out, outleft));
}
DX_FN(iconv);
DX_EXPORT("_libiconv", d_iconv);

static int d_iconv_close(iconv_t cd) { return DX_RET(iconv_close(cd)); }
DX_FN(iconv_close);
DX_EXPORT("_libiconv_close", d_iconv_close);

static void d_libiconv_set_relocation_prefix(const char *original, const char *current) {
    (void)original;
    (void)current;
}
DX_FN(libiconv_set_relocation_prefix);
static int libiconv_version = 0x010b;
DX_EXPORT("__libiconv_version", &libiconv_version);
