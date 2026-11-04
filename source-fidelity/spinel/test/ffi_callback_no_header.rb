# Adjacent, left alone: a callback-taking function no included header declares
# (lfind is in <search.h>) is called with no prototype at all -- an implicit
# declaration returning int, so the :ptr result is truncated (clang warns
# "cast to 'void *' from smaller integer type 'int'"; gcc 14+ rejects it).
module L
  ffi_callback :cmp, [:ptr, :ptr], :int
  ffi_func :calloc, [:size_t, :size_t], :ptr
  ffi_func :lfind, [:ptr, :ptr, :ptr, :size_t, :cmp], :ptr
end
def cmp(a, b) = 0
nel = L.calloc(1, 8)
puts L.lfind(nil, nil, nel, 8, method(:cmp)) == nil
