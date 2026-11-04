# A value built for the JSON walk stays rooted for the walk. The hash a Struct
# or a Data reflects into, and the document pretty_generate re-reads out of a
# user #to_json answer, are each the walk's only reference to themselves while
# the walk allocates a GC string for every key it reaches, and for every
# numeric, string or symbol scalar -- unrooted, the walk reads them back after
# a collection has already freed them.
require "json"

# A member whose INFERRED type is poly -- here, because pick can answer an Array,
# a Hash or a String -- keeps its container through the reflection; every other
# container type reflects as null. That is the shape that makes the walk recurse
# under the value being rooted, so it is the shape worth testing.
Z = Struct.new(:m, :n)
def pick(i)
  return [1, 2, "three"] if i == 0
  return { "k" => "v" } if i == 1
  "plain"
end
doc = ["a", Z.new(pick(0), pick(1)), "b"]

# The members really do reach the walk: without this line the arms below would
# still print true if the reflection went back to answering null for them.
puts JSON.generate(doc).include?("three")

# Spinel reflects a Struct into a JSON object where CRuby renders its to_s, so
# what the three arms below pin is that every answer is the SAME answer:
# unrooted, the reflected hash is freed while the walk is still reading it.
first = JSON.generate(doc)
flat_stable = true
2000.times { flat_stable = false if JSON.generate(doc) != first }
puts flat_stable

first_pretty = JSON.pretty_generate(doc)
pretty_stable = true
500.times { pretty_stable = false if JSON.pretty_generate(doc) != first_pretty }
puts pretty_stable

# a Data reflects through the same hook
D = Data.define(:x, :y)
ddoc = ["a", D.new(x: pick(0), y: pick(2)), "b"]
first_data = JSON.generate(ddoc)
data_stable = true
2000.times { data_stable = false if JSON.generate(ddoc) != first_data }
puts data_stable

class Point
  def initialize(x, y)
    @x = x
    @y = y
  end

  def to_json(*args)
    { x: @x, y: @y }.to_json(*args)
  end
end

# test/user_to_json_nested.rb already pins this same Point through the same walk;
# new here are the siblings and the loop, so a collection lands inside the
# re-read walk. A #to_json that forwards its state is the case where the re-read
# agrees with CRuby, so the document itself is CRuby's.
reparsed = nil
2000.times { reparsed = JSON.pretty_generate(["x", Point.new(5, 6), "y"]) }
puts reparsed
