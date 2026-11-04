# `return x unless block` in an inlined yielding method.
#
# The method's result slot is written from two places -- the guarded return
# and the yield tail -- and takes the tail's type. The guard is decided when
# the body is spliced (a literal block is there, or it is not), but only the
# `block_given?` spelling was read that way: `unless block`, written against
# the method's own `&block` parameter, stayed in the C, and its dead branch
# assigned the return's value into the slot the live branch had typed. An
# `sp_F *` met a `const char *` and the build stopped (#4819).
class F
  def path = "a.img"
  def size = 5
end

def with_f(&block)
  f = F.new
  return f unless block
  yield f
end

# a literal block: the guarded return is dead
p with_f { |x| x.path }
# no block: the yield tail is dead
p with_f.class
# a second site whose block answers something else
p with_f { |x| x.size }

# the `if block` direction, where the guard is still decided when the body is
# spliced. The block is used only as a presence test here: a method that uses
# the name as a VALUE is reached through its proc form, takes the block as a
# real argument, and must NOT be answered statically -- that shape is covered
# by test/toplevel_extend_block_param.rb.
def pick(&blk)
  if blk
    yield 3
  else
    0
  end
end
p pick { |n| n * 2 }
p pick
