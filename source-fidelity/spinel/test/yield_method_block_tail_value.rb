# A block whose VALUE is a call driving a block into a yielding method: the
# callee splices inline, and its statement form is a plain compound with no
# value -- the splice must take the expression form, or the enclosing block's
# slot receives a void ({...}) and the C does not compile.
class Builder
  def self.build(n)
    x = "a" * n
    yield x
    r = x + "z"
    r
  end
end

def wrap
  r = yield
  "got #{r}"
end

acc = []
puts wrap { Builder.build(3) { |v| acc << v } }
p acc
# the same shape through an instance method
class Widget
  def make(base)
    y = base * 2
    yield y
    y + 1
  end
end
puts wrap { Widget.new.make(20) { |v| acc << v } }
p acc
