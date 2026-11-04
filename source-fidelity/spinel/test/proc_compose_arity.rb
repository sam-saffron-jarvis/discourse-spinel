# A composed call passes its own argument count through to the first-called
# proc: none at all reaches a zero-arity lambda, and an optional parameter
# takes its default rather than a phantom argument.
f0 = -> { 7 }
inc = ->(x) { x + 1 }
p((f0 >> inc).call)

opt = ->(x = 2) { x + 1 }
dbl = ->(x) { x * 2 }
p((opt >> dbl).call)
p((opt >> dbl).call(10))

# A plain proc adjusts to the composed call's arguments -- leniency survives
# composition in both positions.
pair = proc { |a, b| [a, b] }
p((pair >> pair).call(5))
p((inc >> pair).call(1))

# A lambda stays strict in both positions.
two = ->(a, b) { a + b }
begin
  (two >> inc).call(9)
rescue ArgumentError => e
  p [e.class, e.message]
end
begin
  (inc >> two).call(9)
rescue ArgumentError => e
  p [e.class, e.message]
end

# A variadic first-called lambda takes whatever the composed call carries.
count = ->(*xs) { xs.length }
p((count >> inc).call)
p((count >> inc).call(:a, :b, :c))

# << composes the other way round, and a hash proc is a lambda whose
# 1-arity a composed call enforces.
p((dbl << inc).call(4))
hp = { a: 10 }.to_proc
p hp.lambda?
begin
  hp.call
rescue ArgumentError => e
  p [e.class, e.message]
end
begin
  hp.call(:a, :a)
rescue ArgumentError => e
  p [e.class, e.message]
end
begin
  (hp >> inc).call
rescue ArgumentError => e
  p [e.class, e.message]
end
p((hp >> inc).call(:a))

# Composing something that can never answer #call refuses up front, after
# both operands evaluate (receiver first).
begin
  inc >> 1
rescue TypeError => e
  p [e.class, e.message]
end
begin
  inc << "s"
rescue TypeError => e
  p [e.class, e.message]
end
begin
  inc.curry >> 1
rescue TypeError => e
  p [e.class, e.message]
end
order = []
begin
  (order << :recv; inc) >> (order << :arg; nil)
rescue TypeError
end
p order
