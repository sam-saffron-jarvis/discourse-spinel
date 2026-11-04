/* wasm32-wasi: no processes; popen answers NULL with ENOSYS (see signal.h
   here). */
#ifndef SP_WASI_STDIO_H
#define SP_WASI_STDIO_H
#include_next <stdio.h>
FILE *popen(const char *, const char *);
int pclose(FILE *);
#endif
