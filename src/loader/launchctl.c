/* launchctl, for programs that manage launchd jobs (`mrun --launchctl`;
 * exec of /bin/launchctl or /usr/bin/launchctl comes here, see
 * src/libsystem/proc.c). There is no launchd: jobs are kept in a small
 * table under $HOME/Library/bitten/launchd, one file per label holding the
 * job's plist path and the pid of its process. Bootstrapping a job starts
 * its program (if RunAtLoad or KeepAlive, as launchd would) detached from
 * the caller, with its plist's arguments, environment, working directory
 * and output paths; booting it out stops it. print, list and kickstart
 * answer from the table. Mach-O programs run under mrun.
 *
 * Supported: bootstrap, bootout, print, kickstart [-k] [-p], list, load,
 * unload, start, stop, remove, enable, disable, version, managerpid,
 * manageruid, managername. */
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "dx.h"

extern char **environ;
int dx_is_macho_file(const char *path);
const char *dx_loader_path(void);

/* ---- a little XML plist reader ---- */

enum { PV_NONE, PV_STRING, PV_BOOL, PV_INT, PV_ARRAY, PV_DICT };
struct pv {
    int type;
    char *s;               /* string, or integer text */
    int b;
    int n;                 /* array / dict entries */
    char **keys;           /* dict */
    struct pv **items;
};

static char *unescape(const char *s, size_t n) {
    char *o = malloc(n + 1);
    size_t k = 0;
    for (size_t i = 0; i < n; i++) {
        if (s[i] == '&') {
            static const struct { const char *e; char c; } ents[] = {
                {"&amp;", '&'}, {"&lt;", '<'}, {"&gt;", '>'}, {"&quot;", '"'}, {"&apos;", '\''}};
            int done = 0;
            for (size_t j = 0; j < sizeof ents / sizeof *ents; j++) {
                size_t l = strlen(ents[j].e);
                if (i + l <= n && !strncmp(s + i, ents[j].e, l)) {
                    o[k++] = ents[j].c;
                    i += l - 1;
                    done = 1;
                    break;
                }
            }
            if (done) continue;
        }
        o[k++] = s[i];
    }
    o[k] = 0;
    return o;
}
/* Skips comments and processing instructions; returns the next '<'. */
static const char *next_tag(const char *p) {
    for (;;) {
        p = strchr(p, '<');
        if (!p) return NULL;
        if (!strncmp(p, "<?", 2) || !strncmp(p, "<!", 2)) {
            const char *e = !strncmp(p, "<!--", 4) ? strstr(p, "-->") : strchr(p, '>');
            if (!e) return NULL;
            p = e + 1;
            continue;
        }
        return p;
    }
}
static struct pv *parse_value(const char **pp);
static char *text_until(const char **pp, const char *close) {
    const char *e = strstr(*pp, close);
    if (!e) return NULL;
    char *t = unescape(*pp, (size_t)(e - *pp));
    *pp = e + strlen(close);
    return t;
}
static struct pv *parse_value(const char **pp) {
    const char *p = next_tag(*pp);
    if (!p) return NULL;
    struct pv *v = calloc(1, sizeof *v);
    if (!strncmp(p, "<string>", 8)) {
        p += 8;
        v->type = PV_STRING;
        v->s = text_until(&p, "</string>");
    } else if (!strncmp(p, "<string/>", 9)) {
        p += 9;
        v->type = PV_STRING;
        v->s = strdup("");
    } else if (!strncmp(p, "<integer>", 9) || !strncmp(p, "<real>", 6)) {
        int real = p[1] == 'r';
        p += real ? 6 : 9;
        v->type = PV_INT;
        v->s = text_until(&p, real ? "</real>" : "</integer>");
    } else if (!strncmp(p, "<true/>", 7) || !strncmp(p, "<false/>", 8)) {
        v->type = PV_BOOL;
        v->b = p[1] == 't';
        p += v->b ? 7 : 8;
    } else if (!strncmp(p, "<array/>", 8)) {
        v->type = PV_ARRAY;
        p += 8;
    } else if (!strncmp(p, "<dict/>", 7)) {
        v->type = PV_DICT;
        p += 7;
    } else if (!strncmp(p, "<array>", 7)) {
        v->type = PV_ARRAY;
        p += 7;
        for (;;) {
            const char *t = next_tag(p);
            if (!t) break;
            if (!strncmp(t, "</array>", 8)) {
                p = t + 8;
                break;
            }
            struct pv *item = parse_value(&p);
            if (!item) break;
            v->items = realloc(v->items, sizeof(*v->items) * (size_t)(v->n + 1));
            v->items[v->n++] = item;
        }
    } else if (!strncmp(p, "<dict>", 6)) {
        v->type = PV_DICT;
        p += 6;
        for (;;) {
            const char *t = next_tag(p);
            if (!t) break;
            if (!strncmp(t, "</dict>", 7)) {
                p = t + 7;
                break;
            }
            if (strncmp(t, "<key>", 5)) break;
            p = t + 5;
            char *key = text_until(&p, "</key>");
            struct pv *item = parse_value(&p);
            if (!key || !item) break;
            v->keys = realloc(v->keys, sizeof(*v->keys) * (size_t)(v->n + 1));
            v->items = realloc(v->items, sizeof(*v->items) * (size_t)(v->n + 1));
            v->keys[v->n] = key;
            v->items[v->n++] = item;
        }
    } else {
        /* unknown element (data, date): skip it */
        const char *e = strchr(p, '>');
        const char *n = e ? strchr(p + 1, '<') : NULL;
        const char *close = n ? strchr(n, '>') : NULL;
        p = close ? close + 1 : p + strlen(p);
        v->type = PV_NONE;
    }
    *pp = p;
    return v;
}
static struct pv *dict_get(struct pv *d, const char *key) {
    if (!d || d->type != PV_DICT) return NULL;
    for (int i = 0; i < d->n; i++)
        if (!strcmp(d->keys[i], key)) return d->items[i];
    return NULL;
}
static const char *dict_str(struct pv *d, const char *key) {
    struct pv *v = dict_get(d, key);
    return v && v->type == PV_STRING ? v->s : NULL;
}
static int dict_true(struct pv *d, const char *key) {
    struct pv *v = dict_get(d, key);
    if (!v) return 0;
    if (v->type == PV_BOOL) return v->b;
    return v->type == PV_DICT; /* KeepAlive as a dictionary of conditions */
}

