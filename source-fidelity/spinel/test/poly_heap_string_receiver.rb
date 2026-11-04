# A poly value holding a HEAP String (the shared-string handle built by in-place
# `<<`) is a String, and every String method reached through a poly receiver has
# to say so. The dispatches guarded only the IMMEDIATE representation
# (tag == SP_TAG_STR), so a heap String either raised NoMethodError naming
# String -- for a method String has -- or, where the guard was a silent
# fallthrough, answered nil or false.

arr = [""]
arr.pop
s = +""
s << "a;b c"
arr.push(s)

arr.each do |line|
  # raised: the arm read .v.s behind a single-armed tag guard
  p line.split(";", 2)
  p line.split
  p line.split(/;/)
  p line.start_with?("a")
  p line.end_with?("c")
  p line.match?(/b/)
  p line.succ
  p line.to_sym

  # answered silently wrong: the guard fell through to a nil/false default
  p line.include?(";")
  p line[1]
  p line[0, 3]
  p line[0..2]
  p line[-1]
  p line["b"]
  p line["zz"]
  p line.slice(1)

  # already right, pinned so the family stays whole
  p line.upcase
  p line.strip
  p line.chars
  p line.index(";")
  p line.sub(";", ":")
  p line.scan(/\w+/)
  p line.partition(";")
  p line == "a;b c"
end

# equal strings hash alike whichever representation they are in, so one is a
# key for the other
k = +""
k << "key"
h = {}
h[k] = 1
p h["key"]
p h.key?(k)
p k.hash == "key".hash

keys = [""]
keys.pop
keys.push(k)
p({"key" => 9}[keys[0]])
p keys.include?("key")
p keys.index("key")
