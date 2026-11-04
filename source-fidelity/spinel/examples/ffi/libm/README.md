# libc / libm FFI demo

Calls a handful of libc and libm functions directly. libc and libm are
linked into every Spinel binary by default, so no `ffi_lib` declaration
is needed for these.

## Build & run

From the repo root:

```sh
./spinel examples/ffi/libm/libm.rb
./libm
```

Expected output:

```
1
4
1024
12
pid > 0: true
```
