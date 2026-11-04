/* wasm32-wasi: no resource limits; getrlimit answers ENOSYS (see
   ../signal.h here). */
#ifndef SP_WASI_SYS_RESOURCE_H
#define SP_WASI_SYS_RESOURCE_H
#include_next <sys/resource.h>
#ifndef RLIM_INFINITY
typedef unsigned long long rlim_t;
struct rlimit { rlim_t rlim_cur, rlim_max; };
#define RLIM_INFINITY (~0ULL)
#define RLIMIT_CPU     0
#define RLIMIT_FSIZE   1
#define RLIMIT_DATA    2
#define RLIMIT_STACK   3
#define RLIMIT_CORE    4
#define RLIMIT_NOFILE  7
#define RLIMIT_AS      9
int getrlimit(int, struct rlimit *);
int setrlimit(int, const struct rlimit *);
#endif
#ifndef PRIO_PROCESS
#define PRIO_PROCESS 0
#define PRIO_PGRP    1
#define PRIO_USER    2
int getpriority(int, id_t);
int setpriority(int, id_t, int);
#endif
#endif
