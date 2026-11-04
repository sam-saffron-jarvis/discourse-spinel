# `iso8601(n)` / `xmlschema(n)` on a receiver typed `Time | nil`: the typed
# emitter serves the fraction-digits form, the boxed-receiver table served
# only the bare one, so a Time read out of a nilable slot answered
# NoMethodError -- campfire's `message.created_at.utc.iso8601(3)` over a
# nullable column is the caller.
def stamp(ok)
  ok ? Time.utc(2026, 9, 12, 12, 41, 18, 170926) : nil
end

x = stamp(true)
puts x.iso8601
puts x.iso8601(3)
puts x.xmlschema(6)
puts x.utc.iso8601(3)
puts x.getlocal("+02:00").iso8601(1)
begin
  stamp(false).iso8601(3)
rescue NoMethodError => e
  puts e.message
end
