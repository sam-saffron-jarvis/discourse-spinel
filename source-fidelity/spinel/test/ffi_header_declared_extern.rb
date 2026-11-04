# An ffi_func whose symbol a header also declares, with C types other than the
# spec's: fopen's FILE * is :ptr's void *, strchr and getenv return char * where
# :str is const char *, memcpy is a macro on some libcs. The extern is declared
# under a private name bound to the symbol by an asm label, so it can't conflict
# with the header's prototype, an ffi_source one, or a second module binding
# the same symbol under other specs (#4891). A variadic one (fprintf) gets the
# same extern with a trailing `...`: calling fprintf through a cast pointer
# whose first parameter is void * is an error under gcc -Werror.
# Expected output written by hand: CRuby has no ffi_func.

module LibC
  ffi_func :fopen,  %i[str str], :ptr
  ffi_func :fputs,  %i[str ptr], :int
  ffi_func :fflush, [:ptr], :int
  ffi_func :fread,  %i[ptr size_t size_t ptr], :size_t
  ffi_func :fileno, [:ptr], :int
  ffi_func :fclose, [:ptr], :int
  ffi_func :fprintf, %i[ptr str varargs], :int
  ffi_func :strchr, %i[str int], :str
  ffi_func :strdup, [:str], :str
  ffi_func :getenv, [:str], :str
  ffi_func :atoi,   [:str], :int
  ffi_func :malloc, [:size_t], :ptr
  ffi_func :memcpy, %i[ptr ptr size_t], :ptr
  ffi_func :free,   [:ptr], :void
  ffi_func :time,   [:ptr], :long
  ffi_func :strlen, [:str], :size_t
  ffi_func :getpid, [], :int
end

module LibM
  ffi_func :cos, [:double], :double
end

module Other
  ffi_func :strlen, [:str], :long
end

module Tiny
  ffi_source <<~C
    int tiny_count(const char *const *names);
    int tiny_count(const char *const *names) { return names ? 1 : 3; }
  C
  ffi_func :tiny_count, [:ptr], :int
end

w = LibC.fopen("/dev/null", "w")
puts w == nil ? "nil" : "open"
puts LibC.fputs("hello", w) >= 0
puts LibC.fprintf(w, "n=%d\n", 42)
puts LibC.fflush(w)
puts LibC.fclose(w)

r = LibC.fopen("/dev/null", "r")
buf = LibC.malloc(16)
puts LibC.fread(buf, 1, 16, r)
puts LibC.fileno(r) > 2
puts LibC.fclose(r)

copy = LibC.malloc(16)
puts LibC.memcpy(copy, buf, 16) == copy
LibC.free(copy)
LibC.free(buf)

puts LibC.strchr("hello", 108)
puts LibC.strdup("abc")
puts LibC.getenv("PATH") == nil ? "unset" : "set"
puts LibC.atoi("42")
puts LibC.time(nil) > 1_000_000_000
puts LibC.strlen("hello")
puts Other.strlen("hello!")
puts LibC.getpid > 0
puts LibM.cos(0.0).to_i
puts Tiny.tiny_count(nil)
