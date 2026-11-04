# Symbol#<=> answers -1/0/1 on boxed Symbols, and a local that becomes
# boxed after looking like a Symbol is still compared as a Symbol
k = nil
f = false
[:z, :a].each do |key|
  if f
    p(key <=> k)
  else
    k = key
    f = true
  end
end
p [nil, :b, :a].min_by { |x| x.nil? ? :z : x }
p [:m, nil].max_by { |x| x.nil? ? :a : x }
