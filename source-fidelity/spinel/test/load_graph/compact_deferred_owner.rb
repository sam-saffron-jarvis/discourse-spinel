# A cached require used as a value makes the owner feature deferred in the
# load record. Metadata discovery may see the child first, but it still
# belongs to the literal owner; uncertain presence is not uncertain identity.
if ARGV.length > 10
  require_relative "compact_deferred_value_lib"
end
require_relative "compact_deferred_owner_lib"
p DeferredLiteralOwner::Value.answer
p DeferredLiteralOwner::Value.name
begin
  OtherLiteralOwner::Value
rescue NameError
  puts "wrong owner rejected"
end
p require_relative("compact_deferred_owner_lib")
