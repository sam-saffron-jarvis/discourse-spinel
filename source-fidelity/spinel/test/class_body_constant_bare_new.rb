# A class-body constant initialised with a bare `new(...)` (#4515): the
# implicit self of a class body is the class, so `new(0)` there is `K.new(0)`.
# The constant was dropped ("defined nowhere in the program") because nothing
# resolved the receiverless call.
class K
  def initialize(n) = @n = n
  def n = @n

  MAP = { 0 => new(0), 1 => new(1) }.freeze

  def self.find(i) = MAP[i]
end

p K.find(1).n   # CRuby: 1

module Outer
  class Inner
    def initialize(v) = @v = v
    def v = @v
    TABLE = [new(1), new(2)]
    DEFAULT = new(9)
    def self.first = TABLE.first
    def self.make(x) = new(x)
    def twin = self.class.new(@v)
  end
end
p Outer::Inner.first.v
p Outer::Inner::DEFAULT.v
p Outer::Inner.make(5).v
p Outer::Inner::TABLE.map(&:v)
p Outer::Inner.new(3).twin.v
