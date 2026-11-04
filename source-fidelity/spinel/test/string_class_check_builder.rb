# A mutable String (one that has been appended to with <<) boxed into a value
# of more than one type, tested against the class String by case/when and by
# the pattern forms. On 646f1115 every line but the last prints the no-match
# answer (other, nomatch, no, false). It should print what the .expected holds.
def mk(k)
  t = +"q"
  3.times { |i| t << "r#{i}" }
  [t, k]
end

def pv(k) = mk(k)[0]

r = case pv(1)
    when Integer then "int"
    when String then "str"
    else "other"
    end
puts "when #{r}"

r = case mk(1)
    in [String => s, Integer] then "array #{s}"
    else "array nomatch"
    end
puts r

r = case pv(1)
    in String => s then "bind #{s}"
    else "bind nomatch"
    end
puts r

r = case pv(1)
    in String then "bare yes"
    else "bare no"
    end
puts r

puts "in #{pv(1) in String}"

r = case {name: pv(1)}
    in {name: String => n} then "hash #{n}"
    else "hash nomatch"
    end
puts r

r = case [1, pv(1), 2]
    in [*, String => s, *] then "find #{s}"
    else "find nomatch"
    end
puts r

# the binding's local already holds a String, so the pattern binds into a
# String slot rather than a boxed one
bound = "pre"
r = case mk(1)
    in [String => bound, Integer] then "typed #{bound} #{bound.length}"
    else "typed nomatch"
    end
puts r

# a plain String took the String arm already
r = case ["q#{1}", 1][0]
    in String => s then "plain #{s}"
    else "plain nomatch"
    end
puts r
