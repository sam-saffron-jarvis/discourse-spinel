# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
# An IO::Buffer passed to an ffi_func pointer argument (:ptr, :pointer,
# :buffer_in / :buffer_out / :buffer_inout) hands C its base address for the
# call, as CRuby's rb_io_buffer_get_bytes_for_reading / _for_writing do: a
# slice's own offset, the size after a resize, NULL for a freed buffer,
# InvalidatedError for a slice whose source is gone, and AccessError for a
# read-only buffer anywhere but :buffer_in. Before, the IO::Buffer object
# itself was passed, and C wrote over its header.
module Pix
  ffi_source <<~C
    #include <stdint.h>
    #include <stddef.h>
    int64_t pix_sum_u8(const void *p, size_t n) {
      const uint8_t *b = p; int64_t s = 0;
      for (size_t i = 0; i < n; i++) s += b[i];
      return s;
    }
    int64_t pix_sum_u16(const void *p, size_t n) {
      const uint16_t *b = p; int64_t s = 0;
      for (size_t i = 0; i < n; i++) s += b[i];
      return s;
    }
    int64_t pix_sum_u32(const void *p, size_t n) {
      const uint32_t *b = p; int64_t s = 0;
      for (size_t i = 0; i < n; i++) s += b[i];
      return s;
    }
    void pix_fill_u32(void *p, size_t n, uint32_t v) {
      uint32_t *b = p;
      for (size_t i = 0; i < n; i++) b[i] = v + (uint32_t)i;
    }
    int pix_is_null(const void *p) { return p == NULL; }
    int pix_is_null_in(const void *p) { return p == NULL; }
    void pix_fill_u32_blocking(void *p, size_t n, uint32_t v) { pix_fill_u32(p, n, v); }
  C
  ffi_func :pix_sum_u8,  [:buffer_in, :size_t], :int64
  ffi_func :pix_sum_u16, [:pointer, :size_t], :int64
  ffi_func :pix_sum_u32, [:ptr, :size_t], :int64
  ffi_func :pix_fill_u32, [:buffer_out, :size_t, :uint32], :void
  ffi_func :pix_fill_u32_blocking, [:ptr, :size_t, :uint32], :void, blocking: true
  ffi_func :pix_is_null, [:ptr], :int
  ffi_func :pix_is_null_in, [:buffer_in], :int
end

module LibC
  ffi_func :memset, [:ptr, :int, :size_t], :ptr
  ffi_func :memcpy, [:buffer_inout, :buffer_in, :size_t], :ptr
  ffi_func :malloc, [:size_t], :ptr
  ffi_func :free, [:ptr], :void
  ffi_read_u8 :byte0, 0
  ffi_read_i32 :i32, 0
  ffi_callback :cmp, [:ptr, :ptr], :int
  ffi_func :qsort, [:ptr, :size_t, :size_t, :cmp], :void
  ffi_func :snprintf, [:ptr, :size_t, :str, :varargs], :int
end

def cmp(a, b)
  pad = "x" * 64
  LibC.i32(a) <=> LibC.i32(b)
end

# 8-bit: an audio-style byte buffer built in Ruby, read by C
audio = IO::Buffer.new(6)
audio.set_values([:U8] * 6, 0, [1, 2, 3, 250, 251, 252])
puts Pix.pix_sum_u8(audio, 6)

# 16-bit
w = IO::Buffer.new(8)
4.times { |i| w.set_value(:u16, i * 2, 60000 + i) }
puts Pix.pix_sum_u16(w, 4)

# 32-bit: C fills a framebuffer, Ruby reads the pixels back
fb = IO::Buffer.new(4 * 4)
Pix.pix_fill_u32(fb, 4, 0xff000000)
p (0...4).map { |i| fb.get_value(:u32, i * 4) }
puts Pix.pix_sum_u32(fb, 4)

# libc into and between buffers
LibC.memset(fb, 0x11, 8)
p fb.get_value(:u32, 0), fb.get_value(:u32, 4), fb.get_value(:u32, 8)
dst = IO::Buffer.new(6)
LibC.memcpy(dst, audio, 6)
p dst.get_string

# a slice starts at its own offset into the source
base = IO::Buffer.new(8)
base.clear(0)
s = base.slice(2, 4)
LibC.memset(s, 7, 4)
p base.get_string
inner = s.slice(1, 2)
LibC.memset(inner, 9, 2)
p base.get_string
puts Pix.pix_sum_u8(base.slice(4, 4), 4)

