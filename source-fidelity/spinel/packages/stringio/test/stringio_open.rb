require "stringio"

# Block form returns the block's value, with the io bound to the param.
r = StringIO.open("foo") { |f| f.read }
p r

# The returned value is a first-class string.
puts r.upcase
puts r.length

# Statement form (block result discarded).
StringIO.open("bar") { |f| puts f.read }

# Block whose value is not a string.
n = StringIO.open("hello") { |f| f.read.length }
p n

# The common write-into-buffer idiom: build text, return io.string.
s = StringIO.open { |io| io.puts "hello"; io.puts "world"; io.string }
print s

# No-block form returns the constructed io.
io = StringIO.open("hi")
p io.read

# Nested inside another block.
["a", "bb"].each do |x|
  v = StringIO.open(x) { |f| f.read }
  puts v.upcase
end
