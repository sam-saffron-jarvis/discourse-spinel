/* wasm32-wasi (preview 1): no name resolution; getaddrinfo answers EAI_FAIL
   (see signal.h here). */
#ifndef SP_WASI_NETDB_H
#define SP_WASI_NETDB_H
#include <sys/socket.h>
struct addrinfo {
  int ai_flags, ai_family, ai_socktype, ai_protocol;
  socklen_t ai_addrlen;
  struct sockaddr *ai_addr;
  char *ai_canonname;
  struct addrinfo *ai_next;
};
#define AI_PASSIVE     0x01
#define AI_CANONNAME   0x02
#define AI_NUMERICHOST 0x04
#define AI_NUMERICSERV 0x400
#define EAI_FAIL     (-4)
#define EAI_NONAME   (-2)
#define EAI_SYSTEM   (-11)
#define NI_MAXHOST 255
#define NI_MAXSERV 32
#define NI_NUMERICHOST 1
#define NI_NUMERICSERV 2
int getaddrinfo(const char *, const char *, const struct addrinfo *, struct addrinfo **);
void freeaddrinfo(struct addrinfo *);
const char *gai_strerror(int);
int getnameinfo(const struct sockaddr *, socklen_t, char *, socklen_t, char *, socklen_t, int);
struct hostent { char *h_name; char **h_aliases; int h_addrtype; int h_length; char **h_addr_list; };
#endif
