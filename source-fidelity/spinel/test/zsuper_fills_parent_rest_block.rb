# A bare `super` from a method with fewer parameters than its parent: the
# parent's `*rest` and `**kw` take an empty Array and Hash, and a parent that
# takes a block only to yield to it is still reached when there is no block to
# forward. A named `&blk` takes the call's block, else the block the method
# was called with -- declared or not -- else nil, with or without explicit
# arguments (#4852).

class RestBase
  def m(x, *rest) = [x, rest]
end
class RestGrey < RestBase
  def m(x) = super
end
p RestGrey.new.m(5)

class KwrestBase
  def m(x, **kw) = [x, kw]
end
class KwrestGrey < KwrestBase
  def m(x) = super
end
p KwrestGrey.new.m(5)

class BlockBase
  def m(x, &blk) = [x, blk]
end
class BlockGrey < BlockBase
  def m(x) = super
end
p BlockGrey.new.m(5)

class BlockCallBase
  def m(x, &blk) = blk ? blk.call(x) : x
end
class BlockCallGrey < BlockCallBase
  def m(x) = super
end
p BlockCallGrey.new.m(5)
p BlockCallGrey.new.m(5) { |v| v * 3 }

class ImplicitBlockGrey < BlockCallBase
  def m(x) = super(x + 1)
end
p ImplicitBlockGrey.new.m(5) { |v| v * 3 }
p ImplicitBlockGrey.new.m(5)

class ChainBlockBase
  def m(x, &blk) = blk ? blk.call(x) : x
end
class ChainBlockMid < ChainBlockBase
  def m(x) = super
end
class ChainBlockGrey < ChainBlockMid
  def m(x) = super(x * 10)
end
p ChainBlockGrey.new.m(2) { |v| v + 1 }

class InitHookBase
  def initialize(x, &handler)
    @x = x
    @handler = handler
  end
  def fire = @handler ? @handler.call(@x) : :none
end
class InitHookGrey < InitHookBase
  def initialize(x) = super
end
p InitHookGrey.new(3) { |v| v * 7 }.fire
p InitHookGrey.new(3).fire

class ForwardBlockGrey < BlockCallBase
  def m(x, &blk) = super
end
p ForwardBlockGrey.new.m(5) { |v| v * 3 }

class ExplicitBlockGrey < BlockCallBase
  def m(x) = super(x)
end
p ExplicitBlockGrey.new.m(5)

class LiteralBlockGrey < BlockCallBase
  def m(x) = super(x) { |v| v * 4 }
end
p LiteralBlockGrey.new.m(5)

class ClassBlockBase
  def self.m(x, &blk) = [x, blk.nil?]
end
class ClassBlockGrey < ClassBlockBase
  def self.m(x) = super
end
p ClassBlockGrey.m(5)

class AllBase
  def m(x, *rest, k: 1, **kw, &blk) = [x, rest, k, kw, blk.nil?]
end
class AllGrey < AllBase
  def m(x) = super
end
p AllGrey.new.m(5)

class AnonBlockBase
  def m(x, &) = [x]
end
class AnonBlockGrey < AnonBlockBase
  def m(x) = super
end
p AnonBlockGrey.new.m(5)

class YieldBase
  def m(x)
    yield x if block_given?
    [x]
  end
end
class YieldGrey < YieldBase
  def m(x) = super
end
p YieldGrey.new.m(6)

class InitAnonBlockBase
  def initialize(x, &) = @x = x
  def x = @x
end
class InitAnonBlockGrey < InitAnonBlockBase
  def initialize(x) = super
end
p InitAnonBlockGrey.new(5).x

class InitBlockBase
  def initialize(x, &blk) = @x = x
  def x = @x
end
class InitBlockGrey < InitBlockBase
  def initialize(x) = super
end
p InitBlockGrey.new(5).x

class InitRestBase
  def initialize(x, *r) = @x = [x, r]
  def x = @x
end
class InitRestGrey < InitRestBase
  def initialize(x) = super
end
p InitRestGrey.new(5).x

class SurplusGrey < RestBase
  def m(x, y) = super
end
p SurplusGrey.new.m(5, 6)

class OptRestBase
  def m(x, y = 0, *rest) = [x, y, rest]
end
class OptRestGrey < OptRestBase
  def m(a, b, c) = super
end
class OptRestShortGrey < OptRestBase
  def m(a, b) = super
end
p OptRestGrey.new.m(1, 2, 3)
p OptRestShortGrey.new.m(1, 2)

class ClassSurplusBase
  def self.m(x, *rest, k: 1) = [x, rest, k]
end
class ClassSurplusGrey < ClassSurplusBase
  def self.m(x, y, z) = super
end
p ClassSurplusGrey.m(1, 2, 3)

class YieldSurplusBase
  def m(x, *rest)
    yield [x, rest]
  end
end
class YieldSurplusGrey < YieldSurplusBase
  def m(x, y)
    super { |v| p v }
  end
end
YieldSurplusGrey.new.m(7, 8)

# already correct before this fix
class OptBase
  def m(x, y = 2) = [x, y]
end
class OptGrey < OptBase
  def m(x) = super
end
p OptGrey.new.m(5)

class KwBase
  def m(x, k: 1) = [x, k]
end
class KwGrey < KwBase
  def m(x) = super
end
p KwGrey.new.m(5)

class InitAnonBase
  def initialize(x, *, **) = @x = x
  def x = @x
end
class InitAnonGrey < InitAnonBase
  def initialize(x) = super
end
p InitAnonGrey.new(5).x

class ClassRestBase
  def self.m(x, *rest, **kw) = [x, rest, kw]
end
class ClassRestGrey < ClassRestBase
  def self.m(x) = super
end
p ClassRestGrey.m(5)
