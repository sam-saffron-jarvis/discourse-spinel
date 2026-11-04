# An op-assign whose right-hand side is an unresolved call (`t += o.weight`
# with no such method) lowers the call to the gate's raise token, a boxed
# value; the int, float and String arms of the op-assign emitter wrote it
# raw into the typed slot and the C did not compile. Each arm coerces the
# token as a plain write does, so the program raises CRuby's NoMethodError.
class Foo
  def initialize
    @n = 1
  end
end
xs = [Foo.new]
def try
  yield
rescue NoMethodError => e
  puts e.message
end
try do
  t = 0
  xs.each { |o| t += o.weight }
  p t
end
try do
  f = 1.5
  xs.each { |o| f *= o.weight }
  p f
end
try do
  s = +"a"
  xs.each { |o| s += o.weight }
  p s
end
