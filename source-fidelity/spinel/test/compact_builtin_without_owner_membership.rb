# Compact headers create real members even without a standalone reopening
# of the builtin owner. Exact membership must not expose that leaf through
# another builtin; literal double underscores are part of the Ruby name.
class String::Compact__Marker
  def self.answer = 41
end
module Comparable::CompactOpen
end
p String::Compact__Marker.answer
p String::Compact__Marker.name
p defined?(::String::Compact__Marker)
p Comparable::CompactOpen.name
p defined?(Comparable::CompactOpen)
begin
  StandardError::Compact__Marker
rescue NameError
  puts "wrong exception owner rejected"
end
begin
  Hash::CompactOpen
rescue NameError
  puts "wrong class owner rejected"
end
p defined?(Array::CompactOpen)
class OnlyAtTop; end
begin
  Comparable::OnlyAtTop
rescue NameError
  puts "top-level fallback rejected"
end
