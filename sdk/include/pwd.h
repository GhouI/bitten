#ifndef BITTEN_PWD_H
#define BITTEN_PWD_H
#include <stdint.h>
struct passwd {
    char *pw_name, *pw_passwd;
    uint32_t pw_uid, pw_gid;
    long pw_change;
    char *pw_class, *pw_gecos, *pw_dir, *pw_shell;
    long pw_expire;
};
struct passwd *getpwuid(uint32_t);
struct passwd *getpwnam(const char *);
#endif
