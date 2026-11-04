# A method whose value is `Hash.new(default)` takes the variant its callers
# narrow it to. The tail-position rule that gives an otherwise-unnarrowed one
# the widest variant (#4291) must fill in an unknown, not override a settled
# type: it widened every such helper to a poly hash (#4304).
def str_hash
  Hash.new("")
end

def int_hash
  Hash.new(0)
end

# nothing narrows this one, so the widest variant is the right answer
def free_hash
  Hash.new(0)
end

s = str_hash
s["k"] = "v"
i = int_hash
i["n"] = 3
puts s["k"] + i["n"].to_s + free_hash.size.to_s
