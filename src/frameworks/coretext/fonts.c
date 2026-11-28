/* The fonts CoreText can use: the TrueType files under BITTEN_FONT_PATH (a
 * colon-separated list of directories), or under /usr/share/fonts,
 * /usr/local/share/fonts and ~/.fonts, plus files programs register with
 * CTFontManager. No Apple font ships with bitten; Apple's names map to
 * open families (DejaVu, Noto, Liberation, FreeFont...):
 *   the system font (.AppleSystemUIFont, .SFNS, SF Pro), Helvetica, Arial,
 *     Lucida Grande  -> a sans-serif family (Liberation Sans first)
 *   Menlo, Monaco, SF Mono, Courier             -> a monospaced family
 *   Times, New York, Georgia                    -> a serif family
 * A weight or slant in the name (Bold, Semibold, Light, Italic...) picks
 * the closest face of the family. */
#include <ctype.h>
#include <dirent.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

#include "ct.h"

static struct ttf **faces;
static int nfaces, cap;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t scanned = PTHREAD_ONCE_INIT;

static void add_face(struct ttf *f) {
    if (nfaces == cap) {
        int n = cap ? cap * 2 : 64;
        struct ttf **p = realloc(faces, (size_t)n * sizeof *p);
        if (!p) { ttf_close(f); return; }
        faces = p;
        cap = n;
    }
    faces[nfaces++] = f;
}

static bool font_file(const char *name) {
    const char *dot = strrchr(name, '.');
    return dot && (!strcasecmp(dot, ".ttf") || !strcasecmp(dot, ".ttc") || !strcasecmp(dot, ".otf"));
}

static int add_file(const char *path) {
    int added = 0;
    for (int i = 0; i < 32; i++) {               /* every face of a collection */
        struct ttf *f = ttf_open(path, i);
        if (!f) break;
        add_face(f);
        added++;
    }
    return added;
}

static void scan_dir(const char *dir, int depth) {
    if (depth > 6) return;
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char path[1024];
        snprintf(path, sizeof path, "%s/%s", dir, e->d_name);
        struct stat st;
        if (stat(path, &st)) continue;
        if (S_ISDIR(st.st_mode)) scan_dir(path, depth + 1);
        else if (font_file(e->d_name)) add_file(path);
    }
    closedir(d);
}

static void scan(void) {
    const char *env = getenv("BITTEN_FONT_PATH");
    if (env && *env) {
        char *copy = strdup(env), *save = NULL;
        for (char *dir = strtok_r(copy, ":", &save); dir; dir = strtok_r(NULL, ":", &save)) scan_dir(dir, 0);
        free(copy);
    } else {
        scan_dir("/usr/share/fonts", 0);
        scan_dir("/usr/local/share/fonts", 0);
        const char *home = getenv("HOME");
        if (home) {
            char p[1024];
            snprintf(p, sizeof p, "%s/.fonts", home);
            scan_dir(p, 0);
        }
    }
    if (!nfaces) dx_log(0, "coretext: no TrueType fonts found (install fonts-dejavu-core, or set BITTEN_FONT_PATH)");
}

int ct_face_count(void) {
    pthread_once(&scanned, scan);
    return nfaces;
}

struct ttf *ct_face_at(int i) {
    pthread_once(&scanned, scan);
    pthread_mutex_lock(&lock);
    struct ttf *f = i >= 0 && i < nfaces ? faces[i] : NULL;
    pthread_mutex_unlock(&lock);
    return f;
}

struct ttf *ct_register_file(const char *path) {
    pthread_once(&scanned, scan);
    pthread_mutex_lock(&lock);
    struct ttf *found = NULL;
    for (int i = 0; i < nfaces && !found; i++)
        if (faces[i]->path && !strcmp(faces[i]->path, path)) found = faces[i];
    if (!found) {
        int before = nfaces;
        if (add_file(path)) found = faces[before];
    }
    pthread_mutex_unlock(&lock);
    return found;
}

/* ---- matching ------------------------------------------------------------------ */

static bool starts(const char *s, const char *prefix) { return !strncasecmp(s, prefix, strlen(prefix)); }

static bool contains(const char *s, const char *word) {
    size_t n = strlen(word);
    for (; *s; s++) if (!strncasecmp(s, word, n)) return true;
    return false;
}

/* Sans-serif stands in for the system font (San Francisco), Helvetica,
 * Arial and Lucida Grande: Arial/Helvetica-metric families first, as their
 * widths are close to San Francisco's (DejaVu Sans runs 10-15% wider, and
 * tight macOS layouts overflow); missing glyphs still fall back. */
