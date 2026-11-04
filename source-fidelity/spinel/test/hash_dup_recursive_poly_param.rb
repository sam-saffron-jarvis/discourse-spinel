# Hash#dup / #clone on a parameter typed poly by a recursive call cycle. The
# boxed hash went out of sp_poly_dup as-is, so the copy aliased the caller's
# hash and every write through it landed in the original (#4646). A boxed
# hash now copies like a boxed array does, variant by variant, and clone
# keeps the frozen bit.
def parse(arg)
  return parse(arg[0]) if arg.is_a?(Array)

  d = arg.dup
  p d.equal?(arg)
  d["y"] = 9
  d
end

h = { "x" => 5 }
p parse(h)
p h
p parse([h])
p h

def parse_sym(arg)
  return parse_sym(arg[0]) if arg.is_a?(Array)

  d = arg.dup
  d[:y] = 9
  d
end

s = { x: 5 }
p parse_sym(s)
p s

def parse_int(arg)
  return parse_int(arg[0]) if arg.is_a?(Array)

  d = arg.clone
  d[2] = 20
  d
end

i = { 1 => 10 }
p parse_int([i])
p i

def cl(arg)
  return cl(arg[0]) if arg.is_a?(Array)

  arg.clone
end
f = { "k" => 1 }.freeze
p cl(f).frozen?
p cl([f]).equal?(f)
