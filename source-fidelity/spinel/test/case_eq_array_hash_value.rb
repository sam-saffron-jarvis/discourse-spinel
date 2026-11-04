# Array#=== and Hash#=== are Object#===, which is ==: a value compares by
# value. `[1,2] === [1,2]` raised NoMethodError on a typed receiver (the
# same comparison through a poly value already answered), and `case arr
# when [1,2]` fell through to the else arm because the when comparison had
# no arm for an array or hash subject.
def check(pat, x) = (pat === x rescue "raised: #{$!.class}")

arr = [1, 2]
h = { a: 1 }
p(arr === arr)
p(arr === [1, 2])
p(arr === [1, 3])
p(h === { a: 1 })
p(h === { a: 2 })
p(["x", "y"] === ["x", "y"])
p([1.5] === [1.5])
p([[1], [2]] === [[1], [2]])

# through a method's parameters, which is where it already worked
p check([1, 2], [1, 2])
p check({ a: 1 }, { a: 1 })

case arr
when [1, 3] then p "wrong"
when [1, 2] then p "matched"
else p "fell through"
end

case h
when({ a: 2 }) then p "wrong"
when({ a: 1 }) then p "matched hash"
else p "fell through"
end

# a class arm and a mismatched-type arm still behave
case arr
when Array then p "class arm"
else p "no"
end

case arr
when "s" then p "wrong"
else p "fell through"
end
