/* wasm32-wasi: no processes; fork/exec answer ENOSYS (see signal.h here). */
#ifndef SP_WASI_UNISTD_H
#define SP_WASI_UNISTD_H
#include_next <unistd.h>
pid_t fork(void);
int execvp(const char *, char *const []);
int execv(const char *, char *const []);
int execl(const char *, const char *, ...);
int setpgid(pid_t, pid_t);
int fchdir(int);
uid_t getuid(void);
gid_t getgid(void);
uid_t geteuid(void);
gid_t getegid(void);
pid_t getppid(void);
int getgroups(int, gid_t *);
#endif
