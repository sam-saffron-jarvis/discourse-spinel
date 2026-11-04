# A fold over the Enumerator from each_with_index / each_index reads [value,
# index] pairs: without the to_a hop a seedless reduce assigned a pair into an
# sp_int and the C compiler refused it, and one answering the accumulator
# answered 0 (#4321).
p [10, 20].each_with_index.reduce { |acc, pair| pair }
p [10, 20].each_with_index.reduce { |acc, pair| acc }
p [10, 20].each_with_index.inject { |acc, pair| pair }
p [10, 20].each_index.reduce { |acc, i| i }
p [10, 20].each_with_index.reduce([]) { |acc, pair| acc << pair }
p [10, 20].each_with_index.to_a.reduce { |acc, pair| pair }
p [10, 20].reduce { |acc, x| acc + x }
