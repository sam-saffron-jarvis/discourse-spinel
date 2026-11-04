# A boxed Enumerator answers its own #size, not a length (each_slice's was 0)
begin; raise "x"; rescue => e; end
e = [1, 2, 3, 4, 5].each_slice(2)
p e.next
p e.size
f = [1, 2, 3].each
p f.next
p f.size