static const char *const SANS[] = {"Liberation Sans", "Arimo", "Nimbus Sans", "Noto Sans", "DejaVu Sans", "FreeSans", NULL};
static const char *const MONO[] = {"DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono", "FreeMono", NULL};
static const char *const SERIF[] = {"DejaVu Serif", "Noto Serif", "Liberation Serif", "FreeSerif", NULL};

/* Weight and slant spelled in a name. */
static void style_of(const char *name, int *weight, bool *italic) {
    *weight = 400;
    if (contains(name, "Thin") || contains(name, "Hairline")) *weight = 100;
    else if (contains(name, "UltraLight") || contains(name, "ExtraLight")) *weight = 200;
    else if (contains(name, "Light")) *weight = 300;
    else if (contains(name, "Medium")) *weight = 500;
    else if (contains(name, "Semibold") || contains(name, "DemiBold") || contains(name, "Demi")) *weight = 600;
    else if (contains(name, "ExtraBold") || contains(name, "UltraBold") || contains(name, "Heavy")) *weight = 800;
    else if (contains(name, "Black")) *weight = 900;
    else if (contains(name, "Bold")) *weight = 700;
    *italic = contains(name, "Italic") || contains(name, "Oblique");
}

/* The closest face of a family: right slant first, then nearest weight;
 * conventional faces win ties (no Condensed, Narrow, ExtraLight...). */
static struct ttf *best_in_family(const char *family, int weight, bool italic) {
    struct ttf *best = NULL;
    int best_score = 1 << 30;
    for (int i = 0; i < nfaces; i++) {
        struct ttf *f = faces[i];
        if (strcasecmp(f->family, family)) continue;
        int score = abs(f->weight - weight) + (f->italic != italic ? 10000 : 0);
        if (contains(f->style, "Condensed") || contains(f->style, "Narrow") || contains(f->full, "Condensed")) score += 5000;
        if (score < best_score) { best_score = score; best = f; }
    }
    return best;
}

static struct ttf *from_list(const char *const *list, int weight, bool italic) {
    for (int i = 0; list[i]; i++) {
        struct ttf *f = best_in_family(list[i], weight, italic);
        if (f) return f;
    }
    return NULL;
}

struct ttf *ct_face_for_name(const char *name) {
    pthread_once(&scanned, scan);
    if (!nfaces) return NULL;
    if (!name || !*name) name = ".AppleSystemUIFont";
    int weight;
    bool italic;
    style_of(name, &weight, &italic);
    pthread_mutex_lock(&lock);
    struct ttf *f = NULL;
    /* Exact PostScript or full name, then family name. */
    for (int i = 0; i < nfaces && !f; i++)
        if (!strcasecmp(faces[i]->postscript, name) || !strcasecmp(faces[i]->full, name)) f = faces[i];
    if (!f) f = best_in_family(name, weight, italic);
    if (!f) {
        if (contains(name, "Mono") || starts(name, "Menlo") || starts(name, "Monaco") || starts(name, "Courier") ||
            starts(name, "SF Mono") || starts(name, "SFMono"))
            f = from_list(MONO, weight, italic);
        else if (starts(name, "Times") || starts(name, "New York") || starts(name, "Georgia") ||
                 starts(name, "Palatino") || starts(name, "Baskerville") || contains(name, "Serif"))
            f = from_list(SERIF, weight, italic);
        else
            f = from_list(SANS, weight, italic);
    }
    /* Strip a style suffix and try the family (Foo-Bold -> Foo). */
    if (!f) {
        char base[128];
        snprintf(base, sizeof base, "%s", name);
        char *dash = strchr(base, '-');
        if (dash) { *dash = 0; f = best_in_family(base, weight, italic); }
    }
    if (!f) f = faces[0];
    pthread_mutex_unlock(&lock);
    return f;
}

struct ttf *ct_face_variant(const struct ttf *of, int weight, bool italic) {
    pthread_once(&scanned, scan);
    pthread_mutex_lock(&lock);
    struct ttf *f = best_in_family(of->family, weight, italic);
    pthread_mutex_unlock(&lock);
    return f ? f : (struct ttf *)of;
}

struct ttf *ct_face_covering(const struct ttf *of, uint32_t c) {
    if (ttf_glyph(of, c)) return (struct ttf *)of;
    pthread_once(&scanned, scan);
    static const char *const fallbacks[] = {"DejaVu Sans", "Noto Sans", "FreeSans", "FreeSerif",
                                            "Noto Sans Symbols", "Noto Sans Symbols2", "Droid Sans Fallback", NULL};
    for (int i = 0; fallbacks[i]; i++) {
        struct ttf *f = best_in_family(fallbacks[i], of->weight, of->italic);
        if (f && ttf_glyph(f, c)) return f;
    }
    for (int i = 0; i < nfaces; i++)
        if (ttf_glyph(faces[i], c)) return faces[i];
    return (struct ttf *)of;
}
