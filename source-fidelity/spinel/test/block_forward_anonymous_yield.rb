# A block forwarded through an anonymous `&` (`def each(&) = @items.each(&)`)
# and the enclosing object's own methods called from it. The forward was left
# to the inline path, which spliced the caller's block into the loop without
# typing its parameters or connecting them, so every such loop ran with an
# empty body: no exception, no warning, the work simply skipped. The forward
# is now the block `{ |__fwd| yield __fwd }`, as a named `&blk` already
# became `{ |__fwd| blk.call(__fwd) }`, and the yield does the rest: a Hash
# pair to |k, v| or |pair|, each_with_index, map's value, two forwards in one
# body, a top-level def, and a private method of the caller (#4618,
# ryudoawaru).
class Reg
  def initialize; @items = [1, 2, 3]; @h = { "a" => 1, "b" => 2 }; @s = ["x", "y"]; end
  def each(&) = @items.each(&)
  def each_pair(&) = @h.each(&)
  def each_key(&) = @h.each_key(&)
  def map_items(&) = @items.map(&)
  def each_str(&) = @s.each(&)
  def each_i(&) = @items.each_with_index(&)
  def each2(&); @items.each(&); @s.each(&); end
  def none(&) = @items.length
end
class App
  def initialize; @seen = []; end
  def run
    r = Reg.new
    r.each { |i| note(i) }
    r.each_pair { |k, v| note("#{k}=#{v}") }
    r.each_pair { |pair| note(pair.inspect) }
    r.each_key { |k| note(k) }
    note(r.map_items { |i| i * 10 }.inspect)
    r.each_str { |s| note(s.upcase) }
    r.each_i { |x, i| note("#{i}:#{x}") }
    r.each2 { |x| note(x.to_s) }
    note(r.none { |x| x }.to_s)
    @seen
  end
  private
  def note(x) = @seen << x
end
p App.new.run
def top(&) = [7, 8].each(&)
top { |x| p x }
