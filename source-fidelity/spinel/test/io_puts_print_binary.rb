# IO#puts and IO#print sized their operand with strlen, so a String with an
# embedded NUL was cut at the first one -- the same defect IO#write had before
# #3540 and IO#pwrite before its own fix. A String carries its byte count, so
# the emitter picks the binary-safe entry for one and keeps the strlen entry
# for a converted value, exactly as the write arm does. Both the typed and the
# boxed-receiver forms.
path = "spinel_puts_bin_#{Process.pid}.tmp"
s = "ab\x00cd"

io = File.open(path, "w"); io.print(s);        io.close; p File.binread(path).bytes
io = File.open(path, "w"); io.puts(s);         io.close; p File.binread(path).bytes
io = File.open(path, "w"); io.print(s, s);     io.close; p File.binread(path).bytesize
io = File.open(path, "w"); io.puts(s, s);      io.close; p File.binread(path).bytesize
io = File.open(path, "w"); io.print(42);       io.close; p File.binread(path).bytes
io = File.open(path, "w"); io.puts("x\x00y\n");io.close; p File.binread(path).bytes

# the boxed receiver takes the same split
h = { 3 => File.open(path, "w"), 4 => "s" }
h[3].print(s); h[3].close; p File.binread(path).bytes
h = { 3 => File.open(path, "w"), 4 => "s" }
h[3].puts(s);  h[3].close; p File.binread(path).bytes

File.unlink(path)
