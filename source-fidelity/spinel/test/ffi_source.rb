# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
# `ffi_source` embeds a compile-time C fragment into the generated translation
# unit, allowing a genuinely single-source-file adapter without a sidecar .c.
module InlineC
  ffi_source <<~C
    #include <stdint.h>
    intptr_t inline_c_triple(intptr_t value) { return value * 3; }
  C
  ffi_func :inline_c_triple, [:long], :long
end

puts InlineC.inline_c_triple(14)
