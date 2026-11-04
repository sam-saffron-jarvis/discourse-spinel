# A Thread, Fiber or lambda body is its own C function, but the ensure
# region stack of the enclosing body stayed in force while it was emitted:
# an ensure inside such a body chained its deferred return / next /
# exception to the enclosing region's label and flags, which live in the
# other function, and the C did not compile (#4547, ryudoawaru). The body
# now starts at ensure depth 0. Beside it: a lambda body with a typed
# result and an ensure returned its sp_RbVal from the sp_int proc function.
Thread.report_on_exception = false
Thread.new do
  Thread.new do
    1
  ensure
    nil
  end.join
ensure
  nil
end.join
puts 'ok'
log = Thread::Queue.new
outer = Thread.new do
  inner = Thread.new do
    log << 'inner body'
    :inner_value
  ensure
    log << 'inner ensure'
  end
  log << "inner returned #{inner.value}"
  :outer_value
ensure
  log << 'outer ensure'
end
puts "outer returned #{outer.value}"
entries = []
entries << log.pop until log.empty?
p entries
f = Fiber.new do
  g = Fiber.new do
    :g
  ensure
    puts "g ensure"
  end
  r = g.resume
  puts "f got #{r}"
  :f
ensure
  puts "f ensure"
end
p f.resume
l = lambda do
  t = Thread.new do
    raise "boom"
  ensure
    puts "t ensure"
  end
  begin
    t.join
  rescue => e
    puts "caught #{e.message}"
  end
  :l
ensure
  puts "l ensure"
end
p l.call
