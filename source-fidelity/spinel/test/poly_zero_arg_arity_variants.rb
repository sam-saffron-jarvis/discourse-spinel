# Zero-argument poly dispatch judges each arm's count as its method does: an
# arm that takes no arguments binds, one that needs some raises ArgumentError
# with CRuby's range, and a reader still answers.

class A
  def h(x) = [:A, x]
  def t(*r, x) = [:A, r, x]
  def g(a = 1) = [:A, a]
end

class B
  def h = [:B]
  def t(*r, x) = [:B, r, x]
  def g(a, b = 2) = [:B, a, b]
end

class C
  attr_reader :h

  def initialize
    @h = :C_reader
  end

  def t = :C
  def g(a) = [:C, a]
end

[A.new, B.new, C.new].each do |o|
  [-> { o.h }, -> { o.t }, -> { o.g }].each do |call|
    begin
      p call.call
    rescue ArgumentError => e
      p e.message
    end
  end
end

# a method reopened on Object is the default arm: one that needs an argument
# raises for every receiver no class arm takes
class Object
  def zz(x) = [:zz, x]
end

class K
  def zz = :K
end

[K.new, 5, "s", A.new].each do |o|
  begin
    p o.zz
  rescue ArgumentError => e
    p e.message
  end
end
