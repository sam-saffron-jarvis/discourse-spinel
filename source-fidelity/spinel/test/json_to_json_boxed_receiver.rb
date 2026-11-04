# CRuby's json defines #to_json on every core class, and the value that most
# needs it is the one JSON.parse just answered -- which spinel types as POLY,
# since a document can be an Array or a Hash. That was the one type the rule
# declined, so `JSON.parse(s).to_json` raised NoMethodError (#4385).
#
# Declining a boxed receiver never routed it to a user method: only a STATIC
# object type can be dispatched at compile time. A boxed one goes through the
# generator, and a user class's own #to_json still wins there -- sp_json_val
# asks sp_obj_to_json_fn first, exactly as CRuby's json does. Both halves are
# below: a boxed Pt serializes through its own method, and so does a typed one.
require "json"

# the report: a value that came out of JSON.parse
puts JSON.parse('{"name":"read_file","arguments":{"path":"/tmp/foo.txt"}}').to_json
puts JSON.parse('[{"a":1},{"b":[2,3]}]').to_json
puts JSON.parse('[1,2.5,"s",true,false,null]').to_json

# a poly receiver from a heterogeneous container
box = { "arr" => [1, 2], "hash" => { "k" => "v" }, "str" => "s",
        "int" => 7, "flt" => 1.5, "t" => true, "n" => nil, "label" => "x" }
%w[arr hash str int flt t n].each { |k| puts box[k].to_json }

# a poly receiver holding a user object that defines its own to_json
class Pt
  def initialize(x, y); @x = x; @y = y; end
  def to_json(*) = "{\"pt\":[#{@x},#{@y}]}"
end
holder = { "p" => Pt.new(1, 2), "label" => "x" }
puts holder["p"].to_json

# a typed receiver of the same class still dispatches to the user method
q = Pt.new(3, 4)
puts q.to_json

# nested: a user object inside a parsed structure re-serialized
puts({ "outer" => Pt.new(5, 6) }.to_json)
