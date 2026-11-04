# Through an includer, CRuby runs a `module_function` method on the INSTANCE:
# `@x` is the instance's ivar, `self` is the instance, and a receiverless
# sibling call dispatches on the instance's class. Spinel registers such a
# method class-level, so the include transplant skipped it and a receiverless
# call was rewritten onto the module -- the body then read a module-owned
# global, answered the Module object, and reached the module's sibling rather
# than the includer's override. Both crossing directions break; a module
# method that writes AND reads its own ivar never did (it is consistent
# module-side), so it is here as the control.
module Rt
  module_function
  def peek = @x                 # includer writes, module reads
  def poke(v); @x = v; end      # module writes, includer reads
  def own; @y = 7; @y; end      # same side: the control
  def whoami = self.class.to_s
  def viasib = helper()
  def helper = "module-helper"
  def viaself = self.helper
end

class M
  include Rt
  def helper = "includer-helper"
  def read_after_write
    @x = 42
    peek
  end
  def write_then_read
    poke(9)
    @x
  end
  # module_function makes these PRIVATE instance methods of the includer, so
  # each is reached through a public wrapper, as CRuby requires
  def who = whoami
  def sib = viasib
  def selfsib = viaself
  def mine = own
  def poke_then_peek(v)
    poke(v)
    peek
  end
end

p M.new.read_after_write
p M.new.write_then_read
p M.new.who
p M.new.sib
p M.new.selfsib
p M.new.mine
# the module-side spellings keep working, on the module's own storage
p Rt.own
p Rt.whoami
p Rt.helper
Rt.poke(5)
p Rt.peek
# ...and the includer's instance is untouched by the module-side write
p M.new.poke_then_peek(1)
