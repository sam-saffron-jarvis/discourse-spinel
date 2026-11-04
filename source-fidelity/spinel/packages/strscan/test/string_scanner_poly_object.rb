require "strscan"

# StringScanner is a native-bound class: a first-class object that flows
# through arrays, blocks, and nilable slots like any user object.
scanners = [StringScanner.new("aa bb"), StringScanner.new("xyz")]
scanners.each { |s| s.getch }
puts scanners[0].pos
puts scanners[1].rest

x = false ? nil : StringScanner.new("zz")
puts x.string

b = []
200.times { |i| b << StringScanner.new("s" * (i % 5 + 1)) }
GC.start
puts b[103].rest_size
