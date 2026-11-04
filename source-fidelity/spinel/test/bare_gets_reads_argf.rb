# A bare `gets` reads the next line of ARGF, as `ARGF.gets` does: stdin
# here, as the test names no files. At end of input it answers nil. On
# 855c69a9 the program does not build: the `while` modifier's `gets` is
# reported as an undefined local variable or method, and without that line
# the first `gets` raises NameError at run time.
class Reader
  def line = gets
end
x = gets
p x
p gets().chomp
p Reader.new.line
p [1].map { gets&.chomp }
n = 0
n += 1 while gets
p n
p gets