# a resize before the call: C sees the new allocation and size
r = IO::Buffer.new(4)
r.resize(4 * 64)
Pix.pix_fill_u32(r, 64, 1)
p r.get_value(:u32, 63 * 4)
# ...and one done by a later argument of the same call
r2 = IO::Buffer.new(4)
Pix.pix_fill_u32(r2, (r2.resize(4 * 32); 32), 100)
p r2.size, r2.get_value(:u32, 31 * 4)

# a mapped file, read in place
File.open(__FILE__) do |io|
  m = IO::Buffer.map(io, 64, 0, IO::Buffer::READONLY)
  puts Pix.pix_sum_u8(m, 64) == File.binread(__FILE__, 64).bytes.sum
end

# an inline buffer expression, and the read-only IO::Buffer.for in :buffer_in
puts Pix.pix_sum_u8(IO::Buffer.for("\x01\x02\x03"), 3)
ro = IO::Buffer.for("abc")
puts Pix.pix_sum_u8(ro, 3)
begin
  Pix.pix_sum_u32(ro, 0)
rescue IO::Buffer::AccessError => e
  puts "#{e.class}: #{e.message}"
end
begin
  Pix.pix_fill_u32(ro.slice(0, 3), 0, 0)
rescue IO::Buffer::AccessError => e
  puts "#{e.class}: #{e.message}"
end

# a freed or zero-size buffer is NULL, as in CRuby's C API
f = IO::Buffer.new(8)
f.free
puts Pix.pix_is_null(f)
puts Pix.pix_is_null_in(f)
puts Pix.pix_is_null(IO::Buffer.new(0))
puts Pix.pix_is_null(IO::Buffer.new(1))

# a slice whose source was freed or shrunk under it
src = IO::Buffer.new(16)
view = src.slice(8, 8)
src.resize(4)
begin
  Pix.pix_sum_u8(view, 8)
rescue IO::Buffer::InvalidatedError => e
  puts "#{e.class}: #{e.message}"
end
src.free
begin
  LibC.memset(view, 0, 8)
rescue IO::Buffer::InvalidatedError => e
  puts "#{e.class}: #{e.message}"
end

# a buffer held in a mixed array arrives boxed, as does a C pointer and nil
mixed = [fb, 1, "x"]
LibC.memset(mixed[0], 0x22, 4)
p fb.get_value(:u32, 0)
raw = LibC.malloc(4)
held = [raw, 2]
LibC.memset(held[0], 5, 4)
p LibC.byte0(raw)
LibC.free(raw)
puts Pix.pix_is_null(nil)
none = nil
none = IO::Buffer.new(4) if ARGV.size > 5
puts Pix.pix_is_null(none)

# a callback-taking function, which runs Ruby during the call, and a variadic one
nums = IO::Buffer.new(4 * 5)
[5, -3, 9, 0, 2].each_with_index { |v, i| nums.set_value(:s32, i * 4, v) }
LibC.qsort(nums, 5, 4, method(:cmp))
p (0...5).map { |i| nums.get_value(:s32, i * 4) }
text = IO::Buffer.new(32)
n = LibC.snprintf(text, 32, "%d-%s", 42, "ok")
p text.get_string(0, n)

# through a method parameter and an instance variable
def clear(b) = LibC.memset(b, 3, b.size)
clear(text)
p text.get_value(:U8, 31)
class Screen
  def initialize = @fb = IO::Buffer.new(8)
  def clear = LibC.memset(@fb, 1, 8)
  def fb = @fb
end
scr = Screen.new
scr.clear
p scr.fb.get_value(:u64, 0)

# blocking calls from several threads while others allocate
workers = (0...4).map do |t|
  Thread.new(t) do |k|
    ok = 0
    50.times do |i|
      b = IO::Buffer.new(4 * 256)
      junk = (0...20).map { |j| "#{k}-#{i}-#{j}" }
      Pix.pix_fill_u32_blocking(b, 256, k * 1000 + i)
      ok += 1 if b.get_value(:u32, 255 * 4) == k * 1000 + i + 255 && junk.size == 20
    end
    ok
  end
end
p workers.map(&:value)
