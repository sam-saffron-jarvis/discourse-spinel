/* wasm32-wasi: no terminals; ioctl answers ENOTTY (see ../signal.h here). */
#ifndef SP_WASI_SYS_IOCTL_H
#define SP_WASI_SYS_IOCTL_H
#include_next <sys/ioctl.h>
#ifndef TIOCGWINSZ
#define TIOCGWINSZ 0x5413
struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
#endif
int ioctl(int, int, ...);
#endif
