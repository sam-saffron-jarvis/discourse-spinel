# spinel: int64 -- assumes a 64-bit Integer (values or arithmetic past 2^31); not run on a 32-bit target
# A live set far larger than the mark stack's initial size: the walk has to
# stay iterative rather than recursing per object.
heap = []
200_000.times { |i| heap << [i, i * 2] }
GC.start
p heap.size
p heap[0]
p heap[199_999]
p heap.sum { |pair| pair[1] } == 200_000 * 199_999
