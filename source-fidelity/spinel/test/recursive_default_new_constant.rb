# A parameter default counts as calling back into its own initialize only
# through `new` on that class, or on a subclass that inherits it. `Array.new`
# or another class's `new` in an initialize default is an ordinary default,
# filled in place. Taking it for a recursive one moved it into a helper,
# whose call was then refused when the object was built from another
# class's method.

module Outer
  class Cart
    SIZE = 4
    class RAMBank
      attr_reader :data
      def initialize(data = Array.new(SIZE, 0))
        @data = data
      end
    end

    class Memory
      def initialize(size = 3) = @cells = Array.new(size, 0)
      def size = @cells.size
    end

    class Drive
      attr_reader :memory
      def initialize(storage, memory = Memory.new)
        @storage = storage
        @memory = memory
      end
    end
  end

  class Pagefox < Cart
    def initialize
      @banks = Array.new(2) { RAMBank.new }
      @drive = Drive.new(:disk)
    end
    def sizes = @banks.map { |b| b.data.size } + [@drive.memory.size]
  end
end
p Outer::Pagefox.new.sizes
p Outer::Cart::RAMBank.new([1]).data

class Holder
  def initialize = @bank = Outer::Cart::RAMBank.new
  def data = @bank.data
end
p Holder.new.data

# a truly recursive initialize default, built from another class
class N
  attr_reader :k
  def initialize(n, k = (n > 0 ? N.new(n - 1).k + 1 : 0))
    @k = k
  end
end
class W
  def initialize = @n = N.new(3)
  def k = @n.k
end
p W.new.k

# the same through a subclass that inherits the initialize
class Base
  attr_reader :depth
  def initialize(n, depth = (n > 0 ? Leaf.new(n - 1).depth + 1 : 0))
    @depth = depth
  end
end
class Leaf < Base
end
class User
  def go = Leaf.new(4).depth
end
p User.new.go
p Base.new(2).depth

# a subclass with its own initialize is not the same method
class Top
  attr_reader :v
  def initialize(v = Other.new.v + 1) = @v = v
end
class Other < Top
  def initialize = @v = 10
end
p Top.new.v

# instance and singleton recursive defaults, called from another class
class Q
  def m(n, v = (n > 0 ? m(n - 1) + 1 : 0)) = v
  def self.d(n, a = (n > 0 ? Q.d(n - 1) + 1 : 0)) = a
end
class Z
  def go = Q.new.m(3)
  def self.cgo = Q.d(2)
end
p Z.new.go
p Z.cgo
