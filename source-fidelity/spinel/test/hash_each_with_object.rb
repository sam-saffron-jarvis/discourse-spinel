# Hash#each_with_object yields the [k, v] pair and the memo: the destructured
# form `|(k, v), memo|` takes the pair apart. A flat `|k, v, memo|` gets the
# pair as k and the memo as v, so memo is nil, exactly as CRuby has it; the
# C emitter this used to run on took the flat form as a spinel extension,
# and its Ruby definition (builtins/enumerable.rb) does what Ruby does.

h = {a: 1, b: 2, c: 3}
result = h.each_with_object([]) { |(k,v), memo| memo << v * 10 }
puts result.inspect

# Flat 3-param form: the memo is nil, as in CRuby
begin
  h.each_with_object([]) { |k, v, memo| memo << v * 100 }
rescue NoMethodError => e
  puts e.message
end
pairs = h.each_with_object([]) { |pair, memo| memo << pair }
puts pairs.inspect
