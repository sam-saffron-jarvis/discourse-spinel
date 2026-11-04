# The per-class free-list pool is pushed onto by the sweep -- and in the
# threaded build the sweep is parallel: every parked worker sweeps its own
# slot, so several workers recycle onto ONE list at once. Eight workers hold
# thousands of pooled instances across a collection and then drop them
# together, so each sweep pushes a long crop from every slot. Under
# scripts/tsan-run.sh this used to report ~100 data races in
# sp_Node_pool_recycle (a plain push); the recycle now pushes with the same
# CAS loop the PolyArray pool uses. Plain `make test` keeps the program
# honest (the total is deterministic); the TSan gate is where the race shows.
class Node
  def initialize(v)
    @v = v
  end

  def v
    @v
  end
end

total = 0
threads = []
8.times do |t|
  threads << Thread.new do
    s = 0
    40.times do
      keep = []
      5000.times { |i| keep << Node.new(i.to_s) }
      s += keep.length
      keep = []
      500.times { |i| s += Node.new(i.to_s).v.length }
    end
    s
  end
end
threads.each { |th| total += th.value }
puts "ok " + total.to_s
