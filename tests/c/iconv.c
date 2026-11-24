#include "darwin.h"

typedef void *iconv_t;
iconv_t iconv_open(const char *, const char *);
size_t iconv(iconv_t, char **, size_t *, char **, size_t *);
int iconv_close(iconv_t);
iconv_t libiconv_open(const char *, const char *);
size_t libiconv(iconv_t, char **, size_t *, char **, size_t *);
int libiconv_close(iconv_t);
void libiconv_set_relocation_prefix(const char *, const char *);
extern int _libiconv_version;

static void convert(iconv_t cd, char *src, size_t size, const char *expected, size_t n) {
    char buf[32], *out = buf;
    size_t left = sizeof buf;
    CHECK(cd != (iconv_t)-1);
    CHECK(libiconv(cd, &src, &size, &out, &left) == 0);
    CHECK(size == 0 && left == sizeof buf - n && out == buf + n);
    CHECK(memcmp(buf, expected, n) == 0);
    CHECK(libiconv_close(cd) == 0);
}

int main(void) {
    char utf8[] = "caf\xc3\xa9 \xf0\x9f\x8c\x8d";
    char utf16[] = "c\0a\0f\0\xe9\0 \0\x3c\xd8\x0d\xdf";
    char latin[] = "caf\xe9", mac[] = "caf\x8e";
    convert(iconv_open("UTF-16LE", "UTF-8"), utf8, sizeof utf8 - 1, utf16, sizeof utf16 - 1);
    convert(libiconv_open("UTF-8", "UTF-16LE"), utf16, sizeof utf16 - 1, utf8, sizeof utf8 - 1);
    convert(libiconv_open("Latin1", "UTF-8"), utf8, 5, latin, sizeof latin - 1);
    convert(iconv_open("UTF-8-MAC", "ISO-8859-1"), latin, sizeof latin - 1, utf8, 5);
    convert(iconv_open("MACROMAN", "UTF-8"), utf8, 5, mac, sizeof mac - 1);
    convert(iconv_open("UTF-8", "MAC"), mac, sizeof mac - 1, utf8, 5);

    char buf[8], *out = buf, *in = utf8;
    size_t size = 1, cap = 1;
    iconv_t cd = iconv_open("UTF-16LE", "UTF-8");
    CHECK(cd != (iconv_t)-1);
    CHECK(iconv(cd, &in, &size, &out, &cap) == (size_t)-1 && errno == 7);
    CHECK(in == utf8 && size == 1 && cap == 1);
    char bad[] = {(char)0xff}, short_utf8[] = {(char)0xc3};
    in = bad;
    cap = sizeof buf;
    CHECK(iconv(cd, &in, &size, &out, &cap) == (size_t)-1 && errno == 92);
    in = short_utf8;
    CHECK(iconv(cd, &in, &size, &out, &cap) == (size_t)-1 && errno == 22);
    CHECK(iconv(cd, NULL, NULL, &out, &cap) == 0);
    CHECK(iconv_close(cd) == 0);
    CHECK(iconv_open("unknown", "UTF-8") == (iconv_t)-1 && errno == 22);
    CHECK(_libiconv_version == 0x010b);
    libiconv_set_relocation_prefix("/unused", "/unused");
    puts("iconv ok");
    return 0;
}
