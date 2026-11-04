# tr/sub/gsub/squeeze and ljust/center/rjust on a poly receiver have their
# own emitters for a String that arrives boxed. They converted the receiver
# with to_s, so an Integer or nil in the slot answered a plausible string
# (`42.tr("4", "x")` gave "x2") where Ruby raises NoMethodError (#4493).
# The receiver is unboxed as a String, and anything else raises.
slots = { "s" => "sql", "i" => 42, "n" => nil, "f" => 1.5 }

def try
  yield.inspect
rescue NoMethodError => e
  "NoMethodError (#{e.message[/for .*/]})"
end

puts try { slots["s"].tr("s", "S") }
puts try { slots["s"].sub("s", "S") }
puts try { slots["s"].gsub("s", "S") }
puts try { slots["s"].squeeze("q") }
puts try { slots["s"].ljust(5, ".") }
puts try { slots["s"].center(5, ".") }
puts try { slots["s"].rjust(5) }
puts try { slots["i"].tr("4", "x") }
puts try { slots["i"].sub("4", "x") }
puts try { slots["i"].gsub("4", "x") }
puts try { slots["i"].squeeze("4") }
puts try { slots["i"].ljust(4, ".") }
puts try { slots["i"].center(4, ".") }
puts try { slots["i"].rjust(4) }
puts try { slots["n"].tr("a", "b") }
puts try { slots["n"].ljust(4) }
puts try { slots["f"].gsub(".", ",") }
puts try { slots["f"].center(6) }
