# A call no possible receiver answers is not typed from an unrelated class's
# method, and the class-side methods of the name join its type (#4930)
class Item
  def initialize(n) = @n = n
  def n = @n
end

class Rel
end

class Story
  def comments = Rel.new
end

class User
  def comments = [Item.new(1)]
end

class Hb
  def self.build = Hb.new
end
class Hs
  def self.build = Hs.new
end
class Ctl
  def build = nil
end

def show(item) = item.n

owner = ARGV.size > 5 ? Story.new : User.new
p show(owner.comments.build) if ARGV.size > 5
p show(Item.new(2))
