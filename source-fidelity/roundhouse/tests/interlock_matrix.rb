lock = ActiveSupport::Dependencies::Interlock.new
lock.start_running
lock.start_running
raise "reader is not reentrant" unless lock.running_depth == 2
writer_started = Queue.new
writer_entered = Queue.new
writer_release = Queue.new
writer = Thread.new do
  writer_started << true
  lock.start_unloading
  lock.start_unloading
  writer_entered << true
  writer_release.pop
  lock.done_unloading
  lock.done_unloading
end
writer_started.pop
sleep 0.02
raise "unloader entered active reader" unless writer_entered.empty?
lock.done_running
sleep 0.02
raise "one release lost enclosing reader" unless lock.running_depth == 1 && writer_entered.empty?
lock.done_running
writer_entered.pop
reader_started = Queue.new
reader_entered = Queue.new
reader = Thread.new do
  reader_started << true
  lock.start_running
  reader_entered << true
  lock.done_running
end
reader_started.pop
sleep 0.02
raise "reader entered exclusive unloader" unless reader_entered.empty?
writer_release << true
writer.join
reader.join
reader_entered.pop
raise "request reader leaked" unless lock.running_depth == 0
begin
  lock.done_unloading
  raise "foreign unlock accepted"
rescue RuntimeError => error
  raise unless error.message == "invalid unlock"
end
puts "reentrant-reader,actual-unloader-wait,enclosing-ownership,actual-reader-wait,reentrant-writer,invalid-unlock:pass"
