# `recv.send(name)` with a runtime name lowers to a static dispatch over the
# program's symbol and string literals. That set used to be capped at 128
# distinct literals of ANY shape, so a program with 129 unrelated strings lost
# the lowering entirely and the refusal blamed a runtime name (#4649). The
# candidates are now the literals shaped like a method name, ranked (defined
# in the program, then called somewhere, then the rest) before the cap.
def calc(method, a, b)
  a.send(method, b)
end

p calc(:+, 1, 2)
p calc(:*, 3, 4)

LABELS = %w[
  l000 l001 l002 l003 l004 l005 l006 l007 l008 l009 l010 l011 l012 l013
  l014 l015 l016 l017 l018 l019 l020 l021 l022 l023 l024 l025 l026 l027
  l028 l029 l030 l031 l032 l033 l034 l035 l036 l037 l038 l039 l040 l041
  l042 l043 l044 l045 l046 l047 l048 l049 l050 l051 l052 l053 l054 l055
  l056 l057 l058 l059 l060 l061 l062 l063 l064 l065 l066 l067 l068 l069
  l070 l071 l072 l073 l074 l075 l076 l077 l078 l079 l080 l081 l082 l083
  l084 l085 l086 l087 l088 l089 l090 l091 l092 l093 l094 l095 l096 l097
  l098 l099 l100 l101 l102 l103 l104 l105 l106 l107 l108 l109 l110 l111
  l112 l113 l114 l115 l116 l117 l118 l119 l120 l121 l122 l123 l124 l125
  l126
].freeze

p LABELS.length

class Vec
  attr_reader :x, :y
  def initialize(x, y)
    @x = x
    @y = y
  end
  def calculate_each(method, other)
    Vec.new(x.send(method, other), y.send(method, other))
  end
  def to_s = "(#{x}, #{y})"
end
puts Vec.new(1, 2).calculate_each(:*, 3)
puts Vec.new(1, 2).calculate_each(:+, 3)
begin
  1.send(:nosuchmethod, 2)
rescue NoMethodError => e
  puts e.message
end
