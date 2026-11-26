/* macOS login(1) as terminal programs use it to start shells:
 * `login -f[l][p] user prog args...` runs prog as the user, a login
 * session (argv[0] "-name", in the home directory) unless -l. */
#include "darwin.h"

struct passwd { char *pw_name, *pw_passwd; unsigned pw_uid, pw_gid; long pw_change; char *pw_class, *pw_gecos, *pw_dir, *pw_shell; long pw_expire; };
struct passwd *getpwuid(unsigned);
unsigned getuid(void);
int fork(void);
int execv(const char *, char *const[]);
int waitpid(int, int *, int);
int pipe(int[2]);
int dup2(int, int);
int close(int);
ssize_t read(int, void *, size_t);
void _exit(int);
char *strstr(const char *, const char *);
int setenv(const char *, const char *, int);

/* Runs login with `flags` and a shell command; returns its output. */
static void run(const char *flags, char *out, size_t len) {
    struct passwd *pw = getpwuid(getuid());
    CHECK(pw != NULL);
    int fds[2];
    CHECK(pipe(fds) == 0);
    int pid = fork();
    if (pid == 0) {
        dup2(fds[1], 1);
        char *const argv[] = {"login", (char *)flags, pw->pw_name, "/bin/sh", "-c",
                              "echo \"$0|$USER|$HOME|$(pwd)|$KEEP\"", NULL};
        execv("/usr/bin/login", argv);
        _exit(127);
    }
    close(fds[1]);
    size_t n = 0;
    ssize_t r;
    while (n + 1 < len && (r = read(fds[0], out + n, len - 1 - n)) > 0) n += (size_t)r;
    out[n] = 0;
    close(fds[0]);
    int status = 0;
    CHECK(waitpid(pid, &status, 0) == pid);
    CHECK(status == 0);
}

int main(void) {
    struct passwd *pw = getpwuid(getuid());
    char expect[512], out[512];
    setenv("KEEP", "kept", 1);

    /* -flp: not a login session, environment kept */
    run("-flp", out, sizeof out);
    snprintf(expect, sizeof expect, "/bin/sh|%s|%s|", pw->pw_name, pw->pw_dir);
    CHECK(strstr(out, expect) == out);
    CHECK(strstr(out, "|kept\n") != NULL);

    /* -f: a login session in the home directory, fresh environment */
    run("-f", out, sizeof out);
    snprintf(expect, sizeof expect, "-sh|%s|%s|%s|\n", pw->pw_name, pw->pw_dir, pw->pw_dir);
    CHECK(strcmp(out, expect) == 0);
    puts("login ok");
    return 0;
}
