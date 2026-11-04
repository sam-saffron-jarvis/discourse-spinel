module Named; end
module Tagged; end
class Item
  include Named
  include Comparable
  def initialize(n) = @n = n
  def <=>(o) = @n <=> o.n
  attr_reader :n
end
class Special < Item; end
class Plain; end
it = Item.new(1)
sp = Special.new(2)
pl = Plain.new
if it.is_a?(Named) then puts "if-yes" else puts "if-no" end
puts(it.is_a?(Named) ? "tern-yes" : "tern-no")
puts "unless-yes" unless it.is_a?(Tagged)
puts(sp.kind_of?(Named) ? "sub-yes" : "sub-no")
puts(it.instance_of?(Named) ? "inst-yes" : "inst-no")
puts(pl.is_a?(Named) ? "plain-yes" : "plain-no")
if it.is_a?(Comparable) then puts "cmp-yes" else puts "cmp-no" end
case it
when Tagged then puts "when Tagged"
when Named then puts "when Named"
end
puts(case sp; when Comparable then "when Comparable"; else "other"; end)
puts(case it; in Named then "in Named"; else "other"; end)
puts(case sp; in Comparable then "in Comparable"; else "other"; end)
puts(case it; in Tagged then "in Tagged"; else "other"; end)
puts(case pl; in Named then "in Named"; else "plain other"; end)
r = (sp in Named)
puts r
puts(case it; in Enumerable then "in Enumerable"; else "not Enumerable"; end)
