/* wasm32-wasi: the POSIX surface wasi-libc leaves out, declared so lib/*.c
   compiles unchanged. The definitions are in sp_wasi.c and answer ENOSYS:
   WASI has no signals, no processes, no name resolution, no user database
   and no stack switching, and a program that reaches for them gets the
   errno, not a link error. This directory is on the include path only for
   a wasi build (-Ilib/wasi), so a native build never sees it. */
#ifndef SP_WASI_SIGNAL_H
#define SP_WASI_SIGNAL_H
#include_next <signal.h>
#include <sys/types.h>

#define SA_RESTART   0x10000000
#define SA_SIGINFO   0x00000004
#define SA_ONSTACK   0x08000000
#define SA_NODEFER   0x40000000
#define SA_RESETHAND 0x80000000

typedef struct {
  int si_signo, si_errno, si_code;
  void *si_addr;
} siginfo_t;

struct sigaction {
  union {
    void (*sa_handler)(int);
    void (*sa_sigaction)(int, siginfo_t *, void *);
  } __sa_handler;
  sigset_t sa_mask;
  int sa_flags;
};
#define sa_handler   __sa_handler.sa_handler
#define sa_sigaction __sa_handler.sa_sigaction

typedef struct sigaltstack { void *ss_sp; int ss_flags; size_t ss_size; } stack_t;

int sigaction(int, const struct sigaction *, struct sigaction *);
int sigaltstack(const stack_t *, stack_t *);
int sigemptyset(sigset_t *);
int sigaddset(sigset_t *, int);
int sigprocmask(int, const sigset_t *, sigset_t *);
int kill(pid_t, int);
#ifndef SIG_BLOCK
#define SIG_BLOCK 0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2
#endif
#endif
