/* wasm32-wasi: no stack switching; getcontext/swapcontext answer -1, so
   Fiber.new fails at the stack rather than jumping into nothing (see
   signal.h here). */
#ifndef SP_WASI_UCONTEXT_H
#define SP_WASI_UCONTEXT_H
#include <signal.h>
typedef struct ucontext_t {
  struct ucontext_t *uc_link;
  stack_t uc_stack;
  int uc_mcontext;
} ucontext_t;
int getcontext(ucontext_t *);
int setcontext(const ucontext_t *);
void makecontext(ucontext_t *, void (*)(void), int, ...);
int swapcontext(ucontext_t *, const ucontext_t *);
#endif
