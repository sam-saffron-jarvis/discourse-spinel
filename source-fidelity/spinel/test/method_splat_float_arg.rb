# A Float handed to a Method through a splat. The spread helper published each
# argument boxed -- which is all a poly-ABI target ever reads -- and ALSO
# precomputed a raw sp_int view of it for a legacy target. Once the boxed
# Float-to-Integer conversion began raising past the machine word rather than
# saturating, that eager conversion took out calls that never wanted it: the
# target here takes its arguments boxed and intact, and `call(*args)` died on
# an argument it was about to receive unharmed.
class Dispatch
  def initialize
    @table = { "eq" => method(:eq), "add" => method(:add), "show" => method(:show) }
  end
  def invoke(name, *args) = @table.fetch(name).call(*args)
  def eq(a, b) = a == b ? 1 : 0
  def add(a, b) = a + b
  def show(a) = a.to_s
end

d = Dispatch.new
# small floats always worked; the wide ones are the regression
p d.invoke("eq", 1.0, 2.0)
p d.invoke("eq", 2.0, 2.0)
p d.invoke("eq", -0.0, -3.4028234663852886e+38)
p d.invoke("eq", 1.7976931348623157e+308, 1.7976931348623157e+308)
p d.invoke("add", 1.5, 2.25)
p d.invoke("add", -3.4028234663852886e+38, 0.0)
p d.invoke("show", 3.4028234663852886e+38)

# the same target called directly, with and without the splat
mm = d.method(:eq)
p mm.call(-0.0, -3.4028234663852886e+38)
args = [-0.0, -3.4028234663852886e+38]
p mm.call(*args)
# an argument read out of a container, so its kind is only known at run time
boxed = [-3.4028234663852886e+38, nil][0]
p mm.call(-0.0, boxed)

# the kinds that DO have a raw slot still reach the target unchanged
p d.invoke("eq", 2, 2)
p d.invoke("add", 3, 4)
p d.invoke("show", "x")
p d.invoke("eq", 2.0, 2)
