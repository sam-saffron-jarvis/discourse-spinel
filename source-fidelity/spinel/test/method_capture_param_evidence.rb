# A method reached only through method(:name) has its untyped parameters
# pinned after the fixpoint. The pin is decided by evidence: the arguments
# the program passes at every dynamic call of a Method value (`.call`,
# `.()`, a numeric-argument `[]`), per position. Integer-only evidence keeps
# the sp_int lane, which is what a register dispatch table wants
# (`@store[addr][addr, value]`); anything else, a splat included, rides the
# boxed channel, so a Float reaches the target as a Float.
class Bus
  def initialize
    @store = Array.new(4) { method(:poke_nop) }
    @store[1] = method(:poke_ram)
    @ram = [0, 0, 0, 0]
  end
  def poke_nop(_addr, _data); end
  def poke_ram(addr, data)
    @ram[addr] = data & 0xff
  end
  def store(addr, value) = @store[addr][addr, value]
  def ram = @ram
end
b = Bus.new
b.store(1, 0x1ff)
b.store(0, 7)
p b.ram
def le(a, b) = (a <= b) ? 1 : 0
def le_export(a, b) = le(a, b)
exports = { "le" => method(:le_export) }
args = [1.5, 2.5]
p exports.fetch("le").call(*args)
p exports.fetch("le").call(3.5, 2.0)
