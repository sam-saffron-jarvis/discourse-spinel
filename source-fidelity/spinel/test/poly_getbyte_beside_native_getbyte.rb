# A native class (StringIO) binds a zero-argument `getbyte`. `s.getbyte(i)`
# on a String that widened to poly must not take that binding's Integer as
# its type: the emission is the builtin sp_poly_getbyte, whose value is
# boxed (nil out of range). The local it fills is then sized for the boxed
# value, and `.chr` on it unboxes. (#4432)
require "stringio"

class Tok
  def initialize(a)
    @a = a
  end

  def split(sep)
    [self]
  end

  def to_s
    @a
  end
end

def url_decode(s)
  return s unless s.include?("%") || s.include?("+")
  out = String.new
  i = 0
  n = s.bytesize
  while i < n
    b = s.getbyte(i)
    if b == 43
      out << 32
      i += 1
    elsif b == 37 && i + 2 < n
      hex = s.getbyte(i + 1).chr + s.getbyte(i + 2).chr
      out << hex.to_i(16)
      i += 3
    else
      out << b
      i += 1
    end
  end
  out
end

def parse(input)
  return if input.empty?
  input.split("&").each do |pair|
    next if pair.empty?
    eq = pair.index("=")
    raw_key = eq.nil? ? pair : pair[0, eq]
    raw_val = eq.nil? ? "" : pair[(eq + 1)..]
    puts url_decode(raw_key) + "=" + url_decode(raw_val)
  end
  nil
end

puts url_decode("a%20b+c")
h = { "q" => "x%21y+z=1&w=%41", "n" => 1 }
parse(h["q"])
p Tok.new("z").split("&").size
io = StringIO.new("AB")
p io.getbyte
