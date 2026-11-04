# A C function declared to return `bool` writes ONE BYTE -- AL on x86-64 --
# and leaves the rest of the register alone. Spinel prototyped :bool as int,
# so it read all 64 bits and a false return whose upper bits were dirty came
# back true. The asm below leaves RAX full of 0x0101..01 with the real answer
# in AL, which is what an ABI-conforming _Bool return looks like at its worst
# (reported by rebuilt against raylib, #4392).
#
# native_c_type had the same mismatch and was fixed in b80f6302; this is the
# FFI table, one layer over.
module Poison
  ffi_source <<~'C'
    #include <stdbool.h>
    #if defined(__x86_64__)
    __asm__(
      ".text\n"
      ".globl sp_probe_poison_false\n"
      ".type sp_probe_poison_false, @function\n"
      "sp_probe_poison_false:\n"
      "  movabs $0x0101010101010100, %rax\n"
      "  ret\n"
      ".globl sp_probe_poison_true\n"
      ".type sp_probe_poison_true, @function\n"
      "sp_probe_poison_true:\n"
      "  movabs $0x0101010101010101, %rax\n"
      "  ret\n"
    );
    #else
    bool sp_probe_poison_false(void){return false;}
    bool sp_probe_poison_true(void){return true;}
    #endif
    bool sp_probe_clean_false(void){return false;}
    bool sp_probe_clean_true(void){return true;}
    /* the argument direction: a bool in, negated out */
    bool sp_probe_not(bool v){return !v;}
  C
  ffi_func :sp_probe_poison_false, [], :bool
  ffi_func :sp_probe_poison_true,  [], :bool
  ffi_func :sp_probe_clean_false,  [], :bool
  ffi_func :sp_probe_clean_true,   [], :bool
  ffi_func :sp_probe_not, [:bool], :bool
end

p Poison.sp_probe_poison_false
p Poison.sp_probe_poison_true
p Poison.sp_probe_clean_false
p Poison.sp_probe_clean_true
p Poison.sp_probe_not(true)
p Poison.sp_probe_not(false)
p Poison.sp_probe_poison_false ? "truthy" : "falsy"
