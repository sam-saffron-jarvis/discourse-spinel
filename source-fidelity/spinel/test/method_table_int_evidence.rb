# A register-handler shape: the handlers are captured with method(:sym) and
# reached only out of a table, so nothing types their parameters and the
# backstop has to decide a C type without a declaration. It decides from the
# arguments the program passes at its own dynamic Method call sites (#4670,
# #4671). Pinned flat to poly instead, the ivar a handler stores went boxed
# too, and `flag_old, sum_old = @flag, @sum` put an sp_RbVal on the right of
# an sp_int and the C stopped compiling.
#
# The evidence is per POSITION and program-wide, which this program pins from
# both sides at once: position 1 is only ever the table's `value`, an Integer,
# so `data` stays an integer and the ivars and the multiple assignment stay
# integers with it; position 0 is also the argument of the `call` below, which
# passes a Float, so `addr` is boxed and has to answer as a Float there and as
# an Integer here.
class Bus
  def initialize
    @store = []
    @sum = 0
    @flag = 0
    @last = 0
    @store[0] = method(:poke_0)
    @store[1] = method(:poke_1)
  end

  def poke_0(addr, data)
    @last = addr
    @sum = (data & 0xe0) << 1
  end

  def poke_1(addr, data)
    @last = addr
    @flag = data & 1
  end

  def store(addr, value)
    @store[addr][addr, value]
  end

  def snapshot
    flag_old, sum_old = @flag, @sum
    [flag_old, sum_old, @last]
  end
end

b = Bus.new
b.store(0, 0xff)
p b.snapshot
b.store(1, 1)
p b.snapshot

# The same capture reached through a site that passes a Float. Reading those
# bits as an integer is how a Float came to answer for a number it never was.
class Scale
  def apply(x) = x.is_a?(Float) ? 1 : 0
  def pick = method(:apply)
end
m = Scale.new.pick
p m.call(3.5)
p m.call(2)