static struct pv *read_plist(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n <= 0 || n > (4 << 20)) {
        fclose(f);
        return NULL;
    }
    char *b = malloc((size_t)n + 1);
    size_t got = fread(b, 1, (size_t)n, f);
    fclose(f);
    b[got] = 0;
    if (got >= 8 && !memcmp(b, "bplist00", 8)) {
        fprintf(stderr, "launchctl: %s: binary property lists are not supported here\n", path);
        free(b);
        return NULL;
    }
    const char *p = strstr(b, "<plist");
    p = p ? strchr(p, '>') : NULL;
    struct pv *v = p ? parse_value(&(const char *){p + 1}) : NULL;
    free(b);
    return v && v->type == PV_DICT ? v : NULL;
}

/* ---- the job table ---- */

static char table_dir[PATH_MAX - 300];

static void make_dirs(const char *path) {
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s", path);
    for (char *p = tmp + 1; *p; p++)
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    mkdir(tmp, 0755);
}
static void init_table(void) {
    const char *home = getenv("HOME");
    snprintf(table_dir, sizeof table_dir, "%s/Library/bitten/launchd", home && *home ? home : "/tmp");
    make_dirs(table_dir);
}
static void job_file(const char *label, char *out) { snprintf(out, PATH_MAX, "%s/%s.job", table_dir, label); }

struct job {
    char plist[PATH_MAX];
    pid_t pid;
    int last_exit;
};
static int job_read(const char *label, struct job *j) {
    char path[PATH_MAX];
    job_file(label, path);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    memset(j, 0, sizeof *j);
    long pid = 0;
    int ex = 0;
    if (fscanf(f, "%ld %d ", &pid, &ex) < 1) pid = 0;
    if (!fgets(j->plist, sizeof j->plist, f)) j->plist[0] = 0;
    j->plist[strcspn(j->plist, "\n")] = 0;
    fclose(f);
    j->pid = (pid_t)pid;
    j->last_exit = ex;
    return 1;
}
static void job_write(const char *label, const struct job *j) {
    char path[PATH_MAX], tmp[PATH_MAX + 8];
    job_file(label, path);
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "w");
    if (!f) return;
    fprintf(f, "%ld %d\n%s\n", (long)j->pid, j->last_exit, j->plist);
    fclose(f);
    rename(tmp, path);
}
static void job_remove(const char *label) {
    char path[PATH_MAX];
    job_file(label, path);
    unlink(path);
    snprintf(path, sizeof path, "%s/%s.plist", table_dir, label);
    unlink(path);
}
static int alive(pid_t pid) {
    if (pid <= 0) return 0;
    if (kill(pid, 0) != 0) return errno == EPERM;
    /* a zombie of ours is not alive */
    char stat[64], buf[256];
    snprintf(stat, sizeof stat, "/proc/%ld/stat", (long)pid);
    FILE *f = fopen(stat, "r");
    if (!f) return 1;
    int z = 0;
    if (fgets(buf, sizeof buf, f)) {
        char *rp = strrchr(buf, ')');
        z = rp && rp[1] == ' ' && rp[2] == 'Z';
    }
    fclose(f);
    return !z;
}

