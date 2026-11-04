# A Ruby-side def on a native class (IO::Buffer#read / #write, which take an
# IO argument) is not a poly-dispatch candidate, so it must not widen what the
# poly-IO arm answers for the same names on a boxed IO handle: `io.write`
# stayed sp_int and `io.read` its C string, both matching the arm's raw
# values. Counting it typed these poly while the arm answered raw C, and the
# program did not build -- read in every mode, write under promote.
IO::Buffer.new(8)
io = [$stdout, nil][0]
n = 0
2.times { n += io.write("x") }
p n
r = [$stdin, nil][0]
s = begin
  r.read(4)
rescue EOFError
  ""
end
p s
