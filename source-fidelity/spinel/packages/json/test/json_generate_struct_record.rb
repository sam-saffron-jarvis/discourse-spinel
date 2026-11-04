# A Struct has no #to_json of its own in CRuby's json -- the method's owner for
# one is the Object module json mixes in -- so it serializes as Object#to_json
# does: `to_s.to_json`, a JSON string. Spinel answered a reflected hash of the
# members here until #4387; the expectations below are CRuby 4.0.4's.
require "json"

Rec = Struct.new(:id, :name)
puts JSON.generate(Rec.new(1, "alice"))
puts JSON.dump(Rec.new(2, "bob"))
puts JSON.generate(Rec.new)

Esc = Struct.new(:text)
puts JSON.generate(Esc.new("a\"b\nc\td"))
