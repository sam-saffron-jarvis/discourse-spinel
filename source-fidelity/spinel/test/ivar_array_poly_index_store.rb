# An ivar `[]` filled by `@a[i] = obj` with an index that is not typed
# Integer kept its Integer element type, and the C handed the object to the
# int setter (#4832).

Chip = Struct.new(:bank)
class Bank
  def initialize(data) = @data = data
  def size = @data.length
end
class Cart
  def initialize(chips)
    @banks = []
    chips.each { |chip| @banks[chip.bank] = Bank.new([1, 2]) }
  end
  def bank(i) = @banks[i]
end
bank, = "\x00\x01".unpack("n2")
p Cart.new([Chip.new(bank)]).bank(1).size
class Cart2
  def initialize(chips)
    @banks = []
    chip = chips[0]
    @banks[chip.bank] = Bank.new([1, 2, 3])
  end
  def bank(i) = @banks[i]
end
p Cart2.new([Chip.new(bank)]).bank(1).size
class Cart3
  def initialize(i)
    @names = []
    @names[i] = "x"
  end
  def names = @names
end
p Cart3.new([1, "y"][0]).names
