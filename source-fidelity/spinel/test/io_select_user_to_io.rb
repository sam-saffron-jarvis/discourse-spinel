# IO.select on a user wrapper that holds a raw socket is the protocol
# behind every TLS/passthrough/pipe class. The codegen gate for adding
# the class to sp_user_to_io_dispatch used to require m->ret == TY_IO
# and skip nothing about yield or &block; the prototype and definition
# loops, however, do skip s->yields and do add an sp_Proc * parameter
# for non-yielding &block. The mismatch produced two failures:
#
# 1. A poly body (`def to_io; @sock; end`) left the class out of the
#    dispatch, so IO.select raised "no implicit conversion of X into IO".
# 2. A yielding body left the class in the dispatch but the prototype
#    and definition loops had skipped it, so the C compile failed with
#    "undefined reference to sp_X_to_io" (or, for &block, "too few
#    arguments" because the dispatch call missed the sp_Proc *).
#
# The fix accepts TY_UNKNOWN and TY_POLY in the gate, excludes scopes
# with s->yields, and passes NULL for the block parameter when the
# method has one. Cases 1 and 2 below match between CRuby and spinel;
# case 3 (yielding) is included in the source so the spinel compile
# exercises the gate exclusion -- a class the gate forgot to skip
# would fail the C build with an undefined-symbol error.

require "socket"

def make_pair
  a, b = Socket.pair(1, 1, 0)
  Thread.new { b.write "x"; b.close }
  [a, b]
end

# 1. poly return (the common wrapper shape: `def to_io; @sock; end`).
#    The constructor takes the raw socket (poly), so @sock is poly,
#    so to_io's return is TY_POLY. The class must be in the dispatch.
class Wrap
  def initialize(sock)
    @sock = sock
  end
  def to_io
    @sock
  end
end

a, _ = make_pair
w = Wrap.new(a)
ready = IO.select([w], nil, nil, 5)
p ready ? "poly" : "TIMEOUT"      #=> "poly"

# 2. non-yielding &block. The prototype includes sp_Proc *lv_block;
#    the dispatch must pass NULL so the C compile succeeds.
class BlockWrap
  def initialize(sock)
    @sock = sock
  end
  def to_io(&block)
    @sock
  end
end

a, _ = make_pair
w = BlockWrap.new(a)
ready = IO.select([w], nil, nil, 5)
p ready ? "block" : "TIMEOUT"     #=> "block"

# 3. yielding #to_io -- the class is excluded from the dispatch to
#    match the prototype/definition loops. A class the gate forgot
#    to skip makes the spinel C build fail, so this case guards the
#    exclusion at compile time rather than testing runtime behaviour.
#    It has to be INSTANTIATED and CALLED to guard anything: an
#    unreachable method never reaches the dispatch in the first
#    place, so the class alone would pass whether the gate skipped
#    yielding scopes or not.
class YieldWrap
  def initialize(sock)
    @sock = sock
  end
  def to_io
    yield if block_given?
    @sock
  end
end

a, _ = make_pair
y = YieldWrap.new(a)
n = 0
y.to_io { n += 1 }
p n                               #=> 1

# ...and the wrapper shapes above still select with such a class in
# the program, which is the whole point of excluding it rather than
# refusing the build.
a, _ = make_pair
ready = IO.select([Wrap.new(a)], nil, nil, 5)
p ready ? "poly-with-yielding-peer" : "TIMEOUT"

puts "done"
