# Keywords into a poly arm whose method declares none count as one more
# positional hash, as CRuby counts them.

class A
  def m(x, **kw) = [x, kw]
end
class B
  def m(x) = [x]
end
[A.new, B.new].each do |o|
  begin
    p o.m(1, y: 2)
  rescue ArgumentError => e
    p e.message
  end
end
