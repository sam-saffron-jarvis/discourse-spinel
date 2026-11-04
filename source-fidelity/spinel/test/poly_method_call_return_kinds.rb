# A bound Method read out of a poly container is invoked through the legacy
# sp_int cast, and the bind site records how the C return boxes. optcarrot's
# CPU store table is this shape: `@store[addr][addr, value]` reaches
# Pulse#poke_0 (its last expression assigns an IntArray), Triangle#poke_0
# (a comparison, a bool), APU#poke_4017 (a poly) and CPU.poke_nop (void).
# Every one of these declined with "undefined method 'call' for an instance
# of Method" once the gate compared kinds; each kind now names its own box.
WAVE = [[0, 1, 0, 0], [0, 1, 1, 0]]

class Chip
  def initialize
    @form = [0]
    @flag = false
    @name = :none
    @child = nil
  end
  attr_reader :form, :flag
  # an IntArray return (the assigned value)
  def poke_form(_addr, data) = @form = WAVE[data & 1]
  # a bool return
  def poke_flag(_addr, data) = @flag = data > 3
  # a Symbol return
  def poke_name(_addr, data) = @name = data == 0 ? :zero : :some
  # nil: a void body
  def poke_nop(_addr, _data)
    @form = [_data]
    nil
  end
  # a poly return
  def poke_any(_addr, data) = data.odd? ? "odd" : data
  # a user-object return, a class without subclasses
  def poke_child(_addr, data) = @child = Leaf.new(data)
  # a user-object return, a class with a subclass (boxed by the id it carries)
  def poke_node(_addr, data) = data > 0 ? Sub.new(data) : Node.new(data)
  # a String-array return
  def poke_words(_addr, data) = @words = ["a"] * data
end

class Leaf
  def initialize(v) = @v = v
  def to_s = "Leaf(#{@v})"
end
class Node
  def initialize(v) = @v = v
  def to_s = "Node(#{@v})"
end
class Sub < Node
  def to_s = "Sub(#{@v})"
end

chip = Chip.new
store = [chip.method(:poke_form), chip.method(:poke_flag), chip.method(:poke_name),
         chip.method(:poke_nop), chip.method(:poke_any), chip.method(:poke_child),
         chip.method(:poke_node), chip.method(:poke_words)]

p store[0].call(0, 1)
p store[0][0, 0]
p chip.form
p store[1].call(1, 5)
p store[1].call(1, 2)
p store[2].call(2, 0)
p store[2][2, 7]
p store[3].call(3, 9)
p chip.form
p store[4].call(4, 3)
p store[4].call(4, 4)
puts store[5].call(5, 1).to_s
puts store[6].call(6, 1).to_s
puts store[6][6, 0].to_s
p store[7].call(7, 2)

# The same targets through Method#to_proc (the generic trampoline).
p store[1].to_proc.call(1, 8)
p store[2].to_proc.call(2, 1)
p store[0].to_proc.call(0, 1)

# The store loop optcarrot runs: every slot is a different kind.
i = 0
while i < store.length
  store[i][i, i]
  i += 1
end
p chip.flag
