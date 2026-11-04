# A proc called through an untyped slot passes its arguments and its result
# through the per-worker boxed channel (_sp_proc_poly_args / _sp_proc_poly_ret).
# The last value a worker returned that way stays in its slot until the next
# boxed call, and the collector treats the slot as a root -- but only its OWN
# worker's copy. Here one worker makes a single boxed call whose result nothing
# else names, then idles while six others allocate through many collections;
# when it allocates again, its own collection marks the slot. Unpublished, the
# object was freed by the other workers' collections and the mark reaches a
# freed pointer (SPINEL_GC_VERIFY=1 aborts naming it; unverified, whatever
# reused the block faults in its scan hook). The result is an Array, an object
# the verifier can check against its registry; a String would be marked through
# the string marker, which does not consult it. With the slots published at the
# barrier like the match registers and proc-return homes, the object survives
# on eight workers as it always did on one.
def make
  proc { |x| [x, "value-" + (x.to_s * 8)] }
end

h = {}
h[:k] = make

quiet = Thread.new do
  h[:k].call(1)
  sleep 0.5
  keep = []
  20000.times { |i| keep << ("z" + i.to_s) }
  keep.length
end

churn = []
6.times do
  churn << Thread.new do
    s = 0
    200000.times { |i| s += ("w" + i.to_s).length }
    s
  end
end
churn.each { |t| t.value }
puts "ok " + quiet.value.to_s
