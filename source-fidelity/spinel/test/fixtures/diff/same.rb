# Both runtimes agree: the gate expects exit 0 from `spinel diff`.
h = { "a" => 1, b: [2, 3] }
p h, h.size
puts Object.new.inspect.sub(/0x\h+/, "X")
puts [3, 1, 2].sort.inspect
