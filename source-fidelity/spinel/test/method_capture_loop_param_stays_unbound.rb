# A method reached only through `method(:name)` and Method#call has no
# call site to type its parameters, so they stay unknown and take the boxed
# lane. The loop-growth heuristic (`x = x + x`, `x = x * y` inside a loop)
# widened such a parameter to Bignum from unknown, the C signature took an
# sp_Bigint *, and the thunk refused a Float argument. A parameter bound
# Integer from a call site still widens (the accumulator below), and a body
# local widens from unknown as before.
class C
  def initialize
    @exports = { "add" => method(:add), "mul" => method(:mul), "lin" => method(:lin) }
  end
  def invoke(name, *args) = @exports.fetch(name).call(*args)
  def add(l0, l1)
    while true
      l0 = l0 + l0
      break
    end
    [l0, l1]
  end
  def mul(l0, l1)
    while true
      l0 = l0 * l0
      break
    end
    [l0, l1]
  end
  def lin(l0, l1)
    while true
      l0 = l0 + 1
      break
    end
    [l0, l1]
  end
end

c = C.new
p c.invoke("add", 1.5, 2.5)
p c.invoke("mul", 1.5, 2.5)
p c.invoke("lin", 1.5, 2.5)
p c.invoke("add", 3, 4)
p c.invoke("mul", 3, 4)

def acc(a)
  while true
    a = a * a
    break
  end
  a
end
p acc(10**6)
