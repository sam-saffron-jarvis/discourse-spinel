require "stringio"

# StringIO is a native-bound class: a first-class object that flows through
# arrays, blocks, nilable slots, and survives GC like any user object.
ios = [StringIO.new("aa"), StringIO.new("bbb")]
ios.each { |io| io.read }
puts ios[0].pos
puts ios[1].pos

x = false ? nil : StringIO.new("z")
puts x.string

b = []
500.times { |i| b << StringIO.new("x" * (i % 7 + 1)) }
GC.start
puts b[300].size
puts b[0].size