/* ---- running a job ---- */

static pid_t start_job(struct pv *d) {
    struct pv *args = dict_get(d, "ProgramArguments");
    const char *program = dict_str(d, "Program");
    int argc = args && args->type == PV_ARRAY ? args->n : 0;
    if (!program && argc == 0) return -1;
    char **argv = calloc((size_t)argc + 2, sizeof(char *));
    for (int i = 0; i < argc; i++) argv[i] = args->items[i]->type == PV_STRING ? args->items[i]->s : (char *)"";
    if (!argc) argv[argc++] = (char *)program;
    const char *path = program ? program : argv[0];

    pid_t pid = fork();
    if (pid != 0) return pid;
    /* the job: its own session, files from the plist */
    setsid();
    const char *wd = dict_str(d, "WorkingDirectory");
    if (wd) {
        if (chdir(wd) < 0) {
        }
    } else if (chdir("/") < 0) {
    }
    int in = open(dict_str(d, "StandardInPath") ?: "/dev/null", O_RDONLY);
    if (in >= 0 && in != 0) {
        dup2(in, 0);
        close(in);
    }
    const char *outs[2] = {dict_str(d, "StandardOutPath"), dict_str(d, "StandardErrorPath")};
    for (int k = 0; k < 2; k++) {
        int fd = open(outs[k] ?: "/dev/null", O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0 && fd != k + 1) {
            dup2(fd, k + 1);
            close(fd);
        }
    }
    for (int fd = 3; fd < 1024; fd++) close(fd);
    struct pv *env = dict_get(d, "EnvironmentVariables");
    for (int i = 0; env && env->type == PV_DICT && i < env->n; i++)
        if (env->items[i]->type == PV_STRING) setenv(env->keys[i], env->items[i]->s, 1);
    const char *label = dict_str(d, "Label");
    if (label) setenv("XPC_SERVICE_NAME", label, 1);
    signal(SIGHUP, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    if (dx_is_macho_file(path)) {
        char **nargv = calloc((size_t)argc + 6, sizeof(char *));
        int k = 0;
        nargv[k++] = (char *)dx_loader_path();
        nargv[k++] = (char *)"--argv0";
        nargv[k++] = argv[0];
        nargv[k++] = (char *)"--";
        nargv[k++] = (char *)path;
        for (int i = 1; i < argc; i++) nargv[k++] = argv[i];
        execve(dx_loader_path(), nargv, environ);
    } else {
        execve(path, argv, environ);
    }
    _exit(127);
}

static int stop_job(const char *label, int sig) {
    struct job j;
    if (!job_read(label, &j)) return 3;
    if (alive(j.pid)) {
        kill(j.pid, sig);
        /* give it a moment, then insist */
        for (int i = 0; i < 50 && alive(j.pid); i++) {
            struct timespec ts = {0, 20 * 1000 * 1000};
            nanosleep(&ts, NULL);
            waitpid(j.pid, NULL, WNOHANG);
        }
        if (alive(j.pid)) kill(j.pid, SIGKILL);
    }
    j.pid = 0;
    job_write(label, &j);
    return 0;
}

/* ---- targets ---- */

/* "gui/501/com.example.job" -> "com.example.job"; "gui/501" -> NULL */
static const char *label_of(const char *target) {
    const char *s = strchr(target, '/');
    if (!s) return target;
    if (!strncmp(target, "system/", 7) || !strncmp(target, "pid/", 4)) {
        const char *l = !strncmp(target, "system/", 7) ? s + 1 : strchr(s + 1, '/');
        return l && *l ? (l[0] == '/' ? l + 1 : l) : NULL;
    }
    const char *t = strchr(s + 1, '/');
    return t && t[1] ? t + 1 : NULL;
}

static int bootstrap_plist(const char *plist) {
    char real[PATH_MAX];
    if (!realpath(plist, real)) snprintf(real, sizeof real, "%s", plist);
    struct pv *d = read_plist(real);
    const char *label = dict_str(d, "Label");
    if (!d || !label) {
        fprintf(stderr, "Bootstrap failed: 5: Input/output error\n");
        return 5;
    }
    struct job j;
    if (job_read(label, &j) && alive(j.pid)) {
        fprintf(stderr, "Bootstrap failed: 5: Input/output error\n");
        return 5;
    }
    memset(&j, 0, sizeof j);
    /* launchd keeps the job's definition; the file may go away */
    snprintf(j.plist, sizeof j.plist, "%s/%s.plist", table_dir, label);
    FILE *in = fopen(real, "rb"), *out = fopen(j.plist, "wb");
    if (in && out) {
        char buf[8192];
        size_t n;
        while ((n = fread(buf, 1, sizeof buf, in)) > 0) fwrite(buf, 1, n, out);
    }
    if (in) fclose(in);
    if (out) fclose(out);
    if (dict_true(d, "RunAtLoad") || dict_true(d, "KeepAlive")) j.pid = start_job(d);
    if (j.pid < 0) j.pid = 0;
    job_write(label, &j);
    return 0;
}

static int print_job(const char *target) {
    const char *label = label_of(target);
    struct job j;
    if (!label) {
        printf("%s = {\n\ttype = launchd domain\n}\n", target);
        return 0;
    }
    if (!job_read(label, &j)) {
        fprintf(stderr, "Could not find service \"%s\" in domain for port\n", label);
        return 113;
    }
    struct pv *d = read_plist(j.plist);
    int running = alive(j.pid);
    printf("%s = {\n", target);
    printf("\tactive count = %d\n", running);
    printf("\tpath = %s\n", j.plist);
    printf("\ttype = LaunchAgent\n");
    printf("\tstate = %s\n\n", running ? "running" : "not running");
    struct pv *args = dict_get(d, "ProgramArguments");
    const char *program = dict_str(d, "Program");
    if (program || (args && args->n)) printf("\tprogram = %s\n", program ? program : args->items[0]->s);
    if (args && args->n) {
        printf("\targuments = {\n");
        for (int i = 0; i < args->n; i++) printf("\t\t%s\n", args->items[i]->type == PV_STRING ? args->items[i]->s : "");
        printf("\t}\n\n");
    }
    if (running) printf("\tpid = %ld\n", (long)j.pid);
    printf("\tlast exit code = %d\n", j.last_exit);
    printf("}\n");
    return 0;
}

static int list_jobs(const char *only) {
    if (only) {
        struct job j;
        if (!job_read(only, &j)) {
            fprintf(stderr, "Could not find service \"%s\" in domain for port\n", only);
            return 113;
        }
        printf("{\n\t\"Label\" = \"%s\";\n", only);
        if (alive(j.pid)) printf("\t\"PID\" = %ld;\n", (long)j.pid);
        printf("\t\"LastExitStatus\" = %d;\n};\n", j.last_exit);
        return 0;
    }
    printf("PID\tStatus\tLabel\n");
    DIR *dir = opendir(table_dir);
    if (!dir) return 0;
    struct dirent *e;
    while ((e = readdir(dir))) {
        size_t n = strlen(e->d_name);
        if (n < 5 || strcmp(e->d_name + n - 4, ".job")) continue;
        char label[256];
        snprintf(label, sizeof label, "%.*s", (int)(n - 4), e->d_name);
        struct job j;
        if (!job_read(label, &j)) continue;
        if (alive(j.pid)) printf("%ld\t%d\t%s\n", (long)j.pid, j.last_exit, label);
        else printf("-\t%d\t%s\n", j.last_exit, label);
    }
    closedir(dir);
    return 0;
}

static void usage(void) {
    fprintf(stderr, "usage: launchctl <subcommand> ... (bootstrap, bootout, print, kickstart, list, load, unload,"
                    " start, stop, remove, enable, disable, version)\n");
}

int dx_launchctl_main(int argc, char **argv) {
    init_table();
    if (argc < 1) {
        usage();
        return 64;
    }
    const char *cmd = argv[0];
    if (!strcmp(cmd, "bootstrap")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: launchctl bootstrap <domain-target> [service-path ...]\n");
            return 64;
        }
        int rc = 0;
        for (int i = 2; i < argc; i++) rc = bootstrap_plist(argv[i]) ?: rc;
        return rc;
    }
    if (!strcmp(cmd, "bootout")) {
        if (argc < 2) return 64;
        if (argc >= 3) {
            int rc = 0;
            for (int i = 2; i < argc; i++) {
                struct pv *d = read_plist(argv[i]);
                const char *label = dict_str(d, "Label");
                if (!label || stop_job(label, SIGTERM)) {
                    fprintf(stderr, "Boot-out failed: 3: No such process\n");
                    rc = 3;
                } else {
                    job_remove(label);
                }
            }
            return rc;
        }
        const char *label = label_of(argv[1]);
        if (!label || stop_job(label, SIGTERM)) {
            fprintf(stderr, "Boot-out failed: 3: No such process\n");
            return 3;
        }
        job_remove(label);
        return 0;
    }
    if (!strcmp(cmd, "print")) return argc < 2 ? 64 : print_job(argv[1]);
    if (!strcmp(cmd, "kickstart")) {
        int kill_first = 0, print_pid = 0, i = 1;
        for (; i < argc && argv[i][0] == '-'; i++) {
            if (strchr(argv[i], 'k')) kill_first = 1;
            if (strchr(argv[i], 'p')) print_pid = 1;
        }
        if (i >= argc) return 64;
        const char *label = label_of(argv[i]);
        struct job j;
        if (!label || !job_read(label, &j)) {
            fprintf(stderr, "Could not find service \"%s\" in domain for port\n", label ? label : argv[i]);
            return 113;
        }
        if (alive(j.pid) && !kill_first) {
            if (print_pid) printf("%ld\n", (long)j.pid);
            return 0;
        }
        if (alive(j.pid)) stop_job(label, SIGTERM);
        struct pv *d = read_plist(j.plist);
        if (!d) return 5;
        j.pid = start_job(d);
        if (j.pid < 0) j.pid = 0;
        job_write(label, &j);
        if (print_pid) printf("%ld\n", (long)j.pid);
        return 0;
    }
    if (!strcmp(cmd, "list")) return list_jobs(argc > 1 ? argv[1] : NULL);
    if (!strcmp(cmd, "load")) {
        int rc = 0;
        for (int i = 1; i < argc; i++)
            if (argv[i][0] != '-') rc = bootstrap_plist(argv[i]) ?: rc;
        return rc;
    }
    if (!strcmp(cmd, "unload")) {
        for (int i = 1; i < argc; i++) {
            if (argv[i][0] == '-') continue;
            struct pv *d = read_plist(argv[i]);
            const char *label = dict_str(d, "Label");
            if (label) {
                stop_job(label, SIGTERM);
                job_remove(label);
            }
        }
        return 0;
    }
    if (!strcmp(cmd, "start") || !strcmp(cmd, "stop") || !strcmp(cmd, "remove")) {
        if (argc < 2) return 64;
        if (!strcmp(cmd, "start")) {
            char *k[] = {(char *)"kickstart", argv[1], NULL};
            return dx_launchctl_main(2, k);
        }
        int rc = stop_job(argv[1], SIGTERM);
        if (!strcmp(cmd, "remove") && !rc) job_remove(argv[1]);
        return rc;
    }
    if (!strcmp(cmd, "enable") || !strcmp(cmd, "disable") || !strcmp(cmd, "setenv") || !strcmp(cmd, "unsetenv") ||
        !strcmp(cmd, "config"))
        return 0;
    if (!strcmp(cmd, "getenv")) {
        const char *v = argc > 1 ? getenv(argv[1]) : NULL;
        if (v) printf("%s\n", v);
        return 0;
    }
    if (!strcmp(cmd, "version")) {
        printf("Darwin Bootstrapper Version 7.0.0: bitten\n");
        return 0;
    }
    if (!strcmp(cmd, "managerpid")) {
        printf("1\n");
        return 0;
    }
    if (!strcmp(cmd, "manageruid")) {
        printf("%d\n", (int)getuid());
        return 0;
    }
    if (!strcmp(cmd, "managername")) {
        printf("Aqua\n");
        return 0;
    }
    usage();
    return 64;
}
