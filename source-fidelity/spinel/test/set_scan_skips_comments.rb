# The implicit `require "set"` is decided by scanning the source for the Set
# constant, and the scan used to run over the whole file rather than over the
# code: the word in this very comment would have spliced set.rb in and taken a
# hello-world's generated C from 41 lines to 959 (#4411). On one real program
# it did worse than waste, because linking Set changed the lowering of an
# unrelated closure and with it the answer (#4410).
#
# Every line below is a place the word appears without being a reference, plus
# the two places it IS one: an interpolation inside a string is code, and so is
# `.to_set`. A false negative would drop a require the program needs, so the
# skipping is conservative and the arms that must still link are here to say so.
puts "Set in a string"
puts 'Set in a single-quoted string'
puts "a Settings-like word: Settings OffSet"

=begin
Set in a block comment
=end

require "set"
s = Set.new([1, 2, 3])
puts "size #{s.size}"
puts "interpolated #{Set.new([4, 5]).size}"
puts "to_set #{[1, 2, 2, 3].to_set.size}"
