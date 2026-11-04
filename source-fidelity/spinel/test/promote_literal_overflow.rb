# spinel: int64
# Two integer literals whose sum, difference or product leaves the word
# promote under --int-overflow=promote like any other operands (#4968):
# typed from the operands alone they took the raising int helper.
puts 9223372036854775807 + 1
puts -9223372036854775807 - 2
puts 3037000500 * 3037000500
puts 40 + 2
puts 9223372036854775808
x = 9223372036854775807
puts x + 1
puts 3 * 4 - 5
