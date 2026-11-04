# `str[start, len] = rhs` builds its result from pieces -- a head slice, the
# replacement, a tail slice -- and each of those allocates. Written as one
# nested expression the piece C evaluates first sat in an unrooted temporary
# while the next one allocated, so a collection landing in that window freed it
# and the splice read it back: the result took its length from recycled memory,
# or faulted outright where the allocator had returned the span to the OS.
#
# One splice never showed it; it needs enough of them for a collection to fall
# in the window. Before the fix this buffer lost 704 bytes partway through the
# loop and the next splice raised IndexError, and under SPINEL_GC_STRESS=1 it
# went wrong within twenty iterations. The invariants are simply that a splice
# of equal length leaves the length alone and writes what it was given.

# Force the collector to run on nearly every allocation, so the window is
# exercised wherever this runs rather than only where the allocator happens to
# put a collection inside it. Read once at the first allocation, which is why
# setting it here works. Without it this still failed before the fix on a
# default macOS build -- at iteration 426 rather than 16 -- but that depended on
# the allocator, and the point of the test is not to depend on it.
ENV["SPINEL_GC_STRESS"] = "1"

N = 4096
CHUNK = 64

buf = Array.new(N, 65).pack("C*")      # all "A"
rhs = Array.new(CHUNK, 66).pack("C*")  # all "B"

i = 0
bad_len = -1
while i < 2000
  buf[(i % 32) * CHUNK, CHUNK] = rhs
  if buf.length != N
    bad_len = buf.length
    break
  end
  i += 1
end

puts "completed: #{i}"
puts "length held: #{bad_len == -1}"
puts "first #{CHUNK * 32} bytes are the replacement: #{buf.byteslice(0, CHUNK * 32) == Array.new(CHUNK * 32, 66).pack('C*')}"
puts "tail untouched: #{buf.byteslice(CHUNK * 32, N - CHUNK * 32) == Array.new(N - CHUNK * 32, 65).pack('C*')}"
