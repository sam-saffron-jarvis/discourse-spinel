# Shared source-only caller. No DB, future/query result, or fake tracker input.
tracker = ActiveRecord::AsynchronousQueriesTracker.run
outer = tracker.current_session
raise "outer session inactive" unless outer.active?
ActiveRecord::AsynchronousQueriesTracker.run
inner = tracker.current_session
raise "nested session reused outer" if inner.equal?(outer)
ActiveRecord::AsynchronousQueriesTracker.complete(tracker)
raise "child finalized enclosing session" unless outer.active? && !inner.active?
raise "enclosing session not restored" unless tracker.current_session.equal?(outer)
ActiveRecord::AsynchronousQueriesTracker.complete(tracker)
raise "outer session not finalized" if outer.active?
begin
  tracker.current_session
  raise "missing session silently accepted"
rescue ActiveRecord::ActiveRecordError => error
  puts error.message
end
tracker.finalize_session
session = ActiveRecord::AsynchronousQueriesTracker::Session.new
entered = Queue.new
release = Queue.new
reader = Thread.new do
  session.synchronize do
    entered << true
    release.pop
  end
end
entered.pop
finished = Queue.new
finalizer = Thread.new do
  session.finalize(true)
  finished << true
end
attempt = 0
while session.active? && attempt < 1000
  sleep 0.001
  attempt += 1
end
raise "finalize did not mark session inactive" if session.active?
raise "wait finalizer did not wait for actual reader" unless finished.empty?
release << true
reader.join
finalizer.join
raise "finalizer did not complete" unless finished.pop
# Exception release must not leave a reader lock behind.
begin
  session.synchronize { raise "reader exception" }
rescue RuntimeError
end
session.finalize(true)
# A completed session stays inactive even when a reader subsequently locks it.
raise "completed session reactivated" if session.synchronize { session.active? }
thread = Thread.new do
  other = ActiveRecord::AsynchronousQueriesTracker.run
  raise "tracker shared across threads" if other.equal?(tracker)
  ActiveRecord::AsynchronousQueriesTracker.complete(other)
end
thread.join
puts "nested-sessions,missing-session,real-reader-wait,exception-unlock,thread-isolation:pass"
