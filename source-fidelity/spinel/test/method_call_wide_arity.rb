# A Method called through a container publishes its arguments into the proc
# convention's boxed side channel, and the channel's slot count is the ceiling
# on how many it can carry. That count lived as a bare 16 in nine places --
# the channel itself, the GC scan that keeps its values alive, the gates in
# the runtime and in three emitters -- and a 17-argument call was refused with
# "undefined method 'call' for an instance of Method". One name (SP_PROC_ARG_SLOTS)
# carries it now, so the scan and the gates cannot drift apart, and it is 64.
class C
  def initialize = @e = { "f1" => method(:f1), "f8" => method(:f8), "f16" => method(:f16), "f17" => method(:f17), "f20" => method(:f20), "f40" => method(:f40), "f64" => method(:f64) }
  def invoke(name, *args) = @e.fetch(name).call(*args)
  def f1(a0) = [a0, a0, a0 + a0]
  def f8(a0, a1, a2, a3, a4, a5, a6, a7) = [a0, a7, a0 + a7]
  def f16(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) = [a0, a15, a0 + a15]
  def f17(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16) = [a0, a16, a0 + a16]
  def f20(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19) = [a0, a19, a0 + a19]
  def f40(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31, a32, a33, a34, a35, a36, a37, a38, a39) = [a0, a39, a0 + a39]
  def f64(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31, a32, a33, a34, a35, a36, a37, a38, a39, a40, a41, a42, a43, a44, a45, a46, a47, a48, a49, a50, a51, a52, a53, a54, a55, a56, a57, a58, a59, a60, a61, a62, a63) = [a0, a63, a0 + a63]
end
c = C.new
p c.invoke("f1", 0)
p c.invoke("f8", 0, 1, 2, 3, 4, 5, 6, 7)
p c.invoke("f16", 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
p c.invoke("f17", 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
p c.invoke("f20", 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19)
p c.invoke("f40", 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39)
p c.invoke("f64", 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63)

# a rest parameter takes the surplus through the same channel
class R
  def initialize = @e = { "r" => method(:r) }
  def invoke(name, *args) = @e.fetch(name).call(*args)
  def r(a, *rest) = [a, rest.length, rest.last]
end
r = R.new
p r.invoke("r", 1, 2, 3)
p r.invoke("r", *(0..40).to_a)
