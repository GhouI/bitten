/* bitten SDK: <netdb.h>. */
#ifndef BITTEN_NETDB_H
#define BITTEN_NETDB_H
#include <sys/_types.h>
#include <sys/socket.h>

struct addrinfo {
    int ai_flags;
    int ai_family;
    int ai_socktype;
    int ai_protocol;
    socklen_t ai_addrlen;
    char *ai_canonname;
    struct sockaddr *ai_addr;
    struct addrinfo *ai_next;
};
struct hostent {
    char *h_name;
    char **h_aliases;
    int h_addrtype;
    int h_length;
    char **h_addr_list;
};
struct servent {
    char *s_name;
    char **s_aliases;
    int s_port;
    char *s_proto;
};
struct protoent {
    char *p_name;
    char **p_aliases;
    int p_proto;
};

#define AI_PASSIVE 0x00000001
#define AI_CANONNAME 0x00000002
#define AI_NUMERICHOST 0x00000004
#define AI_ALL 0x00000100
#define AI_V4MAPPED_CFG 0x00000200
#define AI_ADDRCONFIG 0x00000400
#define AI_V4MAPPED 0x00000800
#define AI_NUMERICSERV 0x00001000
#define AI_DEFAULT (AI_V4MAPPED_CFG | AI_ADDRCONFIG)
#define EAI_ADDRFAMILY 1
#define EAI_AGAIN 2
#define EAI_BADFLAGS 3
#define EAI_FAIL 4
#define EAI_FAMILY 5
#define EAI_MEMORY 6
#define EAI_NODATA 7
#define EAI_NONAME 8
#define EAI_SERVICE 9
#define EAI_SOCKTYPE 10
#define EAI_SYSTEM 11
#define NI_NOFQDN 0x00000001
#define NI_NUMERICHOST 0x00000002
#define NI_NAMEREQD 0x00000004
#define NI_NUMERICSERV 0x00000008
#define NI_DGRAM 0x00000010
#define NI_MAXHOST 1025
#define NI_MAXSERV 32

__BEGIN_DECLS
extern int h_errno;
int getaddrinfo(const char *restrict, const char *restrict, const struct addrinfo *restrict,
                struct addrinfo **restrict);
void freeaddrinfo(struct addrinfo *);
const char *gai_strerror(int);
int getnameinfo(const struct sockaddr *restrict, socklen_t, char *restrict, socklen_t, char *restrict,
                socklen_t, int);
struct hostent *gethostbyname(const char *);
struct servent *getservbyname(const char *, const char *);
struct servent *getservbyport(int, const char *);
struct protoent *getprotobyname(const char *);
__END_DECLS
#endif
