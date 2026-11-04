# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
# Issue #836: String * <huge> raises ArgumentError instead of
# segfaulting (the implicit malloc-NULL + memcpy chain).
begin
  puts "x" * (1 << 60)
rescue ArgumentError => e
  puts "huge: " + e.message
end
begin
  puts "x" * -1
rescue ArgumentError => e
  puts "neg: " + e.message
end
puts "ab" * 3
puts ("hi" * 0).inspect
