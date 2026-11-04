# File::NULL is the null device, and the name Process.spawn / File.open take
# to discard a stream. It sat beside File::SEPARATOR and its siblings in the
# builtin-constant table but was missing from both halves of it: the emitter
# had no arm, so the reference warned at compile time and raised NameError,
# and inference had no arm either, which is what made a naive emitter-only
# addition read back as nil (the constant path takes the unknown-kind tail).

p File::NULL
p File::NULL.class
p File::NULL.length
p File::NULL + "x"
p File.exist?(File::NULL)

# it flows like any other string constant
h = { out: File::NULL }
p h[:out]
def null_path
  File::NULL
end
p null_path
p [File::NULL, File::SEPARATOR]

# and it is a real path
File.open(File::NULL, "w") { |f| f.write("discarded") }
p File.size(File::NULL)

# the reporter's use: a spawn redirect that discards both streams
pid = Process.spawn("echo", "SHOULD-NOT-APPEAR", out: File::NULL, err: File::NULL)
sleep 0.3
puts "redirected"
