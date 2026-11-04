# push / append / unshift answer the RECEIVER; through a boxed receiver the
# poly dispatch declared a result temp its arm never wrote, so the answer was
# the temp's zero seed (#4320), and unshift had no arm at all.
g = ->(acc) { acc.push(1) }
p g.call([])
p g.call([5])
p ->(acc) { acc.append(1) }.call([])
p ->(acc) { acc.unshift(1) }.call([])
p ->(acc) { acc.unshift(1) }.call([5])
p ->(acc) { acc.prepend(1) }.call([9])
p ->(acc) { acc.unshift(1, 2) }.call([9])
p ->(acc) { acc.push(1, 2) }.call([])
p ->(acc) { acc << 1 }.call([])
p ->(acc) { acc.concat([1]) }.call([])
p ->(acc) { acc.insert(0, 1) }.call([])

# the other array kinds take the same arms
p ->(acc) { acc.push("b") }.call(["a"])
p ->(acc) { acc.unshift("b") }.call(["a"])
p ->(acc) { acc.push(1.5) }.call([0.5])
p ->(acc) { acc.unshift(1.5) }.call([0.5])

# chained, so the answer is used rather than discarded
p ->(acc) { acc.push(1).push(2) }.call([])
p ->(acc) { acc.unshift(1).size }.call([])
