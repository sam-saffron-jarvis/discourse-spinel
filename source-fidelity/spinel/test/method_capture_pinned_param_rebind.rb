# A method reachable only through `method(:name)` has its parameters
# pinned to int after the inference fixpoint. The re-binding rounds that
# follow the pin have to settle the callee's locals and returns as well:
# the first call types the helper's parameter int, the helper's return
# then widens to Bignum, the local it fills widens with it, and the SECOND
# call passes that Bignum -- so the parameter has to widen too, or the C
# passes an sp_Bigint* to an sp_int. Both modes; the values fit an int.
module Rt
  M64 = 0xffff_ffff_ffff_ffff
  module_function
  def m64(x) = (x >= 0 && x <= M64) ? x : (x & M64)
end

class Mod
  include Rt
  def initialize
    @exports = { "add3" => method(:_add3), "seq" => method(:_seq) }
  end
  def invoke(name, *args)
    @exports[name].call(*args)
  end
  def _add3(l0, l1, l2)
    l3 = m64(l0 + l1)
    m64(l3 + l2)
  end
  def _seq(l0, l1, l2)
    l3 = m64(m64(l0 + l1) + l2)
    [l3, l3 < l0 ? 1 : 0]
  end
end

m = Mod.new
p m.invoke("add3", 1, 1, 1)
p m.invoke("add3", -5, 2, 3)
p m.invoke("seq", 1, 2, 3)
p m.invoke("seq", -1, 0, 0)
