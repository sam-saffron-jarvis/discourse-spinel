# `expr => pattern` is the one-arm `case expr; in pattern; end`: a class or
# value pattern raises NoMatchingPatternError on a miss, a nil in an object
# slot is not deconstructed, and nested and typed-hash patterns bind. The
# rightward form had an emitter of its own that checked none of this.
class Shape
  attr_reader :x
  def initialize(x = 1) = @x = x
  def deconstruct = [@x, 2]
  def deconstruct_keys(k) = {x: @x}
end
class Sub < Shape; end
def shape(f) = f ? Shape.new : nil
def try
  yield
rescue NoMatchingPatternError => e
  p e.class
end
v = shape(false)
try { v => Shape; p :matched }
try { v => [a, b]; p [a, b] }
try { v => {x:}; p x }
w = shape(true)
try { w => Shape; p :ok }
try { w => [a, b]; p [a, b] }
try { w => {x:}; p x }
try { w => Sub; p :bad }
try { w => Sub(x:); p :bad }
try { 5 => Integer; p :int }
try { 5 => String; p :bad }
try { [1, [2, 3]] => [a, [b, c]]; p [a, b, c] }
try { {name: "x", age: 3} => {name: String => nm}; p nm }
try { 3 => 1..5; p :range }
