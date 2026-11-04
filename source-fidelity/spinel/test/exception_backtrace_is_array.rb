# A rescued exception's #backtrace is an ARRAY, never nil, so the chained forms
# work without a nil check. A release build has no frame symbols, so it is the
# empty one; `make backtrace-test` covers the debug build, where the frames of
# the raise that landed are in it (#4310).
begin
  raise TypeError, "boom"
rescue => e
  bt = e.backtrace
  p bt.is_a?(Array)
  p bt.empty? || bt.first.is_a?(String)
  p bt.length >= 0
end

class Custom < StandardError; end

begin
  raise Custom, "mine"
rescue Custom => e
  p e.backtrace.is_a?(Array)
end

# set_backtrace still wins over the backfill
begin
  begin
    raise "inner"
  rescue => e
    e.set_backtrace(["a.rb:1", "b.rb:2"])
    raise e
  end
rescue => e2
  p e2.backtrace
end
