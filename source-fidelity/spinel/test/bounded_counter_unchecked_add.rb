# spinel: int64
# An Integer local that only ever takes a small literal or `+=` / `-=` a
# small literal inside a container iterator's block cannot leave the word
# (an iterator's trip count is bounded by a length), so its adds are plain C
# adds with neither the overflow branch nor the nil test. The counter of a
# Ruby-written find_index was paying twice the C emitter's time on that one
# add. A counter written any other way, one stepping inside a while / until
# / loop, or one starting from a large literal keeps the checked add and
# raises where CRuby promotes.
def fi(a)
  idx = nil
  i = 0
  a.each do |x|
    if x > 5
      idx = i
      break
    end
    i += 1
  end
  idx
end
p fi([1, 3, 5, 7, 9])
n = 0
3.times { n += 2 }
[1, 2].each { |x| n -= 1 }
p n
k = 0
[[1, 2], [3]].each { |row| row.each { |v| k += 1 } }
p k
m = 0
1.upto(4) { |i| m += i > 2 ? 1 : 0 } rescue m = -1
p m
c = 9223372036854775806
begin
  2.times { c += 1 }
  p c
rescue RangeError => e
  puts "RangeError: #{e.message}"
end
w = 9223372036854775806
begin
  while w < 9223372036854775807
    w += 1
  end
  w += 1
  p w
rescue RangeError => e
  puts "RangeError: #{e.message}"
end
z = 0
loop do
  z += 1
  break if z == 3
end
p z
