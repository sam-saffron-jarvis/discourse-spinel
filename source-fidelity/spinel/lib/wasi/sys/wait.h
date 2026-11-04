/* wasm32-wasi: no processes; waitpid answers ECHILD (see signal.h here). */
#ifndef SP_WASI_SYS_WAIT_H
#define SP_WASI_SYS_WAIT_H
#include <sys/types.h>
#define WNOHANG   1
#define WUNTRACED 2
#define WEXITSTATUS(s)  (((s) & 0xff00) >> 8)
#define WTERMSIG(s)     ((s) & 0x7f)
#define WSTOPSIG(s)     WEXITSTATUS(s)
#define WIFEXITED(s)    (!WTERMSIG(s))
#define WIFSTOPPED(s)   ((short)((((s) & 0xffff) * 0x10001) >> 8) > 0x7f00)
#define WIFSIGNALED(s)  (((s) & 0xffff) - 1U < 0xffu)
#define WCOREDUMP(s)    ((s) & 0x80)
pid_t waitpid(pid_t, int *, int);
pid_t wait(int *);
#endif
