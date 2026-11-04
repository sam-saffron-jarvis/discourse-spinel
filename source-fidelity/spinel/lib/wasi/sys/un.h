/* wasm32-wasi: wasi-libc's sockaddr_un has no path; a program that binds one
   gets ENOTSUP from the host (see ../signal.h here). */
#ifndef SP_WASI_SYS_UN_H
#define SP_WASI_SYS_UN_H
#include <sys/socket.h>
struct sockaddr_un { sa_family_t sun_family; char sun_path[108]; };
#endif
