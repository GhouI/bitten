/* bitten SDK: <sys/un.h>. */
#ifndef BITTEN_SYS_UN_H
#define BITTEN_SYS_UN_H
#include <sys/_types.h>
struct sockaddr_un {
    unsigned char sun_len;
    sa_family_t sun_family;
    char sun_path[104];
};
#define SOL_LOCAL 0
#define LOCAL_PEERCRED 0x001
#define LOCAL_PEERPID 0x002
#define LOCAL_PEEREPID 0x003
#define LOCAL_PEERTOKEN 0x006
#endif
