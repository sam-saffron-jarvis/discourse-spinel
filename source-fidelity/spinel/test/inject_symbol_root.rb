# The blockless symbol fold, `inject(:+)` over an array of Strings, copies its
# receiver into a C temporary and reads the next element out of it on every
# turn, while the concatenation between two turns allocates a fresh String.
# Every receiver here is a method's answer, so nothing but that temporary holds
# it; the accumulator is likewise reassigned from each fresh String and read
# back by the next turn. Either one collected mid-walk shows up as a short
# answer, a different tail or a crash, never as a passing test. The
# local-receiver arm is the control: a local is itself a root. The Integer and
# Float folds allocate nothing between turns and are here to show that arm's
# answers are unchanged.

ENTRIES = 40
BIG = 3000

def make_array
  (1..ENTRIES).map { |i| "a#{i}" }
end

def make_big
  (1..BIG).map { |i| "s#{i}-" }
end

def make_ints
  (1..ENTRIES).map { |i| i * 3 }
end

def make_floats
  (1..ENTRIES).map { |i| i * 0.5 }
end

def make_empty
  [].map { |i| "x#{i}" }
end

def show(label, s)
  if s.nil?
    puts "#{label} nil"
  else
    puts "#{label} len=#{s.length} head=#{s[0, 6]} tail=#{s[-6, 6]}"
  end
end

# --- the four spellings of the symbol fold over a method's answer ---

show("inject sym", make_array.inject(:+))
show("reduce sym", make_array.reduce(:+))
show("inject block-sym", make_array.inject(&:+))
show("reduce block-sym", make_array.reduce(&:+))

# --- seeded folds: the seed is the first accumulator ---

show("inject seed sym", make_array.inject("z", :+))
show("reduce seed block-sym", make_array.reduce("z", &:+))

# --- a long walk, so the concatenations reach a collection on a plain build ---

show("inject big", make_big.inject(:+))
show("inject big seed", make_big.inject("Z", :+))

# --- edge shapes: empty and single-element receivers ---

show("inject empty", make_empty.inject(:+))
show("inject empty seed", make_empty.inject("e", :+))
show("inject one", make_array.first(1).inject(:+))

# --- the arms this fold shares: Integer and Float folds, unchanged ---

puts "inject ints #{make_ints.inject(:+)} #{make_ints.reduce(:-)}"
puts "inject floats #{make_floats.inject(:+)} #{make_floats.reduce(2.0, :+)}"

# --- control: the same fold over a receiver held in a local ---

held = make_array
show("control inject sym", held.inject(:+))
held = make_big
show("control inject big", held.inject(:+))
