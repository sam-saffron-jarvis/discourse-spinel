# CRuby's json is method dispatch: `require "json"` mixes #to_json into Object
# and into each core class, and JSON.generate calls it. So an object with no
# #to_json of its own lands on Object#to_json, which is `to_s.to_json` -- a JSON
# STRING. Struct has no override there either (the method's owner for a Struct
# is that Object module), which is why a struct reads as "#<struct S x=1>"
# rather than as its members.
#
# Spinel has no runtime method table to mix a module into, so it reaches the
# same two answers by a different road: the user arm is the hook the generated
# program installs, and the fallback renders the class's own #to_s (or CRuby's
# default #<Name:0x..>). It used to reflect an object into a hash of its
# members, so JSON.generate(a struct) answered {"x":1}, and a plain object with
# no reflection answered null, which is not any Ruby's answer (#4387).
require "json"

class Hooked
  def to_json(*) = '"HOOKED"'
end
class WithToS
  def to_s = "PLAIN-TO-S"
end
S = Struct.new(:x, :y)

# a class's own #to_json wins, through both doors
p Hooked.new.to_json
p JSON.generate(Hooked.new)

# everything else is its #to_s, as a JSON string
p WithToS.new.to_json
p JSON.generate(WithToS.new)
p S.new(1, 2).to_json
p JSON.generate(S.new(1, 2))

# and inside a container, where the element is boxed
p JSON.generate([Hooked.new, S.new(3, 4)])
p({ "k" => S.new(5, 6) }.to_json)

# Struct#to_s IS Struct#inspect in CRuby, and a BOXED struct used to miss that
# and render #<S:0x..> -- the same fallback this fix routes through.
def boxed(v) = ({ "v" => v, "label" => "x" })["v"]
b = boxed(S.new(7, 8))
p b.to_s
p "#{b}"
p b.inspect

# the core classes are unaffected
p({}.to_json)
p [].to_json
p({ "a" => [1, { "b" => 2 }] }.to_json)
p "s".to_json
p 1.to_json
p nil.to_json
