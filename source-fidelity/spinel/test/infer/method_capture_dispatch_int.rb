# A dispatch table of captured methods called with Integer arguments only
# (`@store[addr][addr, value]`, optcarrot's shape): the untyped parameters
# of the captured methods keep the sp_int lane, since every dynamic call of
# a Method value in the program passes Integers.
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
p b.ram
