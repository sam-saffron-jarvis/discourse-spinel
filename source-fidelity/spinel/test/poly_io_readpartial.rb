# IO#readpartial on a boxed (poly) IO handle: the poly-IO arm had no arm for
# the name and answered NoMethodError where CRuby reads. Both forms: the plain
# count, and (count, outbuf) which fills the buffer, rebinds it, and RETURNS
# it (same #3336 semantics as the typed arm); EOF raises EOFError.
io = [$stdin, nil][0]
p io.readpartial(4)
buf = +"zzzzzzzz"
r = io.readpartial(2, buf)
p [r, buf, r.equal?(buf)]
begin
  io.readpartial(4)
rescue EOFError
  puts "eof"
end
begin                           # count-less and over-long forms are refused
  io.readpartial                # before the stream is touched
rescue ArgumentError => e
  puts e.message
end
begin
  io.readpartial(1, +"b", :extra)
rescue ArgumentError => e
  puts e.message
end
