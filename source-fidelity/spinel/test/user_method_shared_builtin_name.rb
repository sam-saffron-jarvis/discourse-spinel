# A user method named after a builtin (`replace`, which String, Array and Hash
# all own), reached through an untyped slot. Two mechanisms conspired to run
# String#replace on an object and answer the argument (#4240):
#
#   - the container-read alias promotion bound the local to a string handle
#     because the mutator-name table matched and the container held a string
#     SOMEWHERE, which is true of any heterogeneous container;
#   - and the poly `replace` arm took the builtin without asking whether a
#     user class owns the name, which its `pack` sibling already asked.
class Frag
  def initialize(html)
    @html = html
  end

  def replace(selector)
    r = block_given? ? yield : "-"
    Frag.new("user-replace:" + selector + ":" + r.to_s)
  end

  def to_s
    @html
  end
end

f1 = Frag.new("abc")
p f1.replace("sel") { nil }.to_s

# the reported shape: a heterogeneous array, so the element is untyped
box = [Frag.new("abc"), "just a string"]
f2 = box[0]
p f2.replace("sel") { nil }.to_s
p f2.replace("sel").to_s

# an array element through the same untyped slot keeps Array#replace
arrs = [Frag.new("z"), [1, 2]]
a = arrs[1]
a.replace([3, 4])
p a
