# A multiple assignment whose target is an index write on a user class
# (`b["href"], title = ...`) is a call of that class's []=. The emitter had
# no arm for it: a literal right side was refused and a computed one dropped
# the write silently, so the program ran with the attribute missing (#5075).

class Box
  def initialize
    @h = {}
  end

  def []=(k, v)
    @h[k] = v
  end

  def [](k)
    @h[k]
  end
end

attrs = { "src" => "/x.png", "alt" => "a" }
b = Box.new
b["href"], title, alt = attrs.values_at("src", "title", "alt").map { |a| a.to_s }
p b["href"]
p title
p alt

c = Box.new
c["x"], c["y"] = ["1", "2"]
p [c["x"], c["y"]]

class Holder
  def initialize = @box = Box.new
  def fill(pair)
    @box[:a], rest = pair
    [@box[:a], rest]
  end
end
p Holder.new.fill([10, 20])
