# A receiver's C name is as long as its Ruby name. A 61-character local
# was cut to 63 bytes of C text, which named the 60-character local next
# to it, and its method ran on the wrong object with no diagnostic; a
# 70-character local was cut to the same neighbour. An instance variable
# read through self-> gets the same 63-byte cut and keeps 54 characters
# where a local keeps 60.
class K
  attr_reader :v
  def initialize(v); @v = v; end
  def m; @v * 2; end
  def n(x); @v + x; end
  def self.tag; "K"; end
end
class J < K
  def m; @v * 3; end
  def self.tag; "J"; end
end
class P
  def initialize(x); @x = x; end
  def dbl; @x * 2; end
end
class Holder
  def initialize
    @bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb = K.new(9)
    @bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb = K.new(1)
  end
  def read; [@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.m, @bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.n(5), @bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.class.tag]; end
end
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = K.new(9)
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = K.new(1)
p(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.m)
p(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.n(5))
p(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.class.tag)
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = J.new(4)
p(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.m)
p(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.class.tag)
p(Holder.new.read)

cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc = P.new(9)
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc = P.new(1)
p(ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.dbl)
