require "strscan"
# StringScanner#unscan raises StringScanner::Error when there is no match
# record to rewind to (double unscan, or unscan before any scan). A single
# valid unscan after a successful scan must still succeed.
# The class renders differently across implementations, so assert only via
# the message, is_a?, and which rescue clauses catch it.

# Positive case: one valid unscan after a scan works.
s = StringScanner.new("abc")
s.scan(/a/)
s.unscan
puts s.pos                       # 0

# Double unscan raises with CRuby's message.
s2 = StringScanner.new("abc")
s2.scan(/a/)
s2.unscan
begin
  s2.unscan
  puts "no error"
rescue StringScanner::Error => e
  puts "double: #{e.message}"
end

# unscan before any scan raises too.
s3 = StringScanner.new("abc")
begin
  s3.unscan
  puts "no error"
rescue StringScanner::Error => e
  puts "fresh: #{e.message}"
end

# StringScanner::Error < StandardError, so these rescue forms catch it.
s4 = StringScanner.new("abc")
begin
  s4.unscan
rescue StandardError => e
  puts "standard: #{e.message}"
end

s5 = StringScanner.new("abc")
begin
  s5.unscan
rescue => e
  puts "bare: #{e.message}"
end

s6 = StringScanner.new("abc")
begin
  s6.unscan
rescue StringScanner::Error => e
  puts "is StandardError? #{e.is_a?(StandardError)}"
end
