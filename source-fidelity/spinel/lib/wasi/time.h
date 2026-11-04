/* wasm32-wasi: WASI has no per-process CPU clock; Process.clock_gettime of
   CLOCK_PROCESS_CPUTIME_ID reads the monotonic clock, as wasi-libc's
   emulated clock(3) does (see signal.h here). */
#ifndef SP_WASI_TIME_H
#define SP_WASI_TIME_H
#include_next <time.h>
#ifndef CLOCK_PROCESS_CPUTIME_ID
#define CLOCK_PROCESS_CPUTIME_ID CLOCK_MONOTONIC
#endif
#ifndef CLOCK_THREAD_CPUTIME_ID
#define CLOCK_THREAD_CPUTIME_ID CLOCK_MONOTONIC
#endif
#endif
