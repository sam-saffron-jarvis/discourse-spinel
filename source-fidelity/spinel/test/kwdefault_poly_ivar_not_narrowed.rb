# frozen_string_literal: true

class Bank
  def initialize(data)
    @data = data
  end

  def peek(addr) = @data[addr & 1]
end

class RAMBank
  def initialize(data)
    @data = data
  end

  def peek(addr) = @data[addr & 1]
end

class Cart
  def initialize(rom)
    @rom = rom
    @ram = RAMBank.new([3, 4])
    @romh = @rom
  end

  def control(value)
    value == 1 ? select(romh: @ram) : select
  end

  def select(romh: @rom)
    @romh = romh
  end

  def peek(addr) = @romh.peek(addr)
end

[Cart.new(Bank.new([1, 2])), Cart.new(RAMBank.new([5, 6]))].each do |cart|
  [1, 0].each do |value|
    cart.control(value)
    puts cart.peek(1)
  end
end
