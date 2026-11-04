# An ensure inside a method whose return type settled on nil declared its
# deferred-return slot as `void _retvN`, because the slot's guard excluded only
# TY_VOID and TY_UNKNOWN while emit_ctype has no C name for nil either. The
# build stopped there (#4245). Reaching it needs the yielding method inlined
# into a lifted proc -- a poly receiver's #each, where the block is
# materialized rather than spliced -- so the instantiation types differently
# from the one the direct call site gets.
module M
  @f = false
  def self.wrap
    html = ""
    @f = true
    begin
      html = yield
    ensure
      @f = false
    end
    html
  end

  def self.flag
    @f
  end
end

class Bag
  def initialize(a)
    @a = a
  end

  def each
    @a.each { |x| yield x }
  end
end

box = [Bag.new(["a", "b"]), "s"]
b = box[0]
b.each do |m|
  puts M.wrap { "x#{m}" }
end
p M.flag

# the ensure still runs on the way out of a raise
module R
  @seen = []
  def self.guard
    begin
      yield
    ensure
      @seen << :ensured
    end
  end

  def self.seen
    @seen
  end
end

bag2 = [Bag.new(["p"]), 1]
b2 = bag2[0]
b2.each do |m|
  begin
    R.guard { raise ArgumentError, "boom #{m}" }
  rescue ArgumentError => e
    puts e.message
  end
end
p R.seen

# a nil-returning method with an ensure, called directly
module N
  def self.run
    begin
      nil
    ensure
      $stdout.flush
    end
  end
end
p N.run
