# A self-recursive yielder whose VALUE is the block's answer works for every
# type the block can answer, not only the ones that fit a machine word.
#
# Such a method is lowered to a real &block (sp_Proc) function, and its return
# used to be forced to Integer: the raw carrier slot, meant to be cast back to
# the real type at the call site. Only some consumer paths emitted that cast --
# `puts x` did, `p x` did not -- so a block answering a String or an Array
# reached a `const char *` slot as an sp_int and the C did not compile. A block
# answering different types on different paths had no cast that could work at
# all, the raw bits being unable to carry a tag. One function serves every call
# site, so the signature is poly and the call site reads it as poly.

def walk(n)
  return yield(n) if n <= 0
  walk(n - 1) { |x| yield x }
end

# Pointer-kind answers: these did not compile.
p walk(2) { |i| "v#{i}" }
p walk(1) { |i| [i, i] }
p walk(1) { |i| { a: i } }

# An answer that differs by path is poly -- no single scalar slot holds it.
p walk(1) { |i| i > 0 ? "s" : 1 }

# Word-sized answers kept working and must keep working.
p walk(2) { |i| i * 10 }
p walk(1) { |i| i * 1.5 }
p walk(1) { |i| :sym }
p walk(1) { |i| nil }
p walk(1) { |i| i.zero? }

# The SAME method driven by blocks of different types from different call
# sites: one C function serves both, so neither may pin the signature.
def countdown(n)
  return yield if n <= 0
  countdown(n - 1) { yield }
end
puts countdown(2) { "done" }
puts countdown(3) { 42 }
p countdown(1) { [1, 2] }

# The instance-method form takes the same path.
class Counter
  def countdown(n)
    return yield if n <= 0
    countdown(n - 1) { yield }
  end
end
cc = Counter.new
p cc.countdown(2) { "inst" }
p cc.countdown(2) { 7 }

# The value is really the block's, at every depth -- a block reading the
# recursion's own argument still answers per level.
def collect(n)
  return yield(n) if n <= 0
  collect(n - 1) { |x| yield(x) }
end
p collect(3) { |d| "depth#{d}" }

# A yielder whose value is its OWN tail, not the block's, is unchanged: it
# still answers what its body ends with.
def own_tail(n)
  yield n
  own_tail(n - 1) { |x| x } if n > 0
  :mine
end
p own_tail(1) { |x| "ignored" }
