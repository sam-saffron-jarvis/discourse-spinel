# A lambda answered by a lambda is invoked through the type-erased proc ABI,
# so its own parameters must read the boxed side-channel (#4328), and the
# receiver of the second `.call` has to be evaluated before that channel is
# written or it clears the argument it is about to read.
o = ->(step) { ->(acc) { step.call(acc) } }
p o.call(->(a) { a + [9] }).call([0])
p o.call(->(a) { a + 1 }).call(2)
p o.call(->(a) { a + 0.5 }).call(1.25)
p o.call(->(a) { a + "b" }).call("a")
p o.call(->(a) { a.merge({ y: 2 }) }).call({ x: 1 })

# a method in place of the outer lambda takes the same path
def outer
  ->(step) { ->(acc) { step.call(acc) } }
end
p outer.call(->(a) { a + [9] }).call([0])

# a `lambda do ... end` outer, and a guard `return` in the innermost one: the
# Proc argument rides the sp_int slot of the bound-method arm (#4329)
def taking
  lambda do |step|
    lambda do |acc|
      return [:stop, acc] if acc > 2

      step.call(acc)
    end
  end
end
p taking.call(->(a) { a + 1 }).call(0)
p taking.call(->(a) { a + 1 }).call(5)
