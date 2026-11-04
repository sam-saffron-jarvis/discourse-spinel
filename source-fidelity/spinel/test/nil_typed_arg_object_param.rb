# A nil-typed argument (a method answering nil) passed where the parameter
# holds an object passes nil (#4930)
class Item
  def initialize(n) = @n = n
  def n = @n
end
class Ctl
  def build = nil
end
def show(item) = item.n
p show(Ctl.new.build) if ARGV.size > 5
p show(Item.new(2))
