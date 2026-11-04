# Methods a class gets through `extend M` run as class methods of that class:
# `self` is the class, and the block is the one the class method's caller
# passes. They used to share the module's body, typed against the module, so a
# block param, a yield, a forwarded `&` or a `self` handed out broke the C.

class K
  def self.name_of(o, n) = "#{o.name}:#{n}"
  def self.apply(o, n, &) = yield(o, n)
end

module MM
  def via_blk(n, &b) = b.call(n)
  def via_yield(n, &) = yield(n)
  def forward(n, &) = K.apply(self, n, &)
  def tag(n) = K.name_of(self, n)
  def scaled(n = 3, &b) = b.call(n) * 2
  def owner_name = describe(self)
  def describe(o) = "<#{o.name}>"
end

class V
  extend MM
  p(via_blk(:a) { |x| x.to_s })
  p(via_yield(:b) { |x| x.to_s })
  p(forward(:c) { |o, x| "#{o.name}/#{x}" })
  p tag(:d)
  p(scaled { |x| x + 1 })
end

class W
  extend MM
  p(scaled(10) { |x| x - 1 })
  p owner_name
end

p V.via_blk(1) { |x| x + 1 }
p W.via_yield("s") { |x| x * 2 }
p W.forward(2) { |o, x| [o.name, x] }
p V.tag(:e)
p V.owner_name

# The macro-module DSL shape: the class body calls a macro that hands the
# class and the block on to a builder.
module MacroMethods
  def machine(name = :state, &) = Machine.find_or_create(self, name, &)
end

module Registry
  def machines = @machines
end

class Machine
  attr_reader :events

  def self.find_or_create(owner, name, &)
    m = new(owner, name)
    m.instance_eval(&) if block_given?
    m
  end

  def initialize(owner, name)
    @events = []
    owner.machines[name] = self
  end

  def event(n) = @events << n
end

class Vehicle
  extend Registry
  @machines = {}
  extend MacroMethods
  machine :state do
    event :ignite
    event :park
  end
end

p Vehicle.machines[:state].events

# A class-body call whose VALUE is used: the yielding class method is inlined
# there too, since it has no function of its own, and it wins over a top-level
# method of the same name.
def inc = yield * 100

module Twice
  def twice(n) = yield(n) * 2
  def doubled = yield * 2
end

class Y
  extend Twice
  def self.inc = yield + 1
  def self.fwd(&) = K.apply(self, 20, &)
  p(doubled { 21 })
  x = inc { 41 }
  p x
  p "t=#{twice(3) { |v| v + 1 }}"
  p K.name_of(Y, twice(4) { |v| v })
  p [inc { 1 }, inc { 2 }]
  p(fwd { |o, v| "#{o.name}#{v}" })
  [1, 2].each { |i| p twice(i) { |v| v } }
  inc { 0 }
end
p(inc { 1 })
