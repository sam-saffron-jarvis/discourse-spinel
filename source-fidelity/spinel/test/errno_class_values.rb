# Errno::* and the id-less exception classes (SystemCallError, LoadError) are
# first-class Class VALUES, carried by name. `when Errno::ENOENT` on a poly
# scrutinee used to compile to a constant false and fall silently to else --
# the quiet wrong answer this project's design promises never to give.
e = (File.open("/nonexistent") rescue $!)

case e
when Errno::EPERM then p 1
when Errno::ENOENT then p 2
else p 3
end

case e
when SystemCallError then puts "syscall"
else puts "else"
end

p(Errno::ENOENT === e)
p(Errno::EPERM === e)
p(e.is_a?(Errno::ENOENT))
p(e.is_a?(SystemCallError))
p(e.class == Errno::ENOENT)

# value positions: to_s, hash key (both by constant and by the runtime class)
p Errno::ENOENT.to_s
p SystemCallError.to_s
m = { Errno::ENOENT => 44, IOError => 5 }
p m[Errno::ENOENT]
p m[e.class]
arr = [Errno::ENOENT, IOError]
p arr.include?(e.class)

# a typed rescue variable dispatches the same way
begin
  File.open("/nonexistent")
rescue Errno::ENOENT => ex
  case ex
  when Errno::ENOENT then puts "typed ok"
  else puts "typed miss"
  end
end

# raising by the class value round-trips through rescue
begin
  raise Errno::ENOENT
rescue SystemCallError => ex2
  puts "raised #{ex2.class}"
end
