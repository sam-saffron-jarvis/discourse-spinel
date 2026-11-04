# An ffi_func declared blocking: true under a heavy allocation load: collections
# start while workers are out in the call, and the values they hold across it
# must survive. Run under GC stress by the thread-puts-test sibling target.
module C
  ffi_lib "c"
  ffi_func :usleep, [:uint32], :int, blocking: true
end
# blocking calls under a heavy allocation load: collections start while
# workers are out, and the values they hold across the call must survive
sleepers = (0...6).map do |i|
  Thread.new(i) do |w|
    keep = []
    400.times do |k|
      s = "w#{w}-#{k}" * 3
      a = [k, s, k * 2.5]
      C.usleep(50)
      keep << a if k % 40 == 0
      raise "lost #{w}/#{k}: #{a.inspect}" unless a[1] == s && a[0] == k
    end
    keep.map { |x| x[1] }.join(",").length
  end
end
churn = (0...6).map do |i|
  Thread.new(i) do |w|
    n = 0
    2000.times { |k| n += ("c" * (k % 50 + 1)).length; [k, k.to_s, [k]].hash }
    n
  end
end
p sleepers.map(&:value)
p churn.map(&:value)
