# A receiverless Kernel wrapper (`method(:Integer)`, synthesized as
# `def __bam_N(__bam_r) = Integer(__bam_r)`) had its parameter pinned to
# Integer whatever the program passed, so its legacy signature could never
# match a String argument, and a builtin's wrapper carries no thunk: called
# out of a boxed slot beside a user class that owns `call`, the Method raised
# NoMethodError in the default mode. The parameter now takes the one kind
# the program's dynamic calls pass when the signature carries it (a String,
# a Symbol, a bool, a typed array); the promote mode's poly signature is
# unchanged. Every dynamic call below passes a String, on purpose: the
# evidence is a union per position over the whole program.

class Handler
  def call(x) = x * 100
end

puts [method(:Integer), Handler.new][0].call("42")
p [method(:String), Handler.new][0].call("s")
p [method(:Integer)][0].call("7")
p method(:Integer).call("8")
p method(:Integer).to_proc.call("9")
[method(:p), Handler.new][0].call("x")
[method(:puts), Handler.new][0].call("y")
conv = [method(:Integer), method(:String)]
p conv[0].call("10")
p conv[1].call("z")
