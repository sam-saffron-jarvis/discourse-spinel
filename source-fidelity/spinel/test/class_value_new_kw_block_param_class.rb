# `k.new(x, **)` on a class known only at run time dispatches through the
# keyword-argument arms, one per class. A class whose initialize keeps a
# named &block takes it as a C parameter, and those arms left it out, so an
# unrelated class with a &block initialize stopped the build (#4882). The
# arm passes nil, as the positional arms do (#4855).

class Plain
  def initialize(x, k: 0)
    @x = x
    @k = k
  end

  def to_s = "Plain(#{@x},#{@k})"
end

class Handled
  def initialize(x, k: 0, &handler)
    @x = x
    @k = k
    @handler = handler
  end

  def to_s = "Handled(#{@x},#{@k},#{@handler ? @handler.call(@x) : "nil"})"
end

class Inherited < Handled
end

class NoKeywords
  def initialize(x, &handler)
    @x = x
    @handler = handler
  end

  def to_s = "NoKeywords(#{@x},#{@handler ? @handler.call(@x) : "nil"})"
end

class Factory
  TYPES = { 0 => Plain, 1 => Handled, 2 => Inherited, 3 => NoKeywords }.freeze

  def self.anon(x, **)
    klass = TYPES.fetch(x)
    klass.new(x, **)
  end

  def self.named(x, **kw)
    klass = TYPES.fetch(x)
    klass.new(x, **kw)
  end

  def self.literal(x)
    klass = TYPES.fetch(x)
    klass.new(x, k: 7)
  end

  def self.dynamic(x, **)
    klass = x == 0 ? Plain : Handled
    klass.new(x, **)
  end

  def self.statement(x, **)
    klass = TYPES.fetch(x)
    klass.new(x, **)
    klass
  end
end

Handled.new(9) { |v| v }
NoKeywords.new(9) { |v| v }

4.times { |i| puts Factory.anon(i).to_s }
3.times { |i| puts Factory.anon(i, k: 5).to_s }
4.times { |i| puts Factory.named(i).to_s }
3.times { |i| puts Factory.named(i, k: 6).to_s }
3.times { |i| puts Factory.literal(i).to_s }
2.times { |i| puts Factory.dynamic(i).to_s }
2.times { |i| puts Factory.dynamic(i, k: 8).to_s }
4.times { |i| puts Factory.statement(i) }

begin
  Factory.anon(3, k: 1)
rescue ArgumentError
  puts "ArgumentError"
end

begin
  Factory.literal(3)
rescue ArgumentError
  puts "ArgumentError"
end
