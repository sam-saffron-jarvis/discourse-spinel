# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
r = Random.new(2**70)
v = r.rand(100)
p v >= 0 && v < 100
p Random.new(2**70).rand(1000) == Random.new(2**70).rand(1000)
p Random.new(2**70 + 1).rand(2**40) != Random.new(2**70 + 2).rand(2**40)
p (Random.new(2**70).rand(100) rescue $!.class).is_a?(Integer)
