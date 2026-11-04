# A callback-taking ffi_func no included header declares (lfind is in
# <search.h>) is declared under its own extern: its :ptr result is a whole
# pointer, not an implicit int.
module L
  ffi_callback :cmp, [:ptr, :ptr], :int
  ffi_func :calloc, [:size_t, :size_t], :ptr
  ffi_func :lfind, [:ptr, :ptr, :ptr, :size_t, :cmp], :ptr
  ffi_func :lsearch, [:ptr, :ptr, :ptr, :size_t, :cmp], :ptr
end
def never(a, b) = 1
def always(a, b) = 0

nel = L.calloc(1, 8)
# nothing to search: NULL
puts L.lfind(nil, nil, nel, 8, method(:never)) == nil

base = L.calloc(4, 8)
key = L.calloc(1, 8)
# lsearch appends the key when no element matches and answers the new slot
slot = L.lsearch(key, base, nel, 8, method(:never))
puts slot == base
# now one element: lfind answers it, the heap address whole
found = L.lfind(key, base, nel, 8, method(:always))
puts found == base
puts L.lfind(key, base, nel, 8, method(:never)) == nil
