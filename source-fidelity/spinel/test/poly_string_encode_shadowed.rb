# String#encode on an untyped receiver when a user class also owns `encode`:
# the poly dispatch switch had a case for the user class and a raising
# default, and a genuine String fell to it -- "undefined method 'encode' for
# an instance of String" once Active Storage's Variation#encode existed
# (#4452). The TAG_STR receiver takes the same transcode the typed receiver
# takes, keywords included.
class Variation
  def initialize(w); @w = w; end
  def encode
    "limit-" + @w.to_s
  end
end

class Box
  def initialize; @h = { "content" => "caf\xE9".b }; end
  def [](k); @h.fetch(k.to_s, nil); end
end

def sanitize(content)
  content.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "")
end

puts Variation.new(3).encode
puts sanitize(Box.new["content"])

# the receiver widened through a slot that also held the user object
slot = [Variation.new(7), "plain".b]
puts slot[1].encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "?")
puts slot[0].encode
puts slot[1].encode("UTF-8")
begin
  [42][0].encode("UTF-8")
rescue NoMethodError => e
  puts e.message
end
