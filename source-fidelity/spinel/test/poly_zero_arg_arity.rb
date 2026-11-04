# A zero-argument call on a poly receiver whose method needs arguments raises
# ArgumentError, as CRuby does. The zero-argument dispatch kept an arm only
# when nrequired was 0, so such an arm was dropped and the call answered
# NoMethodError; nrequired is also an index, not a count, so a leading
# optional (`def h(a = {}, c)`) read as needing two.

class A
  def h(a = {}, c) = [:A, a, c]
end

class B
  def h(a = {}, c) = [:B, a, c]
end

[A.new, B.new].each do |o|
  begin
    p o.h
  rescue ArgumentError => e
    p e.message
  end
end
