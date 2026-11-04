# A mutable-string local written inside Array.new's block, where a nested
# block appends to it. The block's non-tail statements are emitted as
# expressions, and the expression form of a local write put the raw
# const char * into the local's sp_String * slot: the C did not compile.

# 1. the reported shape
x = Array.new(1) do |r|
  line = +""
  2.times { line << "a" }
  line
end
puts x[0]

# 2. String.new, several rows, the row index appended
rows = Array.new(3) do |i|
  s = String.new
  (i + 1).times { s << i.to_s }
  s
end
p rows

# 3. two locals, one aliasing the other: a mutation shows through both
pairs = Array.new(2) do |i|
  a = +"x"
  b = a
  2.times { b << "y" }
  a + "|" + b
end
p pairs

# 4. the write used as a value (a condition)
buf = nil
if (buf = +"abc")
  3.times { buf << "d" }
end
p buf
